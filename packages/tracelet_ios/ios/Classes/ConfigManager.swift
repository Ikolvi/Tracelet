import Foundation

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
        cache.merge(config) { _, new in new }
        saveToDisk()
        return cache
    }

    func getConfig() -> [String: Any] {
        return cache
    }

    func reset(_ newConfig: [String: Any]?) {
        cache = defaultConfig()
        if let c = newConfig {
            cache.merge(c) { _, new in new }
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
    func getStationaryRadius() -> Double { cache["stationaryRadius"] as? Double ?? 25.0 }
    func getDisableElasticity() -> Bool { cache["disableElasticity"] as? Bool ?? false }
    func getElasticityMultiplier() -> Double { cache["elasticityMultiplier"] as? Double ?? 1.0 }
    func getGeofenceProximityRadius() -> Double { cache["geofenceProximityRadius"] as? Double ?? 1000.0 }
    func getMaxDaysToPersist() -> Int { cache["maxDaysToPersist"] as? Int ?? 1 }
    func getMaxRecordsToPersist() -> Int { cache["maxRecordsToPersist"] as? Int ?? -1 }
    func getLocationUpdateInterval() -> Int { cache["locationUpdateInterval"] as? Int ?? 1000 }
    func getFastestLocationUpdateInterval() -> Int { cache["fastestLocationUpdateInterval"] as? Int ?? -1 }
    func getDeferTime() -> Int { cache["deferTime"] as? Int ?? 0 }
    func getAllowIdenticalLocations() -> Bool { cache["allowIdenticalLocations"] as? Bool ?? false }
    func getUseSignificantChangesOnly() -> Bool { cache["useSignificantChangesOnly"] as? Bool ?? false }
    func getShowsBackgroundLocationIndicator() -> Bool { cache["showsBackgroundLocationIndicator"] as? Bool ?? false }
    func getPausesLocationUpdatesAutomatically() -> Bool { cache["pausesLocationUpdatesAutomatically"] as? Bool ?? false }
    func getDisableLocationAuthorizationAlert() -> Bool { cache["disableLocationAuthorizationAlert"] as? Bool ?? false }
    func getLocationAuthorizationRequest() -> String { cache["locationAuthorizationRequest"] as? String ?? "Always" }

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

    // GeofenceConfig
    func getGeofenceInitialTriggerEntry() -> Bool { cache["geofenceInitialTriggerEntry"] as? Bool ?? true }
    func getGeofenceModeKnockOut() -> Bool { cache["geofenceModeKnockOut"] as? Bool ?? false }

    // HttpConfig
    func getUrl() -> String { cache["url"] as? String ?? "" }
    func getAutoSync() -> Bool { cache["autoSync"] as? Bool ?? true }
    func getAutoSyncThreshold() -> Int { cache["autoSyncThreshold"] as? Int ?? 0 }
    func getBatchSync() -> Bool { cache["batchSync"] as? Bool ?? false }
    func getMaxBatchSize() -> Int { cache["maxBatchSize"] as? Int ?? -1 }
    func getHttpRootProperty() -> String { cache["httpRootProperty"] as? String ?? "location" }
    func getHttpHeaders() -> [String: String] { cache["headers"] as? [String: String] ?? [:] }
    func getHttpMethod() -> String { cache["method"] as? String ?? "POST" }
    func getHttpTimeout() -> Int { cache["httpTimeout"] as? Int ?? 60000 }
    func getLocationsOrderDirection() -> String { cache["locationsOrderDirection"] as? String ?? "ASC" }

    // LoggerConfig
    func getLogMaxDays() -> Int { cache["logMaxDays"] as? Int ?? 3 }

    // MARK: - Defaults
    private func defaultConfig() -> [String: Any] {
        return [
            "desiredAccuracy": -1,
            "distanceFilter": 10.0,
            "stationaryRadius": 25.0,
            "disableElasticity": false,
            "elasticityMultiplier": 1.0,
            "geofenceProximityRadius": 1000.0,
            "maxDaysToPersist": 1,
            "maxRecordsToPersist": -1,
            "locationUpdateInterval": 1000,
            "fastestLocationUpdateInterval": -1,
            "deferTime": 0,
            "allowIdenticalLocations": false,
            "useSignificantChangesOnly": false,
            "showsBackgroundLocationIndicator": false,
            "pausesLocationUpdatesAutomatically": false,
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
            "geofenceInitialTriggerEntry": true,
            "geofenceModeKnockOut": false,
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
            "logMaxDays": 3,
        ]
    }
}
