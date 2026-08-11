package com.ikolvi.tracelet.sdk.model

import org.json.JSONArray
import org.json.JSONObject

/** Standard configuration profiles for Tracelet. */
enum class TraceletProfile {
    /** Turn-by-Turn, precise tracking without adaptive degradation. */
    HIGH_ACCURACY,
    
    /** Standard tracking balancing battery and accuracy. Uses smart motion detection and adaptive mode. */
    BALANCED,
    
    /** Background-only, battery-sensitive tracking with sparse updates and cellular/wifi locations. */
    LOW_POWER
}

/**
 * Typed configuration for the Tracelet SDK.
 */
data class TraceletConfig(
    val geo: GeoConfig = GeoConfig(),
    val app: AppConfig = AppConfig(),
    val android: AndroidConfig = AndroidConfig(),
    val ios: IosConfig = IosConfig(),
    val http: HttpConfig = HttpConfig(),
    val logger: LoggerConfig = LoggerConfig(),
    val motion: MotionConfig = MotionConfig(),
    val geofence: GeofenceConfig = GeofenceConfig(),
    val persistence: PersistenceConfig = PersistenceConfig(),
    val audit: AuditConfig = AuditConfig(),
    val privacyZone: PrivacyZoneConfig = PrivacyZoneConfig(),
    val security: SecurityConfig = SecurityConfig(),
    val attestation: AttestationConfig = AttestationConfig(),
) {
    companion object {
        private val profilesJson = mapOf(
            TraceletProfile.HIGH_ACCURACY to """{"geo":{"desiredAccuracy":0,"distanceFilter":5.0,"stationaryRadius":25.0,"enableAdaptiveMode":false,"disableElasticity":true,"enableDeadReckoning":true,"filter":{"useKalmanFilter":true,"rejectMockLocations":true}},"motion":{"motionDetectionMode":0,"stationaryTrackingMode":0,"stopTimeout":3},"android":{"geofenceModeHighAccuracy":true,"locationUpdateInterval":1000,"fastestLocationUpdateInterval":500}}""",
            TraceletProfile.BALANCED to """{"geo":{"desiredAccuracy":1,"distanceFilter":20.0,"stationaryRadius":50.0,"enableAdaptiveMode":true,"disableElasticity":false,"elasticityMultiplier":1.0,"filter":{"useKalmanFilter":false}},"motion":{"motionDetectionMode":2,"stationaryTrackingMode":1,"stopTimeout":5},"android":{"geofenceModeHighAccuracy":false,"locationUpdateInterval":5000}}""",
            TraceletProfile.LOW_POWER to """{"geo":{"desiredAccuracy":2,"distanceFilter":50.0,"stationaryRadius":100.0,"enableAdaptiveMode":true,"disableElasticity":false,"elasticityMultiplier":2.0,"enableSparseUpdates":true,"sparseDistanceThreshold":100.0},"motion":{"motionDetectionMode":1,"stationaryTrackingMode":1,"stopTimeout":2},"android":{"geofenceModeHighAccuracy":false,"locationUpdateInterval":10000}}"""
        )

        private fun jsonToMap(json: JSONObject): Map<String, Any?> {
            val map = mutableMapOf<String, Any?>()
            val keys = json.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                val value = json.get(key)
                map[key] = when (value) {
                    JSONObject.NULL -> null
                    is JSONObject -> jsonToMap(value)
                    is JSONArray -> {
                        val list = mutableListOf<Any?>()
                        for (i in 0 until value.length()) {
                            val item = value.get(i)
                            list.add(if (item is JSONObject) jsonToMap(item) else item)
                        }
                        list
                    }
                    else -> value
                }
            }
            return map
        }

        private fun fromProfile(profile: TraceletProfile): TraceletConfig {
            val jsonStr = profilesJson[profile] ?: throw IllegalArgumentException("Unknown profile")
            val baseMap = jsonToMap(JSONObject(jsonStr))
            return fromMap(baseMap)
        }

        /** High Accuracy profile tailored for turn-by-turn navigation or precise tracking. */
        fun highAccuracy() = fromProfile(TraceletProfile.HIGH_ACCURACY)
        
        /** Balanced profile tailored for standard social/fleet apps, balancing accuracy and battery. */
        fun balanced() = fromProfile(TraceletProfile.BALANCED)
        
        /** Low Power profile tailored for background-only coarse tracking to maximize battery life. */
        fun lowPower() = fromProfile(TraceletProfile.LOW_POWER)

        @Suppress("UNCHECKED_CAST")
        fun fromMap(map: Map<String, Any?>): TraceletConfig = TraceletConfig(
            geo = (map["geo"] as? Map<String, Any?>)?.let { GeoConfig.fromMap(it) } ?: GeoConfig.fromMap(map),
            app = (map["app"] as? Map<String, Any?>)?.let { AppConfig.fromMap(it) } ?: AppConfig.fromMap(map),
            android = (map["android"] as? Map<String, Any?>)?.let { AndroidConfig.fromMap(it) } ?: AndroidConfig.fromMap(map),
            ios = (map["ios"] as? Map<String, Any?>)?.let { IosConfig.fromMap(it) } ?: IosConfig.fromMap(map),
            http = (map["http"] as? Map<String, Any?>)?.let { HttpConfig.fromMap(it) } ?: HttpConfig.fromMap(map),
            logger = (map["logger"] as? Map<String, Any?>)?.let { LoggerConfig.fromMap(it) } ?: LoggerConfig.fromMap(map),
            motion = (map["motion"] as? Map<String, Any?>)?.let { MotionConfig.fromMap(it) } ?: MotionConfig.fromMap(map),
            geofence = (map["geofence"] as? Map<String, Any?>)?.let { GeofenceConfig.fromMap(it) } ?: GeofenceConfig.fromMap(map),
            persistence = (map["persistence"] as? Map<String, Any?>)?.let { PersistenceConfig.fromMap(it) } ?: PersistenceConfig.fromMap(map),
            audit = (map["audit"] as? Map<String, Any?>)?.let { AuditConfig.fromMap(it) } ?: AuditConfig.fromMap(map),
            privacyZone = (map["privacyZone"] as? Map<String, Any?>)?.let { PrivacyZoneConfig.fromMap(it) } ?: PrivacyZoneConfig.fromMap(map),
            security = (map["security"] as? Map<String, Any?>)?.let { SecurityConfig.fromMap(it) } ?: SecurityConfig.fromMap(map),
            attestation = (map["attestation"] as? Map<String, Any?>)?.let { AttestationConfig.fromMap(it) } ?: AttestationConfig.fromMap(map),
        )
    }

    fun toMap(): Map<String, Any?> = buildMap {
        put("geo", geo.toMap())
        put("app", app.toMap())
        put("android", android.toMap())
        put("ios", ios.toMap())
        put("http", http.toMap())
        put("logger", logger.toMap())
        put("motion", motion.toMap())
        put("geofence", geofence.toMap())
        put("persistence", persistence.toMap())
        put("audit", audit.toMap())
        put("privacyZone", privacyZone.toMap())
        put("security", security.toMap())
        put("attestation", attestation.toMap())
    }
}

// Enums
enum class DesiredAccuracy(val value: Int) { HIGH(0), MEDIUM(1), LOW(2), VERY_LOW(3), PASSIVE(4); companion object { fun fromValue(v: Int) = entries.firstOrNull { it.value == v } ?: HIGH } }
enum class LogLevel(val value: Int) { VERBOSE(0), DEBUG(1), INFO(2), WARN(3), ERROR(4); companion object { fun fromValue(v: Int) = entries.firstOrNull { it.value == v } ?: INFO } }
enum class HttpMethod(val value: Int) { POST(0), PUT(1); companion object { fun fromValue(v: Int) = entries.firstOrNull { it.value == v } ?: POST } }
enum class PersistMode(val value: Int) { ALL(0), LOCATION(1), GEOFENCE(2), NONE(3); companion object { fun fromValue(v: Int) = entries.firstOrNull { it.value == v } ?: ALL } }
enum class LocationFilterPolicy(val value: Int) { ADJUST(0), IGNORE(1), DISCARD(2); companion object { fun fromValue(v: Int) = entries.firstOrNull { it.value == v } ?: ADJUST } }
enum class MockDetectionLevel(val value: Int) { DISABLED(0), BASIC(1), HEURISTIC(2); companion object { fun fromValue(v: Int) = entries.firstOrNull { it.value == v } ?: DISABLED } }
enum class LocationActivityType(val value: Int) { OTHER(0), AUTOMOTIVE_NAVIGATION(1), FITNESS(2), OTHER_NAVIGATION(3), AIRBORNE(4); companion object { fun fromValue(v: Int) = entries.firstOrNull { it.value == v } ?: OTHER } }
enum class LocationAuthorizationRequest { ALWAYS, WHEN_IN_USE }
enum class NotificationPriority(val value: Int) { MIN(-2), LOW(-1), DEFAULT(0), HIGH(1), MAX(2); companion object { fun fromValue(v: Int) = entries.firstOrNull { it.value == v } ?: DEFAULT } }
enum class LocationOrder(val value: Int) { ASC(0), DESC(1); companion object { fun fromValue(v: Int) = entries.firstOrNull { it.value == v } ?: ASC } }
enum class ActivityType { STILL, ON_FOOT, WALKING, RUNNING, ON_BICYCLE, IN_VEHICLE, UNKNOWN }
enum class HashAlgorithm(val value: Int) { SHA256(0), SHA512(1); companion object { fun fromValue(v: Int) = entries.firstOrNull { it.value == v } ?: SHA256 } }

// Sub-configs
data class GeoConfig(
    val desiredAccuracy: DesiredAccuracy = DesiredAccuracy.HIGH,
    val distanceFilter: Double = 10.0,
    val stationaryRadius: Double = 25.0,
    val locationTimeout: Int = 60,
    val disableElasticity: Boolean = false,
    val elasticityMultiplier: Double = 1.0,
    val stopAfterElapsedMinutes: Int = -1,
    val maxMonitoredGeofences: Int = -1,
    val enableTimestampMeta: Boolean = false,
    val enableAdaptiveMode: Boolean = false,
    val periodicLocationInterval: Int = 900,
    val periodicDesiredAccuracy: DesiredAccuracy = DesiredAccuracy.MEDIUM,
    val enableSparseUpdates: Boolean = false,
    val sparseDistanceThreshold: Double = 50.0,
    val sparseMaxIdleSeconds: Int = 300,
    val enableDeadReckoning: Boolean = false,
    val deadReckoningActivationDelay: Int = 10,
    val deadReckoningMaxDuration: Int = 120,
    val batteryBudgetPerHour: Double = 0.0,
    val resolveAddress: Boolean = false,
    val filter: LocationFilter? = null,
) {
    companion object {
        fun fromMap(m: Map<String, Any?>) = GeoConfig(
            desiredAccuracy = DesiredAccuracy.fromValue((m["desiredAccuracy"] as? Number)?.toInt() ?: 0),
            distanceFilter = (m["distanceFilter"] as? Number)?.toDouble() ?: 10.0,
            stationaryRadius = (m["stationaryRadius"] as? Number)?.toDouble() ?: 25.0,
            locationTimeout = (m["locationTimeout"] as? Number)?.toInt() ?: 60,
            disableElasticity = m["disableElasticity"] as? Boolean ?: false,
            elasticityMultiplier = (m["elasticityMultiplier"] as? Number)?.toDouble() ?: 1.0,
            stopAfterElapsedMinutes = (m["stopAfterElapsedMinutes"] as? Number)?.toInt() ?: -1,
            maxMonitoredGeofences = (m["maxMonitoredGeofences"] as? Number)?.toInt() ?: -1,
            enableTimestampMeta = m["enableTimestampMeta"] as? Boolean ?: false,
            enableAdaptiveMode = m["enableAdaptiveMode"] as? Boolean ?: false,
            periodicLocationInterval = (m["periodicLocationInterval"] as? Number)?.toInt() ?: 900,
            periodicDesiredAccuracy = DesiredAccuracy.fromValue((m["periodicDesiredAccuracy"] as? Number)?.toInt() ?: 1),
            enableSparseUpdates = m["enableSparseUpdates"] as? Boolean ?: false,
            sparseDistanceThreshold = (m["sparseDistanceThreshold"] as? Number)?.toDouble() ?: 50.0,
            sparseMaxIdleSeconds = (m["sparseMaxIdleSeconds"] as? Number)?.toInt() ?: 300,
            enableDeadReckoning = m["enableDeadReckoning"] as? Boolean ?: false,
            deadReckoningActivationDelay = (m["deadReckoningActivationDelay"] as? Number)?.toInt() ?: 10,
            deadReckoningMaxDuration = (m["deadReckoningMaxDuration"] as? Number)?.toInt() ?: 120,
            batteryBudgetPerHour = (m["batteryBudgetPerHour"] as? Number)?.toDouble() ?: 0.0,
            resolveAddress = m["resolveAddress"] as? Boolean ?: false,
            filter = (m["filter"] as? Map<String, Any?>)?.let { LocationFilter.fromMap(it) }
        )
    }
    fun toMap(): Map<String, Any?> = buildMap {
        put("desiredAccuracy", desiredAccuracy.value); put("distanceFilter", distanceFilter); put("stationaryRadius", stationaryRadius)
        put("locationTimeout", locationTimeout); put("disableElasticity", disableElasticity); put("elasticityMultiplier", elasticityMultiplier)
        put("stopAfterElapsedMinutes", stopAfterElapsedMinutes); put("maxMonitoredGeofences", maxMonitoredGeofences)
        put("enableTimestampMeta", enableTimestampMeta); put("enableAdaptiveMode", enableAdaptiveMode)
        put("periodicLocationInterval", periodicLocationInterval); put("periodicDesiredAccuracy", periodicDesiredAccuracy.value)
        put("enableSparseUpdates", enableSparseUpdates); put("sparseDistanceThreshold", sparseDistanceThreshold)
        put("sparseMaxIdleSeconds", sparseMaxIdleSeconds); put("enableDeadReckoning", enableDeadReckoning)
        put("deadReckoningActivationDelay", deadReckoningActivationDelay); put("deadReckoningMaxDuration", deadReckoningMaxDuration)
        put("batteryBudgetPerHour", batteryBudgetPerHour); put("resolveAddress", resolveAddress); filter?.let { put("filter", it.toMap()) }
    }
}

data class AndroidConfig(
    val locationUpdateInterval: Int = 1000,
    val fastestLocationUpdateInterval: Int = 500,
    val deferTime: Int = 0,
    val allowIdenticalLocations: Boolean = false,
    val geofenceModeHighAccuracy: Boolean = false,
    val periodicUseForegroundService: Boolean = false,
    val periodicUseExactAlarms: Boolean = false,
    val scheduleUseAlarmManager: Boolean = false,
    val foregroundService: ForegroundServiceConfig = ForegroundServiceConfig(),
    /**
     * Drops the OEM Wakelock when the device enters a fully stationary state.
     * Resolves Issue #162.
     */
    val releaseWakelockWhenStationary: Boolean = false,
) {
    companion object {
        fun fromMap(m: Map<String, Any?>) = AndroidConfig(
            locationUpdateInterval = (m["locationUpdateInterval"] as? Number)?.toInt() ?: 1000,
            fastestLocationUpdateInterval = (m["fastestLocationUpdateInterval"] as? Number)?.toInt() ?: 500,
            deferTime = (m["deferTime"] as? Number)?.toInt() ?: 0,
            allowIdenticalLocations = m["allowIdenticalLocations"] as? Boolean ?: false,
            geofenceModeHighAccuracy = m["geofenceModeHighAccuracy"] as? Boolean ?: false,
            periodicUseForegroundService = m["periodicUseForegroundService"] as? Boolean ?: false,
            periodicUseExactAlarms = m["periodicUseExactAlarms"] as? Boolean ?: false,
            scheduleUseAlarmManager = m["scheduleUseAlarmManager"] as? Boolean ?: false,
            foregroundService = (m["foregroundService"] as? Map<String, Any?>)?.let { ForegroundServiceConfig.fromMap(it) } ?: ForegroundServiceConfig(),
            releaseWakelockWhenStationary = m["releaseWakelockWhenStationary"] as? Boolean ?: false,
        )
    }
    fun toMap(): Map<String, Any?> = mapOf(
        "locationUpdateInterval" to locationUpdateInterval, "fastestLocationUpdateInterval" to fastestLocationUpdateInterval,
        "deferTime" to deferTime, "allowIdenticalLocations" to allowIdenticalLocations, "geofenceModeHighAccuracy" to geofenceModeHighAccuracy,
        "periodicUseForegroundService" to periodicUseForegroundService, "periodicUseExactAlarms" to periodicUseExactAlarms,
        "scheduleUseAlarmManager" to scheduleUseAlarmManager, "foregroundService" to foregroundService.toMap(),
        "releaseWakelockWhenStationary" to releaseWakelockWhenStationary
    )
}

data class IosConfig(
    val activityType: LocationActivityType = LocationActivityType.OTHER,
    val useSignificantChangesOnly: Boolean = false,
    val showsBackgroundLocationIndicator: Boolean = false,
    val pausesLocationUpdatesAutomatically: Boolean = false,
    val locationAuthorizationRequest: LocationAuthorizationRequest = LocationAuthorizationRequest.ALWAYS,
    val disableLocationAuthorizationAlert: Boolean = false,
    val preventSuspend: Boolean = false,
) {
    companion object {
        fun fromMap(m: Map<String, Any?>) = IosConfig(
            activityType = LocationActivityType.fromValue((m["activityType"] as? Number)?.toInt() ?: 0),
            useSignificantChangesOnly = m["useSignificantChangesOnly"] as? Boolean ?: false,
            showsBackgroundLocationIndicator = m["showsBackgroundLocationIndicator"] as? Boolean ?: false,
            pausesLocationUpdatesAutomatically = m["pausesLocationUpdatesAutomatically"] as? Boolean ?: false,
            locationAuthorizationRequest = if (m["locationAuthorizationRequest"] == "WhenInUse") LocationAuthorizationRequest.WHEN_IN_USE else LocationAuthorizationRequest.ALWAYS,
            disableLocationAuthorizationAlert = m["disableLocationAuthorizationAlert"] as? Boolean ?: false,
            preventSuspend = m["preventSuspend"] as? Boolean ?: false
        )
    }
    fun toMap(): Map<String, Any?> = mapOf(
        "activityType" to activityType.value, "useSignificantChangesOnly" to useSignificantChangesOnly,
        "showsBackgroundLocationIndicator" to showsBackgroundLocationIndicator, "pausesLocationUpdatesAutomatically" to pausesLocationUpdatesAutomatically,
        "locationAuthorizationRequest" to if (locationAuthorizationRequest == LocationAuthorizationRequest.ALWAYS) "Always" else "WhenInUse",
        "disableLocationAuthorizationAlert" to disableLocationAuthorizationAlert, "preventSuspend" to preventSuspend
    )
}

data class LocationFilter(
    val policy: LocationFilterPolicy = LocationFilterPolicy.ADJUST,
    val maxImpliedSpeed: Int = 0,
    val odometerAccuracyThreshold: Int = 0,
    val trackingAccuracyThreshold: Int = 0,
    val useKalmanFilter: Boolean = false,
    val rejectMockLocations: Boolean = false,
    val mockDetectionLevel: MockDetectionLevel = MockDetectionLevel.DISABLED,
) {
    companion object {
        fun fromMap(m: Map<String, Any?>) = LocationFilter(
            policy = LocationFilterPolicy.fromValue((m["policy"] as? Number)?.toInt() ?: 0),
            maxImpliedSpeed = (m["maxImpliedSpeed"] as? Number)?.toInt() ?: 0,
            odometerAccuracyThreshold = (m["odometerAccuracyThreshold"] as? Number)?.toInt() ?: 0,
            trackingAccuracyThreshold = (m["trackingAccuracyThreshold"] as? Number)?.toInt() ?: 0,
            useKalmanFilter = m["useKalmanFilter"] as? Boolean ?: false,
            rejectMockLocations = m["rejectMockLocations"] as? Boolean ?: false,
            mockDetectionLevel = MockDetectionLevel.fromValue((m["mockDetectionLevel"] as? Number)?.toInt() ?: 0)
        )
    }
    fun toMap(): Map<String, Any?> = mapOf(
        "policy" to policy.value, "maxImpliedSpeed" to maxImpliedSpeed, "odometerAccuracyThreshold" to odometerAccuracyThreshold,
        "trackingAccuracyThreshold" to trackingAccuracyThreshold, "useKalmanFilter" to useKalmanFilter,
        "rejectMockLocations" to rejectMockLocations, "mockDetectionLevel" to mockDetectionLevel.value
    )
}

data class AppConfig(
    val stopOnTerminate: Boolean = true,
    val startOnBoot: Boolean = false,
    val heartbeatInterval: Int = 60,
    val schedule: List<String> = emptyList(),
    val remoteConfigUrl: String? = null,
    val remoteConfigHeaders: Map<String, String> = emptyMap(),
    val remoteConfigTimeout: Int = 10000,
    val remoteConfigRefreshInterval: Int = 0,
) {
    companion object {
        fun fromMap(m: Map<String, Any?>) = AppConfig(
            stopOnTerminate = m["stopOnTerminate"] as? Boolean ?: true,
            startOnBoot = m["startOnBoot"] as? Boolean ?: false,
            heartbeatInterval = (m["heartbeatInterval"] as? Number)?.toInt() ?: 60,
            schedule = (m["schedule"] as? List<*>)?.mapNotNull { it as? String } ?: emptyList(),
            remoteConfigUrl = m["remoteConfigUrl"] as? String,
            remoteConfigHeaders = (m["remoteConfigHeaders"] as? Map<String, String>) ?: emptyMap(),
            remoteConfigTimeout = (m["remoteConfigTimeout"] as? Number)?.toInt() ?: 10000,
            remoteConfigRefreshInterval = (m["remoteConfigRefreshInterval"] as? Number)?.toInt() ?: 0
        )
    }
    fun toMap(): Map<String, Any?> = mapOf(
        "stopOnTerminate" to stopOnTerminate, "startOnBoot" to startOnBoot, "heartbeatInterval" to heartbeatInterval,
        "schedule" to schedule, "remoteConfigUrl" to remoteConfigUrl, "remoteConfigHeaders" to remoteConfigHeaders,
        "remoteConfigTimeout" to remoteConfigTimeout, "remoteConfigRefreshInterval" to remoteConfigRefreshInterval
    )
}

data class ForegroundServiceConfig(
    val enabled: Boolean = true,
    val channelId: String = "tracelet_channel",
    val channelName: String = "Tracelet",
    val notificationTitle: String = "Tracelet",
    val notificationText: String = "Tracking location in background",
    val notificationColor: String? = null,
    val notificationSmallIcon: String? = null,
    val notificationLargeIcon: String? = null,
    val notificationPriority: NotificationPriority = NotificationPriority.DEFAULT,
    val notificationOngoing: Boolean = true,
    val showNotificationOnPauseOnly: Boolean = false,
    val actions: List<String> = emptyList(),
    /** Epoch milliseconds used as the origin of the notification timer. */
    val notificationStartedAt: Long? = null,
    /** Whether to render the self-ticking notification timer. */
    val notificationShowTimer: Boolean = false,
    /** Whether notification updates should alert the user only once. */
    val notificationOnlyAlertOnce: Boolean = false,
) {
    companion object {
        fun fromMap(m: Map<String, Any?>) = ForegroundServiceConfig(
            enabled = m["enabled"] as? Boolean ?: true,
            channelId = m["channelId"] as? String ?: "tracelet_channel",
            channelName = m["channelName"] as? String ?: "Tracelet",
            notificationTitle = m["notificationTitle"] as? String ?: "Tracelet",
            notificationText = m["notificationText"] as? String ?: "Tracking location in background",
            notificationColor = m["notificationColor"] as? String,
            notificationSmallIcon = m["notificationSmallIcon"] as? String,
            notificationLargeIcon = m["notificationLargeIcon"] as? String,
            notificationPriority = NotificationPriority.fromValue((m["notificationPriority"] as? Number)?.toInt() ?: 0),
            notificationOngoing = m["notificationOngoing"] as? Boolean ?: true,
            showNotificationOnPauseOnly = m["showNotificationOnPauseOnly"] as? Boolean ?: false,
            actions = (m["actions"] as? List<*>)?.mapNotNull { it as? String } ?: emptyList(),
            notificationStartedAt = (m["notificationStartedAt"] as? Number)?.toLong(),
            notificationShowTimer = m["notificationShowTimer"] as? Boolean ?: false,
            notificationOnlyAlertOnce = m["notificationOnlyAlertOnce"] as? Boolean ?: false,
        )
    }
    fun toMap(): Map<String, Any?> = mapOf(
        "enabled" to enabled, "channelId" to channelId, "channelName" to channelName, "notificationTitle" to notificationTitle,
        "notificationText" to notificationText, "notificationColor" to notificationColor, "notificationSmallIcon" to notificationSmallIcon,
        "notificationLargeIcon" to notificationLargeIcon, "notificationStartedAt" to notificationStartedAt,
        "notificationShowTimer" to notificationShowTimer, "notificationOnlyAlertOnce" to notificationOnlyAlertOnce,
        "notificationPriority" to notificationPriority.value, "notificationOngoing" to notificationOngoing,
        "showNotificationOnPauseOnly" to showNotificationOnPauseOnly, "actions" to actions
    )
}

data class HttpConfig(
    val url: String? = null,
    val method: HttpMethod = HttpMethod.POST,
    val headers: Map<String, String> = emptyMap(),
    val batchSync: Boolean = false,
    val maxBatchSize: Int = 250,
    val autoSync: Boolean = true,
    val params: Map<String, Any?> = emptyMap(),
    val autoSyncThreshold: Int = 0,
    val autoSyncDelay: Int? = null,
    val syncInterval: Int = 900000,
    val httpTimeout: Int = 60000,
    val locationsOrderDirection: LocationOrder = LocationOrder.ASC,
    val disableAutoSyncOnCellular: Boolean = false,
    val maxRetries: Int = 3,
    val retryBackoffBase: Int = 1000,
    val retryBackoffCap: Int = 60000,
    val enableDeltaCompression: Boolean = false,
    val deltaCoordinatePrecision: Int = 5,
    val syncTelematics: Boolean = false,
    val telematicsUrl: String? = null,
    val sslPinningFingerprints: List<String>? = null,
    val sslPinningCertificates: List<String>? = null,
    val httpRootProperty: String = "location",
    val extras: Map<String, Any?> = emptyMap(),
) {
    companion object {
        fun fromMap(m: Map<String, Any?>) = HttpConfig(
            url = m["url"] as? String,
            method = HttpMethod.fromValue((m["method"] as? Number)?.toInt() ?: 0),
            headers = (m["headers"] as? Map<String, String>) ?: emptyMap(),
            batchSync = m["batchSync"] as? Boolean ?: false,
            maxBatchSize = (m["maxBatchSize"] as? Number)?.toInt() ?: 250,
            autoSync = m["autoSync"] as? Boolean ?: true,
            params = (m["params"] as? Map<String, Any?>) ?: emptyMap(),
            autoSyncThreshold = (m["autoSyncThreshold"] as? Number)?.toInt() ?: 0,
            autoSyncDelay = (m["autoSyncDelay"] as? Number)?.toInt(),
            syncInterval = (m["syncInterval"] as? Number)?.toInt() ?: 900000,
            httpTimeout = (m["httpTimeout"] as? Number)?.toInt() ?: 60000,
            locationsOrderDirection = LocationOrder.fromValue((m["locationsOrderDirection"] as? Number)?.toInt() ?: 0),
            disableAutoSyncOnCellular = m["disableAutoSyncOnCellular"] as? Boolean ?: false,
            maxRetries = (m["maxRetries"] as? Number)?.toInt() ?: 3,
            retryBackoffBase = (m["retryBackoffBase"] as? Number)?.toInt() ?: 1000,
            retryBackoffCap = (m["retryBackoffCap"] as? Number)?.toInt() ?: 60000,
            enableDeltaCompression = m["enableDeltaCompression"] as? Boolean ?: false,
            deltaCoordinatePrecision = (m["deltaCoordinatePrecision"] as? Number)?.toInt() ?: 5,
            syncTelematics = m["syncTelematics"] as? Boolean ?: false,
            telematicsUrl = m["telematicsUrl"] as? String,
            sslPinningFingerprints = (m["sslPinningFingerprints"] as? List<*>)?.mapNotNull { it as? String },
            sslPinningCertificates = (m["sslPinningCertificates"] as? List<*>)?.mapNotNull { it as? String },
            httpRootProperty = m["httpRootProperty"] as? String ?: "location",
            extras = (m["extras"] as? Map<String, Any?>) ?: emptyMap()
        )
    }
    fun toMap(): Map<String, Any?> = mapOf(
        "url" to url, "method" to method.value, "headers" to headers, "batchSync" to batchSync,
        "maxBatchSize" to maxBatchSize, "autoSync" to autoSync, "params" to params,
        "autoSyncThreshold" to autoSyncThreshold, "autoSyncDelay" to autoSyncDelay,
        "syncInterval" to syncInterval, "httpTimeout" to httpTimeout,
        "locationsOrderDirection" to locationsOrderDirection.value,
        "disableAutoSyncOnCellular" to disableAutoSyncOnCellular,
        "maxRetries" to maxRetries, "retryBackoffBase" to retryBackoffBase, "retryBackoffCap" to retryBackoffCap,
        "enableDeltaCompression" to enableDeltaCompression, "deltaCoordinatePrecision" to deltaCoordinatePrecision,
        "syncTelematics" to syncTelematics, "telematicsUrl" to telematicsUrl,
        "sslPinningFingerprints" to sslPinningFingerprints, "sslPinningCertificates" to sslPinningCertificates,
        "httpRootProperty" to httpRootProperty, "extras" to extras
    )
}

data class LoggerConfig(val logLevel: LogLevel = LogLevel.INFO, val logMaxDays: Int = 3, val debug: Boolean = false) {
    companion object { fun fromMap(m: Map<String, Any?>) = LoggerConfig(logLevel = LogLevel.fromValue((m["logLevel"] as? Number)?.toInt() ?: 2), logMaxDays = (m["logMaxDays"] as? Number)?.toInt() ?: 3, debug = m["debug"] as? Boolean ?: false) }
    fun toMap(): Map<String, Any?> = mapOf("logLevel" to logLevel.value, "logMaxDays" to logMaxDays, "debug" to debug)
}

data class MotionConfig(
    val stopTimeout: Int = 5,
    val motionTriggerDelay: Int = 0,
    val disableMotionActivityUpdates: Boolean = false,
    val isMoving: Boolean = false,
    val activityRecognitionInterval: Int = 10000,
    val minimumActivityRecognitionConfidence: Int = 75,
    val disableStopDetection: Boolean = false,
    val stopDetectionDelay: Int = 0,
    val stopOnStationary: Boolean = false,
    val stationaryRadius: Double = 25.0,
    val useSignificantChangesOnly: Boolean = false,
    val shakeThreshold: Double = 2.5,
    val stillThreshold: Double = 0.4,
    val stillSampleCount: Int = 25,
    val motionDetectionMode: MotionDetectionMode = MotionDetectionMode.ACCELEROMETER,
    val speedMovingThreshold: Double = 1.5,
    val speedStationaryDelay: Int = 180,
    val stationaryTrackingMode: StationaryTrackingMode = StationaryTrackingMode.PERIODIC,
    val stationaryPeriodicInterval: Int = 900,
    val stationaryPeriodicAccuracy: DesiredAccuracy = DesiredAccuracy.MEDIUM,
    val speedWakeConfirmCount: Int = 1,
) {
    companion object {
        fun fromMap(m: Map<String, Any?>) = MotionConfig(
            stopTimeout = (m["stopTimeout"] as? Number)?.toInt() ?: 5,
            motionTriggerDelay = (m["motionTriggerDelay"] as? Number)?.toInt() ?: 0,
            disableMotionActivityUpdates = m["disableMotionActivityUpdates"] as? Boolean ?: false,
            isMoving = m["isMoving"] as? Boolean ?: false,
            activityRecognitionInterval = (m["activityRecognitionInterval"] as? Number)?.toInt() ?: 10000,
            minimumActivityRecognitionConfidence = (m["minimumActivityRecognitionConfidence"] as? Number)?.toInt() ?: 75,
            disableStopDetection = m["disableStopDetection"] as? Boolean ?: false,
            stopDetectionDelay = (m["stopDetectionDelay"] as? Number)?.toInt() ?: 0,
            stopOnStationary = m["stopOnStationary"] as? Boolean ?: false,
            stationaryRadius = (m["stationaryRadius"] as? Number)?.toDouble() ?: 25.0,
            useSignificantChangesOnly = m["useSignificantChangesOnly"] as? Boolean ?: false,
            shakeThreshold = (m["shakeThreshold"] as? Number)?.toDouble() ?: 2.5,
            stillThreshold = (m["stillThreshold"] as? Number)?.toDouble() ?: 0.4,
            stillSampleCount = (m["stillSampleCount"] as? Number)?.toInt() ?: 25,
            motionDetectionMode = MotionDetectionMode.fromInt((m["motionDetectionMode"] as? Number)?.toInt() ?: 0),
            speedMovingThreshold = (m["speedMovingThreshold"] as? Number)?.toDouble() ?: 1.5,
            speedStationaryDelay = (m["speedStationaryDelay"] as? Number)?.toInt() ?: 180,
            stationaryTrackingMode = StationaryTrackingMode.fromInt((m["stationaryTrackingMode"] as? Number)?.toInt() ?: 0),
            stationaryPeriodicInterval = (m["stationaryPeriodicInterval"] as? Number)?.toInt() ?: 900,
            stationaryPeriodicAccuracy = DesiredAccuracy.fromValue((m["stationaryPeriodicAccuracy"] as? Number)?.toInt() ?: 1),
            speedWakeConfirmCount = (m["speedWakeConfirmCount"] as? Number)?.toInt() ?: 1,
        )
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "stopTimeout" to stopTimeout,
        "motionTriggerDelay" to motionTriggerDelay,
        "disableMotionActivityUpdates" to disableMotionActivityUpdates,
        "isMoving" to isMoving,
        "activityRecognitionInterval" to activityRecognitionInterval,
        "minimumActivityRecognitionConfidence" to minimumActivityRecognitionConfidence,
        "disableStopDetection" to disableStopDetection,
        "stopDetectionDelay" to stopDetectionDelay,
        "stopOnStationary" to stopOnStationary,
        "stationaryRadius" to stationaryRadius,
        "useSignificantChangesOnly" to useSignificantChangesOnly,
        "shakeThreshold" to shakeThreshold,
        "stillThreshold" to stillThreshold,
        "stillSampleCount" to stillSampleCount,
        "motionDetectionMode" to motionDetectionMode.value,
        "speedMovingThreshold" to speedMovingThreshold,
        "speedStationaryDelay" to speedStationaryDelay,
        "stationaryTrackingMode" to stationaryTrackingMode.value,
        "stationaryPeriodicInterval" to stationaryPeriodicInterval,
        "stationaryPeriodicAccuracy" to stationaryPeriodicAccuracy.value,
        "speedWakeConfirmCount" to speedWakeConfirmCount,
    )
}

data class GeofenceConfig(
    val geofenceInitialTriggerEntry: Boolean = true,
    val geofenceInitialTrigger: Boolean = true,
    val geofenceProximityRadius: Int = 1000
) {
    companion object { 
        fun fromMap(m: Map<String, Any?>) = GeofenceConfig(
            geofenceInitialTriggerEntry = m["geofenceInitialTriggerEntry"] as? Boolean ?: true,
            geofenceInitialTrigger = m["geofenceInitialTrigger"] as? Boolean ?: true,
            geofenceProximityRadius = (m["geofenceProximityRadius"] as? Number)?.toInt() ?: 1000
        )
    }
    fun toMap(): Map<String, Any?> = mapOf(
        "geofenceInitialTriggerEntry" to geofenceInitialTriggerEntry,
        "geofenceInitialTrigger" to geofenceInitialTrigger, "geofenceProximityRadius" to geofenceProximityRadius
    )
}

data class PersistenceConfig(
    val maxDaysToPersist: Int = 1,
    val maxRecordsToPersist: Int = -1,
    val persistMode: PersistMode = PersistMode.ALL,
    val disableProviderChangeRecord: Boolean = false
) {
    companion object { 
        fun fromMap(m: Map<String, Any?>) = PersistenceConfig(
            maxDaysToPersist = (m["maxDaysToPersist"] as? Number)?.toInt() ?: 1,
            maxRecordsToPersist = (m["maxRecordsToPersist"] as? Number)?.toInt() ?: -1,
            persistMode = PersistMode.fromValue((m["persistMode"] as? Number)?.toInt() ?: 0),
            disableProviderChangeRecord = m["disableProviderChangeRecord"] as? Boolean ?: false
        )
    }
    fun toMap(): Map<String, Any?> = mapOf(
        "maxDaysToPersist" to maxDaysToPersist, "maxRecordsToPersist" to maxRecordsToPersist,
        "persistMode" to persistMode.value, "disableProviderChangeRecord" to disableProviderChangeRecord
    )
}

data class AuditConfig(
    val enabled: Boolean = false,
    val hashAlgorithm: HashAlgorithm = HashAlgorithm.SHA256,
    val includeExtrasInHash: Boolean = false
) {
    companion object { 
        fun fromMap(m: Map<String, Any?>) = AuditConfig(
            enabled = m["enabled"] as? Boolean ?: false,
            hashAlgorithm = HashAlgorithm.fromValue((m["hashAlgorithm"] as? Number)?.toInt() ?: 0),
            includeExtrasInHash = m["includeExtrasInHash"] as? Boolean ?: false
        )
    }
    fun toMap(): Map<String, Any?> = mapOf("enabled" to enabled, "hashAlgorithm" to hashAlgorithm.value, "includeExtrasInHash" to includeExtrasInHash)
}

data class PrivacyZoneConfig(val enabled: Boolean = false) {
    companion object { fun fromMap(m: Map<String, Any?>) = PrivacyZoneConfig(enabled = m["enabled"] as? Boolean ?: false) }
    fun toMap(): Map<String, Any?> = mapOf("enabled" to enabled)
}

data class SecurityConfig(
    val encryptDatabase: Boolean = false,
    val encryptionKey: String? = null
) {
    companion object { 
        fun fromMap(m: Map<String, Any?>) = SecurityConfig(
            encryptDatabase = m["encryptDatabase"] as? Boolean ?: false,
            encryptionKey = m["encryptionKey"] as? String
        )
    }
    fun toMap(): Map<String, Any?> = mapOf("encryptDatabase" to encryptDatabase, "encryptionKey" to encryptionKey)
}

data class AttestationConfig(
    val enabled: Boolean = false,
    val refreshInterval: Int = 3600,
    val verificationUrl: String? = null
) {
    companion object { 
        fun fromMap(m: Map<String, Any?>) = AttestationConfig(
            enabled = m["enabled"] as? Boolean ?: false,
            refreshInterval = (m["refreshInterval"] as? Number)?.toInt() ?: 3600,
            verificationUrl = m["verificationUrl"] as? String
        )
    }
    fun toMap(): Map<String, Any?> = mapOf("enabled" to enabled, "refreshInterval" to refreshInterval, "verificationUrl" to verificationUrl)
}
