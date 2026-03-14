package com.tracelet.reactnative

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.WritableArray
import com.facebook.react.bridge.WritableMap
import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.tracelet.core.ConfigManager
import com.tracelet.core.StateManager
import com.tracelet.core.TraceletBootstrap
import com.tracelet.core.TraceletEventSender
import com.tracelet.core.audit.AuditTrailManager
import com.tracelet.core.privacy.PrivacyZoneManager
import com.tracelet.core.db.TraceletDatabase
import com.tracelet.core.geofence.GeofenceManager
import com.tracelet.core.http.HttpSyncManager
import com.tracelet.core.location.LocationEngine
import com.tracelet.core.location.PeriodicLocationWorker
import com.tracelet.core.motion.MotionDetector
import com.tracelet.core.service.LocationService
import com.tracelet.core.util.PermissionManager
import com.tracelet.core.util.SoundManager
import com.tracelet.core.util.TraceletLogger

@ReactModule(name = TraceletModule.NAME)
class TraceletModule(
    private val reactContext: ReactApplicationContext
) : ReactContextBaseJavaModule(reactContext), TraceletEventSender {

    companion object {
        const val NAME = "TraceletReactNative"
    }

    // Core subsystems
    private lateinit var configManager: ConfigManager
    private lateinit var stateManager: StateManager
    private lateinit var database: TraceletDatabase
    private lateinit var locationEngine: LocationEngine
    private lateinit var motionDetector: MotionDetector
    private lateinit var geofenceManager: GeofenceManager
    private lateinit var httpSyncManager: HttpSyncManager
    private lateinit var logger: TraceletLogger
    private lateinit var soundManager: SoundManager
    private lateinit var permissionManager: PermissionManager
    private lateinit var auditTrailManager: AuditTrailManager
    private lateinit var privacyZoneManager: PrivacyZoneManager

    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }
    private var heartbeatRunnable: Runnable? = null
    private var isReady = false

    override fun getName(): String = NAME

    override fun initialize() {
        super.initialize()
        initSubsystems()
    }

    private fun initSubsystems() {
        val ctx = reactContext.applicationContext

        // Register bootstrap factories for headless/boot-restart scenarios
        TraceletBootstrap.eventSenderFactory = { context ->
            // No-op event sender for headless context — events go via headless dispatcher
            object : TraceletEventSender {
                override fun sendEvent(eventName: String, params: Map<String, Any?>) {}
                override fun hasListener(eventName: String): Boolean = false
            }
        }
        TraceletBootstrap.headlessDispatcherFactory = { context ->
            ReactNativeHeadlessDispatcher(context)
        }

        configManager = ConfigManager.getInstance(ctx)
        stateManager = StateManager(ctx)
        database = TraceletDatabase.getInstance(ctx)
        logger = TraceletLogger(ctx, configManager, database)

        auditTrailManager = AuditTrailManager(ctx, database, configManager)
        privacyZoneManager = PrivacyZoneManager(ctx, database, configManager)

        locationEngine = LocationEngine(ctx, configManager, stateManager, this, database)
        locationEngine.auditTrailManager = auditTrailManager
        locationEngine.privacyZoneManager = privacyZoneManager

        locationEngine.onLocationPersisted = {
            httpSyncManager.onLocationInserted()
        }

        motionDetector = MotionDetector(ctx, configManager, stateManager, this)
        motionDetector.onMotionStateChanged = { isMoving ->
            handleMotionStateChange(isMoving)
        }
        motionDetector.onStopRequested = {
            mainHandler.post {
                stateManager.enabled = false
                stateManager.isMoving = false
                locationEngine.stop()
                motionDetector.stop()
                stopHeartbeat()
                if (configManager.isForegroundServiceEnabled()) {
                    LocationService.stop(ctx)
                }
                sendEvent("onEnabledChange", mapOf("enabled" to false))
                logger.info("stopOnStationary — tracking stopped by motion detector")
            }
        }

        geofenceManager = GeofenceManager(ctx, configManager, this, database)
        httpSyncManager = HttpSyncManager(ctx, configManager, this, database)
        soundManager = SoundManager(ctx, configManager)
        permissionManager = PermissionManager(ctx)

        // Wire PeriodicLocationWorker event routing for headless context
        PeriodicLocationWorker.eventSender = this
        PeriodicLocationWorker.httpSyncManager = httpSyncManager
    }

    // ── TraceletEventSender ─────────────────────────────────────────

    override fun sendEvent(eventName: String, params: Map<String, Any?>) {
        reactContext
            .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
            .emit(eventName, params.toWritableMap())
    }

    override fun hasListener(eventName: String): Boolean = true

    // ── Lifecycle ───────────────────────────────────────────────────

    @ReactMethod
    fun ready(config: ReadableMap, promise: Promise) {
        val configMap = config.toHashMap()
        val merged = configManager.setConfig(configMap)

        if (configManager.isDebug()) soundManager.start()
        httpSyncManager.start()
        logger.pruneOldLogs()

        isReady = true
        logger.info("ready() called (React Native)")
        promise.resolve(stateManager.toMap(merged).toWritableMap())
    }

    @ReactMethod
    fun start(promise: Promise) {
        if (!isReady) {
            promise.reject("ERR_NOT_READY", "Call ready() before start()")
            return
        }

        val authStatus = permissionManager.getAuthorizationStatus(currentActivity)
        if (authStatus != PermissionManager.STATUS_WHEN_IN_USE &&
            authStatus != PermissionManager.STATUS_ALWAYS
        ) {
            promise.reject(
                "ERR_PERMISSION_DENIED",
                "Location permission is required. Call requestPermission() first."
            )
            return
        }

        LocationService.stopBootTracking()
        locationEngine.stopPeriodic()
        PeriodicLocationWorker.cancel(reactContext)
        PeriodicLocationWorker.eventSender = null
        PeriodicLocationWorker.httpSyncManager = null

        stateManager.enabled = true
        stateManager.trackingMode = 0
        stateManager.isMoving = configManager.getIsMoving()

        if (configManager.isForegroundServiceEnabled()) {
            LocationService.start(reactContext)
        }

        locationEngine.start()
        locationEngine.onLocationUpdate = { lat, lng ->
            geofenceManager.updateProximity(lat, lng)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val hasMotion = ContextCompat.checkSelfPermission(
                reactContext, Manifest.permission.ACTIVITY_RECOGNITION
            ) == PackageManager.PERMISSION_GRANTED
            if (hasMotion) motionDetector.start()
        } else {
            motionDetector.start()
        }

        startHeartbeat()
        sendEvent("onEnabledChange", mapOf("enabled" to true))
        logger.info("start() — tracking started (React Native)")
        promise.resolve(stateManager.toMap(configManager.getConfig()).toWritableMap())
    }

    @ReactMethod
    fun stop(promise: Promise) {
        stateManager.enabled = false
        stateManager.isMoving = false

        locationEngine.stop()
        locationEngine.onLocationUpdate = null
        motionDetector.stop()
        stopHeartbeat()

        if (configManager.isForegroundServiceEnabled()) {
            LocationService.stop(reactContext)
        }

        PeriodicLocationWorker.cancel(reactContext)
        PeriodicLocationWorker.eventSender = null
        PeriodicLocationWorker.httpSyncManager = null

        sendEvent("onEnabledChange", mapOf("enabled" to false))
        logger.info("stop() — tracking stopped (React Native)")
        promise.resolve(stateManager.toMap(configManager.getConfig()).toWritableMap())
    }

    @ReactMethod
    fun startGeofences(promise: Promise) {
        if (!isReady) {
            promise.reject("ERR_NOT_READY", "Call ready() before startGeofences()")
            return
        }

        stateManager.enabled = true
        stateManager.trackingMode = 1
        stateManager.isMoving = false

        geofenceManager.reRegisterAll()
        locationEngine.onLocationUpdate = { lat, lng ->
            geofenceManager.updateProximity(lat, lng)
        }
        locationEngine.start()

        sendEvent("onEnabledChange", mapOf("enabled" to true))
        logger.info("startGeofences() — geofence tracking started (React Native)")
        promise.resolve(stateManager.toMap(configManager.getConfig()).toWritableMap())
    }

    @ReactMethod
    fun startPeriodic(promise: Promise) {
        if (!isReady) {
            promise.reject("ERR_NOT_READY", "Call ready() before startPeriodic()")
            return
        }

        val authStatus = permissionManager.getAuthorizationStatus(currentActivity)
        if (authStatus != PermissionManager.STATUS_WHEN_IN_USE &&
            authStatus != PermissionManager.STATUS_ALWAYS
        ) {
            promise.reject(
                "ERR_PERMISSION_DENIED",
                "Location permission is required. Call requestPermission() first."
            )
            return
        }

        LocationService.stopBootTracking()
        locationEngine.stop()
        motionDetector.stop()
        if (configManager.isForegroundServiceEnabled()) {
            LocationService.stop(reactContext)
        }

        stateManager.enabled = true
        stateManager.trackingMode = 2
        stateManager.isMoving = false

        PeriodicLocationWorker.eventSender = this
        PeriodicLocationWorker.httpSyncManager = httpSyncManager

        val interval = configManager.getPeriodicLocationInterval()
        val useForeground = configManager.getPeriodicUseForegroundService()
        val useExactAlarms = configManager.getPeriodicUseExactAlarms() ||
            (!useForeground && interval < 900)

        if (useForeground) {
            if (configManager.isForegroundServiceEnabled()) {
                LocationService.start(reactContext)
            }
            locationEngine.startPeriodic()
        } else if (useExactAlarms) {
            PeriodicLocationWorker.scheduleOneTime(reactContext)
            PeriodicLocationWorker.scheduleExactAlarm(reactContext, interval)
        } else {
            PeriodicLocationWorker.schedule(reactContext, interval)
            PeriodicLocationWorker.scheduleOneTime(reactContext)
        }

        startHeartbeat()
        sendEvent("onEnabledChange", mapOf("enabled" to true))
        logger.info("startPeriodic() — periodic tracking started (React Native)")
        promise.resolve(stateManager.toMap(configManager.getConfig()).toWritableMap())
    }

    @ReactMethod
    fun getState(promise: Promise) {
        promise.resolve(stateManager.toMap(configManager.getConfig()).toWritableMap())
    }

    @ReactMethod
    fun setConfig(config: ReadableMap, promise: Promise) {
        val configMap = config.toHashMap()
        val merged = configManager.setConfig(configMap)
        promise.resolve(stateManager.toMap(merged).toWritableMap())
    }

    @ReactMethod
    fun reset(config: ReadableMap?, promise: Promise) {
        stateManager.enabled = false
        stateManager.isMoving = false
        locationEngine.stop()
        locationEngine.onLocationUpdate = null
        motionDetector.stop()
        stopHeartbeat()
        if (configManager.isForegroundServiceEnabled()) {
            LocationService.stop(reactContext)
        }
        PeriodicLocationWorker.cancel(reactContext)
        PeriodicLocationWorker.eventSender = null
        PeriodicLocationWorker.httpSyncManager = null

        configManager.reset()
        val configMap = config?.toHashMap() ?: emptyMap<String, Any>()
        val merged = configManager.setConfig(configMap)
        database.deleteAllLocations()

        sendEvent("onEnabledChange", mapOf("enabled" to false))
        isReady = false
        logger.info("reset() — plugin reset (React Native)")
        promise.resolve(stateManager.toMap(merged).toWritableMap())
    }

    // ── Location ────────────────────────────────────────────────────

    @ReactMethod
    fun getCurrentPosition(options: ReadableMap, promise: Promise) {
        val opts = options.toHashMap()
        locationEngine.getCurrentPosition(opts, { location ->
            promise.resolve(location.toWritableMap())
        }, { error ->
            promise.reject("ERR_LOCATION", error)
        })
    }

    @ReactMethod
    fun getLastKnownLocation(options: ReadableMap?, promise: Promise) {
        val location = locationEngine.getLastKnownLocation()
        if (location != null) {
            promise.resolve(location.toWritableMap())
        } else {
            promise.resolve(null)
        }
    }

    @ReactMethod
    fun watchPosition(options: ReadableMap, promise: Promise) {
        val opts = options.toHashMap()
        val watchId = locationEngine.watchPosition(opts)
        promise.resolve(watchId)
    }

    @ReactMethod
    fun stopWatchPosition(watchId: Double, promise: Promise) {
        val result = locationEngine.stopWatchPosition(watchId.toInt())
        promise.resolve(result)
    }

    @ReactMethod
    fun changePace(isMoving: Boolean, promise: Promise) {
        val result = locationEngine.changePace(isMoving)
        promise.resolve(result)
    }

    @ReactMethod
    fun getOdometer(promise: Promise) {
        promise.resolve(locationEngine.getOdometer())
    }

    @ReactMethod
    fun setOdometer(value: Double, promise: Promise) {
        promise.resolve(locationEngine.setOdometer(value))
    }

    // ── Geofencing ──────────────────────────────────────────────────

    @ReactMethod
    fun addGeofence(geofence: ReadableMap, promise: Promise) {
        val g = geofence.toHashMap()
        promise.resolve(geofenceManager.addGeofence(g))
    }

    @ReactMethod
    fun addGeofences(geofences: ReadableArray, promise: Promise) {
        val list = mutableListOf<Map<String, Any?>>()
        for (i in 0 until geofences.size()) {
            geofences.getMap(i)?.let { list.add(it.toHashMap()) }
        }
        promise.resolve(geofenceManager.addGeofences(list))
    }

    @ReactMethod
    fun removeGeofence(identifier: String, promise: Promise) {
        promise.resolve(geofenceManager.removeGeofence(identifier))
    }

    @ReactMethod
    fun removeGeofences(promise: Promise) {
        promise.resolve(geofenceManager.removeGeofences())
    }

    @ReactMethod
    fun getGeofences(promise: Promise) {
        val geofences = geofenceManager.getGeofences()
        val arr = Arguments.createArray()
        for (g in geofences) {
            arr.pushMap((g as Map<String, Any?>).toWritableMap())
        }
        promise.resolve(arr)
    }

    @ReactMethod
    fun getGeofence(identifier: String, promise: Promise) {
        val g = geofenceManager.getGeofence(identifier)
        if (g != null) {
            promise.resolve((g as Map<String, Any?>).toWritableMap())
        } else {
            promise.resolve(null)
        }
    }

    @ReactMethod
    fun geofenceExists(identifier: String, promise: Promise) {
        promise.resolve(geofenceManager.geofenceExists(identifier))
    }

    // ── Persistence ─────────────────────────────────────────────────

    @ReactMethod
    fun getLocations(query: ReadableMap?, promise: Promise) {
        val q = query?.toHashMap()
        val limit = (q?.get("limit") as? Number)?.toInt() ?: -1
        val order = (q?.get("order") as? Number)?.toInt() ?: 0
        val locations = database.getLocations(limit, order)
        val arr = Arguments.createArray()
        for (loc in locations) {
            arr.pushMap((loc as Map<String, Any?>).toWritableMap())
        }
        promise.resolve(arr)
    }

    @ReactMethod
    fun getCount(promise: Promise) {
        promise.resolve(database.getLocationCount())
    }

    @ReactMethod
    fun destroyLocations(promise: Promise) {
        promise.resolve(database.deleteAllLocations())
    }

    @ReactMethod
    fun destroyLocation(uuid: String, promise: Promise) {
        promise.resolve(database.deleteLocation(uuid))
    }

    @ReactMethod
    fun insertLocation(location: ReadableMap, promise: Promise) {
        val params = location.toHashMap()
        val uuid = database.insertLocation(params)
        httpSyncManager.onLocationInserted()
        promise.resolve(uuid)
    }

    // ── HTTP Sync ───────────────────────────────────────────────────

    @ReactMethod
    fun sync(promise: Promise) {
        httpSyncManager.sync { synced ->
            val arr = Arguments.createArray()
            for (loc in synced) {
                arr.pushMap((loc as Map<String, Any?>).toWritableMap())
            }
            promise.resolve(arr)
        }
    }

    // ── Permissions ─────────────────────────────────────────────────

    @ReactMethod
    fun requestPermission(promise: Promise) {
        promise.resolve(permissionManager.getAuthorizationStatus(currentActivity))
    }

    @ReactMethod
    fun getPermissionStatus(promise: Promise) {
        promise.resolve(permissionManager.getAuthorizationStatus(currentActivity))
    }

    @ReactMethod
    fun requestNotificationPermission(promise: Promise) {
        promise.resolve(permissionManager.getNotificationPermissionStatus(currentActivity))
    }

    @ReactMethod
    fun getNotificationPermissionStatus(promise: Promise) {
        promise.resolve(permissionManager.getNotificationPermissionStatus(currentActivity))
    }

    @ReactMethod
    fun requestMotionPermission(promise: Promise) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val has = ContextCompat.checkSelfPermission(
                reactContext, Manifest.permission.ACTIVITY_RECOGNITION
            ) == PackageManager.PERMISSION_GRANTED
            promise.resolve(if (has) 3 else 0)
        } else {
            promise.resolve(3) // Not required pre-Q
        }
    }

    @ReactMethod
    fun getMotionPermissionStatus(promise: Promise) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val has = ContextCompat.checkSelfPermission(
                reactContext, Manifest.permission.ACTIVITY_RECOGNITION
            ) == PackageManager.PERMISSION_GRANTED
            promise.resolve(if (has) 3 else 0)
        } else {
            promise.resolve(3)
        }
    }

    @ReactMethod
    fun requestTemporaryFullAccuracy(purposeKey: String, promise: Promise) {
        // Android doesn't have temporary full accuracy — always full
        promise.resolve(0)
    }

    @ReactMethod
    fun canScheduleExactAlarms(promise: Promise) {
        promise.resolve(PeriodicLocationWorker.canScheduleExactAlarms(reactContext))
    }

    // ── Utilities ───────────────────────────────────────────────────

    @ReactMethod
    fun isPowerSaveMode(promise: Promise) {
        promise.resolve(permissionManager.isPowerSaveMode())
    }

    @ReactMethod
    fun getProviderState(promise: Promise) {
        promise.resolve(locationEngine.buildProviderState().toWritableMap())
    }

    @ReactMethod
    fun getSensors(promise: Promise) {
        promise.resolve(motionDetector.getSensors().toWritableMap())
    }

    @ReactMethod
    fun getDeviceInfo(promise: Promise) {
        promise.resolve(mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "version" to Build.VERSION.RELEASE,
            "platform" to "android",
            "framework" to "react-native",
        ).toWritableMap())
    }

    // ── Motion state handling ───────────────────────────────────────

    private fun handleMotionStateChange(isMoving: Boolean) {
        stateManager.isMoving = isMoving
        if (isMoving) {
            locationEngine.start()
            if (configManager.isDebug()) soundManager.playSound("motionchange_true")
        } else {
            locationEngine.stop()
            if (configManager.isDebug()) soundManager.playSound("motionchange_false")
        }
    }

    // ── Heartbeat ───────────────────────────────────────────────────

    private fun startHeartbeat() {
        stopHeartbeat()
        val interval = configManager.getHeartbeatInterval().toLong() * 1000L
        if (interval <= 0) return
        heartbeatRunnable = object : Runnable {
            override fun run() {
                locationEngine.getCurrentPosition(emptyMap(), { location ->
                    sendEvent("onHeartbeat", location)
                }, { _ -> })
                mainHandler.postDelayed(this, interval)
            }
        }
        mainHandler.postDelayed(heartbeatRunnable!!, interval)
    }

    private fun stopHeartbeat() {
        heartbeatRunnable?.let { mainHandler.removeCallbacks(it) }
        heartbeatRunnable = null
    }
}

/** Extension to convert Map to WritableMap for RN bridge. */
private fun Map<String, Any?>.toWritableMap(): WritableMap {
    val map = Arguments.createMap()
    for ((key, value) in this) {
        when (value) {
            null -> map.putNull(key)
            is Boolean -> map.putBoolean(key, value)
            is Int -> map.putInt(key, value)
            is Long -> map.putDouble(key, value.toDouble())
            is Float -> map.putDouble(key, value.toDouble())
            is Double -> map.putDouble(key, value)
            is String -> map.putString(key, value)
            is Map<*, *> -> {
                @Suppress("UNCHECKED_CAST")
                map.putMap(key, (value as Map<String, Any?>).toWritableMap())
            }
            is List<*> -> {
                val arr = Arguments.createArray()
                for (item in value) {
                    when (item) {
                        null -> arr.pushNull()
                        is Boolean -> arr.pushBoolean(item)
                        is Int -> arr.pushInt(item)
                        is Long -> arr.pushDouble(item.toDouble())
                        is Float -> arr.pushDouble(item.toDouble())
                        is Double -> arr.pushDouble(item)
                        is String -> arr.pushString(item)
                        is Map<*, *> -> {
                            @Suppress("UNCHECKED_CAST")
                            arr.pushMap((item as Map<String, Any?>).toWritableMap())
                        }
                        else -> arr.pushString(item.toString())
                    }
                }
                map.putArray(key, arr)
            }
            else -> map.putString(key, value.toString())
        }
    }
    return map
}
