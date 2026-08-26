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
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Broadcasts events to multiple EventDispatchers.
 *
 * The fan-out can legitimately end up with **no member able to receive** — most
 * often after task removal, when the primary engine detaches while another
 * plugin's background engine keeps the process alive (#371). Every dispatcher
 * has its own [EventDispatcher.headlessFallback] for the engine-is-gone case,
 * but those are members of the list: once the list is empty there is nothing
 * left to fall back *from*, and `forEach` on an empty list is a silent no-op.
 * So the composite carries a fallback of its own — see [headlessFallback].
 */
class MultiEventSender : com.ikolvi.tracelet.sdk.TraceletEventSender {
    private val dispatchers = CopyOnWriteArrayList<EventDispatcher>()

    /**
     * Where an event goes when no member of the fan-out can receive it (#371).
     *
     * Wired by the primary plugin instance to the same `HeadlessTaskService`
     * the per-dispatcher fallbacks use, so the surviving process keeps a
     * headless-capable receiver after the UI engine dies. Null before any
     * primary attach — in that state the members keep their old behaviour of
     * each falling back on their own.
     */
    @Volatile
    var headlessFallback: ((eventName: String, data: Map<String, Any?>) -> Unit)? = null

    /**
     * Whether events are currently being routed to the headless task because
     * the fan-out cannot receive them. Only used to log the *transitions*: the
     * events themselves arrive every few seconds, and this whole class of bug
     * is invisible precisely because the empty-fan-out path logged nothing.
     */
    private val routingToHeadless = AtomicBoolean(false)

    fun add(dispatcher: EventDispatcher) = dispatchers.addIfAbsent(dispatcher)
    fun remove(dispatcher: EventDispatcher) = dispatchers.remove(dispatcher)

    /**
     * Sends one event, to the engines that can receive it or — when none can —
     * to the headless task (#371).
     *
     * [send] is the per-dispatcher call; [eventName] and [data] are what the
     * headless task needs, and are the same names `EventDispatcher.fallback`
     * uses so the headless side sees one vocabulary.
     */
    private inline fun fanOut(
        eventName: String,
        data: Map<String, Any?>,
        send: (EventDispatcher) -> Unit,
    ) {
        val members = dispatchers
        if (members.any { it.canReceive }) {
            if (routingToHeadless.compareAndSet(true, false)) {
                TraceletLog.lifecycle(
                    "engines: a Flutter engine can receive events again — " +
                        "headless routing stopped (#371)",
                )
            }
            members.forEach(send)
            return
        }

        val fallback = headlessFallback
        if (fallback == null) {
            // No primary has attached in this process yet, so there is no
            // HeadlessTaskService to route to. Let the members fall back
            // individually, exactly as before.
            if (members.isEmpty()) {
                if (routingToHeadless.compareAndSet(false, true)) {
                    TraceletLog.lifecycle(
                        "engines: '$eventName' dispatched into an empty fan-out with " +
                            "no headless fallback wired — delivery is being lost (#371)",
                    )
                }
            }
            members.forEach(send)
            return
        }

        if (routingToHeadless.compareAndSet(false, true)) {
            TraceletLog.lifecycle(
                "engines: no attached engine can receive events (fan-out " +
                    "size=${members.size}) — routing to the headless task (#371)",
            )
        }
        fallback(eventName, data)
    }

    override fun sendLocation(data: Map<String, Any?>) = fanOut("location", data) { it.sendLocation(data) }
    override fun sendMotionChange(data: Map<String, Any?>) = fanOut("motionchange", data) { it.sendMotionChange(data) }
    override fun sendSpeedMotionChange(data: Map<String, Any?>) = fanOut("speedmotionchange", data) { it.sendSpeedMotionChange(data) }
    override fun sendActivityChange(data: Map<String, Any?>) = fanOut("activitychange", data) { it.sendActivityChange(data) }
    override fun sendProviderChange(data: Map<String, Any?>) = fanOut("providerchange", data) { it.sendProviderChange(data) }
    override fun sendGeofence(data: Map<String, Any?>) = fanOut("geofence", data) { it.sendGeofence(data) }
    override fun sendGeofencesChange(data: Map<String, Any?>) = fanOut("geofenceschange", data) { it.sendGeofencesChange(data) }
    override fun sendHeartbeat(data: Map<String, Any?>) = fanOut("heartbeat", data) { it.sendHeartbeat(data) }
    override fun sendHttp(data: Map<String, Any?>) = fanOut("http", data) { it.sendHttp(data) }
    override fun sendSchedule(data: Map<String, Any?>) = fanOut("schedule", data) { it.sendSchedule(data) }
    override fun sendPowerSaveChange(isPowerSaveMode: Boolean) =
        fanOut("powersavechange", mapOf("value" to isPowerSaveMode)) { it.sendPowerSaveChange(isPowerSaveMode) }
    override fun sendConnectivityChange(data: Map<String, Any?>) = fanOut("connectivitychange", data) { it.sendConnectivityChange(data) }
    override fun sendEnabledChange(enabled: Boolean) =
        fanOut("enabledchange", mapOf("value" to enabled)) { it.sendEnabledChange(enabled) }
    override fun sendNotificationAction(action: String) =
        fanOut("notificationaction", mapOf("value" to action)) { it.sendNotificationAction(action) }
    override fun sendAuthorization(data: Map<String, Any?>) = fanOut("authorization", data) { it.sendAuthorization(data) }
    override fun sendWatchPosition(data: Map<String, Any?>) = fanOut("watchposition", data) { it.sendWatchPosition(data) }

    override fun sendRemoteConfigEvent(data: Map<String, Any?>) = fanOut("remoteconfig", data) { it.sendRemoteConfigEvent(data) }
    override fun sendTrip(data: Map<String, Any?>) = fanOut("trip", data) { it.sendTrip(data) }
    override fun sendBudgetAdjustment(data: Map<String, Any?>) = fanOut("budgetadjustment", data) { it.sendBudgetAdjustment(data) }
    override fun sendDrivingEvent(data: Map<String, Any?>) = fanOut("drivingevent", data) { it.sendDrivingEvent(data) }
    override fun sendImpact(data: Map<String, Any?>) = fanOut("impact", data) { it.sendImpact(data) }
    override fun sendModeChange(data: Map<String, Any?>) = fanOut("modechange", data) { it.sendModeChange(data) }
    override fun sendCrashModelStatus(data: Map<String, Any?>) = fanOut("crashmodelstatus", data) { it.sendCrashModelStatus(data) }

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

    /**
     * Messenger of a secondary **UI** engine that has not yet shown that its
     * Dart side listens for events (#364).
     *
     * Non-null only between this engine's attach and the
     * [onDartEventsSubscribed] handshake that lets it join the fan-out; null on
     * the primary instance and on every headless engine, both of which must
     * never take this path.
     */
    @Volatile private var pendingUiMessenger: BinaryMessenger? = null

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
                dispatchToHeadless(hs, eventName, eventData)
            }

            // The same route, one level up (#371). The per-dispatcher fallback
            // above can only fire while this dispatcher is *in* the fan-out, and
            // on task removal it is the first thing removed — leaving a composite
            // with no members, whose `forEach` drops every event in silence when
            // another plugin's background engine keeps the process alive. Wiring
            // the composite to the same HeadlessTaskService instance matters:
            // that object owns the spawn-in-flight guard and the pending-event
            // queue, so both routes feed one engine rather than racing two.
            globalEventSender.headlessFallback = { eventName, eventData ->
                dispatchToHeadless(hs, eventName, eventData)
            }

            TraceletBootstrap.headlessDispatcherFactory = { ctx -> HeadlessTaskService(ctx) }
            TraceletBootstrap.eventSenderFactory = { ctx ->
                val dispatcher = EventDispatcher()
                val h = HeadlessTaskService(ctx)
                dispatcher.headlessFallback = { name, data ->
                    dispatchToHeadless(h, name, data)
                }
                dispatcher
            }
        } else {
            // Secondary engine — either an in-process UI engine (EngineGroup,
            // e.g. flutter_overlay_window) or a headless background isolate.
            // The two must be handled differently (see below).
            //
            // The attach *thread* cannot tell them apart, though it looks like it
            // can: Flutter requires FlutterEngine to be constructed on the main
            // looper, so a headless spawn attaches from the main thread too and a
            // thread check calls it a UI engine. (requestSyncBody's isMainThread()
            // check is sound — it runs on a background sync thread, a different
            // situation.) What is exact is the flag HeadlessTaskService already
            // sets around the FlutterEngine constructor, which is precisely the
            // call that triggers this attach (#358).
            val isUiEngine = !HeadlessTaskService.isSpawningHeadlessEngine
            // On the always-on lifecycle channel (#318), not DEBUG: this decides
            // which component delivers every subsequent event, it is taken in the
            // killed state, and when it goes wrong the only symptom is silence —
            // exactly the report that arrives from a release build whose logLevel
            // may be `error` or `off`, which drops DEBUG. Engine attaches are a
            // handful per process (the headless spawn beside it is already
            // lifecycle), so the row budget is unaffected (#358).
            val kind = if (isUiEngine) "UI" else "headless"
            val delivery = if (isUiEngine) {
                "delivered to it once its Dart side subscribes"
            } else {
                "routed to the headless task"
            }
            TraceletLog.lifecycle(
                "engines: secondary attach — $kind (engineCount=$count); " +
                    "events $delivery"
            )

            eventDispatcher = EventDispatcher()

            if (isUiEngine) {
                // A real UI engine can display events — but only if its Dart
                // side is actually listening, and "not spawned by us" is not
                // evidence that it is. Any plugin may create a FlutterEngine in
                // this process (firebase_messaging's background message service,
                // flutter_local_notifications, background_downloader…), plugin
                // auto-registration attaches Tracelet to it, and none of those
                // isolates ever calls `Tracelet.onLocation`. Registering such an
                // engine here gave its dispatcher a non-null Pigeon `eventApi`,
                // which `EventDispatcher` reads as "a Flutter engine can receive
                // this" — so every event was posted into an isolate with no
                // listeners instead of falling through to `headlessFallback`,
                // and after task removal the app got nothing at all for the rest
                // of the process (#364, the foreign-engine half of #358).
                //
                // So hold the messenger and wait for evidence:
                // [onDartEventsSubscribed] fires when this engine's Dart side
                // registers its Pigeon event receiver, which is exactly the
                // moment it becomes able to receive. An engine that never
                // subscribes never joins the fan-out, and events keep reaching
                // the registered headless task. Waiting costs nothing: before
                // Dart subscribes there is no handler on the other end, so the
                // events this defers were being dropped by the engine anyway.
                pendingUiMessenger = binding.binaryMessenger
                primaryInstance?.headlessService?.let { hs ->
                    eventDispatcher.headlessFallback = { name, data ->
                        dispatchToHeadless(hs, name, data)
                    }
                }
            } else {
                // A headless engine must NOT join the event fan-out. Registering
                // its Pigeon event API gives the dispatcher a non-null `eventApi`,
                // and `EventDispatcher` treats that as "a Flutter engine can
                // receive this" — so every subsequent event took the engine
                // branch and was posted into an isolate with no `onGeofence`
                // listener, instead of falling through to `headlessFallback`.
                //
                // The headless isolate receives events through
                // `HeadlessTaskService.dispatchEvent`, a different channel
                // entirely. So one transient headless engine — spawned for a
                // sync body, say — permanently swallowed every geofence
                // crossing in that process: logged, persisted and synced
                // natively, but never delivered to the registered headless
                // task, and therefore invisible to the app (#358).
            }
        }

        // Pigeon API: register on EVERY engine.
        val apiHeadless = headlessService ?: HeadlessTaskService(context)
        TraceletHostApi.setUp(
            binding.binaryMessenger,
            // The HostApi is set up per messenger, so a call arriving on this
            // one came from *this* engine's Dart side — which is what makes
            // `requestStateFlush` usable as the per-engine subscription
            // handshake (#364).
            TraceletHostApiImpl(context, apiHeadless, ::onDartEventsSubscribed),
        )
    }

    /**
     * This engine's Dart side registered its Pigeon event receiver (#364).
     *
     * `PigeonTracelet._ensureEventsRegistered()` calls `requestStateFlush()`
     * once per isolate, immediately after `TraceletEventApi.setUp(...)`, on the
     * first access to any event stream — so this is the native side's only
     * evidence that a given engine can actually receive events, rather than
     * merely existing.
     *
     * Only a secondary UI engine waiting in [pendingUiMessenger] acts on it:
     *
     * - the **primary** already registered at attach and is unaffected — its
     *   dispatcher must be live before Dart subscribes, since `ready()` and the
     *   state flush it triggers both run through it;
     * - a **headless** engine leaves [pendingUiMessenger] null and is ignored
     *   here, so an app whose headless task subscribes to a stream cannot pull
     *   the headless engine into the fan-out and re-break #358.
     *
     * Idempotent: `_eventsRegistered` makes Dart send this once per isolate,
     * but a re-entrant or duplicated call must not double-register, so the
     * messenger is consumed under the lock and `addIfAbsent` guards the fan-out.
     */
    @Synchronized
    internal fun onDartEventsSubscribed() {
        val messenger = pendingUiMessenger ?: return
        pendingUiMessenger = null
        eventDispatcher.register(messenger)
        globalEventSender.add(eventDispatcher)
        // Lifecycle, not debug, for the same reason the attach decision above is
        // (#318/#358): this is the moment a secondary engine starts receiving
        // events, and its absence from a report is the finding.
        TraceletLog.lifecycle(
            "engines: secondary UI engine subscribed — joining the event " +
                "fan-out (#364)"
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val count = attachedEngineCount.decrementAndGet()
        sdk.logger.debug("onDetachedFromEngine: remainingEngines=$count")
        
        isEngineAttached = false
        TraceletHostApi.setUp(binding.binaryMessenger, null)
        // A secondary UI engine that detached before its Dart side ever
        // subscribed must not be able to join the fan-out afterwards on a late
        // handshake, holding a messenger whose engine is gone (#364).
        pendingUiMessenger = null

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
        // Complete an in-flight Pigeon permission reply before losing the
        // Activity listener that is otherwise its only completion path.
        sdk.clearPendingPermissionCallback()
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
