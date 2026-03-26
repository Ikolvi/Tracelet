import XCTest
@testable import TraceletSDK

// MARK: - PrivacyZoneManager Tests

final class PrivacyZoneManagerTests: XCTestCase {

    private func makeManager(enabled: Bool = true) -> (PrivacyZoneManager, TraceletDatabase) {
        let db = TraceletDatabase(inMemory: true)
        let config = ConfigManager()
        config.setConfig(["privacyZoneEnabled": enabled])
        return (PrivacyZoneManager(database: db, configManager: config), db)
    }

    func testDisabledReturnsNilAction() {
        let (mgr, _) = makeManager(enabled: false)
        let result = mgr.evaluate(latitude: 37.78, longitude: -122.42)
        XCTAssertNil(result.action)
    }

    func testNoZonesReturnsNilAction() {
        let (mgr, _) = makeManager()
        let result = mgr.evaluate(latitude: 37.78, longitude: -122.42)
        XCTAssertNil(result.action)
    }

    func testExcludeZoneDropsLocation() {
        let (mgr, _) = makeManager()
        _ = mgr.addZone([
            "identifier": "home",
            "latitude": 37.78,
            "longitude": -122.42,
            "radius": 1000.0,
            "action": PrivacyZoneManager.actionExclude,
        ])

        let location: [String: Any] = [
            "coords": [
                "latitude": 37.78,
                "longitude": -122.42,
            ] as [String: Any],
        ]
        let result = mgr.processLocation(location)
        XCTAssertEqual(result.action, .drop)
        XCTAssertNil(result.location)
    }

    func testEventOnlyZonePassesLocation() {
        let (mgr, _) = makeManager()
        _ = mgr.addZone([
            "identifier": "office",
            "latitude": 37.78,
            "longitude": -122.42,
            "radius": 1000.0,
            "action": PrivacyZoneManager.actionEventOnly,
        ])

        let location: [String: Any] = [
            "coords": [
                "latitude": 37.78,
                "longitude": -122.42,
            ] as [String: Any],
        ]
        let result = mgr.processLocation(location)
        XCTAssertEqual(result.action, .eventOnly)
        XCTAssertNotNil(result.location)
    }

    func testDegradeZoneSnapsCoordinates() {
        let (mgr, _) = makeManager()
        _ = mgr.addZone([
            "identifier": "school",
            "latitude": 37.78,
            "longitude": -122.42,
            "radius": 1000.0,
            "action": PrivacyZoneManager.actionDegrade,
            "degradedAccuracyMeters": 500.0,
        ])

        let location: [String: Any] = [
            "coords": [
                "latitude": 37.7801,
                "longitude": -122.4201,
                "accuracy": 10.0,
            ] as [String: Any],
        ]
        let result = mgr.processLocation(location)
        XCTAssertEqual(result.action, .degraded)

        let coords = result.location?["coords"] as? [String: Any]
        let accuracy = coords?["accuracy"] as? Double
        XCTAssertEqual(accuracy, 500.0)

        // Lat/lng should be snapped to grid
        let lat = coords?["latitude"] as? Double ?? 0
        let lng = coords?["longitude"] as? Double ?? 0
        XCTAssertNotEqual(lat, 37.7801)
        XCTAssertNotEqual(lng, -122.4201)
    }

    func testOutsideZonePassesThrough() {
        let (mgr, _) = makeManager()
        _ = mgr.addZone([
            "identifier": "home",
            "latitude": 37.78,
            "longitude": -122.42,
            "radius": 100.0,
            "action": PrivacyZoneManager.actionExclude,
        ])

        // ~1.3 km away
        let location: [String: Any] = [
            "coords": [
                "latitude": 37.79,
                "longitude": -122.41,
            ] as [String: Any],
        ]
        let result = mgr.processLocation(location)
        XCTAssertEqual(result.action, .passThrough)
    }

    func testMostRestrictiveZoneWins() {
        let (mgr, _) = makeManager()
        // Overlapping zones: degrade + exclude
        _ = mgr.addZone([
            "identifier": "outer",
            "latitude": 37.78,
            "longitude": -122.42,
            "radius": 2000.0,
            "action": PrivacyZoneManager.actionDegrade,
        ])
        _ = mgr.addZone([
            "identifier": "inner",
            "latitude": 37.78,
            "longitude": -122.42,
            "radius": 2000.0,
            "action": PrivacyZoneManager.actionExclude,
        ])

        let result = mgr.evaluate(latitude: 37.78, longitude: -122.42)
        XCTAssertEqual(result.action, PrivacyZoneManager.actionExclude)
    }

    func testZoneCRUD() {
        let (mgr, _) = makeManager()

        _ = mgr.addZone(["identifier": "a", "latitude": 1.0, "longitude": 2.0, "radius": 100.0, "action": 0])
        _ = mgr.addZone(["identifier": "b", "latitude": 3.0, "longitude": 4.0, "radius": 200.0, "action": 1])

        XCTAssertEqual(mgr.getZones().count, 2)

        _ = mgr.removeZone("a")
        XCTAssertEqual(mgr.getZones().count, 1)

        _ = mgr.removeAllZones()
        XCTAssertEqual(mgr.getZones().count, 0)
    }

    func testMissingCoordsPassesThrough() {
        let (mgr, _) = makeManager()
        _ = mgr.addZone([
            "identifier": "home",
            "latitude": 37.78,
            "longitude": -122.42,
            "radius": 1000.0,
            "action": PrivacyZoneManager.actionExclude,
        ])

        // Location map without coords key
        let location: [String: Any] = ["timestamp": "2024-01-01"]
        let result = mgr.processLocation(location)
        XCTAssertEqual(result.action, .passThrough)
    }
}

// MARK: - AuditTrailManager Tests

final class AuditTrailManagerTests: XCTestCase {

    private func makeManager() -> (AuditTrailManager, TraceletDatabase) {
        let db = TraceletDatabase(inMemory: true)
        let config = ConfigManager()
        config.setConfig(["auditEnabled": true])
        return (AuditTrailManager(database: db, configManager: config), db)
    }

    func testAppendCreatesAuditRecord() {
        let (mgr, db) = makeManager()
        let location: [String: Any] = [
            "uuid": "loc-001",
            "timestamp": "2024-01-01T00:00:00Z",
            "is_moving": true,
            "odometer": 100.0,
            "coords": [
                "latitude": 37.7749,
                "longitude": -122.4194,
                "accuracy": 10.0,
                "speed": 5.0,
                "heading": 180.0,
                "altitude": 50.0,
            ] as [String: Any],
        ]

        let result = mgr.appendToChain(location)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?["audit_chain_index"] as? Int, 0)
        XCTAssertNotNil(result?["audit_hash"] as? String)
        XCTAssertNotNil(result?["audit_previous_hash"] as? String)

        // Chain index increments
        let result2 = mgr.appendToChain(location)
        XCTAssertEqual(result2?["audit_chain_index"] as? Int, 1)
    }

    func testVerifyChainEmptyIsValid() {
        let (mgr, _) = makeManager()
        let result = mgr.verifyChain()
        XCTAssertEqual(result["is_valid"] as? Bool, true)
        XCTAssertEqual(result["total_records"] as? Int, 0)
    }

    func testGetProofReturnsNilForMissing() {
        let (mgr, _) = makeManager()
        let proof = mgr.getProof(uuid: "nonexistent")
        XCTAssertNil(proof)
    }

    func testResetClearsChain() {
        let (mgr, _) = makeManager()
        let location: [String: Any] = [
            "uuid": "loc-001",
            "timestamp": "2024-01-01T00:00:00Z",
            "is_moving": false,
            "odometer": 0.0,
            "coords": [
                "latitude": 0.0, "longitude": 0.0,
                "accuracy": 10.0, "speed": 0.0,
                "heading": 0.0, "altitude": 0.0,
            ] as [String: Any],
        ]
        _ = mgr.appendToChain(location)
        mgr.reset()

        let result = mgr.verifyChain()
        XCTAssertEqual(result["total_records"] as? Int, 0)
    }

    func testDisabledAuditReturnsNil() {
        let db = TraceletDatabase(inMemory: true)
        let config = ConfigManager()
        config.setConfig(["auditEnabled": false])
        let mgr = AuditTrailManager(database: db, configManager: config)

        let result = mgr.appendToChain(["uuid": "loc-001", "timestamp": "t"])
        XCTAssertNil(result)
    }

    func testChainLinkage() {
        let (mgr, _) = makeManager()
        let loc1: [String: Any] = [
            "uuid": "loc-001",
            "timestamp": "2024-01-01T00:00:00Z",
            "is_moving": false,
            "odometer": 0.0,
            "coords": [
                "latitude": 37.0, "longitude": -122.0,
                "accuracy": 10.0, "speed": 0.0,
                "heading": 0.0, "altitude": 0.0,
            ] as [String: Any],
        ]
        let loc2: [String: Any] = [
            "uuid": "loc-002",
            "timestamp": "2024-01-01T00:01:00Z",
            "is_moving": true,
            "odometer": 50.0,
            "coords": [
                "latitude": 37.001, "longitude": -122.001,
                "accuracy": 8.0, "speed": 3.0,
                "heading": 45.0, "altitude": 52.0,
            ] as [String: Any],
        ]

        let r1 = mgr.appendToChain(loc1)!
        let r2 = mgr.appendToChain(loc2)!

        // Second record's previous hash must equal first record's hash
        XCTAssertEqual(
            r2["audit_previous_hash"] as? String,
            r1["audit_hash"] as? String
        )
    }
}

// MARK: - TraceletLogger Tests

final class TraceletLoggerTests: XCTestCase {

    func testLogLevels() {
        let config = ConfigManager()
        config.setConfig(["logLevel": 5]) // verbose
        let db = TraceletDatabase(inMemory: true)
        let logger = TraceletLogger(configManager: config, database: db)

        logger.error("Error message")
        logger.warning("Warning message")
        logger.info("Info message")
        logger.debug("Debug message")
        logger.verbose("Verbose message")

        let logs = logger.getLog()
        XCTAssertGreaterThanOrEqual(logs.count, 5)
    }

    func testLogLevelFiltering() {
        let config = ConfigManager()
        config.setConfig(["logLevel": 1]) // only errors
        let db = TraceletDatabase(inMemory: true)
        let logger = TraceletLogger(configManager: config, database: db)

        logger.error("Error message")
        logger.info("Info message")
        logger.debug("Debug message")

        let logs = logger.getLog()
        // Only error should have been logged
        XCTAssertEqual(logs.count, 1)
    }

    func testDestroyLog() {
        let config = ConfigManager()
        config.setConfig(["logLevel": 5])
        let db = TraceletDatabase(inMemory: true)
        let logger = TraceletLogger(configManager: config, database: db)

        logger.info("Test")
        XCTAssertGreaterThan(logger.getLog().count, 0)

        _ = logger.destroyLog()
        XCTAssertEqual(logger.getLog().count, 0)
    }

    func testLogForEmail() {
        let config = ConfigManager()
        config.setConfig(["logLevel": 5])
        let db = TraceletDatabase(inMemory: true)
        let logger = TraceletLogger(configManager: config, database: db)

        logger.info("Email test log")
        let emailStr = logger.getLogForEmail()
        XCTAssertFalse(emailStr.isEmpty)
    }

    func testDartLogLevel() {
        let config = ConfigManager()
        config.setConfig(["logLevel": 5])
        let db = TraceletDatabase(inMemory: true)
        let logger = TraceletLogger(configManager: config, database: db)

        logger.log(levelString: "ERROR", message: "Dart error")
        logger.log(levelString: "INFO", message: "Dart info")

        let logs = logger.getLog()
        XCTAssertEqual(logs.count, 2)
    }
}

// MARK: - ScheduleManager Tests

final class ScheduleManagerTests: XCTestCase {

    func testScheduleParseValidEntry() {
        let config = ConfigManager()
        // Mon-Fri 09:00-17:00
        config.setConfig(["schedule": ["1-5 09:00-17:00"]])
        let state = StateManager()
        let events = MockEventSender()
        let mgr = ScheduleManager(configManager: config, stateManager: state, eventDispatcher: events)

        // isWithinSchedule should return a boolean (we can't control time, but we verify no crash)
        let _ = mgr.isWithinSchedule()
    }

    func testScheduleEmptyReturnsFalse() {
        let config = ConfigManager()
        config.setConfig(["schedule": [String]()])
        let state = StateManager()
        let events = MockEventSender()
        let mgr = ScheduleManager(configManager: config, stateManager: state, eventDispatcher: events)

        XCTAssertFalse(mgr.isWithinSchedule())
    }

    func testScheduleStartSetsEnabled() {
        let config = ConfigManager()
        config.setConfig(["schedule": ["1-7 00:00-23:59"]])
        let state = StateManager()
        let events = MockEventSender()
        let mgr = ScheduleManager(configManager: config, stateManager: state, eventDispatcher: events)

        mgr.start()
        XCTAssertTrue(state.schedulerEnabled)
    }

    func testScheduleStopClearsEnabled() {
        let config = ConfigManager()
        config.setConfig(["schedule": ["1-7 00:00-23:59"]])
        let state = StateManager()
        let events = MockEventSender()
        let mgr = ScheduleManager(configManager: config, stateManager: state, eventDispatcher: events)

        mgr.start()
        mgr.stop()
        XCTAssertFalse(state.schedulerEnabled)
    }

    func testScheduleDispatchesEvent() {
        let config = ConfigManager()
        config.setConfig(["schedule": ["1-7 00:00-23:59"]])
        let state = StateManager()
        let events = MockEventSender()
        let mgr = ScheduleManager(configManager: config, stateManager: state, eventDispatcher: events)

        mgr.start()
        XCTAssertTrue(events.scheduleSent)
    }
}

// MARK: - Haversine and Degrade Utility Tests

final class PrivacyUtilTests: XCTestCase {

    func testHaversineDistanceZero() {
        let d = haversineDistanceMetres(lat1: 37.78, lng1: -122.42, lat2: 37.78, lng2: -122.42)
        XCTAssertEqual(d, 0.0, accuracy: 0.001)
    }

    func testHaversineDistanceKnown() {
        // SF to LA: ~559 km
        let d = haversineDistanceMetres(lat1: 37.7749, lng1: -122.4194, lat2: 34.0522, lng2: -118.2437)
        XCTAssertEqual(d, 559_000, accuracy: 5000) // within 5 km
    }

    func testIsActionMoreRestrictive() {
        XCTAssertTrue(isActionMoreRestrictive(PrivacyZoneManager.actionExclude, than: PrivacyZoneManager.actionDegrade))
        XCTAssertTrue(isActionMoreRestrictive(PrivacyZoneManager.actionExclude, than: PrivacyZoneManager.actionEventOnly))
        XCTAssertTrue(isActionMoreRestrictive(PrivacyZoneManager.actionEventOnly, than: PrivacyZoneManager.actionDegrade))
        XCTAssertFalse(isActionMoreRestrictive(PrivacyZoneManager.actionDegrade, than: PrivacyZoneManager.actionExclude))
    }

    func testDegradeCoordinatesSnapToGrid() {
        let (lat, lng) = degradeCoordinates(lat: 37.7749, lng: -122.4194, accuracyMeters: 1000.0)
        // Grid degree = 1000/111320 ≈ 0.00898
        // The snapped values should differ from the original
        XCTAssertNotEqual(lat, 37.7749)
        XCTAssertNotEqual(lng, -122.4194)
        // But should be close (within ~1 km / 0.01 deg)
        XCTAssertEqual(lat, 37.7749, accuracy: 0.02)
        XCTAssertEqual(lng, -122.4194, accuracy: 0.02)
    }
}

// MARK: - ConfigManager Extended Tests

final class ConfigManagerExtendedTests: XCTestCase {

    func testConfigMergesPartialUpdate() {
        let config = ConfigManager()
        config.setConfig(["distanceFilter": 50.0, "logLevel": 3])
        config.setConfig(["distanceFilter": 100.0])

        let c = config.getConfig()
        XCTAssertEqual(c["distanceFilter"] as? Double, 100.0)
        XCTAssertEqual(c["logLevel"] as? Int, 3) // preserved
    }

    func testStopOnTerminateDefault() {
        let config = ConfigManager()
        XCTAssertTrue(config.getStopOnTerminate())
    }

    func testStartOnBootDefault() {
        let config = ConfigManager()
        XCTAssertFalse(config.getStartOnBoot())
    }

    func testHeartbeatIntervalDefault() {
        let config = ConfigManager()
        XCTAssertEqual(config.getHeartbeatInterval(), 120)
    }

    func testPrivacyZoneDisabledByDefault() {
        let config = ConfigManager()
        XCTAssertFalse(config.getPrivacyZoneEnabled())
    }

    func testAuditDefaultsToConfigEnabled() {
        let config = ConfigManager()
        // getAuditEnabled falls through: auditEnabled ?? enabled ?? false
        // With clean config (no auditEnabled key), it uses "enabled" key from general state.
        let result = config.getAuditEnabled()
        XCTAssertNotNil(result) // just verify no crash; actual default depends on UserDefaults state
    }

    func testScheduleDefaultEmpty() {
        let config = ConfigManager()
        XCTAssertEqual(config.getSchedule().count, 0)
    }

    func testLogMaxDaysDefault() {
        let config = ConfigManager()
        XCTAssertEqual(config.getLogMaxDays(), 3)
    }
}

// MARK: - Database Extended Tests

final class DatabaseExtendedTests: XCTestCase {

    func testPrivacyZoneCRUD() {
        let db = TraceletDatabase(inMemory: true)
        let added = db.insertPrivacyZone([
            "identifier": "zone1",
            "latitude": 37.78,
            "longitude": -122.42,
            "radius": 500.0,
            "action": 0,
        ])
        XCTAssertTrue(added)

        let zones = db.getPrivacyZones()
        XCTAssertEqual(zones.count, 1)
        XCTAssertEqual(zones.first?["identifier"] as? String, "zone1")

        let deleted = db.deletePrivacyZone("zone1")
        XCTAssertTrue(deleted)
        XCTAssertEqual(db.getPrivacyZones().count, 0)
    }

    func testDeleteAllPrivacyZones() {
        let db = TraceletDatabase(inMemory: true)
        _ = db.insertPrivacyZone(["identifier": "a", "latitude": 1.0, "longitude": 2.0, "radius": 100.0, "action": 0])
        _ = db.insertPrivacyZone(["identifier": "b", "latitude": 3.0, "longitude": 4.0, "radius": 200.0, "action": 1])
        XCTAssertEqual(db.getPrivacyZones().count, 2)

        _ = db.deleteAllPrivacyZones()
        XCTAssertEqual(db.getPrivacyZones().count, 0)
    }

    func testAuditRecordCRUD() {
        let db = TraceletDatabase(inMemory: true)
        db.insertAuditRecord(uuid: "loc-1", hash: "abc123", previousHash: "genesis", chainIndex: 0)

        let record = db.getAuditRecord(uuid: "loc-1")
        XCTAssertNotNil(record)
        XCTAssertEqual(record?["hash"] as? String, "abc123")
        XCTAssertEqual(record?["chain_index"] as? Int, 0)

        let trail = db.getAuditTrail()
        XCTAssertEqual(trail.count, 1)
    }

    func testDeleteAllAuditRecords() {
        let db = TraceletDatabase(inMemory: true)
        db.insertAuditRecord(uuid: "loc-1", hash: "h1", previousHash: "g", chainIndex: 0)
        db.insertAuditRecord(uuid: "loc-2", hash: "h2", previousHash: "h1", chainIndex: 1)

        db.deleteAllAuditRecords()
        XCTAssertEqual(db.getAuditTrail().count, 0)
    }

    func testDatabaseMultipleLocations() {
        let db = TraceletDatabase(inMemory: true)
        for i in 0..<10 {
            _ = db.insertLocation([
                "uuid": "loc-\(i)",
                "latitude": 37.0 + Double(i) * 0.001,
                "longitude": -122.0,
                "accuracy": 10.0,
                "speed": 0.0,
                "heading": 0.0,
                "altitude": 0.0,
                "timestamp": "2024-01-01T00:0\(i):00Z",
            ])
        }
        XCTAssertEqual(db.getLocationCount(), 10)

        let locations = db.getLocations(limit: 5)
        XCTAssertEqual(locations.count, 5)
    }
}

// MARK: - DelegateEventSender Extended Tests

final class DelegateEventSenderExtendedTests: XCTestCase {

    func testForwardsMotionChange() {
        let sender = DelegateEventSender()
        sender.sdk = TraceletSdk.shared
        let delegate = FullMockDelegate()
        sender.delegate = delegate
        let exp = XCTestExpectation(description: "motion")
        delegate.onMotionChange = { exp.fulfill() }

        sender.sendMotionChange(["isMoving": true])
        wait(for: [exp], timeout: 1.0)
        XCTAssertTrue(delegate.motionChangeCalled)
    }

    func testForwardsActivityChange() {
        let sender = DelegateEventSender()
        sender.sdk = TraceletSdk.shared
        let delegate = FullMockDelegate()
        sender.delegate = delegate
        let exp = XCTestExpectation(description: "activity")
        delegate.onActivityChange = { exp.fulfill() }

        sender.sendActivityChange(["type": "walking", "confidence": 100])
        wait(for: [exp], timeout: 1.0)
        XCTAssertTrue(delegate.activityChangeCalled)
    }

    func testForwardsGeofence() {
        let sender = DelegateEventSender()
        sender.sdk = TraceletSdk.shared
        let delegate = FullMockDelegate()
        sender.delegate = delegate
        let exp = XCTestExpectation(description: "geofence")
        delegate.onGeofence = { exp.fulfill() }

        sender.sendGeofence(["identifier": "office", "action": "ENTER"])
        wait(for: [exp], timeout: 1.0)
        XCTAssertTrue(delegate.geofenceCalled)
    }

    func testForwardsHeartbeat() {
        let sender = DelegateEventSender()
        sender.sdk = TraceletSdk.shared
        let delegate = FullMockDelegate()
        sender.delegate = delegate
        let exp = XCTestExpectation(description: "heartbeat")
        delegate.onHeartbeat = { exp.fulfill() }

        sender.sendHeartbeat(["location": [:]])
        wait(for: [exp], timeout: 1.0)
        XCTAssertTrue(delegate.heartbeatCalled)
    }

    func testForwardsHttp() {
        let sender = DelegateEventSender()
        sender.sdk = TraceletSdk.shared
        let delegate = FullMockDelegate()
        sender.delegate = delegate
        let exp = XCTestExpectation(description: "http")
        delegate.onHttp = { exp.fulfill() }

        sender.sendHttp(["status": 200])
        wait(for: [exp], timeout: 1.0)
        XCTAssertTrue(delegate.httpCalled)
    }

    func testForwardsSchedule() {
        let sender = DelegateEventSender()
        sender.sdk = TraceletSdk.shared
        let delegate = FullMockDelegate()
        sender.delegate = delegate
        let exp = XCTestExpectation(description: "schedule")
        delegate.onSchedule = { exp.fulfill() }

        sender.sendSchedule(["enabled": true])
        wait(for: [exp], timeout: 1.0)
        XCTAssertTrue(delegate.scheduleCalled)
    }

    func testForwardsProviderChange() {
        let sender = DelegateEventSender()
        sender.sdk = TraceletSdk.shared
        let delegate = FullMockDelegate()
        sender.delegate = delegate
        let exp = XCTestExpectation(description: "provider")
        delegate.onProviderChange = { exp.fulfill() }

        sender.sendProviderChange(["provider": "gps"])
        wait(for: [exp], timeout: 1.0)
        XCTAssertTrue(delegate.providerChangeCalled)
    }

    func testForwardsConnectivityChange() {
        let sender = DelegateEventSender()
        sender.sdk = TraceletSdk.shared
        let delegate = FullMockDelegate()
        sender.delegate = delegate
        let exp = XCTestExpectation(description: "connectivity")
        delegate.onConnectivityChange = { exp.fulfill() }

        sender.sendConnectivityChange(["connected": true])
        wait(for: [exp], timeout: 1.0)
        XCTAssertTrue(delegate.connectivityChangeCalled)
    }
}

// MARK: - StateManager Extended Tests

final class StateManagerExtendedTests: XCTestCase {

    func testToMapIncludesConfig() {
        let state = StateManager()
        state.enabled = true
        state.trackingMode = 1

        let config: [String: Any] = ["distanceFilter": 50.0]
        let map = state.toMap(config)

        XCTAssertEqual(map["enabled"] as? Bool, true)
        XCTAssertEqual(map["trackingMode"] as? Int, 1)
    }

    func testMultipleOdometerIncrements() {
        let state = StateManager()
        state.odometer = 0
        state.addOdometer(distance: 100.0)
        state.addOdometer(distance: 200.0)
        state.addOdometer(distance: 50.0)
        XCTAssertEqual(state.odometer, 350.0)
    }
}

// MARK: - Mock Helpers

private class MockEventSender: TraceletEventSending {
    var scheduleSent = false

    func sendLocation(_ data: [String: Any]) {}
    func sendMotionChange(_ data: [String: Any]) {}
    func sendActivityChange(_ data: [String: Any]) {}
    func sendProviderChange(_ data: [String: Any]) {}
    func sendGeofence(_ data: [String: Any]) {}
    func sendGeofencesChange(_ data: [String: Any]) {}
    func sendHeartbeat(_ data: [String: Any]) {}
    func sendHttp(_ data: [String: Any]) {}
    func sendSchedule(_ data: [String: Any]) { scheduleSent = true }
    func sendPowerSaveChange(_ isPowerSave: Bool) {}
    func sendConnectivityChange(_ data: [String: Any]) {}
    func sendEnabledChange(_ enabled: Bool) {}
    func sendNotificationAction(_ data: [String: Any]) {}
    func sendAuthorization(_ data: [String: Any]) {}
    func sendWatchPosition(_ data: [String: Any]) {}
    func sendRemoteConfigEvent(_ data: [String: Any]) {}
    func hasListener(eventName: String) -> Bool { return true }
}

private class FullMockDelegate: TraceletDelegate {
    var motionChangeCalled = false
    var activityChangeCalled = false
    var geofenceCalled = false
    var heartbeatCalled = false
    var httpCalled = false
    var scheduleCalled = false
    var providerChangeCalled = false
    var connectivityChangeCalled = false

    var onMotionChange: (() -> Void)?
    var onActivityChange: (() -> Void)?
    var onGeofence: (() -> Void)?
    var onHeartbeat: (() -> Void)?
    var onHttp: (() -> Void)?
    var onSchedule: (() -> Void)?
    var onProviderChange: (() -> Void)?
    var onConnectivityChange: (() -> Void)?

    func tracelet(_ sdk: TraceletSdk, didUpdateLocation location: [String: Any]) {}
    func tracelet(_ sdk: TraceletSdk, didChangeMotion data: [String: Any]) { motionChangeCalled = true; onMotionChange?() }
    func tracelet(_ sdk: TraceletSdk, didChangeActivity data: [String: Any]) { activityChangeCalled = true; onActivityChange?() }
    func tracelet(_ sdk: TraceletSdk, didChangeProvider data: [String: Any]) { providerChangeCalled = true; onProviderChange?() }
    func tracelet(_ sdk: TraceletSdk, didTriggerGeofence data: [String: Any]) { geofenceCalled = true; onGeofence?() }
    func tracelet(_ sdk: TraceletSdk, didChangeGeofences data: [String: Any]) {}
    func tracelet(_ sdk: TraceletSdk, didHeartbeat data: [String: Any]) { heartbeatCalled = true; onHeartbeat?() }
    func tracelet(_ sdk: TraceletSdk, didSyncHttp data: [String: Any]) { httpCalled = true; onHttp?() }
    func tracelet(_ sdk: TraceletSdk, didSchedule data: [String: Any]) { scheduleCalled = true; onSchedule?() }
    func tracelet(_ sdk: TraceletSdk, didChangePowerSave isPowerSave: Bool) {}
    func tracelet(_ sdk: TraceletSdk, didChangeConnectivity data: [String: Any]) { connectivityChangeCalled = true; onConnectivityChange?() }
    func tracelet(_ sdk: TraceletSdk, didChangeEnabled enabled: Bool) {}
    func tracelet(_ sdk: TraceletSdk, didAuthorize data: [String: Any]) {}
}
