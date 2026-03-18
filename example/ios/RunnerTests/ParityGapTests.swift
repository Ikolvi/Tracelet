import XCTest
@testable import tracelet_ios

/// Tests for iOS←Android parity gap fixes:
/// - `ConfigManager.hasConfig()`
/// - `StateManager.lastPeriodicLatitude/Longitude`
/// - `StateManager.addOdometer(distance:)`
final class ParityGapTests: XCTestCase {

    // MARK: - ConfigManager.hasConfig()

    func testHasConfig_defaultReturnsFalse() {
        let config = ConfigManager()
        config.reset(nil) // Clear any residual state
        // After reset, config is in memory but disk may have data.
        // Force a truly clean state by removing the key entirely.
        UserDefaults.standard.removeObject(forKey: "com.tracelet.config")
        let freshConfig = ConfigManager()
        XCTAssertFalse(freshConfig.hasConfig())
    }

    func testHasConfig_afterSetConfigReturnsTrue() {
        let config = ConfigManager()
        config.reset(nil)
        _ = config.setConfig(["geo": ["desiredAccuracy": -1]])
        XCTAssertTrue(config.hasConfig())
    }

    func testHasConfig_afterResetStillTrue() {
        // reset() writes default config to disk, so hasConfig should be true
        let config = ConfigManager()
        _ = config.setConfig(["geo": ["distanceFilter": 50.0]])
        config.reset(nil)
        XCTAssertTrue(config.hasConfig())
    }

    // MARK: - StateManager.lastPeriodicLatitude/Longitude

    func testLastPeriodicLatitude_defaultIsNaN() {
        let state = StateManager()
        state.reset()
        XCTAssertTrue(state.lastPeriodicLatitude.isNaN)
    }

    func testLastPeriodicLongitude_defaultIsNaN() {
        let state = StateManager()
        state.reset()
        XCTAssertTrue(state.lastPeriodicLongitude.isNaN)
    }

    func testLastPeriodicLatitude_setAndGet() {
        let state = StateManager()
        state.reset()
        state.lastPeriodicLatitude = 37.7749
        XCTAssertEqual(state.lastPeriodicLatitude, 37.7749, accuracy: 0.0001)
    }

    func testLastPeriodicLongitude_setAndGet() {
        let state = StateManager()
        state.reset()
        state.lastPeriodicLongitude = -122.4194
        XCTAssertEqual(state.lastPeriodicLongitude, -122.4194, accuracy: 0.0001)
    }

    func testLastPeriodicLatitude_settingNaNRemovesValue() {
        let state = StateManager()
        state.reset()
        state.lastPeriodicLatitude = 37.7749
        XCTAssertFalse(state.lastPeriodicLatitude.isNaN)
        state.lastPeriodicLatitude = .nan
        XCTAssertTrue(state.lastPeriodicLatitude.isNaN)
    }

    func testLastPeriodicLongitude_settingNaNRemovesValue() {
        let state = StateManager()
        state.reset()
        state.lastPeriodicLongitude = -122.4194
        XCTAssertFalse(state.lastPeriodicLongitude.isNaN)
        state.lastPeriodicLongitude = .nan
        XCTAssertTrue(state.lastPeriodicLongitude.isNaN)
    }

    func testLastPeriodicCoordinates_persistAcrossInstances() {
        let state1 = StateManager()
        state1.reset()
        state1.lastPeriodicLatitude = 48.8566
        state1.lastPeriodicLongitude = 2.3522

        // New instance should read the persisted values
        let state2 = StateManager()
        XCTAssertEqual(state2.lastPeriodicLatitude, 48.8566, accuracy: 0.0001)
        XCTAssertEqual(state2.lastPeriodicLongitude, 2.3522, accuracy: 0.0001)
    }

    func testReset_clearsPeriodicCoordinates() {
        let state = StateManager()
        state.lastPeriodicLatitude = 35.6762
        state.lastPeriodicLongitude = 139.6503
        state.reset()
        XCTAssertTrue(state.lastPeriodicLatitude.isNaN)
        XCTAssertTrue(state.lastPeriodicLongitude.isNaN)
    }

    // MARK: - StateManager.addOdometer(distance:)

    func testAddOdometer_addsToExistingValue() {
        let state = StateManager()
        state.reset()
        XCTAssertEqual(state.odometer, 0.0, accuracy: 0.001)
        state.addOdometer(distance: 100.0)
        XCTAssertEqual(state.odometer, 100.0, accuracy: 0.001)
        state.addOdometer(distance: 50.5)
        XCTAssertEqual(state.odometer, 150.5, accuracy: 0.001)
    }

    func testAddOdometer_zeroDistanceNoChange() {
        let state = StateManager()
        state.reset()
        state.odometer = 500.0
        state.addOdometer(distance: 0.0)
        XCTAssertEqual(state.odometer, 500.0, accuracy: 0.001)
    }

    func testAddOdometer_negativeDistanceSubtracts() {
        let state = StateManager()
        state.reset()
        state.odometer = 200.0
        state.addOdometer(distance: -50.0)
        XCTAssertEqual(state.odometer, 150.0, accuracy: 0.001)
    }

    func testAddOdometer_multipleSmallIncrements() {
        let state = StateManager()
        state.reset()
        for _ in 0..<1000 {
            state.addOdometer(distance: 1.0)
        }
        XCTAssertEqual(state.odometer, 1000.0, accuracy: 0.01)
    }

    func testAddOdometer_veryLargeDistance() {
        let state = StateManager()
        state.reset()
        state.addOdometer(distance: 40_075_000.0) // circumference of Earth in meters
        XCTAssertEqual(state.odometer, 40_075_000.0, accuracy: 0.1)
    }

    func testAddOdometer_fractionalMeters() {
        let state = StateManager()
        state.reset()
        state.addOdometer(distance: 0.001) // 1 millimeter
        state.addOdometer(distance: 0.002)
        XCTAssertEqual(state.odometer, 0.003, accuracy: 0.0001)
    }

    // MARK: - ConfigManager edge cases

    func testHasConfig_afterRemoveObjectReturnsFalse() {
        let config = ConfigManager()
        _ = config.setConfig(["geo": ["desiredAccuracy": -1]])
        XCTAssertTrue(config.hasConfig())
        UserDefaults.standard.removeObject(forKey: "com.tracelet.config")
        // Need a fresh instance since old one still has in-memory cache
        let fresh = ConfigManager()
        XCTAssertFalse(fresh.hasConfig())
    }

    func testHasConfig_multipleSetConfigCalls() {
        let config = ConfigManager()
        config.reset(nil)
        _ = config.setConfig(["geo": ["desiredAccuracy": -1]])
        _ = config.setConfig(["geo": ["distanceFilter": 100.0]])
        _ = config.setConfig(["geo": ["desiredAccuracy": 10]])
        XCTAssertTrue(config.hasConfig())
    }

    // MARK: - StateManager periodic coordinates edge cases

    func testLastPeriodicLatitude_extremeValues() {
        let state = StateManager()
        state.reset()
        // Test valid latitude range boundaries
        state.lastPeriodicLatitude = 90.0
        XCTAssertEqual(state.lastPeriodicLatitude, 90.0, accuracy: 0.0001)
        state.lastPeriodicLatitude = -90.0
        XCTAssertEqual(state.lastPeriodicLatitude, -90.0, accuracy: 0.0001)
    }

    func testLastPeriodicLongitude_extremeValues() {
        let state = StateManager()
        state.reset()
        // Test valid longitude range boundaries
        state.lastPeriodicLongitude = 180.0
        XCTAssertEqual(state.lastPeriodicLongitude, 180.0, accuracy: 0.0001)
        state.lastPeriodicLongitude = -180.0
        XCTAssertEqual(state.lastPeriodicLongitude, -180.0, accuracy: 0.0001)
    }

    func testLastPeriodicLatitude_zeroIsValid() {
        let state = StateManager()
        state.reset()
        state.lastPeriodicLatitude = 0.0
        // Zero is a valid coordinate (equator), should NOT be treated as NaN
        XCTAssertFalse(state.lastPeriodicLatitude.isNaN)
        XCTAssertEqual(state.lastPeriodicLatitude, 0.0, accuracy: 0.0001)
    }

    func testLastPeriodicLongitude_zeroIsValid() {
        let state = StateManager()
        state.reset()
        state.lastPeriodicLongitude = 0.0
        // Zero is a valid coordinate (prime meridian), should NOT be treated as NaN
        XCTAssertFalse(state.lastPeriodicLongitude.isNaN)
        XCTAssertEqual(state.lastPeriodicLongitude, 0.0, accuracy: 0.0001)
    }

    func testLastPeriodicCoordinates_overwritesPrevious() {
        let state = StateManager()
        state.reset()
        state.lastPeriodicLatitude = 37.7749
        state.lastPeriodicLongitude = -122.4194
        // Overwrite with new location
        state.lastPeriodicLatitude = 48.8566
        state.lastPeriodicLongitude = 2.3522
        XCTAssertEqual(state.lastPeriodicLatitude, 48.8566, accuracy: 0.0001)
        XCTAssertEqual(state.lastPeriodicLongitude, 2.3522, accuracy: 0.0001)
    }

    func testLastPeriodicCoordinates_setOnlyLatitude() {
        let state = StateManager()
        state.reset()
        // Set only lat, lon should remain NaN
        state.lastPeriodicLatitude = 51.5074
        XCTAssertEqual(state.lastPeriodicLatitude, 51.5074, accuracy: 0.0001)
        XCTAssertTrue(state.lastPeriodicLongitude.isNaN)
    }

    func testLastPeriodicCoordinates_infinityHandling() {
        let state = StateManager()
        state.reset()
        // Infinity is not NaN — should be stored (even though it's invalid coords)
        state.lastPeriodicLatitude = .infinity
        XCTAssertFalse(state.lastPeriodicLatitude.isNaN)
        XCTAssertTrue(state.lastPeriodicLatitude.isInfinite)
    }

    // MARK: - StateManager.reset() comprehensive

    func testReset_odometerIsZero() {
        let state = StateManager()
        state.odometer = 999.9
        state.addOdometer(distance: 0.1)
        state.reset()
        XCTAssertEqual(state.odometer, 0.0, accuracy: 0.001)
    }

    func testReset_allStateFieldsCleared() {
        let state = StateManager()
        state.enabled = true
        state.trackingMode = 1
        state.schedulerEnabled = true
        state.isMoving = true
        state.odometer = 5000.0
        state.didLaunchInBackground = true
        state.lastLocationTime = 1234567890.0
        state.lastPeriodicLatitude = 37.0
        state.lastPeriodicLongitude = -122.0
        state.reset()
        XCTAssertFalse(state.enabled)
        XCTAssertEqual(state.trackingMode, 0)
        XCTAssertFalse(state.schedulerEnabled)
        XCTAssertFalse(state.isMoving)
        XCTAssertEqual(state.odometer, 0.0, accuracy: 0.001)
        XCTAssertFalse(state.didLaunchInBackground)
        XCTAssertEqual(state.lastLocationTime, 0.0, accuracy: 0.001)
        XCTAssertTrue(state.lastPeriodicLatitude.isNaN)
        XCTAssertTrue(state.lastPeriodicLongitude.isNaN)
    }
}
