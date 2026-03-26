import XCTest
@testable import TraceletSDK

/// Unit tests for ``TraceletConfig`` and all sub-config structs.
///
/// Tests cover:
/// - Default values for every config group
/// - `toMap()` serialization produces the correct keys and values
/// - Non-default values round-trip through `toMap()`
/// - Enum raw-value mappings
final class TraceletConfigTests: XCTestCase {

    // MARK: - TraceletConfig (top-level)

    func testDefaultConfigContainsAllSectionKeys() {
        let map = TraceletConfig().toMap()
        let expected = [
            "geo", "app", "http", "logger", "motion",
            "geofence", "persistence", "audit", "privacyZone",
            "security", "attestation",
        ]
        for key in expected {
            XCTAssertNotNil(map[key], "Missing key: \(key)")
        }
        XCTAssertEqual(map.count, expected.count)
    }

    // MARK: - GeoConfig

    func testDefaultGeoConfigToMap() {
        let map = TraceletGeoConfig().toMap()
        XCTAssertEqual(map["desiredAccuracy"] as? Int, TraceletDesiredAccuracy.high.rawValue)
        XCTAssertEqual(map["distanceFilter"] as? Double, 10.0)
        XCTAssertEqual(map["locationUpdateInterval"] as? Int, 1000)
        XCTAssertEqual(map["fastestLocationUpdateInterval"] as? Int, 500)
        XCTAssertEqual(map["stationaryRadius"] as? Double, 25.0)
        XCTAssertEqual(map["locationTimeout"] as? Int, 60)
        XCTAssertEqual(map["activityType"] as? Int, TraceletActivityType.other.rawValue)
        XCTAssertEqual(map["disableElasticity"] as? Bool, false)
        XCTAssertEqual(map["elasticityMultiplier"] as? Double, 1.0)
        XCTAssertEqual(map["stopAfterElapsedMinutes"] as? Int, -1)
        XCTAssertEqual(map["deferTime"] as? Int, 0)
        XCTAssertEqual(map["allowIdenticalLocations"] as? Bool, false)
        XCTAssertEqual(map["geofenceModeHighAccuracy"] as? Bool, false)
        XCTAssertEqual(map["maxMonitoredGeofences"] as? Int, -1)
        XCTAssertEqual(map["useSignificantChangesOnly"] as? Bool, false)
        XCTAssertEqual(map["showsBackgroundLocationIndicator"] as? Bool, false)
        XCTAssertEqual(map["pausesLocationUpdatesAutomatically"] as? Bool, false)
        XCTAssertEqual(map["locationAuthorizationRequest"] as? String, "Always")
        XCTAssertEqual(map["disableLocationAuthorizationAlert"] as? Bool, false)
        XCTAssertEqual(map["enableTimestampMeta"] as? Bool, false)
        XCTAssertEqual(map["enableAdaptiveMode"] as? Bool, false)
        XCTAssertEqual(map["periodicLocationInterval"] as? Int, 900)
        XCTAssertEqual(map["periodicDesiredAccuracy"] as? Int, TraceletDesiredAccuracy.medium.rawValue)
        XCTAssertEqual(map["periodicUseForegroundService"] as? Bool, false)
        XCTAssertEqual(map["periodicUseExactAlarms"] as? Bool, false)
        XCTAssertEqual(map["enableSparseUpdates"] as? Bool, false)
        XCTAssertEqual(map["sparseDistanceThreshold"] as? Double, 50.0)
        XCTAssertEqual(map["sparseMaxIdleSeconds"] as? Int, 300)
        XCTAssertEqual(map["enableDeadReckoning"] as? Bool, false)
        XCTAssertEqual(map["deadReckoningActivationDelay"] as? Int, 10)
        XCTAssertEqual(map["deadReckoningMaxDuration"] as? Int, 120)
        XCTAssertEqual(map["batteryBudgetPerHour"] as? Double, 0.0)
        XCTAssertNil(map["filter"])
    }

    func testGeoConfigWithFilterIncludesFilterInMap() {
        let config = TraceletGeoConfig(
            desiredAccuracy: .low,
            distanceFilter: 50.0,
            filter: TraceletLocationFilter(
                policy: .ignore,
                maxImpliedSpeed: 200,
                trackingAccuracyThreshold: 100,
                useKalmanFilter: true
            )
        )
        let map = config.toMap()
        XCTAssertEqual(map["desiredAccuracy"] as? Int, TraceletDesiredAccuracy.low.rawValue)
        XCTAssertEqual(map["distanceFilter"] as? Double, 50.0)

        let filterMap = map["filter"] as? [String: Any]
        XCTAssertNotNil(filterMap)
        XCTAssertEqual(filterMap?["policy"] as? Int, TraceletLocationFilterPolicy.ignore.rawValue)
        XCTAssertEqual(filterMap?["maxImpliedSpeed"] as? Int, 200)
        XCTAssertEqual(filterMap?["trackingAccuracyThreshold"] as? Int, 100)
        XCTAssertEqual(filterMap?["useKalmanFilter"] as? Bool, true)
    }

    func testGeoConfigWhenInUseAuthorization() {
        let config = TraceletGeoConfig(locationAuthorizationRequest: .whenInUse)
        XCTAssertEqual(config.toMap()["locationAuthorizationRequest"] as? String, "WhenInUse")
    }

    // MARK: - LocationFilter

    func testDefaultLocationFilterToMap() {
        let map = TraceletLocationFilter().toMap()
        XCTAssertEqual(map["policy"] as? Int, TraceletLocationFilterPolicy.adjust.rawValue)
        XCTAssertEqual(map["maxImpliedSpeed"] as? Int, 0)
        XCTAssertEqual(map["odometerAccuracyThreshold"] as? Int, 0)
        XCTAssertEqual(map["trackingAccuracyThreshold"] as? Int, 0)
        XCTAssertEqual(map["useKalmanFilter"] as? Bool, false)
        XCTAssertEqual(map["rejectMockLocations"] as? Bool, false)
        XCTAssertEqual(map["mockDetectionLevel"] as? Int, TraceletMockDetectionLevel.disabled.rawValue)
    }

    func testLocationFilterCustomValues() {
        let filter = TraceletLocationFilter(
            policy: .discard,
            maxImpliedSpeed: 120,
            odometerAccuracyThreshold: 50,
            trackingAccuracyThreshold: 200,
            useKalmanFilter: true,
            rejectMockLocations: true,
            mockDetectionLevel: .heuristic
        )
        let map = filter.toMap()
        XCTAssertEqual(map["policy"] as? Int, TraceletLocationFilterPolicy.discard.rawValue)
        XCTAssertEqual(map["maxImpliedSpeed"] as? Int, 120)
        XCTAssertEqual(map["odometerAccuracyThreshold"] as? Int, 50)
        XCTAssertEqual(map["trackingAccuracyThreshold"] as? Int, 200)
        XCTAssertEqual(map["useKalmanFilter"] as? Bool, true)
        XCTAssertEqual(map["rejectMockLocations"] as? Bool, true)
        XCTAssertEqual(map["mockDetectionLevel"] as? Int, TraceletMockDetectionLevel.heuristic.rawValue)
    }

    // MARK: - AppConfig

    func testDefaultAppConfigToMap() {
        let map = TraceletAppConfig().toMap()
        XCTAssertEqual(map["stopOnTerminate"] as? Bool, true)
        XCTAssertEqual(map["startOnBoot"] as? Bool, false)
        XCTAssertEqual(map["heartbeatInterval"] as? Int, 60)
        XCTAssertEqual((map["schedule"] as? [String])?.count, 0)
        XCTAssertEqual(map["scheduleUseAlarmManager"] as? Bool, false)
        XCTAssertEqual(map["preventSuspend"] as? Bool, false)
        XCTAssertNil(map["remoteConfigUrl"])
        XCTAssertEqual(map["remoteConfigTimeout"] as? Int, 10000)
        XCTAssertEqual(map["remoteConfigRefreshInterval"] as? Int, 0)
        XCTAssertNotNil(map["foregroundService"])
    }

    func testAppConfigCustomValues() {
        let config = TraceletAppConfig(
            stopOnTerminate: false,
            startOnBoot: true,
            heartbeatInterval: 120,
            schedule: ["1-7 09:00-17:00"],
            preventSuspend: true,
            remoteConfigUrl: "https://example.com/config"
        )
        let map = config.toMap()
        XCTAssertEqual(map["stopOnTerminate"] as? Bool, false)
        XCTAssertEqual(map["startOnBoot"] as? Bool, true)
        XCTAssertEqual(map["heartbeatInterval"] as? Int, 120)
        XCTAssertEqual(map["schedule"] as? [String], ["1-7 09:00-17:00"])
        XCTAssertEqual(map["preventSuspend"] as? Bool, true)
        XCTAssertEqual(map["remoteConfigUrl"] as? String, "https://example.com/config")
    }

    // MARK: - ForegroundServiceConfig

    func testDefaultForegroundServiceConfigToMap() {
        let map = TraceletForegroundServiceConfig().toMap()
        XCTAssertEqual(map["enabled"] as? Bool, true)
        XCTAssertEqual(map["channelId"] as? String, "tracelet_channel")
        XCTAssertEqual(map["channelName"] as? String, "Tracelet")
        XCTAssertEqual(map["notificationTitle"] as? String, "Tracelet")
        XCTAssertEqual(map["notificationText"] as? String, "Tracking location in background")
        XCTAssertNil(map["notificationColor"])
        XCTAssertNil(map["notificationSmallIcon"])
        XCTAssertNil(map["notificationLargeIcon"])
        XCTAssertEqual(map["notificationPriority"] as? Int, TraceletNotificationPriority.default.rawValue)
        XCTAssertEqual(map["notificationOngoing"] as? Bool, true)
        XCTAssertEqual((map["actions"] as? [String])?.count, 0)
    }

    func testForegroundServiceConfigCustomValues() {
        let config = TraceletForegroundServiceConfig(
            notificationTitle: "Fleet",
            notificationText: "Tracking...",
            notificationColor: "#FF0000",
            notificationSmallIcon: "ic_small",
            notificationLargeIcon: "ic_large",
            notificationPriority: .high
        )
        let map = config.toMap()
        XCTAssertEqual(map["notificationTitle"] as? String, "Fleet")
        XCTAssertEqual(map["notificationText"] as? String, "Tracking...")
        XCTAssertEqual(map["notificationColor"] as? String, "#FF0000")
        XCTAssertEqual(map["notificationSmallIcon"] as? String, "ic_small")
        XCTAssertEqual(map["notificationLargeIcon"] as? String, "ic_large")
        XCTAssertEqual(map["notificationPriority"] as? Int, TraceletNotificationPriority.high.rawValue)
    }

    // MARK: - HttpConfig

    func testDefaultHttpConfigToMap() {
        let map = TraceletHttpConfig().toMap()
        XCTAssertNil(map["url"])
        XCTAssertEqual(map["method"] as? Int, TraceletHttpMethod.post.rawValue)
        XCTAssertEqual(map["httpRootProperty"] as? String, "location")
        XCTAssertEqual(map["batchSync"] as? Bool, false)
        XCTAssertEqual(map["maxBatchSize"] as? Int, 250)
        XCTAssertEqual(map["autoSync"] as? Bool, true)
        XCTAssertEqual(map["autoSyncThreshold"] as? Int, 0)
        XCTAssertEqual(map["httpTimeout"] as? Int, 60000)
        XCTAssertEqual(map["locationsOrderDirection"] as? Int, TraceletLocationOrder.asc.rawValue)
        XCTAssertEqual(map["disableAutoSyncOnCellular"] as? Bool, false)
        XCTAssertEqual(map["maxRetries"] as? Int, 10)
        XCTAssertEqual(map["retryBackoffBase"] as? Int, 1000)
        XCTAssertEqual(map["retryBackoffCap"] as? Int, 300000)
        XCTAssertEqual(map["enableDeltaCompression"] as? Bool, false)
        XCTAssertEqual(map["deltaCoordinatePrecision"] as? Int, 6)
        XCTAssertEqual((map["sslPinningCertificates"] as? [String])?.count, 0)
        XCTAssertEqual((map["sslPinningFingerprints"] as? [String])?.count, 0)
    }

    func testHttpConfigCustomValues() {
        let config = TraceletHttpConfig(
            url: "https://api.example.com/locations",
            method: .put,
            headers: ["Authorization": "Bearer token"],
            batchSync: true,
            maxBatchSize: 100
        )
        let map = config.toMap()
        XCTAssertEqual(map["url"] as? String, "https://api.example.com/locations")
        XCTAssertEqual(map["method"] as? Int, TraceletHttpMethod.put.rawValue)
        let headers = map["headers"] as? [String: String]
        XCTAssertEqual(headers?["Authorization"], "Bearer token")
        XCTAssertEqual(map["batchSync"] as? Bool, true)
        XCTAssertEqual(map["maxBatchSize"] as? Int, 100)
    }

    // MARK: - LoggerConfig

    func testDefaultLoggerConfigToMap() {
        let map = TraceletLoggerConfig().toMap()
        XCTAssertEqual(map["logLevel"] as? Int, TraceletLogLevel.info.rawValue)
        XCTAssertEqual(map["logMaxDays"] as? Int, 3)
        XCTAssertEqual(map["debug"] as? Bool, false)
    }

    func testLoggerConfigCustomValues() {
        let config = TraceletLoggerConfig(logLevel: .verbose, logMaxDays: 7, debug: true)
        let map = config.toMap()
        XCTAssertEqual(map["logLevel"] as? Int, TraceletLogLevel.verbose.rawValue)
        XCTAssertEqual(map["logMaxDays"] as? Int, 7)
        XCTAssertEqual(map["debug"] as? Bool, true)
    }

    // MARK: - MotionConfig

    func testDefaultMotionConfigToMap() {
        let map = TraceletMotionConfig().toMap()
        XCTAssertEqual(map["stopTimeout"] as? Int, 5)
        XCTAssertEqual(map["motionTriggerDelay"] as? Int, 0)
        XCTAssertEqual(map["disableMotionActivityUpdates"] as? Bool, false)
        XCTAssertEqual(map["isMoving"] as? Bool, false)
        XCTAssertEqual(map["activityRecognitionInterval"] as? Int, 10000)
        XCTAssertEqual(map["minimumActivityRecognitionConfidence"] as? Int, 75)
        XCTAssertEqual(map["disableStopDetection"] as? Bool, false)
        XCTAssertEqual(map["stopDetectionDelay"] as? Int, 0)
        XCTAssertEqual(map["stopOnStationary"] as? Bool, false)
        XCTAssertEqual((map["triggerActivities"] as? [String])?.count, 0)
        XCTAssertEqual(map["shakeThreshold"] as? Double, 2.5)
        XCTAssertEqual(map["stillThreshold"] as? Double, 0.4)
        XCTAssertEqual(map["stillSampleCount"] as? Int, 25)
    }

    func testMotionConfigWithTriggerActivities() {
        let config = TraceletMotionConfig(
            stopTimeout: 10,
            disableMotionActivityUpdates: true,
            triggerActivities: [.onFoot, .inVehicle]
        )
        let map = config.toMap()
        XCTAssertEqual(map["stopTimeout"] as? Int, 10)
        XCTAssertEqual(map["disableMotionActivityUpdates"] as? Bool, true)
        let activities = map["triggerActivities"] as? [String] ?? []
        XCTAssertTrue(activities.contains("on_foot"))
        XCTAssertTrue(activities.contains("in_vehicle"))
    }

    // MARK: - GeofenceConfig

    func testDefaultGeofenceConfigToMap() {
        let map = TraceletGeofenceConfig().toMap()
        XCTAssertEqual(map["geofenceProximityRadius"] as? Int, 1000)
        XCTAssertEqual(map["geofenceInitialTriggerEntry"] as? Bool, true)
        XCTAssertEqual(map["geofenceModeKnockOut"] as? Bool, false)
    }

    func testGeofenceConfigCustomValues() {
        let config = TraceletGeofenceConfig(
            geofenceProximityRadius: 5000,
            geofenceInitialTriggerEntry: false,
            geofenceModeKnockOut: true
        )
        let map = config.toMap()
        XCTAssertEqual(map["geofenceProximityRadius"] as? Int, 5000)
        XCTAssertEqual(map["geofenceInitialTriggerEntry"] as? Bool, false)
        XCTAssertEqual(map["geofenceModeKnockOut"] as? Bool, true)
    }

    // MARK: - PersistenceConfig

    func testDefaultPersistenceConfigToMap() {
        let map = TraceletPersistenceConfig().toMap()
        XCTAssertEqual(map["persistMode"] as? Int, TraceletPersistMode.all.rawValue)
        XCTAssertEqual(map["maxDaysToPersist"] as? Int, -1)
        XCTAssertEqual(map["maxRecordsToPersist"] as? Int, -1)
        XCTAssertNil(map["locationTemplate"])
        XCTAssertNil(map["geofenceTemplate"])
        XCTAssertEqual(map["disableProviderChangeRecord"] as? Bool, false)
    }

    func testPersistenceConfigCustomValues() {
        let config = TraceletPersistenceConfig(
            persistMode: .location,
            maxDaysToPersist: 14,
            maxRecordsToPersist: 5000,
            locationTemplate: "{\"lat\":<%= latitude %>,\"lng\":<%= longitude %>}"
        )
        let map = config.toMap()
        XCTAssertEqual(map["persistMode"] as? Int, TraceletPersistMode.location.rawValue)
        XCTAssertEqual(map["maxDaysToPersist"] as? Int, 14)
        XCTAssertEqual(map["maxRecordsToPersist"] as? Int, 5000)
        XCTAssertEqual(map["locationTemplate"] as? String, "{\"lat\":<%= latitude %>,\"lng\":<%= longitude %>}")
    }

    // MARK: - AuditConfig

    func testDefaultAuditConfigToMap() {
        let map = TraceletAuditConfig().toMap()
        XCTAssertEqual(map["enabled"] as? Bool, false)
        XCTAssertEqual(map["hashAlgorithm"] as? Int, TraceletHashAlgorithm.sha256.rawValue)
    }

    func testAuditConfigEnabledWithSHA512() {
        let config = TraceletAuditConfig(enabled: true, hashAlgorithm: .sha512)
        let map = config.toMap()
        XCTAssertEqual(map["enabled"] as? Bool, true)
        XCTAssertEqual(map["hashAlgorithm"] as? Int, TraceletHashAlgorithm.sha512.rawValue)
    }

    // MARK: - PrivacyZoneConfig

    func testDefaultPrivacyZoneConfigToMap() {
        let map = TraceletPrivacyZoneConfig().toMap()
        XCTAssertEqual(map["enabled"] as? Bool, false)
    }

    // MARK: - SecurityConfig

    func testDefaultSecurityConfigToMap() {
        let map = TraceletSecurityConfig().toMap()
        XCTAssertEqual(map["encryptDatabase"] as? Bool, false)
    }

    func testSecurityConfigEnabled() {
        XCTAssertEqual(
            TraceletSecurityConfig(encryptDatabase: true).toMap()["encryptDatabase"] as? Bool,
            true
        )
    }

    // MARK: - AttestationConfig

    func testDefaultAttestationConfigToMap() {
        let map = TraceletAttestationConfig().toMap()
        XCTAssertEqual(map["enabled"] as? Bool, false)
        XCTAssertEqual(map["refreshInterval"] as? Int, 3600)
    }

    func testAttestationConfigCustom() {
        let config = TraceletAttestationConfig(enabled: true, refreshInterval: 7200)
        let map = config.toMap()
        XCTAssertEqual(map["enabled"] as? Bool, true)
        XCTAssertEqual(map["refreshInterval"] as? Int, 7200)
    }

    // MARK: - Enum raw values

    func testDesiredAccuracyRawValues() {
        XCTAssertEqual(TraceletDesiredAccuracy.high.rawValue, 0)
        XCTAssertEqual(TraceletDesiredAccuracy.medium.rawValue, 1)
        XCTAssertEqual(TraceletDesiredAccuracy.low.rawValue, 2)
    }

    func testLogLevelRawValues() {
        XCTAssertEqual(TraceletLogLevel.verbose.rawValue, 0)
        XCTAssertEqual(TraceletLogLevel.debug.rawValue, 1)
        XCTAssertEqual(TraceletLogLevel.info.rawValue, 2)
        XCTAssertEqual(TraceletLogLevel.warn.rawValue, 3)
        XCTAssertEqual(TraceletLogLevel.error.rawValue, 4)
    }

    func testHttpMethodRawValues() {
        XCTAssertEqual(TraceletHttpMethod.post.rawValue, 0)
        XCTAssertEqual(TraceletHttpMethod.put.rawValue, 1)
    }

    func testPersistModeRawValues() {
        XCTAssertEqual(TraceletPersistMode.all.rawValue, 0)
        XCTAssertEqual(TraceletPersistMode.location.rawValue, 1)
        XCTAssertEqual(TraceletPersistMode.geofence.rawValue, 2)
        XCTAssertEqual(TraceletPersistMode.none.rawValue, 3)
    }

    func testLocationFilterPolicyRawValues() {
        XCTAssertEqual(TraceletLocationFilterPolicy.adjust.rawValue, 0)
        XCTAssertEqual(TraceletLocationFilterPolicy.ignore.rawValue, 1)
        XCTAssertEqual(TraceletLocationFilterPolicy.discard.rawValue, 2)
    }

    func testMockDetectionLevelRawValues() {
        XCTAssertEqual(TraceletMockDetectionLevel.disabled.rawValue, 0)
        XCTAssertEqual(TraceletMockDetectionLevel.basic.rawValue, 1)
        XCTAssertEqual(TraceletMockDetectionLevel.heuristic.rawValue, 2)
    }

    func testActivityTypeRawValues() {
        XCTAssertEqual(TraceletActivityType.other.rawValue, 0)
        XCTAssertEqual(TraceletActivityType.automotiveNavigation.rawValue, 1)
        XCTAssertEqual(TraceletActivityType.fitness.rawValue, 2)
        XCTAssertEqual(TraceletActivityType.otherNavigation.rawValue, 3)
        XCTAssertEqual(TraceletActivityType.airborne.rawValue, 4)
    }

    func testNotificationPriorityRawValues() {
        XCTAssertEqual(TraceletNotificationPriority.min.rawValue, -2)
        XCTAssertEqual(TraceletNotificationPriority.low.rawValue, -1)
        XCTAssertEqual(TraceletNotificationPriority.default.rawValue, 0)
        XCTAssertEqual(TraceletNotificationPriority.high.rawValue, 1)
        XCTAssertEqual(TraceletNotificationPriority.max.rawValue, 2)
    }

    func testLocationOrderRawValues() {
        XCTAssertEqual(TraceletLocationOrder.asc.rawValue, 0)
        XCTAssertEqual(TraceletLocationOrder.desc.rawValue, 1)
    }

    func testMotionActivityTypeRawValues() {
        XCTAssertEqual(TraceletMotionActivityType.still.rawValue, "still")
        XCTAssertEqual(TraceletMotionActivityType.onFoot.rawValue, "on_foot")
        XCTAssertEqual(TraceletMotionActivityType.walking.rawValue, "walking")
        XCTAssertEqual(TraceletMotionActivityType.running.rawValue, "running")
        XCTAssertEqual(TraceletMotionActivityType.onBicycle.rawValue, "on_bicycle")
        XCTAssertEqual(TraceletMotionActivityType.inVehicle.rawValue, "in_vehicle")
        XCTAssertEqual(TraceletMotionActivityType.unknown.rawValue, "unknown")
    }

    func testHashAlgorithmRawValues() {
        XCTAssertEqual(TraceletHashAlgorithm.sha256.rawValue, 0)
        XCTAssertEqual(TraceletHashAlgorithm.sha512.rawValue, 1)
    }

    // MARK: - Full config round-trip

    func testFullConfigWithCustomValuesProducesCorrectNestedMap() {
        let config = TraceletConfig(
            geo: TraceletGeoConfig(
                desiredAccuracy: .low,
                distanceFilter: 50.0,
                filter: TraceletLocationFilter(useKalmanFilter: true)
            ),
            app: TraceletAppConfig(
                stopOnTerminate: false,
                startOnBoot: true,
                foregroundService: TraceletForegroundServiceConfig(
                    notificationTitle: "Test"
                )
            ),
            http: TraceletHttpConfig(
                url: "https://api.example.com/tracks",
                batchSync: true
            ),
            logger: TraceletLoggerConfig(logLevel: .verbose, debug: true),
            motion: TraceletMotionConfig(stopTimeout: 10),
            geofence: TraceletGeofenceConfig(geofenceProximityRadius: 5000),
            persistence: TraceletPersistenceConfig(maxDaysToPersist: 7),
            audit: TraceletAuditConfig(enabled: true),
            privacyZone: TraceletPrivacyZoneConfig(enabled: true),
            security: TraceletSecurityConfig(encryptDatabase: true),
            attestation: TraceletAttestationConfig(enabled: true, refreshInterval: 1800)
        )

        let map = config.toMap()

        // Verify nested section maps
        let geoMap = map["geo"] as? [String: Any]
        XCTAssertEqual(geoMap?["desiredAccuracy"] as? Int, TraceletDesiredAccuracy.low.rawValue)
        XCTAssertEqual(geoMap?["distanceFilter"] as? Double, 50.0)
        XCTAssertNotNil(geoMap?["filter"])

        let appMap = map["app"] as? [String: Any]
        XCTAssertEqual(appMap?["stopOnTerminate"] as? Bool, false)
        XCTAssertEqual(appMap?["startOnBoot"] as? Bool, true)

        let httpMap = map["http"] as? [String: Any]
        XCTAssertEqual(httpMap?["url"] as? String, "https://api.example.com/tracks")
        XCTAssertEqual(httpMap?["batchSync"] as? Bool, true)

        let loggerMap = map["logger"] as? [String: Any]
        XCTAssertEqual(loggerMap?["debug"] as? Bool, true)
        XCTAssertEqual(loggerMap?["logLevel"] as? Int, TraceletLogLevel.verbose.rawValue)

        let motionMap = map["motion"] as? [String: Any]
        XCTAssertEqual(motionMap?["stopTimeout"] as? Int, 10)

        let geofenceMap = map["geofence"] as? [String: Any]
        XCTAssertEqual(geofenceMap?["geofenceProximityRadius"] as? Int, 5000)

        let persistenceMap = map["persistence"] as? [String: Any]
        XCTAssertEqual(persistenceMap?["maxDaysToPersist"] as? Int, 7)

        let auditMap = map["audit"] as? [String: Any]
        XCTAssertEqual(auditMap?["enabled"] as? Bool, true)

        let privacyMap = map["privacyZone"] as? [String: Any]
        XCTAssertEqual(privacyMap?["enabled"] as? Bool, true)

        let securityMap = map["security"] as? [String: Any]
        XCTAssertEqual(securityMap?["encryptDatabase"] as? Bool, true)

        let attestMap = map["attestation"] as? [String: Any]
        XCTAssertEqual(attestMap?["enabled"] as? Bool, true)
        XCTAssertEqual(attestMap?["refreshInterval"] as? Int, 1800)
    }

    // MARK: - fromMap() round-trip tests

    func testGeoConfigFromMapRoundTrip() {
        let original = TraceletGeoConfig(
            desiredAccuracy: .low,
            distanceFilter: 42.0,
            locationUpdateInterval: 2000,
            fastestLocationUpdateInterval: 1000,
            stationaryRadius: 50.0,
            locationTimeout: 120,
            activityType: .fitness,
            disableElasticity: true,
            elasticityMultiplier: 2.5,
            stopAfterElapsedMinutes: 30,
            deferTime: 5,
            allowIdenticalLocations: true,
            geofenceModeHighAccuracy: true,
            maxMonitoredGeofences: 20,
            useSignificantChangesOnly: true,
            showsBackgroundLocationIndicator: true,
            pausesLocationUpdatesAutomatically: true,
            locationAuthorizationRequest: .whenInUse,
            disableLocationAuthorizationAlert: true,
            enableTimestampMeta: true,
            enableAdaptiveMode: true,
            periodicLocationInterval: 300,
            periodicDesiredAccuracy: .low,
            periodicUseForegroundService: true,
            periodicUseExactAlarms: true,
            enableSparseUpdates: true,
            sparseDistanceThreshold: 100.0,
            sparseMaxIdleSeconds: 600,
            enableDeadReckoning: true,
            deadReckoningActivationDelay: 20,
            deadReckoningMaxDuration: 240,
            batteryBudgetPerHour: 5.0,
            filter: .init(
                policy: .discard,
                maxImpliedSpeed: 120,
                odometerAccuracyThreshold: 50,
                trackingAccuracyThreshold: 200,
                useKalmanFilter: true,
                rejectMockLocations: true,
                mockDetectionLevel: .heuristic
            )
        )
        let restored = TraceletGeoConfig.fromMap(original.toMap())
        XCTAssertEqual(restored.desiredAccuracy, original.desiredAccuracy)
        XCTAssertEqual(restored.distanceFilter, original.distanceFilter)
        XCTAssertEqual(restored.locationUpdateInterval, original.locationUpdateInterval)
        XCTAssertEqual(restored.disableElasticity, original.disableElasticity)
        XCTAssertEqual(restored.locationAuthorizationRequest, original.locationAuthorizationRequest)
        XCTAssertEqual(restored.periodicDesiredAccuracy, original.periodicDesiredAccuracy)
        XCTAssertEqual(restored.batteryBudgetPerHour, original.batteryBudgetPerHour)
        XCTAssertEqual(restored.filter?.policy, original.filter?.policy)
        XCTAssertEqual(restored.filter?.maxImpliedSpeed, original.filter?.maxImpliedSpeed)
        XCTAssertEqual(restored.filter?.useKalmanFilter, original.filter?.useKalmanFilter)
    }

    func testGeoConfigFromMapDefaults() {
        let restored = TraceletGeoConfig.fromMap([:])
        let defaults = TraceletGeoConfig()
        XCTAssertEqual(restored.desiredAccuracy, defaults.desiredAccuracy)
        XCTAssertEqual(restored.distanceFilter, defaults.distanceFilter)
        XCTAssertNil(restored.filter)
    }

    func testLocationFilterFromMapRoundTrip() {
        let original = TraceletLocationFilter(
            policy: .ignore,
            maxImpliedSpeed: 90,
            odometerAccuracyThreshold: 30,
            trackingAccuracyThreshold: 150,
            useKalmanFilter: true,
            rejectMockLocations: true,
            mockDetectionLevel: .basic
        )
        let restored = TraceletLocationFilter.fromMap(original.toMap())
        XCTAssertEqual(restored.policy, original.policy)
        XCTAssertEqual(restored.maxImpliedSpeed, original.maxImpliedSpeed)
        XCTAssertEqual(restored.useKalmanFilter, original.useKalmanFilter)
        XCTAssertEqual(restored.mockDetectionLevel, original.mockDetectionLevel)
    }

    func testAppConfigFromMapRoundTrip() {
        let original = TraceletAppConfig(
            stopOnTerminate: false,
            startOnBoot: true,
            heartbeatInterval: 120,
            schedule: ["1-7 09:00-17:00"],
            scheduleUseAlarmManager: true,
            preventSuspend: true,
            foregroundService: .init(
                notificationTitle: "Test",
                notificationText: "Testing",
                notificationPriority: .high
            ),
            remoteConfigUrl: "https://example.com/config",
            remoteConfigHeaders: ["X-Key": "abc"],
            remoteConfigTimeout: 5000,
            remoteConfigRefreshInterval: 3600
        )
        let restored = TraceletAppConfig.fromMap(original.toMap())
        XCTAssertEqual(restored.stopOnTerminate, original.stopOnTerminate)
        XCTAssertEqual(restored.startOnBoot, original.startOnBoot)
        XCTAssertEqual(restored.schedule, original.schedule)
        XCTAssertEqual(restored.preventSuspend, original.preventSuspend)
        XCTAssertEqual(restored.remoteConfigUrl, original.remoteConfigUrl)
        XCTAssertEqual(restored.foregroundService.notificationTitle, original.foregroundService.notificationTitle)
    }

    func testForegroundServiceConfigFromMapRoundTrip() {
        let original = TraceletForegroundServiceConfig(
            enabled: false,
            channelId: "custom",
            channelName: "Custom",
            notificationTitle: "Title",
            notificationText: "Text",
            notificationColor: "#FF0000",
            notificationSmallIcon: "ic_small",
            notificationLargeIcon: "ic_large",
            notificationPriority: .max,
            notificationOngoing: false,
            actions: ["pause", "stop"]
        )
        let restored = TraceletForegroundServiceConfig.fromMap(original.toMap())
        XCTAssertEqual(restored.enabled, original.enabled)
        XCTAssertEqual(restored.notificationTitle, original.notificationTitle)
        XCTAssertEqual(restored.notificationColor, original.notificationColor)
        XCTAssertEqual(restored.notificationPriority, original.notificationPriority)
        XCTAssertEqual(restored.actions, original.actions)
    }

    func testHttpConfigFromMapRoundTrip() {
        let original = TraceletHttpConfig(
            url: "https://api.example.com/locs",
            method: .put,
            headers: ["Auth": "Bearer xyz"],
            httpRootProperty: "data",
            batchSync: true,
            maxBatchSize: 50,
            autoSync: false,
            autoSyncThreshold: 10,
            httpTimeout: 30000,
            locationsOrderDirection: .desc,
            disableAutoSyncOnCellular: true,
            maxRetries: 5,
            retryBackoffBase: 2000,
            retryBackoffCap: 60000,
            enableDeltaCompression: true,
            deltaCoordinatePrecision: 4,
            sslPinningCertificates: ["cert1"],
            sslPinningFingerprints: ["fp1"]
        )
        let restored = TraceletHttpConfig.fromMap(original.toMap())
        XCTAssertEqual(restored.url, original.url)
        XCTAssertEqual(restored.method, original.method)
        XCTAssertEqual(restored.batchSync, original.batchSync)
        XCTAssertEqual(restored.maxRetries, original.maxRetries)
        XCTAssertEqual(restored.sslPinningCertificates, original.sslPinningCertificates)
    }

    func testLoggerConfigFromMapRoundTrip() {
        let original = TraceletLoggerConfig(logLevel: .error, logMaxDays: 14, debug: true)
        let restored = TraceletLoggerConfig.fromMap(original.toMap())
        XCTAssertEqual(restored.logLevel, original.logLevel)
        XCTAssertEqual(restored.logMaxDays, original.logMaxDays)
        XCTAssertEqual(restored.debug, original.debug)
    }

    func testMotionConfigFromMapRoundTrip() {
        let original = TraceletMotionConfig(
            stopTimeout: 10,
            motionTriggerDelay: 5,
            disableMotionActivityUpdates: true,
            isMoving: true,
            activityRecognitionInterval: 5000,
            minimumActivityRecognitionConfidence: 50,
            disableStopDetection: true,
            stopDetectionDelay: 3,
            stopOnStationary: true,
            triggerActivities: [.inVehicle, .onBicycle],
            shakeThreshold: 3.0,
            stillThreshold: 0.5,
            stillSampleCount: 30
        )
        let restored = TraceletMotionConfig.fromMap(original.toMap())
        XCTAssertEqual(restored.stopTimeout, original.stopTimeout)
        XCTAssertEqual(restored.disableMotionActivityUpdates, original.disableMotionActivityUpdates)
        XCTAssertEqual(restored.triggerActivities, original.triggerActivities)
        XCTAssertEqual(restored.shakeThreshold, original.shakeThreshold)
    }

    func testGeofenceConfigFromMapRoundTrip() {
        let original = TraceletGeofenceConfig(
            geofenceProximityRadius: 5000,
            geofenceInitialTriggerEntry: false,
            geofenceModeKnockOut: true
        )
        let restored = TraceletGeofenceConfig.fromMap(original.toMap())
        XCTAssertEqual(restored.geofenceProximityRadius, original.geofenceProximityRadius)
        XCTAssertEqual(restored.geofenceInitialTriggerEntry, original.geofenceInitialTriggerEntry)
        XCTAssertEqual(restored.geofenceModeKnockOut, original.geofenceModeKnockOut)
    }

    func testPersistenceConfigFromMapRoundTrip() {
        let original = TraceletPersistenceConfig(
            persistMode: .geofence,
            maxDaysToPersist: 14,
            maxRecordsToPersist: 10000,
            locationTemplate: "{\"lat\":<%latitude%>}",
            geofenceTemplate: "{\"id\":\"<%identifier%>\"}",
            disableProviderChangeRecord: true
        )
        let restored = TraceletPersistenceConfig.fromMap(original.toMap())
        XCTAssertEqual(restored.persistMode, original.persistMode)
        XCTAssertEqual(restored.maxDaysToPersist, original.maxDaysToPersist)
        XCTAssertEqual(restored.locationTemplate, original.locationTemplate)
    }

    func testAuditConfigFromMapRoundTrip() {
        let original = TraceletAuditConfig(enabled: true, hashAlgorithm: .sha512)
        let restored = TraceletAuditConfig.fromMap(original.toMap())
        XCTAssertEqual(restored.enabled, original.enabled)
        XCTAssertEqual(restored.hashAlgorithm, original.hashAlgorithm)
    }

    func testPrivacyZoneConfigFromMapRoundTrip() {
        let original = TraceletPrivacyZoneConfig(enabled: true)
        let restored = TraceletPrivacyZoneConfig.fromMap(original.toMap())
        XCTAssertEqual(restored.enabled, original.enabled)
    }

    func testSecurityConfigFromMapRoundTrip() {
        let original = TraceletSecurityConfig(encryptDatabase: true)
        let restored = TraceletSecurityConfig.fromMap(original.toMap())
        XCTAssertEqual(restored.encryptDatabase, original.encryptDatabase)
    }

    func testAttestationConfigFromMapRoundTrip() {
        let original = TraceletAttestationConfig(enabled: true, refreshInterval: 1800)
        let restored = TraceletAttestationConfig.fromMap(original.toMap())
        XCTAssertEqual(restored.enabled, original.enabled)
        XCTAssertEqual(restored.refreshInterval, original.refreshInterval)
    }

    func testTraceletConfigFromMapRoundTrip() {
        let original = TraceletConfig(
            geo: .init(desiredAccuracy: .low, distanceFilter: 42.0),
            app: .init(stopOnTerminate: false, startOnBoot: true),
            http: .init(url: "https://example.com", batchSync: true),
            logger: .init(logLevel: .verbose, debug: true),
            motion: .init(stopTimeout: 10),
            geofence: .init(geofenceProximityRadius: 5000),
            persistence: .init(maxDaysToPersist: 7),
            audit: .init(enabled: true),
            privacyZone: .init(enabled: true),
            security: .init(encryptDatabase: true),
            attestation: .init(enabled: true, refreshInterval: 1800)
        )
        let restored = TraceletConfig.fromMap(original.toMap())
        XCTAssertEqual(restored.geo.distanceFilter, 42.0)
        XCTAssertEqual(restored.geo.desiredAccuracy, TraceletDesiredAccuracy.low)
        XCTAssertEqual(restored.app.stopOnTerminate, false)
        XCTAssertEqual(restored.http.url, "https://example.com")
        XCTAssertEqual(restored.logger.debug, true)
        XCTAssertEqual(restored.motion.stopTimeout, 10)
        XCTAssertEqual(restored.geofence.geofenceProximityRadius, 5000)
        XCTAssertEqual(restored.persistence.maxDaysToPersist, 7)
        XCTAssertEqual(restored.audit.enabled, true)
        XCTAssertEqual(restored.privacyZone.enabled, true)
        XCTAssertEqual(restored.security.encryptDatabase, true)
        XCTAssertEqual(restored.attestation.refreshInterval, 1800)
    }

    func testTraceletConfigFromMapDefaults() {
        let restored = TraceletConfig.fromMap([:])
        let defaults = TraceletConfig()
        XCTAssertEqual(restored.geo.desiredAccuracy, defaults.geo.desiredAccuracy)
        XCTAssertEqual(restored.app.stopOnTerminate, defaults.app.stopOnTerminate)
        XCTAssertEqual(restored.logger.logLevel, defaults.logger.logLevel)
    }

    // MARK: - ObjC Wrapper fromMap() Round-Trip Tests

    func testGeoConfigObjCFromMapRoundTrip() {
        let original = TraceletGeoConfigObjC(
            desiredAccuracy: 2,
            distanceFilter: 42.0,
            locationUpdateInterval: 2000,
            fastestLocationUpdateInterval: 1000,
            stationaryRadius: 50.0,
            locationTimeout: 120,
            activityType: 1,
            disableElasticity: true,
            elasticityMultiplier: 2.5,
            stopAfterElapsedMinutes: 30,
            deferTime: 5,
            allowIdenticalLocations: true,
            geofenceModeHighAccuracy: true,
            maxMonitoredGeofences: 20,
            useSignificantChangesOnly: true,
            showsBackgroundLocationIndicator: true,
            pausesLocationUpdatesAutomatically: true,
            locationAuthorizationRequest: "WhenInUse",
            disableLocationAuthorizationAlert: true,
            enableTimestampMeta: true,
            enableAdaptiveMode: true,
            periodicLocationInterval: 600,
            periodicDesiredAccuracy: 2,
            periodicUseForegroundService: true,
            periodicUseExactAlarms: true,
            enableSparseUpdates: true,
            sparseDistanceThreshold: 100.0,
            sparseMaxIdleSeconds: 600,
            enableDeadReckoning: true,
            deadReckoningActivationDelay: 20,
            deadReckoningMaxDuration: 240,
            batteryBudgetPerHour: 5.0,
            filter: TraceletLocationFilterObjC(
                policy: 1,
                maxImpliedSpeed: 300,
                odometerAccuracyThreshold: 100,
                trackingAccuracyThreshold: 50,
                useKalmanFilter: true,
                rejectMockLocations: true,
                mockDetectionLevel: 2
            )
        )
        let restored = TraceletGeoConfigObjC.fromMap(original.toMap())
        XCTAssertEqual(restored.desiredAccuracy, 2)
        XCTAssertEqual(restored.distanceFilter, 42.0)
        XCTAssertEqual(restored.locationUpdateInterval, 2000)
        XCTAssertEqual(restored.activityType, 1)
        XCTAssertEqual(restored.disableElasticity, true)
        XCTAssertEqual(restored.elasticityMultiplier, 2.5)
        XCTAssertEqual(restored.locationAuthorizationRequest, "WhenInUse")
        XCTAssertEqual(restored.periodicDesiredAccuracy, 2)
        XCTAssertEqual(restored.enableDeadReckoning, true)
        XCTAssertEqual(restored.batteryBudgetPerHour, 5.0)
        XCTAssertNotNil(restored.filter)
        XCTAssertEqual(restored.filter?.policy, 1)
        XCTAssertEqual(restored.filter?.useKalmanFilter, true)
        XCTAssertEqual(restored.filter?.mockDetectionLevel, 2)
    }

    func testGeoConfigObjCFromMapDefaults() {
        let restored = TraceletGeoConfigObjC.fromMap([:])
        XCTAssertEqual(restored.desiredAccuracy, 0)
        XCTAssertEqual(restored.distanceFilter, 10.0)
        XCTAssertEqual(restored.locationAuthorizationRequest, "Always")
        XCTAssertNil(restored.filter)
    }

    func testLocationFilterObjCFromMapRoundTrip() {
        let original = TraceletLocationFilterObjC(
            policy: 2, maxImpliedSpeed: 250, odometerAccuracyThreshold: 80,
            trackingAccuracyThreshold: 40, useKalmanFilter: true,
            rejectMockLocations: true, mockDetectionLevel: 1
        )
        let restored = TraceletLocationFilterObjC.fromMap(original.toMap())
        XCTAssertEqual(restored.policy, 2)
        XCTAssertEqual(restored.maxImpliedSpeed, 250)
        XCTAssertEqual(restored.useKalmanFilter, true)
        XCTAssertEqual(restored.mockDetectionLevel, 1)
    }

    func testAppConfigObjCFromMapRoundTrip() {
        let original = TraceletAppConfigObjC(
            stopOnTerminate: false,
            startOnBoot: true,
            heartbeatInterval: 120,
            schedule: ["1-7 09:00-17:00"],
            scheduleUseAlarmManager: true,
            preventSuspend: true,
            foregroundService: TraceletForegroundServiceConfigObjC(
                enabled: true, channelId: "test_ch", channelName: "Test",
                notificationTitle: "Title", notificationText: "Text",
                notificationColor: "#FF0000", notificationSmallIcon: "small",
                notificationLargeIcon: "large", notificationPriority: 1,
                notificationOngoing: false, actions: ["stop"]
            ),
            remoteConfigUrl: "https://example.com/config",
            remoteConfigHeaders: ["X-Key": "val"],
            remoteConfigTimeout: 5000,
            remoteConfigRefreshInterval: 3600
        )
        let restored = TraceletAppConfigObjC.fromMap(original.toMap())
        XCTAssertEqual(restored.stopOnTerminate, false)
        XCTAssertEqual(restored.startOnBoot, true)
        XCTAssertEqual(restored.heartbeatInterval, 120)
        XCTAssertEqual(restored.schedule, ["1-7 09:00-17:00"])
        XCTAssertEqual(restored.preventSuspend, true)
        XCTAssertEqual(restored.foregroundService.channelId, "test_ch")
        XCTAssertEqual(restored.foregroundService.notificationColor, "#FF0000")
        XCTAssertEqual(restored.foregroundService.notificationPriority, 1)
        XCTAssertEqual(restored.foregroundService.actions, ["stop"])
        XCTAssertEqual(restored.remoteConfigUrl, "https://example.com/config")
        XCTAssertEqual(restored.remoteConfigHeaders, ["X-Key": "val"])
        XCTAssertEqual(restored.remoteConfigRefreshInterval, 3600)
    }

    func testForegroundServiceConfigObjCFromMapRoundTrip() {
        let original = TraceletForegroundServiceConfigObjC(
            enabled: false, channelId: "ch", channelName: "Name",
            notificationTitle: "T", notificationText: "Txt",
            notificationColor: "#00FF00", notificationSmallIcon: nil,
            notificationLargeIcon: nil, notificationPriority: -2,
            notificationOngoing: false, actions: ["pause", "resume"]
        )
        let restored = TraceletForegroundServiceConfigObjC.fromMap(original.toMap())
        XCTAssertEqual(restored.enabled, false)
        XCTAssertEqual(restored.channelId, "ch")
        XCTAssertEqual(restored.notificationColor, "#00FF00")
        XCTAssertNil(restored.notificationSmallIcon)
        XCTAssertEqual(restored.notificationPriority, -2)
        XCTAssertEqual(restored.actions, ["pause", "resume"])
    }

    func testHttpConfigObjCFromMapRoundTrip() {
        let original = TraceletHttpConfigObjC(
            url: "https://api.example.com/locations",
            method: 1,
            headers: ["Authorization": "Bearer token"],
            httpRootProperty: "data",
            batchSync: true,
            maxBatchSize: 100,
            autoSync: false,
            autoSyncThreshold: 5,
            httpTimeout: 30000,
            locationsOrderDirection: 1,
            disableAutoSyncOnCellular: true,
            maxRetries: 5,
            retryBackoffBase: 2000,
            retryBackoffCap: 60000,
            enableDeltaCompression: true,
            deltaCoordinatePrecision: 5,
            sslPinningCertificates: ["cert1"],
            sslPinningFingerprints: ["fp1"]
        )
        let restored = TraceletHttpConfigObjC.fromMap(original.toMap())
        XCTAssertEqual(restored.url, "https://api.example.com/locations")
        XCTAssertEqual(restored.method, 1)
        XCTAssertEqual(restored.headers, ["Authorization": "Bearer token"])
        XCTAssertEqual(restored.batchSync, true)
        XCTAssertEqual(restored.maxBatchSize, 100)
        XCTAssertEqual(restored.locationsOrderDirection, 1)
        XCTAssertEqual(restored.enableDeltaCompression, true)
        XCTAssertEqual(restored.sslPinningCertificates, ["cert1"])
    }

    func testLoggerConfigObjCFromMapRoundTrip() {
        let original = TraceletLoggerConfigObjC(logLevel: 4, logMaxDays: 7, debug: true)
        let restored = TraceletLoggerConfigObjC.fromMap(original.toMap())
        XCTAssertEqual(restored.logLevel, 4)
        XCTAssertEqual(restored.logMaxDays, 7)
        XCTAssertEqual(restored.debug, true)
    }

    func testMotionConfigObjCFromMapRoundTrip() {
        let original = TraceletMotionConfigObjC(
            stopTimeout: 10, motionTriggerDelay: 5,
            disableMotionActivityUpdates: true, isMoving: true,
            activityRecognitionInterval: 20000,
            minimumActivityRecognitionConfidence: 50,
            disableStopDetection: true, stopDetectionDelay: 3,
            stopOnStationary: true, triggerActivities: ["on_foot", "in_vehicle"],
            shakeThreshold: 3.0, stillThreshold: 0.5, stillSampleCount: 30
        )
        let restored = TraceletMotionConfigObjC.fromMap(original.toMap())
        XCTAssertEqual(restored.stopTimeout, 10)
        XCTAssertEqual(restored.disableMotionActivityUpdates, true)
        XCTAssertEqual(restored.triggerActivities, ["on_foot", "in_vehicle"])
        XCTAssertEqual(restored.shakeThreshold, 3.0)
        XCTAssertEqual(restored.stillSampleCount, 30)
    }

    func testGeofenceConfigObjCFromMapRoundTrip() {
        let original = TraceletGeofenceConfigObjC(
            geofenceProximityRadius: 5000,
            geofenceInitialTriggerEntry: false,
            geofenceModeKnockOut: true
        )
        let restored = TraceletGeofenceConfigObjC.fromMap(original.toMap())
        XCTAssertEqual(restored.geofenceProximityRadius, 5000)
        XCTAssertEqual(restored.geofenceInitialTriggerEntry, false)
        XCTAssertEqual(restored.geofenceModeKnockOut, true)
    }

    func testPersistenceConfigObjCFromMapRoundTrip() {
        let original = TraceletPersistenceConfigObjC(
            persistMode: 2, maxDaysToPersist: 7, maxRecordsToPersist: 5000,
            locationTemplate: "{\"lat\":<%= latitude %>}", geofenceTemplate: nil,
            disableProviderChangeRecord: true
        )
        let restored = TraceletPersistenceConfigObjC.fromMap(original.toMap())
        XCTAssertEqual(restored.persistMode, 2)
        XCTAssertEqual(restored.maxDaysToPersist, 7)
        XCTAssertEqual(restored.locationTemplate, "{\"lat\":<%= latitude %>}")
        XCTAssertNil(restored.geofenceTemplate)
        XCTAssertEqual(restored.disableProviderChangeRecord, true)
    }

    func testAuditConfigObjCFromMapRoundTrip() {
        let original = TraceletAuditConfigObjC(enabled: true, hashAlgorithm: 1)
        let restored = TraceletAuditConfigObjC.fromMap(original.toMap())
        XCTAssertEqual(restored.enabled, true)
        XCTAssertEqual(restored.hashAlgorithm, 1)
    }

    func testPrivacyZoneConfigObjCFromMapRoundTrip() {
        let original = TraceletPrivacyZoneConfigObjC(enabled: true)
        let restored = TraceletPrivacyZoneConfigObjC.fromMap(original.toMap())
        XCTAssertEqual(restored.enabled, true)
    }

    func testSecurityConfigObjCFromMapRoundTrip() {
        let original = TraceletSecurityConfigObjC(encryptDatabase: true)
        let restored = TraceletSecurityConfigObjC.fromMap(original.toMap())
        XCTAssertEqual(restored.encryptDatabase, true)
    }

    func testAttestationConfigObjCFromMapRoundTrip() {
        let original = TraceletAttestationConfigObjC(enabled: true, refreshInterval: 7200)
        let restored = TraceletAttestationConfigObjC.fromMap(original.toMap())
        XCTAssertEqual(restored.enabled, true)
        XCTAssertEqual(restored.refreshInterval, 7200)
    }

    func testTraceletConfigObjCFromMapRoundTrip() {
        let original = TraceletConfigObjC(
            geo: TraceletGeoConfigObjC(desiredAccuracy: 2, distanceFilter: 42.0),
            app: TraceletAppConfigObjC(stopOnTerminate: false, startOnBoot: true),
            http: TraceletHttpConfigObjC(url: "https://example.com", method: 1),
            logger: TraceletLoggerConfigObjC(logLevel: 3, logMaxDays: 5, debug: true),
            motion: TraceletMotionConfigObjC(stopTimeout: 10),
            geofence: TraceletGeofenceConfigObjC(geofenceProximityRadius: 5000),
            persistence: TraceletPersistenceConfigObjC(maxDaysToPersist: 7),
            audit: TraceletAuditConfigObjC(enabled: true, hashAlgorithm: 1),
            privacyZone: TraceletPrivacyZoneConfigObjC(enabled: true),
            security: TraceletSecurityConfigObjC(encryptDatabase: true),
            attestation: TraceletAttestationConfigObjC(enabled: true, refreshInterval: 1800)
        )
        let restored = TraceletConfigObjC.fromMap(original.toMap())
        XCTAssertEqual(restored.geo.desiredAccuracy, 2)
        XCTAssertEqual(restored.geo.distanceFilter, 42.0)
        XCTAssertEqual(restored.app.stopOnTerminate, false)
        XCTAssertEqual(restored.app.startOnBoot, true)
        XCTAssertEqual(restored.http.url, "https://example.com")
        XCTAssertEqual(restored.http.method, 1)
        XCTAssertEqual(restored.logger.logLevel, 3)
        XCTAssertEqual(restored.logger.debug, true)
        XCTAssertEqual(restored.motion.stopTimeout, 10)
        XCTAssertEqual(restored.geofence.geofenceProximityRadius, 5000)
        XCTAssertEqual(restored.persistence.maxDaysToPersist, 7)
        XCTAssertEqual(restored.audit.enabled, true)
        XCTAssertEqual(restored.audit.hashAlgorithm, 1)
        XCTAssertEqual(restored.privacyZone.enabled, true)
        XCTAssertEqual(restored.security.encryptDatabase, true)
        XCTAssertEqual(restored.attestation.refreshInterval, 1800)
    }

    func testTraceletConfigObjCFromMapDefaults() {
        let restored = TraceletConfigObjC.fromMap([:])
        XCTAssertEqual(restored.geo.desiredAccuracy, 0)
        XCTAssertEqual(restored.geo.distanceFilter, 10.0)
        XCTAssertEqual(restored.app.stopOnTerminate, true)
        XCTAssertEqual(restored.logger.logLevel, 2)
        XCTAssertEqual(restored.motion.stopTimeout, 5)
        XCTAssertEqual(restored.security.encryptDatabase, false)
    }
}
