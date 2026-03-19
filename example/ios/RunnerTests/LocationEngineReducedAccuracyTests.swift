import XCTest
@testable import tracelet_ios
import CoreLocation

/// Tests for reduced accuracy handling and locationSource classification
/// in `LocationEngine.buildLocationMap()`.
final class LocationEngineReducedAccuracyTests: XCTestCase {

    private var engine: LocationEngine!

    override func setUp() {
        super.setUp()
        let config = ConfigManager()
        let state = StateManager()
        let db = TraceletDatabase(inMemory: true)
        let events = StubEventSender()
        engine = LocationEngine(
            configManager: config,
            stateManager: state,
            eventDispatcher: events,
            database: db
        )
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    // MARK: - Helper

    private func buildLocation(accuracy: Double) -> CLLocation {
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            altitude: 30,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 10,
            timestamp: Date()
        )
    }

    // MARK: - locationSource classification (full accuracy mode)

    func testLocationSource_gpsAccuracy_returnsGps() {
        let loc = buildLocation(accuracy: 10.0)
        let map = engine.buildLocationMap(loc)
        XCTAssertEqual(map["locationSource"] as? String, "gps")
    }

    func testLocationSource_atGpsThreshold_returnsGps() {
        let loc = buildLocation(accuracy: 50.0)
        let map = engine.buildLocationMap(loc)
        XCTAssertEqual(map["locationSource"] as? String, "gps")
    }

    func testLocationSource_wifiAccuracy_returnsWifi() {
        let loc = buildLocation(accuracy: 100.0)
        let map = engine.buildLocationMap(loc)
        XCTAssertEqual(map["locationSource"] as? String, "wifi")
    }

    func testLocationSource_atWifiUpperBound_returnsWifi() {
        let loc = buildLocation(accuracy: 200.0)
        let map = engine.buildLocationMap(loc)
        XCTAssertEqual(map["locationSource"] as? String, "wifi")
    }

    func testLocationSource_cellAccuracy_returnsCell() {
        let loc = buildLocation(accuracy: 500.0)
        let map = engine.buildLocationMap(loc)
        XCTAssertEqual(map["locationSource"] as? String, "cell")
    }

    func testLocationSource_veryLowAccuracy_returnsCell() {
        let loc = buildLocation(accuracy: 5000.0)
        let map = engine.buildLocationMap(loc)
        XCTAssertEqual(map["locationSource"] as? String, "cell")
    }

    func testLocationSource_negativeAccuracy_returnsUnknown() {
        // CLLocation uses negative accuracy to indicate invalid
        let loc = buildLocation(accuracy: -1.0)
        let map = engine.buildLocationMap(loc)
        XCTAssertEqual(map["locationSource"] as? String, "unknown")
    }

    // MARK: - reducedAccuracy field presence

    func testReducedAccuracy_presentInMap() {
        let loc = buildLocation(accuracy: 10.0)
        let map = engine.buildLocationMap(loc)
        XCTAssertNotNil(map["reducedAccuracy"])
    }

    func testReducedAccuracy_isBool() {
        let loc = buildLocation(accuracy: 10.0)
        let map = engine.buildLocationMap(loc)
        XCTAssertTrue(map["reducedAccuracy"] is Bool)
    }

    // MARK: - buildLocationMap standard fields

    func testBuildLocationMap_containsRequiredFields() {
        let loc = buildLocation(accuracy: 10.0)
        let map = engine.buildLocationMap(loc)

        XCTAssertNotNil(map["uuid"])
        XCTAssertNotNil(map["timestamp"])
        XCTAssertNotNil(map["coords"])
        XCTAssertNotNil(map["is_moving"])
        XCTAssertNotNil(map["odometer"])
        XCTAssertNotNil(map["locationSource"])
        XCTAssertNotNil(map["reducedAccuracy"])
        XCTAssertNotNil(map["mock"])
        XCTAssertNotNil(map["activity"])
        XCTAssertNotNil(map["battery"])
    }

    func testBuildLocationMap_coordsContainAccuracy() {
        let loc = buildLocation(accuracy: 25.0)
        let map = engine.buildLocationMap(loc)
        let coords = map["coords"] as? [String: Any]
        XCTAssertNotNil(coords)
        XCTAssertEqual(coords?["accuracy"] as? Double, 25.0)
    }

    func testBuildLocationMap_uuid_isUnique() {
        let loc = buildLocation(accuracy: 10.0)
        let map1 = engine.buildLocationMap(loc)
        let map2 = engine.buildLocationMap(loc)
        XCTAssertNotEqual(map1["uuid"] as? String, map2["uuid"] as? String)
    }
}

// MARK: - Stub event sender (no-op)

private final class StubEventSender: TraceletEventSending {
    func sendLocation(_ data: [String: Any]) {}
    func sendMotionChange(_ data: [String: Any]) {}
    func sendActivityChange(_ data: [String: Any]) {}
    func sendProviderChange(_ data: [String: Any]) {}
    func sendGeofence(_ data: [String: Any]) {}
    func sendGeofencesChange(_ data: [String: Any]) {}
    func sendHeartbeat(_ data: [String: Any]) {}
    func sendHttp(_ data: [String: Any]) {}
    func sendSchedule(_ data: [String: Any]) {}
    func sendPowerSaveChange(_ isPowerSave: Bool) {}
    func sendConnectivityChange(_ data: [String: Any]) {}
    func sendEnabledChange(_ enabled: Bool) {}
    func sendNotificationAction(_ data: [String: Any]) {}
    func sendAuthorization(_ data: [String: Any]) {}
    func sendWatchPosition(_ data: [String: Any]) {}
    func sendRemoteConfigEvent(_ data: [String: Any]) {}
}
