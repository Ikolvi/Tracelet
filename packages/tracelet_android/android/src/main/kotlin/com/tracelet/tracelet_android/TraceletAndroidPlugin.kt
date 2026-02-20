package com.tracelet.tracelet_android

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.tracelet.tracelet_android.db.TraceletDatabase
import com.tracelet.tracelet_android.geofence.GeofenceManager
import com.tracelet.tracelet_android.http.HttpSyncManager
import com.tracelet.tracelet_android.location.LocationEngine
import com.tracelet.tracelet_android.motion.MotionDetector
import com.tracelet.tracelet_android.receiver.BootReceiver
import com.tracelet.tracelet_android.receiver.GeofenceBroadcastReceiver
import com.tracelet.tracelet_android.schedule.ScheduleManager
import com.tracelet.tracelet_android.service.HeadlessTaskService
import com.tracelet.tracelet_android.service.LocationService
import com.tracelet.tracelet_android.util.*
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * TraceletAndroidPlugin — Full Android implementation of the Tracelet plugin.
 *
 * Wires together all subsystems:
 * - ConfigManager / StateManager (persistence)
 * - LocationEngine (FusedLocationProviderClient)
 * - LocationService (foreground service)
 * - MotionDetector (activity recognition + accelerometer)
 * - GeofenceManager (GeofencingClient)
 * - TraceletDatabase (SQLite)
 * - HttpSyncManager (OkHttp)
 * - HeadlessTaskService (background Dart execution)
 * - ScheduleManager (AlarmManager scheduling)
 * - TraceletLogger / SoundManager / PermissionManager
 * - EventDispatcher (15 EventChannels → Dart)
 */
class TraceletAndroidPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    // Core subsystems
    private lateinit var configManager: ConfigManager
    private lateinit var stateManager: StateManager
    private lateinit var eventDispatcher: EventDispatcher
    private lateinit var database: TraceletDatabase
    private lateinit var locationEngine: LocationEngine
    private lateinit var motionDetector: MotionDetector
    private lateinit var geofenceManager: GeofenceManager
    private lateinit var httpSyncManager: HttpSyncManager
    private lateinit var headlessService: HeadlessTaskService
    private lateinit var scheduleManager: ScheduleManager
    private lateinit var logger: TraceletLogger
    private lateinit var soundManager: SoundManager
    private lateinit var permissionManager: PermissionManager

    private var activity: Activity? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var heartbeatRunnable: Runnable? = null
    private var isReady = false

    // =========================================================================
    // FlutterPlugin lifecycle
    // =========================================================================

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext

        // MethodChannel
        channel = MethodChannel(binding.binaryMessenger, "com.tracelet/methods")
        channel.setMethodCallHandler(this)

        // EventChannels
        eventDispatcher = EventDispatcher()
        eventDispatcher.register(binding.binaryMessenger)

        // Persistence
        configManager = ConfigManager(context)
        stateManager = StateManager(context)
        database = TraceletDatabase.getInstance(context)

        // Logger
        logger = TraceletLogger(context, configManager, database)

        // Location
        locationEngine = LocationEngine(context, configManager, stateManager, eventDispatcher, database)

        // Motion
        motionDetector = MotionDetector(context, configManager, stateManager, eventDispatcher)
        motionDetector.onMotionStateChanged = { isMoving ->
            handleMotionStateChange(isMoving)
        }

        // Geofencing
        geofenceManager = GeofenceManager(context, configManager, eventDispatcher, database)
        GeofenceBroadcastReceiver.geofenceManager = geofenceManager

        // HTTP
        httpSyncManager = HttpSyncManager(context, configManager, eventDispatcher, database)

        // Headless
        headlessService = HeadlessTaskService(context)

        // Schedule
        scheduleManager = ScheduleManager(context, configManager, stateManager, eventDispatcher)
        scheduleManager.onScheduleStart = { handleScheduleStart() }
        scheduleManager.onScheduleStop = { handleScheduleStop() }

        // Sound
        soundManager = SoundManager(context, configManager)

        // Permissions
        permissionManager = PermissionManager(context)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventDispatcher.unregister()
        destroyAll()
    }

    // =========================================================================
    // ActivityAware lifecycle
    // =========================================================================

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    // =========================================================================
    // MethodCallHandler — handles ALL method calls from Dart
    // =========================================================================

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            // Lifecycle
            "ready" -> handleReady(call, result)
            "start" -> handleStart(result)
            "stop" -> handleStop(result)
            "startGeofences" -> handleStartGeofences(result)
            "getState" -> handleGetState(result)
            "setConfig" -> handleSetConfig(call, result)
            "reset" -> handleReset(call, result)

            // Location
            "getCurrentPosition" -> handleGetCurrentPosition(call, result)
            "watchPosition" -> handleWatchPosition(call, result)
            "stopWatchPosition" -> handleStopWatchPosition(call, result)
            "changePace" -> handleChangePace(call, result)
            "getOdometer" -> result.success(locationEngine.getOdometer())
            "setOdometer" -> {
                val value = (call.arguments as? Number)?.toDouble() ?: 0.0
                result.success(locationEngine.setOdometer(value))
            }

            // Geofencing
            "addGeofence" -> handleAddGeofence(call, result)
            "addGeofences" -> handleAddGeofences(call, result)
            "removeGeofence" -> {
                val id = call.arguments as? String ?: ""
                result.success(geofenceManager.removeGeofence(id))
            }
            "removeGeofences" -> result.success(geofenceManager.removeGeofences())
            "getGeofences" -> result.success(geofenceManager.getGeofences())
            "getGeofence" -> {
                val id = call.arguments as? String ?: ""
                result.success(geofenceManager.getGeofence(id))
            }
            "geofenceExists" -> {
                val id = call.arguments as? String ?: ""
                result.success(geofenceManager.geofenceExists(id))
            }

            // Persistence
            "getLocations" -> handleGetLocations(call, result)
            "getCount" -> result.success(database.getLocationCount())
            "destroyLocations" -> result.success(database.deleteAllLocations())
            "destroyLocation" -> {
                val uuid = call.arguments as? String ?: ""
                result.success(database.deleteLocation(uuid))
            }
            "insertLocation" -> handleInsertLocation(call, result)

            // HTTP Sync
            "sync" -> handleSync(result)

            // Utility
            "isPowerSaveMode" -> result.success(permissionManager.isPowerSaveMode())
            "requestPermission" -> result.success(permissionManager.requestPermission(activity))
            "requestTemporaryFullAccuracy" -> {
                // Android doesn't have temporary full accuracy (iOS-only concept)
                result.success(permissionManager.getAuthorizationStatus())
            }
            "getProviderState" -> result.success(locationEngine.buildProviderState())
            "getSensors" -> result.success(motionDetector.getSensors())
            "getDeviceInfo" -> result.success(getDeviceInfo())
            "playSound" -> {
                val name = call.arguments as? String ?: ""
                result.success(soundManager.playSound(name))
            }
            "isIgnoringBatteryOptimizations" ->
                result.success(permissionManager.isIgnoringBatteryOptimizations())
            "requestSettings" -> {
                val action = call.arguments as? String ?: ""
                result.success(handleRequestSettings(action))
            }
            "showSettings" -> {
                val action = call.arguments as? String ?: ""
                result.success(handleShowSettings(action))
            }

            // Background Tasks
            "startBackgroundTask" -> result.success(0) // Android doesn't need explicit BG tasks
            "stopBackgroundTask" -> result.success(call.arguments as? Int ?: 0)

            // Logging
            "getLog" -> {
                @Suppress("UNCHECKED_CAST")
                val query = call.arguments as? Map<String, Any?>
                result.success(logger.getLog(query))
            }
            "destroyLog" -> result.success(logger.destroyLog())
            "emailLog" -> handleEmailLog(call, result)
            "log" -> {
                val args = call.arguments as? List<*>
                val level = args?.firstOrNull() as? String ?: "INFO"
                val message = args?.lastOrNull() as? String ?: ""
                result.success(logger.log(level, message))
            }

            // Scheduling
            "startSchedule" -> handleStartSchedule(result)
            "stopSchedule" -> handleStopSchedule(result)

            // Headless
            "registerHeadlessTask" -> handleRegisterHeadlessTask(call, result)

            // Legacy
            "getPlatformVersion" -> result.success("Android ${Build.VERSION.RELEASE}")

            else -> result.notImplemented()
        }
    }

    // =========================================================================
    // Lifecycle handlers
    // =========================================================================

    private fun handleReady(call: MethodCall, result: Result) {
        @Suppress("UNCHECKED_CAST")
        val configMap = call.arguments as? Map<String, Any?> ?: emptyMap()

        // Merge config with defaults and persist
        val merged = configManager.setConfig(configMap)

        // Initialize subsystems
        if (configManager.isDebug()) soundManager.start()
        httpSyncManager.start()
        logger.pruneOldLogs()

        // Update boot receiver state
        updateBootReceiverState()

        isReady = true

        // Return current state including the merged config
        val stateMap = stateManager.toMap(merged)
        logger.info("ready() called")
        result.success(stateMap)
    }

    private fun handleStart(result: Result) {
        if (!isReady) {
            result.error("NOT_READY", "Call ready() before start()", null)
            return
        }

        stateManager.enabled = true
        stateManager.trackingMode = 0 // Location tracking
        stateManager.isMoving = configManager.getIsMoving()

        // Start foreground service
        LocationService.start(context)

        // Start location engine
        locationEngine.start()

        // Start motion detector
        motionDetector.start()

        // Start heartbeat
        startHeartbeat()

        // Fire enabledChange
        eventDispatcher.sendEnabledChange(true)

        logger.info("start() — tracking started")
        result.success(stateManager.toMap(configManager.getConfig()))
    }

    private fun handleStop(result: Result) {
        stateManager.enabled = false
        stateManager.isMoving = false

        // Stop all subsystems
        locationEngine.stop()
        motionDetector.stop()
        stopHeartbeat()

        // Stop foreground service
        LocationService.stop(context)

        // Fire enabledChange
        eventDispatcher.sendEnabledChange(false)

        logger.info("stop() — tracking stopped")
        result.success(stateManager.toMap(configManager.getConfig()))
    }

    private fun handleStartGeofences(result: Result) {
        if (!isReady) {
            result.error("NOT_READY", "Call ready() before startGeofences()", null)
            return
        }

        stateManager.enabled = true
        stateManager.trackingMode = 1 // Geofences only

        // Re-register all geofences
        geofenceManager.reRegisterAll()

        // Start foreground service (needed for background geofencing)
        LocationService.start(context)

        eventDispatcher.sendEnabledChange(true)

        logger.info("startGeofences() — geofence-only mode")
        result.success(stateManager.toMap(configManager.getConfig()))
    }

    private fun handleGetState(result: Result) {
        result.success(stateManager.toMap(configManager.getConfig()))
    }

    private fun handleSetConfig(call: MethodCall, result: Result) {
        @Suppress("UNCHECKED_CAST")
        val configMap = call.arguments as? Map<String, Any?> ?: emptyMap()
        val merged = configManager.setConfig(configMap)

        // Restart affected subsystems if currently tracking
        if (stateManager.enabled) {
            locationEngine.stop()
            locationEngine.start()
        }

        updateBootReceiverState()

        result.success(stateManager.toMap(merged))
    }

    private fun handleReset(call: MethodCall, result: Result) {
        // Stop everything
        locationEngine.destroy()
        motionDetector.stop()
        stopHeartbeat()
        geofenceManager.destroy()
        LocationService.stop(context)

        // Reset state
        stateManager.reset()

        // Reset config
        @Suppress("UNCHECKED_CAST")
        val newConfig = call.arguments as? Map<String, Any?>
        configManager.reset(newConfig)

        isReady = false

        logger.info("reset() — all subsystems reset")
        result.success(stateManager.toMap(configManager.getConfig()))
    }

    // =========================================================================
    // Location handlers
    // =========================================================================

    private fun handleGetCurrentPosition(call: MethodCall, result: Result) {
        @Suppress("UNCHECKED_CAST")
        val options = call.arguments as? Map<String, Any?> ?: emptyMap()

        locationEngine.getCurrentPosition(options) { location ->
            if (location != null) {
                result.success(location)
            } else {
                result.error("LOCATION_UNAVAILABLE", "Could not get current position", null)
            }
        }
    }

    private fun handleWatchPosition(call: MethodCall, result: Result) {
        @Suppress("UNCHECKED_CAST")
        val options = call.arguments as? Map<String, Any?> ?: emptyMap()
        val watchId = locationEngine.watchPosition(options)
        if (watchId >= 0) {
            result.success(watchId)
        } else {
            result.error("PERMISSION_DENIED", "Location permission not granted", null)
        }
    }

    private fun handleStopWatchPosition(call: MethodCall, result: Result) {
        val watchId = (call.arguments as? Number)?.toInt() ?: -1
        result.success(locationEngine.stopWatchPosition(watchId))
    }

    private fun handleChangePace(call: MethodCall, result: Result) {
        val isMoving = call.arguments as? Boolean ?: false
        result.success(locationEngine.changePace(isMoving))
    }

    // =========================================================================
    // Geofence handlers
    // =========================================================================

    private fun handleAddGeofence(call: MethodCall, result: Result) {
        @Suppress("UNCHECKED_CAST")
        val geofence = call.arguments as? Map<String, Any?> ?: run {
            result.error("INVALID_ARGS", "Expected geofence map", null)
            return
        }
        result.success(geofenceManager.addGeofence(geofence))
    }

    private fun handleAddGeofences(call: MethodCall, result: Result) {
        @Suppress("UNCHECKED_CAST")
        val geofences = call.arguments as? List<Map<String, Any?>> ?: run {
            result.error("INVALID_ARGS", "Expected list of geofence maps", null)
            return
        }
        result.success(geofenceManager.addGeofences(geofences))
    }

    // =========================================================================
    // Persistence handlers
    // =========================================================================

    private fun handleGetLocations(call: MethodCall, result: Result) {
        @Suppress("UNCHECKED_CAST")
        val query = call.arguments as? Map<String, Any?>
        val limit = (query?.get("limit") as? Number)?.toInt() ?: -1
        val offset = (query?.get("offset") as? Number)?.toInt() ?: 0
        val orderAsc = (query?.get("order") as? Number)?.toInt() != 1
        result.success(database.getLocations(limit, offset, orderAsc))
    }

    private fun handleInsertLocation(call: MethodCall, result: Result) {
        @Suppress("UNCHECKED_CAST")
        val params = call.arguments as? Map<String, Any?> ?: emptyMap()
        val uuid = database.insertLocation(params)
        httpSyncManager.onLocationInserted()
        result.success(uuid)
    }

    // =========================================================================
    // HTTP sync handler
    // =========================================================================

    private fun handleSync(result: Result) {
        httpSyncManager.sync { syncedLocations ->
            result.success(syncedLocations)
        }
    }

    // =========================================================================
    // Utility handlers
    // =========================================================================

    private fun getDeviceInfo(): Map<String, Any?> {
        return mapOf(
            "model" to Build.MODEL,
            "manufacturer" to Build.MANUFACTURER,
            "version" to Build.VERSION.RELEASE,
            "platform" to "android",
            "framework" to "flutter",
            "sdk" to Build.VERSION.SDK_INT,
        )
    }

    private fun handleRequestSettings(action: String): Boolean {
        return when (action) {
            "ignoreOptimizations" -> permissionManager.requestIgnoreBatteryOptimizations(activity)
            "location" -> permissionManager.showLocationSettings(activity)
            else -> false
        }
    }

    private fun handleShowSettings(action: String): Boolean {
        return when (action) {
            "location" -> permissionManager.showLocationSettings(activity)
            "app" -> permissionManager.showAppSettings(activity)
            else -> false
        }
    }

    private fun handleEmailLog(call: MethodCall, result: Result) {
        val email = call.arguments as? String ?: ""
        val logContent = logger.getLogForEmail()

        try {
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_EMAIL, arrayOf(email))
                putExtra(Intent.EXTRA_SUBJECT, "Tracelet Log")
                putExtra(Intent.EXTRA_TEXT, logContent)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    // =========================================================================
    // Schedule handlers
    // =========================================================================

    private fun handleStartSchedule(result: Result) {
        scheduleManager.start()
        result.success(stateManager.toMap(configManager.getConfig()))
    }

    private fun handleStopSchedule(result: Result) {
        scheduleManager.stop()
        result.success(stateManager.toMap(configManager.getConfig()))
    }

    // =========================================================================
    // Headless task handler
    // =========================================================================

    private fun handleRegisterHeadlessTask(call: MethodCall, result: Result) {
        val callbackIds = call.arguments as? List<*> ?: run {
            result.error("INVALID_ARGS", "Expected list of callback IDs", null)
            return
        }
        val registrationId = (callbackIds.getOrNull(0) as? Number)?.toLong() ?: -1L
        val dispatchId = (callbackIds.getOrNull(1) as? Number)?.toLong() ?: -1L

        headlessService.registerCallbacks(registrationId, dispatchId)
        result.success(true)
    }

    // =========================================================================
    // Motion state handling
    // =========================================================================

    private fun handleMotionStateChange(isMoving: Boolean) {
        logger.debug("Motion state changed: isMoving=$isMoving")
        stateManager.isMoving = isMoving

        if (isMoving) {
            // Restart location tracking
            locationEngine.start()
            soundManager.playMotionChange(true)
        } else {
            // Stop location tracking to conserve battery
            locationEngine.stop()
            soundManager.playMotionChange(false)
        }

        // Dispatch motionChange event with last known location
        val locationMap = locationEngine.getLastLocation()?.let { loc ->
            mapOf(
                "isMoving" to isMoving,
                "coords" to mapOf(
                    "latitude" to loc.latitude,
                    "longitude" to loc.longitude,
                ),
            )
        } ?: mapOf("isMoving" to isMoving)

        eventDispatcher.sendMotionChange(locationMap)
    }

    // =========================================================================
    // Schedule callbacks
    // =========================================================================

    private fun handleScheduleStart() {
        stateManager.enabled = true
        LocationService.start(context)
        locationEngine.start()
        motionDetector.start()
        startHeartbeat()
        eventDispatcher.sendEnabledChange(true)
    }

    private fun handleScheduleStop() {
        stateManager.enabled = false
        locationEngine.stop()
        motionDetector.stop()
        stopHeartbeat()
        LocationService.stop(context)
        eventDispatcher.sendEnabledChange(false)
    }

    // =========================================================================
    // Heartbeat
    // =========================================================================

    private fun startHeartbeat() {
        stopHeartbeat()
        val intervalSeconds = configManager.getHeartbeatInterval()
        if (intervalSeconds <= 0) return

        heartbeatRunnable = object : Runnable {
            override fun run() {
                if (!stateManager.enabled) return
                locationEngine.getCurrentPosition(emptyMap()) { location ->
                    val heartbeatData = location ?: emptyMap()
                    eventDispatcher.sendHeartbeat(heartbeatData)
                }
                mainHandler.postDelayed(this, intervalSeconds * 1000L)
            }
        }
        mainHandler.postDelayed(heartbeatRunnable!!, intervalSeconds * 1000L)
    }

    private fun stopHeartbeat() {
        heartbeatRunnable?.let { mainHandler.removeCallbacks(it) }
        heartbeatRunnable = null
    }

    // =========================================================================
    // Boot receiver management
    // =========================================================================

    private fun updateBootReceiverState() {
        val enabled = configManager.getStartOnBoot() && !configManager.getStopOnTerminate()
        val componentName = ComponentName(context, BootReceiver::class.java)
        val newState = if (enabled) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        } else {
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        }

        try {
            context.packageManager.setComponentEnabledSetting(
                componentName,
                newState,
                PackageManager.DONT_KILL_APP
            )
        } catch (e: Exception) {
            logger.warning("Failed to update BootReceiver state: ${e.message}")
        }
    }

    // =========================================================================
    // Cleanup
    // =========================================================================

    private fun destroyAll() {
        locationEngine.destroy()
        motionDetector.stop()
        geofenceManager.destroy()
        httpSyncManager.stop()
        headlessService.destroy()
        scheduleManager.stop()
        soundManager.stop()
        stopHeartbeat()
        GeofenceBroadcastReceiver.geofenceManager = null
    }
}
