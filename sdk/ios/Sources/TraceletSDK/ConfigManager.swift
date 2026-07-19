import Foundation
import CoreLocation

/// Persists plugin configuration via UserDefaults.
///
/// Stores the complete Config map as a JSON blob. Provides typed getters
/// matching all Dart Config fields across sub-configs: GeoConfig, AppConfig,
/// HttpConfig, LoggerConfig, MotionConfig, GeofenceConfig, ForegroundServiceConfig.
public final class ConfigManager {
    private let defaults: UserDefaults
    private let key = "com.tracelet.config"
    private var cache: [String: Any] = [:]

    public init() {
        defaults = UserDefaults.standard
        loadFromDisk()
    }

    // MARK: - Persistence

    public func setConfig(_ config: [String: Any]) -> [String: Any] {
        // Dart sends a nested structure: {geo: {...}, app: {...}, http: {...}, ...}
        // Flatten known section sub-maps into the top level first.
        let sectionKeys: Set<String> = ["geo", "app", "http", "logger", "motion", "geofence", "persistence"]
        var flat: [String: Any] = [:]
        for (key, value) in config {
            if sectionKeys.contains(key), let sub = value as? [String: Any] {
                flat.merge(sub) { _, new in new }
            } else {
                flat[key] = value
            }
        }
        // Filter out NSNull / nil values — a partial setConfig() must not
        // overwrite existing non-null config with defaults.  E.g. calling
        // setConfig({app: {heartbeatInterval: -1}}) must not wipe the
        // HTTP URL that was set during ready().
        let filtered = flat.filter { !($0.value is NSNull) }
        cache.merge(filtered) { _, new in new }
        saveToDisk()
        return cache
    }

    public func getConfig() -> [String: Any] {
        return cache
    }

    /// Returns `true` if a config has been persisted at least once.
    public func hasConfig() -> Bool {
        return defaults.data(forKey: key) != nil
    }

    public func reset(_ newConfig: [String: Any]?) {
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
    public func getDesiredAccuracy() -> Int { (cache["desiredAccuracy"] as? NSNumber)?.intValue ?? -1 }
    public func getDistanceFilter() -> Double { cache["distanceFilter"] as? Double ?? 10.0 }
    public func getLocationTimeout() -> Int { (cache["locationTimeout"] as? NSNumber)?.intValue ?? 60 }
    public func getStationaryRadius() -> Double { cache["stationaryRadius"] as? Double ?? 25.0 }
    public func getGeofenceProximityRadius() -> Double { cache["geofenceProximityRadius"] as? Double ?? 1000.0 }
    public func getResolveAddress() -> Bool { cache["resolveAddress"] as? Bool ?? false }
    public func getMaxDaysToPersist() -> Int { (cache["maxDaysToPersist"] as? NSNumber)?.intValue ?? -1 }
    public func getMaxRecordsToPersist() -> Int { (cache["maxRecordsToPersist"] as? NSNumber)?.intValue ?? -1 }
    public func getLocationUpdateInterval() -> Int { (cache["locationUpdateInterval"] as? NSNumber)?.intValue ?? 1000 }
    public func getFastestLocationUpdateInterval() -> Int { (cache["fastestLocationUpdateInterval"] as? NSNumber)?.intValue ?? -1 }
    public func getDeferTime() -> Int { (cache["deferTime"] as? NSNumber)?.intValue ?? 0 }
    public func getAllowIdenticalLocations() -> Bool { cache["allowIdenticalLocations"] as? Bool ?? false }
    public func getUseSignificantChangesOnly() -> Bool { cache["useSignificantChangesOnly"] as? Bool ?? false }
    public func getShowsBackgroundLocationIndicator() -> Bool { cache["showsBackgroundLocationIndicator"] as? Bool ?? false }
    public func getPausesLocationUpdatesAutomatically() -> Bool { cache["pausesLocationUpdatesAutomatically"] as? Bool ?? true }
    public func getDisableLocationAuthorizationAlert() -> Bool { cache["disableLocationAuthorizationAlert"] as? Bool ?? false }
    public func getLocationAuthorizationRequest() -> String { cache["locationAuthorizationRequest"] as? String ?? "Always" }
    public func getStopAfterElapsedMinutes() -> Int { (cache["stopAfterElapsedMinutes"] as? NSNumber)?.intValue ?? -1 }
    public func getMaxMonitoredGeofences() -> Int { (cache["maxMonitoredGeofences"] as? NSNumber)?.intValue ?? -1 }
    public func getEnableTimestampMeta() -> Bool { cache["enableTimestampMeta"] as? Bool ?? false }

    /// Maps the `activityType` config value to a `CLActivityType` (I-M2).
    ///
    /// The Flutter bridge sends `activityType` as the raw enum index (an Int,
    /// matching `TraceletActivityType`); older persisted caches may still hold
    /// the string name. Reading it as an `Int` first (with a string fallback)
    /// makes the configured value actually take effect — previously the value
    /// was stored as an Int but read as a String, so it always fell through to
    /// `.otherNavigation` regardless of what was configured. See issue #250.
    public func getActivityType() -> CLActivityType {
        let resolved: TraceletActivityType
        if let number = cache["activityType"] as? NSNumber,
           let t = TraceletActivityType(rawValue: number.intValue) {
            resolved = t
        } else if let name = cache["activityType"] as? String {
            switch name {
            case "automotiveNavigation": resolved = .automotiveNavigation
            case "fitness": resolved = .fitness
            case "otherNavigation": resolved = .otherNavigation
            case "airborne": resolved = .airborne
            case "other": resolved = .other
            default: resolved = .otherNavigation
            }
        } else {
            resolved = .otherNavigation
        }

        switch resolved {
        case .other: return .other
        case .automotiveNavigation: return .automotiveNavigation
        case .fitness: return .fitness
        case .otherNavigation: return .otherNavigation
        case .airborne:
            if #available(iOS 12.0, *) { return .airborne }
            return .otherNavigation
        }
    }
    // Periodic mode config
    public func getPeriodicLocationInterval() -> Int { (cache["periodicLocationInterval"] as? NSNumber)?.intValue ?? 900 }
    public func getPeriodicDesiredAccuracy() -> Int { (cache["periodicDesiredAccuracy"] as? NSNumber)?.intValue ?? 1 }
    public func getPeriodicUseForegroundService() -> Bool { cache["periodicUseForegroundService"] as? Bool ?? false }
    public func getPeriodicUseExactAlarms() -> Bool { cache["periodicUseExactAlarms"] as? Bool ?? false }
    // LocationFilter
    public func getOdometerAccuracyThreshold() -> Int { (cache["odometerAccuracyThreshold"] as? NSNumber)?.intValue ?? 0 }
    public func getRejectMockLocations() -> Bool { cache["rejectMockLocations"] as? Bool ?? false }
    public func getMockDetectionLevel() -> Int { (cache["mockDetectionLevel"] as? NSNumber)?.intValue ?? 1 }
    public func getDisableElasticity() -> Bool { cache["disableElasticity"] as? Bool ?? false }
    public func getElasticityMultiplier() -> Double { (cache["elasticityMultiplier"] as? NSNumber)?.doubleValue ?? 1.0 }
    public func getEnableAdaptiveMode() -> Bool { cache["enableAdaptiveMode"] as? Bool ?? false }
    public func getTrackingAccuracyThreshold() -> Int { (cache["trackingAccuracyThreshold"] as? NSNumber)?.intValue ?? 100 }
    public func getFilterPolicy() -> Int { (cache["filterPolicy"] as? NSNumber)?.intValue ?? 0 }
    public func getMaxImpliedSpeed() -> Int { (cache["maxImpliedSpeed"] as? NSNumber)?.intValue ?? 80 }
    public func getEnableSparseUpdates() -> Bool { cache["enableSparseUpdates"] as? Bool ?? false }
    public func getSparseDistanceThreshold() -> Double { (cache["sparseDistanceThreshold"] as? NSNumber)?.doubleValue ?? 50.0 }
    public func getSparseMaxIdleSeconds() -> Int { (cache["sparseMaxIdleSeconds"] as? NSNumber)?.intValue ?? 0 }
    public func getEnableKalmanFilter() -> Bool {
        // Dart's LocationFilter serializes this under "useKalmanFilter"; read it
        // first so the EKF isn't silently disabled by a key mismatch (#148).
        (cache["useKalmanFilter"] as? Bool) ?? (cache["enableKalmanFilter"] as? Bool) ?? false
    }

    // Dead Reckoning
    public func getEnableDeadReckoning() -> Bool { cache["enableDeadReckoning"] as? Bool ?? false }
    public func getDeadReckoningActivationDelay() -> Int { (cache["deadReckoningActivationDelay"] as? NSNumber)?.intValue ?? 10 }
    public func getDeadReckoningMaxDuration() -> Int { (cache["deadReckoningMaxDuration"] as? NSNumber)?.intValue ?? 120 }

    // AppConfig
    public func isDebug() -> Bool { cache["debug"] as? Bool ?? false }
    public func getLogLevel() -> Int { (cache["logLevel"] as? NSNumber)?.intValue ?? 5 }
    public func getStopOnTerminate() -> Bool { cache["stopOnTerminate"] as? Bool ?? true }
    public func getStartOnBoot() -> Bool { cache["startOnBoot"] as? Bool ?? false }
    public func getHeartbeatInterval() -> Int { (cache["heartbeatInterval"] as? NSNumber)?.intValue ?? 60 }
    public func getSchedule() -> [String] { cache["schedule"] as? [String] ?? [] }
    public func getPreventSuspend() -> Bool { cache["preventSuspend"] as? Bool ?? false }
    public func getUseBackgroundActivitySession() -> Bool { cache["useBackgroundActivitySession"] as? Bool ?? false }
    
    public struct LiveActivityConfig {
        public let title: String
        public let body: String
    }

    public func getLiveActivityConfig() -> LiveActivityConfig? {
        guard let map = cache["liveActivityConfig"] as? [String: Any],
              let title = map["title"] as? String,
              let body = map["body"] as? String else { return nil }
        return LiveActivityConfig(title: title, body: body)
    }

    // MotionConfig
    public func getIsMoving() -> Bool { cache["isMoving"] as? Bool ?? false }
    public func getStopTimeout() -> Int { (cache["stopTimeout"] as? NSNumber)?.intValue ?? 5 }
    public func getMotionTriggerDelay() -> Int { (cache["motionTriggerDelay"] as? NSNumber)?.intValue ?? 0 }
    public func getStopDetectionDelay() -> Int { (cache["stopDetectionDelay"] as? NSNumber)?.intValue ?? 0 }
    public func getDisableMotionActivityUpdates() -> Bool { cache["disableMotionActivityUpdates"] as? Bool ?? false }
    public func getDisableStopDetection() -> Bool { cache["disableStopDetection"] as? Bool ?? false }
    public func getActivityRecognitionInterval() -> Int { (cache["activityRecognitionInterval"] as? NSNumber)?.intValue ?? 10000 }
    public func getMinimumActivityRecognitionConfidence() -> Int { (cache["minimumActivityRecognitionConfidence"] as? NSNumber)?.intValue ?? 75 }
    public func getStopOnStationary() -> Bool { cache["stopOnStationary"] as? Bool ?? false }
    public func getTriggerActivities() -> String { cache["triggerActivities"] as? String ?? "" }
    
    // Speed Motion Config
    public func getMotionDetectionMode() -> MotionDetectionMode {
        if let val = cache["motionDetectionMode"] as? Int, let mode = MotionDetectionMode(rawValue: val) {
            return mode
        }
        return .activity
    }
    public func getSpeedMovingThreshold() -> Double { cache["speedMovingThreshold"] as? Double ?? 1.5 }
    public func getSpeedStationaryDelay() -> Int { (cache["speedStationaryDelay"] as? NSNumber)?.intValue ?? 180 }
    public func getStationaryTrackingMode() -> StationaryTrackingMode {
        if let val = cache["stationaryTrackingMode"] as? Int, let mode = StationaryTrackingMode(rawValue: val) {
            return mode
        }
        return .periodic
    }
    public func getStationaryPeriodicInterval() -> Int { (cache["stationaryPeriodicInterval"] as? NSNumber)?.intValue ?? 120 }
    public func getStationaryPeriodicAccuracy() -> Int { (cache["stationaryPeriodicAccuracy"] as? NSNumber)?.intValue ?? 1 }
    public func getSpeedWakeConfirmCount() -> Int { (cache["speedWakeConfirmCount"] as? NSNumber)?.intValue ?? 1 }

    /// Shake threshold (gravity-subtracted magnitude).
    ///
    /// Dart sends this value in m/s². We divide by 9.81 to convert to g-force.
    public func getShakeThreshold() -> Double {
        if let val = cache["shakeThreshold"] as? Double {
            return val / 9.81
        }
        return 0.35
    }
    /// Still threshold (gravity-subtracted magnitude).
    ///
    /// Dart sends this value in m/s². We divide by 9.81 to convert to g-force.
    public func getStillThreshold() -> Double {
        if let val = cache["stillThreshold"] as? Double {
            return val / 9.81
        }
        return 0.15
    }
    /// Consecutive still samples needed before triggering stillness.
    /// At 10 Hz, 30 samples ≈ 3 seconds of sustained stillness.
    public func getStillSampleCount() -> Int { (cache["stillSampleCount"] as? NSNumber)?.intValue ?? 30 }

    // GeofenceConfig
    public func getGeofenceInitialTriggerEntry() -> Bool { cache["geofenceInitialTriggerEntry"] as? Bool ?? true }
    public func getGeofenceInitialTrigger() -> Bool { cache["geofenceInitialTrigger"] as? Bool ?? true }
    public func getGeofenceModeKnockOut() -> Bool { cache["geofenceModeKnockOut"] as? Bool ?? false }
    public func getGeofenceModeHighAccuracy() -> Bool { cache["geofenceModeHighAccuracy"] as? Bool ?? false }

    // HttpConfig
    public func getUrl() -> String { cache["url"] as? String ?? "" }
    public func getAutoSync() -> Bool { cache["autoSync"] as? Bool ?? true }
    public func getAutoSyncThreshold() -> Int { (cache["autoSyncThreshold"] as? NSNumber)?.intValue ?? 0 }
    public func getAutoSyncDelay() -> Int { (cache["autoSyncDelay"] as? NSNumber)?.intValue ?? 10000 }
    public func getSyncInterval() -> Int { (cache["syncInterval"] as? NSNumber)?.intValue ?? 0 }
    public func getBatchSync() -> Bool { cache["batchSync"] as? Bool ?? false }
    public func getMaxBatchSize() -> Int {
        let value = (cache["maxBatchSize"] as? NSNumber)?.intValue ?? 250
        return value < 0 ? 250 : value
    }
    public func getHttpRootProperty() -> String { cache["httpRootProperty"] as? String ?? "location" }
    public func getHttpHeaders() -> [String: String] {
        if let headers = cache["headers"] as? [String: String] {
            return headers
        }
        // Platform channel may deliver values as [String: Any] — coerce to strings.
        if let headers = cache["headers"] as? [String: Any] {
            return headers.mapValues { "\($0)" }
        }
        return [:]
    }
    public func getHttpMethod() -> String {
        // Dart serializes method as an Int (0 = POST, 1 = PUT).
        if let index = (cache["method"] as? NSNumber)?.intValue {
            return index == 1 ? "PUT" : "POST"
        }
        return cache["method"] as? String ?? "POST"
    }
    public func getHttpTimeout() -> Int { (cache["httpTimeout"] as? NSNumber)?.intValue ?? 60000 }
    public func getLocationsOrderDirection() -> Int { (cache["locationsOrderDirection"] as? NSNumber)?.intValue ?? 0 }
    public func getDisableAutoSyncOnCellular() -> Bool { cache["disableAutoSyncOnCellular"] as? Bool ?? false }
    public func getMaxRetries() -> Int { (cache["maxRetries"] as? NSNumber)?.intValue ?? 10 }
    public func getRetryBackoffBase() -> Int { (cache["retryBackoffBase"] as? NSNumber)?.intValue ?? 1000 }
    public func getRetryBackoffCap() -> Int { (cache["retryBackoffCap"] as? NSNumber)?.intValue ?? 300000 }
    public func getEnableDeltaCompression() -> Bool { cache["enableDeltaCompression"] as? Bool ?? false }
    // Default must match the Dart HttpConfig default (5), not 6 (Issue #137).
    public func getDeltaCoordinatePrecision() -> Int { (cache["deltaCoordinatePrecision"] as? NSNumber)?.intValue ?? 5 }
    public func getSyncTelematics() -> Bool { cache["syncTelematics"] as? Bool ?? false }
    public func getTelematicsUrl() -> String { cache["telematicsUrl"] as? String ?? "" }
    
    public func getHttpParams() -> [String: Any] {
        if let params = cache["params"] as? [String: Any] {
            return params
        }
        return [:]
    }

    public func getHttpExtras() -> [String: Any] {
        if let extras = cache["httpExtras"] as? [String: Any] {
            return extras
        }
        if let extras = cache["extras"] as? [String: Any] {
            return extras
        }
        return [:]
    }

    // PersistenceConfig
    public func getPersistMode() -> Int { (cache["persistMode"] as? NSNumber)?.intValue ?? 0 }
    public func getLocationTemplate() -> String? { cache["locationTemplate"] as? String }
    public func getGeofenceTemplate() -> String? { cache["geofenceTemplate"] as? String }
    public func getDisableProviderChangeRecord() -> Bool { cache["disableProviderChangeRecord"] as? Bool ?? false }
    public func getPersistenceExtras() -> [String: Any] { cache["persistenceExtras"] as? [String: Any] ?? cache["extras"] as? [String: Any] ?? [:] }

    // LoggerConfig
    public func getLogMaxDays() -> Int { (cache["logMaxDays"] as? NSNumber)?.intValue ?? 3 }

    // AuditConfig (Enterprise)
    public func getAuditEnabled() -> Bool {
        if let audit = cache["audit"] as? [String: Any], let enabled = audit["enabled"] as? Bool { return enabled }
        return cache["auditEnabled"] as? Bool ?? cache["enabled"] as? Bool ?? false
    }
    public func getAuditHashAlgorithm() -> String {
        if let audit = cache["audit"] as? [String: Any], let alg = audit["hashAlgorithm"] as? String { return alg }
        return cache["hashAlgorithm"] as? String ?? "SHA-256"
    }
    public func getAuditIncludeExtrasInHash() -> Bool {
        if let audit = cache["audit"] as? [String: Any], let inc = audit["includeExtrasInHash"] as? Bool { return inc }
        return cache["includeExtrasInHash"] as? Bool ?? false
    }

    // PrivacyZoneConfig (Enterprise)
    public func getPrivacyZoneEnabled() -> Bool {
        if let pz = cache["privacyZone"] as? [String: Any], let enabled = pz["enabled"] as? Bool { return enabled }
        return cache["privacyZoneEnabled"] as? Bool ?? false
    }

    // SecurityConfig (Enterprise)
    public func getEncryptDatabase() -> Bool {
        if let sec = cache["security"] as? [String: Any], let enc = sec["encryptDatabase"] as? Bool { return enc }
        return cache["encryptDatabase"] as? Bool ?? false
    }
    public func getEncryptionKey() -> String? {
        if let sec = cache["security"] as? [String: Any], let key = sec["encryptionKey"] as? String { return key }
        return cache["encryptionKey"] as? String
    }

    // AttestationConfig (Enterprise)
    public func getAttestationEnabled() -> Bool {
        if let att = cache["attestation"] as? [String: Any], let enabled = att["enabled"] as? Bool { return enabled }
        return cache["attestationEnabled"] as? Bool ?? false
    }
    public func getAttestationRefreshInterval() -> Int {
        if let att = cache["attestation"] as? [String: Any], let interval = (att["refreshInterval"] as? NSNumber)?.intValue { return interval }
        return (cache["attestationRefreshInterval"] as? NSNumber)?.intValue ?? 3600
    }
    public func getAttestationVerificationUrl() -> String? {
        if let att = cache["attestation"] as? [String: Any], let url = att["verificationUrl"] as? String { return url }
        return cache["attestationVerificationUrl"] as? String
    }

    // RemoteConfig (Enterprise)
    public func getRemoteConfigUrl() -> String? {
        let url = cache["remoteConfigUrl"] as? String
        return (url?.isEmpty == false) ? url : nil
    }
    public func getRemoteConfigHeaders() -> [String: String] {
        cache["remoteConfigHeaders"] as? [String: String] ?? [:]
    }
    public func getRemoteConfigTimeout() -> Int { (cache["remoteConfigTimeout"] as? NSNumber)?.intValue ?? 30000 }
    public func getRemoteConfigRefreshInterval() -> Int { (cache["remoteConfigRefreshInterval"] as? NSNumber)?.intValue ?? 3600 }

    // MARK: - Battery Budget
    public func getBatteryBudgetPerHour() -> Double { cache["batteryBudgetPerHour"] as? Double ?? 0.0 }

    // MARK: - Telematics / classifier / impact (3.3.0)
    public func getEnableDrivingEvents() -> Bool { cache["enableDrivingEvents"] as? Bool ?? false }
    public func getHarshBrakingG() -> Double { cache["harshBrakingG"] as? Double ?? 0.40 }
    public func getHarshAccelerationG() -> Double { cache["harshAccelerationG"] as? Double ?? 0.35 }
    public func getHarshCorneringG() -> Double { cache["harshCorneringG"] as? Double ?? 0.40 }
    public func getSpeedLimitKmh() -> Double { cache["speedLimitKmh"] as? Double ?? 0.0 }
    public func getSpeedingToleranceKmh() -> Double { cache["speedingToleranceKmh"] as? Double ?? 5.0 }
    public func getSpeedingMinDurationMs() -> Int64 { (cache["speedingMinDurationMs"] as? NSNumber)?.int64Value ?? 3000 }
    public func getMinSpeedForEventsKmh() -> Double { cache["minSpeedForEventsKmh"] as? Double ?? 5.0 }
    public func getEventDebounceMs() -> Int64 { (cache["eventDebounceMs"] as? NSNumber)?.int64Value ?? 2000 }

    public func getEnableFusedClassifier() -> Bool { cache["enableFusedClassifier"] as? Bool ?? false }
    public func getFusedClassifierAuthoritative() -> Bool { cache["fusedClassifierAuthoritative"] as? Bool ?? false }
    public func getModeSwitchDwellMs() -> Int64 { (cache["modeSwitchDwellMs"] as? NSNumber)?.int64Value ?? 8000 }
    public func getMinModeConfidence() -> Double { cache["minModeConfidence"] as? Double ?? 0.6 }

    public func getEnableCrashDetection() -> Bool { cache["enableCrashDetection"] as? Bool ?? false }
    public func getEnableFallDetection() -> Bool { cache["enableFallDetection"] as? Bool ?? false }
    public func getCrashGThreshold() -> Double { cache["crashGThreshold"] as? Double ?? 2.0 }
    public func getCrashMinSpeedKmh() -> Double { cache["crashMinSpeedKmh"] as? Double ?? 25.0 }
    public func getFallGThreshold() -> Double { cache["fallGThreshold"] as? Double ?? 2.5 }
    public func getConfirmWindowMs() -> Int64 { (cache["confirmWindowMs"] as? NSNumber)?.int64Value ?? 15000 }
    public func getMinImpactConfidence() -> Double { cache["minImpactConfidence"] as? Double ?? 0.6 }

    // #183 crash ML model (opt-in). URL/sha of the encrypted model + the
    // probability threshold; empty URL ⇒ pure rule engine.
    public func getCrashModelUrl() -> String? { (cache["crashModelUrl"] as? String).flatMap { $0.isEmpty ? nil : $0 } }
    public func getCrashModelSha256() -> String? { (cache["crashModelSha256"] as? String).flatMap { $0.isEmpty ? nil : $0 } }
    public func getCrashModelThreshold() -> Double { cache["crashModelThreshold"] as? Double ?? 0.5 }
    // Licensing unlock: when set, the SDK POSTs the license to fetch the key + URL.
    public func getCrashModelUnlockUrl() -> String? { (cache["crashModelUnlockUrl"] as? String).flatMap { $0.isEmpty ? nil : $0 } }
    public func getCrashModelLicenseKey() -> String? { (cache["crashModelLicenseKey"] as? String).flatMap { $0.isEmpty ? nil : $0 } }

    // MARK: - SSL Pinning

    public func getSslPinningCertificates() -> [String] {
        if let certs = cache["sslPinningCertificates"] as? [String] {
            return certs
        }
        return []
    }

    public func getSslPinningFingerprints() -> [String] {
        if let fps = cache["sslPinningFingerprints"] as? [String] {
            return fps
        }
        return []
    }

    // MARK: - Dynamic Headers (volatile — not persisted)

    private var dynamicHeaders: [String: String] = [:]

    public func setDynamicHeaders(_ headers: [String: String]) {
        dynamicHeaders = headers
    }

    public func getDynamicHeaders() -> [String: String] { return dynamicHeaders }

    /// Merged headers: static config headers + dynamic headers (dynamic wins).
    public func getMergedHttpHeaders() -> [String: String] {
        let staticHeaders = getHttpHeaders()
        if dynamicHeaders.isEmpty { return staticHeaders }
        return staticHeaders.merging(dynamicHeaders) { _, new in new }
    }

    // MARK: - Route Context (volatile — not persisted)

    private var routeContext: [String: Any]? = nil

    public func setRouteContext(_ context: [String: Any]) {
        routeContext = context
    }

    public func clearRouteContext() {
        routeContext = nil
    }

    public func getRouteContext() -> [String: Any]? { return routeContext }

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
            "preventSuspend": false,
            "useBackgroundActivitySession": false,
            "debug": false,
            "logLevel": 5,
            "stopOnTerminate": true,
            "startOnBoot": false,
            "heartbeatInterval": 60,
            "schedule": [] as [String],
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
            "autoSyncDelay": 10000,
            "batchSync": false,
            "maxBatchSize": -1,
            "httpRootProperty": "location",
            "headers": [:] as [String: String],
            "params": [:] as [String: Any],
            "extras": [:] as [String: Any],
            "method": "POST",
            "httpTimeout": 60000,
            "locationsOrderDirection": 0,
            "disableAutoSyncOnCellular": false,
            "persistMode": 0,
            "maxDaysToPersist": -1,
            "maxRecordsToPersist": -1,
            "disableProviderChangeRecord": false,
            "logMaxDays": 3,
        ]
    }
}
