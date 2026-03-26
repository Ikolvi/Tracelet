import Foundation

// MARK: - Enums

/// GPS accuracy level. Matches Dart `DesiredAccuracy`.
public enum TraceletDesiredAccuracy: Int {
    /// GPS-level accuracy (~5m). Highest battery usage.
    case high = 0
    /// WiFi/cell accuracy (~100m). Moderate battery.
    case medium = 1
    /// City-level accuracy (~1km). Lowest battery.
    case low = 2
}

/// Log verbosity level. Matches Dart `LogLevel`.
public enum TraceletLogLevel: Int {
    case verbose = 0
    case debug = 1
    case info = 2
    case warn = 3
    case error = 4
}

/// HTTP method for server sync.
public enum TraceletHttpMethod: Int {
    case post = 0
    case put = 1
}

/// Location record persistence mode.
public enum TraceletPersistMode: Int {
    case all = 0
    case location = 1
    case geofence = 2
    case none = 3
}

/// Location filter policy.
public enum TraceletLocationFilterPolicy: Int {
    case adjust = 0
    case ignore = 1
    case discard = 2
}

/// Mock detection aggressiveness.
public enum TraceletMockDetectionLevel: Int {
    case disabled = 0
    case basic = 1
    case heuristic = 2
}

/// Activity type hint (iOS CLActivityType mapping).
public enum TraceletActivityType: Int {
    case other = 0
    case automotiveNavigation = 1
    case fitness = 2
    case otherNavigation = 3
    case airborne = 4
}

/// Location authorization level.
public enum TraceletAuthorizationRequest {
    case always
    case whenInUse
}

/// Notification priority (Android foreground service).
public enum TraceletNotificationPriority: Int {
    case min = -2
    case low = -1
    case `default` = 0
    case high = 1
    case max = 2
}

/// Locations sort order for HTTP sync.
public enum TraceletLocationOrder: Int {
    case asc = 0
    case desc = 1
}

/// Activity type for motion trigger filtering.
public enum TraceletMotionActivityType: String {
    case still
    case onFoot = "on_foot"
    case walking
    case running
    case onBicycle = "on_bicycle"
    case inVehicle = "in_vehicle"
    case unknown
}

/// Hash algorithm for audit trail.
public enum TraceletHashAlgorithm: Int {
    case sha256 = 0
    case sha512 = 1
}

// MARK: - TraceletConfig

/// Typed configuration for the Tracelet SDK.
///
/// Mirrors the Dart `Config` class so native iOS developers get the same
/// structured, type-safe API:
///
/// ```swift
/// let config = TraceletConfig(
///     geo: .init(
///         desiredAccuracy: .high,
///         distanceFilter: 10.0,
///         filter: .init(
///             trackingAccuracyThreshold: 100,
///             maxImpliedSpeed: 80
///         )
///     ),
///     app: .init(
///         stopOnTerminate: false,
///         startOnBoot: true
///     ),
///     persistence: .init(
///         maxDaysToPersist: 7,
///         maxRecordsToPersist: 5000
///     ),
///     logger: .init(
///         debug: true,
///         logLevel: .verbose
///     )
/// )
///
/// sdk.ready(config: config)
/// ```
public struct TraceletConfig {
    public let geo: TraceletGeoConfig
    public let app: TraceletAppConfig
    public let http: TraceletHttpConfig
    public let logger: TraceletLoggerConfig
    public let motion: TraceletMotionConfig
    public let geofence: TraceletGeofenceConfig
    public let persistence: TraceletPersistenceConfig
    public let audit: TraceletAuditConfig
    public let privacyZone: TraceletPrivacyZoneConfig
    public let security: TraceletSecurityConfig
    public let attestation: TraceletAttestationConfig

    public init(
        geo: TraceletGeoConfig = .init(),
        app: TraceletAppConfig = .init(),
        http: TraceletHttpConfig = .init(),
        logger: TraceletLoggerConfig = .init(),
        motion: TraceletMotionConfig = .init(),
        geofence: TraceletGeofenceConfig = .init(),
        persistence: TraceletPersistenceConfig = .init(),
        audit: TraceletAuditConfig = .init(),
        privacyZone: TraceletPrivacyZoneConfig = .init(),
        security: TraceletSecurityConfig = .init(),
        attestation: TraceletAttestationConfig = .init()
    ) {
        self.geo = geo
        self.app = app
        self.http = http
        self.logger = logger
        self.motion = motion
        self.geofence = geofence
        self.persistence = persistence
        self.audit = audit
        self.privacyZone = privacyZone
        self.security = security
        self.attestation = attestation
    }

    /// Converts to the dictionary format expected by ``ConfigManager``.
    public func toMap() -> [String: Any] {
        [
            "geo": geo.toMap(),
            "app": app.toMap(),
            "http": http.toMap(),
            "logger": logger.toMap(),
            "motion": motion.toMap(),
            "geofence": geofence.toMap(),
            "persistence": persistence.toMap(),
            "audit": audit.toMap(),
            "privacyZone": privacyZone.toMap(),
            "security": security.toMap(),
            "attestation": attestation.toMap(),
        ]
    }

    /// Creates a ``TraceletConfig`` from a dictionary.
    public static func fromMap(_ map: [String: Any]) -> TraceletConfig {
        TraceletConfig(
            geo: (map["geo"] as? [String: Any]).map { TraceletGeoConfig.fromMap($0) } ?? .init(),
            app: (map["app"] as? [String: Any]).map { TraceletAppConfig.fromMap($0) } ?? .init(),
            http: (map["http"] as? [String: Any]).map { TraceletHttpConfig.fromMap($0) } ?? .init(),
            logger: (map["logger"] as? [String: Any]).map { TraceletLoggerConfig.fromMap($0) } ?? .init(),
            motion: (map["motion"] as? [String: Any]).map { TraceletMotionConfig.fromMap($0) } ?? .init(),
            geofence: (map["geofence"] as? [String: Any]).map { TraceletGeofenceConfig.fromMap($0) } ?? .init(),
            persistence: (map["persistence"] as? [String: Any]).map { TraceletPersistenceConfig.fromMap($0) } ?? .init(),
            audit: (map["audit"] as? [String: Any]).map { TraceletAuditConfig.fromMap($0) } ?? .init(),
            privacyZone: (map["privacyZone"] as? [String: Any]).map { TraceletPrivacyZoneConfig.fromMap($0) } ?? .init(),
            security: (map["security"] as? [String: Any]).map { TraceletSecurityConfig.fromMap($0) } ?? .init(),
            attestation: (map["attestation"] as? [String: Any]).map { TraceletAttestationConfig.fromMap($0) } ?? .init()
        )
    }
}

// MARK: - GeoConfig

/// Location accuracy, sampling, and filtering settings.
///
/// ```swift
/// TraceletGeoConfig(
///     desiredAccuracy: .high,
///     distanceFilter: 10.0,
///     filter: .init(maxImpliedSpeed: 80)
/// )
/// ```
public struct TraceletGeoConfig {
    public let desiredAccuracy: TraceletDesiredAccuracy
    public let distanceFilter: Double
    public let locationUpdateInterval: Int
    public let fastestLocationUpdateInterval: Int
    public let stationaryRadius: Double
    public let locationTimeout: Int
    public let activityType: TraceletActivityType
    public let disableElasticity: Bool
    public let elasticityMultiplier: Double
    public let stopAfterElapsedMinutes: Int
    public let deferTime: Int
    public let allowIdenticalLocations: Bool
    public let geofenceModeHighAccuracy: Bool
    public let maxMonitoredGeofences: Int
    public let useSignificantChangesOnly: Bool
    public let showsBackgroundLocationIndicator: Bool
    public let pausesLocationUpdatesAutomatically: Bool
    public let locationAuthorizationRequest: TraceletAuthorizationRequest
    public let disableLocationAuthorizationAlert: Bool
    public let enableTimestampMeta: Bool
    public let enableAdaptiveMode: Bool
    public let periodicLocationInterval: Int
    public let periodicDesiredAccuracy: TraceletDesiredAccuracy
    public let periodicUseForegroundService: Bool
    public let periodicUseExactAlarms: Bool
    public let enableSparseUpdates: Bool
    public let sparseDistanceThreshold: Double
    public let sparseMaxIdleSeconds: Int
    public let enableDeadReckoning: Bool
    public let deadReckoningActivationDelay: Int
    public let deadReckoningMaxDuration: Int
    public let batteryBudgetPerHour: Double
    public let filter: TraceletLocationFilter?

    public init(
        desiredAccuracy: TraceletDesiredAccuracy = .high,
        distanceFilter: Double = 10.0,
        locationUpdateInterval: Int = 1000,
        fastestLocationUpdateInterval: Int = 500,
        stationaryRadius: Double = 25.0,
        locationTimeout: Int = 60,
        activityType: TraceletActivityType = .other,
        disableElasticity: Bool = false,
        elasticityMultiplier: Double = 1.0,
        stopAfterElapsedMinutes: Int = -1,
        deferTime: Int = 0,
        allowIdenticalLocations: Bool = false,
        geofenceModeHighAccuracy: Bool = false,
        maxMonitoredGeofences: Int = -1,
        useSignificantChangesOnly: Bool = false,
        showsBackgroundLocationIndicator: Bool = false,
        pausesLocationUpdatesAutomatically: Bool = false,
        locationAuthorizationRequest: TraceletAuthorizationRequest = .always,
        disableLocationAuthorizationAlert: Bool = false,
        enableTimestampMeta: Bool = false,
        enableAdaptiveMode: Bool = false,
        periodicLocationInterval: Int = 900,
        periodicDesiredAccuracy: TraceletDesiredAccuracy = .medium,
        periodicUseForegroundService: Bool = false,
        periodicUseExactAlarms: Bool = false,
        enableSparseUpdates: Bool = false,
        sparseDistanceThreshold: Double = 50.0,
        sparseMaxIdleSeconds: Int = 300,
        enableDeadReckoning: Bool = false,
        deadReckoningActivationDelay: Int = 10,
        deadReckoningMaxDuration: Int = 120,
        batteryBudgetPerHour: Double = 0.0,
        filter: TraceletLocationFilter? = nil
    ) {
        self.desiredAccuracy = desiredAccuracy
        self.distanceFilter = distanceFilter
        self.locationUpdateInterval = locationUpdateInterval
        self.fastestLocationUpdateInterval = fastestLocationUpdateInterval
        self.stationaryRadius = stationaryRadius
        self.locationTimeout = locationTimeout
        self.activityType = activityType
        self.disableElasticity = disableElasticity
        self.elasticityMultiplier = elasticityMultiplier
        self.stopAfterElapsedMinutes = stopAfterElapsedMinutes
        self.deferTime = deferTime
        self.allowIdenticalLocations = allowIdenticalLocations
        self.geofenceModeHighAccuracy = geofenceModeHighAccuracy
        self.maxMonitoredGeofences = maxMonitoredGeofences
        self.useSignificantChangesOnly = useSignificantChangesOnly
        self.showsBackgroundLocationIndicator = showsBackgroundLocationIndicator
        self.pausesLocationUpdatesAutomatically = pausesLocationUpdatesAutomatically
        self.locationAuthorizationRequest = locationAuthorizationRequest
        self.disableLocationAuthorizationAlert = disableLocationAuthorizationAlert
        self.enableTimestampMeta = enableTimestampMeta
        self.enableAdaptiveMode = enableAdaptiveMode
        self.periodicLocationInterval = periodicLocationInterval
        self.periodicDesiredAccuracy = periodicDesiredAccuracy
        self.periodicUseForegroundService = periodicUseForegroundService
        self.periodicUseExactAlarms = periodicUseExactAlarms
        self.enableSparseUpdates = enableSparseUpdates
        self.sparseDistanceThreshold = sparseDistanceThreshold
        self.sparseMaxIdleSeconds = sparseMaxIdleSeconds
        self.enableDeadReckoning = enableDeadReckoning
        self.deadReckoningActivationDelay = deadReckoningActivationDelay
        self.deadReckoningMaxDuration = deadReckoningMaxDuration
        self.batteryBudgetPerHour = batteryBudgetPerHour
        self.filter = filter
    }

    public func toMap() -> [String: Any] {
        var map: [String: Any] = [
            "desiredAccuracy": desiredAccuracy.rawValue,
            "distanceFilter": distanceFilter,
            "locationUpdateInterval": locationUpdateInterval,
            "fastestLocationUpdateInterval": fastestLocationUpdateInterval,
            "stationaryRadius": stationaryRadius,
            "locationTimeout": locationTimeout,
            "activityType": activityType.rawValue,
            "disableElasticity": disableElasticity,
            "elasticityMultiplier": elasticityMultiplier,
            "stopAfterElapsedMinutes": stopAfterElapsedMinutes,
            "deferTime": deferTime,
            "allowIdenticalLocations": allowIdenticalLocations,
            "geofenceModeHighAccuracy": geofenceModeHighAccuracy,
            "maxMonitoredGeofences": maxMonitoredGeofences,
            "useSignificantChangesOnly": useSignificantChangesOnly,
            "showsBackgroundLocationIndicator": showsBackgroundLocationIndicator,
            "pausesLocationUpdatesAutomatically": pausesLocationUpdatesAutomatically,
            "locationAuthorizationRequest": locationAuthorizationRequest == .always ? "Always" : "WhenInUse",
            "disableLocationAuthorizationAlert": disableLocationAuthorizationAlert,
            "enableTimestampMeta": enableTimestampMeta,
            "enableAdaptiveMode": enableAdaptiveMode,
            "periodicLocationInterval": periodicLocationInterval,
            "periodicDesiredAccuracy": periodicDesiredAccuracy.rawValue,
            "periodicUseForegroundService": periodicUseForegroundService,
            "periodicUseExactAlarms": periodicUseExactAlarms,
            "enableSparseUpdates": enableSparseUpdates,
            "sparseDistanceThreshold": sparseDistanceThreshold,
            "sparseMaxIdleSeconds": sparseMaxIdleSeconds,
            "enableDeadReckoning": enableDeadReckoning,
            "deadReckoningActivationDelay": deadReckoningActivationDelay,
            "deadReckoningMaxDuration": deadReckoningMaxDuration,
            "batteryBudgetPerHour": batteryBudgetPerHour,
        ]
        if let filter = filter {
            map["filter"] = filter.toMap()
        }
        return map
    }

    /// Creates a ``TraceletGeoConfig`` from a dictionary.
    public static func fromMap(_ map: [String: Any]) -> TraceletGeoConfig {
        TraceletGeoConfig(
            desiredAccuracy: TraceletDesiredAccuracy(rawValue: map["desiredAccuracy"] as? Int ?? 0) ?? .high,
            distanceFilter: (map["distanceFilter"] as? NSNumber)?.doubleValue ?? 10.0,
            locationUpdateInterval: map["locationUpdateInterval"] as? Int ?? 1000,
            fastestLocationUpdateInterval: map["fastestLocationUpdateInterval"] as? Int ?? 500,
            stationaryRadius: (map["stationaryRadius"] as? NSNumber)?.doubleValue ?? 25.0,
            locationTimeout: map["locationTimeout"] as? Int ?? 60,
            activityType: TraceletActivityType(rawValue: map["activityType"] as? Int ?? 0) ?? .other,
            disableElasticity: map["disableElasticity"] as? Bool ?? false,
            elasticityMultiplier: (map["elasticityMultiplier"] as? NSNumber)?.doubleValue ?? 1.0,
            stopAfterElapsedMinutes: map["stopAfterElapsedMinutes"] as? Int ?? -1,
            deferTime: map["deferTime"] as? Int ?? 0,
            allowIdenticalLocations: map["allowIdenticalLocations"] as? Bool ?? false,
            geofenceModeHighAccuracy: map["geofenceModeHighAccuracy"] as? Bool ?? false,
            maxMonitoredGeofences: map["maxMonitoredGeofences"] as? Int ?? -1,
            useSignificantChangesOnly: map["useSignificantChangesOnly"] as? Bool ?? false,
            showsBackgroundLocationIndicator: map["showsBackgroundLocationIndicator"] as? Bool ?? false,
            pausesLocationUpdatesAutomatically: map["pausesLocationUpdatesAutomatically"] as? Bool ?? false,
            locationAuthorizationRequest: (map["locationAuthorizationRequest"] as? String) == "WhenInUse" ? .whenInUse : .always,
            disableLocationAuthorizationAlert: map["disableLocationAuthorizationAlert"] as? Bool ?? false,
            enableTimestampMeta: map["enableTimestampMeta"] as? Bool ?? false,
            enableAdaptiveMode: map["enableAdaptiveMode"] as? Bool ?? false,
            periodicLocationInterval: map["periodicLocationInterval"] as? Int ?? 900,
            periodicDesiredAccuracy: TraceletDesiredAccuracy(rawValue: map["periodicDesiredAccuracy"] as? Int ?? 1) ?? .medium,
            periodicUseForegroundService: map["periodicUseForegroundService"] as? Bool ?? false,
            periodicUseExactAlarms: map["periodicUseExactAlarms"] as? Bool ?? false,
            enableSparseUpdates: map["enableSparseUpdates"] as? Bool ?? false,
            sparseDistanceThreshold: (map["sparseDistanceThreshold"] as? NSNumber)?.doubleValue ?? 50.0,
            sparseMaxIdleSeconds: map["sparseMaxIdleSeconds"] as? Int ?? 300,
            enableDeadReckoning: map["enableDeadReckoning"] as? Bool ?? false,
            deadReckoningActivationDelay: map["deadReckoningActivationDelay"] as? Int ?? 10,
            deadReckoningMaxDuration: map["deadReckoningMaxDuration"] as? Int ?? 120,
            batteryBudgetPerHour: (map["batteryBudgetPerHour"] as? NSNumber)?.doubleValue ?? 0.0,
            filter: (map["filter"] as? [String: Any]).map { TraceletLocationFilter.fromMap($0) }
        )
    }
}

// MARK: - LocationFilter

/// Location filtering and denoising.
///
/// ```swift
/// TraceletLocationFilter(
///     trackingAccuracyThreshold: 100,
///     maxImpliedSpeed: 80,
///     useKalmanFilter: true
/// )
/// ```
public struct TraceletLocationFilter {
    public let policy: TraceletLocationFilterPolicy
    public let maxImpliedSpeed: Int
    public let odometerAccuracyThreshold: Int
    public let trackingAccuracyThreshold: Int
    public let useKalmanFilter: Bool
    public let rejectMockLocations: Bool
    public let mockDetectionLevel: TraceletMockDetectionLevel

    public init(
        policy: TraceletLocationFilterPolicy = .adjust,
        maxImpliedSpeed: Int = 0,
        odometerAccuracyThreshold: Int = 0,
        trackingAccuracyThreshold: Int = 0,
        useKalmanFilter: Bool = false,
        rejectMockLocations: Bool = false,
        mockDetectionLevel: TraceletMockDetectionLevel = .disabled
    ) {
        self.policy = policy
        self.maxImpliedSpeed = maxImpliedSpeed
        self.odometerAccuracyThreshold = odometerAccuracyThreshold
        self.trackingAccuracyThreshold = trackingAccuracyThreshold
        self.useKalmanFilter = useKalmanFilter
        self.rejectMockLocations = rejectMockLocations
        self.mockDetectionLevel = mockDetectionLevel
    }

    public func toMap() -> [String: Any] {
        [
            "policy": policy.rawValue,
            "maxImpliedSpeed": maxImpliedSpeed,
            "odometerAccuracyThreshold": odometerAccuracyThreshold,
            "trackingAccuracyThreshold": trackingAccuracyThreshold,
            "useKalmanFilter": useKalmanFilter,
            "rejectMockLocations": rejectMockLocations,
            "mockDetectionLevel": mockDetectionLevel.rawValue,
        ]
    }

    /// Creates a ``TraceletLocationFilter`` from a dictionary.
    public static func fromMap(_ map: [String: Any]) -> TraceletLocationFilter {
        TraceletLocationFilter(
            policy: TraceletLocationFilterPolicy(rawValue: map["policy"] as? Int ?? 0) ?? .adjust,
            maxImpliedSpeed: map["maxImpliedSpeed"] as? Int ?? 0,
            odometerAccuracyThreshold: map["odometerAccuracyThreshold"] as? Int ?? 0,
            trackingAccuracyThreshold: map["trackingAccuracyThreshold"] as? Int ?? 0,
            useKalmanFilter: map["useKalmanFilter"] as? Bool ?? false,
            rejectMockLocations: map["rejectMockLocations"] as? Bool ?? false,
            mockDetectionLevel: TraceletMockDetectionLevel(rawValue: map["mockDetectionLevel"] as? Int ?? 0) ?? .disabled
        )
    }
}

// MARK: - AppConfig

/// Application lifecycle and scheduling settings.
///
/// ```swift
/// TraceletAppConfig(
///     stopOnTerminate: false,
///     startOnBoot: true,
///     preventSuspend: true
/// )
/// ```
public struct TraceletAppConfig {
    public let stopOnTerminate: Bool
    public let startOnBoot: Bool
    public let heartbeatInterval: Int
    public let schedule: [String]
    public let scheduleUseAlarmManager: Bool
    public let preventSuspend: Bool
    public let foregroundService: TraceletForegroundServiceConfig
    public let remoteConfigUrl: String?
    public let remoteConfigHeaders: [String: String]
    public let remoteConfigTimeout: Int
    public let remoteConfigRefreshInterval: Int

    public init(
        stopOnTerminate: Bool = true,
        startOnBoot: Bool = false,
        heartbeatInterval: Int = 60,
        schedule: [String] = [],
        scheduleUseAlarmManager: Bool = false,
        preventSuspend: Bool = false,
        foregroundService: TraceletForegroundServiceConfig = .init(),
        remoteConfigUrl: String? = nil,
        remoteConfigHeaders: [String: String] = [:],
        remoteConfigTimeout: Int = 10000,
        remoteConfigRefreshInterval: Int = 0
    ) {
        self.stopOnTerminate = stopOnTerminate
        self.startOnBoot = startOnBoot
        self.heartbeatInterval = heartbeatInterval
        self.schedule = schedule
        self.scheduleUseAlarmManager = scheduleUseAlarmManager
        self.preventSuspend = preventSuspend
        self.foregroundService = foregroundService
        self.remoteConfigUrl = remoteConfigUrl
        self.remoteConfigHeaders = remoteConfigHeaders
        self.remoteConfigTimeout = remoteConfigTimeout
        self.remoteConfigRefreshInterval = remoteConfigRefreshInterval
    }

    public func toMap() -> [String: Any] {
        var map: [String: Any] = [
            "stopOnTerminate": stopOnTerminate,
            "startOnBoot": startOnBoot,
            "heartbeatInterval": heartbeatInterval,
            "schedule": schedule,
            "scheduleUseAlarmManager": scheduleUseAlarmManager,
            "preventSuspend": preventSuspend,
            "foregroundService": foregroundService.toMap(),
            "remoteConfigHeaders": remoteConfigHeaders,
            "remoteConfigTimeout": remoteConfigTimeout,
            "remoteConfigRefreshInterval": remoteConfigRefreshInterval,
        ]
        if let url = remoteConfigUrl {
            map["remoteConfigUrl"] = url
        }
        return map
    }

    /// Creates a ``TraceletAppConfig`` from a dictionary.
    public static func fromMap(_ map: [String: Any]) -> TraceletAppConfig {
        TraceletAppConfig(
            stopOnTerminate: map["stopOnTerminate"] as? Bool ?? true,
            startOnBoot: map["startOnBoot"] as? Bool ?? false,
            heartbeatInterval: map["heartbeatInterval"] as? Int ?? 60,
            schedule: map["schedule"] as? [String] ?? [],
            scheduleUseAlarmManager: map["scheduleUseAlarmManager"] as? Bool ?? false,
            preventSuspend: map["preventSuspend"] as? Bool ?? false,
            foregroundService: (map["foregroundService"] as? [String: Any]).map { TraceletForegroundServiceConfig.fromMap($0) } ?? .init(),
            remoteConfigUrl: map["remoteConfigUrl"] as? String,
            remoteConfigHeaders: map["remoteConfigHeaders"] as? [String: String] ?? [:],
            remoteConfigTimeout: map["remoteConfigTimeout"] as? Int ?? 10000,
            remoteConfigRefreshInterval: map["remoteConfigRefreshInterval"] as? Int ?? 0
        )
    }
}

// MARK: - ForegroundServiceConfig

/// Android foreground service notification configuration.
///
/// On iOS, foreground service config is ignored — iOS uses its own
/// background-mode mechanisms.
///
/// ```swift
/// TraceletForegroundServiceConfig(
///     notificationTitle: "Fleet Tracker",
///     notificationText: "Recording trip"
/// )
/// ```
public struct TraceletForegroundServiceConfig {
    public let enabled: Bool
    public let channelId: String
    public let channelName: String
    public let notificationTitle: String
    public let notificationText: String
    public let notificationColor: String?
    public let notificationSmallIcon: String?
    public let notificationLargeIcon: String?
    public let notificationPriority: TraceletNotificationPriority
    public let notificationOngoing: Bool
    public let actions: [String]

    public init(
        enabled: Bool = true,
        channelId: String = "tracelet_channel",
        channelName: String = "Tracelet",
        notificationTitle: String = "Tracelet",
        notificationText: String = "Tracking location in background",
        notificationColor: String? = nil,
        notificationSmallIcon: String? = nil,
        notificationLargeIcon: String? = nil,
        notificationPriority: TraceletNotificationPriority = .default,
        notificationOngoing: Bool = true,
        actions: [String] = []
    ) {
        self.enabled = enabled
        self.channelId = channelId
        self.channelName = channelName
        self.notificationTitle = notificationTitle
        self.notificationText = notificationText
        self.notificationColor = notificationColor
        self.notificationSmallIcon = notificationSmallIcon
        self.notificationLargeIcon = notificationLargeIcon
        self.notificationPriority = notificationPriority
        self.notificationOngoing = notificationOngoing
        self.actions = actions
    }

    public func toMap() -> [String: Any] {
        var map: [String: Any] = [
            "enabled": enabled,
            "channelId": channelId,
            "channelName": channelName,
            "notificationTitle": notificationTitle,
            "notificationText": notificationText,
            "notificationPriority": notificationPriority.rawValue,
            "notificationOngoing": notificationOngoing,
            "actions": actions,
        ]
        if let color = notificationColor { map["notificationColor"] = color }
        if let small = notificationSmallIcon { map["notificationSmallIcon"] = small }
        if let large = notificationLargeIcon { map["notificationLargeIcon"] = large }
        return map
    }

    /// Creates a ``TraceletForegroundServiceConfig`` from a dictionary.
    public static func fromMap(_ map: [String: Any]) -> TraceletForegroundServiceConfig {
        TraceletForegroundServiceConfig(
            enabled: map["enabled"] as? Bool ?? true,
            channelId: map["channelId"] as? String ?? "tracelet_channel",
            channelName: map["channelName"] as? String ?? "Tracelet",
            notificationTitle: map["notificationTitle"] as? String ?? "Tracelet",
            notificationText: map["notificationText"] as? String ?? "Tracking location in background",
            notificationColor: map["notificationColor"] as? String,
            notificationSmallIcon: map["notificationSmallIcon"] as? String,
            notificationLargeIcon: map["notificationLargeIcon"] as? String,
            notificationPriority: TraceletNotificationPriority(rawValue: map["notificationPriority"] as? Int ?? 0) ?? .default,
            notificationOngoing: map["notificationOngoing"] as? Bool ?? true,
            actions: map["actions"] as? [String] ?? []
        )
    }
}

// MARK: - HttpConfig

/// HTTP synchronization settings.
///
/// ```swift
/// TraceletHttpConfig(
///     url: "https://api.example.com/locations",
///     batchSync: true,
///     maxBatchSize: 100,
///     headers: ["Authorization": "Bearer token"]
/// )
/// ```
public struct TraceletHttpConfig {
    public let url: String?
    public let method: TraceletHttpMethod
    public let headers: [String: String]
    public let httpRootProperty: String
    public let batchSync: Bool
    public let maxBatchSize: Int
    public let autoSync: Bool
    public let autoSyncThreshold: Int
    public let httpTimeout: Int
    public let params: [String: Any]
    public let locationsOrderDirection: TraceletLocationOrder
    public let extras: [String: Any]
    public let disableAutoSyncOnCellular: Bool
    public let maxRetries: Int
    public let retryBackoffBase: Int
    public let retryBackoffCap: Int
    public let enableDeltaCompression: Bool
    public let deltaCoordinatePrecision: Int
    public let sslPinningCertificates: [String]
    public let sslPinningFingerprints: [String]

    public init(
        url: String? = nil,
        method: TraceletHttpMethod = .post,
        headers: [String: String] = [:],
        httpRootProperty: String = "location",
        batchSync: Bool = false,
        maxBatchSize: Int = 250,
        autoSync: Bool = true,
        autoSyncThreshold: Int = 0,
        httpTimeout: Int = 60000,
        params: [String: Any] = [:],
        locationsOrderDirection: TraceletLocationOrder = .asc,
        extras: [String: Any] = [:],
        disableAutoSyncOnCellular: Bool = false,
        maxRetries: Int = 10,
        retryBackoffBase: Int = 1000,
        retryBackoffCap: Int = 300000,
        enableDeltaCompression: Bool = false,
        deltaCoordinatePrecision: Int = 6,
        sslPinningCertificates: [String] = [],
        sslPinningFingerprints: [String] = []
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.httpRootProperty = httpRootProperty
        self.batchSync = batchSync
        self.maxBatchSize = maxBatchSize
        self.autoSync = autoSync
        self.autoSyncThreshold = autoSyncThreshold
        self.httpTimeout = httpTimeout
        self.params = params
        self.locationsOrderDirection = locationsOrderDirection
        self.extras = extras
        self.disableAutoSyncOnCellular = disableAutoSyncOnCellular
        self.maxRetries = maxRetries
        self.retryBackoffBase = retryBackoffBase
        self.retryBackoffCap = retryBackoffCap
        self.enableDeltaCompression = enableDeltaCompression
        self.deltaCoordinatePrecision = deltaCoordinatePrecision
        self.sslPinningCertificates = sslPinningCertificates
        self.sslPinningFingerprints = sslPinningFingerprints
    }

    public func toMap() -> [String: Any] {
        var map: [String: Any] = [
            "method": method.rawValue,
            "headers": headers,
            "httpRootProperty": httpRootProperty,
            "batchSync": batchSync,
            "maxBatchSize": maxBatchSize,
            "autoSync": autoSync,
            "autoSyncThreshold": autoSyncThreshold,
            "httpTimeout": httpTimeout,
            "params": params,
            "locationsOrderDirection": locationsOrderDirection.rawValue,
            "httpExtras": extras,
            "disableAutoSyncOnCellular": disableAutoSyncOnCellular,
            "maxRetries": maxRetries,
            "retryBackoffBase": retryBackoffBase,
            "retryBackoffCap": retryBackoffCap,
            "enableDeltaCompression": enableDeltaCompression,
            "deltaCoordinatePrecision": deltaCoordinatePrecision,
            "sslPinningCertificates": sslPinningCertificates,
            "sslPinningFingerprints": sslPinningFingerprints,
        ]
        if let url = url { map["url"] = url }
        return map
    }

    /// Creates a ``TraceletHttpConfig`` from a dictionary.
    public static func fromMap(_ map: [String: Any]) -> TraceletHttpConfig {
        TraceletHttpConfig(
            url: map["url"] as? String,
            method: TraceletHttpMethod(rawValue: map["method"] as? Int ?? 0) ?? .post,
            headers: map["headers"] as? [String: String] ?? [:],
            httpRootProperty: map["httpRootProperty"] as? String ?? "location",
            batchSync: map["batchSync"] as? Bool ?? false,
            maxBatchSize: map["maxBatchSize"] as? Int ?? 250,
            autoSync: map["autoSync"] as? Bool ?? true,
            autoSyncThreshold: map["autoSyncThreshold"] as? Int ?? 0,
            httpTimeout: map["httpTimeout"] as? Int ?? 60000,
            params: map["params"] as? [String: Any] ?? [:],
            locationsOrderDirection: TraceletLocationOrder(rawValue: map["locationsOrderDirection"] as? Int ?? 0) ?? .asc,
            extras: map["httpExtras"] as? [String: Any] ?? [:],
            disableAutoSyncOnCellular: map["disableAutoSyncOnCellular"] as? Bool ?? false,
            maxRetries: map["maxRetries"] as? Int ?? 10,
            retryBackoffBase: map["retryBackoffBase"] as? Int ?? 1000,
            retryBackoffCap: map["retryBackoffCap"] as? Int ?? 300000,
            enableDeltaCompression: map["enableDeltaCompression"] as? Bool ?? false,
            deltaCoordinatePrecision: map["deltaCoordinatePrecision"] as? Int ?? 6,
            sslPinningCertificates: map["sslPinningCertificates"] as? [String] ?? [],
            sslPinningFingerprints: map["sslPinningFingerprints"] as? [String] ?? []
        )
    }
}

// MARK: - LoggerConfig

/// Logging and debug sound settings.
///
/// ```swift
/// TraceletLoggerConfig(logLevel: .verbose, debug: true)
/// ```
public struct TraceletLoggerConfig {
    public let logLevel: TraceletLogLevel
    public let logMaxDays: Int
    public let debug: Bool

    public init(
        logLevel: TraceletLogLevel = .info,
        logMaxDays: Int = 3,
        debug: Bool = false
    ) {
        self.logLevel = logLevel
        self.logMaxDays = logMaxDays
        self.debug = debug
    }

    public func toMap() -> [String: Any] {
        [
            "logLevel": logLevel.rawValue,
            "logMaxDays": logMaxDays,
            "debug": debug,
        ]
    }

    /// Creates a ``TraceletLoggerConfig`` from a dictionary.
    public static func fromMap(_ map: [String: Any]) -> TraceletLoggerConfig {
        TraceletLoggerConfig(
            logLevel: TraceletLogLevel(rawValue: map["logLevel"] as? Int ?? 2) ?? .info,
            logMaxDays: map["logMaxDays"] as? Int ?? 3,
            debug: map["debug"] as? Bool ?? false
        )
    }
}

// MARK: - MotionConfig

/// Motion detection sensitivity settings.
///
/// ```swift
/// TraceletMotionConfig(
///     stopTimeout: 5,
///     shakeThreshold: 2.5,
///     stillThreshold: 0.4
/// )
/// ```
public struct TraceletMotionConfig {
    public let stopTimeout: Int
    public let motionTriggerDelay: Int
    public let disableMotionActivityUpdates: Bool
    public let isMoving: Bool
    public let activityRecognitionInterval: Int
    public let minimumActivityRecognitionConfidence: Int
    public let disableStopDetection: Bool
    public let stopDetectionDelay: Int
    public let stopOnStationary: Bool
    public let triggerActivities: Set<TraceletMotionActivityType>
    public let shakeThreshold: Double
    public let stillThreshold: Double
    public let stillSampleCount: Int

    public init(
        stopTimeout: Int = 5,
        motionTriggerDelay: Int = 0,
        disableMotionActivityUpdates: Bool = false,
        isMoving: Bool = false,
        activityRecognitionInterval: Int = 10000,
        minimumActivityRecognitionConfidence: Int = 75,
        disableStopDetection: Bool = false,
        stopDetectionDelay: Int = 0,
        stopOnStationary: Bool = false,
        triggerActivities: Set<TraceletMotionActivityType> = [],
        shakeThreshold: Double = 2.5,
        stillThreshold: Double = 0.4,
        stillSampleCount: Int = 25
    ) {
        self.stopTimeout = stopTimeout
        self.motionTriggerDelay = motionTriggerDelay
        self.disableMotionActivityUpdates = disableMotionActivityUpdates
        self.isMoving = isMoving
        self.activityRecognitionInterval = activityRecognitionInterval
        self.minimumActivityRecognitionConfidence = minimumActivityRecognitionConfidence
        self.disableStopDetection = disableStopDetection
        self.stopDetectionDelay = stopDetectionDelay
        self.stopOnStationary = stopOnStationary
        self.triggerActivities = triggerActivities
        self.shakeThreshold = shakeThreshold
        self.stillThreshold = stillThreshold
        self.stillSampleCount = stillSampleCount
    }

    public func toMap() -> [String: Any] {
        [
            "stopTimeout": stopTimeout,
            "motionTriggerDelay": motionTriggerDelay,
            "disableMotionActivityUpdates": disableMotionActivityUpdates,
            "isMoving": isMoving,
            "activityRecognitionInterval": activityRecognitionInterval,
            "minimumActivityRecognitionConfidence": minimumActivityRecognitionConfidence,
            "disableStopDetection": disableStopDetection,
            "stopDetectionDelay": stopDetectionDelay,
            "stopOnStationary": stopOnStationary,
            "triggerActivities": triggerActivities.map { $0.rawValue },
            "shakeThreshold": shakeThreshold,
            "stillThreshold": stillThreshold,
            "stillSampleCount": stillSampleCount,
        ]
    }

    /// Creates a ``TraceletMotionConfig`` from a dictionary.
    public static func fromMap(_ map: [String: Any]) -> TraceletMotionConfig {
        TraceletMotionConfig(
            stopTimeout: map["stopTimeout"] as? Int ?? 5,
            motionTriggerDelay: map["motionTriggerDelay"] as? Int ?? 0,
            disableMotionActivityUpdates: map["disableMotionActivityUpdates"] as? Bool ?? false,
            isMoving: map["isMoving"] as? Bool ?? false,
            activityRecognitionInterval: map["activityRecognitionInterval"] as? Int ?? 10000,
            minimumActivityRecognitionConfidence: map["minimumActivityRecognitionConfidence"] as? Int ?? 75,
            disableStopDetection: map["disableStopDetection"] as? Bool ?? false,
            stopDetectionDelay: map["stopDetectionDelay"] as? Int ?? 0,
            stopOnStationary: map["stopOnStationary"] as? Bool ?? false,
            triggerActivities: Set((map["triggerActivities"] as? [String] ?? []).compactMap { TraceletMotionActivityType(rawValue: $0) }),
            shakeThreshold: (map["shakeThreshold"] as? NSNumber)?.doubleValue ?? 2.5,
            stillThreshold: (map["stillThreshold"] as? NSNumber)?.doubleValue ?? 0.4,
            stillSampleCount: map["stillSampleCount"] as? Int ?? 25
        )
    }
}

// MARK: - GeofenceConfig

/// Geofencing settings.
///
/// ```swift
/// TraceletGeofenceConfig(
///     geofenceProximityRadius: 2000,
///     geofenceInitialTriggerEntry: true
/// )
/// ```
public struct TraceletGeofenceConfig {
    public let geofenceProximityRadius: Int
    public let geofenceInitialTriggerEntry: Bool
    public let geofenceModeKnockOut: Bool

    public init(
        geofenceProximityRadius: Int = 1000,
        geofenceInitialTriggerEntry: Bool = true,
        geofenceModeKnockOut: Bool = false
    ) {
        self.geofenceProximityRadius = geofenceProximityRadius
        self.geofenceInitialTriggerEntry = geofenceInitialTriggerEntry
        self.geofenceModeKnockOut = geofenceModeKnockOut
    }

    public func toMap() -> [String: Any] {
        [
            "geofenceProximityRadius": geofenceProximityRadius,
            "geofenceInitialTriggerEntry": geofenceInitialTriggerEntry,
            "geofenceModeKnockOut": geofenceModeKnockOut,
        ]
    }

    /// Creates a ``TraceletGeofenceConfig`` from a dictionary.
    public static func fromMap(_ map: [String: Any]) -> TraceletGeofenceConfig {
        TraceletGeofenceConfig(
            geofenceProximityRadius: map["geofenceProximityRadius"] as? Int ?? 1000,
            geofenceInitialTriggerEntry: map["geofenceInitialTriggerEntry"] as? Bool ?? true,
            geofenceModeKnockOut: map["geofenceModeKnockOut"] as? Bool ?? false
        )
    }
}

// MARK: - PersistenceConfig

/// Database persistence and retention settings.
///
/// ```swift
/// TraceletPersistenceConfig(
///     maxDaysToPersist: 14,
///     maxRecordsToPersist: 5000
/// )
/// ```
public struct TraceletPersistenceConfig {
    public let persistMode: TraceletPersistMode
    public let maxDaysToPersist: Int
    public let maxRecordsToPersist: Int
    public let locationTemplate: String?
    public let geofenceTemplate: String?
    public let disableProviderChangeRecord: Bool
    public let extras: [String: Any]

    public init(
        persistMode: TraceletPersistMode = .all,
        maxDaysToPersist: Int = -1,
        maxRecordsToPersist: Int = -1,
        locationTemplate: String? = nil,
        geofenceTemplate: String? = nil,
        disableProviderChangeRecord: Bool = false,
        extras: [String: Any] = [:]
    ) {
        self.persistMode = persistMode
        self.maxDaysToPersist = maxDaysToPersist
        self.maxRecordsToPersist = maxRecordsToPersist
        self.locationTemplate = locationTemplate
        self.geofenceTemplate = geofenceTemplate
        self.disableProviderChangeRecord = disableProviderChangeRecord
        self.extras = extras
    }

    public func toMap() -> [String: Any] {
        var map: [String: Any] = [
            "persistMode": persistMode.rawValue,
            "maxDaysToPersist": maxDaysToPersist,
            "maxRecordsToPersist": maxRecordsToPersist,
            "disableProviderChangeRecord": disableProviderChangeRecord,
            "persistenceExtras": extras,
        ]
        if let tpl = locationTemplate { map["locationTemplate"] = tpl }
        if let tpl = geofenceTemplate { map["geofenceTemplate"] = tpl }
        return map
    }

    /// Creates a ``TraceletPersistenceConfig`` from a dictionary.
    public static func fromMap(_ map: [String: Any]) -> TraceletPersistenceConfig {
        TraceletPersistenceConfig(
            persistMode: TraceletPersistMode(rawValue: map["persistMode"] as? Int ?? 0) ?? .all,
            maxDaysToPersist: map["maxDaysToPersist"] as? Int ?? -1,
            maxRecordsToPersist: map["maxRecordsToPersist"] as? Int ?? -1,
            locationTemplate: map["locationTemplate"] as? String,
            geofenceTemplate: map["geofenceTemplate"] as? String,
            disableProviderChangeRecord: map["disableProviderChangeRecord"] as? Bool ?? false,
            extras: map["persistenceExtras"] as? [String: Any] ?? [:]
        )
    }
}

// MARK: - AuditConfig

/// Tamper-proof audit trail settings (Enterprise).
///
/// ```swift
/// TraceletAuditConfig(enabled: true, hashAlgorithm: .sha256)
/// ```
public struct TraceletAuditConfig {
    public let enabled: Bool
    public let hashAlgorithm: TraceletHashAlgorithm

    public init(enabled: Bool = false, hashAlgorithm: TraceletHashAlgorithm = .sha256) {
        self.enabled = enabled
        self.hashAlgorithm = hashAlgorithm
    }

    public func toMap() -> [String: Any] {
        ["enabled": enabled, "hashAlgorithm": hashAlgorithm.rawValue]
    }

    /// Creates a ``TraceletAuditConfig`` from a dictionary.
    public static func fromMap(_ map: [String: Any]) -> TraceletAuditConfig {
        TraceletAuditConfig(
            enabled: map["enabled"] as? Bool ?? false,
            hashAlgorithm: TraceletHashAlgorithm(rawValue: map["hashAlgorithm"] as? Int ?? 0) ?? .sha256
        )
    }
}

// MARK: - PrivacyZoneConfig

/// Privacy zone controls (Enterprise).
///
/// ```swift
/// TraceletPrivacyZoneConfig(enabled: true)
/// ```
public struct TraceletPrivacyZoneConfig {
    public let enabled: Bool

    public init(enabled: Bool = false) {
        self.enabled = enabled
    }

    public func toMap() -> [String: Any] {
        ["enabled": enabled]
    }

    /// Creates a ``TraceletPrivacyZoneConfig`` from a dictionary.
    public static func fromMap(_ map: [String: Any]) -> TraceletPrivacyZoneConfig {
        TraceletPrivacyZoneConfig(enabled: map["enabled"] as? Bool ?? false)
    }
}

// MARK: - SecurityConfig

/// At-rest database encryption settings (Enterprise).
///
/// ```swift
/// TraceletSecurityConfig(encryptDatabase: true)
/// ```
public struct TraceletSecurityConfig {
    public let encryptDatabase: Bool

    public init(encryptDatabase: Bool = false) {
        self.encryptDatabase = encryptDatabase
    }

    public func toMap() -> [String: Any] {
        ["encryptDatabase": encryptDatabase]
    }

    /// Creates a ``TraceletSecurityConfig`` from a dictionary.
    public static func fromMap(_ map: [String: Any]) -> TraceletSecurityConfig {
        TraceletSecurityConfig(encryptDatabase: map["encryptDatabase"] as? Bool ?? false)
    }
}

// MARK: - AttestationConfig

/// Device integrity attestation settings (Enterprise).
///
/// ```swift
/// TraceletAttestationConfig(enabled: true, refreshInterval: 3600)
/// ```
public struct TraceletAttestationConfig {
    public let enabled: Bool
    public let refreshInterval: Int

    public init(enabled: Bool = false, refreshInterval: Int = 3600) {
        self.enabled = enabled
        self.refreshInterval = refreshInterval
    }

    public func toMap() -> [String: Any] {
        ["enabled": enabled, "refreshInterval": refreshInterval]
    }

    /// Creates a ``TraceletAttestationConfig`` from a dictionary.
    public static func fromMap(_ map: [String: Any]) -> TraceletAttestationConfig {
        TraceletAttestationConfig(
            enabled: map["enabled"] as? Bool ?? false,
            refreshInterval: map["refreshInterval"] as? Int ?? 3600
        )
    }
}
