package com.ikolvi.tracelet.flutter
import com.ikolvi.tracelet.sdk.util.TraceletLog

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.ikolvi.tracelet.sdk.TraceletBootstrap
import com.ikolvi.tracelet.sdk.TraceletSdk
import com.ikolvi.tracelet.sdk.sync.NO_SYNC_BODY_BUILDER_SENTINEL
import com.ikolvi.tracelet.TraceletHostApi
import com.ikolvi.tracelet.flutter.service.HeadlessTaskService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Broadcasts events to multiple EventDispatchers.
 */
class MultiEventSender : com.ikolvi.tracelet.sdk.TraceletEventSender {
    private val dispatchers = CopyOnWriteArrayList<EventDispatcher>()

    fun add(dispatcher: EventDispatcher) = dispatchers.addIfAbsent(dispatcher)
    fun remove(dispatcher: EventDispatcher) = dispatchers.remove(dispatcher)
    
    // Fallback getter - uses first available dispatcher for hasListener checks
    private val first: EventDispatcher? get() = dispatchers.firstOrNull()

    override fun sendLocation(data: Map<String, Any?>) { dispatchers.forEach { it.sendLocation(data) } }
    override fun sendMotionChange(data: Map<String, Any?>) { dispatchers.forEach { it.sendMotionChange(data) } }
    override fun sendSpeedMotionChange(data: Map<String, Any?>) { dispatchers.forEach { it.sendSpeedMotionChange(data) } }
    override fun sendActivityChange(data: Map<String, Any?>) { dispatchers.forEach { it.sendActivityChange(data) } }
    override fun sendProviderChange(data: Map<String, Any?>) { dispatchers.forEach { it.sendProviderChange(data) } }
    override fun sendGeofence(data: Map<String, Any?>) { dispatchers.forEach { it.sendGeofence(data) } }
    override fun sendGeofencesChange(data: Map<String, Any?>) { dispatchers.forEach { it.sendGeofencesChange(data) } }
    override fun sendHeartbeat(data: Map<String, Any?>) { dispatchers.forEach { it.sendHeartbeat(data) } }
    override fun sendHttp(data: Map<String, Any?>) { dispatchers.forEach { it.sendHttp(data) } }
    override fun sendSchedule(data: Map<String, Any?>) { dispatchers.forEach { it.sendSchedule(data) } }
    override fun sendPowerSaveChange(isPowerSaveMode: Boolean) { dispatchers.forEach { it.sendPowerSaveChange(isPowerSaveMode) } }
    override fun sendConnectivityChange(data: Map<String, Any?>) { dispatchers.forEach { it.sendConnectivityChange(data) } }
    override fun sendEnabledChange(enabled: Boolean) { dispatchers.forEach { it.sendEnabledChange(enabled) } }
    override fun sendNotificationAction(action: String) { dispatchers.forEach { it.sendNotificationAction(action) } }
    override fun sendAuthorization(data: Map<String, Any?>) { dispatchers.forEach { it.sendAuthorization(data) } }
    override fun sendWatchPosition(data: Map<String, Any?>) { dispatchers.forEach { it.sendWatchPosition(data) } }
    
    override fun sendRemoteConfigEvent(data: Map<String, Any?>) { dispatchers.forEach { it.sendRemoteConfigEvent(data) } }
    override fun sendTrip(data: Map<String, Any?>) { dispatchers.forEach { it.sendTrip(data) } }
    override fun sendBudgetAdjustment(data: Map<String, Any?>) { dispatchers.forEach { it.sendBudgetAdjustment(data) } }
    override fun sendDrivingEvent(data: Map<String, Any?>) { dispatchers.forEach { it.sendDrivingEvent(data) } }
    override fun sendImpact(data: Map<String, Any?>) { dispatchers.forEach { it.sendImpact(data) } }
    override fun sendModeChange(data: Map<String, Any?>) { dispatchers.forEach { it.sendModeChange(data) } }
    override fun sendCrashModelStatus(data: Map<String, Any?>) { dispatchers.forEach { it.sendCrashModelStatus(data) } }

    override fun hasListener(eventName: String): Boolean = dispatchers.any { it.hasListener(eventName) }
}


/**
 * TraceletAndroidPlugin — Robust Flutter bridge for Tracelet.
 */
class TraceletAndroidPlugin :
    FlutterPlugin,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener,
    com.ikolvi.tracelet.sdk.sync.DartSyncInterceptor {

    companion object {
        private const val TAG = "TraceletAndroidPlugin"
        private const val DART_CALLBACK_TIMEOUT_MS = 10_000L

        init {
            try {
                System.loadLibrary("tracelet_core")
            } catch (e: UnsatisfiedLinkError) {
                // Ignore in test environments like Robolectric
                TraceletLog.warning("Failed to load tracelet_core library, expected in tests", e)
            }
        }

        @Volatile
        var primaryInstance: TraceletAndroidPlugin? = null

        // Whether a foreground custom sync body builder is registered in Dart.
        // If false, we immediately return the sentinel instead of waiting for a 
        // Dart timeout, preventing the sync from aborting when suspended.
        @Volatile
        var hasCustomSyncBodyBuilder: Boolean = false
        
        private val attachedEngineCount = AtomicInteger(0)
        private val globalEventSender = MultiEventSender()

        @JvmField
        internal var isMainThread: () -> Boolean = {
            Looper.myLooper() == Looper.getMainLooper()
        }
    }

    private lateinit var context: Context
    private lateinit var eventDispatcher: EventDispatcher
    private var headlessService: HeadlessTaskService? = null

    private var activityBinding: ActivityPluginBinding? = null
    private var syncBodyChannel: MethodChannel? = null
    @Volatile private var isEngineAttached = false

    private val sdk: TraceletSdk get() = TraceletSdk.getInstance(context)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        isEngineAttached = true
        
        val count = attachedEngineCount.incrementAndGet()
        val isFirst = count == 1

        // ISSUE 136: Protect primary singletons from headless background engines.
        // Android's FlutterLoader uses reflection to auto-attach plugins to ALL FlutterEngines.
        // When the app is swiped away, the UI engine dies (primaryInstance becomes null). 
        // Later, HeadlessTaskService spins up a background engine, which instantiates a NEW 
        // TraceletAndroidPlugin. Without this flag check, the new headless plugin would see 
        // primaryInstance == null and hijack the dartSyncInterceptor, breaking routing.
        val isPrimaryCandidate = primaryInstance == null && !HeadlessTaskService.isSpawningHeadlessEngine
        
        sdk.logger.debug("onAttachedToEngine: engineCount=$count, isFirst=$isFirst, isPrimaryCandidate=$isPrimaryCandidate")

        if (isPrimaryCandidate) {
            primaryInstance = this
            sdk.logger.debug("onAttachedToEngine: setting as PRIMARY instance")

            eventDispatcher = EventDispatcher()
            eventDispatcher.register(binding.binaryMessenger)
            globalEventSender.add(eventDispatcher)

            sdk.setEventSender(globalEventSender)
            
            // Only initialize the SDK if it's the very first engine. 
            // If the SDK was already initialized (e.g. by a previous engine that detached),
            // initialize() is usually idempotent but we want to be sure.
            sdk.initialize()

            val hs = HeadlessTaskService(context, sdk.configManager)
            headlessService = hs

            val mainHandler = Handler(Looper.getMainLooper())
            syncBodyChannel = MethodChannel(binding.binaryMessenger, "com.tracelet/sync_body")
            
            syncBodyChannel?.setMethodCallHandler { call, result ->
                if (call.method == "setHasCustomSyncBodyBuilder") {
                    val hasBuilder = call.arguments as? Boolean ?: false
                    hasCustomSyncBodyBuilder = hasBuilder
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
            
            sdk.dartSyncInterceptor = this

            eventDispatcher.headlessFallback = { eventName, eventData ->
                if (hs.isRegistered()) {
                    hs.dispatchEvent(eventName, eventData)
                }
            }

            TraceletBootstrap.headlessDispatcherFactory = { ctx -> HeadlessTaskService(ctx) }
            TraceletBootstrap.eventSenderFactory = { ctx ->
                val dispatcher = EventDispatcher()
                val h = HeadlessTaskService(ctx)
                dispatcher.headlessFallback = { name, data ->
                    if (h.isRegistered()) h.dispatchEvent(name, data)
                }
                dispatcher
            }
        } else {
            // Secondary engine (e.g. headless isolate or EngineGroup overlay)
            sdk.logger.debug("onAttachedToEngine: secondary engine attach")
            
            // We still need an EventDispatcher for this engine if it wants to receive events in the foreground
            eventDispatcher = EventDispatcher()
            eventDispatcher.register(binding.binaryMessenger)
            globalEventSender.add(eventDispatcher)
            
            // At least we ensure that events fall back to headless if this engine is not the primary.
            primaryInstance?.headlessService?.let { hs ->
                eventDispatcher.headlessFallback = { name, data ->
                    if (hs.isRegistered()) hs.dispatchEvent(name, data)
                }
            }
        }

        // Pigeon API: register on EVERY engine.
        val apiHeadless = headlessService ?: HeadlessTaskService(context)
        TraceletHostApi.setUp(
            binding.binaryMessenger,
            TraceletHostApiImpl(context, apiHeadless),
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val count = attachedEngineCount.decrementAndGet()
        sdk.logger.debug("onDetachedFromEngine: remainingEngines=$count")
        
        isEngineAttached = false
        TraceletHostApi.setUp(binding.binaryMessenger, null)

        if (primaryInstance === this) {
            sdk.logger.debug("onDetachedFromEngine: primary instance detaching")
            primaryInstance = null
            syncBodyChannel = null
            
            // If this was the last engine, destroy the SDK.
            // Otherwise, we must NOT destroy the SDK because secondary engines might still be using it!
            globalEventSender.remove(eventDispatcher)
            if (count == 0) {
                sdk.logger.debug("onDetachedFromEngine: last engine detached, destroying SDK")
                eventDispatcher.unregister()
                sdk.destroyAll()
            } else {
                sdk.logger.debug("onDetachedFromEngine: secondary engines still active, SDK preserved")
                // We should probably promote another instance to primaryInstance here if needed.
                // But for Tracelet, the first one is usually the main one.
            }
        } else {
            globalEventSender.remove(eventDispatcher)
            eventDispatcher.unregister()
            if (count == 0) {
                sdk.logger.debug("onDetachedFromEngine: secondary engine was last, destroying SDK")
                sdk.destroyAll()
            }
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        sdk.logger.debug("onAttachedToActivity")
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
        sdk.activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        sdk.logger.debug("onDetachedFromActivityForConfigChanges")
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        sdk.activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        sdk.logger.debug("onReattachedToActivityForConfigChanges")
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
        sdk.activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        sdk.logger.debug("onDetachedFromActivity")
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        sdk.activity = null
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        return sdk.handlePermissionResult(requestCode, permissions, grantResults)
    }

    override fun requestTokenRefresh(): Boolean {
        sdk.logger.debug("requestTokenRefresh called. isEngineAttached=$isEngineAttached")
        if (!isEngineAttached) {
            if (headlessService?.isRegistered() != true) return false
            sdk.logger.debug("requestTokenRefresh: Engine detached, routing to HeadlessTaskService")
            // Note: If HeadlessTaskService doesn't have a specific token refresh method,
            // we can route it to headers refresh, as they are essentially the same headless callback layer.
            return headlessService?.requestHeadersRefresh(10000L) ?: false
        }
        val handler = Handler(Looper.getMainLooper())
        val latch = java.util.concurrent.CountDownLatch(1)
        var success = false
        handler.post {
            syncBodyChannel?.invokeMethod("requestTokenRefresh", null, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    success = result as? Boolean ?: false
                    latch.countDown()
                }
                override fun error(code: String, msg: String?, details: Any?) { latch.countDown() }
                override fun notImplemented() { latch.countDown() }
            })
        }
        val awaited = latch.await(DART_CALLBACK_TIMEOUT_MS, java.util.concurrent.TimeUnit.MILLISECONDS)
        if (!awaited) sdk.logger.error("requestTokenRefresh: TIMEOUT waiting for Dart callback")
        return success
    }

    override fun requestFreshHeaders(): Boolean {
        sdk.logger.debug("requestFreshHeaders called. isEngineAttached=$isEngineAttached")
        if (!isEngineAttached) {
            if (headlessService?.isRegistered() != true) return false
            sdk.logger.debug("requestFreshHeaders: Engine detached, routing to HeadlessTaskService")
            return headlessService?.requestHeadersRefresh(10000L) ?: false
        }
        val handler = Handler(Looper.getMainLooper())
        val latch = java.util.concurrent.CountDownLatch(1)
        var success = false
        handler.post {
            syncBodyChannel?.invokeMethod("requestFreshHeaders", null, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    success = result as? Boolean ?: false
                    latch.countDown()
                }
                override fun error(code: String, msg: String?, details: Any?) { latch.countDown() }
                override fun notImplemented() { latch.countDown() }
            })
        }
        val awaited = latch.await(DART_CALLBACK_TIMEOUT_MS, java.util.concurrent.TimeUnit.MILLISECONDS)
        if (!awaited) sdk.logger.error("requestFreshHeaders: TIMEOUT waiting for Dart callback")
        return success
    }

    /**
     * Returns the custom JSON body, [NO_SYNC_BODY_BUILDER_SENTINEL] when no
     * builder is registered, or `null` when a registered builder failed (timed
     * out or threw). Must never return an error object as a body — that was the
     * Issue #125 bug.
     */
    override fun requestSyncBody(locations: List<Map<String, Any?>>): String? {
        if (!hasCustomSyncBodyBuilder) {
            // No foreground builder registered in Dart. Return the sentinel
            // immediately to bypass the 10-second channel timeout and ensure
            // the sync falls back to the default payload without aborting.
            //
            // #340: the `requestSyncBody called with N locations` line below
            // sits after this check, so this branch returned in silence and a
            // device posting the default payload gave no clue why. Kept in step
            // with the iOS log of the same name.
            //
            // Deliberately TraceletLog, not `sdk.logger`: `sdk` resolves through
            // `TraceletSdk.getInstance(context)` and throws before the plugin is
            // attached to an engine. This branch must stay reachable in that
            // state — returning the sentinel *immediately, touching nothing* is
            // the #125 guarantee, and routing the log through the SDK broke it.
            // TraceletLog falls back to Log.d until a logger is attached.
            //
            // #340: before falling through to the default payload, try the
            // *headless* builder. This flag only ever reflects the foreground
            // isolate, so a process whose Dart never ran the app code that calls
            // setSyncBodyBuilder — a background relaunch, or an app opened but
            // not yet through its own init — reads false here even when
            // registerHeadlessSyncBodyBuilder is registered and usable. The
            // routing below is gated on !isEngineAttached, so it could not
            // rescue an *attached* engine whose Dart simply had not registered.
            //
            // `headlessService` is non-null only on the attached primary
            // instance, so this cannot fire in the never-attached state the
            // #125 guarantee is about — `context` itself is unset there.
            val hs = headlessService
            if (hs != null && !isMainThread() && hs.isSyncBodyBuilderRegistered()) {
                TraceletLog.debug(
                    "requestSyncBody: no foreground builder — routing to the headless builder",
                )
                return hs.requestCustomSyncBody(
                    locations,
                    DART_CALLBACK_TIMEOUT_MS,
                    sdk.getTelematicsForCustomBuilder(),
                )
            }

            TraceletLog.debug(
                "requestSyncBody: no custom sync body builder registered " +
                    "(setSyncBodyBuilder never reached native) — using the default payload",
            )
            return NO_SYNC_BODY_BUILDER_SENTINEL
        }

        sdk.logger.debug("requestSyncBody called with ${locations.size} locations. isEngineAttached=$isEngineAttached")
        if (!isEngineAttached) {
            // Background/killed: route to the headless service, which returns the
            // sentinel when no headless builder is registered and `null` only
            // when a registered one fails.
            val hs = headlessService ?: return NO_SYNC_BODY_BUILDER_SENTINEL
            sdk.logger.debug("requestSyncBody: Engine detached, routing to HeadlessTaskService")
            return hs.requestCustomSyncBody(
                locations,
                10000L,
                sdk.getTelematicsForCustomBuilder(),
            )
        }
        val handler = Handler(Looper.getMainLooper())
        val latch = java.util.concurrent.CountDownLatch(1)
        var body: String? = null
        // #214: deliver telematics alongside locations so custom-schema builders
        // can include driving/crash events. Map shape {locations, telematics};
        // the Dart handler stays backward-compatible with the old bare-List arg.
        // telematics is empty unless syncTelematics is enabled (gated in the SDK).
        val args = mapOf(
            "locations" to locations,
            "telematics" to sdk.getTelematicsForCustomBuilder(),
        )
        handler.post {
            syncBodyChannel?.invokeMethod("buildSyncBody", args, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    // String = sentinel or real body; null = a registered builder
                    // threw on the Dart side → leave body null so we abort.
                    body = result as? String
                    latch.countDown()
                }
                override fun error(code: String, msg: String?, details: Any?) {
                    // Channel error → abort (leave body null).
                    sdk.logger.error("requestSyncBody: error: $msg")
                    latch.countDown()
                }
                override fun notImplemented() {
                    // No Dart handler = no builder → fall through to default sync.
                    body = NO_SYNC_BODY_BUILDER_SENTINEL
                    latch.countDown()
                }
            })
        }
        val awaited = latch.await(DART_CALLBACK_TIMEOUT_MS, java.util.concurrent.TimeUnit.MILLISECONDS)
        if (!awaited) {
            // The foreground Dart isolate didn't answer in time. This usually
            // means the app is backgrounding/suspended or the main thread is
            // janky when an auto-sync fires — it is NOT the same as "the builder
            // ran and failed". So don't abort outright: fall back to the headless
            // engine, which has its own isolate and is built for background work
            // (Issue #134).
            sdk.logger.error("requestSyncBody: TIMEOUT waiting for Dart callback after $DART_CALLBACK_TIMEOUT_MS ms; falling back to headless")
            val hs = headlessService ?: return null
            val headlessBody = hs.requestCustomSyncBody(
                locations,
                DART_CALLBACK_TIMEOUT_MS,
                sdk.getTelematicsForCustomBuilder(),
            )
            // The headless runner returns the sentinel when no headless builder is
            // registered. We must NOT post the default body in that case (a
            // foreground custom builder IS registered, so default would be the
            // wrong shape), so abort (null) and leave the batch for the next
            // sync attempt.
            return if (headlessBody == NO_SYNC_BODY_BUILDER_SENTINEL) null else headlessBody
        }
        return body
    }
}
