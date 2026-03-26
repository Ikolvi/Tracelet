import Foundation

// =============================================================================
// Objective-C bridging wrappers for TraceletConfig types.
//
// Swift structs and non-Int-raw-value enums cannot be exposed to Objective-C.
// These @objc classes mirror the Swift struct API, allowing native iOS developers
// using Objective-C to build typed configs with the same pattern:
//
//   TraceletConfigObjC *config = [[TraceletConfigObjC alloc]
//       initWithGeo:[[TraceletGeoConfigObjC alloc] initWithDesiredAccuracy:0
//                                                          distanceFilter:10.0]
//                app:[[TraceletAppConfigObjC alloc] initWithStopOnTerminate:NO
//                                                           startOnBoot:YES]];
//
//   [sdk readyWithConfig:[config toMap]];
// =============================================================================

// MARK: - TraceletConfigObjC

/// Objective-C wrapper for ``TraceletConfig``.
@objc(TraceletConfig_ObjC)
@objcMembers
public final class TraceletConfigObjC: NSObject {
    public let geo: TraceletGeoConfigObjC
    public let app: TraceletAppConfigObjC
    public let http: TraceletHttpConfigObjC
    public let logger: TraceletLoggerConfigObjC
    public let motion: TraceletMotionConfigObjC
    public let geofence: TraceletGeofenceConfigObjC
    public let persistence: TraceletPersistenceConfigObjC
    public let audit: TraceletAuditConfigObjC
    public let privacyZone: TraceletPrivacyZoneConfigObjC
    public let security: TraceletSecurityConfigObjC
    public let attestation: TraceletAttestationConfigObjC

    public init(
        geo: TraceletGeoConfigObjC = TraceletGeoConfigObjC(),
        app: TraceletAppConfigObjC = TraceletAppConfigObjC(),
        http: TraceletHttpConfigObjC = TraceletHttpConfigObjC(),
        logger: TraceletLoggerConfigObjC = TraceletLoggerConfigObjC(),
        motion: TraceletMotionConfigObjC = TraceletMotionConfigObjC(),
        geofence: TraceletGeofenceConfigObjC = TraceletGeofenceConfigObjC(),
        persistence: TraceletPersistenceConfigObjC = TraceletPersistenceConfigObjC(),
        audit: TraceletAuditConfigObjC = TraceletAuditConfigObjC(),
        privacyZone: TraceletPrivacyZoneConfigObjC = TraceletPrivacyZoneConfigObjC(),
        security: TraceletSecurityConfigObjC = TraceletSecurityConfigObjC(),
        attestation: TraceletAttestationConfigObjC = TraceletAttestationConfigObjC()
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

    /// Convert to dictionary format expected by ``ConfigManager``.
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

    /// Convert to the Swift struct equivalent.
    public func toSwift() -> TraceletConfig {
        TraceletConfig(
            geo: geo.toSwift(),
            app: app.toSwift(),
            http: http.toSwift(),
            logger: logger.toSwift(),
            motion: motion.toSwift(),
            geofence: geofence.toSwift(),
            persistence: persistence.toSwift(),
            audit: audit.toSwift(),
            privacyZone: privacyZone.toSwift(),
            security: security.toSwift(),
            attestation: attestation.toSwift()
        )
    }

    @objc public class func fromMap(_ map: [String: Any]) -> TraceletConfigObjC {
        TraceletConfigObjC(
            geo: TraceletGeoConfigObjC.fromMap(map["geo"] as? [String: Any] ?? [:]),
            app: TraceletAppConfigObjC.fromMap(map["app"] as? [String: Any] ?? [:]),
            http: TraceletHttpConfigObjC.fromMap(map["http"] as? [String: Any] ?? [:]),
            logger: TraceletLoggerConfigObjC.fromMap(map["logger"] as? [String: Any] ?? [:]),
            motion: TraceletMotionConfigObjC.fromMap(map["motion"] as? [String: Any] ?? [:]),
            geofence: TraceletGeofenceConfigObjC.fromMap(map["geofence"] as? [String: Any] ?? [:]),
            persistence: TraceletPersistenceConfigObjC.fromMap(map["persistence"] as? [String: Any] ?? [:]),
            audit: TraceletAuditConfigObjC.fromMap(map["audit"] as? [String: Any] ?? [:]),
            privacyZone: TraceletPrivacyZoneConfigObjC.fromMap(map["privacyZone"] as? [String: Any] ?? [:]),
            security: TraceletSecurityConfigObjC.fromMap(map["security"] as? [String: Any] ?? [:]),
            attestation: TraceletAttestationConfigObjC.fromMap(map["attestation"] as? [String: Any] ?? [:])
        )
    }
}

// MARK: - TraceletGeoConfigObjC

/// Objective-C wrapper for ``TraceletGeoConfig``.
@objc(TraceletGeoConfig_ObjC)
@objcMembers
public final class TraceletGeoConfigObjC: NSObject {
    /// 0 = high, 1 = medium, 2 = low
    public let desiredAccuracy: Int
    public let distanceFilter: Double
    public let locationUpdateInterval: Int
    public let fastestLocationUpdateInterval: Int
    public let stationaryRadius: Double
    public let locationTimeout: Int
    /// 0 = other, 1 = automotiveNavigation, 2 = fitness, 3 = otherNavigation, 4 = airborne
    public let activityType: Int
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
    /// "Always" or "WhenInUse"
    public let locationAuthorizationRequest: String
    public let disableLocationAuthorizationAlert: Bool
    public let enableTimestampMeta: Bool
    public let enableAdaptiveMode: Bool
    public let periodicLocationInterval: Int
    /// 0 = high, 1 = medium, 2 = low
    public let periodicDesiredAccuracy: Int
    public let periodicUseForegroundService: Bool
    public let periodicUseExactAlarms: Bool
    public let enableSparseUpdates: Bool
    public let sparseDistanceThreshold: Double
    public let sparseMaxIdleSeconds: Int
    public let enableDeadReckoning: Bool
    public let deadReckoningActivationDelay: Int
    public let deadReckoningMaxDuration: Int
    public let batteryBudgetPerHour: Double
    public let filter: TraceletLocationFilterObjC?

    public init(
        desiredAccuracy: Int = 0,
        distanceFilter: Double = 10.0,
        locationUpdateInterval: Int = 1000,
        fastestLocationUpdateInterval: Int = 500,
        stationaryRadius: Double = 25.0,
        locationTimeout: Int = 60,
        activityType: Int = 0,
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
        locationAuthorizationRequest: String = "Always",
        disableLocationAuthorizationAlert: Bool = false,
        enableTimestampMeta: Bool = false,
        enableAdaptiveMode: Bool = false,
        periodicLocationInterval: Int = 900,
        periodicDesiredAccuracy: Int = 1,
        periodicUseForegroundService: Bool = false,
        periodicUseExactAlarms: Bool = false,
        enableSparseUpdates: Bool = false,
        sparseDistanceThreshold: Double = 50.0,
        sparseMaxIdleSeconds: Int = 300,
        enableDeadReckoning: Bool = false,
        deadReckoningActivationDelay: Int = 10,
        deadReckoningMaxDuration: Int = 120,
        batteryBudgetPerHour: Double = 0.0,
        filter: TraceletLocationFilterObjC? = nil
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
            "desiredAccuracy": desiredAccuracy,
            "distanceFilter": distanceFilter,
            "locationUpdateInterval": locationUpdateInterval,
            "fastestLocationUpdateInterval": fastestLocationUpdateInterval,
            "stationaryRadius": stationaryRadius,
            "locationTimeout": locationTimeout,
            "activityType": activityType,
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
            "locationAuthorizationRequest": locationAuthorizationRequest,
            "disableLocationAuthorizationAlert": disableLocationAuthorizationAlert,
            "enableTimestampMeta": enableTimestampMeta,
            "enableAdaptiveMode": enableAdaptiveMode,
            "periodicLocationInterval": periodicLocationInterval,
            "periodicDesiredAccuracy": periodicDesiredAccuracy,
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
        if let f = filter { map["filter"] = f.toMap() }
        return map
    }

    public func toSwift() -> TraceletGeoConfig {
        TraceletGeoConfig(
            desiredAccuracy: TraceletDesiredAccuracy(rawValue: desiredAccuracy) ?? .high,
            distanceFilter: distanceFilter,
            locationUpdateInterval: locationUpdateInterval,
            fastestLocationUpdateInterval: fastestLocationUpdateInterval,
            stationaryRadius: stationaryRadius,
            locationTimeout: locationTimeout,
            activityType: TraceletActivityType(rawValue: activityType) ?? .other,
            disableElasticity: disableElasticity,
            elasticityMultiplier: elasticityMultiplier,
            stopAfterElapsedMinutes: stopAfterElapsedMinutes,
            deferTime: deferTime,
            allowIdenticalLocations: allowIdenticalLocations,
            geofenceModeHighAccuracy: geofenceModeHighAccuracy,
            maxMonitoredGeofences: maxMonitoredGeofences,
            useSignificantChangesOnly: useSignificantChangesOnly,
            showsBackgroundLocationIndicator: showsBackgroundLocationIndicator,
            pausesLocationUpdatesAutomatically: pausesLocationUpdatesAutomatically,
            locationAuthorizationRequest: locationAuthorizationRequest == "Always" ? .always : .whenInUse,
            disableLocationAuthorizationAlert: disableLocationAuthorizationAlert,
            enableTimestampMeta: enableTimestampMeta,
            enableAdaptiveMode: enableAdaptiveMode,
            periodicLocationInterval: periodicLocationInterval,
            periodicDesiredAccuracy: TraceletDesiredAccuracy(rawValue: periodicDesiredAccuracy) ?? .medium,
            periodicUseForegroundService: periodicUseForegroundService,
            periodicUseExactAlarms: periodicUseExactAlarms,
            enableSparseUpdates: enableSparseUpdates,
            sparseDistanceThreshold: sparseDistanceThreshold,
            sparseMaxIdleSeconds: sparseMaxIdleSeconds,
            enableDeadReckoning: enableDeadReckoning,
            deadReckoningActivationDelay: deadReckoningActivationDelay,
            deadReckoningMaxDuration: deadReckoningMaxDuration,
            batteryBudgetPerHour: batteryBudgetPerHour,
            filter: filter?.toSwift()
        )
    }

    @objc public class func fromMap(_ map: [String: Any]) -> TraceletGeoConfigObjC {
        var filterObjC: TraceletLocationFilterObjC? = nil
        if let filterMap = map["filter"] as? [String: Any] {
            filterObjC = TraceletLocationFilterObjC.fromMap(filterMap)
        }
        return TraceletGeoConfigObjC(
            desiredAccuracy: map["desiredAccuracy"] as? Int ?? 0,
            distanceFilter: map["distanceFilter"] as? Double ?? 10.0,
            locationUpdateInterval: map["locationUpdateInterval"] as? Int ?? 1000,
            fastestLocationUpdateInterval: map["fastestLocationUpdateInterval"] as? Int ?? 500,
            stationaryRadius: map["stationaryRadius"] as? Double ?? 25.0,
            locationTimeout: map["locationTimeout"] as? Int ?? 60,
            activityType: map["activityType"] as? Int ?? 0,
            disableElasticity: map["disableElasticity"] as? Bool ?? false,
            elasticityMultiplier: map["elasticityMultiplier"] as? Double ?? 1.0,
            stopAfterElapsedMinutes: map["stopAfterElapsedMinutes"] as? Int ?? -1,
            deferTime: map["deferTime"] as? Int ?? 0,
            allowIdenticalLocations: map["allowIdenticalLocations"] as? Bool ?? false,
            geofenceModeHighAccuracy: map["geofenceModeHighAccuracy"] as? Bool ?? false,
            maxMonitoredGeofences: map["maxMonitoredGeofences"] as? Int ?? -1,
            useSignificantChangesOnly: map["useSignificantChangesOnly"] as? Bool ?? false,
            showsBackgroundLocationIndicator: map["showsBackgroundLocationIndicator"] as? Bool ?? false,
            pausesLocationUpdatesAutomatically: map["pausesLocationUpdatesAutomatically"] as? Bool ?? false,
            locationAuthorizationRequest: map["locationAuthorizationRequest"] as? String ?? "Always",
            disableLocationAuthorizationAlert: map["disableLocationAuthorizationAlert"] as? Bool ?? false,
            enableTimestampMeta: map["enableTimestampMeta"] as? Bool ?? false,
            enableAdaptiveMode: map["enableAdaptiveMode"] as? Bool ?? false,
            periodicLocationInterval: map["periodicLocationInterval"] as? Int ?? 900,
            periodicDesiredAccuracy: map["periodicDesiredAccuracy"] as? Int ?? 1,
            periodicUseForegroundService: map["periodicUseForegroundService"] as? Bool ?? false,
            periodicUseExactAlarms: map["periodicUseExactAlarms"] as? Bool ?? false,
            enableSparseUpdates: map["enableSparseUpdates"] as? Bool ?? false,
            sparseDistanceThreshold: map["sparseDistanceThreshold"] as? Double ?? 50.0,
            sparseMaxIdleSeconds: map["sparseMaxIdleSeconds"] as? Int ?? 300,
            enableDeadReckoning: map["enableDeadReckoning"] as? Bool ?? false,
            deadReckoningActivationDelay: map["deadReckoningActivationDelay"] as? Int ?? 10,
            deadReckoningMaxDuration: map["deadReckoningMaxDuration"] as? Int ?? 120,
            batteryBudgetPerHour: map["batteryBudgetPerHour"] as? Double ?? 0.0,
            filter: filterObjC
        )
    }
}

// MARK: - TraceletLocationFilterObjC

/// Objective-C wrapper for ``TraceletLocationFilter``.
@objc(TraceletLocationFilter_ObjC)
@objcMembers
public final class TraceletLocationFilterObjC: NSObject {
    /// 0 = adjust, 1 = ignore, 2 = discard
    public let policy: Int
    public let maxImpliedSpeed: Int
    public let odometerAccuracyThreshold: Int
    public let trackingAccuracyThreshold: Int
    public let useKalmanFilter: Bool
    public let rejectMockLocations: Bool
    /// 0 = disabled, 1 = basic, 2 = heuristic
    public let mockDetectionLevel: Int

    public init(
        policy: Int = 0,
        maxImpliedSpeed: Int = 0,
        odometerAccuracyThreshold: Int = 0,
        trackingAccuracyThreshold: Int = 0,
        useKalmanFilter: Bool = false,
        rejectMockLocations: Bool = false,
        mockDetectionLevel: Int = 0
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
            "policy": policy,
            "maxImpliedSpeed": maxImpliedSpeed,
            "odometerAccuracyThreshold": odometerAccuracyThreshold,
            "trackingAccuracyThreshold": trackingAccuracyThreshold,
            "useKalmanFilter": useKalmanFilter,
            "rejectMockLocations": rejectMockLocations,
            "mockDetectionLevel": mockDetectionLevel,
        ]
    }

    public func toSwift() -> TraceletLocationFilter {
        TraceletLocationFilter(
            policy: TraceletLocationFilterPolicy(rawValue: policy) ?? .adjust,
            maxImpliedSpeed: maxImpliedSpeed,
            odometerAccuracyThreshold: odometerAccuracyThreshold,
            trackingAccuracyThreshold: trackingAccuracyThreshold,
            useKalmanFilter: useKalmanFilter,
            rejectMockLocations: rejectMockLocations,
            mockDetectionLevel: TraceletMockDetectionLevel(rawValue: mockDetectionLevel) ?? .disabled
        )
    }

    @objc public class func fromMap(_ map: [String: Any]) -> TraceletLocationFilterObjC {
        TraceletLocationFilterObjC(
            policy: map["policy"] as? Int ?? 0,
            maxImpliedSpeed: map["maxImpliedSpeed"] as? Int ?? 0,
            odometerAccuracyThreshold: map["odometerAccuracyThreshold"] as? Int ?? 0,
            trackingAccuracyThreshold: map["trackingAccuracyThreshold"] as? Int ?? 0,
            useKalmanFilter: map["useKalmanFilter"] as? Bool ?? false,
            rejectMockLocations: map["rejectMockLocations"] as? Bool ?? false,
            mockDetectionLevel: map["mockDetectionLevel"] as? Int ?? 0
        )
    }
}

// MARK: - TraceletAppConfigObjC

/// Objective-C wrapper for ``TraceletAppConfig``.
@objc(TraceletAppConfig_ObjC)
@objcMembers
public final class TraceletAppConfigObjC: NSObject {
    public let stopOnTerminate: Bool
    public let startOnBoot: Bool
    public let heartbeatInterval: Int
    public let schedule: [String]
    public let scheduleUseAlarmManager: Bool
    public let preventSuspend: Bool
    public let foregroundService: TraceletForegroundServiceConfigObjC
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
        foregroundService: TraceletForegroundServiceConfigObjC = TraceletForegroundServiceConfigObjC(),
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
        if let url = remoteConfigUrl { map["remoteConfigUrl"] = url }
        return map
    }

    public func toSwift() -> TraceletAppConfig {
        TraceletAppConfig(
            stopOnTerminate: stopOnTerminate,
            startOnBoot: startOnBoot,
            heartbeatInterval: heartbeatInterval,
            schedule: schedule,
            scheduleUseAlarmManager: scheduleUseAlarmManager,
            preventSuspend: preventSuspend,
            foregroundService: foregroundService.toSwift(),
            remoteConfigUrl: remoteConfigUrl,
            remoteConfigHeaders: remoteConfigHeaders,
            remoteConfigTimeout: remoteConfigTimeout,
            remoteConfigRefreshInterval: remoteConfigRefreshInterval
        )
    }

    @objc public class func fromMap(_ map: [String: Any]) -> TraceletAppConfigObjC {
        let fgMap = map["foregroundService"] as? [String: Any] ?? [:]
        return TraceletAppConfigObjC(
            stopOnTerminate: map["stopOnTerminate"] as? Bool ?? true,
            startOnBoot: map["startOnBoot"] as? Bool ?? false,
            heartbeatInterval: map["heartbeatInterval"] as? Int ?? 60,
            schedule: map["schedule"] as? [String] ?? [],
            scheduleUseAlarmManager: map["scheduleUseAlarmManager"] as? Bool ?? false,
            preventSuspend: map["preventSuspend"] as? Bool ?? false,
            foregroundService: TraceletForegroundServiceConfigObjC.fromMap(fgMap),
            remoteConfigUrl: map["remoteConfigUrl"] as? String,
            remoteConfigHeaders: map["remoteConfigHeaders"] as? [String: String] ?? [:],
            remoteConfigTimeout: map["remoteConfigTimeout"] as? Int ?? 10000,
            remoteConfigRefreshInterval: map["remoteConfigRefreshInterval"] as? Int ?? 0
        )
    }
}

// MARK: - TraceletForegroundServiceConfigObjC

/// Objective-C wrapper for ``TraceletForegroundServiceConfig``.
@objc(TraceletForegroundServiceConfig_ObjC)
@objcMembers
public final class TraceletForegroundServiceConfigObjC: NSObject {
    public let enabled: Bool
    public let channelId: String
    public let channelName: String
    public let notificationTitle: String
    public let notificationText: String
    public let notificationColor: String?
    public let notificationSmallIcon: String?
    public let notificationLargeIcon: String?
    /// -2 = min, -1 = low, 0 = default, 1 = high, 2 = max
    public let notificationPriority: Int
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
        notificationPriority: Int = 0,
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
            "notificationPriority": notificationPriority,
            "notificationOngoing": notificationOngoing,
            "actions": actions,
        ]
        if let c = notificationColor { map["notificationColor"] = c }
        if let s = notificationSmallIcon { map["notificationSmallIcon"] = s }
        if let l = notificationLargeIcon { map["notificationLargeIcon"] = l }
        return map
    }

    public func toSwift() -> TraceletForegroundServiceConfig {
        TraceletForegroundServiceConfig(
            enabled: enabled,
            channelId: channelId,
            channelName: channelName,
            notificationTitle: notificationTitle,
            notificationText: notificationText,
            notificationColor: notificationColor,
            notificationSmallIcon: notificationSmallIcon,
            notificationLargeIcon: notificationLargeIcon,
            notificationPriority: TraceletNotificationPriority(rawValue: notificationPriority) ?? .default,
            notificationOngoing: notificationOngoing,
            actions: actions
        )
    }

    @objc public class func fromMap(_ map: [String: Any]) -> TraceletForegroundServiceConfigObjC {
        TraceletForegroundServiceConfigObjC(
            enabled: map["enabled"] as? Bool ?? true,
            channelId: map["channelId"] as? String ?? "tracelet_channel",
            channelName: map["channelName"] as? String ?? "Tracelet",
            notificationTitle: map["notificationTitle"] as? String ?? "Tracelet",
            notificationText: map["notificationText"] as? String ?? "Tracking location in background",
            notificationColor: map["notificationColor"] as? String,
            notificationSmallIcon: map["notificationSmallIcon"] as? String,
            notificationLargeIcon: map["notificationLargeIcon"] as? String,
            notificationPriority: map["notificationPriority"] as? Int ?? 0,
            notificationOngoing: map["notificationOngoing"] as? Bool ?? true,
            actions: map["actions"] as? [String] ?? []
        )
    }
}

// MARK: - TraceletHttpConfigObjC

/// Objective-C wrapper for ``TraceletHttpConfig``.
@objc(TraceletHttpConfig_ObjC)
@objcMembers
public final class TraceletHttpConfigObjC: NSObject {
    public let url: String?
    /// 0 = POST, 1 = PUT
    public let method: Int
    public let headers: [String: String]
    public let httpRootProperty: String
    public let batchSync: Bool
    public let maxBatchSize: Int
    public let autoSync: Bool
    public let autoSyncThreshold: Int
    public let httpTimeout: Int
    /// 0 = asc, 1 = desc
    public let locationsOrderDirection: Int
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
        method: Int = 0,
        headers: [String: String] = [:],
        httpRootProperty: String = "location",
        batchSync: Bool = false,
        maxBatchSize: Int = 250,
        autoSync: Bool = true,
        autoSyncThreshold: Int = 0,
        httpTimeout: Int = 60000,
        locationsOrderDirection: Int = 0,
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
        self.locationsOrderDirection = locationsOrderDirection
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
            "method": method,
            "headers": headers,
            "httpRootProperty": httpRootProperty,
            "batchSync": batchSync,
            "maxBatchSize": maxBatchSize,
            "autoSync": autoSync,
            "autoSyncThreshold": autoSyncThreshold,
            "httpTimeout": httpTimeout,
            "locationsOrderDirection": locationsOrderDirection,
            "disableAutoSyncOnCellular": disableAutoSyncOnCellular,
            "maxRetries": maxRetries,
            "retryBackoffBase": retryBackoffBase,
            "retryBackoffCap": retryBackoffCap,
            "enableDeltaCompression": enableDeltaCompression,
            "deltaCoordinatePrecision": deltaCoordinatePrecision,
            "sslPinningCertificates": sslPinningCertificates,
            "sslPinningFingerprints": sslPinningFingerprints,
        ]
        if let u = url { map["url"] = u }
        return map
    }

    public func toSwift() -> TraceletHttpConfig {
        TraceletHttpConfig(
            url: url,
            method: TraceletHttpMethod(rawValue: method) ?? .post,
            headers: headers,
            httpRootProperty: httpRootProperty,
            batchSync: batchSync,
            maxBatchSize: maxBatchSize,
            autoSync: autoSync,
            autoSyncThreshold: autoSyncThreshold,
            httpTimeout: httpTimeout,
            locationsOrderDirection: TraceletLocationOrder(rawValue: locationsOrderDirection) ?? .asc,
            disableAutoSyncOnCellular: disableAutoSyncOnCellular,
            maxRetries: maxRetries,
            retryBackoffBase: retryBackoffBase,
            retryBackoffCap: retryBackoffCap,
            enableDeltaCompression: enableDeltaCompression,
            deltaCoordinatePrecision: deltaCoordinatePrecision,
            sslPinningCertificates: sslPinningCertificates,
            sslPinningFingerprints: sslPinningFingerprints
        )
    }

    @objc public class func fromMap(_ map: [String: Any]) -> TraceletHttpConfigObjC {
        TraceletHttpConfigObjC(
            url: map["url"] as? String,
            method: map["method"] as? Int ?? 0,
            headers: map["headers"] as? [String: String] ?? [:],
            httpRootProperty: map["httpRootProperty"] as? String ?? "location",
            batchSync: map["batchSync"] as? Bool ?? false,
            maxBatchSize: map["maxBatchSize"] as? Int ?? 250,
            autoSync: map["autoSync"] as? Bool ?? true,
            autoSyncThreshold: map["autoSyncThreshold"] as? Int ?? 0,
            httpTimeout: map["httpTimeout"] as? Int ?? 60000,
            locationsOrderDirection: map["locationsOrderDirection"] as? Int ?? 0,
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

// MARK: - TraceletLoggerConfigObjC

/// Objective-C wrapper for ``TraceletLoggerConfig``.
@objc(TraceletLoggerConfig_ObjC)
@objcMembers
public final class TraceletLoggerConfigObjC: NSObject {
    /// 0 = verbose, 1 = debug, 2 = info, 3 = warn, 4 = error
    public let logLevel: Int
    public let logMaxDays: Int
    public let debug: Bool

    public init(logLevel: Int = 2, logMaxDays: Int = 3, debug: Bool = false) {
        self.logLevel = logLevel
        self.logMaxDays = logMaxDays
        self.debug = debug
    }

    public func toMap() -> [String: Any] {
        ["logLevel": logLevel, "logMaxDays": logMaxDays, "debug": debug]
    }

    public func toSwift() -> TraceletLoggerConfig {
        TraceletLoggerConfig(
            logLevel: TraceletLogLevel(rawValue: logLevel) ?? .info,
            logMaxDays: logMaxDays,
            debug: debug
        )
    }

    @objc public class func fromMap(_ map: [String: Any]) -> TraceletLoggerConfigObjC {
        TraceletLoggerConfigObjC(
            logLevel: map["logLevel"] as? Int ?? 2,
            logMaxDays: map["logMaxDays"] as? Int ?? 3,
            debug: map["debug"] as? Bool ?? false
        )
    }
}

// MARK: - TraceletMotionConfigObjC

/// Objective-C wrapper for ``TraceletMotionConfig``.
@objc(TraceletMotionConfig_ObjC)
@objcMembers
public final class TraceletMotionConfigObjC: NSObject {
    public let stopTimeout: Int
    public let motionTriggerDelay: Int
    public let disableMotionActivityUpdates: Bool
    public let isMoving: Bool
    public let activityRecognitionInterval: Int
    public let minimumActivityRecognitionConfidence: Int
    public let disableStopDetection: Bool
    public let stopDetectionDelay: Int
    public let stopOnStationary: Bool
    /// Array of string activity types: "still", "on_foot", "walking", "running", "on_bicycle", "in_vehicle", "unknown"
    public let triggerActivities: [String]
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
        triggerActivities: [String] = [],
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
            "triggerActivities": triggerActivities,
            "shakeThreshold": shakeThreshold,
            "stillThreshold": stillThreshold,
            "stillSampleCount": stillSampleCount,
        ]
    }

    public func toSwift() -> TraceletMotionConfig {
        let activities: Set<TraceletMotionActivityType> = Set(
            triggerActivities.compactMap { TraceletMotionActivityType(rawValue: $0) }
        )
        return TraceletMotionConfig(
            stopTimeout: stopTimeout,
            motionTriggerDelay: motionTriggerDelay,
            disableMotionActivityUpdates: disableMotionActivityUpdates,
            isMoving: isMoving,
            activityRecognitionInterval: activityRecognitionInterval,
            minimumActivityRecognitionConfidence: minimumActivityRecognitionConfidence,
            disableStopDetection: disableStopDetection,
            stopDetectionDelay: stopDetectionDelay,
            stopOnStationary: stopOnStationary,
            triggerActivities: activities,
            shakeThreshold: shakeThreshold,
            stillThreshold: stillThreshold,
            stillSampleCount: stillSampleCount
        )
    }

    @objc public class func fromMap(_ map: [String: Any]) -> TraceletMotionConfigObjC {
        TraceletMotionConfigObjC(
            stopTimeout: map["stopTimeout"] as? Int ?? 5,
            motionTriggerDelay: map["motionTriggerDelay"] as? Int ?? 0,
            disableMotionActivityUpdates: map["disableMotionActivityUpdates"] as? Bool ?? false,
            isMoving: map["isMoving"] as? Bool ?? false,
            activityRecognitionInterval: map["activityRecognitionInterval"] as? Int ?? 10000,
            minimumActivityRecognitionConfidence: map["minimumActivityRecognitionConfidence"] as? Int ?? 75,
            disableStopDetection: map["disableStopDetection"] as? Bool ?? false,
            stopDetectionDelay: map["stopDetectionDelay"] as? Int ?? 0,
            stopOnStationary: map["stopOnStationary"] as? Bool ?? false,
            triggerActivities: map["triggerActivities"] as? [String] ?? [],
            shakeThreshold: map["shakeThreshold"] as? Double ?? 2.5,
            stillThreshold: map["stillThreshold"] as? Double ?? 0.4,
            stillSampleCount: map["stillSampleCount"] as? Int ?? 25
        )
    }
}

// MARK: - TraceletGeofenceConfigObjC

/// Objective-C wrapper for ``TraceletGeofenceConfig``.
@objc(TraceletGeofenceConfig_ObjC)
@objcMembers
public final class TraceletGeofenceConfigObjC: NSObject {
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

    public func toSwift() -> TraceletGeofenceConfig {
        TraceletGeofenceConfig(
            geofenceProximityRadius: geofenceProximityRadius,
            geofenceInitialTriggerEntry: geofenceInitialTriggerEntry,
            geofenceModeKnockOut: geofenceModeKnockOut
        )
    }

    @objc public class func fromMap(_ map: [String: Any]) -> TraceletGeofenceConfigObjC {
        TraceletGeofenceConfigObjC(
            geofenceProximityRadius: map["geofenceProximityRadius"] as? Int ?? 1000,
            geofenceInitialTriggerEntry: map["geofenceInitialTriggerEntry"] as? Bool ?? true,
            geofenceModeKnockOut: map["geofenceModeKnockOut"] as? Bool ?? false
        )
    }
}

// MARK: - TraceletPersistenceConfigObjC

/// Objective-C wrapper for ``TraceletPersistenceConfig``.
@objc(TraceletPersistenceConfig_ObjC)
@objcMembers
public final class TraceletPersistenceConfigObjC: NSObject {
    /// 0 = all, 1 = location, 2 = geofence, 3 = none
    public let persistMode: Int
    public let maxDaysToPersist: Int
    public let maxRecordsToPersist: Int
    public let locationTemplate: String?
    public let geofenceTemplate: String?
    public let disableProviderChangeRecord: Bool

    public init(
        persistMode: Int = 0,
        maxDaysToPersist: Int = -1,
        maxRecordsToPersist: Int = -1,
        locationTemplate: String? = nil,
        geofenceTemplate: String? = nil,
        disableProviderChangeRecord: Bool = false
    ) {
        self.persistMode = persistMode
        self.maxDaysToPersist = maxDaysToPersist
        self.maxRecordsToPersist = maxRecordsToPersist
        self.locationTemplate = locationTemplate
        self.geofenceTemplate = geofenceTemplate
        self.disableProviderChangeRecord = disableProviderChangeRecord
    }

    public func toMap() -> [String: Any] {
        var map: [String: Any] = [
            "persistMode": persistMode,
            "maxDaysToPersist": maxDaysToPersist,
            "maxRecordsToPersist": maxRecordsToPersist,
            "disableProviderChangeRecord": disableProviderChangeRecord,
        ]
        if let t = locationTemplate { map["locationTemplate"] = t }
        if let t = geofenceTemplate { map["geofenceTemplate"] = t }
        return map
    }

    public func toSwift() -> TraceletPersistenceConfig {
        TraceletPersistenceConfig(
            persistMode: TraceletPersistMode(rawValue: persistMode) ?? .all,
            maxDaysToPersist: maxDaysToPersist,
            maxRecordsToPersist: maxRecordsToPersist,
            locationTemplate: locationTemplate,
            geofenceTemplate: geofenceTemplate,
            disableProviderChangeRecord: disableProviderChangeRecord
        )
    }

    @objc public class func fromMap(_ map: [String: Any]) -> TraceletPersistenceConfigObjC {
        TraceletPersistenceConfigObjC(
            persistMode: map["persistMode"] as? Int ?? 0,
            maxDaysToPersist: map["maxDaysToPersist"] as? Int ?? -1,
            maxRecordsToPersist: map["maxRecordsToPersist"] as? Int ?? -1,
            locationTemplate: map["locationTemplate"] as? String,
            geofenceTemplate: map["geofenceTemplate"] as? String,
            disableProviderChangeRecord: map["disableProviderChangeRecord"] as? Bool ?? false
        )
    }
}

// MARK: - TraceletAuditConfigObjC

/// Objective-C wrapper for ``TraceletAuditConfig``.
@objc(TraceletAuditConfig_ObjC)
@objcMembers
public final class TraceletAuditConfigObjC: NSObject {
    public let enabled: Bool
    /// 0 = SHA-256, 1 = SHA-512
    public let hashAlgorithm: Int

    public init(enabled: Bool = false, hashAlgorithm: Int = 0) {
        self.enabled = enabled
        self.hashAlgorithm = hashAlgorithm
    }

    public func toMap() -> [String: Any] {
        ["enabled": enabled, "hashAlgorithm": hashAlgorithm]
    }

    public func toSwift() -> TraceletAuditConfig {
        TraceletAuditConfig(
            enabled: enabled,
            hashAlgorithm: TraceletHashAlgorithm(rawValue: hashAlgorithm) ?? .sha256
        )
    }

    @objc public class func fromMap(_ map: [String: Any]) -> TraceletAuditConfigObjC {
        TraceletAuditConfigObjC(
            enabled: map["enabled"] as? Bool ?? false,
            hashAlgorithm: map["hashAlgorithm"] as? Int ?? 0
        )
    }
}

// MARK: - TraceletPrivacyZoneConfigObjC

/// Objective-C wrapper for ``TraceletPrivacyZoneConfig``.
@objc(TraceletPrivacyZoneConfig_ObjC)
@objcMembers
public final class TraceletPrivacyZoneConfigObjC: NSObject {
    public let enabled: Bool

    public init(enabled: Bool = false) {
        self.enabled = enabled
    }

    public func toMap() -> [String: Any] {
        ["enabled": enabled]
    }

    public func toSwift() -> TraceletPrivacyZoneConfig {
        TraceletPrivacyZoneConfig(enabled: enabled)
    }

    @objc public class func fromMap(_ map: [String: Any]) -> TraceletPrivacyZoneConfigObjC {
        TraceletPrivacyZoneConfigObjC(enabled: map["enabled"] as? Bool ?? false)
    }
}

// MARK: - TraceletSecurityConfigObjC

/// Objective-C wrapper for ``TraceletSecurityConfig``.
@objc(TraceletSecurityConfig_ObjC)
@objcMembers
public final class TraceletSecurityConfigObjC: NSObject {
    public let encryptDatabase: Bool

    public init(encryptDatabase: Bool = false) {
        self.encryptDatabase = encryptDatabase
    }

    public func toMap() -> [String: Any] {
        ["encryptDatabase": encryptDatabase]
    }

    public func toSwift() -> TraceletSecurityConfig {
        TraceletSecurityConfig(encryptDatabase: encryptDatabase)
    }

    @objc public class func fromMap(_ map: [String: Any]) -> TraceletSecurityConfigObjC {
        TraceletSecurityConfigObjC(encryptDatabase: map["encryptDatabase"] as? Bool ?? false)
    }
}

// MARK: - TraceletAttestationConfigObjC

/// Objective-C wrapper for ``TraceletAttestationConfig``.
@objc(TraceletAttestationConfig_ObjC)
@objcMembers
public final class TraceletAttestationConfigObjC: NSObject {
    public let enabled: Bool
    public let refreshInterval: Int

    public init(enabled: Bool = false, refreshInterval: Int = 3600) {
        self.enabled = enabled
        self.refreshInterval = refreshInterval
    }

    public func toMap() -> [String: Any] {
        ["enabled": enabled, "refreshInterval": refreshInterval]
    }

    public func toSwift() -> TraceletAttestationConfig {
        TraceletAttestationConfig(enabled: enabled, refreshInterval: refreshInterval)
    }

    @objc public class func fromMap(_ map: [String: Any]) -> TraceletAttestationConfigObjC {
        TraceletAttestationConfigObjC(
            enabled: map["enabled"] as? Bool ?? false,
            refreshInterval: map["refreshInterval"] as? Int ?? 3600
        )
    }
}
