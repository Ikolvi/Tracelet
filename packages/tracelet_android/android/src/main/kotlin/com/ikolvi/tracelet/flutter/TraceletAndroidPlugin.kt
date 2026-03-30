package com.ikolvi.tracelet.flutter

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import com.ikolvi.tracelet.sdk.TraceletBootstrap
import com.ikolvi.tracelet.sdk.TraceletSdk
import com.ikolvi.tracelet.TraceletHostApi
import com.ikolvi.tracelet.flutter.service.HeadlessTaskService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
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

    private lateinit var context: Context
    private lateinit var eventDispatcher: EventDispatcher
    private lateinit var headlessService: HeadlessTaskService

    private var activityBinding: ActivityPluginBinding? = null

    private val sdk: TraceletSdk get() = TraceletSdk.getInstance(context)

    // =========================================================================
    // FlutterPlugin lifecycle
    // =========================================================================

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext

        // Event dispatcher (Pigeon FlutterApi → Dart)
        eventDispatcher = EventDispatcher()
        eventDispatcher.register(binding.binaryMessenger)

        // Inject event sender and initialize SDK
        sdk.setEventSender(eventDispatcher)
        sdk.initialize()

        // Flutter-specific: headless task service
        headlessService = HeadlessTaskService(context, sdk.configManager)

        // Wire 401 → headless headers refresh
        sdk.httpSyncManager.onAuthorizationRequired = {
            headlessService.requestHeadersRefresh(10_000L)
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
        TraceletHostApi.setUp(binding.binaryMessenger, null)
        eventDispatcher.unregister()
        sdk.destroyAll()
        headlessService.destroy()
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
        val pendingCallback = sdk.pendingPermissionCallback
        sdk.pendingPermissionCallback = null
        pendingCallback?.invoke(sdk.getPermissionStatus())
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
