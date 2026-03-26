package com.ikolvi.tracelet.flutter

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import com.ikolvi.tracelet.TlActivity
import com.ikolvi.tracelet.TlAuthorizationStatus
import com.ikolvi.tracelet.TlBattery
import com.ikolvi.tracelet.TlCoords
import com.ikolvi.tracelet.TlCurrentPositionOptions
import com.ikolvi.tracelet.TlGeofence
import com.ikolvi.tracelet.TlLocation
import com.ikolvi.tracelet.TlProviderChangeEvent
import com.ikolvi.tracelet.TlState
import com.ikolvi.tracelet.TraceletHostApi
import com.ikolvi.tracelet.flutter.service.HeadlessTaskService
import com.ikolvi.tracelet.sdk.TraceletSdk

/**
 * Pigeon-backed implementation of [TraceletHostApi].
 *
 * Delegates every call to [TraceletSdk] and converts between Pigeon typed
 * objects ([TlState], [TlLocation], etc.) and the SDK's raw map format.
 */
class TraceletHostApiImpl(
    private val context: Context,
    private val headlessService: HeadlessTaskService,
) : TraceletHostApi {

    private val sdk: TraceletSdk get() = TraceletSdk.getInstance(context)

    // =========================================================================
    // Converters: SDK Map → Pigeon types
    // =========================================================================

    @Suppress("UNCHECKED_CAST")
    private fun mapToTlState(m: Map<String, Any?>): TlState = TlState(
        enabled = m["enabled"] as? Boolean ?: false,
        isMoving = m["isMoving"] as? Boolean ?: false,
        trackingMode = (m["trackingMode"] as? Number)?.toLong() ?: 0L,
        schedulerEnabled = m["schedulerEnabled"] as? Boolean ?: false,
        odometer = (m["odometer"] as? Number)?.toDouble() ?: 0.0,
        lastLocationTimestamp = m["lastLocationTimestamp"] as? String,
    )

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
        },
    )

    // Pigeon TlGeofence → SDK Map
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

    // TlCurrentPositionOptions → SDK Map
    private fun optionsToMap(o: TlCurrentPositionOptions): Map<String, Any?> = mapOf(
        "timeout" to o.timeout,
        "maximumAge" to o.maximumAge,
        "persist" to o.persist,
        "samples" to o.samples,
    )

    @Suppress("UNCHECKED_CAST")
    private fun mapToTlProviderState(m: Map<String, Any?>): TlProviderChangeEvent =
        TlProviderChangeEvent(
            enabled = m["enabled"] as? Boolean ?: false,
            gps = m["gps"] as? Boolean ?: false,
            network = m["network"] as? Boolean ?: false,
            status = (m["status"] as? Number)?.toLong() ?: 0L,
            accuracyAuthorization = (m["accuracyAuthorization"] as? Number)?.toLong(),
        )

    private fun intToAuthStatus(value: Int): TlAuthorizationStatus =
        TlAuthorizationStatus.values().getOrElse(value) {
            TlAuthorizationStatus.NOT_DETERMINED
        }

    // =========================================================================
    // Lifecycle
    // =========================================================================

    @Suppress("UNCHECKED_CAST")
    override fun ready(config: Map<String, Any?>, callback: (Result<TlState>) -> Unit) {
        sdk.ready(config) { state ->
            callback(Result.success(mapToTlState(state as Map<String, Any?>)))
        }
    }

    override fun start(callback: (Result<TlState>) -> Unit) {
        val err = sdk.start()
        if (err != null) {
            callback(Result.failure(Exception(err)))
        } else {
            @Suppress("UNCHECKED_CAST")
            callback(Result.success(mapToTlState(sdk.getState() as Map<String, Any?>)))
        }
    }

    override fun stop(callback: (Result<TlState>) -> Unit) {
        sdk.stop()
        @Suppress("UNCHECKED_CAST")
        callback(Result.success(mapToTlState(sdk.getState() as Map<String, Any?>)))
    }

    override fun startGeofences(callback: (Result<TlState>) -> Unit) {
        val err = sdk.startGeofences()
        if (err != null) {
            callback(Result.failure(Exception(err)))
        } else {
            @Suppress("UNCHECKED_CAST")
            callback(Result.success(mapToTlState(sdk.getState() as Map<String, Any?>)))
        }
    }

    override fun startPeriodic(callback: (Result<TlState>) -> Unit) {
        val err = sdk.startPeriodic()
        if (err != null) {
            callback(Result.failure(Exception(err)))
        } else {
            @Suppress("UNCHECKED_CAST")
            callback(Result.success(mapToTlState(sdk.getState() as Map<String, Any?>)))
        }
    }

    @Suppress("UNCHECKED_CAST")
    override fun getState(callback: (Result<TlState>) -> Unit) {
        callback(Result.success(mapToTlState(sdk.getState() as Map<String, Any?>)))
    }

    @Suppress("UNCHECKED_CAST")
    override fun setConfig(config: Map<String, Any?>, callback: (Result<TlState>) -> Unit) {
        callback(Result.success(mapToTlState(sdk.setConfig(config) as Map<String, Any?>)))
    }

    @Suppress("UNCHECKED_CAST")
    override fun reset(config: Map<String, Any?>?, callback: (Result<TlState>) -> Unit) {
        sdk.reset(config)
        callback(Result.success(mapToTlState(sdk.getState() as Map<String, Any?>)))
    }

    // =========================================================================
    // Location
    // =========================================================================

    @Suppress("UNCHECKED_CAST")
    override fun getCurrentPosition(
        options: TlCurrentPositionOptions,
        callback: (Result<TlLocation>) -> Unit,
    ) {
        sdk.getCurrentPosition(optionsToMap(options)) { loc ->
            if (loc != null) {
                callback(Result.success(mapToTlLocation(loc as Map<String, Any?>)))
            } else {
                callback(Result.failure(Exception("LOCATION_UNAVAILABLE")))
            }
        }
    }

    @Suppress("UNCHECKED_CAST")
    override fun getLastKnownLocation(
        options: Map<String, Any?>?,
        callback: (Result<TlLocation?>) -> Unit,
    ) {
        sdk.getLastKnownLocation(options ?: emptyMap()) { loc ->
            if (loc != null) {
                callback(Result.success(mapToTlLocation(loc as Map<String, Any?>)))
            } else {
                callback(Result.success(null))
            }
        }
    }

    override fun watchPosition(options: Map<String, Any?>, callback: (Result<Long>) -> Unit) {
        val watchId = sdk.watchPosition(options)
        if (watchId >= 0) {
            callback(Result.success(watchId.toLong()))
        } else {
            callback(Result.failure(Exception("PERMISSION_DENIED")))
        }
    }

    override fun stopWatchPosition(watchId: Long, callback: (Result<Boolean>) -> Unit) {
        callback(Result.success(sdk.stopWatchPosition(watchId.toInt())))
    }

    override fun changePace(isMoving: Boolean, callback: (Result<Boolean>) -> Unit) {
        sdk.changePace(isMoving)
        callback(Result.success(true))
    }

    override fun getOdometer(callback: (Result<Double>) -> Unit) {
        callback(Result.success(sdk.getOdometer()))
    }

    @Suppress("UNCHECKED_CAST")
    override fun setOdometer(value: Double, callback: (Result<TlLocation>) -> Unit) {
        val loc = sdk.setOdometer(value) as Map<String, Any?>
        callback(Result.success(mapToTlLocation(loc)))
    }

    // =========================================================================
    // Geofencing
    // =========================================================================

    override fun addGeofence(geofence: TlGeofence, callback: (Result<Boolean>) -> Unit) {
        callback(Result.success(sdk.addGeofence(tlGeofenceToMap(geofence))))
    }

    override fun addGeofences(geofences: List<TlGeofence>, callback: (Result<Boolean>) -> Unit) {
        sdk.addGeofences(geofences.map(::tlGeofenceToMap))
        callback(Result.success(true))
    }

    override fun removeGeofence(identifier: String, callback: (Result<Boolean>) -> Unit) {
        callback(Result.success(sdk.removeGeofence(identifier)))
    }

    override fun removeGeofences(callback: (Result<Boolean>) -> Unit) {
        callback(Result.success(sdk.removeGeofences()))
    }

    @Suppress("UNCHECKED_CAST")
    override fun getGeofences(callback: (Result<List<TlGeofence>>) -> Unit) {
        val raw = sdk.getGeofences() as List<Map<String, Any?>>
        callback(Result.success(raw.map(::mapToTlGeofence)))
    }

    @Suppress("UNCHECKED_CAST")
    override fun getGeofence(identifier: String, callback: (Result<TlGeofence?>) -> Unit) {
        val raw = sdk.getGeofence(identifier) as? Map<String, Any?>
        callback(Result.success(raw?.let(::mapToTlGeofence)))
    }

    override fun geofenceExists(identifier: String, callback: (Result<Boolean>) -> Unit) {
        callback(Result.success(sdk.geofenceExists(identifier)))
    }

    // =========================================================================
    // Persistence
    // =========================================================================

    @Suppress("UNCHECKED_CAST")
    override fun getLocations(
        query: Map<String, Any?>?,
        callback: (Result<List<TlLocation>>) -> Unit,
    ) {
        val raw = sdk.getLocations(query) as List<Map<String, Any?>>
        callback(Result.success(raw.map(::mapToTlLocation)))
    }

    override fun getCount(query: Map<String, Any?>?, callback: (Result<Long>) -> Unit) {
        callback(Result.success(sdk.getCount(query).toLong()))
    }

    override fun destroyLocations(callback: (Result<Boolean>) -> Unit) {
        callback(Result.success(sdk.destroyLocations()))
    }

    override fun destroySyncedLocations(callback: (Result<Long>) -> Unit) {
        callback(Result.success(sdk.destroySyncedLocations().toLong()))
    }

    override fun destroyLocation(uuid: String, callback: (Result<Boolean>) -> Unit) {
        callback(Result.success(sdk.destroyLocation(uuid)))
    }

    override fun insertLocation(
        params: Map<String, Any?>,
        callback: (Result<String>) -> Unit,
    ) {
        callback(Result.success(sdk.insertLocation(params)))
    }

    // =========================================================================
    // HTTP Sync
    // =========================================================================

    @Suppress("UNCHECKED_CAST")
    override fun sync(callback: (Result<List<TlLocation>>) -> Unit) {
        sdk.sync { synced ->
            val list = (synced as? List<Map<String, Any?>>) ?: emptyList()
            callback(Result.success(list.map(::mapToTlLocation)))
        }
    }

    override fun setDynamicHeaders(
        headers: Map<String, String>,
        callback: (Result<Boolean>) -> Unit,
    ) {
        sdk.setDynamicHeaders(headers)
        callback(Result.success(true))
    }

    override fun setRouteContext(
        context: Map<String, Any?>,
        callback: (Result<Boolean>) -> Unit,
    ) {
        sdk.setRouteContext(context)
        callback(Result.success(true))
    }

    override fun clearRouteContext(callback: (Result<Boolean>) -> Unit) {
        sdk.clearRouteContext()
        callback(Result.success(true))
    }

    // =========================================================================
    // Permissions
    // =========================================================================

    override fun getPermissionStatus(callback: (Result<TlAuthorizationStatus>) -> Unit) {
        callback(Result.success(intToAuthStatus(sdk.getPermissionStatus())))
    }

    override fun requestPermission(callback: (Result<TlAuthorizationStatus>) -> Unit) {
        sdk.requestPermission { status ->
            callback(Result.success(intToAuthStatus(status)))
        }
    }

    override fun getNotificationPermissionStatus(callback: (Result<Long>) -> Unit) {
        callback(Result.success(sdk.getNotificationPermissionStatus().toLong()))
    }

    override fun requestNotificationPermission(callback: (Result<Long>) -> Unit) {
        sdk.requestNotificationPermission { status ->
            callback(Result.success(status.toLong()))
        }
    }

    override fun canScheduleExactAlarms(callback: (Result<Boolean>) -> Unit) {
        callback(Result.success(sdk.canScheduleExactAlarms()))
    }

    override fun openExactAlarmSettings(callback: (Result<Boolean>) -> Unit) {
        callback(Result.success(sdk.openExactAlarmSettings()))
    }

    override fun getMotionPermissionStatus(callback: (Result<Long>) -> Unit) {
        callback(Result.success(sdk.getMotionPermissionStatus().toLong()))
    }

    override fun requestMotionPermission(callback: (Result<Long>) -> Unit) {
        sdk.requestMotionPermission { status ->
            callback(Result.success(status.toLong()))
        }
    }

    override fun requestTemporaryFullAccuracy(
        purpose: String,
        callback: (Result<Long>) -> Unit,
    ) {
        // No-op on Android — only meaningful on iOS 14+.
        callback(Result.success(sdk.getPermissionStatus().toLong()))
    }

    // =========================================================================
    // Utility
    // =========================================================================

    override fun isPowerSaveMode(callback: (Result<Boolean>) -> Unit) {
        callback(Result.success(sdk.isPowerSaveMode()))
    }

    @Suppress("UNCHECKED_CAST")
    override fun getProviderState(callback: (Result<TlProviderChangeEvent>) -> Unit) {
        callback(Result.success(mapToTlProviderState(sdk.getProviderState() as Map<String, Any?>)))
    }

    override fun getDeviceInfo(callback: (Result<Map<String, Any?>>) -> Unit) {
        callback(Result.success(mapOf(
            "model" to Build.MODEL,
            "manufacturer" to Build.MANUFACTURER,
            "version" to Build.VERSION.RELEASE,
            "platform" to "android",
            "framework" to "flutter",
            "sdk" to Build.VERSION.SDK_INT,
        )))
    }

    @Suppress("UNCHECKED_CAST")
    override fun getSensors(callback: (Result<Map<String, Any?>>) -> Unit) {
        callback(Result.success(sdk.getSensors() as Map<String, Any?>))
    }

    override fun playSound(name: String, callback: (Result<Boolean>) -> Unit) {
        callback(Result.success(sdk.playSound(name)))
    }

    override fun isIgnoringBatteryOptimizations(callback: (Result<Boolean>) -> Unit) {
        callback(Result.success(sdk.isIgnoringBatteryOptimizations()))
    }

    override fun requestSettings(action: String, callback: (Result<Boolean>) -> Unit) {
        callback(Result.success(sdk.requestSettings(action)))
    }

    override fun showSettings(action: String, callback: (Result<Boolean>) -> Unit) {
        callback(Result.success(sdk.showSettings(action)))
    }

    @Suppress("UNCHECKED_CAST")
    override fun getSettingsHealth(callback: (Result<Map<String, Any?>>) -> Unit) {
        callback(Result.success(sdk.getSettingsHealth() as Map<String, Any?>))
    }

    override fun openOemSettings(label: String, callback: (Result<Boolean>) -> Unit) {
        callback(Result.success(sdk.openOemSettings(label)))
    }

    // =========================================================================
    // Logging
    // =========================================================================

    override fun getLog(query: Map<String, Any?>?, callback: (Result<String>) -> Unit) {
        callback(Result.success(sdk.getLog(query)))
    }

    override fun destroyLog(callback: (Result<Boolean>) -> Unit) {
        callback(Result.success(sdk.destroyLog()))
    }

    override fun emailLog(email: String, callback: (Result<Boolean>) -> Unit) {
        val logContent = sdk.getLog(null)
        try {
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_EMAIL, arrayOf(email))
                putExtra(Intent.EXTRA_SUBJECT, "Tracelet Log")
                putExtra(Intent.EXTRA_TEXT, logContent)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            callback(Result.success(true))
        } catch (_: Exception) {
            callback(Result.success(false))
        }
    }

    override fun log(level: String, message: String, callback: (Result<Boolean>) -> Unit) {
        callback(Result.success(sdk.log(level, message)))
    }

    // =========================================================================
    // Scheduling
    // =========================================================================

    @Suppress("UNCHECKED_CAST")
    override fun startSchedule(callback: (Result<TlState>) -> Unit) {
        sdk.startSchedule()
        callback(Result.success(mapToTlState(sdk.getState() as Map<String, Any?>)))
    }

    @Suppress("UNCHECKED_CAST")
    override fun stopSchedule(callback: (Result<TlState>) -> Unit) {
        sdk.stopSchedule()
        callback(Result.success(mapToTlState(sdk.getState() as Map<String, Any?>)))
    }

    // =========================================================================
    // Background Tasks
    // =========================================================================

    override fun startBackgroundTask(callback: (Result<Long>) -> Unit) {
        // No-op on Android — background tasks are managed by the OS.
        callback(Result.success(0L))
    }

    override fun stopBackgroundTask(taskId: Long, callback: (Result<Long>) -> Unit) {
        callback(Result.success(taskId))
    }

    // =========================================================================
    // Headless
    // =========================================================================

    override fun registerHeadlessTask(
        callbackIds: List<Long>,
        callback: (Result<Boolean>) -> Unit,
    ) {
        val registrationId = callbackIds.getOrNull(0) ?: -1L
        val dispatchId = callbackIds.getOrNull(1) ?: -1L
        headlessService.registerCallbacks(registrationId, dispatchId)
        callback(Result.success(true))
    }

    override fun registerHeadlessHeadersCallback(
        callbackIds: List<Long>,
        callback: (Result<Boolean>) -> Unit,
    ) {
        storeHeadlessCallback(callbackIds, "headlessHeaders")
        callback(Result.success(true))
    }

    override fun registerHeadlessSyncBodyBuilder(
        callbackIds: List<Long>,
        callback: (Result<Boolean>) -> Unit,
    ) {
        storeHeadlessCallback(callbackIds, "headlessSyncBody")
        callback(Result.success(true))
    }

    private fun storeHeadlessCallback(callbackIds: List<Long>, key: String) {
        val registrationId = callbackIds.getOrNull(0) ?: -1L
        val dispatchId = callbackIds.getOrNull(1) ?: -1L
        val prefs = context.getSharedPreferences("com.tracelet.headless", Context.MODE_PRIVATE)
        prefs.edit()
            .putLong("${key}_registrationId", registrationId)
            .putLong("${key}_dispatchId", dispatchId)
            .apply()
    }

    // =========================================================================
    // Enterprise: Audit Trail
    // =========================================================================

    @Suppress("UNCHECKED_CAST")
    override fun verifyAuditTrail(callback: (Result<Map<String, Any?>>) -> Unit) {
        callback(Result.success(sdk.verifyAuditChain() as Map<String, Any?>))
    }

    @Suppress("UNCHECKED_CAST")
    override fun getAuditProof(uuid: String, callback: (Result<Map<String, Any?>?>) -> Unit) {
        callback(Result.success(sdk.getAuditProof(uuid) as? Map<String, Any?>))
    }

    // =========================================================================
    // Enterprise: Privacy Zones
    // =========================================================================

    override fun addPrivacyZone(zone: Map<String, Any?>, callback: (Result<Boolean>) -> Unit) {
        callback(Result.success(sdk.addPrivacyZone(zone)))
    }

    @Suppress("UNCHECKED_CAST")
    override fun addPrivacyZones(
        zones: List<Map<String, Any?>>,
        callback: (Result<Boolean>) -> Unit,
    ) {
        callback(Result.success(sdk.addPrivacyZones(zones)))
    }

    override fun removePrivacyZone(identifier: String, callback: (Result<Boolean>) -> Unit) {
        callback(Result.success(sdk.removePrivacyZone(identifier)))
    }

    override fun removePrivacyZones(callback: (Result<Boolean>) -> Unit) {
        callback(Result.success(sdk.removePrivacyZones()))
    }

    @Suppress("UNCHECKED_CAST")
    override fun getPrivacyZones(callback: (Result<List<Map<String, Any?>>>) -> Unit) {
        callback(Result.success(sdk.getPrivacyZones() as List<Map<String, Any?>>))
    }

    // =========================================================================
    // Enterprise: Encrypted Database
    // =========================================================================

    override fun isDatabaseEncrypted(callback: (Result<Boolean>) -> Unit) {
        callback(Result.success(sdk.isDatabaseEncrypted()))
    }

    override fun encryptDatabase(callback: (Result<Boolean>) -> Unit) {
        try {
            callback(Result.success(sdk.encryptDatabase()))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }

    // =========================================================================
    // Enterprise: Device Attestation
    // =========================================================================

    override fun getAttestationToken(callback: (Result<Map<String, Any?>?>) -> Unit) {
        sdk.attestDevice { token ->
            sdk.mainHandler.post {
                @Suppress("UNCHECKED_CAST")
                callback(Result.success(token as? Map<String, Any?>))
            }
        }
    }

    // =========================================================================
    // Enterprise: Carbon Estimator
    // =========================================================================

    @Suppress("UNCHECKED_CAST")
    override fun getCarbonReport(
        query: Map<String, Any?>?,
        callback: (Result<Map<String, Any?>>) -> Unit,
    ) {
        callback(Result.success(sdk.getCarbonReport(query) as Map<String, Any?>))
    }

    // =========================================================================
    // Enterprise: Dead Reckoning
    // =========================================================================

    @Suppress("UNCHECKED_CAST")
    override fun getDeadReckoningState(callback: (Result<Map<String, Any?>?>) -> Unit) {
        callback(Result.success(sdk.getDeadReckoningState() as? Map<String, Any?>))
    }
}
