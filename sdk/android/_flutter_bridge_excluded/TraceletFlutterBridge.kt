package com.tracelet.tracelet_android

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import com.ikolvi.tracelet.sdk.TraceletBootstrap
import com.ikolvi.tracelet.sdk.TraceletSdk
import com.ikolvi.tracelet.sdk.location.PeriodicLocationWorker
import com.ikolvi.tracelet.sdk.service.LocationService
import com.ikolvi.tracelet.sdk.util.OemCompat
import com.ikolvi.tracelet.sdk.util.TraceletPermissionManager
import com.tracelet.tracelet_android.service.HeadlessTaskService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/**
 * Thin Flutter bridge for the Tracelet SDK.
 *
 * Delegates all business logic to [TraceletSdk]. This class is responsible
 * only for Flutter-specific concerns:
 * - MethodChannel handling (Dart → SDK)
 * - EventChannel dispatching (SDK → Dart) via [EventDispatcher]
 * - HeadlessTaskService (background Dart isolate)
 * - Activity lifecycle & permission delegation
 */
class TraceletAndroidPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var eventDispatcher: EventDispatcher
    private lateinit var sdk: TraceletSdk

    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPermissionResult: Result? = null
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }

    // =========================================================================
    // FlutterPlugin lifecycle
    // =========================================================================

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        sdk = TraceletSdk.getInstance(context)

        // Register bootstrap factories for headless/boot-restart scenarios
        TraceletBootstrap.eventSenderFactory = { ctx ->
            EventDispatcher()
        }
        TraceletBootstrap.headlessDispatcherFactory = { ctx ->
            HeadlessTaskService(ctx)
        }

        // MethodChannel
        channel = MethodChannel(binding.binaryMessenger, "com.tracelet/methods")
        channel.setMethodCallHandler(this)

        // EventChannels — SDK events → Dart
        eventDispatcher = EventDispatcher()
        eventDispatcher.register(binding.binaryMessenger)

        // Wire SDK → EventDispatcher (Flutter EventChannels)
        sdk.setListener(null) // Clear any previous listener
        // The EventDispatcher is the TraceletEventSender for the Flutter bridge
        // We need to wire it into the SDK's internal event sender

        // Wire headless fallback
        val headlessService = HeadlessTaskService(context)
        eventDispatcher.headlessFallback = { eventName, eventData ->
            if (headlessService.isRegistered()) {
                headlessService.dispatchEvent(eventName, eventData)
            }
        }

        // Re-wire for periodic mode if active
        if (sdk.getState()["enabled"] == true && sdk.getState()["trackingMode"] == 2) {
            PeriodicLocationWorker.eventSender = eventDispatcher
            PeriodicLocationWorker.httpSyncManager = sdk.httpSyncManager
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventDispatcher.unregister()
    }

    // =========================================================================
    // ActivityAware lifecycle
    // =========================================================================

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
        sdk.setActivity(binding.activity)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
        sdk.setActivity(null)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
        sdk.setActivity(binding.activity)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
        sdk.setActivity(null)
    }

    // =========================================================================
    // MethodCallHandler — routes Dart calls to SDK
    // =========================================================================

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            // Lifecycle
            "ready" -> {
                @Suppress("UNCHECKED_CAST")
                val config = call.arguments as? Map<String, Any?> ?: emptyMap()
                result.success(sdk.ready(config))
            }
            "start" -> result.success(sdk.start())
            "stop" -> result.success(sdk.stop())
            "startPeriodic" -> result.success(sdk.startPeriodic())
            "startGeofences" -> result.success(sdk.startGeofences())
            "getState" -> result.success(sdk.getState())
            "setConfig" -> {
                @Suppress("UNCHECKED_CAST")
                val config = call.arguments as? Map<String, Any?> ?: emptyMap()
                result.success(sdk.setConfig(config))
            }
            "reset" -> {
                @Suppress("UNCHECKED_CAST")
                val config = call.arguments as? Map<String, Any?>
                result.success(sdk.reset(config))
            }

            // Location
            "getCurrentPosition" -> {
                @Suppress("UNCHECKED_CAST")
                val options = call.arguments as? Map<String, Any?> ?: emptyMap()
                result.success(sdk.getCurrentPosition(options))
            }
            "getOdometer" -> result.success(sdk.locationEngine.getOdometer())
            "setOdometer" -> {
                val value = (call.arguments as? Number)?.toDouble() ?: 0.0
                result.success(sdk.locationEngine.setOdometer(value))
            }
            "changePace" -> {
                val isMoving = call.arguments as? Boolean ?: false
                sdk.locationEngine.changePace(isMoving)
                result.success(sdk.getState())
            }

            // Geofencing
            "addGeofence" -> {
                @Suppress("UNCHECKED_CAST")
                val geofence = call.arguments as? Map<String, Any?> ?: emptyMap()
                sdk.addGeofences(listOf(geofence))
                result.success(true)
            }
            "addGeofences" -> {
                @Suppress("UNCHECKED_CAST")
                val geofences = (call.arguments as? List<*>)
                    ?.filterIsInstance<Map<String, Any?>>() ?: emptyList()
                sdk.addGeofences(geofences)
                result.success(true)
            }
            "removeGeofence" -> {
                val id = call.arguments as? String ?: ""
                sdk.removeGeofences(listOf(id))
                result.success(true)
            }
            "removeGeofences" -> {
                sdk.removeGeofences(emptyList())
                result.success(true)
            }
            "getGeofences" -> result.success(sdk.geofenceManager.getGeofences())

            // Persistence
            "getLocations" -> result.success(sdk.getLocations())
            "getCount" -> result.success(sdk.getCount())
            "destroyLocations" -> result.success(sdk.destroyLocations())

            // HTTP Sync
            "sync" -> result.success(sdk.sync())

            // Permissions
            "getPermissionStatus" -> result.success(
                sdk.permissionManager.getAuthorizationStatus(activity)
            )
            "requestPermission" -> handleRequestPermission(result)
            "isPowerSaveMode" -> result.success(sdk.permissionManager.isPowerSaveMode())

            // Utility
            "getProviderState" -> result.success(sdk.locationEngine.buildProviderState())
            "getSensors" -> result.success(sdk.motionDetector.getSensors())
            "getDeviceInfo" -> result.success(getDeviceInfo())
            "playSound" -> {
                val name = call.arguments as? String ?: ""
                result.success(sdk.soundManager.playSound(name))
            }

            // OEM compatibility
            "getSettingsHealth" -> result.success(OemCompat.getSettingsHealth(context))

            // Headless
            "registerHeadlessTask" -> {
                val callbackId = (call.arguments as? List<*>)?.firstOrNull() as? Long
                if (callbackId != null) {
                    HeadlessTaskService.registerCallback(context, callbackId)
                }
                result.success(true)
            }

            // Enterprise
            "verifyAuditTrail" -> result.success(sdk.auditTrailManager.verifyChain())
            "isDatabaseEncrypted" -> result.success(sdk.encryptionManager.isDatabaseEncrypted())
            "getAttestationToken" -> {
                sdk.deviceAttestor.requestToken { token ->
                    mainHandler.post { result.success(token) }
                }
            }
            "getDeadReckoningState" -> result.success(sdk.locationEngine.getDeadReckoningState())

            // Logging
            "getLog" -> {
                @Suppress("UNCHECKED_CAST")
                val query = call.arguments as? Map<String, Any?>
                result.success(sdk.logger.getLog(query))
            }
            "destroyLog" -> result.success(sdk.logger.destroyLog())

            "getPlatformVersion" -> result.success("Android ${Build.VERSION.RELEASE}")

            else -> result.notImplemented()
        }
    }

    // =========================================================================
    // Permissions
    // =========================================================================

    private fun handleRequestPermission(result: Result) {
        if (activity == null) {
            result.error("NO_ACTIVITY", "No activity available for permission request", null)
            return
        }
        pendingPermissionResult = result
        sdk.permissionManager.requestLocationPermission(activity!!)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        val result = pendingPermissionResult ?: return false
        pendingPermissionResult = null

        val status = sdk.permissionManager.getAuthorizationStatus(activity)
        result.success(status)
        return true
    }

    // =========================================================================
    // Utility
    // =========================================================================

    private fun getDeviceInfo(): Map<String, Any?> {
        return mapOf(
            "model" to Build.MODEL,
            "manufacturer" to Build.MANUFACTURER,
            "version" to Build.VERSION.RELEASE,
            "platform" to "android",
            "framework" to "flutter",
            "sdkVersion" to Build.VERSION.SDK_INT,
        )
    }
}
