import Foundation
import CoreLocation

/// Persists plugin configuration via UserDefaults.
///
/// Stores the complete Config map as a JSON blob. Provides typed getters
/// matching all Dart Config fields across sub-configs: GeoConfig, AppConfig,
/// HttpConfig, LoggerConfig, MotionConfig, GeofenceConfig, ForegroundServiceConfig.
final class ConfigManager {
    private let defaults: UserDefaults
    private let key = "com.tracelet.config"
    private var cache: [String: Any] = [:]

    init() {
        defaults = UserDefaults.standard
        loadFromDisk()
    }

    // MARK: - Persistence

    func setConfig(_ config: [String: Any]) -> [String: Any] {
        // Dart sends a nested structure: {geo: {...}, app: {...}, http: {...}, ...}
        // Flatten known section sub-maps into the top level first.
        let sectionKeys: Set<String> = ["geo", "app", "http", "logger", "motion", "geofence", "persistence", "audit", "privacyZone"]
        var flat: [String: Any] = [:]
        for (key, value) in config {
            if sectionKeys.contains(key), let sub = value as? [String: Any] {
                flat.merge(sub) { _, new in new }
            } else {
                flat[key] = value
            }
        }
        cache.merge(flat) { _, new in new }
        saveToDisk()
        return cache
    }

    func getConfig() -> [String: Any] {
        return cache
    }

    func reset(_ newConfig: [String: Any]?) {
        cache = defaultConfig()
        if let c = newConfig {
            let _ = setConfig(c)
        }
        saveToDisk()
    }

    private func loadFromDisk() {
        if let data = defaults.data(forKey: key),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            cache = json
        } else {
            cache = defaultConfig()
        }
    }

    private func saveToDisk() {
        if let data = try? JSONSerialization.data(withJSONObject: cache) {
            defaults.set(data, forKey: key)
        }
    }

    // MARK: - Typed Getters

    // GeoConfig
    func getDesiredAccuracy() -> Int { cache["desiredAccuracy"] as? Int ?? -1 }
    func getDistanceFilter() -> Double { cache["distanceFilter"] as? Double ?? 10.0 }
    func getLocationTimeout() -> Int { cache["locationTimeout"] as? Int ?? 60 }
    func getStationaryRadius() -> Double { cache["stationaryRadius"] as? Double ?? 25.0 }
    func getGeofenceProximityRadius() -> Double { cache["geofenceProximityRadius"] as? Double ?? 1000.0 }
    func getMaxDaysToPersist() -> Int { cache["maxDaysToPersist"] as? Int ?? -1 }
    func getMaxRecordsToPersist() -> Int { cache["maxRecordsToPersist"] as? Int ?? -1 }
    func getLocationUpdateInterval() -> Int { cache["locationUpdateInterval"] as? Int ?? 1000 }
    func getFastestLocationUpdateInterval() -> Int { cache["fastestLocationUpdateInterval"] as? Int ?? -1 }
    func getDeferTime() -> Int { cache["deferTime"] as? Int ?? 0 }
    func getAllowIdenticalLocations() -> Bool { cache["allowIdenticalLocations"] as? Bool ?? false }
    func getUseSignificantChangesOnly() -> Bool { cache["useSignificantChangesOnly"] as? Bool ?? false }
    func getShowsBackgroundLocationIndicator() -> Bool { cache["showsBackgroundLocationIndicator"] as? Bool ?? false }
    func getPausesLocationUpdatesAutomatically() -> Bool { cache["pausesLocationUpdatesAutomatically"] as? Bool ?? true }
    func getDisableLocationAuthorizationAlert() -> Bool { cache["disableLocationAuthorizationAlert"] as? Bool ?? false }
    func getLocationAuthorizationRequest() -> String { cache["locationAuthorizationRequest"] as? String ?? "Always" }
    func getStopAfterElapsedMinutes() -> Int { cache["stopAfterElapsedMinutes"] as? Int ?? -1 }
    func getMaxMonitoredGeofences() -> Int { cache["maxMonitoredGeofences"] as? Int ?? -1 }
    func getEnableTimestampMeta() -> Bool { cache["enableTimestampMeta"] as? Bool ?? false }

    /// Maps the `activityType` config string to a `CLActivityType` (I-M2).
    func getActivityType() -> CLActivityType {
        let value = cache["activityType"] as? String ?? "other"
        switch value {
        case "automotiveNavigation": return .automotiveNavigation
        case "fitness": return .fitness
        case "otherNavigation": return .otherNavigation
        case "airborne":
            if #available(iOS 12.0, *) { return .airborne }
            return .otherNavigation
        default: return .otherNavigation
        }
    }
    // Periodic mode config
    func getPeriodicLocationInterval() -> Int { cache["periodicLocationInterval"] as? Int ?? 900 }
    func getPeriodicDesiredAccuracy() -> Int { cache["periodicDesiredAccuracy"] as? Int ?? 1 }
    func getPeriodicUseForegroundService() -> Bool { cache["periodicUseForegroundService"] as? Bool ?? false }
    func getPeriodicUseExactAlarms() -> Bool { cache["periodicUseExactAlarms"] as? Bool ?? false }
    // LocationFilter
    func getOdometerAccuracyThreshold() -> Int { cache["odometerAccuracyThreshold"] as? Int ?? 0 }
    func getRejectMockLocations() -> Bool { cache["rejectMockLocations"] as? Bool ?? false }
    func getMockDetectionLevel() -> Int { cache["mockDetectionLevel"] as? Int ?? 1 }

    // AppConfig
    func isDebug() -> Bool { cache["debug"] as? Bool ?? false }
    func getLogLevel() -> Int { cache["logLevel"] as? Int ?? 5 }
    func getStopOnTerminate() -> Bool { cache["stopOnTerminate"] as? Bool ?? true }
    func getStartOnBoot() -> Bool { cache["startOnBoot"] as? Bool ?? false }
    func getHeartbeatInterval() -> Int { cache["heartbeatInterval"] as? Int ?? 60 }
    func getSchedule() -> [String] { cache["schedule"] as? [String] ?? [] }
    func getPreventSuspend() -> Bool { cache["preventSuspend"] as? Bool ?? false }

    // MotionConfig
    func getIsMoving() -> Bool { cache["isMoving"] as? Bool ?? false }
    func getStopTimeout() -> Int { cache["stopTimeout"] as? Int ?? 5 }
    func getMotionTriggerDelay() -> Int { cache["motionTriggerDelay"] as? Int ?? 0 }
    func getStopDetectionDelay() -> Int { cache["stopDetectionDelay"] as? Int ?? 0 }
    func getDisableMotionActivityUpdates() -> Bool { cache["disableMotionActivityUpdates"] as? Bool ?? false }
    func getDisableStopDetection() -> Bool { cache["disableStopDetection"] as? Bool ?? false }
    func getActivityRecognitionInterval() -> Int { cache["activityRecognitionInterval"] as? Int ?? 10000 }
    func getMinimumActivityRecognitionConfidence() -> Int { cache["minimumActivityRecognitionConfidence"] as? Int ?? 75 }
    func getStopOnStationary() -> Bool { cache["stopOnStationary"] as? Bool ?? false }
    func getTriggerActivities() -> String { cache["triggerActivities"] as? String ?? "" }

    /// Shake threshold in g-force (converted from m/s² config value).
    /// Default: 2.5 m/s² ÷ 9.81 ≈ 0.255 g
    func getShakeThreshold() -> Double {
        let msSquared = cache["shakeThreshold"] as? Double ?? 2.5
        return msSquared / 9.81
    }
    /// Still threshold in g-force (converted from m/s² config value).
    /// Default: 0.4 m/s² ÷ 9.81 ≈ 0.041 g
    func getStillThreshold() -> Double {
        let msSquared = cache["stillThreshold"] as? Double ?? 0.4
        return msSquared / 9.81
    }
    /// Consecutive still samples needed. iOS samples at 50 Hz so
    /// adjust accordingly. Default: 25 (matches Dart default).
    func getStillSampleCount() -> Int { cache["stillSampleCount"] as? Int ?? 25 }

    // GeofenceConfig
    func getGeofenceInitialTriggerEntry() -> Bool { cache["geofenceInitialTriggerEntry"] as? Bool ?? true }
    func getGeofenceModeKnockOut() -> Bool { cache["geofenceModeKnockOut"] as? Bool ?? false }
    func getGeofenceModeHighAccuracy() -> Bool { cache["geofenceModeHighAccuracy"] as? Bool ?? false }

    // HttpConfig
    func getUrl() -> String { cache["url"] as? String ?? "" }
    func getAutoSync() -> Bool { cache["autoSync"] as? Bool ?? true }
    func getAutoSyncThreshold() -> Int { cache["autoSyncThreshold"] as? Int ?? 0 }
    func getBatchSync() -> Bool { cache["batchSync"] as? Bool ?? false }
    func getMaxBatchSize() -> Int {
        let value = cache["maxBatchSize"] as? Int ?? 250
        return value < 0 ? 250 : value
    }
    func getHttpRootProperty() -> String { cache["httpRootProperty"] as? String ?? "location" }
    func getHttpHeaders() -> [String: String] {
        if let headers = cache["headers"] as? [String: String] {
            return headers
        }
        // Platform channel may deliver values as [String: Any] — coerce to strings.
        if let headers = cache["headers"] as? [String: Any] {
            return headers.mapValues { "\($0)" }
        }
        return [:]
    }
    func getHttpMethod() -> String {
        // Dart serializes method as an Int (0 = POST, 1 = PUT).
        if let index = cache["method"] as? Int {
            return index == 1 ? "PUT" : "POST"
        }
        return cache["method"] as? String ?? "POST"
    }
    func getHttpTimeout() -> Int { cache["httpTimeout"] as? Int ?? 60000 }
    func getLocationsOrderDirection() -> String { cache["locationsOrderDirection"] as? String ?? "ASC" }
    func getDisableAutoSyncOnCellular() -> Bool { cache["disableAutoSyncOnCellular"] as? Bool ?? false }
    func getMaxRetries() -> Int { cache["maxRetries"] as? Int ?? 10 }
    func getRetryBackoffBase() -> Int { cache["retryBackoffBase"] as? Int ?? 1000 }
    func getRetryBackoffCap() -> Int { cache["retryBackoffCap"] as? Int ?? 300000 }

    // PersistenceConfig
    func getPersistMode() -> Int { cache["persistMode"] as? Int ?? 0 }
    func getLocationTemplate() -> String? { cache["locationTemplate"] as? String }
    func getGeofenceTemplate() -> String? { cache["geofenceTemplate"] as? String }
    func getDisableProviderChangeRecord() -> Bool { cache["disableProviderChangeRecord"] as? Bool ?? false }
    func getPersistenceExtras() -> [String: Any] { cache["extras"] as? [String: Any] ?? [:] }

    // LoggerConfig
    func getLogMaxDays() -> Int { cache["logMaxDays"] as? Int ?? 3 }

    // AuditConfig (Enterprise)
    func getAuditEnabled() -> Bool { cache["enabled"] as? Bool ?? false }
    func getAuditHashAlgorithm() -> String { cache["hashAlgorithm"] as? String ?? "SHA-256" }
    func getAuditIncludeExtrasInHash() -> Bool { cache["includeExtrasInHash"] as? Bool ?? false }

    // PrivacyZoneConfig (Enterprise)
    func getPrivacyZoneEnabled() -> Bool { cache["privacyZoneEnabled"] as? Bool ?? false }

    // MARK: - Defaults
    private func defaultConfig() -> [String: Any] {
        return [
            "desiredAccuracy": -1,
            "distanceFilter": 10.0,
            "stationaryRadius": 25.0,
            "disableElasticity": false,
            "elasticityMultiplier": 1.0,
            "geofenceProximityRadius": 1000.0,
            "locationUpdateInterval": 1000,
            "fastestLocationUpdateInterval": -1,
            "deferTime": 0,
            "allowIdenticalLocations": false,
            "useSignificantChangesOnly": false,
            "showsBackgroundLocationIndicator": false,
            "pausesLocationUpdatesAutomatically": true,
            "disableLocationAuthorizationAlert": false,
            "locationAuthorizationRequest": "Always",
            "debug": false,
            "logLevel": 5,
            "stopOnTerminate": true,
            "startOnBoot": false,
            "heartbeatInterval": 60,
            "schedule": [] as [String],
            "preventSuspend": false,
            "isMoving": false,
            "stopTimeout": 5,
            "motionTriggerDelay": 0,
            "stopDetectionDelay": 0,
            "disableMotionActivityUpdates": false,
            "disableStopDetection": false,
            "activityRecognitionInterval": 10000,
            "minimumActivityRecognitionConfidence": 75,
            "stopOnStationary": false,
            "triggerActivities": "",
            "stopAfterElapsedMinutes": -1,
            "maxMonitoredGeofences": -1,
            "enableTimestampMeta": false,
            "geofenceInitialTriggerEntry": true,
            "geofenceModeKnockOut": false,
            "geofenceModeHighAccuracy": false,
            "url": "",
            "autoSync": true,
            "autoSyncThreshold": 0,
            "batchSync": false,
            "maxBatchSize": -1,
            "httpRootProperty": "location",
            "headers": [:] as [String: String],
            "method": "POST",
            "httpTimeout": 60000,
            "locationsOrderDirection": "ASC",
            "disableAutoSyncOnCellular": false,
            "persistMode": 0,
            "maxDaysToPersist": -1,
            "maxRecordsToPersist": -1,
            "disableProviderChangeRecord": false,
            "logMaxDays": 3,
        ]
    }
}
