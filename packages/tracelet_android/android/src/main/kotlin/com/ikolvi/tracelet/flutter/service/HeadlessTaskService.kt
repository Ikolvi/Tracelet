package com.ikolvi.tracelet.flutter.service

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import com.ikolvi.tracelet.sdk.TraceletSdk
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.HeadersRefreshable
import com.ikolvi.tracelet.sdk.HeadlessDispatcher
import com.ikolvi.tracelet.sdk.sync.NO_SYNC_BODY_BUILDER_SENTINEL
import com.ikolvi.tracelet.sdk.util.TraceletLog
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation
import android.os.SystemClock
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/**
 * Headless Dart execution service for background events.
 *
 * When the app UI is killed but the service is running, this creates
 * a new FlutterEngine and dispatches HeadlessEvents to the registered
 * Dart callback.
 *
 * Flow:
 * 1. Dart calls registerHeadlessTask() → callback handles stored in SharedPreferences
 * 2. Background event occurs with no UI FlutterEngine
 * 3. HeadlessTaskService creates a new FlutterEngine
 * 4. Executes the Dart callback via DartExecutor
 * 5. Sends HeadlessEvent via MethodChannel
 * 6. Disposes engine when done
 */
class HeadlessTaskService(
    private val context: Context,
    private val configManager: ConfigManager? = null,
) : HeadlessDispatcher, HeadersRefreshable {

    companion object {
        private const val TAG = "HeadlessTaskService"
        private const val PREFS_NAME = "com.tracelet.headless"
        private const val KEY_REGISTRATION_CALLBACK = "registration_callback_id"
        private const val KEY_DISPATCH_CALLBACK = "dispatch_callback_id"
        private const val CHANNEL_NAME = "com.tracelet/headless"
        private const val METHODS_CHANNEL_NAME = "com.tracelet/methods"

        // Context flag to protect against FlutterLoader auto-registering plugins.
        // Used by TraceletAndroidPlugin.onAttachedToEngine to avoid hijacking the primary
        // instance singletons (like dartSyncInterceptor) when a headless engine boots (Issue 136).
        @JvmStatic
        var isSpawningHeadlessEngine = false

        /**
         * How long a spawn may take before it is declared stalled and retried
         * (#331). Generous: a cold engine on a loaded device legitimately takes
         * seconds. What it must not do is wait forever in silence.
         */
        internal const val ENGINE_SPAWN_TIMEOUT_MS = 30_000L

        /**
         * Cap on events buffered while the engine comes up (#331). The queue was
         * unbounded, so a spawn that never completed grew it for as long as
         * tracking ran — every 2 s on a continuous config.
         */
        internal const val MAX_PENDING_EVENTS = 200
    }

    /**
     * How far a spawn attempt got. Named in the stall log so a single bug report
     * identifies which link broke, instead of leaving "no engine, no error"
     * (#331).
     */
    internal enum class SpawnStage {
        /** No spawn in flight. */
        IDLE,

        /** Posted to the main thread; the block has not started. */
        POSTED,

        /** FlutterLoader initialization completed. */
        LOADER_READY,

        /** The FlutterEngine object exists; Dart has not signalled back. */
        ENGINE_CREATED,

        /** Dart called `initialized` — events flow. */
        READY,
    }

    enum class CallbackType(val regKey: String, val dispatchKey: String) {
        MAIN(KEY_REGISTRATION_CALLBACK, KEY_DISPATCH_CALLBACK),
        HEADERS("headlessHeaders_registrationId", "headlessHeaders_dispatchId"),
        SYNC_BODY("headlessSyncBody_registrationId", "headlessSyncBody_dispatchId")
    }

    @Volatile
    private var flutterEngine: FlutterEngine? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val isEngineReady = AtomicBoolean(false)
    private val pendingEvents = LinkedBlockingQueue<Map<String, Any?>>()
    @Volatile
    private var headlessMethodChannel: MethodChannel? = null

    /**
     * One spawn at a time (#331). Events arrive from several threads at once
     * (location, heartbeat, sync); without this each one posted its own spawn
     * and a second FlutterEngine could overwrite [headlessMethodChannel] out
     * from under the engine that was about to become ready.
     */
    private val spawnInFlight = AtomicBoolean(false)

    @Volatile
    private var spawnStage = SpawnStage.IDLE

    /** [SystemClock.elapsedRealtime] when the in-flight spawn was posted. */
    @Volatile
    private var spawnStartedAtMs = 0L

    /** Events discarded because the queue hit [MAX_PENDING_EVENTS]. */
    private val droppedEvents = AtomicLong(0)

    /** Latch signaled when headless Dart callback calls setDynamicHeaders. */
    @Volatile
    private var headersRefreshLatch: CountDownLatch? = null

    /** Latch signaled when headless Dart callback returns custom sync body. */
    private val syncBodyLock = Object()
    private var syncBodyLatch: CountDownLatch? = null
    private var syncBodyResponse: String? = null

    /** Register the headless callback IDs (called from Dart side). */
    fun registerCallbacks(type: CallbackType, registrationCallbackId: Long, dispatchCallbackId: Long) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putLong(type.regKey, registrationCallbackId)
            .putLong(type.dispatchKey, dispatchCallbackId)
            .apply()
        TraceletSdk.getInstance(context).logger.debug("Headless callbacks registered ($type): reg=$registrationCallbackId, dispatch=$dispatchCallbackId")
    }

    /** Returns whether headless task is registered. */
    override fun isRegistered(): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.contains(KEY_REGISTRATION_CALLBACK) && prefs.contains(KEY_DISPATCH_CALLBACK)
    }

    /**
     * Whether `registerHeadlessSyncBodyBuilder` has persisted a callback pair.
     *
     * A SharedPreferences read and nothing else (#340): it is consulted from
     * `requestSyncBody`'s earliest branch, which must stay cheap and must not
     * reach into the SDK.
     */
    fun isSyncBodyBuilderRegistered(): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getLong(CallbackType.SYNC_BODY.regKey, -1L) != -1L &&
            prefs.getLong(CallbackType.SYNC_BODY.dispatchKey, -1L) != -1L
    }

    /**
     * Dispatch a headless event. If no UI engine is available, creates
     * a new FlutterEngine to handle the event.
     *
     * Each event is wrapped to include the dispatch callback ID so the
     * Dart-side dispatcher ([_headlessCallbackDispatcher]) can look up
     * the user's callback via [PluginUtilities.getCallbackFromHandle].
     */
    override fun dispatchEvent(eventName: String, eventData: Map<String, Any?>) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val dispatchId = prefs.getLong(KEY_DISPATCH_CALLBACK, -1L)

        val event = mapOf(
            "name" to eventName,
            "event" to eventData,
            "dispatchId" to dispatchId,
        )

        // Geofence crossings only, on the always-on channel (#318): they are the
        // SDK's product event, a handful a day, and the one place a report needs
        // to distinguish "the crossing never reached Dart" from "it reached Dart
        // and the app did nothing with it". Every other event is high-frequency
        // and stays off this channel. Also names the registration, since a
        // missing MAIN callback id delivers to nobody (#358).
        if (eventName == "geofence") {
            val engineReady = isEngineReady.get() && headlessMethodChannel != null
            TraceletLog.lifecycle(
                "headless: dispatching geofence to the headless task — " +
                    "route=${if (engineReady) "live engine" else "queued, spawning"} " +
                    "dispatchId=${if (dispatchId == -1L) "MISSING" else "set"}",
            )
        }

        if (isEngineReady.get() && headlessMethodChannel != null) {
            sendEvent(event)
            return
        }

        enqueue(event)
        ensureEngine()
    }

    /**
     * Destroy the headless FlutterEngine and discard anything still queued.
     *
     * Only for a real teardown. A *failed spawn* must not come through here —
     * clearing the queue there threw away every event the engine was being
     * spawned to deliver (#331); [resetSpawn] keeps them for the next attempt.
     */
    fun destroy() {
        val abandoned = pendingEvents.size
        if (abandoned > 0) {
            TraceletLog.warning(
                "headless: destroy() discarding $abandoned undelivered event(s)",
            )
        }
        resetSpawn()
        pendingEvents.clear()
    }

    /**
     * Request a headers refresh from the headless Dart callback.
     *
     * Dispatches a `headersRefresh` event to the Dart headless callback
     * registered via `registerHeadlessHeadersCallback`. The Dart callback
     * is expected to refresh the token and call `Tracelet.setDynamicHeaders()`,
     * which routes back to the native side and signals this method to return.
     *
     * @param timeoutMs Maximum time to wait for the Dart callback to respond.
     * @return `true` if headers were refreshed within the timeout.
     */
    override fun requestHeadersRefresh(timeoutMs: Long): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val dispatchId = prefs.getLong("headlessHeaders_dispatchId", -1L)
        val registrationId = prefs.getLong("headlessHeaders_registrationId", -1L)
        if (dispatchId == -1L || registrationId == -1L) {
            TraceletSdk.getInstance(context).logger.warning("No headless headers callback registered")
            return false
        }

        // Guard: blocking the main thread would deadlock because the Dart
        // MethodChannel response also needs the main thread.
        if (Looper.myLooper() == Looper.getMainLooper()) {
            TraceletSdk.getInstance(context).logger.error("requestHeadersRefresh() must not be called on the main thread — would deadlock")
            return false
        }

        val latch = CountDownLatch(1)
        headersRefreshLatch = latch

        // Dispatch the headersRefresh event using the headers-specific dispatch ID
        val event = mapOf(
            "name" to "headersRefresh",
            "event" to emptyMap<String, Any?>(),
            "dispatchId" to dispatchId,
        )

        if (isEngineReady.get() && headlessMethodChannel != null) {
            sendEvent(event)
        } else {
            enqueue(event)
            ensureEngine()
        }

        return try {
            val result = latch.await(timeoutMs, TimeUnit.MILLISECONDS)
            if (result) {
                TraceletSdk.getInstance(context).logger.debug("Headers refresh completed by headless callback")
            } else {
                TraceletSdk.getInstance(context).logger.warning("Headers refresh timed out after ${timeoutMs}ms")
            }
            result
        } finally {
            headersRefreshLatch = null
        }
    }

    /**
     * Request a custom sync body from the headless Dart callback.
     *
     * Dispatches a `syncBodyBuild` event to the Dart headless callback
     * registered via `registerHeadlessSyncBodyBuilder`. The Dart callback
     * is expected to transform the locations and call
     * `Tracelet.setSyncBodyResponse()`, which routes back to the native
     * side and signals this method to return.
     *
     * @param locations The batch of locations to include in the body.
     * @param timeoutMs Maximum time to wait for the Dart callback to respond.
     * @return The custom JSON body string, or `null` if timed out or unavailable.
     */
    fun requestCustomSyncBody(
        locations: List<Map<String, Any?>>,
        timeoutMs: Long,
        // #214: telematics for the killed-state custom builder. Defaults to empty
        // so existing callers/headless callbacks keep working unchanged.
        telematics: List<Map<String, Any?>> = emptyList(),
    ): String? {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val dispatchId = prefs.getLong("headlessSyncBody_dispatchId", -1L)
        val registrationId = prefs.getLong("headlessSyncBody_registrationId", -1L)
        if (dispatchId == -1L || registrationId == -1L) {
            // No headless builder registered → sentinel so the sync provider
            // falls through to the default payload rather than aborting.
            TraceletSdk.getInstance(context).logger.warning("No headless sync body callback registered")
            return NO_SYNC_BODY_BUILDER_SENTINEL
        }

        if (Looper.myLooper() == Looper.getMainLooper()) {
            // A builder is registered but we cannot run it here → abort (null).
            TraceletSdk.getInstance(context).logger.error("requestCustomSyncBody() must not be called on the main thread — would deadlock")
            return null
        }

        val latch = CountDownLatch(1)
        synchronized(syncBodyLock) {
            syncBodyLatch = latch
            syncBodyResponse = null
        }

        val event = mapOf(
            "name" to "syncBodyBuild",
            // #214: include telematics so headless custom builders can read
            // event['telematics'] (empty unless syncTelematics is enabled).
            "event" to mapOf("locations" to locations, "telematics" to telematics),
            "dispatchId" to dispatchId,
        )

        if (isEngineReady.get() && headlessMethodChannel != null) {
            sendEvent(event)
        } else {
            enqueue(event)
            ensureEngine()
        }

        return try {
            val completed = latch.await(timeoutMs, TimeUnit.MILLISECONDS)
            if (completed) {
                TraceletSdk.getInstance(context).logger.debug("Sync body build completed by headless callback")
                synchronized(syncBodyLock) { syncBodyResponse }
            } else {
                TraceletSdk.getInstance(context).logger.warning("Sync body build timed out after ${timeoutMs}ms")
                null
            }
        } finally {
            synchronized(syncBodyLock) {
                syncBodyLatch = null
                syncBodyResponse = null
            }
        }
    }

    // =========================================================================
    // Private
    // =========================================================================

    private fun ensureEngine() {
        // A spawn that never finished used to leave the engine non-null (or the
        // in-flight flag set) forever, and this method's first line then made
        // every subsequent event a silent no-op. Give up on it and try again
        // instead (#331).
        failStalledSpawn()

        if (flutterEngine != null) return

        // One spawn at a time — concurrent dispatches must not each post one.
        if (!spawnInFlight.compareAndSet(false, true)) return

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        // Try main headless callback first, then fallback to headers or sync body
        var registrationCallbackId = prefs.getLong(CallbackType.MAIN.regKey, -1L)
        if (registrationCallbackId == -1L) {
            registrationCallbackId = prefs.getLong(CallbackType.HEADERS.regKey, -1L)
        }
        if (registrationCallbackId == -1L) {
            registrationCallbackId = prefs.getLong(CallbackType.SYNC_BODY.regKey, -1L)
        }

        if (registrationCallbackId == -1L) {
            TraceletLog.warning(
                "headless: no callbacks registered — dropping ${pendingEvents.size} queued event(s)",
            )
            pendingEvents.clear()
            spawnInFlight.set(false)
            return
        }

        spawnStage = SpawnStage.POSTED
        spawnStartedAtMs = SystemClock.elapsedRealtime()
        // The anchor for every "headless never fired" report: it says a spawn was
        // asked for. Its absence means routing never reached this service; its
        // presence without a matching `engine ready` names the stall (#331).
        TraceletLog.lifecycle(
            "headless: spawning a FlutterEngine (${pendingEvents.size} event(s) queued)",
        )

        mainHandler.post {
            try {
                // The process-wide loader, not a fresh FlutterLoader(). A new one
                // re-runs full Flutter initialization — the source of the
                // "FlutterJNI.loadLibrary called more than once" warning — and
                // blocks the main thread on its own init future. Once the app has
                // started Flutter, both calls below return immediately (#331).
                val loader = FlutterInjector.instance().flutterLoader()
                if (!loader.initialized()) {
                    loader.startInitialization(context)
                    loader.ensureInitializationComplete(context, null)
                }
                spawnStage = SpawnStage.LOADER_READY

                isSpawningHeadlessEngine = true
                val engine = try {
                    FlutterEngine(context)
                } finally {
                    isSpawningHeadlessEngine = false
                }

                headlessMethodChannel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)

                // Set up method channel to receive "ready" signal from Dart
                headlessMethodChannel?.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "initialized" -> {
                            spawnStage = SpawnStage.READY
                            isEngineReady.set(true)
                            spawnInFlight.set(false)
                            TraceletLog.lifecycle(
                                "headless: engine ready — draining " +
                                    "${pendingEvents.size} queued event(s)",
                            )
                            drainPendingEvents()
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                }

                // Handle setDynamicHeaders from headless Dart callback.
                // When the Dart headless callback calls Tracelet.setDynamicHeaders(),
                // it goes through com.tracelet/methods. We handle it here so the
                // headless engine can update headers and signal the refresh latch.
                val methodsChannel = MethodChannel(engine.dartExecutor.binaryMessenger, METHODS_CHANNEL_NAME)
                methodsChannel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "setDynamicHeaders" -> {
                            @Suppress("UNCHECKED_CAST")
                            val headers = (call.arguments as? Map<String, Any?>)
                                ?.mapValues { it.value?.toString() ?: "" }
                                ?: emptyMap()
                            configManager?.setDynamicHeaders(headers)
                            headersRefreshLatch?.countDown()
                            result.success(true)
                        }
                        "setSyncBodyResponse" -> {
                            synchronized(syncBodyLock) {
                                syncBodyResponse = call.arguments as? String
                            }
                            syncBodyLatch?.countDown()
                            result.success(true)
                        }
                        "requestTermination" -> {
                            try {
                                TraceletSdk.getInstance(context).stop()
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("STOP_FAILED", e.message, null)
                            }
                        }
                        else -> result.notImplemented()
                    }
                }

                // Execute the registration callback in Dart
                val callbackInfo = FlutterCallbackInformation.lookupCallbackInformation(registrationCallbackId)
                if (callbackInfo == null) {
                    // Nothing can ever consume these events: the callback the
                    // engine exists to run is gone from the app bundle.
                    TraceletLog.lifecycle(
                        "headless: no callback info for ID $registrationCallbackId — " +
                            "the registered Dart entrypoint is gone from this build",
                    )
                    headlessMethodChannel = null
                    engine.destroy()
                    destroy()
                    return@post
                }

                engine.dartExecutor.executeDartCallback(
                    DartExecutor.DartCallback(context.assets, loader.findAppBundlePath(), callbackInfo)
                )
                // Published only once the engine is fully wired. Assigning it
                // before this point (as the `.also {}` form did) meant a failure
                // inside the block still left a non-null engine behind, and
                // ensureEngine()'s null check then blocked every retry (#331).
                flutterEngine = engine
                spawnStage = SpawnStage.ENGINE_CREATED
            } catch (t: Throwable) {
                // Throwable, not Exception: a failed native load arrives as
                // UnsatisfiedLinkError, which escaped this handler unseen and left
                // the caller with no engine and no error at any level (#331).
                TraceletLog.lifecycle(
                    "headless: engine spawn FAILED at stage $spawnStage — ${t.message}",
                )
                TraceletLog.error("Failed to create headless FlutterEngine", t)
                // resetSpawn, not destroy: the queued events are what the engine
                // was being spawned to deliver. Keep them for the next attempt.
                resetSpawn()
            }
        }
    }

    /**
     * Abandons an in-flight spawn that has outlived [ENGINE_SPAWN_TIMEOUT_MS] so
     * the next event can start a fresh one (#331).
     *
     * The reported failure was permanent: whatever the main thread was doing —
     * blocked, or never running the posted block at all — no timeout, retry, or
     * log ever followed, and events accumulated for as long as tracking ran. The
     * stage recorded here is the diagnostic: it names how far the attempt got.
     */
    private fun failStalledSpawn() {
        if (!spawnInFlight.get() || isEngineReady.get()) return
        val startedAt = spawnStartedAtMs
        if (startedAt == 0L) return
        val elapsed = SystemClock.elapsedRealtime() - startedAt
        if (elapsed < ENGINE_SPAWN_TIMEOUT_MS) return

        TraceletLog.lifecycle(
            "headless: engine spawn STALLED at stage $spawnStage after ${elapsed}ms — " +
                "retrying (${pendingEvents.size} event(s) queued)",
        )
        resetSpawn()
    }

    /**
     * Returns to a spawnable state, keeping [pendingEvents] intact. Unlike
     * [destroy] this is recoverable: the next dispatched event starts a new
     * spawn and drains everything buffered in the meantime.
     */
    private fun resetSpawn() {
        val engine = flutterEngine
        flutterEngine = null
        headlessMethodChannel = null
        isEngineReady.set(false)
        spawnStage = SpawnStage.IDLE
        spawnStartedAtMs = 0L
        spawnInFlight.set(false)
        // FlutterEngine.destroy() is main-thread-only; failStalledSpawn runs on
        // whichever thread produced the event.
        if (engine != null) {
            if (Looper.myLooper() == Looper.getMainLooper()) {
                engine.destroy()
            } else {
                mainHandler.post { engine.destroy() }
            }
        }
    }

    /**
     * Buffers an event for the engine that is coming up, capped at
     * [MAX_PENDING_EVENTS].
     *
     * The queue was unbounded (#331): a spawn that never completed grew it by one
     * entry per location fix — every 2 s under the reporter's config — for the
     * life of the process. Oldest-first eviction keeps the freshest events, and
     * the drop is reported rather than silent.
     */
    private fun enqueue(event: Map<String, Any?>) {
        var dropped = 0
        while (pendingEvents.size >= MAX_PENDING_EVENTS) {
            if (pendingEvents.poll() == null) break
            dropped++
        }
        if (dropped > 0) {
            val total = droppedEvents.addAndGet(dropped.toLong())
            if (total == dropped.toLong()) {
                // Once per queue, on the always-on channel: a report showing this
                // has a headless engine that never came up.
                TraceletLog.lifecycle(
                    "headless: pending-event queue hit its $MAX_PENDING_EVENTS cap — " +
                        "dropping the oldest events while stage $spawnStage",
                )
            }
            TraceletLog.warning(
                "headless: queue full — dropped $dropped event(s) (total $total)",
            )
        }
        pendingEvents.add(event)
    }

    private fun drainPendingEvents() {
        while (pendingEvents.isNotEmpty()) {
            val event = pendingEvents.poll() ?: break
            sendEvent(event)
        }
    }

    private fun sendEvent(event: Map<String, Any?>) {
        mainHandler.post {
            headlessMethodChannel?.invokeMethod("headlessEvent", event)
        }
    }
}
