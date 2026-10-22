package com.ikolvi.tracelet.sdk.sync

import com.ikolvi.tracelet.sdk.TraceletSdk
import com.ikolvi.tracelet.sdk.location.LocationDataSink
import uniffi.tracelet_sync.SyncManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
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

    // #437: drains batch after batch and never drops a request made while a
    // sync is in flight — see AutoSyncDrainer.
    private val drainer = AutoSyncDrainer(scope, syncMutex, ::uploadOneBatch) { msg ->
        sdk.logger.error("NativeSyncProvider: $msg")
    }

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
        val http = sdk.rustEngineState?.getConfig()?.http
        // #437: autoSyncThreshold was stored and passed to Rust but never read.
        val threshold = http?.autoSyncThreshold ?: 0
        if (threshold > 0) {
            val pending = try { sdk.rustDatabase?.getLocationsCount() } catch (_: Exception) { null }
            if (pending != null && pending < threshold) return
        }
        drainer.request(http?.autoSyncDelay?.toLong() ?: 10_000L)
    }

    override fun <T> runExclusive(block: () -> T): T =
        kotlinx.coroutines.runBlocking { syncMutex.withLock { block() } }

    override fun requestDrain() = drainer.request(0)

    /**
     * Cancels a pending (debounced) or in-flight auto-sync so no further POSTs
     * fire after tracking is stopped. Called from [TraceletSdk.stop]. A
     * subsequent location insert (after a new start) schedules a fresh sync, so
     * this does not need to be reset.
     */
    override fun cancelPendingSync() {
        drainer.cancel()
    }

    /**
     * Uploads the oldest batch and clears it. Returns the rows cleared, or 0
     * when the queue is empty or the upload failed. Called under [syncMutex]
     * by the drainer.
     */
    private suspend fun uploadOneBatch(): Int {
        run {
            sdk.logger.debug("NativeSyncProvider: triggerSync started")
            val db = sdk.rustDatabase ?: run {
                sdk.logger.error("NativeSyncProvider: rustDatabase is null")
                return 0
            }
            val state = sdk.rustEngineState ?: run {
                sdk.logger.error("NativeSyncProvider: rustEngineState is null")
                return 0
            }

            try {
                // 1. Request Fresh Headers
                val interceptor = sdk.dartSyncInterceptor
                if (interceptor?.requestFreshHeaders() == true) {
                    sdk.logger.debug("NativeSyncProvider: Headers refreshed via Dart interceptor")
                }

                val coreHttp = state.getConfig().http
                sdk.logger.debug("NativeSyncProvider: coreHttp config: url=${coreHttp.url}, autoSync=${coreHttp.autoSync}")
                if (coreHttp.url.isNullOrEmpty() || !coreHttp.autoSync) return 0

                val limit = if (coreHttp.maxBatchSize > 0) coreHttp.maxBatchSize else 250
                // Always the OLDEST rows: `clearLocationsUpTo` deletes every id
                // up to the one given, so reading the newest N and clearing up to
                // the smallest of them deleted older rows that were never sent
                // (#437). `locationsOrderDirection` (#138) orders the payload.
                val oldest = db.getLocationsBatch(uniffi.tracelet_core.LocationQuery(
                    startTimeMs = null,
                    endTimeMs = null,
                    limit = limit.toInt(),
                    offset = null,
                    orderDescending = false
                ))
                sdk.logger.debug("NativeSyncProvider: Found ${oldest.size} locations in DB")
                if (oldest.isEmpty()) return 0
                val records = if (coreHttp.locationsOrderDirection == 1) oldest.reversed() else oldest
                val clearUpTo = oldest.maxOf { it.id }

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
                    return 0
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
                        db.clearLocationsUpTo(clearUpTo)
                        sdk.logger.info("NativeSyncProvider: Synced and cleared ${records.size} locations via custom body fallback.")
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
                    return if (result.success) records.size else 0
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
                        // #402: carried from the row, not resolved at flush time.
                        tripId = it.tripId,
                        address = it.address  // #212
                    )
                }

                val count = syncManager.syncBatchBlocking(syncConfig, syncRecords)
                if (count > 0U) {
                    db.clearLocationsUpTo(clearUpTo)
                    sdk.logger.info("NativeSyncProvider: Synced and cleared $count locations.")
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
                return if (count > 0U) records.size else 0
            } catch (e: Exception) {
                sdk.logger.error("NativeSyncProvider: Sync failed: ${e.message}")
                sdk.getEventSender().sendHttp(mapOf(
                    "success" to false,
                    "status" to 0,
                    "responseText" to (e.message ?: "Unknown error"),
                    "isRetry" to false,
                    "retryCount" to 0
                ))
                return 0
            }
        }
    }

    /**
     * POSTs telematics to their own endpoint (#368).
     *
     * Reuses [executeFallbackHttpSync] so the dedicated endpoint gets the same
     * headers, timeouts, retry/backoff and 401 token-refresh handling as the
     * location path — the only difference is the URL and the body.
     */
    override fun postTelematicsBlocking(
        config: uniffi.tracelet_core.HttpConfig,
        url: String,
        body: String,
    ): Boolean = kotlinx.coroutines.runBlocking {
        val result = executeFallbackHttpSync(
            config.copy(url = url),
            body,
            sdk.dartSyncInterceptor,
        )
        sdk.getEventSender().sendHttp(mapOf(
            "success" to result.success,
            "status" to result.status,
            "responseText" to result.responseText,
            "isRetry" to false,
            "retryCount" to 0
        ))
        result.success
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
                // #402: carried from the row, not resolved at flush time.
                tripId = it.tripId,
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
            var bodyWritten = false
            try {
                val url = URL(coreHttp.url)
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = if (coreHttp.method.toInt() == 1) "PUT" else "POST"
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/json")
                // #437: the configured timeout, not a fixed 15 s.
                val timeout = SyncRetryPolicy.timeoutMs(coreHttp.httpTimeout)
                conn.connectTimeout = timeout
                conn.readTimeout = timeout

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
                bodyWritten = true

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
                    kotlinx.coroutines.delay(
                        SyncRetryPolicy.backoffMs(attempt, coreHttp.retryBackoffBase, coreHttp.retryBackoffCap),
                    )
                }
            } catch (e: Exception) {
                sdk.logger.error("NativeSyncProvider: executeFallbackHttpSync Exception: ${e.message}")
                lastResponse = e.message ?: "Unknown exception"
                lastStatus = 0
                if (!SyncRetryPolicy.mayRetry(e, bodyWritten)) {
                    // The server may be processing it: a retry would send the
                    // batch twice. The rows stay queued for the next sync (#437).
                    sdk.logger.error("NativeSyncProvider: timed out after the body was sent — not retrying")
                    return FallbackSyncResult(false, lastStatus, lastResponse)
                }
                if (attempt < maxRetries) {
                    kotlinx.coroutines.delay(
                        SyncRetryPolicy.backoffMs(attempt, coreHttp.retryBackoffBase, coreHttp.retryBackoffCap),
                    )
                }
            }
        }
        return FallbackSyncResult(false, lastStatus, lastResponse)
    }
}
