import XCTest
@testable import TraceletSDK

/// Regression tests guarding the `Double` config getters against integer-encoded
/// values.
///
/// A JSON remote config frequently drops the decimal point (`1` instead of
/// `1.0`), and callers may pass a plain Swift `Int`. `cache[...] as? Double`
/// returns nil for a non-`Double` numeric (a Swift `Int` does not bridge to
/// `Double` via `as?`), which would silently collapse the value to the default.
/// All `Double` getters read through `NSNumber` so any numeric encoding coerces
/// correctly — this test locks that in.
final class ConfigManagerNumericCoercionTests: XCTestCase {

    private var config: ConfigManager!

    override func setUp() {
        super.setUp()
        config = ConfigManager()
        config.reset(nil)
    }

    override func tearDown() {
        config.reset(nil)
        config = nil
        super.tearDown()
    }

    /// Every plain `Double` getter must return the integer-encoded value as a
    /// Double rather than its default. `(key, integerInput, expected)`.
    func testDoubleGettersCoerceIntegerEncodedValues() {
        _ = config.setConfig([
            "distanceFilter": 42,
            "stationaryRadius": 30,
            "geofenceProximityRadius": 500,
            "speedMovingThreshold": 3,
            "batteryBudgetPerHour": 1,
            "harshBrakingG": 1,
            "harshAccelerationG": 1,
            "harshCorneringG": 1,
            "speedLimitKmh": 80,
            "speedingToleranceKmh": 7,
            "minSpeedForEventsKmh": 6,
            "minModeConfidence": 1,
            "crashGThreshold": 3,
            "crashMinSpeedKmh": 20,
            "fallGThreshold": 2,
            "minImpactConfidence": 1,
            "crashModelThreshold": 1,
        ])

        XCTAssertEqual(config.getDistanceFilter(), 42.0)
        XCTAssertEqual(config.getStationaryRadius(), 30.0)
        XCTAssertEqual(config.getGeofenceProximityRadius(), 500.0)
        XCTAssertEqual(config.getSpeedMovingThreshold(), 3.0)
        XCTAssertEqual(config.getBatteryBudgetPerHour(), 1.0)
        XCTAssertEqual(config.getHarshBrakingG(), 1.0)
        XCTAssertEqual(config.getHarshAccelerationG(), 1.0)
        XCTAssertEqual(config.getHarshCorneringG(), 1.0)
        XCTAssertEqual(config.getSpeedLimitKmh(), 80.0)
        XCTAssertEqual(config.getSpeedingToleranceKmh(), 7.0)
        XCTAssertEqual(config.getMinSpeedForEventsKmh(), 6.0)
        XCTAssertEqual(config.getMinModeConfidence(), 1.0)
        XCTAssertEqual(config.getCrashGThreshold(), 3.0)
        XCTAssertEqual(config.getCrashMinSpeedKmh(), 20.0)
        XCTAssertEqual(config.getFallGThreshold(), 2.0)
        XCTAssertEqual(config.getMinImpactConfidence(), 1.0)
        XCTAssertEqual(config.getCrashModelThreshold(), 1.0)
    }

    /// `shakeThreshold` / `stillThreshold` are received in m/s² and converted to
    /// g by dividing by 9.81 — the integer-encoded input must still be read.
    func testShakeAndStillThresholdCoerceIntegerEncodedValues() {
        _ = config.setConfig([
            "shakeThreshold": 9,   // m/s²
            "stillThreshold": 2,   // m/s²
        ])
        XCTAssertEqual(config.getShakeThreshold(), 9.0 / 9.81, accuracy: 1e-9)
        XCTAssertEqual(config.getStillThreshold(), 2.0 / 9.81, accuracy: 1e-9)
    }

    /// Double-encoded values must of course still work.
    func testDoubleGettersStillAcceptDoubleValues() {
        _ = config.setConfig([
            "distanceFilter": 12.5,
            "crashGThreshold": 3.25,
        ])
        XCTAssertEqual(config.getDistanceFilter(), 12.5)
        XCTAssertEqual(config.getCrashGThreshold(), 3.25)
    }

    /// Values delivered as `NSNumber` (what `JSONSerialization` produces for a
    /// fetched remote config) must coerce too — the real remote-config path.
    func testDoubleGettersAcceptNSNumberValues() {
        _ = config.setConfig([
            "distanceFilter": NSNumber(value: 15),      // integer NSNumber
            "harshBrakingG": NSNumber(value: 0.42),     // double NSNumber
        ])
        XCTAssertEqual(config.getDistanceFilter(), 15.0)
        XCTAssertEqual(config.getHarshBrakingG(), 0.42)
    }
}
