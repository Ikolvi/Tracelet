package com.ikolvi.tracelet.sdk.sync

import com.ikolvi.tracelet.sdk.TraceletSdk
import com.ikolvi.tracelet.sdk.location.LocationDataSink
import uniffi.tracelet_sync.SyncManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

class NativeSyncProvider(private val sdk: TraceletSdk) : LocationDataSink, TraceletSdk.SyncProvider {
    // SupervisorJob: a single failed/throwing sync must NOT cancel the scope —
    // otherwise the FIRST background sync that hits an uncaught error would kill
    // every future sync (the "syncs once then never again" bug, Issue #134).
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val syncMutex = Mutex()
    private val syncManager = SyncManager()

    private var syncJob: kotlinx.coroutines.Job? = null
    private val DEBOUNCE_MS = 10_000L

    @Volatile
    private var lastSyncBodySource: String? = null

    /**
     * Records which body the sync is posting — but only when the answer
     * changes (#340).
     *
     * The per-sync lines around the call sites are `debug`, so on a release
     * build at the shipped log levels they are dropped and a device posting the
     * default payload when the app registered a custom builder leaves no trace
     * of it. The lifecycle channel is never level-gated, which is exactly what
     * a release build needs.
     *
     * It cannot simply be written per sync, though: syncs fire every few
     * seconds while tracking, and [TraceletLogger.lifecycle] is explicitly
     * reserved for events that fire a handful of times per session because its
     * rows share a bounded cap with the killed-state trail. One entry per sync
     * would evict the trail it exists to preserve.
     *
     * Reporting only transitions costs a handful of rows per session and still
     * answers the whole question: which body is this app sending, and did that
     * ever change mid-session?
     */
    private fun reportSyncBodySource(source: String, detail: String) {
        val changed = synchronized(this) {
            if (lastSyncBodySource == source) {
                false
            } else {
                lastSyncBodySource = source
                true
            }
        }
        if (changed) sdk.logger.lifecycle("sync-body: $detail")
    }

    override fun insertLocation(location: Map<String, Any?>) {
        val delayMs = sdk.rustEngineState?.getConfig()?.http?.autoSyncDelay?.toLong() ?: 10_000L
        if (syncJob?.isActive == true) return
        syncJob = scope.launch {
            // Contain ANY throwable from a single sync iteration so it can never
            // propagate out of the coroutine and tear down auto-sync. Real
            // cancellation (stop() → cancelPendingSync) is re-thrown so it still
            // works. (Issue #134: keep background auto-sync firing every cycle.)
            try {
                kotlinx.coroutines.delay(delayMs)
                triggerSync()
            } catch (ce: kotlinx.coroutines.CancellationException) {
                throw ce
            } catch (t: Throwable) {
                sdk.logger.error("NativeSyncProvider: auto-sync iteration failed (contained): ${t.message}")
            }
        }
    }

    /**
     * Cancels a pending (debounced) or in-flight auto-sync so no further POSTs
     * fire after tracking is stopped. Called from [TraceletSdk.stop]. A
     * subsequent location insert (after a new start) schedules a fresh sync, so
     * this does not need to be reset.
     */
    override fun cancelPendingSync() {
        syncJob?.cancel()
        syncJob = null
    }

    private suspend fun triggerSync() {
        syncMutex.withLock {
            sdk.logger.debug("NativeSyncProvider: triggerSync started")
            val db = sdk.rustDatabase ?: run {
                sdk.logger.error("NativeSyncProvider: rustDatabase is null")
                return
            }
            val state = sdk.rustEngineState ?: run {
                sdk.logger.error("NativeSyncProvider: rustEngineState is null")
                return
            }

            try {
                // 1. Request Fresh Headers
                val interceptor = sdk.dartSyncInterceptor
                if (interceptor?.requestFreshHeaders() == true) {
                    sdk.logger.debug("NativeSyncProvider: Headers refreshed via Dart interceptor")
                }

                val coreHttp = state.getConfig().http
                sdk.logger.debug("NativeSyncProvider: coreHttp config: url=${coreHttp.url}, autoSync=${coreHttp.autoSync}")
                if (coreHttp.url.isNullOrEmpty() || !coreHttp.autoSync) return

                val limit = if (coreHttp.maxBatchSize > 0) coreHttp.maxBatchSize else 250
                val records = db.getLocationsBatch(uniffi.tracelet_core.LocationQuery(
                    startTimeMs = null,
                    endTimeMs = null,
                    limit = limit.toInt(),
                    offset = null,
                    // Honor the configured sort order (0=ascending, 1=descending)
                    // instead of always defaulting to ascending (Issue #138).
                    orderDescending = coreHttp.locationsOrderDirection == 1
                ))
                sdk.logger.debug("NativeSyncProvider: Found ${records.size} locations in DB")
                if (records.isEmpty()) return

                // Prepare maps for Dart interceptor (Issue #126: nested schema
                // matching onLocation/getLocations, not a flat map).
                val recordsMap = records.map { sdk.mapRecordToLocation(it) }

                val customBody = interceptor?.requestSyncBody(recordsMap)
                if (interceptor != null && customBody == null) {
                    // A builder is registered but it timed out or threw
                    // (requestSyncBody returns the sentinel, not null, when no
                    // builder exists). Abort instead of posting an error object
                    // or the default payload.
                    sdk.logger.error("NativeSyncProvider: custom sync body failed to build; aborting sync")
                    sdk.getEventSender().sendHttp(mapOf(
                        "success" to false,
                        "status" to 0,
                        "responseText" to "custom sync body failed to build",
                        "isRetry" to false,
                        "retryCount" to 0
                    ))
                    return
                }

                if (customBody == null || customBody == NO_SYNC_BODY_BUILDER_SENTINEL) {
                    reportSyncBodySource(
                        if (interceptor == null) "no-interceptor" else "no-builder",
                        if (interceptor == null) {
                            "posting the DEFAULT payload — no dartSyncInterceptor attached to the SDK"
                        } else {
                            "posting the DEFAULT payload — no custom sync body builder reached " +
                                "native (setSyncBodyBuilder registered in Dart?)"
                        },
                    )
                }

                if (customBody != null && customBody != NO_SYNC_BODY_BUILDER_SENTINEL) {
                    reportSyncBodySource("custom", "posting the app's custom sync body")
                    val result = executeFallbackHttpSync(coreHttp, customBody, interceptor)
                    if (result.success) {
                        records.lastOrNull()?.id?.let { lastId ->
                            db.clearLocationsUpTo(lastId)
                            sdk.logger.info("NativeSyncProvider: Synced and cleared ${records.size} locations via custom body fallback.")
                        }
                        sdk.getEventSender().sendHttp(mapOf(
                            "success" to true,
                            "status" to result.status,
                            "responseText" to result.responseText,
                            "isRetry" to false,
                            "retryCount" to 0
                        ))
                    } else {
                        sdk.logger.error("NativeSyncProvider: Custom body sync failed with status ${result.status}")
                        sdk.getEventSender().sendHttp(mapOf(
                            "success" to false,
                            "status" to result.status,
                            "responseText" to result.responseText,
                            "isRetry" to false,
                            "retryCount" to 0
                        ))
                    }
                    return
                }

                val syncConfig = uniffi.tracelet_sync.SyncHttpConfig(
                    url = coreHttp.url,
                    method = coreHttp.method,
                    headers = coreHttp.headers,
                    batchSync = coreHttp.batchSync,
                    maxBatchSize = coreHttp.maxBatchSize,
                    autoSync = coreHttp.autoSync,
                    maxRetries = coreHttp.maxRetries,
                    retryBackoffBase = coreHttp.retryBackoffBase,
                    retryBackoffCap = coreHttp.retryBackoffCap,
                    sslPinningCertificates = coreHttp.sslPinningCertificates,
                    sslPinningFingerprints = coreHttp.sslPinningFingerprints,
                    httpRootProperty = coreHttp.httpRootProperty,
                    params = coreHttp.params,
                    extras = coreHttp.extras,
                    disableAutoSyncOnCellular = coreHttp.disableAutoSyncOnCellular,
                    enableDeltaCompression = coreHttp.enableDeltaCompression,
                    deltaCoordinatePrecision = coreHttp.deltaCoordinatePrecision,
                    locationsOrderDirection = coreHttp.locationsOrderDirection
                )

                val syncRecords = records.map {
                    uniffi.tracelet_sync.SyncLocationRecord(
                        id = it.id,
                        uuid = it.uuid,
                        timestamp = it.timestamp,
                        latitude = it.latitude,
                        longitude = it.longitude,
                        accuracy = it.accuracy,
                        speed = it.speed,
                        heading = it.heading,
                        altitude = it.altitude,
                        isMock = it.isMock,
                        isMoving = it.isMoving,
                        activity = it.activity,
                        event = it.eventType,
                        routeContext = it.routeContext,
                        address = it.address  // #212
                    )
                }

                val count = syncManager.syncBatchBlocking(syncConfig, syncRecords)
                if (count > 0U) {
                    records.lastOrNull()?.id?.let { lastId ->
                        db.clearLocationsUpTo(lastId)
                        sdk.logger.info("NativeSyncProvider: Synced and cleared $count locations.")
                    }
                    sdk.getEventSender().sendHttp(mapOf(
                        "success" to true,
                        "status" to 200,
                        "responseText" to "Synced $count locations",
                        "isRetry" to false,
                        "retryCount" to 0
                    ))
                } else {
                    sdk.getEventSender().sendHttp(mapOf(
                        "success" to false,
                        "status" to 0,
                        "responseText" to "Sync failed",
                        "isRetry" to false,
                        "retryCount" to 0
                    ))
                }
            } catch (e: Exception) {
                sdk.logger.error("NativeSyncProvider: Sync failed: ${e.message}")
                sdk.getEventSender().sendHttp(mapOf(
                    "success" to false,
                    "status" to 0,
                    "responseText" to (e.message ?: "Unknown error"),
                    "isRetry" to false,
                    "retryCount" to 0
                ))
            }
        }
    }

    override fun syncBatchBlocking(config: uniffi.tracelet_core.HttpConfig, records: List<uniffi.tracelet_core.DbLocationRecord>): Long {
        val syncConfig = uniffi.tracelet_sync.SyncHttpConfig(
            url = config.url,
            method = config.method,
            headers = config.headers,
            batchSync = config.batchSync,
            maxBatchSize = config.maxBatchSize,
            autoSync = config.autoSync,
            maxRetries = config.maxRetries,
            retryBackoffBase = config.retryBackoffBase,
            retryBackoffCap = config.retryBackoffCap,
            sslPinningCertificates = config.sslPinningCertificates,
            sslPinningFingerprints = config.sslPinningFingerprints,
            httpRootProperty = config.httpRootProperty,
            params = config.params,
            extras = config.extras,
            disableAutoSyncOnCellular = config.disableAutoSyncOnCellular,
            enableDeltaCompression = config.enableDeltaCompression,
            deltaCoordinatePrecision = config.deltaCoordinatePrecision,
            locationsOrderDirection = config.locationsOrderDirection
        )
        val syncRecords = records.map {
            uniffi.tracelet_sync.SyncLocationRecord(
                id = it.id,
                uuid = it.uuid,
                timestamp = it.timestamp,
                latitude = it.latitude,
                longitude = it.longitude,
                accuracy = it.accuracy,
                speed = it.speed,
                heading = it.heading,
                altitude = it.altitude,
                isMock = it.isMock,
                isMoving = it.isMoving,
                activity = it.activity,
                event = it.eventType,
                routeContext = it.routeContext,
                address = it.address  // #212
            )
        }

        val interceptor = sdk.dartSyncInterceptor
        sdk.logger.debug("NativeSyncProvider: Interceptor is $interceptor")
        if (interceptor == null) {
            // #340: this entry point reported nothing at all. `triggerSync` — the
            // debounced auto-sync — was instrumented and this one was not, so a
            // manual sync() and every killed-state sync that lands here left no
            // trace of which body it posted. iOS reports from inside its own
            // syncBatchBlocking, so the two platforms disagreed about what a
            // bug report would contain.
            reportSyncBodySource(
                "no-interceptor",
                "posting the DEFAULT payload — no dartSyncInterceptor attached to the SDK",
            )
        }
        if (interceptor != null) {
            // Issue #126: nested schema matching onLocation/getLocations.
            val recordMaps = records.map { sdk.mapRecordToLocation(it) }
            val customBody = interceptor.requestSyncBody(recordMaps)
            sdk.logger.debug("NativeSyncProvider: Custom body is $customBody")
            if (customBody == NO_SYNC_BODY_BUILDER_SENTINEL) {
                reportSyncBodySource(
                    "no-builder",
                    "posting the DEFAULT payload — no custom sync body builder reached " +
                        "native (setSyncBodyBuilder registered in Dart?)",
                )
            }
            if (customBody == null) {
                // Builder registered but failed → abort (0 = nothing synced).
                sdk.logger.error("NativeSyncProvider: custom sync body failed to build; aborting sync")
                sdk.getEventSender().sendHttp(mapOf(
                    "success" to false,
                    "status" to 0,
                    "responseText" to "custom sync body failed to build",
                    "isRetry" to false,
                    "retryCount" to 0
                ))
                return 0L
            }
            if (customBody != NO_SYNC_BODY_BUILDER_SENTINEL) {
                reportSyncBodySource("custom", "posting the app's custom sync body")
                return kotlinx.coroutines.runBlocking {
                    val result = executeFallbackHttpSync(config, customBody, interceptor)
                    sdk.logger.debug("NativeSyncProvider: Fallback HTTP result: ${result.success}, status: ${result.status}")
                    if (result.success) {
                        sdk.getEventSender().sendHttp(mapOf(
                            "success" to true,
                            "status" to result.status,
                            "responseText" to result.responseText,
                            "isRetry" to false,
                            "retryCount" to 0
                        ))
                        records.size.toLong()
                    } else {
                        sdk.getEventSender().sendHttp(mapOf(
                            "success" to false,
                            "status" to result.status,
                            "responseText" to result.responseText,
                            "isRetry" to false,
                            "retryCount" to 0
                        ))
                        0L
                    }
                }
            }
            // sentinel → no builder → fall through to the default sync below.
        }

        try {
            val count = syncManager.syncBatchBlocking(syncConfig, syncRecords).toLong()
            if (count > 0L) {
                sdk.getEventSender().sendHttp(mapOf(
                    "success" to true,
                    "status" to 200,
                    "responseText" to "Synced $count locations",
                    "isRetry" to false,
                    "retryCount" to 0
                ))
            } else {
                sdk.getEventSender().sendHttp(mapOf(
                    "success" to false,
                    "status" to 0,
                    "responseText" to "Sync failed",
                    "isRetry" to false,
                    "retryCount" to 0
                ))
            }
            return count
        } catch (e: Exception) {
            sdk.logger.error("NativeSyncProvider: Sync failed: ${e.message}")
            sdk.getEventSender().sendHttp(mapOf(
                "success" to false,
                "status" to 0,
                "responseText" to (e.message ?: "Unknown error"),
                "isRetry" to false,
                "retryCount" to 0
            ))
            throw e
        }
    }

    data class FallbackSyncResult(val success: Boolean, val status: Int, val responseText: String)

    private suspend fun executeFallbackHttpSync(
        coreHttp: uniffi.tracelet_core.HttpConfig,
        customBody: String,
        interceptor: DartSyncInterceptor?
    ): FallbackSyncResult {
        var currentHeaders = coreHttp.headers
        val maxRetries = coreHttp.maxRetries.toInt()
        
        var lastStatus = 0
        var lastResponse = "Unknown error"

        for (attempt in 0..maxRetries) {
            try {
                val url = URL(coreHttp.url)
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = if (coreHttp.method.toInt() == 1) "PUT" else "POST"
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/json")
                conn.connectTimeout = 15000
                conn.readTimeout = 15000

                if (currentHeaders.isNotEmpty()) {
                    try {
                        currentHeaders.forEach { (key, value) ->
                            conn.setRequestProperty(key, value)
                        }
                    } catch (e: Exception) {
                        android.util.Log.e("NativeSyncProvider", "Failed to set HTTP headers: ${e.message}", e)
                    }
                }

                conn.outputStream.use { os ->
                    val input = customBody.toByteArray(Charsets.UTF_8)
                    os.write(input, 0, input.size)
                }

                val status = conn.responseCode
                lastStatus = status
                
                val responseStream = if (status in 200..299) conn.inputStream else conn.errorStream
                val responseText = responseStream?.bufferedReader()?.use { it.readText() } ?: ""
                lastResponse = responseText

                conn.disconnect()
                
                if (status in 200..299) {
                    return FallbackSyncResult(true, status, responseText)
                } else if (status == 401 && interceptor != null) {
                    if (interceptor.requestTokenRefresh()) {
                        val newConfig = sdk.rustEngineState?.getConfig()?.http
                        if (newConfig != null) {
                            currentHeaders = newConfig.headers
                        }
                        continue 
                    } else {
                        return FallbackSyncResult(false, status, responseText)
                    }
                } else if (status in 400..499 && status != 408 && status != 429) {
                    // Client error, no point in retrying (except timeout/rate limits)
                    return FallbackSyncResult(false, status, responseText)
                }
                
                if (attempt < maxRetries) {
                    kotlinx.coroutines.delay(1000L * (attempt + 1))
                }
            } catch (e: Exception) {
                sdk.logger.error("HTTP Sync failed: ${e.message}")
                sdk.logger.error("NativeSyncProvider: executeFallbackHttpSync Exception: ${e.message}")
                lastResponse = e.message ?: "Unknown exception"
                lastStatus = 0
                if (attempt < maxRetries) {
                    kotlinx.coroutines.delay(1000L * (attempt + 1))
                }
            }
        }
        return FallbackSyncResult(false, lastStatus, lastResponse)
    }
}
