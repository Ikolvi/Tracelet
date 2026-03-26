package com.ikolvi.tracelet.sdk.model

/**
 * Typed configuration for the Tracelet SDK.
 *
 * Mirrors the Dart [Config] class so native Android developers get the same
 * structured, type-safe API:
 *
 * ```kotlin
 * val config = TraceletConfig(
 *     geo = GeoConfig(
 *         desiredAccuracy = DesiredAccuracy.HIGH,
 *         distanceFilter = 10.0,
 *         filter = LocationFilter(
 *             trackingAccuracyThreshold = 100,
 *             maxImpliedSpeed = 80,
 *         ),
 *     ),
 *     app = AppConfig(
 *         stopOnTerminate = false,
 *         startOnBoot = true,
 *     ),
 *     persistence = PersistenceConfig(
 *         maxDaysToPersist = 7,
 *         maxRecordsToPersist = 5000,
 *     ),
 *     logger = LoggerConfig(
 *         debug = true,
 *         logLevel = LogLevel.VERBOSE,
 *     ),
 * )
 *
 * sdk.ready(config) { state -> /* ready */ }
 * ```
 */
data class TraceletConfig(
    val geo: GeoConfig = GeoConfig(),
    val app: AppConfig = AppConfig(),
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
        @Suppress("UNCHECKED_CAST")
        fun fromMap(map: Map<String, Any?>): TraceletConfig = TraceletConfig(
            geo = (map["geo"] as? Map<String, Any?>)?.let { GeoConfig.fromMap(it) } ?: GeoConfig(),
            app = (map["app"] as? Map<String, Any?>)?.let { AppConfig.fromMap(it) } ?: AppConfig(),
            http = (map["http"] as? Map<String, Any?>)?.let { HttpConfig.fromMap(it) } ?: HttpConfig(),
            logger = (map["logger"] as? Map<String, Any?>)?.let { LoggerConfig.fromMap(it) } ?: LoggerConfig(),
            motion = (map["motion"] as? Map<String, Any?>)?.let { MotionConfig.fromMap(it) } ?: MotionConfig(),
            geofence = (map["geofence"] as? Map<String, Any?>)?.let { GeofenceConfig.fromMap(it) } ?: GeofenceConfig(),
            persistence = (map["persistence"] as? Map<String, Any?>)?.let { PersistenceConfig.fromMap(it) } ?: PersistenceConfig(),
            audit = (map["audit"] as? Map<String, Any?>)?.let { AuditConfig.fromMap(it) } ?: AuditConfig(),
            privacyZone = (map["privacyZone"] as? Map<String, Any?>)?.let { PrivacyZoneConfig.fromMap(it) } ?: PrivacyZoneConfig(),
            security = (map["security"] as? Map<String, Any?>)?.let { SecurityConfig.fromMap(it) } ?: SecurityConfig(),
            attestation = (map["attestation"] as? Map<String, Any?>)?.let { AttestationConfig.fromMap(it) } ?: AttestationConfig(),
        )
    }

    /** Converts to the flat map format expected by [ConfigManager]. */
    fun toMap(): Map<String, Any?> = buildMap {
        put("geo", geo.toMap())
        put("app", app.toMap())
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

// =============================================================================
// Enums
// =============================================================================

/** GPS accuracy level. Matches Dart [DesiredAccuracy]. */
enum class DesiredAccuracy(val value: Int) {
    /** GPS-level accuracy (~5m). Highest battery usage. */
    HIGH(0),
    /** WiFi/cell accuracy (~100m). Moderate battery. */
    MEDIUM(1),
    /** City-level accuracy (~1km). Lowest battery. */
    LOW(2);

    companion object {
        fun fromValue(value: Int): DesiredAccuracy =
            entries.firstOrNull { it.value == value } ?: HIGH
    }
}

/** Log verbosity level. Matches Dart [LogLevel]. */
enum class LogLevel(val value: Int) {
    VERBOSE(0),
    DEBUG(1),
    INFO(2),
    WARN(3),
    ERROR(4);

    companion object {
        fun fromValue(value: Int): LogLevel =
            entries.firstOrNull { it.value == value } ?: INFO
    }
}

/** HTTP method for server sync. */
enum class HttpMethod(val value: Int) {
    POST(0),
    PUT(1);

    companion object {
        fun fromValue(value: Int): HttpMethod =
            entries.firstOrNull { it.value == value } ?: POST
    }
}

/** Location record persistence mode. */
enum class PersistMode(val value: Int) {
    ALL(0),
    LOCATION(1),
    GEOFENCE(2),
    NONE(3);

    companion object {
        fun fromValue(value: Int): PersistMode =
            entries.firstOrNull { it.value == value } ?: ALL
    }
}

/** Location filter policy. */
enum class LocationFilterPolicy(val value: Int) {
    ADJUST(0),
    IGNORE(1),
    DISCARD(2);

    companion object {
        fun fromValue(value: Int): LocationFilterPolicy =
            entries.firstOrNull { it.value == value } ?: ADJUST
    }
}

/** Mock detection aggressiveness. */
enum class MockDetectionLevel(val value: Int) {
    DISABLED(0),
    BASIC(1),
    HEURISTIC(2);

    companion object {
        fun fromValue(value: Int): MockDetectionLevel =
            entries.firstOrNull { it.value == value } ?: DISABLED
    }
}

/** Activity type hint (iOS only). */
enum class LocationActivityType(val value: Int) {
    OTHER(0),
    AUTOMOTIVE_NAVIGATION(1),
    FITNESS(2),
    OTHER_NAVIGATION(3),
    AIRBORNE(4);

    companion object {
        fun fromValue(value: Int): LocationActivityType =
            entries.firstOrNull { it.value == value } ?: OTHER
    }
}

/** Location authorization level. */
enum class LocationAuthorizationRequest {
    ALWAYS,
    WHEN_IN_USE
}

/** Notification priority for the foreground service. */
enum class NotificationPriority(val value: Int) {
    MIN(-2),
    LOW(-1),
    DEFAULT(0),
    HIGH(1),
    MAX(2);

    companion object {
        fun fromValue(value: Int): NotificationPriority =
            entries.firstOrNull { it.value == value } ?: DEFAULT
    }
}

/** Locations sort order for HTTP sync. */
enum class LocationOrder(val value: Int) {
    ASC(0),
    DESC(1);

    companion object {
        fun fromValue(value: Int): LocationOrder =
            entries.firstOrNull { it.value == value } ?: ASC
    }
}

/** Activity type for motion trigger filtering. */
enum class ActivityType {
    STILL,
    ON_FOOT,
    WALKING,
    RUNNING,
    ON_BICYCLE,
    IN_VEHICLE,
    UNKNOWN
}

/** Hash algorithm for audit trail. */
enum class HashAlgorithm(val value: Int) {
    SHA256(0),
    SHA512(1);

    companion object {
        fun fromValue(value: Int): HashAlgorithm =
            entries.firstOrNull { it.value == value } ?: SHA256
    }
}

// =============================================================================
// Sub-config data classes
// =============================================================================

/**
 * Location accuracy, sampling, and filtering settings.
 *
 * ```kotlin
 * GeoConfig(
 *     desiredAccuracy = DesiredAccuracy.HIGH,
 *     distanceFilter = 10.0,
 *     filter = LocationFilter(maxImpliedSpeed = 80),
 * )
 * ```
 */
data class GeoConfig(
    val desiredAccuracy: DesiredAccuracy = DesiredAccuracy.HIGH,
    val distanceFilter: Double = 10.0,
    val locationUpdateInterval: Int = 1000,
    val fastestLocationUpdateInterval: Int = 500,
    val stationaryRadius: Double = 25.0,
    val locationTimeout: Int = 60,
    val activityType: LocationActivityType = LocationActivityType.OTHER,
    val disableElasticity: Boolean = false,
    val elasticityMultiplier: Double = 1.0,
    val stopAfterElapsedMinutes: Int = -1,
    val deferTime: Int = 0,
    val allowIdenticalLocations: Boolean = false,
    val geofenceModeHighAccuracy: Boolean = false,
    val maxMonitoredGeofences: Int = -1,
    val useSignificantChangesOnly: Boolean = false,
    val showsBackgroundLocationIndicator: Boolean = false,
    val pausesLocationUpdatesAutomatically: Boolean = false,
    val locationAuthorizationRequest: LocationAuthorizationRequest = LocationAuthorizationRequest.ALWAYS,
    val disableLocationAuthorizationAlert: Boolean = false,
    val enableTimestampMeta: Boolean = false,
    val enableAdaptiveMode: Boolean = false,
    val periodicLocationInterval: Int = 900,
    val periodicDesiredAccuracy: DesiredAccuracy = DesiredAccuracy.MEDIUM,
    val periodicUseForegroundService: Boolean = false,
    val periodicUseExactAlarms: Boolean = false,
    val enableSparseUpdates: Boolean = false,
    val sparseDistanceThreshold: Double = 50.0,
    val sparseMaxIdleSeconds: Int = 300,
    val enableDeadReckoning: Boolean = false,
    val deadReckoningActivationDelay: Int = 10,
    val deadReckoningMaxDuration: Int = 120,
    val batteryBudgetPerHour: Double = 0.0,
    val filter: LocationFilter? = null,
) {
    companion object {
        @Suppress("UNCHECKED_CAST")
        fun fromMap(map: Map<String, Any?>): GeoConfig = GeoConfig(
            desiredAccuracy = DesiredAccuracy.fromValue((map["desiredAccuracy"] as? Number)?.toInt() ?: 0),
            distanceFilter = (map["distanceFilter"] as? Number)?.toDouble() ?: 10.0,
            locationUpdateInterval = (map["locationUpdateInterval"] as? Number)?.toInt() ?: 1000,
            fastestLocationUpdateInterval = (map["fastestLocationUpdateInterval"] as? Number)?.toInt() ?: 500,
            stationaryRadius = (map["stationaryRadius"] as? Number)?.toDouble() ?: 25.0,
            locationTimeout = (map["locationTimeout"] as? Number)?.toInt() ?: 60,
            activityType = LocationActivityType.fromValue((map["activityType"] as? Number)?.toInt() ?: 0),
            disableElasticity = map["disableElasticity"] as? Boolean ?: false,
            elasticityMultiplier = (map["elasticityMultiplier"] as? Number)?.toDouble() ?: 1.0,
            stopAfterElapsedMinutes = (map["stopAfterElapsedMinutes"] as? Number)?.toInt() ?: -1,
            deferTime = (map["deferTime"] as? Number)?.toInt() ?: 0,
            allowIdenticalLocations = map["allowIdenticalLocations"] as? Boolean ?: false,
            geofenceModeHighAccuracy = map["geofenceModeHighAccuracy"] as? Boolean ?: false,
            maxMonitoredGeofences = (map["maxMonitoredGeofences"] as? Number)?.toInt() ?: -1,
            useSignificantChangesOnly = map["useSignificantChangesOnly"] as? Boolean ?: false,
            showsBackgroundLocationIndicator = map["showsBackgroundLocationIndicator"] as? Boolean ?: false,
            pausesLocationUpdatesAutomatically = map["pausesLocationUpdatesAutomatically"] as? Boolean ?: false,
            locationAuthorizationRequest = if ((map["locationAuthorizationRequest"] as? String) == "WhenInUse") LocationAuthorizationRequest.WHEN_IN_USE else LocationAuthorizationRequest.ALWAYS,
            disableLocationAuthorizationAlert = map["disableLocationAuthorizationAlert"] as? Boolean ?: false,
            enableTimestampMeta = map["enableTimestampMeta"] as? Boolean ?: false,
            enableAdaptiveMode = map["enableAdaptiveMode"] as? Boolean ?: false,
            periodicLocationInterval = (map["periodicLocationInterval"] as? Number)?.toInt() ?: 900,
            periodicDesiredAccuracy = DesiredAccuracy.fromValue((map["periodicDesiredAccuracy"] as? Number)?.toInt() ?: 1),
            periodicUseForegroundService = map["periodicUseForegroundService"] as? Boolean ?: false,
            periodicUseExactAlarms = map["periodicUseExactAlarms"] as? Boolean ?: false,
            enableSparseUpdates = map["enableSparseUpdates"] as? Boolean ?: false,
            sparseDistanceThreshold = (map["sparseDistanceThreshold"] as? Number)?.toDouble() ?: 50.0,
            sparseMaxIdleSeconds = (map["sparseMaxIdleSeconds"] as? Number)?.toInt() ?: 300,
            enableDeadReckoning = map["enableDeadReckoning"] as? Boolean ?: false,
            deadReckoningActivationDelay = (map["deadReckoningActivationDelay"] as? Number)?.toInt() ?: 10,
            deadReckoningMaxDuration = (map["deadReckoningMaxDuration"] as? Number)?.toInt() ?: 120,
            batteryBudgetPerHour = (map["batteryBudgetPerHour"] as? Number)?.toDouble() ?: 0.0,
            filter = (map["filter"] as? Map<String, Any?>)?.let { LocationFilter.fromMap(it) },
        )
    }

    fun toMap(): Map<String, Any?> = buildMap {
        put("desiredAccuracy", desiredAccuracy.value)
        put("distanceFilter", distanceFilter)
        put("locationUpdateInterval", locationUpdateInterval)
        put("fastestLocationUpdateInterval", fastestLocationUpdateInterval)
        put("stationaryRadius", stationaryRadius)
        put("locationTimeout", locationTimeout)
        put("activityType", activityType.value)
        put("disableElasticity", disableElasticity)
        put("elasticityMultiplier", elasticityMultiplier)
        put("stopAfterElapsedMinutes", stopAfterElapsedMinutes)
        put("deferTime", deferTime)
        put("allowIdenticalLocations", allowIdenticalLocations)
        put("geofenceModeHighAccuracy", geofenceModeHighAccuracy)
        put("maxMonitoredGeofences", maxMonitoredGeofences)
        put("useSignificantChangesOnly", useSignificantChangesOnly)
        put("showsBackgroundLocationIndicator", showsBackgroundLocationIndicator)
        put("pausesLocationUpdatesAutomatically", pausesLocationUpdatesAutomatically)
        put("locationAuthorizationRequest", if (locationAuthorizationRequest == LocationAuthorizationRequest.ALWAYS) "Always" else "WhenInUse")
        put("disableLocationAuthorizationAlert", disableLocationAuthorizationAlert)
        put("enableTimestampMeta", enableTimestampMeta)
        put("enableAdaptiveMode", enableAdaptiveMode)
        put("periodicLocationInterval", periodicLocationInterval)
        put("periodicDesiredAccuracy", periodicDesiredAccuracy.value)
        put("periodicUseForegroundService", periodicUseForegroundService)
        put("periodicUseExactAlarms", periodicUseExactAlarms)
        put("enableSparseUpdates", enableSparseUpdates)
        put("sparseDistanceThreshold", sparseDistanceThreshold)
        put("sparseMaxIdleSeconds", sparseMaxIdleSeconds)
        put("enableDeadReckoning", enableDeadReckoning)
        put("deadReckoningActivationDelay", deadReckoningActivationDelay)
        put("deadReckoningMaxDuration", deadReckoningMaxDuration)
        put("batteryBudgetPerHour", batteryBudgetPerHour)
        filter?.let { put("filter", it.toMap()) }
    }
}

/**
 * Location filtering and denoising.
 *
 * ```kotlin
 * LocationFilter(
 *     trackingAccuracyThreshold = 100,
 *     maxImpliedSpeed = 80,
 *     useKalmanFilter = true,
 * )
 * ```
 */
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
        fun fromMap(map: Map<String, Any?>): LocationFilter = LocationFilter(
            policy = LocationFilterPolicy.fromValue((map["policy"] as? Number)?.toInt() ?: 0),
            maxImpliedSpeed = (map["maxImpliedSpeed"] as? Number)?.toInt() ?: 0,
            odometerAccuracyThreshold = (map["odometerAccuracyThreshold"] as? Number)?.toInt() ?: 0,
            trackingAccuracyThreshold = (map["trackingAccuracyThreshold"] as? Number)?.toInt() ?: 0,
            useKalmanFilter = map["useKalmanFilter"] as? Boolean ?: false,
            rejectMockLocations = map["rejectMockLocations"] as? Boolean ?: false,
            mockDetectionLevel = MockDetectionLevel.fromValue((map["mockDetectionLevel"] as? Number)?.toInt() ?: 0),
        )
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "policy" to policy.value,
        "maxImpliedSpeed" to maxImpliedSpeed,
        "odometerAccuracyThreshold" to odometerAccuracyThreshold,
        "trackingAccuracyThreshold" to trackingAccuracyThreshold,
        "useKalmanFilter" to useKalmanFilter,
        "rejectMockLocations" to rejectMockLocations,
        "mockDetectionLevel" to mockDetectionLevel.value,
    )
}

/**
 * Application lifecycle and scheduling settings.
 *
 * ```kotlin
 * AppConfig(
 *     stopOnTerminate = false,
 *     startOnBoot = true,
 *     foregroundService = ForegroundServiceConfig(
 *         notificationTitle = "My App",
 *         notificationText = "Tracking your location",
 *     ),
 * )
 * ```
 */
data class AppConfig(
    val stopOnTerminate: Boolean = true,
    val startOnBoot: Boolean = false,
    val heartbeatInterval: Int = 60,
    val schedule: List<String> = emptyList(),
    val scheduleUseAlarmManager: Boolean = false,
    val preventSuspend: Boolean = false,
    val foregroundService: ForegroundServiceConfig = ForegroundServiceConfig(),
    val remoteConfigUrl: String? = null,
    val remoteConfigHeaders: Map<String, String> = emptyMap(),
    val remoteConfigTimeout: Int = 10000,
    val remoteConfigRefreshInterval: Int = 0,
) {
    companion object {
        @Suppress("UNCHECKED_CAST")
        fun fromMap(map: Map<String, Any?>): AppConfig = AppConfig(
            stopOnTerminate = map["stopOnTerminate"] as? Boolean ?: true,
            startOnBoot = map["startOnBoot"] as? Boolean ?: false,
            heartbeatInterval = (map["heartbeatInterval"] as? Number)?.toInt() ?: 60,
            schedule = (map["schedule"] as? List<*>)?.mapNotNull { it as? String } ?: emptyList(),
            scheduleUseAlarmManager = map["scheduleUseAlarmManager"] as? Boolean ?: false,
            preventSuspend = map["preventSuspend"] as? Boolean ?: false,
            foregroundService = (map["foregroundService"] as? Map<String, Any?>)?.let { ForegroundServiceConfig.fromMap(it) } ?: ForegroundServiceConfig(),
            remoteConfigUrl = map["remoteConfigUrl"] as? String,
            remoteConfigHeaders = (map["remoteConfigHeaders"] as? Map<String, String>) ?: emptyMap(),
            remoteConfigTimeout = (map["remoteConfigTimeout"] as? Number)?.toInt() ?: 10000,
            remoteConfigRefreshInterval = (map["remoteConfigRefreshInterval"] as? Number)?.toInt() ?: 0,
        )
    }

    fun toMap(): Map<String, Any?> = buildMap {
        put("stopOnTerminate", stopOnTerminate)
        put("startOnBoot", startOnBoot)
        put("heartbeatInterval", heartbeatInterval)
        put("schedule", schedule)
        put("scheduleUseAlarmManager", scheduleUseAlarmManager)
        put("preventSuspend", preventSuspend)
        put("foregroundService", foregroundService.toMap())
        put("remoteConfigUrl", remoteConfigUrl)
        put("remoteConfigHeaders", remoteConfigHeaders)
        put("remoteConfigTimeout", remoteConfigTimeout)
        put("remoteConfigRefreshInterval", remoteConfigRefreshInterval)
    }
}

/**
 * Android foreground service notification configuration.
 *
 * ```kotlin
 * ForegroundServiceConfig(
 *     notificationTitle = "Fleet Tracker",
 *     notificationText = "Recording trip",
 *     notificationColor = "#4CAF50",
 *     notificationPriority = NotificationPriority.LOW,
 * )
 * ```
 */
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
    val actions: List<String> = emptyList(),
) {
    companion object {
        @Suppress("UNCHECKED_CAST")
        fun fromMap(map: Map<String, Any?>): ForegroundServiceConfig = ForegroundServiceConfig(
            enabled = map["enabled"] as? Boolean ?: true,
            channelId = map["channelId"] as? String ?: "tracelet_channel",
            channelName = map["channelName"] as? String ?: "Tracelet",
            notificationTitle = map["notificationTitle"] as? String ?: "Tracelet",
            notificationText = map["notificationText"] as? String ?: "Tracking location in background",
            notificationColor = map["notificationColor"] as? String,
            notificationSmallIcon = map["notificationSmallIcon"] as? String,
            notificationLargeIcon = map["notificationLargeIcon"] as? String,
            notificationPriority = NotificationPriority.fromValue((map["notificationPriority"] as? Number)?.toInt() ?: 0),
            notificationOngoing = map["notificationOngoing"] as? Boolean ?: true,
            actions = (map["actions"] as? List<*>)?.mapNotNull { it as? String } ?: emptyList(),
        )
    }

    fun toMap(): Map<String, Any?> = buildMap {
        put("enabled", enabled)
        put("channelId", channelId)
        put("channelName", channelName)
        put("notificationTitle", notificationTitle)
        put("notificationText", notificationText)
        put("notificationColor", notificationColor)
        put("notificationSmallIcon", notificationSmallIcon)
        put("notificationLargeIcon", notificationLargeIcon)
        put("notificationPriority", notificationPriority.value)
        put("notificationOngoing", notificationOngoing)
        put("actions", actions)
    }
}

/**
 * HTTP synchronization settings.
 *
 * ```kotlin
 * HttpConfig(
 *     url = "https://api.example.com/locations",
 *     batchSync = true,
 *     maxBatchSize = 100,
 *     headers = mapOf("Authorization" to "Bearer token"),
 * )
 * ```
 */
data class HttpConfig(
    val url: String? = null,
    val method: HttpMethod = HttpMethod.POST,
    val headers: Map<String, String> = emptyMap(),
    val httpRootProperty: String = "location",
    val batchSync: Boolean = false,
    val maxBatchSize: Int = 250,
    val autoSync: Boolean = true,
    val autoSyncThreshold: Int = 0,
    val httpTimeout: Int = 60000,
    val params: Map<String, Any?> = emptyMap(),
    val locationsOrderDirection: LocationOrder = LocationOrder.ASC,
    val extras: Map<String, Any?> = emptyMap(),
    val disableAutoSyncOnCellular: Boolean = false,
    val maxRetries: Int = 10,
    val retryBackoffBase: Int = 1000,
    val retryBackoffCap: Int = 300000,
    val enableDeltaCompression: Boolean = false,
    val deltaCoordinatePrecision: Int = 6,
    val sslPinningCertificates: List<String> = emptyList(),
    val sslPinningFingerprints: List<String> = emptyList(),
) {
    companion object {
        @Suppress("UNCHECKED_CAST")
        fun fromMap(map: Map<String, Any?>): HttpConfig = HttpConfig(
            url = map["url"] as? String,
            method = HttpMethod.fromValue((map["method"] as? Number)?.toInt() ?: 0),
            headers = (map["headers"] as? Map<String, String>) ?: emptyMap(),
            httpRootProperty = map["httpRootProperty"] as? String ?: "location",
            batchSync = map["batchSync"] as? Boolean ?: false,
            maxBatchSize = (map["maxBatchSize"] as? Number)?.toInt() ?: 250,
            autoSync = map["autoSync"] as? Boolean ?: true,
            autoSyncThreshold = (map["autoSyncThreshold"] as? Number)?.toInt() ?: 0,
            httpTimeout = (map["httpTimeout"] as? Number)?.toInt() ?: 60000,
            params = (map["params"] as? Map<String, Any?>) ?: emptyMap(),
            locationsOrderDirection = LocationOrder.fromValue((map["locationsOrderDirection"] as? Number)?.toInt() ?: 0),
            extras = (map["httpExtras"] as? Map<String, Any?>) ?: emptyMap(),
            disableAutoSyncOnCellular = map["disableAutoSyncOnCellular"] as? Boolean ?: false,
            maxRetries = (map["maxRetries"] as? Number)?.toInt() ?: 10,
            retryBackoffBase = (map["retryBackoffBase"] as? Number)?.toInt() ?: 1000,
            retryBackoffCap = (map["retryBackoffCap"] as? Number)?.toInt() ?: 300000,
            enableDeltaCompression = map["enableDeltaCompression"] as? Boolean ?: false,
            deltaCoordinatePrecision = (map["deltaCoordinatePrecision"] as? Number)?.toInt() ?: 6,
            sslPinningCertificates = (map["sslPinningCertificates"] as? List<*>)?.mapNotNull { it as? String } ?: emptyList(),
            sslPinningFingerprints = (map["sslPinningFingerprints"] as? List<*>)?.mapNotNull { it as? String } ?: emptyList(),
        )
    }

    fun toMap(): Map<String, Any?> = buildMap {
        put("url", url)
        put("method", method.value)
        put("headers", headers)
        put("httpRootProperty", httpRootProperty)
        put("batchSync", batchSync)
        put("maxBatchSize", maxBatchSize)
        put("autoSync", autoSync)
        put("autoSyncThreshold", autoSyncThreshold)
        put("httpTimeout", httpTimeout)
        put("params", params)
        put("locationsOrderDirection", locationsOrderDirection.value)
        put("httpExtras", extras)
        put("disableAutoSyncOnCellular", disableAutoSyncOnCellular)
        put("maxRetries", maxRetries)
        put("retryBackoffBase", retryBackoffBase)
        put("retryBackoffCap", retryBackoffCap)
        put("enableDeltaCompression", enableDeltaCompression)
        put("deltaCoordinatePrecision", deltaCoordinatePrecision)
        put("sslPinningCertificates", sslPinningCertificates)
        put("sslPinningFingerprints", sslPinningFingerprints)
    }
}

/**
 * Logging and debug sound settings.
 *
 * ```kotlin
 * LoggerConfig(
 *     logLevel = LogLevel.VERBOSE,
 *     debug = true,
 * )
 * ```
 */
data class LoggerConfig(
    val logLevel: LogLevel = LogLevel.INFO,
    val logMaxDays: Int = 3,
    val debug: Boolean = false,
) {
    companion object {
        fun fromMap(map: Map<String, Any?>): LoggerConfig = LoggerConfig(
            logLevel = LogLevel.fromValue((map["logLevel"] as? Number)?.toInt() ?: 2),
            logMaxDays = (map["logMaxDays"] as? Number)?.toInt() ?: 3,
            debug = map["debug"] as? Boolean ?: false,
        )
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "logLevel" to logLevel.value,
        "logMaxDays" to logMaxDays,
        "debug" to debug,
    )
}

/**
 * Motion detection sensitivity settings.
 *
 * ```kotlin
 * MotionConfig(
 *     stopTimeout = 5,
 *     shakeThreshold = 2.5,
 *     stillThreshold = 0.4,
 * )
 * ```
 */
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
    val triggerActivities: Set<ActivityType> = emptySet(),
    val shakeThreshold: Double = 2.5,
    val stillThreshold: Double = 0.4,
    val stillSampleCount: Int = 25,
) {
    companion object {
        fun fromMap(map: Map<String, Any?>): MotionConfig = MotionConfig(
            stopTimeout = (map["stopTimeout"] as? Number)?.toInt() ?: 5,
            motionTriggerDelay = (map["motionTriggerDelay"] as? Number)?.toInt() ?: 0,
            disableMotionActivityUpdates = map["disableMotionActivityUpdates"] as? Boolean ?: false,
            isMoving = map["isMoving"] as? Boolean ?: false,
            activityRecognitionInterval = (map["activityRecognitionInterval"] as? Number)?.toInt() ?: 10000,
            minimumActivityRecognitionConfidence = (map["minimumActivityRecognitionConfidence"] as? Number)?.toInt() ?: 75,
            disableStopDetection = map["disableStopDetection"] as? Boolean ?: false,
            stopDetectionDelay = (map["stopDetectionDelay"] as? Number)?.toInt() ?: 0,
            stopOnStationary = map["stopOnStationary"] as? Boolean ?: false,
            triggerActivities = (map["triggerActivities"] as? List<*>)?.mapNotNull { name ->
                (name as? String)?.uppercase()?.let { upper ->
                    ActivityType.entries.firstOrNull { it.name == upper }
                }
            }?.toSet() ?: emptySet(),
            shakeThreshold = (map["shakeThreshold"] as? Number)?.toDouble() ?: 2.5,
            stillThreshold = (map["stillThreshold"] as? Number)?.toDouble() ?: 0.4,
            stillSampleCount = (map["stillSampleCount"] as? Number)?.toInt() ?: 25,
        )
    }

    fun toMap(): Map<String, Any?> = buildMap {
        put("stopTimeout", stopTimeout)
        put("motionTriggerDelay", motionTriggerDelay)
        put("disableMotionActivityUpdates", disableMotionActivityUpdates)
        put("isMoving", isMoving)
        put("activityRecognitionInterval", activityRecognitionInterval)
        put("minimumActivityRecognitionConfidence", minimumActivityRecognitionConfidence)
        put("disableStopDetection", disableStopDetection)
        put("stopDetectionDelay", stopDetectionDelay)
        put("stopOnStationary", stopOnStationary)
        put("triggerActivities", triggerActivities.map { it.name.lowercase() })
        put("shakeThreshold", shakeThreshold)
        put("stillThreshold", stillThreshold)
        put("stillSampleCount", stillSampleCount)
    }
}

/**
 * Geofencing settings.
 *
 * ```kotlin
 * GeofenceConfig(
 *     geofenceProximityRadius = 2000,
 *     geofenceInitialTriggerEntry = true,
 * )
 * ```
 */
data class GeofenceConfig(
    val geofenceProximityRadius: Int = 1000,
    val geofenceInitialTriggerEntry: Boolean = true,
    val geofenceModeKnockOut: Boolean = false,
) {
    companion object {
        fun fromMap(map: Map<String, Any?>): GeofenceConfig = GeofenceConfig(
            geofenceProximityRadius = (map["geofenceProximityRadius"] as? Number)?.toInt() ?: 1000,
            geofenceInitialTriggerEntry = map["geofenceInitialTriggerEntry"] as? Boolean ?: true,
            geofenceModeKnockOut = map["geofenceModeKnockOut"] as? Boolean ?: false,
        )
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "geofenceProximityRadius" to geofenceProximityRadius,
        "geofenceInitialTriggerEntry" to geofenceInitialTriggerEntry,
        "geofenceModeKnockOut" to geofenceModeKnockOut,
    )
}

/**
 * Database persistence and retention settings.
 *
 * ```kotlin
 * PersistenceConfig(
 *     maxDaysToPersist = 14,
 *     maxRecordsToPersist = 5000,
 * )
 * ```
 */
data class PersistenceConfig(
    val persistMode: PersistMode = PersistMode.ALL,
    val maxDaysToPersist: Int = -1,
    val maxRecordsToPersist: Int = -1,
    val locationTemplate: String? = null,
    val geofenceTemplate: String? = null,
    val disableProviderChangeRecord: Boolean = false,
    val extras: Map<String, Any?> = emptyMap(),
) {
    companion object {
        @Suppress("UNCHECKED_CAST")
        fun fromMap(map: Map<String, Any?>): PersistenceConfig = PersistenceConfig(
            persistMode = PersistMode.fromValue((map["persistMode"] as? Number)?.toInt() ?: 0),
            maxDaysToPersist = (map["maxDaysToPersist"] as? Number)?.toInt() ?: -1,
            maxRecordsToPersist = (map["maxRecordsToPersist"] as? Number)?.toInt() ?: -1,
            locationTemplate = map["locationTemplate"] as? String,
            geofenceTemplate = map["geofenceTemplate"] as? String,
            disableProviderChangeRecord = map["disableProviderChangeRecord"] as? Boolean ?: false,
            extras = (map["persistenceExtras"] as? Map<String, Any?>) ?: emptyMap(),
        )
    }

    fun toMap(): Map<String, Any?> = buildMap {
        put("persistMode", persistMode.value)
        put("maxDaysToPersist", maxDaysToPersist)
        put("maxRecordsToPersist", maxRecordsToPersist)
        put("locationTemplate", locationTemplate)
        put("geofenceTemplate", geofenceTemplate)
        put("disableProviderChangeRecord", disableProviderChangeRecord)
        put("persistenceExtras", extras)
    }
}

/**
 * Tamper-proof audit trail settings (Enterprise).
 *
 * ```kotlin
 * AuditConfig(enabled = true, hashAlgorithm = HashAlgorithm.SHA256)
 * ```
 */
data class AuditConfig(
    val enabled: Boolean = false,
    val hashAlgorithm: HashAlgorithm = HashAlgorithm.SHA256,
) {
    companion object {
        fun fromMap(map: Map<String, Any?>): AuditConfig = AuditConfig(
            enabled = map["enabled"] as? Boolean ?: false,
            hashAlgorithm = HashAlgorithm.fromValue((map["hashAlgorithm"] as? Number)?.toInt() ?: 0),
        )
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "enabled" to enabled,
        "hashAlgorithm" to hashAlgorithm.value,
    )
}

/**
 * Privacy zone controls (Enterprise).
 *
 * ```kotlin
 * PrivacyZoneConfig(enabled = true)
 * ```
 */
data class PrivacyZoneConfig(
    val enabled: Boolean = false,
) {
    companion object {
        fun fromMap(map: Map<String, Any?>): PrivacyZoneConfig = PrivacyZoneConfig(
            enabled = map["enabled"] as? Boolean ?: false,
        )
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "enabled" to enabled,
    )
}

/**
 * At-rest database encryption settings (Enterprise).
 *
 * ```kotlin
 * SecurityConfig(encryptDatabase = true)
 * ```
 */
data class SecurityConfig(
    val encryptDatabase: Boolean = false,
) {
    companion object {
        fun fromMap(map: Map<String, Any?>): SecurityConfig = SecurityConfig(
            encryptDatabase = map["encryptDatabase"] as? Boolean ?: false,
        )
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "encryptDatabase" to encryptDatabase,
    )
}

/**
 * Device integrity attestation settings (Enterprise).
 *
 * ```kotlin
 * AttestationConfig(enabled = true, refreshInterval = 3600)
 * ```
 */
data class AttestationConfig(
    val enabled: Boolean = false,
    val refreshInterval: Int = 3600,
) {
    companion object {
        fun fromMap(map: Map<String, Any?>): AttestationConfig = AttestationConfig(
            enabled = map["enabled"] as? Boolean ?: false,
            refreshInterval = (map["refreshInterval"] as? Number)?.toInt() ?: 3600,
        )
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "enabled" to enabled,
        "refreshInterval" to refreshInterval,
    )
}
