package com.ikolvi.tracelet_sync

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

import com.ikolvi.tracelet.sdk.TraceletSdk
import com.ikolvi.tracelet.sdk.location.LocationDataSink
import com.ikolvi.tracelet.sdk.sync.NO_SYNC_BODY_BUILDER_SENTINEL
import uniffi.tracelet_sync.SyncManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class TraceletSyncSink(private val sdk: TraceletSdk) : LocationDataSink, TraceletSdk.SyncProvider {
    // SupervisorJob: a single failed sync must not cancel the scope, else the
    // first background sync that throws kills every future sync (Issue #134).
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val syncMutex = Mutex()
    private val syncManager = SyncManager()

    private var syncJob: kotlinx.coroutines.Job? = null
    private val DEBOUNCE_MS = 10_000L

    override fun insertLocation(location: Map<String, Any?>) {
        val delayMs = sdk.rustEngineState?.getConfig()?.http?.autoSyncDelay?.toLong() ?: 10_000L
        if (syncJob?.isActive == true) return
        syncJob = scope.launch {
            // Contain any throwable so a single failed iteration can't tear down
            // auto-sync; re-throw real cancellation so stop() still works (#134).
            try {
                kotlinx.coroutines.delay(delayMs)
                triggerSync()
            } catch (ce: kotlinx.coroutines.CancellationException) {
                throw ce
            } catch (t: Throwable) {
                sdk.logger.error("TraceletSyncSink: auto-sync iteration failed (contained): ${t.message}")
            }
        }
    }

    // Cancel the in-flight debounce so stop() takes effect immediately (#213).
    // TraceletSdk.stop() calls syncProvider?.cancelPendingSync(); without this
    // override (the interface default is a no-op) the coroutine kept sleeping
    // through delay(autoSyncDelay) and still fired an HTTP sync up to ~10s after
    // the user stopped tracking.
    override fun cancelPendingSync() {
        syncJob?.cancel()
        syncJob = null
        sdk.logger.debug("TraceletSyncSink: pending debounced background sync cancelled on stop().")
    }
    
    private suspend fun triggerSync() {
        syncMutex.withLock {
            sdk.logger.debug("triggerSync started")
            val db = sdk.rustDatabase ?: run {
                sdk.logger.error("rustDatabase is null")
                return
            }
            val state = sdk.rustEngineState ?: run {
                sdk.logger.error("rustEngineState is null")
                return
            }
            
            try {
                val coreHttp = state.getConfig().http
                sdk.logger.debug("coreHttp config: url=${coreHttp.url}, autoSync=${coreHttp.autoSync}")
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
                sdk.logger.debug("Found ${records.size} locations in DB")
                if (records.isEmpty()) return
                
                val count = syncBatchBlocking(coreHttp, records)
                if (count > 0L) {
                    records.lastOrNull()?.id?.let { lastId ->
                        db.clearLocationsUpTo(lastId)
                        sdk.logger.info("Synced and cleared $count locations.")
                    }
                }
            } catch (e: Exception) {
                sdk.logger.error("Sync failed: ${e.message}")
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
                address = it.address  // #212: carry reverse-geocoded address into the default payload
            )
        }
        val interceptor = sdk.dartSyncInterceptor
        sdk.logger.debug("TraceletSyncPlugin Interceptor is $interceptor")
        if (interceptor != null) {
            // Issue #126: emit the SAME nested schema as onLocation/getLocations
            // (nested coords/activity/battery + route_context) so the Dart
            // custom-body builder receives a consistent shape instead of a flat
            // map with a raw String activity.
            val recordMaps = records.map { sdk.mapRecordToLocation(it) }
            sdk.logger.debug("Calling requestSyncBody on interceptor with ${recordMaps.size} records")
            val customBody = interceptor.requestSyncBody(recordMaps)
            sdk.logger.debug("requestSyncBody returned: $customBody")
            if (customBody == null) {
                // Builder registered but failed → abort (0 = nothing synced).
                sdk.logger.error("Custom sync body failed to build; aborting sync")
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
                return kotlinx.coroutines.runBlocking {
                    val result = executeFallbackHttpSync(config, customBody, interceptor)
                    sdk.logger.debug("executeFallbackHttpSync result: ${result.success}, status: ${result.status}")
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
                // #214 dedup: a custom builder may have included the telematics we
                // exposed via getTelematicsForCustomBuilder(); now that the POST
                // succeeded, mark exactly those synced so they aren't re-sent.
                // No-op for the default-payload path (nothing was exposed).
                sdk.markExposedTelematicsSynced()
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
            sdk.logger.error("Sync failed: ${e.message}")
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

    data class FallbackSyncResult(val success: Boolean, val status: Int, val responseText: String)

    internal suspend fun executeFallbackHttpSync(
        coreHttp: uniffi.tracelet_core.HttpConfig,
        customBody: String,
        interceptor: com.ikolvi.tracelet.sdk.sync.DartSyncInterceptor?
    ): FallbackSyncResult {
        var currentHeaders = coreHttp.headers
        val maxRetries = coreHttp.maxRetries.toInt()
        
        var lastStatus = 0
        var lastResponse = "Unknown error"

        for (attempt in 0..maxRetries) {
            try {
                val url = java.net.URL(coreHttp.url)
                val conn = url.openConnection() as java.net.HttpURLConnection
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
                        sdk.logger.error("Failed to set HTTP headers: ${e.message}")
                    }
                }

                conn.outputStream.use { os ->
                    val input = customBody.toByteArray(kotlin.text.Charsets.UTF_8)
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
            } catch (e: Exception) {
                sdk.logger.error("HTTP Sync failed: ${e.message}")
                lastResponse = e.message ?: "Unknown exception"
                lastStatus = 0
            }
            if (attempt < maxRetries) {
                kotlinx.coroutines.delay(1000L * (attempt + 1))
            }
        }
        return FallbackSyncResult(false, lastStatus, lastResponse)
    }
}

/** TraceletSyncPlugin */
class TraceletSyncPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel

    companion object {
        /**
         * The one and only sink for this process (#286).
         *
         * `onAttachedToEngine` used to build a NEW [TraceletSyncSink] for every
         * `FlutterEngine` that attached, and `onDetachedFromEngine` never tore it
         * down. Hosts that spawn secondary engines — `workmanager_android` creates
         * one per task, plus headless services and engine groups — therefore
         * accumulated sinks for the lifetime of the process. Each surviving sink
         * owns its own [CoroutineScope], [Mutex] and `SyncManager`, so the
         * per-sink guards (`syncJob?.isActive`, `syncMutex`) could no longer
         * serialize anything: one persisted location fanned out into N blocking
         * auto-syncs, each pinning 1–2 threads, which surfaced in production as
         * `OutOfMemoryError: pthread_create failed` and heap exhaustion (plus
         * duplicate points server-side and racing `clearLocationsUpTo` calls).
         *
         * [TraceletSdk] is a process singleton and exactly one sync provider can
         * be active, so the sink is created on first attach and reused by every
         * later engine. That keeps the concurrency guards meaningful no matter how
         * many engines come and go.
         */
        @Volatile
        private var sharedSink: TraceletSyncSink? = null

        private val sinkLock = Any()

        /**
         * Returns the process-wide sink, creating it on first use.
         *
         * Double-checked locking: attaches happen on each engine's platform
         * thread, and a background engine can attach while the UI engine is
         * still attaching.
         */
        @JvmStatic
        internal fun obtainSharedSink(sdk: TraceletSdk): TraceletSyncSink {
            sharedSink?.let { return it }
            return synchronized(sinkLock) {
                sharedSink ?: TraceletSyncSink(sdk).also { sharedSink = it }
            }
        }

        /** Visible for tests: the current process-wide sink, if one was created. */
        @JvmStatic
        internal fun sharedSinkOrNull(): TraceletSyncSink? = sharedSink

        /** Visible for tests: forget the process-wide sink between cases. */
        @JvmStatic
        internal fun resetSharedSinkForTesting() {
            synchronized(sinkLock) { sharedSink = null }
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "tracelet_sync")
        channel.setMethodCallHandler(this)
        
        try {
            val context = binding.applicationContext
            val traceletSdk = TraceletSdk.getInstance(context)

            val isFirstAttach = sharedSinkOrNull() == null
            val sink = obtainSharedSink(traceletSdk)
            // Idempotent for the same instance: registerSyncProvider() skips the
            // cancel/unregister path when the provider is unchanged, and both
            // LocationEngine.registerSink() calls dedupe.
            traceletSdk.registerSyncProvider(sink)

            if (isFirstAttach) {
                traceletSdk.logger.info("Sync sink registered!")
            } else {
                traceletSdk.logger.info(
                    "Sync sink reused for an additional FlutterEngine (process-wide, #286)",
                )
            }
        } catch (e: Exception) {
            val ctx = binding.applicationContext
            TraceletSdk.getInstance(ctx).logger.error("Failed to init sync engine: ${e.message}")
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        if (call.method == "initialize") {
            result.success(true)
        } else {
            result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        // The sink is deliberately NOT cancelled here. It is process-wide now, so
        // there is nothing to accumulate, and native/headless tracking keeps
        // persisting locations after an engine (often a short-lived background
        // one) goes away — tearing the sink down would silently stop auto-sync for
        // the rest of the process. TraceletSdk.stop() still calls
        // cancelPendingSync() when the user stops tracking (#213).
    }
}
