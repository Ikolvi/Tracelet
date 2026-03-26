import XCTest
@testable import TraceletSDK

final class TraceletSdkTests: XCTestCase {

    // MARK: - Singleton

    func testSharedInstanceIsSingleton() {
        let a = TraceletSdk.shared
        let b = TraceletSdk.shared
        XCTAssertTrue(a === b)
    }

    // MARK: - StateManager

    func testStateManagerDefaultsAfterReset() {
        let state = StateManager()
        state.reset()
        XCTAssertFalse(state.enabled)
        XCTAssertEqual(state.trackingMode, 0)
        XCTAssertFalse(state.isMoving)
        XCTAssertEqual(state.odometer, 0.0)
        XCTAssertFalse(state.schedulerEnabled)
    }

    func testStateManagerReset() {
        let state = StateManager()
        state.enabled = true
        state.isMoving = true
        state.odometer = 1234.5
        state.trackingMode = 2
        state.schedulerEnabled = true

        state.reset()

        XCTAssertFalse(state.enabled)
        XCTAssertFalse(state.isMoving)
        XCTAssertEqual(state.odometer, 0.0)
        XCTAssertEqual(state.trackingMode, 0)
        XCTAssertFalse(state.schedulerEnabled)
    }

    func testStateManagerToMap() {
        let state = StateManager()
        state.enabled = true
        state.trackingMode = 1
        state.isMoving = true
        state.odometer = 500.0

        let map = state.toMap(nil)

        XCTAssertEqual(map["enabled"] as? Bool, true)
        XCTAssertEqual(map["trackingMode"] as? Int, 1)
        XCTAssertEqual(map["isMoving"] as? Bool, true)
        XCTAssertEqual(map["odometer"] as? Double, 500.0)
    }

    func testStateManagerAddOdometer() {
        let state = StateManager()
        state.odometer = 0
        state.addOdometer(distance: 100.0)
        state.addOdometer(distance: 50.0)
        XCTAssertEqual(state.odometer, 150.0, accuracy: 0.001)
    }

    // MARK: - ConfigManager

    func testConfigManagerDefaults() {
        let config = ConfigManager()
        config.reset(nil) // Ensure clean state
        XCTAssertEqual(config.getDistanceFilter(), 10.0)
        XCTAssertEqual(config.getStationaryRadius(), 25.0)
        XCTAssertTrue(config.getStopOnTerminate())
        XCTAssertFalse(config.getStartOnBoot())
        XCTAssertTrue(config.getAutoSync())
        XCTAssertEqual(config.getHeartbeatInterval(), 60)
        XCTAssertEqual(config.getStopTimeout(), 5)
        XCTAssertFalse(config.isDebug())
    }

    func testConfigManagerSetConfig() {
        let config = ConfigManager()
        let _ = config.setConfig([
            "geo": [
                "distanceFilter": 50.0,
                "stationaryRadius": 100.0,
            ] as [String: Any],
            "app": [
                "debug": true,
                "heartbeatInterval": 120,
            ] as [String: Any],
        ])

        XCTAssertEqual(config.getDistanceFilter(), 50.0)
        XCTAssertEqual(config.getStationaryRadius(), 100.0)
        XCTAssertTrue(config.isDebug())
        XCTAssertEqual(config.getHeartbeatInterval(), 120)
    }

    func testConfigManagerReset() {
        let config = ConfigManager()
        let _ = config.setConfig([
            "geo": ["distanceFilter": 99.0] as [String: Any],
        ])
        XCTAssertEqual(config.getDistanceFilter(), 99.0)

        config.reset(nil)
        XCTAssertEqual(config.getDistanceFilter(), 10.0)
    }

    func testConfigManagerDynamicHeaders() {
        let config = ConfigManager()
        let _ = config.setConfig([
            "http": [
                "headers": ["X-Static": "abc"],
            ] as [String: Any],
        ])

        config.setDynamicHeaders(["Authorization": "Bearer tok123"])

        let merged = config.getMergedHttpHeaders()
        XCTAssertEqual(merged["X-Static"], "abc")
        XCTAssertEqual(merged["Authorization"], "Bearer tok123")
    }

    func testConfigManagerDynamicHeadersOverrideStatic() {
        let config = ConfigManager()
        let _ = config.setConfig([
            "http": [
                "headers": ["Authorization": "old"],
            ] as [String: Any],
        ])

        config.setDynamicHeaders(["Authorization": "new"])

        let merged = config.getMergedHttpHeaders()
        XCTAssertEqual(merged["Authorization"], "new")
    }

    func testConfigManagerRouteContext() {
        let config = ConfigManager()
        XCTAssertNil(config.getRouteContext())

        config.setRouteContext(["taskId": "delivery-42", "driverId": "driver-7"])
        let ctx = config.getRouteContext()
        XCTAssertEqual(ctx?["taskId"] as? String, "delivery-42")
        XCTAssertEqual(ctx?["driverId"] as? String, "driver-7")

        config.clearRouteContext()
        XCTAssertNil(config.getRouteContext())
    }

    func testConfigManagerHttpMethod() {
        let config = ConfigManager()

        // Default is POST
        XCTAssertEqual(config.getHttpMethod(), "POST")

        // Dart sends method as Int (0=POST, 1=PUT)
        let _ = config.setConfig(["http": ["method": 1] as [String: Any]])
        XCTAssertEqual(config.getHttpMethod(), "PUT")

        let _ = config.setConfig(["http": ["method": 0] as [String: Any]])
        XCTAssertEqual(config.getHttpMethod(), "POST")
    }

    func testConfigManagerPeriodicDefaults() {
        let config = ConfigManager()
        XCTAssertEqual(config.getPeriodicLocationInterval(), 900)
        XCTAssertEqual(config.getPeriodicDesiredAccuracy(), 1)
        XCTAssertFalse(config.getPeriodicUseForegroundService())
    }

    // MARK: - DelegateEventSender

    func testDelegateEventSenderHasListenerWithoutDelegate() {
        let sender = DelegateEventSender()
        XCTAssertFalse(sender.hasListener(eventName: "location"))
    }

    func testDelegateEventSenderForwardsLocation() {
        let sender = DelegateEventSender()
        let sdk = TraceletSdk.shared
        sender.sdk = sdk
        let mockDelegate = MockDelegate()
        sender.delegate = mockDelegate

        let expectation = XCTestExpectation(description: "location delivered")
        mockDelegate.onLocation = { _, data in
            XCTAssertEqual(data["latitude"] as? Double, 37.7749)
            expectation.fulfill()
        }

        sender.sendLocation(["latitude": 37.7749, "longitude": -122.4194])
        wait(for: [expectation], timeout: 1.0)
    }

    func testDelegateEventSenderForwardsPowerSave() {
        let sender = DelegateEventSender()
        let sdk = TraceletSdk.shared
        sender.sdk = sdk
        let mockDelegate = MockDelegate()
        sender.delegate = mockDelegate

        let expectation = XCTestExpectation(description: "power save delivered")
        mockDelegate.onPowerSave = { _, isPowerSave in
            XCTAssertTrue(isPowerSave)
            expectation.fulfill()
        }

        sender.sendPowerSaveChange(true)
        wait(for: [expectation], timeout: 1.0)
    }

    func testDelegateEventSenderForwardsEnabledChange() {
        let sender = DelegateEventSender()
        let sdk = TraceletSdk.shared
        sender.sdk = sdk
        let mockDelegate = MockDelegate()
        sender.delegate = mockDelegate

        let expectation = XCTestExpectation(description: "enabled change delivered")
        mockDelegate.onEnabledChange = { _, enabled in
            XCTAssertFalse(enabled)
            expectation.fulfill()
        }

        sender.sendEnabledChange(false)
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Database (in-memory)

    func testDatabaseInsertAndRetrieve() {
        let db = TraceletDatabase(inMemory: true)

        let uuid = db.insertLocation([
            "uuid": "test-uuid-1",
            "latitude": 37.7749,
            "longitude": -122.4194,
            "accuracy": 5.0,
            "speed": 1.5,
            "heading": 90.0,
            "altitude": 10.0,
            "timestamp": "2024-01-01T00:00:00Z",
        ])

        XCTAssertFalse(uuid.isEmpty)

        let locations = db.getLocations()
        XCTAssertEqual(locations.count, 1)
    }

    func testDatabaseCount() {
        let db = TraceletDatabase(inMemory: true)

        XCTAssertEqual(db.getLocationCount(), 0)

        let _ = db.insertLocation([
            "uuid": "cnt-1",
            "latitude": 1.0, "longitude": 2.0,
            "accuracy": 5.0, "speed": 0.0, "heading": 0.0, "altitude": 0.0,
            "timestamp": "2024-01-01T00:00:00Z",
        ])
        let _ = db.insertLocation([
            "uuid": "cnt-2",
            "latitude": 3.0, "longitude": 4.0,
            "accuracy": 5.0, "speed": 0.0, "heading": 0.0, "altitude": 0.0,
            "timestamp": "2024-01-01T01:00:00Z",
        ])

        XCTAssertEqual(db.getLocationCount(), 2)
    }

    func testDatabaseDeleteAll() {
        let db = TraceletDatabase(inMemory: true)

        let _ = db.insertLocation([
            "uuid": "del-1",
            "latitude": 1.0, "longitude": 2.0,
            "accuracy": 5.0, "speed": 0.0, "heading": 0.0, "altitude": 0.0,
            "timestamp": "2024-01-01T00:00:00Z",
        ])

        XCTAssertEqual(db.getLocationCount(), 1)
        let _ = db.deleteAllLocations()
        XCTAssertEqual(db.getLocationCount(), 0)
    }

    func testDatabaseDeleteByUuid() {
        let db = TraceletDatabase(inMemory: true)

        let _ = db.insertLocation([
            "uuid": "keep-me",
            "latitude": 1.0, "longitude": 2.0,
            "accuracy": 5.0, "speed": 0.0, "heading": 0.0, "altitude": 0.0,
            "timestamp": "2024-01-01T00:00:00Z",
        ])
        let _ = db.insertLocation([
            "uuid": "delete-me",
            "latitude": 3.0, "longitude": 4.0,
            "accuracy": 5.0, "speed": 0.0, "heading": 0.0, "altitude": 0.0,
            "timestamp": "2024-01-01T01:00:00Z",
        ])

        XCTAssertEqual(db.getLocationCount(), 2)
        let _ = db.deleteLocation("delete-me")
        XCTAssertEqual(db.getLocationCount(), 1)
    }

    func testDatabaseGeofenceCRUD() {
        let db = TraceletDatabase(inMemory: true)

        let added = db.insertGeofence([
            "identifier": "office",
            "latitude": 37.7749,
            "longitude": -122.4194,
            "radius": 200.0,
            "notifyOnEntry": true,
            "notifyOnExit": true,
        ])
        XCTAssertTrue(added)
        XCTAssertTrue(db.geofenceExists("office"))

        let geofence = db.getGeofence("office")
        XCTAssertNotNil(geofence)
        XCTAssertEqual(geofence?["identifier"] as? String, "office")

        let geofences = db.getGeofences()
        XCTAssertEqual(geofences.count, 1)

        let _ = db.deleteGeofence("office")
        XCTAssertFalse(db.geofenceExists("office"))
    }

    func testDatabaseLogCRUD() {
        let db = TraceletDatabase(inMemory: true)

        db.insertLog(level: "info", message: "Test log entry")
        db.insertLog(level: "error", message: "Test error")

        let logStr = db.getLogForEmail()
        XCTAssertTrue(logStr.contains("Test log entry") || !logStr.isEmpty)

        let _ = db.deleteAllLogs()
    }

    // MARK: - DeltaEncoder

    func testDeltaEncoderEmptyInput() {
        let result = DeltaEncoder.encode([], precision: 6)
        XCTAssertTrue(result.isEmpty)
    }

    func testDeltaEncoderSingleLocation() {
        let locations: [[String: Any]] = [
            [
                "coords": [
                    "latitude": 37.7749,
                    "longitude": -122.4194,
                ] as [String: Any],
                "timestamp": "2024-01-01T00:00:00Z",
            ]
        ]

        let result = DeltaEncoder.encode(locations, precision: 6)
        XCTAssertEqual(result.count, 1)
    }

    // MARK: - ConfigManager — null-merge protection

    func testConfigManagerPartialUpdateDoesNotOverwriteUrlWithNull() {
        let config = ConfigManager()
        config.reset(nil)

        // Simulate ready() setting an HTTP URL
        let _ = config.setConfig([
            "http": ["url": "https://example.com/api"] as [String: Any],
        ])
        XCTAssertEqual(config.getUrl(), "https://example.com/api")

        // Simulate a partial setConfig — Dart always serialises ALL sections
        // including http with url=NSNull() by default
        let _ = config.setConfig([
            "app": ["heartbeatInterval": -1] as [String: Any],
            "http": ["url": NSNull(), "autoSync": true] as [String: Any],
        ])

        // URL must NOT be wiped
        XCTAssertEqual(config.getUrl(), "https://example.com/api")
        // The non-null value must still be applied
        XCTAssertTrue(config.getAutoSync())
    }

    func testConfigManagerExplicitUrlOverwriteStillWorks() {
        let config = ConfigManager()
        config.reset(nil)

        let _ = config.setConfig([
            "http": ["url": "https://old.example.com"] as [String: Any],
        ])
        XCTAssertEqual(config.getUrl(), "https://old.example.com")

        let _ = config.setConfig([
            "http": ["url": "https://new.example.com"] as [String: Any],
        ])
        XCTAssertEqual(config.getUrl(), "https://new.example.com")
    }

    // MARK: - Database — deleteSyncedLocations

    func testDeleteSyncedLocationsRemovesOnlySyncedRows() {
        let db = TraceletDatabase(inMemory: true)

        let uuid1 = db.insertLocation([
            "uuid": "sync-1",
            "latitude": 37.77, "longitude": -122.42,
            "accuracy": 5.0, "speed": 0.0, "heading": 0.0, "altitude": 0.0,
            "timestamp": "2024-01-01T00:00:00Z",
        ])
        let uuid2 = db.insertLocation([
            "uuid": "sync-2",
            "latitude": 37.78, "longitude": -122.43,
            "accuracy": 5.0, "speed": 0.0, "heading": 0.0, "altitude": 0.0,
            "timestamp": "2024-01-01T01:00:00Z",
        ])

        // Mark only the first as synced
        db.markSynced(uuids: [uuid1])

        XCTAssertEqual(db.getLocationCount(), 2)

        // Delete synced — only uuid1 should be removed
        let deleted = db.deleteSyncedLocations()
        XCTAssertEqual(deleted, 1)
        XCTAssertEqual(db.getLocationCount(), 1)

        // Remaining location should be the un-synced one
        let remaining = db.getLocations()
        XCTAssertEqual(remaining.first?["uuid"] as? String, "sync-2")
    }

    func testDeleteSyncedLocationsReturnsZeroWhenNoneSynced() {
        let db = TraceletDatabase(inMemory: true)

        let _ = db.insertLocation([
            "uuid": "not-synced",
            "latitude": 1.0, "longitude": 2.0,
            "accuracy": 5.0, "speed": 0.0, "heading": 0.0, "altitude": 0.0,
            "timestamp": "2024-01-01T00:00:00Z",
        ])

        let deleted = db.deleteSyncedLocations()
        XCTAssertEqual(deleted, 0)
        XCTAssertEqual(db.getLocationCount(), 1)
    }
}

// MARK: - Mock Delegate

private class MockDelegate: TraceletDelegate {
    var onLocation: ((TraceletSdk, [String: Any]) -> Void)?
    var onPowerSave: ((TraceletSdk, Bool) -> Void)?
    var onEnabledChange: ((TraceletSdk, Bool) -> Void)?

    func tracelet(_ sdk: TraceletSdk, didUpdateLocation location: [String: Any]) {
        onLocation?(sdk, location)
    }
    func tracelet(_ sdk: TraceletSdk, didChangeMotion data: [String: Any]) {}
    func tracelet(_ sdk: TraceletSdk, didChangeActivity data: [String: Any]) {}
    func tracelet(_ sdk: TraceletSdk, didChangeProvider data: [String: Any]) {}
    func tracelet(_ sdk: TraceletSdk, didTriggerGeofence data: [String: Any]) {}
    func tracelet(_ sdk: TraceletSdk, didChangeGeofences data: [String: Any]) {}
    func tracelet(_ sdk: TraceletSdk, didHeartbeat data: [String: Any]) {}
    func tracelet(_ sdk: TraceletSdk, didSyncHttp data: [String: Any]) {}
    func tracelet(_ sdk: TraceletSdk, didSchedule data: [String: Any]) {}
    func tracelet(_ sdk: TraceletSdk, didChangePowerSave isPowerSave: Bool) {
        onPowerSave?(sdk, isPowerSave)
    }
    func tracelet(_ sdk: TraceletSdk, didChangeConnectivity data: [String: Any]) {}
    func tracelet(_ sdk: TraceletSdk, didChangeEnabled enabled: Bool) {
        onEnabledChange?(sdk, enabled)
    }
    func tracelet(_ sdk: TraceletSdk, didAuthorize data: [String: Any]) {}
}
