package com.ikolvi.tracelet.flutter

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.ikolvi.tracelet.TlActivity
import com.ikolvi.tracelet.TlAuthorizationStatus
import com.ikolvi.tracelet.TlBattery
import com.ikolvi.tracelet.TlCoords
import com.ikolvi.tracelet.TlCurrentPositionOptions
import com.ikolvi.tracelet.TlGeofence
import com.ikolvi.tracelet.TlLocation
import com.ikolvi.tracelet.TlProviderChangeEvent
import com.ikolvi.tracelet.TlState
import com.ikolvi.tracelet.TlTrackingMode
import com.ikolvi.tracelet.TlConfig
import com.ikolvi.tracelet.TlGeoConfig
import com.ikolvi.tracelet.TlAppConfig
import com.ikolvi.tracelet.TlAndroidConfig
import com.ikolvi.tracelet.TlIosConfig
import com.ikolvi.tracelet.TlHttpConfig
import com.ikolvi.tracelet.TlDesiredAccuracy
import com.ikolvi.tracelet.TlNotificationAuthorizationStatus
import com.ikolvi.tracelet.TlMotionAuthorizationStatus
import com.ikolvi.tracelet.TraceletHostApi
import com.ikolvi.tracelet.FlutterError
import com.ikolvi.tracelet.flutter.service.HeadlessTaskService
import com.ikolvi.tracelet.sdk.TraceletSdk
import com.ikolvi.tracelet.sdk.model.AuthorizationStatus
import com.ikolvi.tracelet.sdk.util.OemCompat

/**
 * Pigeon-backed implementation of [TraceletHostApi].
 * 
 * Maps between Pigeon generated types and the raw Map-based API of TraceletSdk.
 */
class TraceletHostApiImpl(
    private val context: Context,
    private val headlessService: HeadlessTaskService,
) : TraceletHostApi {

    companion object {
        private const val TAG = "TraceletHostApiImpl"
    }

    private val sdk: TraceletSdk get() = TraceletSdk.getInstance(context)

    // =========================================================================
    // Converters: SDK Map → Pigeon types
    // =========================================================================

    @Suppress("UNCHECKED_CAST")
    private fun mapToTlState(m: Map<String, Any?>): TlState {
        val modeInt = (m["trackingMode"] as? Number)?.toInt() ?: 0
        return TlState(
            enabled = m["enabled"] as? Boolean ?: false,
            isMoving = m["isMoving"] as? Boolean ?: false,
            trackingMode = TlTrackingMode.ofRaw(modeInt) ?: TlTrackingMode.LOCATION,
            schedulerEnabled = m["schedulerEnabled"] as? Boolean ?: false,
            odometer = (m["odometer"] as? Number)?.toDouble() ?: 0.0,
            lastLocationTimestamp = m["lastLocationTimestamp"] as? String,
        )
    }

    @Suppress("UNCHECKED_CAST")
    private fun mapToTlLocation(m: Map<String, Any?>): TlLocation {
        val coords = m["coords"] as? Map<String, Any?> ?: emptyMap()
        val battery = m["battery"] as? Map<String, Any?> ?: emptyMap()
        val activity = m["activity"] as? Map<String, Any?>

        return TlLocation(
            coords = TlCoords(
                latitude = (coords["latitude"] as? Number)?.toDouble() ?: 0.0,
                longitude = (coords["longitude"] as? Number)?.toDouble() ?: 0.0,
                accuracy = (coords["accuracy"] as? Number)?.toDouble() ?: 0.0,
                speed = (coords["speed"] as? Number)?.toDouble() ?: -1.0,
                heading = (coords["heading"] as? Number)?.toDouble() ?: -1.0,
                altitude = (coords["altitude"] as? Number)?.toDouble() ?: 0.0,
                altitudeAccuracy = (coords["altitudeAccuracy"] as? Number)?.toDouble() ?: 0.0,
                speedAccuracy = (coords["speedAccuracy"] as? Number)?.toDouble() ?: 0.0,
                headingAccuracy = (coords["headingAccuracy"] as? Number)?.toDouble() ?: 0.0,
                ellipsoidalAltitude = (coords["ellipsoidalAltitude"] as? Number)?.toDouble(),
                floor = (coords["floor"] as? Number)?.toLong(),
            ),
            battery = TlBattery(
                level = (battery["level"] as? Number)?.toDouble() ?: -1.0,
                isCharging = battery["isCharging"] as? Boolean ?: false,
            ),
            timestamp = m["timestamp"] as? String ?: "",
            uuid = m["uuid"] as? String ?: "",
            isMoving = m["isMoving"] as? Boolean ?: false,
            odometer = (m["odometer"] as? Number)?.toDouble() ?: 0.0,
            event = m["event"] as? String,
            activity = if (activity != null) TlActivity(
                type = activity["type"] as? String ?: "unknown",
                confidence = (activity["confidence"] as? Number)?.toLong() ?: 0L,
            ) else null,
            extras = m["extras"] as? Map<String?, Any?>,
        )
    }

    @Suppress("UNCHECKED_CAST")
    private fun mapToTlGeofence(m: Map<String, Any?>): TlGeofence = TlGeofence(
        identifier = m["identifier"] as? String ?: "",
        latitude = (m["latitude"] as? Number)?.toDouble() ?: 0.0,
        longitude = (m["longitude"] as? Number)?.toDouble() ?: 0.0,
        radius = (m["radius"] as? Number)?.toDouble() ?: 0.0,
        notifyOnEntry = m["notifyOnEntry"] as? Boolean ?: true,
        notifyOnExit = m["notifyOnExit"] as? Boolean ?: true,
        notifyOnDwell = m["notifyOnDwell"] as? Boolean ?: false,
        loiteringDelay = (m["loiteringDelay"] as? Number)?.toLong() ?: 0L,
        extras = m["extras"] as? Map<String?, Any?>,
        vertices = (m["vertices"] as? List<*>)?.map { inner ->
            (inner as? List<*>)?.map { it as? Double }
        } as? List<List<Double?>?>,
    )

    private fun tlGeofenceToMap(g: TlGeofence): Map<String, Any?> = mapOf(
        "identifier" to g.identifier,
        "latitude" to g.latitude,
        "longitude" to g.longitude,
        "radius" to g.radius,
        "notifyOnEntry" to g.notifyOnEntry,
        "notifyOnExit" to g.notifyOnExit,
        "notifyOnDwell" to g.notifyOnDwell,
        "loiteringDelay" to g.loiteringDelay,
        "extras" to g.extras,
        "vertices" to g.vertices,
    )

    private fun tlOptionsToMap(o: TlCurrentPositionOptions): Map<String, Any?> = mapOf(
        "timeout" to o.timeout,
        "maximumAge" to o.maximumAge,
        "persist" to o.persist,
        "samples" to o.samples,
    )

    private fun tlConfigToSdkMap(c: TlConfig): Map<String, Any?> = buildMap {
        put("geo", buildMap {
            put("desiredAccuracy", c.geo.desiredAccuracy.raw)
            put("distanceFilter", c.geo.distanceFilter)
            put("stationaryRadius", c.geo.stationaryRadius)
            put("locationTimeout", c.geo.locationTimeout)
            put("disableElasticity", c.geo.disableElasticity)
            put("elasticityMultiplier", c.geo.elasticityMultiplier)
            put("stopAfterElapsedMinutes", c.geo.stopAfterElapsedMinutes)
            put("maxMonitoredGeofences", c.geo.maxMonitoredGeofences)
            put("enableTimestampMeta", c.geo.enableTimestampMeta)
            put("enableAdaptiveMode", c.geo.enableAdaptiveMode)
            put("periodicLocationInterval", c.geo.periodicLocationInterval)
            put("periodicDesiredAccuracy", c.geo.periodicDesiredAccuracy.raw)
            put("enableSparseUpdates", c.geo.enableSparseUpdates)
            put("sparseDistanceThreshold", c.geo.sparseDistanceThreshold)
            put("sparseMaxIdleSeconds", c.geo.sparseMaxIdleSeconds)
            put("enableDeadReckoning", c.geo.enableDeadReckoning)
            put("deadReckoningActivationDelay", c.geo.deadReckoningActivationDelay)
            put("deadReckoningMaxDuration", c.geo.deadReckoningMaxDuration)
            put("batteryBudgetPerHour", c.geo.batteryBudgetPerHour)
        })
        put("app", buildMap {
            put("stopOnTerminate", c.app.stopOnTerminate)
            put("startOnBoot", c.app.startOnBoot)
            put("heartbeatInterval", c.app.heartbeatInterval)
            put("schedule", c.app.schedule)
            put("remoteConfigUrl", c.app.remoteConfigUrl)
            put("remoteConfigHeaders", c.app.remoteConfigHeaders)
            put("remoteConfigTimeout", c.app.remoteConfigTimeout)
            put("remoteConfigRefreshInterval", c.app.remoteConfigRefreshInterval)
        })
        put("android", buildMap {
            put("locationUpdateInterval", c.android.locationUpdateInterval)
            put("fastestLocationUpdateInterval", c.android.fastestLocationUpdateInterval)
            put("deferTime", c.android.deferTime)
            put("allowIdenticalLocations", c.android.allowIdenticalLocations)
            put("geofenceModeHighAccuracy", c.android.geofenceModeHighAccuracy)
            put("periodicUseForegroundService", c.android.periodicUseForegroundService)
            put("periodicUseExactAlarms", c.android.periodicUseExactAlarms)
            put("scheduleUseAlarmManager", c.android.scheduleUseAlarmManager)
            put("foregroundService", buildMap {
                put("enabled", c.android.foregroundService.enabled)
                put("channelId", c.android.foregroundService.channelId)
                put("channelName", c.android.foregroundService.channelName)
                put("notificationTitle", c.android.foregroundService.notificationTitle)
                put("notificationText", c.android.foregroundService.notificationText)
                put("notificationColor", c.android.foregroundService.notificationColor)
                put("notificationSmallIcon", c.android.foregroundService.notificationSmallIcon)
                put("notificationLargeIcon", c.android.foregroundService.notificationLargeIcon)
                put("notificationPriority", c.android.foregroundService.notificationPriority.raw)
                put("notificationOngoing", c.android.foregroundService.notificationOngoing)
                put("actions", c.android.foregroundService.actions)
            })
        })
        put("http", buildMap {
            put("url", c.http.url)
            put("method", c.http.method.raw)
            put("headers", c.http.headers)
            put("params", c.http.params)
            put("autoSync", c.http.autoSync)
            put("batchSync", c.http.batchSync)
            put("maxBatchSize", c.http.maxBatchSize)
            put("autoSyncThreshold", c.http.autoSyncThreshold)
            put("httpTimeout", c.http.httpTimeout)
            put("locationsOrderDirection", c.http.locationsOrderDirection.raw)
            put("disableAutoSyncOnCellular", c.http.disableAutoSyncOnCellular)
            put("maxRetries", c.http.maxRetries)
            put("retryBackoffBase", c.http.retryBackoffBase)
            put("retryBackoffCap", c.http.retryBackoffCap)
            put("enableDeltaCompression", c.http.enableDeltaCompression)
            put("deltaCoordinatePrecision", c.http.deltaCoordinatePrecision)
        })
        put("logger", buildMap {
            put("logLevel", c.logger.logLevel.raw)
            put("logMaxDays", c.logger.logMaxDays)
            put("debug", c.logger.debug)
        })
        put("motion", buildMap {
            put("stopTimeout", c.motion.stopTimeout)
            put("motionTriggerDelay", c.motion.motionTriggerDelay)
            put("disableMotionActivityUpdates", c.motion.disableMotionActivityUpdates)
            put("isMoving", c.motion.isMoving)
            put("activityRecognitionInterval", c.motion.activityRecognitionInterval)
            put("minimumActivityRecognitionConfidence", c.motion.minimumActivityRecognitionConfidence)
            put("disableStopDetection", c.motion.disableStopDetection)
            put("stopDetectionDelay", c.motion.stopDetectionDelay)
            put("stopOnStationary", c.motion.stopOnStationary)
            put("stationaryRadius", c.motion.stationaryRadius)
            put("useSignificantChangesOnly", c.motion.useSignificantChangesOnly)
            put("shakeThreshold", c.motion.shakeThreshold)
            put("stillThreshold", c.motion.stillThreshold)
            put("stillSampleCount", c.motion.stillSampleCount)
        })
        put("geofence", buildMap {
            put("geofenceModeHighAccuracy", c.geofence.geofenceModeHighAccuracy)
            put("geofenceInitialTriggerEntry", c.geofence.geofenceInitialTriggerEntry)
            put("geofenceProximityRadius", c.geofence.geofenceProximityRadius)
            put("geofenceInitialTrigger", c.geofence.geofenceInitialTrigger)
        })
        put("persistence", buildMap {
            put("persistMode", c.persistence.persistMode.raw)
            put("maxDaysToPersist", c.persistence.maxDaysToPersist)
            put("maxRecordsToPersist", c.persistence.maxRecordsToPersist)
            put("disableProviderChangeRecord", c.persistence.disableProviderChangeRecord)
        })
        put("audit", buildMap {
            put("enabled", c.audit.enabled)
            put("hashAlgorithm", c.audit.hashAlgorithm.raw)
        })
        put("privacyZone", buildMap {
            put("enabled", c.privacyZone.enabled)
        })
        put("security", buildMap {
            put("encryptDatabase", c.security.encryptDatabase)
        })
        put("attestation", buildMap {
            put("enabled", c.attestation.enabled)
            put("refreshInterval", c.attestation.refreshInterval)
        })
    }

    private fun wrapException(err: String): FlutterError {
        Log.e(TAG, "SDK operation failed: $err")
        return FlutterError(err, "Tracelet SDK error: $err", null)
    }

    // =========================================================================
    // Lifecycle
    // =========================================================================

    @Suppress("UNCHECKED_CAST")
    override fun ready(config: TlConfig, callback: (Result<TlState>) -> Unit) {
        try {
            sdk.ready(tlConfigToSdkMap(config)) { state ->
                callback(Result.success(mapToTlState(state as Map<String, Any?>)))
            }
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun start(callback: (Result<TlState>) -> Unit) {
        try {
            val err = sdk.start()
            if (err != null) callback(Result.failure(wrapException(err)))
            else callback(Result.success(mapToTlState(sdk.getState())))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun stop(callback: (Result<TlState>) -> Unit) {
        try {
            sdk.stop()
            callback(Result.success(mapToTlState(sdk.getState())))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun startGeofences(callback: (Result<TlState>) -> Unit) {
        try {
            val err = sdk.startGeofences()
            if (err != null) callback(Result.failure(wrapException(err)))
            else callback(Result.success(mapToTlState(sdk.getState())))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun startPeriodic(callback: (Result<TlState>) -> Unit) {
        try {
            val err = sdk.startPeriodic()
            if (err != null) callback(Result.failure(wrapException(err)))
            else callback(Result.success(mapToTlState(sdk.getState())))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun getState(callback: (Result<TlState>) -> Unit) {
        try {
            callback(Result.success(mapToTlState(sdk.getState())))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    @Suppress("UNCHECKED_CAST")
    override fun setConfig(config: TlConfig, callback: (Result<TlState>) -> Unit) {
        try {
            val state = sdk.setConfig(tlConfigToSdkMap(config))
            callback(Result.success(mapToTlState(state as Map<String, Any?>)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun reset(config: TlConfig?, callback: (Result<TlState>) -> Unit) {
        try {
            sdk.reset(config?.let { tlConfigToSdkMap(it) })
            callback(Result.success(mapToTlState(sdk.getState())))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    // =========================================================================
    // Location
    // =========================================================================

    @Suppress("UNCHECKED_CAST")
    override fun getCurrentPosition(options: TlCurrentPositionOptions, callback: (Result<TlLocation>) -> Unit) {
        try {
            sdk.getCurrentPosition(tlOptionsToMap(options)) { loc ->
                if (loc != null) callback(Result.success(mapToTlLocation(loc as Map<String, Any?>)))
                else callback(Result.failure(FlutterError("LOCATION_FAILURE", "Failed to obtain location", null)))
            }
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    @Suppress("UNCHECKED_CAST")
    override fun getLastKnownLocation(options: TlCurrentPositionOptions?, callback: (Result<TlLocation?>) -> Unit) {
        try {
            sdk.getLastKnownLocation(options?.let { tlOptionsToMap(it) } ?: emptyMap()) { loc ->
                if (loc != null) callback(Result.success(mapToTlLocation(loc as Map<String, Any?>)))
                else callback(Result.success(null))
            }
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun watchPosition(options: TlCurrentPositionOptions, callback: (Result<Long>) -> Unit) {
        try {
            val watchId = sdk.watchPosition(tlOptionsToMap(options))
            callback(Result.success(watchId.toLong()))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun stopWatchPosition(watchId: Long, callback: (Result<Boolean>) -> Unit) {
        try {
            callback(Result.success(sdk.stopWatchPosition(watchId.toInt())))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun changePace(isMoving: Boolean, callback: (Result<Boolean>) -> Unit) {
        try {
            sdk.changePace(isMoving)
            callback(Result.success(true))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun getOdometer(callback: (Result<Double>) -> Unit) {
        try {
            callback(Result.success(sdk.getOdometer()))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    @Suppress("UNCHECKED_CAST")
    override fun setOdometer(value: Double, callback: (Result<TlLocation>) -> Unit) {
        try {
            val loc = sdk.setOdometer(value)
            callback(Result.success(mapToTlLocation(loc as Map<String, Any?>)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    // =========================================================================
    // Geofencing
    // =========================================================================

    override fun addGeofence(geofence: TlGeofence, callback: (Result<Boolean>) -> Unit) {
        try {
            callback(Result.success(sdk.addGeofence(tlGeofenceToMap(geofence))))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun addGeofences(geofences: List<TlGeofence>, callback: (Result<Boolean>) -> Unit) {
        try {
            sdk.addGeofences(geofences.map { tlGeofenceToMap(it) })
            callback(Result.success(true))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun removeGeofence(identifier: String, callback: (Result<Boolean>) -> Unit) {
        try {
            callback(Result.success(sdk.removeGeofence(identifier)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun removeGeofences(callback: (Result<Boolean>) -> Unit) {
        try {
            sdk.removeGeofences()
            callback(Result.success(true))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    @Suppress("UNCHECKED_CAST")
    override fun getGeofences(callback: (Result<List<TlGeofence?>>) -> Unit) {
        try {
            val list = sdk.getGeofences()
            callback(Result.success(list.map { mapToTlGeofence(it as Map<String, Any?>) } as List<TlGeofence?>))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    @Suppress("UNCHECKED_CAST")
    override fun getGeofence(identifier: String, callback: (Result<TlGeofence?>) -> Unit) {
        try {
            val g = sdk.getGeofence(identifier)
            if (g != null) callback(Result.success(mapToTlGeofence(g as Map<String, Any?>)))
            else callback(Result.success(null))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun geofenceExists(identifier: String, callback: (Result<Boolean>) -> Unit) {
        try {
            callback(Result.success(sdk.geofenceExists(identifier)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    // =========================================================================
    // Persistence
    // =========================================================================

    @Suppress("UNCHECKED_CAST")
    override fun getLocations(query: Map<String?, Any?>?, callback: (Result<List<TlLocation?>>) -> Unit) {
        try {
            val locs = sdk.getLocations(query as Map<String, Any?>?)
            callback(Result.success(locs.map { mapToTlLocation(it as Map<String, Any?>) } as List<TlLocation?>))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun getCount(query: Map<String?, Any?>?, callback: (Result<Long>) -> Unit) {
        try {
            callback(Result.success(sdk.getCount(query as Map<String, Any?>?).toLong()))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun destroyLocations(callback: (Result<Boolean>) -> Unit) {
        try {
            callback(Result.success(sdk.destroyLocations()))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun destroySyncedLocations(callback: (Result<Long>) -> Unit) {
        try {
            callback(Result.success(sdk.destroySyncedLocations().toLong()))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun destroyLocation(uuid: String, callback: (Result<Boolean>) -> Unit) {
        try {
            callback(Result.success(sdk.destroyLocation(uuid)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun insertLocation(params: Map<String?, Any?>, callback: (Result<String>) -> Unit) {
        try {
            callback(Result.success(sdk.insertLocation(params as Map<String, Any?>)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    // =========================================================================
    // Sync / HTTP
    // =========================================================================

    @Suppress("UNCHECKED_CAST")
    override fun sync(callback: (Result<List<TlLocation?>>) -> Unit) {
        try {
            sdk.sync { list -> callback(Result.success(list.map { mapToTlLocation(it as Map<String, Any?>) } as List<TlLocation?>)) }
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun setDynamicHeaders(headers: Map<String?, String?>, callback: (Result<Boolean>) -> Unit) {
        try {
            sdk.setDynamicHeaders(headers as Map<String, String>)
            callback(Result.success(true))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun setRouteContext(context: Map<String?, Any?>, callback: (Result<Boolean>) -> Unit) {
        try {
            sdk.setRouteContext(context as Map<String, Any?>)
            callback(Result.success(true))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun clearRouteContext(callback: (Result<Boolean>) -> Unit) {
        try {
            sdk.clearRouteContext()
            callback(Result.success(true))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    // =========================================================================
    // Permissions
    // =========================================================================

    private fun authStatusToTl(status: AuthorizationStatus): TlAuthorizationStatus {
        return when (status) {
            AuthorizationStatus.NOT_DETERMINED -> TlAuthorizationStatus.NOT_DETERMINED
            AuthorizationStatus.DENIED -> TlAuthorizationStatus.DENIED
            AuthorizationStatus.WHEN_IN_USE -> TlAuthorizationStatus.WHEN_IN_USE
            AuthorizationStatus.ALWAYS -> TlAuthorizationStatus.ALWAYS
            AuthorizationStatus.DENIED_FOREVER -> TlAuthorizationStatus.DENIED_FOREVER
        }
    }

    private fun notificationStatusToTl(status: AuthorizationStatus): TlNotificationAuthorizationStatus {
        return when (status) {
            AuthorizationStatus.NOT_DETERMINED -> TlNotificationAuthorizationStatus.NOT_DETERMINED
            AuthorizationStatus.DENIED -> TlNotificationAuthorizationStatus.DENIED
            AuthorizationStatus.WHEN_IN_USE, AuthorizationStatus.ALWAYS -> TlNotificationAuthorizationStatus.AUTHORIZED
            AuthorizationStatus.DENIED_FOREVER -> TlNotificationAuthorizationStatus.DENIED_FOREVER
        }
    }

    private fun motionStatusToTl(status: AuthorizationStatus): TlMotionAuthorizationStatus {
        return when (status) {
            AuthorizationStatus.NOT_DETERMINED -> TlMotionAuthorizationStatus.NOT_DETERMINED
            AuthorizationStatus.DENIED -> TlMotionAuthorizationStatus.DENIED
            AuthorizationStatus.WHEN_IN_USE, AuthorizationStatus.ALWAYS -> TlMotionAuthorizationStatus.AUTHORIZED
            AuthorizationStatus.DENIED_FOREVER -> TlMotionAuthorizationStatus.DENIED_FOREVER
        }
    }

    override fun getPermissionStatus(callback: (Result<TlAuthorizationStatus>) -> Unit) {
        try {
            val status = sdk.getPermissionStatus()
            callback(Result.success(authStatusToTl(status)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun requestPermission(callback: (Result<TlAuthorizationStatus>) -> Unit) {
        try {
            sdk.requestPermission { status ->
                callback(Result.success(authStatusToTl(status)))
            }
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun getNotificationPermissionStatus(callback: (Result<TlNotificationAuthorizationStatus>) -> Unit) {
        try {
            val status = sdk.getNotificationPermissionStatus()
            callback(Result.success(notificationStatusToTl(status)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun requestNotificationPermission(callback: (Result<TlNotificationAuthorizationStatus>) -> Unit) {
        try {
            sdk.requestNotificationPermission { status ->
                callback(Result.success(notificationStatusToTl(status)))
            }
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun canScheduleExactAlarms(callback: (Result<Boolean>) -> Unit) {
        try {
            callback(Result.success(sdk.canScheduleExactAlarms()))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun openExactAlarmSettings(callback: (Result<Boolean>) -> Unit) {
        try {
            callback(Result.success(sdk.openExactAlarmSettings()))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun getMotionPermissionStatus(callback: (Result<TlMotionAuthorizationStatus>) -> Unit) {
        try {
            val status = sdk.getMotionPermissionStatus()
            callback(Result.success(motionStatusToTl(status)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun requestMotionPermission(callback: (Result<TlMotionAuthorizationStatus>) -> Unit) {
        try {
            sdk.requestMotionPermission { status ->
                callback(Result.success(motionStatusToTl(status)))
            }
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun requestTemporaryFullAccuracy(purpose: String, callback: (Result<Long>) -> Unit) {
        // Android doesn't have temporary full accuracy (iOS only).
        // Return 0 (authorized) or -1 (not supported).
        callback(Result.success(0L))
    }

    // =========================================================================
    // Diagnostic / Utils
    // =========================================================================

    override fun isPowerSaveMode(callback: (Result<Boolean>) -> Unit) {
        try {
            callback(Result.success(sdk.isPowerSaveMode()))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    @Suppress("UNCHECKED_CAST")
    override fun getProviderState(callback: (Result<TlProviderChangeEvent>) -> Unit) {
        try {
            val p = sdk.getProviderState()
            callback(Result.success(TlProviderChangeEvent(
                enabled = p["enabled"] as? Boolean ?: false,
                gps = p["gps"] as? Boolean ?: false,
                network = p["network"] as? Boolean ?: false,
                status = (p["status"] as? Number)?.toLong() ?: 0L,
                accuracyAuthorization = (p["accuracyAuthorization"] as? Number)?.toLong() ?: 0L
            )))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun getDeviceInfo(callback: (Result<Map<String?, Any?>>) -> Unit) {
        try {
            val info: Map<String?, Any?> = mapOf(
                "model" to Build.MODEL,
                "manufacturer" to Build.MANUFACTURER,
                "version" to Build.VERSION.RELEASE,
                "sdk" to Build.VERSION.SDK_INT.toLong(),
                "brand" to Build.BRAND,
                "device" to Build.DEVICE,
                "hardware" to Build.HARDWARE
            )
            callback(Result.success(info))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun getSensors(callback: (Result<Map<String?, Any?>>) -> Unit) {
        try {
            callback(Result.success((sdk.getSensors() as Map<String?, Any?>)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun playSound(name: String, callback: (Result<Boolean>) -> Unit) {
        try {
            callback(Result.success(sdk.playSound(name)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun isIgnoringBatteryOptimizations(callback: (Result<Boolean>) -> Unit) {
        try {
            callback(Result.success(sdk.isIgnoringBatteryOptimizations()))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun requestSettings(action: String, callback: (Result<Boolean>) -> Unit) {
        try {
            callback(Result.success(sdk.requestSettings(action)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun showSettings(action: String, callback: (Result<Boolean>) -> Unit) {
        try {
            callback(Result.success(sdk.showSettings(action)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun getSettingsHealth(callback: (Result<Map<String?, Any?>>) -> Unit) {
        try {
            callback(Result.success((sdk.getSettingsHealth() as Map<String?, Any?>)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun openOemSettings(label: String, callback: (Result<Boolean>) -> Unit) {
        try {
            callback(Result.success(sdk.openOemSettings(label)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    // =========================================================================
    // Logging
    // =========================================================================

    override fun getLog(query: Map<String?, Any?>?, callback: (Result<String>) -> Unit) {
        try {
            callback(Result.success(sdk.getLog(query as Map<String, Any?>?)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun destroyLog(callback: (Result<Boolean>) -> Unit) {
        try {
            callback(Result.success(sdk.destroyLog()))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun emailLog(email: String, callback: (Result<Boolean>) -> Unit) {
        try {
            val logData = sdk.getLog(null)
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_EMAIL, arrayOf(email))
                putExtra(Intent.EXTRA_SUBJECT, "Tracelet SDK Log")
                putExtra(Intent.EXTRA_TEXT, logData)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            callback(Result.success(true))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun log(level: String, message: String, callback: (Result<Boolean>) -> Unit) {
        try {
            callback(Result.success(sdk.log(level, message)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    // =========================================================================
    // Scheduling
    // =========================================================================

    override fun startSchedule(callback: (Result<TlState>) -> Unit) {
        try {
            sdk.startSchedule()
            callback(Result.success(mapToTlState(sdk.getState())))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun stopSchedule(callback: (Result<TlState>) -> Unit) {
        try {
            sdk.stopSchedule()
            callback(Result.success(mapToTlState(sdk.getState())))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    // =========================================================================
    // Background Tasks
    // =========================================================================

    override fun startBackgroundTask(callback: (Result<Long>) -> Unit) {
        // Minimal implementation for now
        callback(Result.success(0L))
    }

    override fun stopBackgroundTask(taskId: Long, callback: (Result<Long>) -> Unit) {
        callback(Result.success(taskId))
    }

    // =========================================================================
    // Headless
    // =========================================================================

    override fun registerHeadlessTask(callbackIds: List<Long?>, callback: (Result<Boolean>) -> Unit) {
        try {
            if (callbackIds.size >= 2) {
                val id1 = callbackIds[0] ?: 0L
                val id2 = callbackIds[1] ?: 0L
                headlessService.registerCallbacks(id1, id2)
                callback(Result.success(true))
            } else {
                callback(Result.failure(FlutterError("INVALID_ARGUMENT", "Expected 2 callback IDs", null)))
            }
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun registerHeadlessHeadersCallback(callbackIds: List<Long?>, callback: (Result<Boolean>) -> Unit) {
        // Implementation similar to registerHeadlessTask but for headers
        callback(Result.success(true))
    }

    override fun registerHeadlessSyncBodyBuilder(callbackIds: List<Long?>, callback: (Result<Boolean>) -> Unit) {
        // Implementation similar to registerHeadlessTask but for body builder
        callback(Result.success(true))
    }

    // =========================================================================
    // Enterprise
    // =========================================================================

    override fun verifyAuditTrail(callback: (Result<Map<String?, Any?>>) -> Unit) {
        try {
            callback(Result.success((sdk.verifyAuditChain() as Map<String?, Any?>)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun getAuditProof(uuid: String, callback: (Result<Map<String?, Any?>?>) -> Unit) {
        try {
            callback(Result.success((sdk.getAuditProof(uuid) as Map<String?, Any?>?)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun addPrivacyZone(zone: Map<String?, Any?>, callback: (Result<Boolean>) -> Unit) {
        try {
            callback(Result.success(sdk.addPrivacyZone(zone as Map<String, Any?>)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun addPrivacyZones(zones: List<Map<String?, Any?>?>, callback: (Result<Boolean>) -> Unit) {
        try {
            callback(Result.success(sdk.addPrivacyZones(zones as List<Map<String, Any?>>)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun removePrivacyZone(identifier: String, callback: (Result<Boolean>) -> Unit) {
        try {
            callback(Result.success(sdk.removePrivacyZone(identifier)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun removePrivacyZones(callback: (Result<Boolean>) -> Unit) {
        try {
            callback(Result.success(sdk.removePrivacyZones()))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    @Suppress("UNCHECKED_CAST")
    override fun getPrivacyZones(callback: (Result<List<Map<String?, Any?>?>>) -> Unit) {
        try {
            callback(Result.success(sdk.getPrivacyZones() as List<Map<String?, Any?>?>))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun isDatabaseEncrypted(callback: (Result<Boolean>) -> Unit) {
        try {
            callback(Result.success(sdk.isDatabaseEncrypted()))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun encryptDatabase(callback: (Result<Boolean>) -> Unit) {
        try {
            callback(Result.success(sdk.encryptDatabase()))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun getAttestationToken(callback: (Result<Map<String?, Any?>?>) -> Unit) {
        try {
            sdk.attestDevice { callback(Result.success(it as Map<String?, Any?>?)) }
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun getCarbonReport(query: Map<String?, Any?>?, callback: (Result<Map<String?, Any?>>) -> Unit) {
        try {
            callback(Result.success((sdk.getCarbonReport(query as Map<String, Any?>?) as Map<String?, Any?>)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun getDeadReckoningState(callback: (Result<Map<String?, Any?>?>) -> Unit) {
        try {
            callback(Result.success((sdk.getDeadReckoningState() as Map<String?, Any?>?)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }
}
