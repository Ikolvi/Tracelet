package com.ikolvi.tracelet.flutter

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import com.ikolvi.tracelet.TlActivity
import com.ikolvi.tracelet.TlAuthorizationStatus
import com.ikolvi.tracelet.TlBattery
import com.ikolvi.tracelet.TlCoords
import com.ikolvi.tracelet.TlCurrentPositionOptions
import com.ikolvi.tracelet.TlGeofence
import com.ikolvi.tracelet.TlLocation
import com.ikolvi.tracelet.TlLocationTuning
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
    /**
     * Invoked when the Dart side of the engine this instance is registered on
     * subscribes to Tracelet's events (#364).
     *
     * Optional so the existing two-argument construction keeps working; the
     * plugin passes it for every engine, and only a secondary UI engine acts
     * on it. See [TraceletAndroidPlugin.onDartEventsSubscribed].
     */
    private val onDartEventsSubscribed: (() -> Unit)? = null,
) : TraceletHostApi {

    companion object {
        private const val TAG = "TraceletHostApiImpl"
    }

    private val sdk: TraceletSdk get() = TraceletSdk.getInstance(context)

    private val activeWakeLocks = ConcurrentHashMap<Long, PowerManager.WakeLock>()
    private val nextTaskId = AtomicLong(1)

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
        val addressMap = m["address"] as? Map<String, Any?>

        // #280: TlLocation has no locationSource/reducedAccuracy fields, so
        // carry them through `extras` — the same transport the live onLocation
        // path uses (EventDispatcher.mapToTlLocation) and that Location.fromMap
        // unpacks. Without this, getLocations()/sync drop the DB-restored
        // classification and report the "unknown"/false defaults.
        val extras = ((m["extras"] as? Map<String?, Any?>) ?: emptyMap()).toMutableMap()
        (m["locationSource"] as? String)?.let { extras["locationSource"] = it }
        (m["reducedAccuracy"] as? Boolean)?.let { extras["reducedAccuracy"] = it }

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
                // Native emits snake_case `is_charging`; accept both for safety.
                isCharging = (battery["is_charging"] ?: battery["isCharging"]) as? Boolean ?: false,
            ),
            timestamp = m["timestamp"] as? String ?: "",
            uuid = m["uuid"] as? String ?: "",
            // Native emits snake_case `is_moving`; accept both for safety.
            isMoving = (m["is_moving"] ?: m["isMoving"]) as? Boolean ?: false,
            odometer = (m["odometer"] as? Number)?.toDouble() ?: 0.0,
            event = m["event"] as? String,
            activity = if (activity != null) TlActivity(
                type = activity["type"] as? String ?: "unknown",
                confidence = (activity["confidence"] as? Number)?.toLong() ?: 0L,
            ) else null,
            extras = if (extras.isEmpty()) null else extras,
            address = addressMap?.let {
                com.ikolvi.tracelet.TlAddress(
                    street = it["street"] as? String,
                    city = it["city"] as? String,
                    state = it["state"] as? String,
                    postalCode = it["postalCode"] as? String ?: it["postal_code"] as? String,
                    country = it["country"] as? String,
                )
            },
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

    private fun tlOptionsToMap(o: TlCurrentPositionOptions): Map<String, Any?> = buildMap {
        put("timeout", o.timeout)
        put("maximumAge", o.maximumAge)
        put("persist", o.persist)
        put("samples", o.samples)
        o.accuracyTarget?.let { put("accuracyTarget", it) }
        o.requestId?.let { put("requestId", it) }
        // Previously dropped here, so getCurrentPosition(desiredAccuracy:/extras:)
        // were silently ignored (#175). Forward them to the SDK.
        o.desiredAccuracy?.let { put("desiredAccuracy", it.raw) }
        o.extras?.let { put("extras", it) }
    }

    private fun tlConfigToSdkMap(c: TlConfig): Map<String, Any?> = buildMap {
        put("geo", buildMap {
            put("desiredAccuracy", c.geo.desiredAccuracy?.raw)
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
            put("periodicDesiredAccuracy", c.geo.periodicDesiredAccuracy?.raw)
            put("enableSparseUpdates", c.geo.enableSparseUpdates)
            put("sparseDistanceThreshold", c.geo.sparseDistanceThreshold)
            put("sparseMaxIdleSeconds", c.geo.sparseMaxIdleSeconds)
            put("enableDeadReckoning", c.geo.enableDeadReckoning)
            put("deadReckoningActivationDelay", c.geo.deadReckoningActivationDelay)
            put("deadReckoningMaxDuration", c.geo.deadReckoningMaxDuration)
            put("batteryBudgetPerHour", c.geo.batteryBudgetPerHour)
            put("resolveAddress", c.geo.resolveAddress)
            put("filter", buildMap {
                put("trackingAccuracyThreshold", c.geo.filter?.trackingAccuracyThreshold)
                put("maxImpliedSpeed", c.geo.filter?.maxImpliedSpeed)
                put("odometerAccuracyThreshold", c.geo.filter?.odometerAccuracyThreshold)
                put("policy", c.geo.filter?.policy?.raw)
                put("rejectMockLocations", c.geo.filter?.rejectMockLocations)
                put("mockDetectionLevel", c.geo.filter?.mockDetectionLevel)
                put("useKalmanFilter", c.geo.filter?.useKalmanFilter)
            })
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
            // High-accuracy geofencing: prefer the cross-platform GeofenceConfig
            // flag, OR'd with the deprecated Android-only flag for backward
            // compatibility (set further below in the Geofence section too).
            put(
                "geofenceModeHighAccuracy",
                (c.geofence.geofenceModeHighAccuracy ?: false) || (c.android.geofenceModeHighAccuracy ?: false),
            )
            put("periodicUseForegroundService", c.android.periodicUseForegroundService)
            put("periodicUseExactAlarms", c.android.periodicUseExactAlarms)
            put("scheduleUseAlarmManager", c.android.scheduleUseAlarmManager)
            put("releaseWakelockWhenStationary", c.android.releaseWakelockWhenStationary)
            // Foreground-service fields are nullable end to end: null means the
            // caller never mentioned the field, and ConfigManager.setConfig()
            // skips nulls so the persisted notification settings survive a
            // partial setConfig(). Do not substitute defaults for null here —
            // that reintroduces #320, where any setConfig() omitting this
            // section silently rewrote the stored title, channel and
            // showNotificationOnPauseOnly with defaults.
            put("foregroundService", buildMap {
                val fg = c.android.foregroundService
                put("enabled", fg?.enabled)
                put("channelId", fg?.channelId)
                put("channelName", fg?.channelName)
                put("notificationTitle", fg?.notificationTitle)
                put("notificationText", fg?.notificationText)
                put("notificationColor", fg?.notificationColor)
                put("notificationSmallIcon", fg?.notificationSmallIcon)
                put("notificationLargeIcon", fg?.notificationLargeIcon)
                put("notificationStartedAt", fg?.notificationStartedAt)
                put("notificationShowTimer", fg?.notificationShowTimer)
                put("notificationOnlyAlertOnce", fg?.notificationOnlyAlertOnce)
                put("notificationPriority", fg?.notificationPriority?.let { it.raw - 2 })
                put("notificationOngoing", fg?.notificationOngoing)
                put("showNotificationOnPauseOnly", fg?.showNotificationOnPauseOnly)
                put("actions", fg?.actions)
            })
        })
        put("http", buildMap {
            put("url", c.http.url)
            put("method", c.http.method?.raw)
            put("headers", c.http.headers)
            put("params", c.http.params)
            put("extras", c.http.extras)
            put("httpRootProperty", c.http.httpRootProperty)
            put("sslPinningFingerprints", c.http.sslPinningFingerprints)
            put("sslPinningCertificates", c.http.sslPinningCertificates)
            put("autoSync", c.http.autoSync)
            put("batchSync", c.http.batchSync)
            put("maxBatchSize", c.http.maxBatchSize)
            put("autoSyncThreshold", c.http.autoSyncThreshold)
            put("autoSyncDelay", c.http.autoSyncDelay)
            put("syncInterval", c.http.syncInterval)
            put("httpTimeout", c.http.httpTimeout)
            put("locationsOrderDirection", c.http.locationsOrderDirection?.raw)
            put("disableAutoSyncOnCellular", c.http.disableAutoSyncOnCellular)
            put("maxRetries", c.http.maxRetries)
            put("retryBackoffBase", c.http.retryBackoffBase)
            put("retryBackoffCap", c.http.retryBackoffCap)
            put("enableDeltaCompression", c.http.enableDeltaCompression)
            put("deltaCoordinatePrecision", c.http.deltaCoordinatePrecision)
            put("syncTelematics", c.http.syncTelematics)
            put("telematicsUrl", c.http.telematicsUrl)
        })
        put("logger", buildMap {
            put("logLevel", c.logger.logLevel?.raw)
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
            put("activityTypes", c.motion.activityTypes?.map { it?.raw })
            put("stationaryRadius", c.motion.stationaryRadius)
            put("useSignificantChangesOnly", c.motion.useSignificantChangesOnly)
            // Sensor thresholds are only forwarded when the app set them. Sending
            // them unconditionally overrode each platform's tuned default with a
            // single cross-platform scalar (Dart's defaults are the Android ones),
            // which on iOS landed ~4x stricter on stillness after the m/s²→g
            // conversion. Absent key ⇒ ConfigManager's own default applies.
            c.motion.shakeThreshold?.let { put("shakeThreshold", it) }
            c.motion.stillThreshold?.let { put("stillThreshold", it) }
            c.motion.stillSampleCount?.let { put("stillSampleCount", it) }
            put("motionDetectionMode", c.motion.motionDetectionMode?.raw)
            put("speedMovingThreshold", c.motion.speedMovingThreshold)
            put("speedStationaryDelay", c.motion.speedStationaryDelay)
            put("stationaryTrackingMode", c.motion.stationaryTrackingMode?.raw)
            put("stationaryPeriodicInterval", c.motion.stationaryPeriodicInterval)
            put("stationaryPeriodicAccuracy", c.motion.stationaryPeriodicAccuracy?.raw)
            put("speedWakeConfirmCount", c.motion.speedWakeConfirmCount)
        })
        put("geofence", buildMap {
            put("geofenceInitialTriggerEntry", c.geofence.geofenceInitialTriggerEntry)
            put("geofenceProximityRadius", c.geofence.geofenceProximityRadius)
            put("geofenceInitialTrigger", c.geofence.geofenceInitialTrigger)
            put("geofenceExitAccuracyMax", c.geofence.geofenceExitAccuracyMax)
        })
        put("persistence", buildMap {
            put("persistMode", c.persistence.persistMode?.raw)
            put("maxDaysToPersist", c.persistence.maxDaysToPersist)
            put("maxRecordsToPersist", c.persistence.maxRecordsToPersist)
            put("disableProviderChangeRecord", c.persistence.disableProviderChangeRecord)
        })
        put("auditEnabled", c.audit.enabled)
        put("audit", buildMap {
            put("enabled", c.audit.enabled)
            put("hashAlgorithm", c.audit.hashAlgorithm?.raw)
        })
        put("privacyZoneEnabled", c.privacyZone.enabled)
        put("privacyZone", buildMap {
            put("enabled", c.privacyZone.enabled)
        })
        put("encryptDatabase", c.security.encryptDatabase)
        put("security", buildMap {
            put("encryptDatabase", c.security.encryptDatabase)
        })
        put("attestationEnabled", c.attestation.enabled)
        put("attestationRefreshInterval", c.attestation.refreshInterval)
        put("attestation", buildMap {
            put("enabled", c.attestation.enabled)
            put("refreshInterval", c.attestation.refreshInterval)
        })
        put("telematics", buildMap {
            put("enableDrivingEvents", c.telematics.enableDrivingEvents)
            put("harshBrakingG", c.telematics.harshBrakingG)
            put("harshAccelerationG", c.telematics.harshAccelerationG)
            put("harshCorneringG", c.telematics.harshCorneringG)
            put("speedLimitKmh", c.telematics.speedLimitKmh)
            put("speedingToleranceKmh", c.telematics.speedingToleranceKmh)
            put("speedingMinDurationMs", c.telematics.speedingMinDurationMs)
            put("minSpeedForEventsKmh", c.telematics.minSpeedForEventsKmh)
            put("eventDebounceMs", c.telematics.eventDebounceMs)
        })
        put("classifier", buildMap {
            put("enableFusedClassifier", c.classifier.enableFusedClassifier)
            put("fusedClassifierAuthoritative", c.classifier.fusedClassifierAuthoritative)
            put("modeSwitchDwellMs", c.classifier.modeSwitchDwellMs)
            put("minModeConfidence", c.classifier.minModeConfidence)
            put("autoTuneFromTransportMode", c.classifier.autoTuneFromTransportMode)
        })
        put("impact", buildMap {
            put("enableCrashDetection", c.impact.enableCrashDetection)
            put("enableFallDetection", c.impact.enableFallDetection)
            put("crashGThreshold", c.impact.crashGThreshold)
            put("crashMinSpeedKmh", c.impact.crashMinSpeedKmh)
            put("fallGThreshold", c.impact.fallGThreshold)
            put("confirmWindowMs", c.impact.confirmWindowMs)
            put("minImpactConfidence", c.impact.minImpactConfidence)
            // #183 crash ML model (opt-in)
            put("crashModelUrl", c.impact.crashModelUrl)
            put("crashModelSha256", c.impact.crashModelSha256)
            put("crashModelThreshold", c.impact.crashModelThreshold)
            put("crashModelUnlockUrl", c.impact.crashModelUnlockUrl)
            put("crashModelLicenseKey", c.impact.crashModelLicenseKey)
        })
    }

    private fun wrapException(err: String): FlutterError {
        sdk.logger.error("SDK operation failed: $err")
        return FlutterError(err, "Tracelet SDK error: $err", null)
    }

    // =========================================================================
    // Lifecycle
    // =========================================================================

    @Suppress("UNCHECKED_CAST")
    override fun requestStateFlush() {
        // `PigeonTracelet._ensureEventsRegistered()` calls this once per isolate,
        // immediately after `TraceletEventApi.setUp(...)`, on the first access to
        // any event stream. Since the HostApi is registered per messenger, its
        // arrival here is the native side's evidence that *this* engine's Dart
        // side is listening — which is what decides whether a secondary engine
        // may join the event fan-out (#364). Signalled before the flush so the
        // re-emitted state reaches an engine that just subscribed.
        onDartEventsSubscribed?.invoke()
        sdk.requestStateFlush()
    }

    override fun ready(config: TlConfig, callback: (Result<TlState>) -> Unit) {
        try {
            sdk.ready(tlConfigToSdkMap(config)) { state ->
                callback(Result.success(mapToTlState(state as Map<String, Any?>)))
            }
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun start(callback: (Result<TlState>) -> Unit) {
        if (!sdk.isReady) {
            callback(Result.failure(FlutterError("NOT_READY", "Call ready() before start()", null)))
            return
        }
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
        if (!sdk.isReady) {
            callback(Result.failure(FlutterError("NOT_READY", "Call ready() before startGeofences()", null)))
            return
        }
        try {
            val err = sdk.startGeofences()
            if (err != null) callback(Result.failure(wrapException(err)))
            else callback(Result.success(mapToTlState(sdk.getState())))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun startPeriodic(callback: (Result<TlState>) -> Unit) {
        if (!sdk.isReady) {
            callback(Result.failure(FlutterError("NOT_READY", "Call ready() before startPeriodic()", null)))
            return
        }
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
        // Match iOS: surface NOT_READY instead of silently returning a default
        // state when setConfig() is called before ready(). Keeps the Flutter
        // plugin behavior identical across platforms so callers can rely on the
        // PlatformException(NOT_READY) signal everywhere.
        if (!sdk.isReady) {
            callback(Result.failure(FlutterError("NOT_READY", "Call ready() before setConfig()", null)))
            return
        }
        try {
            val state = sdk.setConfig(tlConfigToSdkMap(config))
            callback(Result.success(mapToTlState(state as Map<String, Any?>)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun reset(config: TlConfig?, callback: (Result<TlState>) -> Unit) {
        if (!sdk.isReady) {
            callback(Result.failure(FlutterError("NOT_READY", "Call ready() before reset()", null)))
            return
        }
        try {
            sdk.reset(config?.let { tlConfigToSdkMap(it) })
            callback(Result.success(mapToTlState(sdk.getState())))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun updateNotification(callback: (Result<Unit>) -> Unit) {
        // #257: refresh the live foreground-service notification so it reflects
        // ForegroundServiceConfig changes applied via setConfig(), without
        // restarting the tracking pipeline. Safe no-op if the service isn't
        // running — LocationService only reposts when already promoted.
        try {
            sdk.updateNotification()
            callback(Result.success(Unit))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    // =========================================================================
    // Location
    // =========================================================================

    @Suppress("UNCHECKED_CAST")
    override fun getCurrentPosition(options: TlCurrentPositionOptions, callback: (Result<TlLocation>) -> Unit) {
        if (!sdk.isReady) {
            callback(Result.failure(FlutterError("NOT_READY", "Call ready() before getCurrentPosition()", null)))
            return
        }
        try {
            sdk.getCurrentPosition(tlOptionsToMap(options)) { loc ->
                if (loc != null) callback(Result.success(mapToTlLocation(loc as Map<String, Any?>)))
                else callback(Result.failure(FlutterError("LOCATION_FAILURE", "Failed to obtain location", null)))
            }
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun cancelCurrentPosition(requestId: String, callback: (Result<Boolean>) -> Unit) {
        try {
            callback(Result.success(sdk.cancelCurrentPosition(requestId)))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
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
        if (!sdk.isReady) {
            callback(Result.failure(FlutterError("NOT_READY", "Call ready() before changePace()", null)))
            return
        }
        try {
            sdk.changePace(isMoving)
            callback(Result.success(true))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun updateLocationProviderOptions(
        desiredAccuracy: TlDesiredAccuracy?,
        distanceFilter: Double?,
        callback: (Result<Boolean>) -> Unit,
    ) {
        if (!sdk.isReady) {
            callback(Result.failure(FlutterError("NOT_READY", "Call ready() before updateLocationProviderOptions()", null)))
            return
        }
        try {
            callback(
                Result.success(
                    sdk.updateLocationProviderOptions(desiredAccuracy?.raw, distanceFilter)
                )
            )
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun confirmImpact(id: Long): Boolean =
        if (sdk.isReady) sdk.confirmImpact(id) else false

    override fun cancelImpact(id: Long): Boolean =
        if (sdk.isReady) sdk.cancelImpact(id) else false

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

    override fun getForegroundServiceHealth(callback: (Result<Map<String?, Any?>>) -> Unit) {
        try {
            @Suppress("UNCHECKED_CAST")
            callback(Result.success(sdk.getForegroundServiceHealth() as Map<String?, Any?>))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    /**
     * Reports the thresholds actually in force in the Rust processor (#303).
     *
     * Read back from the processor rather than from ConfigManager: those two
     * could silently disagree, which is the whole bug #303 fixed, so a getter
     * that answered from config would be unable to detect a regression. Null
     * before a processor exists, and while a transport-mode auto-tune is in
     * force these are the tuned values, not the configured ones.
     */
    override fun getCurrentLocationTuning(callback: (Result<TlLocationTuning?>) -> Unit) {
        try {
            val t = sdk.getCurrentLocationTuning()
            callback(
                Result.success(
                    t?.let {
                        TlLocationTuning(
                            distanceFilter = it.distanceFilter,
                            trackingAccuracyThreshold = it.trackingAccuracyThreshold.toLong(),
                            odometerAccuracyThreshold = it.odometerAccuracyThreshold.toLong(),
                            maxImpliedSpeed = it.maxImpliedSpeed.toLong(),
                        )
                    }
                )
            )
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun openOemSettings(label: String, callback: (Result<Boolean>) -> Unit) {
        try {
            callback(Result.success(sdk.openOemSettings(label)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun showPowerManager(callback: (Result<Boolean>) -> Unit) {
        try {
            callback(Result.success(sdk.showPowerManager()))
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
    // Telematics
    // =========================================================================

    override fun getTelematicsEvents(limit: Long, callback: (Result<List<com.ikolvi.tracelet.TlTelematicsRecord?>>) -> Unit) {
        try {
            val events = sdk.getTelematicsEvents(limit.toInt())
            val mapped = events.map { e ->
                com.ikolvi.tracelet.TlTelematicsRecord(
                    id = e.id,
                    eventType = e.eventType,
                    severity = e.severity,
                    // #367: the magnitudes behind the normalized severity.
                    speed = e.speed,
                    value = e.value,
                    latitude = e.latitude,
                    longitude = e.longitude,
                    timestamp = e.timestamp,
                    synced = e.synced,
                    // #402: the trip this event was recorded during.
                    tripId = e.tripId
                )
            }
            callback(Result.success(mapped))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun destroyTelematicsEvents(callback: (Result<Boolean>) -> Unit) {
        try {
            callback(Result.success(sdk.destroyTelematicsEvents()))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun simulateTelematicsEvent(eventType: String, severity: Double, latitude: Double, longitude: Double, callback: (Result<Boolean>) -> Unit) {
        try {
            callback(Result.success(sdk.simulateTelematicsEvent(eventType, severity, latitude, longitude)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun debugRunCrashModelInference(peakG: Double, speedKmh: Double, crashLike: Boolean, callback: (Result<Map<String, Any?>>) -> Unit) {
        try {
            callback(Result.success(sdk.debugRunCrashModelInference(peakG, speedKmh, crashLike)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    // =========================================================================
    // Scheduling
    // =========================================================================

    override fun startSchedule(callback: (Result<TlState>) -> Unit) {
        if (!sdk.isReady) {
            callback(Result.failure(FlutterError("NOT_READY", "Call ready() before startSchedule()", null)))
            return
        }
        try {
            sdk.startSchedule()
            callback(Result.success(mapToTlState(sdk.getState())))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun stopSchedule(callback: (Result<TlState>) -> Unit) {
        if (!sdk.isReady) {
            callback(Result.failure(FlutterError("NOT_READY", "Call ready() before stopSchedule()", null)))
            return
        }
        try {
            sdk.stopSchedule()
            callback(Result.success(mapToTlState(sdk.getState())))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    // =========================================================================
    // Background Tasks
    // =========================================================================

    override fun startBackgroundTask(callback: (Result<Long>) -> Unit) {
        try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            if (pm == null) {
                callback(Result.success(0L))
                return
            }

            val taskId = nextTaskId.getAndIncrement()
            val wakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK, 
                "com.tracelet:task:$taskId"
            )
            
            // Acquire with a 30-second absolute timeout to prevent battery drain
            wakeLock.acquire(30_000L)
            activeWakeLocks[taskId] = wakeLock
            
            sdk.logger.debug("Acquired transient WakeLock for task: $taskId")
            callback(Result.success(taskId))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }

    override fun stopBackgroundTask(taskId: Long, callback: (Result<Long>) -> Unit) {
        try {
            val wakeLock = activeWakeLocks.remove(taskId)
            if (wakeLock != null && wakeLock.isHeld) {
                wakeLock.release()
                sdk.logger.debug("Released transient WakeLock for task: $taskId")
            }
            callback(Result.success(taskId))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }

    // =========================================================================
    // Headless
    // =========================================================================

    override fun registerHeadlessTask(callbackIds: List<Long?>, callback: (Result<Boolean>) -> Unit) {
        try {
            if (callbackIds.size >= 2) {
                val id1 = callbackIds[0] ?: 0L
                val id2 = callbackIds[1] ?: 0L
                headlessService.registerCallbacks(HeadlessTaskService.CallbackType.MAIN, id1, id2)
                callback(Result.success(true))
            } else {
                callback(Result.failure(FlutterError("INVALID_ARGUMENT", "Expected 2 callback IDs", null)))
            }
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun registerHeadlessHeadersCallback(callbackIds: List<Long?>, callback: (Result<Boolean>) -> Unit) {
        try {
            if (callbackIds.size >= 2) {
                val id1 = callbackIds[0] ?: 0L
                val id2 = callbackIds[1] ?: 0L
                headlessService.registerCallbacks(HeadlessTaskService.CallbackType.HEADERS, id1, id2)
                callback(Result.success(true))
            } else {
                callback(Result.failure(FlutterError("INVALID_ARGUMENT", "Expected 2 callback IDs", null)))
            }
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun registerHeadlessSyncBodyBuilder(callbackIds: List<Long?>, callback: (Result<Boolean>) -> Unit) {
        try {
            if (callbackIds.size >= 2) {
                val id1 = callbackIds[0] ?: 0L
                val id2 = callbackIds[1] ?: 0L
                headlessService.registerCallbacks(HeadlessTaskService.CallbackType.SYNC_BODY, id1, id2)
                callback(Result.success(true))
            } else {
                callback(Result.failure(FlutterError("INVALID_ARGUMENT", "Expected 2 callback IDs", null)))
            }
        } catch (e: Exception) { callback(Result.failure(e)) }
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
    override fun getPrivacyZones(callback: (Result<List<Any?>>) -> Unit) {
        try {
            callback(Result.success(sdk.getPrivacyZones() as List<Any?>))
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

    override fun getCarbonReport(query: Map<String, Any?>?, callback: (Result<Map<String, Any?>>) -> Unit) {
        try {
            callback(Result.success((sdk.getCarbonReport(query) as Map<String, Any?>)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }

    override fun getLogs(limit: Long, callback: (Result<List<com.ikolvi.tracelet.TlLogEntry?>>) -> Unit) {
        val records = sdk.getLogs(limit.toInt())
        val mapped = records.map { r ->
            com.ikolvi.tracelet.TlLogEntry(
                id = r.id.toLong(),
                level = r.level,
                message = r.message,
                timestamp = r.timestamp
            )
        }
        callback(Result.success(mapped))
    }

    override fun clearLogs(callback: (Result<Unit>) -> Unit) {
        sdk.clearLogs()
        callback(Result.success(Unit))
    }

    override fun getDeadReckoningState(callback: (Result<Map<String?, Any?>?>) -> Unit) {
        try {
            callback(Result.success((sdk.getDeadReckoningState() as Map<String?, Any?>?)))
        } catch (e: Exception) { callback(Result.failure(e)) }
    }
}
