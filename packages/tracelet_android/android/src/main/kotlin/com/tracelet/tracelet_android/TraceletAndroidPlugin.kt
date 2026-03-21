package com.tracelet.tracelet_android

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import com.tracelet.core.ConfigManager
import com.tracelet.core.StateManager
import com.tracelet.core.TraceletBootstrap
import com.tracelet.core.attestation.DeviceAttestor
import com.tracelet.core.audit.AuditTrailManager
import com.tracelet.core.privacy.PrivacyZoneManager
import com.tracelet.core.db.DatabaseEncryptionManager
import com.tracelet.core.db.TraceletDatabase
import com.tracelet.core.geofence.GeofenceManager
import com.tracelet.core.http.HttpSyncManager
import com.tracelet.core.location.LocationEngine
import com.tracelet.core.location.PeriodicLocationWorker
import com.tracelet.core.motion.MotionDetector
import com.tracelet.core.receiver.BootReceiver
import com.tracelet.core.receiver.GeofenceBroadcastReceiver
import com.tracelet.core.schedule.ScheduleManager
import com.tracelet.core.service.LocationService
import com.tracelet.core.util.*
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
 * - TraceletLogger / SoundManager / TraceletPermissionManager
 * - EventDispatcher (15 EventChannels → Dart)
 */
class TraceletAndroidPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

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
    private lateinit var permissionManager: TraceletPermissionManager
    private lateinit var auditTrailManager: AuditTrailManager
    private lateinit var privacyZoneManager: PrivacyZoneManager
    private lateinit var encryptionManager: DatabaseEncryptionManager
    private lateinit var deviceAttestor: DeviceAttestor

    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }
    private var heartbeatRunnable: Runnable? = null
    private var stopAfterElapsedRunnable: Runnable? = null
    private var isReady = false
    private var pendingPermissionResult: Result? = null

    // =========================================================================
    // FlutterPlugin lifecycle
    // =========================================================================

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext

        // Register bootstrap factories for headless/boot-restart scenarios
        TraceletBootstrap.eventSenderFactory = { ctx ->
            EventDispatcher() // Flutter EventDispatcher (no messenger — headless shell)
        }
        TraceletBootstrap.headlessDispatcherFactory = { ctx ->
            HeadlessTaskService(ctx)
        }

        // MethodChannel
        channel = MethodChannel(binding.binaryMessenger, "com.tracelet/methods")
        channel.setMethodCallHandler(this)

        // EventChannels
        eventDispatcher = EventDispatcher()
        eventDispatcher.register(binding.binaryMessenger)

        // Persistence
        configManager = ConfigManager.getInstance(context)
        stateManager = StateManager(context)
        encryptionManager = DatabaseEncryptionManager(context)
        val dbPassword = encryptionManager.getDatabasePassword(null)
        database = TraceletDatabase.getInstance(context, dbPassword)

        // Logger
        logger = TraceletLogger(context, configManager, database)

        // Audit Trail (Enterprise)
        auditTrailManager = AuditTrailManager(context, database, configManager)

        // Privacy Zones (Enterprise)
        privacyZoneManager = PrivacyZoneManager(context, database, configManager)

        // Device Attestation (Enterprise)
        deviceAttestor = DeviceAttestor(context)

        // Location
        locationEngine = LocationEngine(context, configManager, stateManager, eventDispatcher, database)
        locationEngine.auditTrailManager = auditTrailManager
        locationEngine.privacyZoneManager = privacyZoneManager

        // Wire location persistence → HTTP auto-sync trigger
        locationEngine.onLocationPersisted = {
            httpSyncManager.onLocationInserted()
        }

        // Trip detection is now handled in shared Dart code (tracelet_platform_interface).

        // Motion
        motionDetector = MotionDetector(context, configManager, stateManager, eventDispatcher)
        motionDetector.onMotionStateChanged = { isMoving ->
            handleMotionStateChange(isMoving)
        }
        motionDetector.onStopRequested = {
            // stopOnStationary: fully stop tracking
            mainHandler.post {
                stateManager.enabled = false
                stateManager.isMoving = false
                locationEngine.stop()
                motionDetector.stop()
                stopHeartbeat()
                if (configManager.isForegroundServiceEnabled()) {
                    LocationService.stop(context)
                }
                eventDispatcher.sendEnabledChange(false)
                logger.info("stopOnStationary — tracking stopped by motion detector")
            }
        }

        // Geofencing
        geofenceManager = GeofenceManager(context, configManager, eventDispatcher, database)
        GeofenceBroadcastReceiver.geofenceManager = geofenceManager

        // HTTP
        httpSyncManager = HttpSyncManager(context, configManager, eventDispatcher, database)

        // Headless
        headlessService = HeadlessTaskService(context)

        // Wire headless fallback — when no Dart UI listener exists for an event,
        // EventDispatcher routes it to HeadlessTaskService.
        eventDispatcher.headlessFallback = { eventName, eventData ->
            if (headlessService.isRegistered()) {
                headlessService.dispatchEvent(eventName, eventData)
            }
        }

        // Schedule
        scheduleManager = ScheduleManager(context, configManager, stateManager, eventDispatcher)
        scheduleManager.onScheduleStart = { handleScheduleStart() }
        scheduleManager.onScheduleStop = { handleScheduleStop() }

        // Sound
        soundManager = SoundManager(context, configManager)

        // Permissions
        permissionManager = TraceletPermissionManager(context)

        // Re-wire EventDispatcher for periodic mode if it was already active
        // (e.g., app returns to foreground after process restart by AlarmManager).
        if (stateManager.enabled && stateManager.trackingMode == 2) {
            PeriodicLocationWorker.eventSender = eventDispatcher
            PeriodicLocationWorker.httpSyncManager = httpSyncManager
        }
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
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
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
            "startPeriodic" -> handleStartPeriodic(result)
            "startGeofences" -> handleStartGeofences(result)
            "getState" -> handleGetState(result)
            "setConfig" -> handleSetConfig(call, result)
            "reset" -> handleReset(call, result)

            // Location
            "getCurrentPosition" -> handleGetCurrentPosition(call, result)
            "getLastKnownLocation" -> handleGetLastKnownLocation(call, result)
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
            "getCount" -> {
                @Suppress("UNCHECKED_CAST")
                val query = call.arguments as? Map<String, Any?>
                val startTime = (query?.get("start") as? Number)?.toLong()
                val endTime = (query?.get("end") as? Number)?.toLong()
                result.success(database.getLocationCount(startTime, endTime))
            }
            "destroyLocations" -> result.success(database.deleteAllLocations())
            "destroyLocation" -> {
                val uuid = call.arguments as? String ?: ""
                result.success(database.deleteLocation(uuid))
            }
            "insertLocation" -> handleInsertLocation(call, result)

            // HTTP Sync
            "sync" -> handleSync(result)
            "setDynamicHeaders" -> {
                @Suppress("UNCHECKED_CAST")
                val headers = (call.arguments as? Map<String, Any?>)
                    ?.mapValues { it.value?.toString() ?: "" }
                    ?: emptyMap()
                configManager.setDynamicHeaders(headers)
                result.success(true)
            }

            // Route Context
            "setRouteContext" -> {
                @Suppress("UNCHECKED_CAST")
                val ctx = call.arguments as? Map<String, Any?> ?: emptyMap()
                configManager.setRouteContext(ctx)
                result.success(true)
            }
            "clearRouteContext" -> {
                configManager.clearRouteContext()
                result.success(true)
            }

            // Headless Callbacks
            "registerHeadlessHeadersCallback" -> handleRegisterHeadlessCallback(call, result, "headlessHeaders")
            "registerHeadlessSyncBodyBuilder" -> handleRegisterHeadlessCallback(call, result, "headlessSyncBody")

            // Utility
            "isPowerSaveMode" -> result.success(permissionManager.isPowerSaveMode())
            "getPermissionStatus" -> result.success(
                permissionManager.getAuthorizationStatus(activity)
            )
            "requestPermission" -> handleRequestPermission(result)
            "getNotificationPermissionStatus" -> result.success(
                permissionManager.getNotificationPermissionStatus(activity)
            )
            "requestNotificationPermission" -> handleRequestNotificationPermission(result)
            "canScheduleExactAlarms" -> result.success(
                PeriodicLocationWorker.canScheduleExactAlarms(context)
            )
            "openExactAlarmSettings" -> handleOpenExactAlarmSettings(result)
            "getMotionPermissionStatus" -> result.success(
                permissionManager.getMotionPermissionStatus(activity)
            )
            "requestMotionPermission" -> handleRequestMotionPermission(result)
            "requestTemporaryFullAccuracy" -> {
                // Android doesn't have temporary full accuracy (iOS-only concept)
                result.success(permissionManager.getAuthorizationStatus(activity))
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

            // OEM compatibility
            "getSettingsHealth" -> result.success(OemCompat.getSettingsHealth(context))
            "openOemSettings" -> {
                val label = call.arguments as? String ?: ""
                result.success(OemCompat.openOemSettingsScreen(context, label))
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

            // Audit Trail (Enterprise)
            "verifyAuditTrail" -> result.success(auditTrailManager.verifyChain())
            "getAuditProof" -> {
                val uuid = call.arguments as? String ?: ""
                result.success(auditTrailManager.getProof(uuid))
            }

            // Privacy Zones (Enterprise)
            "addPrivacyZone" -> {
                @Suppress("UNCHECKED_CAST")
                val zone = call.arguments as? Map<String, Any?> ?: emptyMap()
                result.success(privacyZoneManager.addZone(zone))
            }
            "addPrivacyZones" -> {
                @Suppress("UNCHECKED_CAST")
                val zones = (call.arguments as? List<*>)
                    ?.filterIsInstance<Map<String, Any?>>()
                    ?: emptyList()
                result.success(privacyZoneManager.addZones(zones))
            }
            "removePrivacyZone" -> {
                val id = call.arguments as? String ?: ""
                result.success(privacyZoneManager.removeZone(id))
            }
            "removePrivacyZones" -> result.success(privacyZoneManager.removeAllZones())
            "getPrivacyZones" -> result.success(privacyZoneManager.getZones())

            // Encrypted Database (Enterprise)
            "isDatabaseEncrypted" -> result.success(encryptionManager.isDatabaseEncrypted())
            "encryptDatabase" -> {
                try {
                    val customKey = configManager.getEncryptionKey()
                    val key = encryptionManager.getOrCreateKey(customKey)
                    val success = database.encryptDatabase(key, encryptionManager)
                    if (success) {
                        database = TraceletDatabase.getInstance(context, key)
                    }
                    result.success(success)
                } catch (e: Exception) {
                    result.error("ENCRYPTION_FAILED", e.message, null)
                }
            }

            // Device Attestation (Enterprise)
            "getAttestationToken" -> {
                deviceAttestor.requestToken { token ->
                    mainHandler.post { result.success(token) }
                }
            }

            // Dead Reckoning (Enterprise)
            "getDeadReckoningState" -> {
                result.success(locationEngine.getDeadReckoningState())
            }

            // Carbon Estimator (Enterprise)
            "getCarbonReport" -> {
                @Suppress("UNCHECKED_CAST")
                val query = call.arguments as? Map<String, Any?>
                result.success(getCarbonReport(query))
            }

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

        // Handle encryption if enabled
        if (configManager.getEncryptDatabase() && !encryptionManager.isDatabaseEncrypted()) {
            val customKey = configManager.getEncryptionKey()
            val key = encryptionManager.getOrCreateKey(customKey)
            val success = database.encryptDatabase(key, encryptionManager)
            if (success) {
                database = TraceletDatabase.getInstance(context, key)
            }
        }

        // Handle remote config if URL is configured
        val remoteUrl = configManager.getRemoteConfigUrl()
        if (!remoteUrl.isNullOrEmpty()) {
            fetchRemoteConfig(remoteUrl, merged, result)
            return
        }

        // Initialize subsystems
        completeReady(merged, result)
    }

    private fun completeReady(config: Map<String, Any?>, result: Result) {
        // Initialize subsystems
        if (configManager.isDebug()) soundManager.start()
        httpSyncManager.start()
        logger.pruneOldLogs()

        // Update boot receiver state
        updateBootReceiverState()

        // Start attestation refresh if enabled
        if (configManager.getAttestationEnabled()) {
            deviceAttestor.startRefresh(configManager.getAttestationRefreshInterval())
        }

        isReady = true

        // Return current state including the merged config
        val stateMap = stateManager.toMap(config)
        logger.info("ready() called")
        result.success(stateMap)
    }

    private fun handleStart(result: Result) {
        if (!isReady) {
            result.error("NOT_READY", "Call ready() before start()", null)
            return
        }

        // Android 14+ requires runtime location permission BEFORE starting
        // a foreground service with FOREGROUND_SERVICE_TYPE_LOCATION.
        val authStatus = permissionManager.getAuthorizationStatus(activity)
        if (authStatus != TraceletPermissionManager.STATUS_WHEN_IN_USE &&
            authStatus != TraceletPermissionManager.STATUS_ALWAYS) {
            result.error(
                "PERMISSION_DENIED",
                "Location permission is required before starting tracking. " +
                    "Call requestPermission() first.",
                null
            )
            return
        }

        // If a boot-mode LocationEngine is running from BootReceiver,
        // shut it down before starting our own engine with full EventChannels.
        LocationService.stopBootTracking()

        // Stop any active periodic tracking before switching to continuous mode.
        locationEngine.stopPeriodic()
        PeriodicLocationWorker.cancel(context)
        PeriodicLocationWorker.eventSender = null
        PeriodicLocationWorker.httpSyncManager = null

        stateManager.enabled = true
        stateManager.trackingMode = 0 // Location tracking
        stateManager.isMoving = configManager.getIsMoving()

        // Start foreground service only if enabled in config.
        // When disabled, one-shot location via getCurrentPosition() and
        // getLastKnownLocation() still work, but continuous background
        // tracking may be killed by the OS.
        if (configManager.isForegroundServiceEnabled()) {
            LocationService.start(context)
        }

        // Start location engine
        locationEngine.start()

        // Wire proximity-based geofence monitoring so geofences are
        // automatically loaded/unloaded as the device moves.
        locationEngine.onLocationUpdate = { lat, lng ->
            geofenceManager.updateProximity(lat, lng)
        }

        // Request activity recognition permission (API 29+) and start motion detector
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val hasMotion = ContextCompat.checkSelfPermission(
                context, Manifest.permission.ACTIVITY_RECOGNITION
            ) == PackageManager.PERMISSION_GRANTED
            if (!hasMotion) {
                // Request permission — motion detector will be started
                // after permission is granted in onRequestPermissionsResult.
                permissionManager.requestActivityRecognition(activity)
            } else {
                motionDetector.start()
            }
        } else {
            motionDetector.start()
        }

        // Start heartbeat
        startHeartbeat()

        // Schedule auto-stop if stopAfterElapsedMinutes is configured
        startStopAfterElapsedTimer()

        // Fire enabledChange
        eventDispatcher.sendEnabledChange(true)

        logger.info("start() — tracking started")
        result.success(stateManager.toMap(configManager.getConfig()))
    }

    private fun handleStartPeriodic(result: Result) {
        if (!isReady) {
            result.error("NOT_READY", "Call ready() before startPeriodic()", null)
            return
        }

        val authStatus = permissionManager.getAuthorizationStatus(activity)
        if (authStatus != TraceletPermissionManager.STATUS_WHEN_IN_USE &&
            authStatus != TraceletPermissionManager.STATUS_ALWAYS) {
            result.error(
                "PERMISSION_DENIED",
                "Location permission is required before starting tracking. " +
                    "Call requestPermission() first.",
                null
            )
            return
        }

        LocationService.stopBootTracking()

        // Stop any active continuous tracking before switching to periodic mode.
        // Without this, requestLocationUpdates remains active and the GPS icon
        // stays permanently visible in the status bar.
        locationEngine.stop()
        motionDetector.stop()
        if (configManager.isForegroundServiceEnabled()) {
            LocationService.stop(context)
        }

        stateManager.enabled = true
        stateManager.trackingMode = 2 // Periodic tracking
        stateManager.isMoving = false

        // Wire the shared EventDispatcher so WorkManager workers can dispatch
        PeriodicLocationWorker.eventSender = eventDispatcher
        PeriodicLocationWorker.httpSyncManager = httpSyncManager

        // Determine scheduling strategy:
        // - Foreground service: use in-process timer (any interval, shows notification)
        // - Exact alarms: use AlarmManager (any interval, no notification)
        // - WorkManager: battery-optimal (minimum 15 min, no notification)
        //
        // Auto-select exact alarms when interval < 15 min and foreground service
        // is off, so short intervals work without a persistent notification.
        val interval = configManager.getPeriodicLocationInterval()
        val useForeground = configManager.getPeriodicUseForegroundService()
        val useExactAlarms = configManager.getPeriodicUseExactAlarms() ||
            (!useForeground && interval < 900)

        if (useForeground) {
            // Strategy 2: Foreground service + timer (sub-15-min intervals)
            if (configManager.isForegroundServiceEnabled()) {
                LocationService.start(context)
            }
            locationEngine.startPeriodic()
        } else if (useExactAlarms) {
            // Strategy 3: AlarmManager exact alarms + OneTimeWorkRequest
            // Enables precise intervals (any duration) without foreground service.
            // Requires SCHEDULE_EXACT_ALARM permission on Android 12+ for exact timing.
            // Falls back to Doze-safe inexact alarms if not granted.
            if (!PeriodicLocationWorker.canScheduleExactAlarms(context)) {
                logger.warning(
                    "SCHEDULE_EXACT_ALARM not granted — timing will be approximate. " +
                    "Grant 'Alarms & reminders' permission in Settings for precise intervals."
                )
            }
            // Perform initial fix immediately
            PeriodicLocationWorker.scheduleOneTime(context)
            // Schedule the first exact alarm for the next interval
            PeriodicLocationWorker.scheduleExactAlarm(
                context,
                interval,
            )
        } else {
            // Strategy 1: WorkManager (default, battery-optimal)
            // No foreground service needed — GPS icon only during fix
            PeriodicLocationWorker.schedule(
                context,
                interval,
            )
            // Perform immediate first fix so the user doesn't wait 15 min.
            PeriodicLocationWorker.scheduleOneTime(context)
        }

        // Start heartbeat if configured (runs independently of periodic mode)
        startHeartbeat()
        startStopAfterElapsedTimer()

        eventDispatcher.sendEnabledChange(true)

        val strategy = when {
            useForeground -> "foreground-service"
            useExactAlarms -> "exact-alarms"
            else -> "workmanager"
        }
        logger.info("startPeriodic() — periodic tracking started " +
            "(interval=${interval}s, " +
            "strategy=$strategy)")
        result.success(stateManager.toMap(configManager.getConfig()))
    }

    private fun handleStop(result: Result) {
        stateManager.enabled = false
        stateManager.isMoving = false

        // Stop all subsystems
        locationEngine.stop()
        locationEngine.onLocationUpdate = null // clear high-accuracy geofence listener
        motionDetector.stop()
        stopHeartbeat()
        cancelStopAfterElapsedTimer()

        // Cancel WorkManager periodic work if it was scheduled
        PeriodicLocationWorker.cancel(context)
        PeriodicLocationWorker.eventSender = null
        PeriodicLocationWorker.httpSyncManager = null

        // Stop foreground service if it was running
        if (configManager.isForegroundServiceEnabled()) {
            LocationService.stop(context)
        }

        // Fire enabledChange
        eventDispatcher.sendEnabledChange(false)

        logger.info("stop() — tracking stopped")
        result.success(stateManager.toMap(configManager.getConfig()))
    }

    // =========================================================================
    // Permission handlers
    // =========================================================================

    /**
     * Asynchronous permission request.
     *
     * Triggers the OS permission dialog and waits for the user's response.
     * The result is sent back to Dart only AFTER the dialog closes.
     */
    private fun handleRequestPermission(result: Result) {
        val act = activity
        if (act == null || pendingPermissionResult != null) {
            // No activity or a request is already in progress — return current status
            result.success(permissionManager.getAuthorizationStatus(activity))
            return
        }

        val status = permissionManager.getAuthorizationStatus(act)

        when (status) {
            TraceletPermissionManager.STATUS_NOT_DETERMINED,
            TraceletPermissionManager.STATUS_DENIED -> {
                // Request foreground permission
                pendingPermissionResult = result
                permissionManager.requestForegroundPermission(act)
            }
            TraceletPermissionManager.STATUS_WHEN_IN_USE -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    // Upgrade to background permission
                    pendingPermissionResult = result
                    permissionManager.requestBackgroundPermission(act)
                } else {
                    // Pre-Q: foreground = always
                    result.success(TraceletPermissionManager.STATUS_ALWAYS)
                }
            }
            else -> {
                // ALWAYS or DENIED_FOREVER — no dialog will show
                result.success(status)
            }
        }
    }

    /**
     * Asynchronous notification permission request (Android 13+ / API 33+).
     *
     * Triggers the OS POST_NOTIFICATIONS dialog and waits for the user's response.
     * On API < 33, returns immediately with status 3 (granted — no runtime permission needed).
     */
    private fun handleRequestNotificationPermission(result: Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            // Pre-13: notifications always allowed
            result.success(TraceletPermissionManager.STATUS_ALWAYS)
            return
        }

        val act = activity
        if (act == null || pendingPermissionResult != null) {
            result.success(permissionManager.getNotificationPermissionStatus(activity))
            return
        }

        val status = permissionManager.getNotificationPermissionStatus(act)
        if (status == TraceletPermissionManager.STATUS_ALWAYS ||
            status == TraceletPermissionManager.STATUS_DENIED_FOREVER) {
            // Already granted or permanently denied — no dialog will show
            result.success(status)
            return
        }

        pendingPermissionResult = result
        permissionManager.requestNotificationPermission(act)
    }

    /**
     * Opens the system Settings page for granting SCHEDULE_EXACT_ALARM.
     *
     * On Android 12+ (API 31+), launches ACTION_REQUEST_SCHEDULE_EXACT_ALARM
     * which shows the "Alarms & reminders" toggle for this app.
     * On Android < 12, returns false (no restriction exists).
     */
    private fun handleOpenExactAlarmSettings(result: Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            result.success(false) // No restriction on pre-12
            return
        }

        try {
            val intent = Intent(
                android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                android.net.Uri.parse("package:" + context.packageName)
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            logger.warning("Failed to open exact alarm settings: " + e.message)
            result.success(false)
        }
    }

    /**
     * Asynchronous motion/activity recognition permission request (API 29+).
     *
     * Triggers the OS ACTIVITY_RECOGNITION dialog and waits for the user's response.
     * On API < 29, returns immediately with status 3 (granted — no runtime permission needed).
     */
    private fun handleRequestMotionPermission(result: Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success(TraceletPermissionManager.STATUS_ALWAYS)
            return
        }

        val act = activity
        if (act == null || pendingPermissionResult != null) {
            result.success(permissionManager.getMotionPermissionStatus(activity))
            return
        }

        val status = permissionManager.getMotionPermissionStatus(act)
        if (status == TraceletPermissionManager.STATUS_ALWAYS ||
            status == TraceletPermissionManager.STATUS_DENIED_FOREVER) {
            result.success(status)
            return
        }

        pendingPermissionResult = result
        permissionManager.requestActivityRecognition(act)
    }

    /**
     * Called by the Flutter engine after the OS permission dialog closes.
     * Resolves the pending Dart `Future<int>` with the actual result.
     */
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode != TraceletPermissionManager.REQUEST_CODE_LOCATION &&
            requestCode != TraceletPermissionManager.REQUEST_CODE_BACKGROUND_LOCATION &&
            requestCode != TraceletPermissionManager.REQUEST_CODE_ACTIVITY_RECOGNITION &&
            requestCode != TraceletPermissionManager.REQUEST_CODE_NOTIFICATION
        ) {
            return false // Not ours
        }

        val pending = pendingPermissionResult ?: return false
        pendingPermissionResult = null

        val act = activity
        if (requestCode == TraceletPermissionManager.REQUEST_CODE_NOTIFICATION) {
            // For notification permission, return the notification status
            pending.success(
                permissionManager.getNotificationPermissionStatus(act)
            )
        } else if (requestCode == TraceletPermissionManager.REQUEST_CODE_ACTIVITY_RECOGNITION) {
            // Activity recognition permission result
            val motionStatus = permissionManager.getMotionPermissionStatus(act)
            // If granted and tracking is active, start the motion detector now
            if (motionStatus == TraceletPermissionManager.STATUS_ALWAYS && stateManager.enabled) {
                motionDetector.start()
            }
            pending.success(motionStatus)
        } else if (act != null) {
            pending.success(permissionManager.getStatusAfterRequest(act))
        } else {
            pending.success(permissionManager.getAuthorizationStatus(null))
        }
        return true
    }

    // =========================================================================
    // Geofence handlers
    // =========================================================================

    private fun handleStartGeofences(result: Result) {
        if (!isReady) {
            result.error("NOT_READY", "Call ready() before startGeofences()", null)
            return
        }

        stateManager.enabled = true
        stateManager.trackingMode = 1 // Geofences only

        // Re-register geofences with proximity filtering
        geofenceManager.reRegisterAll()

        // Wire proximity-based geofence monitoring so geofences are
        // automatically loaded/unloaded as the device moves.
        // Also handles high-accuracy mode (Dart evaluates transitions).
        locationEngine.onLocationUpdate = { lat, lng ->
            geofenceManager.updateProximity(lat, lng)
        }

        // geofenceModeHighAccuracy: also start GPS tracking and compute
        // transitions in-app for more precise enter/exit detection.
        if (configManager.getGeofenceModeHighAccuracy()) {
            geofenceManager.clearHighAccuracyState()
            locationEngine.start()
        } else {
            // Start with low-power mode for proximity updates only
            locationEngine.start()
        }

        // Start foreground service if enabled (needed for background geofencing)
        if (configManager.isForegroundServiceEnabled()) {
            LocationService.start(context)
        }

        eventDispatcher.sendEnabledChange(true)

        logger.info("startGeofences() — geofence-only mode (highAccuracy=${configManager.getGeofenceModeHighAccuracy()})")
        result.success(stateManager.toMap(configManager.getConfig()))
    }

    private fun handleGetState(result: Result) {
        result.success(stateManager.toMap(configManager.getConfig()))
    }

    private fun handleSetConfig(call: MethodCall, result: Result) {
        @Suppress("UNCHECKED_CAST")
        val configMap = call.arguments as? Map<String, Any?> ?: emptyMap()

        // Capture location-relevant config before merge to avoid unnecessary restart (A-M4).
        val oldConfig = configManager.getConfig()
        val merged = configManager.setConfig(configMap)

        // Only restart location engine when location-affecting keys actually changed.
        if (stateManager.enabled) {
            val locationKeys = listOf(
                "desiredAccuracy", "distanceFilter", "locationUpdateInterval",
                "fastestLocationUpdateInterval", "stationaryRadius", "deferTime",
                "disableElasticity", "elasticityMultiplier",
            )
            val needsRestart = locationKeys.any { key -> oldConfig[key] != merged[key] }
            if (needsRestart) {
                locationEngine.stop()
                locationEngine.start()
            }
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

    private fun handleGetLastKnownLocation(call: MethodCall, result: Result) {
        @Suppress("UNCHECKED_CAST")
        val options = call.arguments as? Map<String, Any?> ?: emptyMap()

        locationEngine.getLastKnownLocation(options) { location ->
            if (location != null) {
                result.success(location)
            } else {
                // Return empty map instead of error — null means "no cached location"
                result.success(emptyMap<String, Any?>())
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
        // Trip detection is now handled in shared Dart code.
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
        val startTime = (query?.get("start") as? Number)?.toLong()
        val endTime = (query?.get("end") as? Number)?.toLong()
        result.success(database.getLocations(limit, offset, orderAsc, startTime, endTime))
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

    private fun handleRegisterHeadlessCallback(call: MethodCall, result: Result, key: String) {
        val callbackIds = call.arguments as? List<*> ?: run {
            result.error("INVALID_ARGS", "Expected list of callback IDs", null)
            return
        }
        val registrationId = (callbackIds.getOrNull(0) as? Number)?.toLong() ?: -1L
        val dispatchId = (callbackIds.getOrNull(1) as? Number)?.toLong() ?: -1L

        val prefs = context.getSharedPreferences("com.tracelet.headless", Context.MODE_PRIVATE)
        prefs.edit()
            .putLong("${key}_registrationId", registrationId)
            .putLong("${key}_dispatchId", dispatchId)
            .apply()

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

        // Dispatch motionChange event with full location data
        val locationMap = locationEngine.getLastLocation()?.let { loc ->
            val map = locationEngine.enrichLocation(loc, "motionchange", locationEngine.lastEffectiveSpeed).toMutableMap()
            map["isMoving"] = isMoving
            map
        } ?: mapOf("isMoving" to isMoving)

        eventDispatcher.sendMotionChange(locationMap)
        // Trip detection is now handled in shared Dart code.
    }

    // =========================================================================
    // Schedule callbacks
    // =========================================================================

    private fun handleScheduleStart() {
        stateManager.enabled = true
        if (configManager.isForegroundServiceEnabled()) {
            LocationService.start(context)
        }
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
        if (configManager.isForegroundServiceEnabled()) {
            LocationService.stop(context)
        }
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

                // Prefer the last known location when tracking is active to
                // avoid activating GPS for a fresh fix on every heartbeat
                // interval (A-H7). Fall back to getCurrentPosition only if
                // no recent location is available.
                val cached = locationEngine.getLastLocation()
                if (cached != null) {
                    val locationData = locationEngine.enrichLocation(cached, "heartbeat")
                    eventDispatcher.sendHeartbeat(mapOf("location" to locationData))
                } else {
                    locationEngine.getCurrentPosition(emptyMap()) { location ->
                        val locationData = location ?: emptyMap()
                        eventDispatcher.sendHeartbeat(mapOf("location" to locationData))
                    }
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
    // stopAfterElapsedMinutes
    // =========================================================================

    private fun startStopAfterElapsedTimer() {
        cancelStopAfterElapsedTimer()
        val minutes = configManager.getStopAfterElapsedMinutes()
        if (minutes <= 0) return

        stopAfterElapsedRunnable = Runnable {
            logger.info("stopAfterElapsedMinutes ($minutes min) — auto-stopping")
            stateManager.enabled = false
            stateManager.isMoving = false
            locationEngine.stop()
            motionDetector.stop()
            stopHeartbeat()
            if (configManager.isForegroundServiceEnabled()) {
                LocationService.stop(context)
            }
            eventDispatcher.sendEnabledChange(false)
        }
        mainHandler.postDelayed(stopAfterElapsedRunnable!!, minutes * 60 * 1000L)
    }

    private fun cancelStopAfterElapsedTimer() {
        stopAfterElapsedRunnable?.let { mainHandler.removeCallbacks(it) }
        stopAfterElapsedRunnable = null
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
    // Remote Config (Enterprise)
    // =========================================================================

    private fun fetchRemoteConfig(url: String, localConfig: Map<String, Any?>, result: Result) {
        // Reject non-HTTPS URLs for security
        if (!url.startsWith("https://")) {
            logger.warning("Remote config URL rejected: only HTTPS is allowed")
            completeReady(localConfig, result)
            return
        }

        val timeout = configManager.getRemoteConfigTimeout()
        val headers = configManager.getRemoteConfigHeaders()
        httpSyncManager.fetchRemoteConfig(url, headers, timeout.toLong()) { remoteConfig ->
            mainHandler.post {
                if (remoteConfig != null) {
                    // Deep merge: remote wins on leaf conflicts
                    val merged = configManager.setConfig(remoteConfig)
                    eventDispatcher.sendRemoteConfigEvent(mapOf(
                        "success" to true,
                        "statusCode" to 200,
                        "appliedConfig" to remoteConfig,
                    ))
                    completeReady(merged, result)
                } else {
                    eventDispatcher.sendRemoteConfigEvent(mapOf(
                        "success" to false,
                        "error" to "Remote config fetch failed or timed out",
                    ))
                    completeReady(localConfig, result)
                }
            }
        }
    }

    // =========================================================================
    // Carbon Report (Enterprise)
    // =========================================================================

    private fun getCarbonReport(query: Map<String, Any?>?): Map<String, Any?> {
        // Get trip data from database and calculate emissions
        val from = (query?.get("from") as? Number)?.toLong()
        val to = (query?.get("to") as? Number)?.toLong()
        val locations = database.getLocations(
            limit = -1,
            offset = 0,
            orderAsc = true,
            startTime = from,
            endTime = to
        )

        var totalGrams = 0.0
        val carbonByMode = mutableMapOf<String, Double>()
        val distanceByMode = mutableMapOf<String, Double>()
        var prevLat = 0.0
        var prevLng = 0.0
        var tripCount = 0
        var wasMoving = false

        for (location in locations) {
            val coords = location["coords"] as? Map<*, *>
            val lat = (coords?.get("latitude") as? Number)?.toDouble() ?: continue
            val lng = (coords?.get("longitude") as? Number)?.toDouble() ?: continue
            val activity = location["activity"] as? Map<*, *>
            val actType = activity?.get("type") as? String ?: "unknown"
            val isMoving = location["is_moving"] == 1 || location["is_moving"] == true

            if (!wasMoving && isMoving) tripCount++
            wasMoving = isMoving

            if (prevLat != 0.0 && prevLng != 0.0) {
                val dist = haversineDistance(prevLat, prevLng, lat, lng)
                distanceByMode[actType] = (distanceByMode[actType] ?: 0.0) + dist
                val factor = carbonFactorForMode(actType)
                val grams = dist / 1000.0 * factor
                carbonByMode[actType] = (carbonByMode[actType] ?: 0.0) + grams
                totalGrams += grams
            }
            prevLat = lat
            prevLng = lng
        }

        return mapOf(
            "totalCarbonGrams" to totalGrams,
            "carbonByMode" to carbonByMode,
            "distanceByMode" to distanceByMode,
            "totalTrips" to tripCount,
        )
    }

    private fun carbonFactorForMode(mode: String): Double {
        return when (mode) {
            "in_vehicle" -> 192.0  // gCO₂/km, EU average
            "on_bicycle", "walking", "running", "on_foot" -> 0.0
            else -> 96.0  // Unknown mode — use half car average
        }
    }

    private fun haversineDistance(lat1: Double, lng1: Double, lat2: Double, lng2: Double): Double {
        val r = 6371000.0 // Earth radius in meters
        val dLat = Math.toRadians(lat2 - lat1)
        val dLng = Math.toRadians(lng2 - lng1)
        val a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
                Math.sin(dLng / 2) * Math.sin(dLng / 2)
        val c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        return r * c
    }

    // =========================================================================
    // Cleanup
    // =========================================================================

    private fun destroyAll() {
        locationEngine.destroy()
        motionDetector.stop()

        // Only destroy geofences if stopOnTerminate is true or geofence mode
        // is not active. When stopOnTerminate is false and geofence mode is
        // active, the Play Services registrations must survive process death
        // so that GeofenceBroadcastReceiver can still fire transition events.
        val keepGeofencesAlive = !configManager.getStopOnTerminate()
            && stateManager.enabled
            && stateManager.trackingMode == 1
        if (!keepGeofencesAlive) {
            geofenceManager.destroy()
        }

        httpSyncManager.stop()
        headlessService.destroy()
        scheduleManager.stop()
        soundManager.stop()
        stopHeartbeat()

        // Only cancel periodic work if stopOnTerminate is true.
        // When stopOnTerminate is false and periodic mode is active,
        // the AlarmManager alarm must survive process death so that
        // PeriodicAlarmReceiver can wake the app for background fixes.
        val keepPeriodicAlive = !configManager.getStopOnTerminate()
            && stateManager.enabled
            && stateManager.trackingMode == 2
        if (!keepPeriodicAlive) {
            PeriodicLocationWorker.cancel(context)
        }
        PeriodicLocationWorker.eventSender = null
        PeriodicLocationWorker.httpSyncManager = null
        if (!keepGeofencesAlive) {
            GeofenceBroadcastReceiver.geofenceManager = null
        }
    }
}
