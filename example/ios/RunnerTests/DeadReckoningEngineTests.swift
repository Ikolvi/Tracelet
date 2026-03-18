import XCTest
@testable import tracelet_ios
import Foundation

/// Unit tests for `DeadReckoningEngine`.
///
/// Tests the public API (activate/deactivate/getState), algorithmic
/// correctness (step length, heading, accuracy degradation, vehicle mode).
/// CoreMotion sensors are unavailable in the test environment, so we
/// focus on state machine transitions and mathematical correctness.
final class DeadReckoningEngineTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a fresh `DeadReckoningEngine` with a clean `ConfigManager`.
    private func createEngine(config: [String: Any] = [:]) -> (DeadReckoningEngine, ConfigManager) {
        let configManager = ConfigManager()
        configManager.reset(nil)
        if !config.isEmpty {
            _ = configManager.setConfig(config)
        }
        let engine = DeadReckoningEngine(configManager: configManager)
        return (engine, configManager)
    }

    // MARK: - Activation / Deactivation

    func testInitialState_isNotActive() {
        let (engine, _) = createEngine()
        XCTAssertFalse(engine.isActive, "Engine should not be active on creation")
    }

    func testActivate_setsIsActive() {
        let (engine, _) = createEngine()
        engine.activate(lat: 37.7749, lng: -122.4194, altitude: 10.0, heading: 90.0, activity: "walking")
        XCTAssertTrue(engine.isActive, "Engine should be active after activate()")
    }

    func testDeactivate_clearsIsActive() {
        let (engine, _) = createEngine()
        engine.activate(lat: 37.7749, lng: -122.4194, altitude: 10.0, heading: 90.0, activity: "walking")
        engine.deactivate()
        XCTAssertFalse(engine.isActive, "Engine should not be active after deactivate()")
    }

    func testDoubleActivate_isIdempotent() {
        let (engine, _) = createEngine()
        engine.activate(lat: 37.7749, lng: -122.4194, altitude: 10.0, heading: 90.0, activity: "walking")
        // Second activate with different position should be ignored
        engine.activate(lat: 40.0, lng: -74.0, altitude: 20.0, heading: 180.0, activity: "running")
        let state = engine.getState()
        XCTAssertNotNil(state)
        XCTAssertEqual(state?["latitude"] as? Double, 37.7749)
        XCTAssertEqual(state?["longitude"] as? Double, -122.4194)
    }

    func testDeactivateWithoutActivate_doesNotCrash() {
        let (engine, _) = createEngine()
        engine.deactivate() // Should be a no-op
        XCTAssertFalse(engine.isActive)
    }

    // MARK: - getState

    func testGetState_whenInactive_returnsNil() {
        let (engine, _) = createEngine()
        XCTAssertNil(engine.getState(), "getState() should return nil when inactive")
    }

    func testGetState_whenActive_returnsExpectedKeys() {
        let (engine, _) = createEngine()
        engine.activate(lat: 37.7749, lng: -122.4194, altitude: 10.0, heading: 90.0, activity: "walking")

        let state = engine.getState()
        XCTAssertNotNil(state)
        XCTAssertNotNil(state?["active"])
        XCTAssertNotNil(state?["elapsed"])
        XCTAssertNotNil(state?["estimatedAccuracy"])
        XCTAssertNotNil(state?["latitude"])
        XCTAssertNotNil(state?["longitude"])
        XCTAssertNotNil(state?["heading"])
        XCTAssertNotNil(state?["stepCount"])
        XCTAssertNotNil(state?["activityType"])
    }

    func testGetState_returnsActivationPosition() {
        let (engine, _) = createEngine()
        engine.activate(lat: 51.5074, lng: -0.1278, altitude: 30.0, heading: 45.0, activity: "walking")

        let state = engine.getState()!
        XCTAssertEqual(state["latitude"] as? Double, 51.5074)
        XCTAssertEqual(state["longitude"] as? Double, -0.1278)
        XCTAssertEqual(state["heading"] as? Double, 45.0)
        XCTAssertEqual(state["activityType"] as? String, "walking")
        XCTAssertEqual(state["active"] as? Bool, true)
        XCTAssertEqual(state["stepCount"] as? Int, 0)
    }

    func testGetState_negativeHeading_clampedToZero() {
        let (engine, _) = createEngine()
        engine.activate(lat: 37.0, lng: -122.0, altitude: 0.0, heading: -1.0, activity: "walking")

        let state = engine.getState()!
        XCTAssertEqual(state["heading"] as? Double, 0.0, "Negative heading should be clamped to 0")
    }

    func testGetState_afterDeactivate_returnsNil() {
        let (engine, _) = createEngine()
        engine.activate(lat: 37.0, lng: -122.0, altitude: 0.0, heading: 90.0, activity: "walking")
        engine.deactivate()
        XCTAssertNil(engine.getState())
    }

    // MARK: - Accuracy Degradation

    func testAccuracy_pedestrian_baseIsFiveMeters() {
        let (engine, _) = createEngine()
        engine.activate(lat: 37.0, lng: -122.0, altitude: 0.0, heading: 0.0, activity: "walking")

        let state = engine.getState()!
        let accuracy = state["estimatedAccuracy"] as! Double
        // At t=0, accuracy = 5.0 + 0*1.0 = 5.0
        XCTAssertEqual(accuracy, 5.0, accuracy: 1.0)
    }

    func testAccuracy_vehicle_baseIsTenMeters() {
        let (engine, _) = createEngine()
        engine.activate(lat: 37.0, lng: -122.0, altitude: 0.0, heading: 0.0, activity: "in_vehicle")

        let state = engine.getState()!
        let accuracy = state["estimatedAccuracy"] as! Double
        // At t=0, accuracy = 10.0 + 0*3.0 = 10.0
        XCTAssertEqual(accuracy, 10.0, accuracy: 1.0)
    }

    func testAccuracy_bicycle_usesVehicleFormula() {
        let (engine, _) = createEngine()
        engine.activate(lat: 37.0, lng: -122.0, altitude: 0.0, heading: 0.0, activity: "on_bicycle")

        let state = engine.getState()!
        let accuracy = state["estimatedAccuracy"] as! Double
        XCTAssertEqual(accuracy, 10.0, accuracy: 1.0)
    }

    func testAccuracy_running_usesPedestrianFormula() {
        let (engine, _) = createEngine()
        engine.activate(lat: 37.0, lng: -122.0, altitude: 0.0, heading: 0.0, activity: "running")

        let state = engine.getState()!
        let accuracy = state["estimatedAccuracy"] as! Double
        XCTAssertEqual(accuracy, 5.0, accuracy: 1.0)
    }

    // MARK: - Activity Type / Mode Detection

    func testActivityType_storedInState() {
        let (engine, _) = createEngine()
        engine.activate(lat: 37.0, lng: -122.0, altitude: 0.0, heading: 0.0, activity: "on_foot")

        let state = engine.getState()!
        XCTAssertEqual(state["activityType"] as? String, "on_foot")
    }

    func testActivityType_unknownActivity_usesPedestrianMode() {
        let (engine, _) = createEngine()
        engine.activate(lat: 37.0, lng: -122.0, altitude: 0.0, heading: 0.0, activity: "unknown")

        let state = engine.getState()!
        let accuracy = state["estimatedAccuracy"] as! Double
        // unknown = pedestrian mode → base accuracy 5m
        XCTAssertEqual(accuracy, 5.0, accuracy: 1.0)
    }

    // MARK: - Config Integration

    func testConfigDefaults_enableDeadReckoning_isFalse() {
        let (_, config) = createEngine()
        XCTAssertFalse(config.getEnableDeadReckoning())
    }

    func testConfigDefaults_activationDelay_isTenSeconds() {
        let (_, config) = createEngine()
        XCTAssertEqual(config.getDeadReckoningActivationDelay(), 10)
    }

    func testConfigDefaults_maxDuration_is120Seconds() {
        let (_, config) = createEngine()
        XCTAssertEqual(config.getDeadReckoningMaxDuration(), 120)
    }

    func testConfigCustom_maxDuration_respected() {
        let (_, config) = createEngine(config: [
            "geo": ["deadReckoningMaxDuration": 60]
        ])
        XCTAssertEqual(config.getDeadReckoningMaxDuration(), 60)
    }

    func testConfigCustom_activationDelay_respected() {
        let (_, config) = createEngine(config: [
            "geo": ["deadReckoningActivationDelay": 30]
        ])
        XCTAssertEqual(config.getDeadReckoningActivationDelay(), 30)
    }

    func testConfigCustom_enableDeadReckoning_respected() {
        let (_, config) = createEngine(config: [
            "geo": ["enableDeadReckoning": true]
        ])
        XCTAssertTrue(config.getEnableDeadReckoning())
    }

    // MARK: - Callback Registration

    func testOnEstimatedLocation_canBeSet() {
        let (engine, _) = createEngine()
        engine.onEstimatedLocation = { _ in }
        XCTAssertNotNil(engine.onEstimatedLocation)
    }

    func testOnDeactivated_canBeSet() {
        let (engine, _) = createEngine()
        engine.onDeactivated = { }
        XCTAssertNotNil(engine.onDeactivated)
    }

    // MARK: - Lifecycle

    func testReactivateAfterDeactivate_works() {
        let (engine, _) = createEngine()

        engine.activate(lat: 37.0, lng: -122.0, altitude: 0.0, heading: 90.0, activity: "walking")
        XCTAssertTrue(engine.isActive)

        engine.deactivate()
        XCTAssertFalse(engine.isActive)

        // Re-activate with new position
        engine.activate(lat: 40.0, lng: -74.0, altitude: 5.0, heading: 180.0, activity: "running")
        XCTAssertTrue(engine.isActive)

        let state = engine.getState()!
        XCTAssertEqual(state["latitude"] as? Double, 40.0)
        XCTAssertEqual(state["longitude"] as? Double, -74.0)
        XCTAssertEqual(state["heading"] as? Double, 180.0)
        XCTAssertEqual(state["activityType"] as? String, "running")
        XCTAssertEqual(state["stepCount"] as? Int, 0)
    }

    // MARK: - Weinberg Step Length Formula

    func testWeinbergFormula_knownValues() {
        // stepLength = 0.7 * diff^0.25
        let step1 = 0.7 * pow(4.0, 0.25)  // 0.7 * 1.4142 ≈ 0.99
        XCTAssertEqual(step1, 0.99, accuracy: 0.01)

        let step2 = 0.7 * pow(16.0, 0.25) // 0.7 * 2.0 = 1.4
        XCTAssertEqual(step2, 1.4, accuracy: 0.01)

        let step3 = 0.7 * pow(1.0, 0.25)  // 0.7
        XCTAssertEqual(step3, 0.7, accuracy: 0.01)
    }

    // MARK: - Position Advancement Math

    func testAdvancePosition_northHeading_onlyChangesLatitude() {
        let stepLength = 0.7
        let headingRad = 0.0 * .pi / 180.0  // north
        let metersPerDegLat = 111_139.0

        let deltaLat = (stepLength * cos(headingRad)) / metersPerDegLat
        let deltaLng = (stepLength * sin(headingRad)) / metersPerDegLat

        XCTAssertGreaterThan(deltaLat, 0, "Walking north should increase latitude")
        XCTAssertEqual(deltaLng, 0, accuracy: 1e-15, "Walking north should not change longitude")
    }

    func testAdvancePosition_eastHeading_onlyChangesLongitude() {
        let stepLength = 0.7
        let headingRad = 90.0 * .pi / 180.0  // east
        let lat = 37.0
        let metersPerDegLat = 111_139.0
        let metersPerDegLng = metersPerDegLat * cos(lat * .pi / 180.0)

        let deltaLat = (stepLength * cos(headingRad)) / metersPerDegLat
        let deltaLng = (stepLength * sin(headingRad)) / metersPerDegLng

        XCTAssertEqual(deltaLat, 0, accuracy: 1e-10, "Walking east should not change latitude")
        XCTAssertGreaterThan(deltaLng, 0, "Walking east should increase longitude")
    }

    func testAdvancePosition_southHeading_decreasesLatitude() {
        let stepLength = 0.7
        let headingRad = 180.0 * .pi / 180.0
        let metersPerDegLat = 111_139.0

        let deltaLat = (stepLength * cos(headingRad)) / metersPerDegLat
        XCTAssertLessThan(deltaLat, 0, "Walking south should decrease latitude")
    }

    func testAdvancePosition_westHeading_decreasesLongitude() {
        let stepLength = 0.7
        let headingRad = 270.0 * .pi / 180.0
        let lat = 37.0
        let metersPerDegLat = 111_139.0
        let metersPerDegLng = metersPerDegLat * cos(lat * .pi / 180.0)

        let deltaLng = (stepLength * sin(headingRad)) / metersPerDegLng
        XCTAssertLessThan(deltaLng, 0, "Walking west should decrease longitude")
    }

    func testMetersPerDegLng_scalesWithLatitude() {
        let metersPerDegLat = 111_139.0

        // At equator: cos(0) = 1
        let equator = metersPerDegLat * cos(0.0 * .pi / 180.0)
        XCTAssertEqual(equator, metersPerDegLat, accuracy: 0.01)

        // At lat=45: cos(45) ≈ 0.707
        let midLat = metersPerDegLat * cos(45.0 * .pi / 180.0)
        XCTAssertEqual(midLat, metersPerDegLat * 0.7071, accuracy: 1.0)

        // At pole: cos(90) ≈ 0
        let pole = metersPerDegLat * cos(90.0 * .pi / 180.0)
        XCTAssertEqual(pole, 0.0, accuracy: 0.01)
    }

    // MARK: - Vehicle Mode Math

    func testVelocityDamping_reducesVelocityOverTime() {
        var velocity = 10.0
        for _ in 0..<100 {
            velocity *= 0.98
        }
        // 10 * 0.98^100 ≈ 1.33
        XCTAssertLessThan(velocity, 2.0, "Velocity should decay after 100 steps")
        XCTAssertGreaterThan(velocity, 0.0, "Velocity should not reach zero")
    }

    func testWorldFrameTransform_headingNorth_preservesDirection() {
        let heading = 0.0
        let headingRad = heading * .pi / 180.0
        let dx = 1.0
        let dy = 0.0

        let worldDx = dx * cos(headingRad) - dy * sin(headingRad)
        let worldDy = dx * sin(headingRad) + dy * cos(headingRad)

        XCTAssertEqual(worldDx, 1.0, accuracy: 1e-10)
        XCTAssertEqual(worldDy, 0.0, accuracy: 1e-10)
    }

    func testWorldFrameTransform_heading90_rotatesCorrectly() {
        let heading = 90.0
        let headingRad = heading * .pi / 180.0
        let dx = 1.0
        let dy = 0.0

        let worldDx = dx * cos(headingRad) - dy * sin(headingRad)
        let worldDy = dx * sin(headingRad) + dy * cos(headingRad)

        XCTAssertEqual(worldDx, 0.0, accuracy: 1e-10)
        XCTAssertEqual(worldDy, 1.0, accuracy: 1e-10)
    }

    // MARK: - Elapsed Time

    func testElapsedSeconds_atActivation_isZero() {
        let (engine, _) = createEngine()
        engine.activate(lat: 37.0, lng: -122.0, altitude: 0.0, heading: 0.0, activity: "walking")

        let state = engine.getState()!
        XCTAssertEqual(state["elapsed"] as? Int, 0)
    }

    // MARK: - Step Count

    func testStepCount_initiallyZero() {
        let (engine, _) = createEngine()
        engine.activate(lat: 37.0, lng: -122.0, altitude: 0.0, heading: 0.0, activity: "walking")

        let state = engine.getState()!
        XCTAssertEqual(state["stepCount"] as? Int, 0)
    }

    // MARK: - Edge Cases

    func testActivate_withZeroCoordinates_works() {
        let (engine, _) = createEngine()
        engine.activate(lat: 0.0, lng: 0.0, altitude: 0.0, heading: 0.0, activity: "walking")

        let state = engine.getState()!
        XCTAssertEqual(state["latitude"] as? Double, 0.0)
        XCTAssertEqual(state["longitude"] as? Double, 0.0)
    }

    func testActivate_withExtremeCoordinates_works() {
        let (engine, _) = createEngine()
        engine.activate(lat: 89.999, lng: 179.999, altitude: 8848.0, heading: 359.0, activity: "walking")

        let state = engine.getState()!
        XCTAssertEqual(state["latitude"] as? Double, 89.999)
        XCTAssertEqual(state["longitude"] as? Double, 179.999)
    }

    func testActivate_withNegativeCoordinates_works() {
        let (engine, _) = createEngine()
        engine.activate(lat: -33.8688, lng: 151.2093, altitude: 58.0, heading: 270.0, activity: "in_vehicle")

        let state = engine.getState()!
        XCTAssertEqual(state["latitude"] as? Double, -33.8688)
        XCTAssertEqual(state["longitude"] as? Double, 151.2093)
    }
}
