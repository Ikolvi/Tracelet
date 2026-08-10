import XCTest
@testable import TraceletSDK

/// #344: a `start()` whose committed pace is stationary must not leave the
/// SMART coordinator deaf to the accelerometer.
///
/// `TraceletSmartMotionCoordinator.syncCurrentMode()` used to map the *session*
/// mode (`stateManager.trackingMode`, which `start()` pins to `.continuous` for
/// the whole session) straight onto the coordinator's *posture*. On a start with
/// `isMoving == false` that wrote `Continuous` into a coordinator whose accel and
/// speed inputs both said stationary — a pair the core emits no action for in
/// either direction. Every subsequent shake returned `.none`, the engine was
/// never switched to continuous, no fixes were recorded and nothing synced.
///
/// Two halves are covered here: the pure mapping, and the core state machine
/// driven through the exact field sequence so the trap itself is pinned rather
/// than just the branch that avoids it.
final class SmartMotionCoordinatorSyncModeTests: XCTestCase {

    // MARK: - The mapping

    func testContinuousSessionStartedStationaryMapsToStationaryPosture() {
        XCTAssertEqual(
            TraceletSmartMotionCoordinator.coordinatorMode(
                sessionMode: .continuous, isMoving: false, useGeofencesWhenStationary: false),
            .stationaryPeriodic)
    }

    func testContinuousSessionStartedStationaryHonoursGeofenceStationaryMode() {
        XCTAssertEqual(
            TraceletSmartMotionCoordinator.coordinatorMode(
                sessionMode: .continuous, isMoving: false, useGeofencesWhenStationary: true),
            .stationaryGeofences)
    }

    func testContinuousSessionStartedMovingMapsToContinuous() {
        XCTAssertEqual(
            TraceletSmartMotionCoordinator.coordinatorMode(
                sessionMode: .continuous, isMoving: true, useGeofencesWhenStationary: false),
            .continuous)
        // The stationary mode is irrelevant while moving.
        XCTAssertEqual(
            TraceletSmartMotionCoordinator.coordinatorMode(
                sessionMode: .continuous, isMoving: true, useGeofencesWhenStationary: true),
            .continuous)
    }

    /// The dedicated stationary session modes are already postures — `isMoving`
    /// must not be allowed to promote them to continuous behind the caller's back.
    func testDedicatedStationarySessionModesAreUnaffectedByPace() {
        for moving in [true, false] {
            XCTAssertEqual(
                TraceletSmartMotionCoordinator.coordinatorMode(
                    sessionMode: .geofences, isMoving: moving, useGeofencesWhenStationary: false),
                .stationaryGeofences)
            XCTAssertEqual(
                TraceletSmartMotionCoordinator.coordinatorMode(
                    sessionMode: .periodic, isMoving: moving, useGeofencesWhenStationary: true),
                .stationaryPeriodic)
        }
    }

    // MARK: - The core state machine, driven through the field sequence

    /// Reproduces the bug report: a previous session in the same process left the
    /// speed machine STATIONARY, then `start()` synced the posture and the user
    /// shook the device.
    private func makeCarriedOverCoordinator() -> SmartMotionCoordinator {
        let core = SmartMotionCoordinator(useGeofencesWhenStationary: false)
        // Previous session settled to stationary. `is_speed_moving` defaults to
        // true, so this is the flag flip that the *next* session then dedupes
        // away — which is why the usual self-correction in
        // `startSpeedMotionManager()` cannot rescue the mapping.
        _ = core.onSpeedStateChange(isMoving: false)
        XCTAssertFalse(core.isSpeedMoving())
        XCTAssertFalse(core.isAccelMoving())
        return core
    }

    func testAccelWakesTheSessionAfterAStationaryStart() {
        let core = makeCarriedOverCoordinator()

        core.setCurrentMode(
            mode: TraceletSmartMotionCoordinator.coordinatorMode(
                sessionMode: .continuous, isMoving: false, useGeofencesWhenStationary: false))

        // A restored-stationary speed machine re-asserting itself must stay a no-op.
        XCTAssertEqual(core.onSpeedStateChange(isMoving: false), .none)

        XCTAssertEqual(core.onAccelStateChange(isMoving: true), .switchToContinuous)
    }

    func testGpsSpeedAlsoWakesTheSessionAfterAStationaryStart() {
        let core = makeCarriedOverCoordinator()

        core.setCurrentMode(
            mode: TraceletSmartMotionCoordinator.coordinatorMode(
                sessionMode: .continuous, isMoving: false, useGeofencesWhenStationary: false))

        XCTAssertEqual(core.onSpeedStateChange(isMoving: true), .switchToContinuous)
    }

    /// The negative control: the old mapping. Kept so the failure mode stays
    /// documented — writing `Continuous` while both inputs say stationary
    /// swallows the wake-up, and the coordinator never recovers on its own.
    func testWritingContinuousWhileBothInputsAreStationarySwallowsTheWakeUp() {
        let core = makeCarriedOverCoordinator()

        core.setCurrentMode(mode: .continuous)

        XCTAssertEqual(core.onAccelStateChange(isMoving: true), .none)
        XCTAssertEqual(core.onSpeedStateChange(isMoving: true), .none)
    }

    /// A start that really is moving keeps the continuous posture, and the
    /// stop-detection path out of it still works.
    func testMovingStartHoldsContinuousAndCanStillGoStationary() {
        let core = SmartMotionCoordinator(useGeofencesWhenStationary: false)
        core.setCurrentMode(
            mode: TraceletSmartMotionCoordinator.coordinatorMode(
                sessionMode: .continuous, isMoving: true, useGeofencesWhenStationary: false))
        _ = core.onAccelStateChange(isMoving: true)

        XCTAssertEqual(core.onAccelStateChange(isMoving: false), .none, "speed still says moving")
        XCTAssertEqual(core.onSpeedStateChange(isMoving: false), .switchToStationaryPeriodic)
    }
}
