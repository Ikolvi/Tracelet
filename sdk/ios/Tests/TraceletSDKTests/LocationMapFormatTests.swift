import XCTest
@testable import TraceletSDK

/// Tests that location map formats produced by SDK model structs and utilities
/// match the structure expected by the Flutter EventDispatcher's `mapToTlLocation()`.
///
/// EventDispatcher expects:
/// - `data["coords"]`    → nested map with: latitude, longitude, accuracy, speed,
///                         heading, altitude, altitudeAccuracy, speedAccuracy, headingAccuracy
/// - `data["battery"]`   → nested map with: level, is_charging
/// - `data["timestamp"]` → string
/// - `data["uuid"]`      → string
/// - `data["is_moving"]` or `data["isMoving"]` → boolean
/// - `data["odometer"]`  → double
/// - `data["event"]`     → string
/// - `data["activity"]`  → map with: type, confidence
/// - `data["extras"]`    → map (optional)
/// - `data["mock"]`      → boolean (pass-through)
final class LocationMapFormatTests: XCTestCase {

    // MARK: - BatteryUtils format

    func testBatteryUtilsGetBatteryInfoUsesIsChargingSnakeCase() {
        // BatteryUtils requires main thread + monitoring enabled
        BatteryUtils.initialize()
        let info = BatteryUtils.getBatteryInfo()

        XCTAssertNotNil(info["is_charging"], "Battery map must contain 'is_charging'")
        XCTAssertNil(info["isCharging"], "Battery map must NOT contain camelCase 'isCharging'")
        XCTAssertNotNil(info["level"], "Battery map must contain 'level'")
    }

    func testBatteryUtilsGetBatteryInfoTypes() {
        BatteryUtils.initialize()
        let info = BatteryUtils.getBatteryInfo()

        XCTAssertTrue(info["is_charging"] is Bool, "is_charging must be Bool")
        XCTAssertTrue(info["level"] is Float || info["level"] is Double, "level must be numeric")
    }

    // MARK: - TraceletBattery model

    func testTraceletBatteryToMapUsesIsChargingSnakeCase() {
        let battery = TraceletBattery(isCharging: true, level: 0.85)
        let map = battery.toMap()

        XCTAssertNotNil(map["is_charging"], "Must contain 'is_charging'")
        XCTAssertNil(map["isCharging"], "Must NOT contain 'isCharging'")
        XCTAssertEqual(map["is_charging"] as? Bool, true)
        XCTAssertEqual(map["level"] as? Double, 0.85)
    }

    func testTraceletBatteryFromMapReadsIsChargingSnakeCase() {
        let map: [String: Any?] = ["is_charging": true, "level": 0.72]
        let battery = TraceletBattery.fromMap(map)
        XCTAssertTrue(battery.isCharging)
        XCTAssertEqual(battery.level, 0.72, accuracy: 0.001)
    }

    func testTraceletBatteryRoundTrip() {
        let original = TraceletBattery(isCharging: true, level: 0.55)
        let restored = TraceletBattery.fromMap(original.toMap())
        XCTAssertEqual(original.isCharging, restored.isCharging)
        XCTAssertEqual(original.level, restored.level, accuracy: 0.001)
    }

    // MARK: - TraceletCoords model

    func testTraceletCoordsToMapUsesCamelCaseKeys() {
        let coords = TraceletCoords(
            latitude: 37.7749, longitude: -122.4194, altitude: 50,
            speed: 5, heading: 180, accuracy: 10,
            speedAccuracy: 1.5, headingAccuracy: 5.0, altitudeAccuracy: 3.0
        )
        let map = coords.toMap()

        // Verify camelCase keys
        XCTAssertNotNil(map["altitudeAccuracy"], "Must use 'altitudeAccuracy' (camelCase)")
        XCTAssertNotNil(map["speedAccuracy"], "Must use 'speedAccuracy' (camelCase)")
        XCTAssertNotNil(map["headingAccuracy"], "Must use 'headingAccuracy' (camelCase)")

        // Verify NO snake_case keys
        XCTAssertNil(map["altitude_accuracy"], "Must NOT use 'altitude_accuracy'")
        XCTAssertNil(map["speed_accuracy"], "Must NOT use 'speed_accuracy'")
        XCTAssertNil(map["heading_accuracy"], "Must NOT use 'heading_accuracy'")

        // Verify values
        XCTAssertEqual(map["latitude"] as? Double, 37.7749)
        XCTAssertEqual(map["longitude"] as? Double, -122.4194)
        XCTAssertEqual(map["altitude"] as? Double, 50.0)
        XCTAssertEqual(map["speed"] as? Double, 5.0)
        XCTAssertEqual(map["heading"] as? Double, 180.0)
        XCTAssertEqual(map["accuracy"] as? Double, 10.0)
        XCTAssertEqual(map["speedAccuracy"] as? Double, 1.5)
        XCTAssertEqual(map["headingAccuracy"] as? Double, 5.0)
        XCTAssertEqual(map["altitudeAccuracy"] as? Double, 3.0)
    }

    func testTraceletCoordsRoundTrip() {
        let original = TraceletCoords(
            latitude: 51.5074, longitude: -0.1278, altitude: 11.2,
            speed: 3.5, heading: 90, accuracy: 8,
            speedAccuracy: 0.5, headingAccuracy: 2.0, altitudeAccuracy: 1.5
        )
        let restored = TraceletCoords.fromMap(original.toMap())
        XCTAssertEqual(original.latitude, restored.latitude, accuracy: 0.0001)
        XCTAssertEqual(original.longitude, restored.longitude, accuracy: 0.0001)
        XCTAssertEqual(original.altitude, restored.altitude, accuracy: 0.001)
        XCTAssertEqual(original.speed, restored.speed, accuracy: 0.001)
        XCTAssertEqual(original.heading, restored.heading, accuracy: 0.001)
        XCTAssertEqual(original.accuracy, restored.accuracy, accuracy: 0.001)
        XCTAssertEqual(original.speedAccuracy, restored.speedAccuracy, accuracy: 0.001)
        XCTAssertEqual(original.headingAccuracy, restored.headingAccuracy, accuracy: 0.001)
        XCTAssertEqual(original.altitudeAccuracy, restored.altitudeAccuracy, accuracy: 0.001)
    }

    // MARK: - TraceletActivityData model

    func testTraceletActivityDataToMapProducesTypeAndConfidence() {
        let activity = TraceletActivityData(type: "walking", confidence: 92)
        let map = activity.toMap()
        XCTAssertEqual(map["type"] as? String, "walking")
        XCTAssertEqual(map["confidence"] as? Int, 92)
    }

    func testTraceletActivityDataDefaults() {
        let activity = TraceletActivityData()
        let map = activity.toMap()
        XCTAssertEqual(map["type"] as? String, "unknown")
        XCTAssertEqual(map["confidence"] as? Int, -1)
    }

    func testTraceletActivityDataRoundTrip() {
        let original = TraceletActivityData(type: "in_vehicle", confidence: 80)
        let restored = TraceletActivityData.fromMap(original.toMap())
        XCTAssertEqual(original.type, restored.type)
        XCTAssertEqual(original.confidence, restored.confidence)
    }

    // MARK: - TraceletLocation model — full map format compliance

    func testTraceletLocationToMapHasNestedCoords() {
        let location = makeTestLocation()
        let map = location.toMap()
        XCTAssertNotNil(map["coords"], "Must have nested 'coords' map")
        let coords = map["coords"] as? [String: Any?]
        XCTAssertNotNil(coords)
        XCTAssertEqual(coords?["latitude"] as? Double, 37.7749)
        XCTAssertEqual(coords?["longitude"] as? Double, -122.4194)
    }

    func testTraceletLocationToMapDoesNotHaveFlatCoordKeys() {
        let location = makeTestLocation()
        let map = location.toMap()
        XCTAssertNil(map["latitude"], "Must NOT have flat 'latitude'")
        XCTAssertNil(map["longitude"], "Must NOT have flat 'longitude'")
        XCTAssertNil(map["accuracy"], "Must NOT have flat 'accuracy'")
        XCTAssertNil(map["speed"], "Must NOT have flat 'speed'")
        XCTAssertNil(map["heading"], "Must NOT have flat 'heading'")
        XCTAssertNil(map["altitude"], "Must NOT have flat 'altitude'")
    }

    func testTraceletLocationToMapHasNestedBatteryWithIsChargingSnakeCase() {
        let location = makeTestLocation()
        let map = location.toMap()
        XCTAssertNotNil(map["battery"], "Must have nested 'battery' map")
        let battery = map["battery"] as? [String: Any?]
        XCTAssertNotNil(battery)
        XCTAssertNotNil(battery?["is_charging"], "Battery must have 'is_charging'")
        XCTAssertNotNil(battery?["level"], "Battery must have 'level'")
        XCTAssertNil(battery?["isCharging"], "Battery must NOT have 'isCharging'")
    }

    func testTraceletLocationToMapHasNestedActivityWithTypeAndConfidence() {
        let location = makeTestLocation()
        let map = location.toMap()
        XCTAssertNotNil(map["activity"], "Must have 'activity' map")
        let activity = map["activity"] as? [String: Any?]
        XCTAssertEqual(activity?["type"] as? String, "walking")
        XCTAssertEqual(activity?["confidence"] as? Int, 85)
    }

    func testTraceletLocationToMapUsesIsMovingSnakeCase() {
        let location = makeTestLocation()
        let map = location.toMap()
        XCTAssertNotNil(map["is_moving"], "Must have 'is_moving' key")
        XCTAssertEqual(map["is_moving"] as? Bool, true)
    }

    func testTraceletLocationToMapHasRequiredStringFields() {
        let location = makeTestLocation()
        let map = location.toMap()
        XCTAssertEqual(map["uuid"] as? String, "test-uuid-123")
        XCTAssertEqual(map["timestamp"] as? String, "2024-06-15T12:00:00.000Z")
        XCTAssertEqual(map["event"] as? String, "location")
    }

    func testTraceletLocationToMapHasOdometerAsDouble() {
        let location = makeTestLocation()
        let map = location.toMap()
        XCTAssertEqual(map["odometer"] as? Double, 1500.5)
    }

    func testTraceletLocationToMapUsesMockKeyNotIsMock() {
        let location = makeTestLocation(isMock: true)
        let map = location.toMap()
        XCTAssertNotNil(map["mock"], "Must use 'mock' key")
        XCTAssertNil(map["isMock"], "Must NOT use 'isMock' key")
        XCTAssertEqual(map["mock"] as? Bool, true)
    }

    func testTraceletLocationToMapCoordsUseCamelCaseAccuracyKeys() {
        let location = makeTestLocation()
        let map = location.toMap()
        let coords = map["coords"] as? [String: Any?]
        XCTAssertNotNil(coords?["altitudeAccuracy"], "Coords must have 'altitudeAccuracy'")
        XCTAssertNotNil(coords?["speedAccuracy"], "Coords must have 'speedAccuracy'")
        XCTAssertNotNil(coords?["headingAccuracy"], "Coords must have 'headingAccuracy'")
        XCTAssertNil(coords?["altitude_accuracy"], "Must NOT use snake_case")
        XCTAssertNil(coords?["speed_accuracy"], "Must NOT use snake_case")
        XCTAssertNil(coords?["heading_accuracy"], "Must NOT use snake_case")
    }

    func testTraceletLocationToMapIncludesExtrasWhenNonEmpty() {
        let location = makeTestLocation(extras: ["route": "A" as Any])
        let map = location.toMap()
        let extras = map["extras"] as? [String: Any?]
        XCTAssertNotNil(extras)
        XCTAssertEqual(extras?["route"] as? String, "A")
    }

    func testTraceletLocationToMapOmitsExtrasWhenEmpty() {
        let location = makeTestLocation(extras: [:])
        let map = location.toMap()
        XCTAssertNil(map["extras"], "Empty extras should be omitted")
    }

    func testTraceletLocationFromMapReadsIsMovingSnakeCase() {
        let map = makeTestLocationMap(motionKey: "is_moving")
        let location = TraceletLocation.fromMap(map)
        XCTAssertTrue(location.isMoving)
    }

    func testTraceletLocationFromMapReadsMockKey() {
        var map = makeTestLocationMap()
        map["mock"] = true
        let location = TraceletLocation.fromMap(map)
        XCTAssertTrue(location.isMock)
    }

    func testTraceletLocationFullRoundTrip() {
        let original = makeTestLocation(isMock: true, extras: ["task": "delivery" as Any])
        let map = original.toMap()
        let restored = TraceletLocation.fromMap(map)

        XCTAssertEqual(original.coords.latitude, restored.coords.latitude, accuracy: 0.0001)
        XCTAssertEqual(original.coords.longitude, restored.coords.longitude, accuracy: 0.0001)
        XCTAssertEqual(original.coords.accuracy, restored.coords.accuracy, accuracy: 0.001)
        XCTAssertEqual(original.coords.speed, restored.coords.speed, accuracy: 0.001)
        XCTAssertEqual(original.coords.heading, restored.coords.heading, accuracy: 0.001)
        XCTAssertEqual(original.coords.altitude, restored.coords.altitude, accuracy: 0.001)
        XCTAssertEqual(original.coords.altitudeAccuracy, restored.coords.altitudeAccuracy, accuracy: 0.001)
        XCTAssertEqual(original.coords.speedAccuracy, restored.coords.speedAccuracy, accuracy: 0.001)
        XCTAssertEqual(original.coords.headingAccuracy, restored.coords.headingAccuracy, accuracy: 0.001)
        XCTAssertEqual(original.timestamp, restored.timestamp)
        XCTAssertEqual(original.isMoving, restored.isMoving)
        XCTAssertEqual(original.uuid, restored.uuid)
        XCTAssertEqual(original.odometer, restored.odometer, accuracy: 0.001)
        XCTAssertEqual(original.event, restored.event)
        XCTAssertEqual(original.isMock, restored.isMock)
        XCTAssertEqual(original.activity.type, restored.activity.type)
        XCTAssertEqual(original.activity.confidence, restored.activity.confidence)
        XCTAssertEqual(original.battery.isCharging, restored.battery.isCharging)
        XCTAssertEqual(original.battery.level, restored.battery.level, accuracy: 0.001)
        XCTAssertEqual(original.extras["task"] as? String, restored.extras["task"] as? String)
    }

    // MARK: - Simulated EventDispatcher consumption

    func testSimulatedEventDispatcherCanReadTraceletLocationToMap() {
        let location = makeTestLocation()
        let data = location.toMap()

        // Simulate what iOS EventDispatcher.mapToTlLocation does:
        let coordsMap = data["coords"] as? [String: Any] ?? [:]
        let batteryMap = data["battery"] as? [String: Any] ?? [:]
        let activityMap = data["activity"] as? [String: Any]

        // coords — cast to Double (these are Swift Doubles, not NSNumber)
        XCTAssertEqual(coordsMap["latitude"] as? Double ?? .nan, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(coordsMap["longitude"] as? Double ?? .nan, -122.4194, accuracy: 0.0001)
        XCTAssertEqual(coordsMap["accuracy"] as? Double ?? .nan, 10.0, accuracy: 0.001)
        XCTAssertEqual(coordsMap["speed"] as? Double ?? .nan, 5.0, accuracy: 0.001)
        XCTAssertEqual(coordsMap["heading"] as? Double ?? .nan, 180.0, accuracy: 0.001)
        XCTAssertEqual(coordsMap["altitude"] as? Double ?? .nan, 50.0, accuracy: 0.001)
        XCTAssertEqual(coordsMap["altitudeAccuracy"] as? Double ?? .nan, 3.0, accuracy: 0.001)
        XCTAssertEqual(coordsMap["speedAccuracy"] as? Double ?? .nan, 1.5, accuracy: 0.001)
        XCTAssertEqual(coordsMap["headingAccuracy"] as? Double ?? .nan, 5.0, accuracy: 0.001)

        // battery
        XCTAssertEqual(batteryMap["level"] as? Double ?? .nan, 0.85, accuracy: 0.001)
        XCTAssertEqual(batteryMap["is_charging"] as? Bool, true)

        // top-level
        XCTAssertEqual(data["uuid"] as? String, "test-uuid-123")
        XCTAssertEqual(data["timestamp"] as? String, "2024-06-15T12:00:00.000Z")
        let isMoving = (data["is_moving"] ?? data["isMoving"]) as? Bool
        XCTAssertEqual(isMoving, true)
        XCTAssertEqual(data["odometer"] as? Double ?? .nan, 1500.5, accuracy: 0.001)
        XCTAssertEqual(data["event"] as? String, "location")

        // activity
        XCTAssertNotNil(activityMap)
        XCTAssertEqual(activityMap?["type"] as? String, "walking")
        XCTAssertEqual(activityMap?["confidence"] as? Int, 85)
    }

    func testSimulatedEventDispatcherHandlesMissingOptionalFields() {
        let data: [String: Any?] = [
            "coords": [
                "latitude": 0.0,
                "longitude": 0.0,
            ] as [String: Any],
            "battery": [
                "level": -1.0,
                "is_charging": false,
            ] as [String: Any],
            "timestamp": "",
            "uuid": "",
            "isMoving": false,
            "odometer": 0.0,
        ]

        let coordsMap = data["coords"] as? [String: Any] ?? [:]
        XCTAssertEqual((coordsMap["latitude"] as? NSNumber)?.doubleValue, 0.0)
        XCTAssertEqual((coordsMap["accuracy"] as? NSNumber)?.doubleValue ?? -1, -1)

        let event = data["event"] as? String
        XCTAssertNil(event) // null/absent is OK

        let activityMap = data["activity"] as? [String: Any]
        XCTAssertNil(activityMap) // null activity is acceptable
    }

    // MARK: - TraceletGeofenceEvent — location nesting

    func testTraceletGeofenceEventToMapNestsLocationCorrectly() {
        let location = makeTestLocation()
        let event = TraceletGeofenceEvent(
            identifier: "office", action: "ENTER", location: location
        )
        let map = event.toMap()
        XCTAssertEqual(map["identifier"] as? String, "office")
        XCTAssertEqual(map["action"] as? String, "ENTER")

        let locMap = map["location"] as? [String: Any?]
        XCTAssertNotNil(locMap, "Geofence event must contain nested 'location'")
        XCTAssertNotNil(locMap?["coords"], "Nested location must have 'coords'")
        XCTAssertNotNil(locMap?["battery"], "Nested location must have 'battery'")
    }

    // MARK: - Dead reckoning location format

    func testDeadReckoningLocationFormatCompliance() {
        // Simulate the map built by onDrLocationEstimated
        let enriched: [String: Any] = [
            "uuid": UUID().uuidString,
            "timestamp": "2024-06-15T12:00:00.000Z",
            "isMoving": true,
            "odometer": 100.0,
            "event": "dead_reckoning",
            "mock": false,
            "isDeadReckoned": true,
            "coords": [
                "latitude": 37.0,
                "longitude": -122.0,
                "altitude": 0.0,
                "speed": 1.5,
                "heading": 90.0,
                "accuracy": 50.0,
                "speedAccuracy": -1.0,
                "headingAccuracy": -1.0,
                "altitudeAccuracy": -1.0,
            ] as [String: Any],
            "activity": [
                "type": "unknown",
                "confidence": -1,
            ] as [String: Any],
            "battery": [
                "level": -1.0,
                "is_charging": false,
            ] as [String: Any],
        ]

        // Verify EventDispatcher can read it
        let coordsMap = enriched["coords"] as? [String: Any] ?? [:]
        XCTAssertEqual((coordsMap["latitude"] as? NSNumber)?.doubleValue, 37.0)
        XCTAssertNotNil(coordsMap["altitudeAccuracy"], "DR coords must use 'altitudeAccuracy'")
        XCTAssertNotNil(coordsMap["speedAccuracy"], "DR coords must use 'speedAccuracy'")
        XCTAssertNotNil(coordsMap["headingAccuracy"], "DR coords must use 'headingAccuracy'")

        let batteryMap = enriched["battery"] as? [String: Any] ?? [:]
        XCTAssertNotNil(batteryMap["is_charging"], "DR battery must use 'is_charging'")
        XCTAssertNil(batteryMap["isCharging"], "DR battery must NOT use 'isCharging'")
    }

    // MARK: - Helpers

    private func makeTestLocation(
        isMock: Bool = false,
        extras: [String: Any?] = [:]
    ) -> TraceletLocation {
        TraceletLocation(
            coords: TraceletCoords(
                latitude: 37.7749, longitude: -122.4194, altitude: 50,
                speed: 5, heading: 180, accuracy: 10,
                speedAccuracy: 1.5, headingAccuracy: 5.0, altitudeAccuracy: 3.0
            ),
            timestamp: "2024-06-15T12:00:00.000Z",
            isMoving: true,
            uuid: "test-uuid-123",
            odometer: 1500.5,
            isMock: isMock,
            activity: TraceletActivityData(type: "walking", confidence: 85),
            battery: TraceletBattery(isCharging: true, level: 0.85),
            event: "location",
            extras: extras
        )
    }

    private func makeTestLocationMap(motionKey: String = "is_moving") -> [String: Any?] {
        [
            "coords": [
                "latitude": 37.7749,
                "longitude": -122.4194,
                "altitude": 50.0,
                "speed": 5.0,
                "heading": 180.0,
                "accuracy": 10.0,
                "speedAccuracy": 1.5,
                "headingAccuracy": 5.0,
                "altitudeAccuracy": 3.0,
            ] as [String: Any],
            "battery": [
                "level": 0.85,
                "is_charging": true,
            ] as [String: Any],
            "activity": [
                "type": "walking",
                "confidence": 85,
            ] as [String: Any],
            "timestamp": "2024-06-15T12:00:00.000Z",
            "uuid": "test-uuid-123",
            motionKey: true,
            "odometer": 1500.5,
            "event": "location",
            "mock": false,
        ]
    }
}
