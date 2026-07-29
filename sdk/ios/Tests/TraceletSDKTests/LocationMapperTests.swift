import XCTest
@testable import TraceletSDK

/// Unit tests for `LocationMapper` — the single source of truth that maps a
/// persisted location record into the nested schema emitted by onLocation and
/// getLocations (Issue #126). Pins that DB-sourced locations use the SAME nested
/// shape as live locations, so the sync interceptor (setSyncBodyBuilder) and
/// getLocations no longer leak a flat representation. Mirrors the Android
/// `LocationMapperTest`.
final class LocationMapperTests: XCTestCase {

    private func sampleMap(
        routeContext: String? = nil,
        isMoving: Bool = true,
        odometer: Double = 1234.5
    ) -> [String: Any] {
        return LocationMapper.buildLocationMap(
            id: 42,
            uuid: "uuid-1",
            timestamp: "2026-06-08T10:00:00Z",
            latitude: 48.8566,
            longitude: 2.3522,
            altitude: 35.0,
            speed: 1.2,
            heading: 90.0,
            accuracy: 5.0,
            isMock: false,
            activity: "walking",
            activityConfidence: 75,
            routeContext: routeContext,
            isMoving: isMoving,
            odometer: odometer
        )
    }

    func testCoordsAreNestedNotFlat() {
        let map = sampleMap()
        XCTAssertNil(map["latitude"], "must NOT be flat — no top-level latitude")
        let coords = map["coords"] as? [String: Any]
        XCTAssertNotNil(coords)
        XCTAssertEqual(coords?["latitude"] as? Double, 48.8566)
        XCTAssertEqual(coords?["longitude"] as? Double, 2.3522)
        XCTAssertEqual(coords?["altitude"] as? Double, 35.0)
        XCTAssertEqual(coords?["speed"] as? Double, 1.2)
        XCTAssertEqual(coords?["heading"] as? Double, 90.0)
        XCTAssertEqual(coords?["accuracy"] as? Double, 5.0)
    }

    func testActivityIsNestedMapNotRawString() {
        let map = sampleMap()
        XCTAssertFalse(map["activity"] is String, "activity must be a nested map, not a String")
        let activity = map["activity"] as? [String: Any]
        XCTAssertEqual(activity?["type"] as? String, "walking")
        // #245: the persisted confidence — no longer hardcoded 100. Mirrors the
        // Android LocationMapperTest.
        XCTAssertEqual(activity?["confidence"] as? Int, 75)
    }

    func testBatteryIsNestedMap() {
        let battery = sampleMap()["battery"] as? [String: Any]
        XCTAssertEqual(battery?["level"] as? Double, -1.0)
        XCTAssertEqual(battery?["isCharging"] as? Bool, false)
    }

    func testPassesThroughIsMovingOdometerAndMeta() {
        let map = sampleMap(isMoving: true, odometer: 999.0)
        XCTAssertEqual(map["is_moving"] as? Bool, true)
        XCTAssertEqual(map["odometer"] as? Double, 999.0)
        XCTAssertEqual(map["event"] as? String, "location")
        XCTAssertEqual(map["mock"] as? Bool, false)
        XCTAssertEqual(map["uuid"] as? String, "uuid-1")
    }

    func testUuidFallsBackToIdWhenNil() {
        let map = LocationMapper.buildLocationMap(
            id: 7, uuid: nil, timestamp: "t", latitude: 0, longitude: 0, altitude: 0,
            speed: 0, heading: 0, accuracy: 0, isMock: false, activity: "still",
            routeContext: nil, isMoving: false, odometer: 0
        )
        XCTAssertEqual(map["uuid"] as? String, "7")
    }

    func testRouteContextNilProducesNoExtras() {
        let map = sampleMap(routeContext: nil)
        XCTAssertNil(map["extras"])
        XCTAssertNil(map["audit_hash"])
    }

    func testRouteContextCustomFieldsGoIntoExtrasRouteContext() {
        let map = sampleMap(routeContext: #"{"taskId":"task-101","driverId":"john"}"#)
        let extras = map["extras"] as? [String: Any]
        let rc = extras?["route_context"] as? [String: Any]
        XCTAssertEqual(rc?["taskId"] as? String, "task-101")
        XCTAssertEqual(rc?["driverId"] as? String, "john")
    }

    func testRouteContextAuditFieldsGoTopLevelNotIntoExtras() {
        let map = sampleMap(
            routeContext: #"{"taskId":"task-101","audit_hash":"h1","audit_previous_hash":"h0","audit_chain_index":7}"#
        )
        XCTAssertEqual(map["audit_hash"] as? String, "h1")
        XCTAssertEqual(map["audit_previous_hash"] as? String, "h0")
        XCTAssertEqual((map["audit_chain_index"] as? NSNumber)?.intValue, 7)

        let rc = (map["extras"] as? [String: Any])?["route_context"] as? [String: Any]
        XCTAssertEqual(rc?["taskId"] as? String, "task-101")
        XCTAssertNil(rc?["audit_hash"], "audit fields must not leak into extras.route_context")
        XCTAssertNil(rc?["audit_chain_index"])
    }

    func testRouteContextInvalidJsonIsIgnoredGracefully() {
        let map = sampleMap(routeContext: "not-json")
        XCTAssertNil(map["extras"])
    }

    // #280: locationSource/reducedAccuracy persisted as first-class route_context
    // keys must be promoted to top level (where Location.fromMap reads them) and
    // must NOT leak into extras.route_context.
    func testRouteContextLocationSourceAndReducedAccuracyGoTopLevelNotIntoExtras() {
        let map = sampleMap(
            routeContext: #"{"taskId":"task-1","locationSource":"gps","reducedAccuracy":true}"#
        )
        XCTAssertEqual(map["locationSource"] as? String, "gps")
        XCTAssertEqual(map["reducedAccuracy"] as? Bool, true)

        let rc = (map["extras"] as? [String: Any])?["route_context"] as? [String: Any]
        XCTAssertEqual(rc?["taskId"] as? String, "task-1")
        XCTAssertNil(rc?["locationSource"], "must not leak into extras.route_context")
        XCTAssertNil(rc?["reducedAccuracy"], "must not leak into extras.route_context")
    }

    func testRouteContextWithoutLocationSourceLeavesKeysAbsent() {
        let map = sampleMap(routeContext: #"{"taskId":"task-1"}"#)
        XCTAssertNil(map["locationSource"])
        XCTAssertNil(map["reducedAccuracy"])
    }

    func testEventTypeAndPayloadSplice() {
        let map = LocationMapper.buildLocationMap(
            id: 99,
            uuid: "uuid-99",
            timestamp: "2026-06-08T10:00:00Z",
            latitude: 0, longitude: 0, altitude: 0, speed: 0, heading: 0, accuracy: 0,
            isMock: false, activity: "still", routeContext: nil, isMoving: false, odometer: 0,
            eventType: "geofence",
            eventPayload: #"{"identifier":"zone-1","action":"ENTER"}"#
        )
        XCTAssertEqual(map["event"] as? String, "geofence")
        let geofenceMap = map["geofence"] as? [String: Any]
        XCTAssertNotNil(geofenceMap)
        XCTAssertEqual(geofenceMap?["identifier"] as? String, "zone-1")
        XCTAssertEqual(geofenceMap?["action"] as? String, "ENTER")
    }
}
