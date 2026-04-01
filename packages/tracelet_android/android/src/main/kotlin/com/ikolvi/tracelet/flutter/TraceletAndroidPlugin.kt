package com.ikolvi.tracelet.flutter

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.ikolvi.tracelet.sdk.TraceletBootstrap
import com.ikolvi.tracelet.sdk.TraceletSdk
import com.ikolvi.tracelet.sdk.http.HttpSyncManager
import com.ikolvi.tracelet.TraceletHostApi
import com.ikolvi.tracelet.flutter.service.HeadlessTaskService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * TraceletAndroidPlugin — Slim Flutter bridge for Tracelet.
 *
 * All engine logic lives in [TraceletSdk]. This class only handles:
 * - Flutter plugin lifecycle (attach/detach)
 * - EventDispatcher creation & injection (Pigeon FlutterApi)
 * - Pigeon HostApi registration
 * - Activity lifecycle & permission result forwarding
 * - Flutter-specific: headless tasks, emailLog, device info
 */
class TraceletAndroidPlugin :
    FlutterPlugin,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    companion object {
        private const val TAG = "TraceletAndroidPlugin"
        /** Timeout for Dart callback round-trips (headers refresh, sync body). */
        private const val DART_CALLBACK_TIMEOUT_MS = 10_000L

        /**
         * Reference to the primary (foreground) plugin instance.
         *
         * When a headless [FlutterEngine] is created (e.g., by
         * [HeadlessTaskService]), [GeneratedPluginRegistrant] registers
         * all plugins on that engine, triggering a second
         * [onAttachedToEngine] on a NEW plugin instance. That instance
         * must NOT overwrite the [httpSyncManager] callbacks — those
         * belong to the foreground engine's MethodChannel.
         */
        @Volatile
        @JvmStatic
        private var primaryInstance: TraceletAndroidPlugin? = null
    }

    private lateinit var context: Context
    private lateinit var eventDispatcher: EventDispatcher
    private lateinit var headlessService: HeadlessTaskService

    private var activityBinding: ActivityPluginBinding? = null
    private var syncBodyChannel: MethodChannel? = null
    @Volatile private var isEngineAttached = false

    private val sdk: TraceletSdk get() = TraceletSdk.getInstance(context)

    // =========================================================================
    // FlutterPlugin lifecycle
    // =========================================================================

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        isEngineAttached = true

        // Event dispatcher (Pigeon FlutterApi → Dart)
        eventDispatcher = EventDispatcher()
        eventDispatcher.register(binding.binaryMessenger)

        // Inject event sender and initialize SDK
        sdk.setEventSender(eventDispatcher)
        sdk.initialize()

        // Flutter-specific: headless task service
        headlessService = HeadlessTaskService(context, sdk.configManager)

        // ── Foreground-only callback wiring ──────────────────────────────
        // When HeadlessTaskService creates a headless FlutterEngine,
        // GeneratedPluginRegistrant registers ALL plugins on that engine,
        // which triggers onAttachedToEngine on a NEW plugin instance.
        // That instance's MethodChannel is connected to the HEADLESS Dart
        // isolate, not the main one where the user's callback handler
        // lives. If the headless instance overwrites httpSyncManager
        // callbacks, MethodChannel messages go to the wrong isolate and
        // time out (10s) before falling back to the headless service.
        //
        // Guard: Only the first (primary/foreground) instance wires
        // callbacks. A second call with the SAME instance (hot restart /
        // double registration) is allowed.
        val isPrimary = primaryInstance == null || primaryInstance === this
        if (isPrimary) {
            primaryInstance = this

            val mainHandler = Handler(Looper.getMainLooper())
            syncBodyChannel = MethodChannel(binding.binaryMessenger, "com.tracelet/sync_body")

            // Wire 401 → foreground token refresh, headless fallback
            HttpSyncManager.onAuthorizationRequired = {
                // Try foreground engine first
                if (isEngineAttached && Looper.myLooper() != Looper.getMainLooper()) {
                    val refreshed = requestTokenRefreshFromDart(mainHandler)
                    if (refreshed) {
                        true
                    } else {
                        // Fallback to headless service
                        headlessService.requestHeadersRefresh(DART_CALLBACK_TIMEOUT_MS)
                    }
                } else {
                    headlessService.requestHeadersRefresh(DART_CALLBACK_TIMEOUT_MS)
                }
            }

            HttpSyncManager.onRequestFreshHeaders = {
                // Try foreground engine first
                if (isEngineAttached && Looper.myLooper() != Looper.getMainLooper()) {
                    val refreshed = requestFreshHeadersFromDart(mainHandler)
                    if (!refreshed) {
                        // Fallback to headless service
                        headlessService.requestHeadersRefresh(DART_CALLBACK_TIMEOUT_MS)
                    }
                } else {
                    headlessService.requestHeadersRefresh(DART_CALLBACK_TIMEOUT_MS)
                }
            }

            // Wire custom sync body builder (foreground → MethodChannel, headless → fallback)
            HttpSyncManager.onBuildCustomSyncBody = buildCustomSyncBodyCallback@{ locations ->
                // Try foreground engine first
                if (isEngineAttached && Looper.myLooper() != Looper.getMainLooper()) {
                    val result = requestSyncBodyFromDart(mainHandler, locations)
                    if (result != null) return@buildCustomSyncBodyCallback result
                }
                // Fallback to headless service
                headlessService.requestCustomSyncBody(locations, DART_CALLBACK_TIMEOUT_MS)
            }

            Log.d(TAG, "onAttachedToEngine: primary instance — callbacks wired")
        } else {
            Log.d(TAG, "onAttachedToEngine: secondary (headless) instance — skipping callback wiring")
        }

        // Wire headless fallback for background events
        eventDispatcher.headlessFallback = { eventName, eventData ->
            if (headlessService.isRegistered()) {
                headlessService.dispatchEvent(eventName, eventData)
            }
        }

        // Bootstrap factory for headless dispatcher
        TraceletBootstrap.headlessDispatcherFactory = { ctx ->
            HeadlessTaskService(ctx)
        }

        // Override event sender factory so boot/task-removal restarts
        // produce an EventDispatcher with headlessFallback properly wired.
        // Without this, geofence events fired after task removal are
        // silently dropped because the EventDispatcher has no fallback.
        TraceletBootstrap.eventSenderFactory = { ctx ->
            val dispatcher = EventDispatcher()
            val hs = HeadlessTaskService(ctx)
            dispatcher.headlessFallback = { eventName, eventData ->
                if (hs.isRegistered()) {
                    hs.dispatchEvent(eventName, eventData)
                }
            }
            dispatcher
        }

        // Pigeon API: register type-safe host API
        TraceletHostApi.setUp(
            binding.binaryMessenger,
            TraceletHostApiImpl(context, headlessService),
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        isEngineAttached = false
        syncBodyChannel = null
        if (primaryInstance === this) {
            primaryInstance = null
            HttpSyncManager.onAuthorizationRequired = null
            HttpSyncManager.onRequestFreshHeaders = null
            HttpSyncManager.onBuildCustomSyncBody = null
        }
        TraceletHostApi.setUp(binding.binaryMessenger, null)
        eventDispatcher.unregister()
        sdk.destroyAll()
        headlessService.destroy()
    }

    // =========================================================================
    // Custom Sync Body (foreground MethodChannel)
    // =========================================================================

    /**
     * Request a custom sync body from Dart via the foreground FlutterEngine.
     *
     * Invokes `buildSyncBody` on `com.tracelet/sync_body` MethodChannel and
     * blocks on a CountDownLatch until Dart responds. Runs on the sync
     * executor thread — must NOT be called on the main thread.
     */
    private fun requestSyncBodyFromDart(
        mainHandler: Handler,
        locations: List<Map<String, Any?>>,
    ): String? {
        val channel = syncBodyChannel ?: return null
        val latch = java.util.concurrent.CountDownLatch(1)
        var result: String? = null

        mainHandler.post {
            channel.invokeMethod(
                "buildSyncBody",
                locations,
                object : MethodChannel.Result {
                    override fun success(r: Any?) {
                        result = r as? String
                        latch.countDown()
                    }
                    override fun error(code: String, msg: String?, details: Any?) {
                        Log.w(TAG, "buildSyncBody Dart error: $code — $msg")
                        latch.countDown()
                    }
                    override fun notImplemented() {
                        latch.countDown()
                    }
                },
            )
        }

        val completed = latch.await(DART_CALLBACK_TIMEOUT_MS, java.util.concurrent.TimeUnit.MILLISECONDS)
        if (!completed) {
            Log.w(TAG, "buildSyncBody timed out waiting for Dart response")
        }
        return result
    }

    // =========================================================================
    // Fresh Headers (foreground MethodChannel)
    // =========================================================================

    /**
     * Request fresh headers from Dart via the foreground FlutterEngine.
     *
     * Invokes `requestFreshHeaders` on `com.tracelet/sync_body` MethodChannel.
     * Dart's handler calls _headersCallback → setDynamicHeaders, updating
     * ConfigManager before the sync request proceeds.
     *
     * Blocks on a CountDownLatch — must NOT be called on the main thread.
     */
    private fun requestFreshHeadersFromDart(mainHandler: Handler): Boolean {
        val channel = syncBodyChannel ?: return false
        val latch = java.util.concurrent.CountDownLatch(1)
        var success = false

        mainHandler.post {
            channel.invokeMethod(
                "requestFreshHeaders",
                null,
                object : MethodChannel.Result {
                    override fun success(r: Any?) {
                        success = (r as? Boolean) ?: false
                        latch.countDown()
                    }
                    override fun error(code: String, msg: String?, details: Any?) {
                        Log.w(TAG, "requestFreshHeaders Dart error: $code — $msg")
                        latch.countDown()
                    }
                    override fun notImplemented() {
                        Log.w(TAG, "requestFreshHeaders: Dart handler not registered")
                        latch.countDown()
                    }
                },
            )
        }

        val completed = latch.await(DART_CALLBACK_TIMEOUT_MS, java.util.concurrent.TimeUnit.MILLISECONDS)
        if (!completed) {
            Log.w(TAG, "requestFreshHeaders timed out after ${DART_CALLBACK_TIMEOUT_MS}ms")
        }
        return success
    }

    // =========================================================================
    // Token Refresh — 401 recovery (foreground MethodChannel)
    // =========================================================================

    /**
     * Request a token refresh from Dart via the foreground FlutterEngine.
     *
     * Invokes `requestTokenRefresh` on `com.tracelet/sync_body` MethodChannel.
     * Dart's handler calls _tokenRefreshCallback (which should refresh the
     * token from the auth API) → setDynamicHeaders, updating ConfigManager.
     *
     * Blocks on a CountDownLatch — must NOT be called on the main thread.
     */
    private fun requestTokenRefreshFromDart(mainHandler: Handler): Boolean {
        val channel = syncBodyChannel ?: return false
        val latch = java.util.concurrent.CountDownLatch(1)
        var success = false

        mainHandler.post {
            channel.invokeMethod(
                "requestTokenRefresh",
                null,
                object : MethodChannel.Result {
                    override fun success(r: Any?) {
                        success = (r as? Boolean) ?: false
                        latch.countDown()
                    }
                    override fun error(code: String, msg: String?, details: Any?) {
                        Log.w(TAG, "requestTokenRefresh Dart error: $code — $msg")
                        latch.countDown()
                    }
                    override fun notImplemented() {
                        latch.countDown()
                    }
                },
            )
        }

        val completed = latch.await(DART_CALLBACK_TIMEOUT_MS, java.util.concurrent.TimeUnit.MILLISECONDS)
        if (!completed) {
            Log.w(TAG, "requestTokenRefresh timed out waiting for Dart response")
        }
        return success
    }

    // =========================================================================
    // ActivityAware lifecycle
    // =========================================================================

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        sdk.activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        sdk.activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        sdk.activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        // Invoke and clear any pending permission callback so the Dart
        // Future doesn't hang forever when the Activity is destroyed
        // while a permission dialog is showing.
        sdk.clearPendingPermissionCallback()
        sdk.activity = null
    }

    // =========================================================================
    // Permission result forwarding
    // =========================================================================

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        return sdk.handlePermissionResult(requestCode, permissions, grantResults)
    }
}
