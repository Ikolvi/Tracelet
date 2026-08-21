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

    /// #409, the mirror image of #344 and the reason `isStreamLive` exists.
    ///
    /// A session resuming stationary while a stream is still live used to write a
    /// stationary posture into a coordinator whose engine was streaming. The core
    /// only emits the stop action when it believes the posture is `.continuous`,
    /// so every later stationary decision returned `.none` and continuous GPS ran
    /// for the rest of the session on a device correctly reported as parked.
    func testStationaryPaceWithALiveStreamMapsToContinuous() {
        XCTAssertEqual(
            TraceletSmartMotionCoordinator.coordinatorMode(
                sessionMode: .continuous, isMoving: false, isStreamLive: true,
                useGeofencesWhenStationary: false),
            .continuous,
            "the posture has to match the engine, or the stop action is never emitted")
        XCTAssertEqual(
            TraceletSmartMotionCoordinator.coordinatorMode(
                sessionMode: .continuous, isMoving: false, isStreamLive: true,
                useGeofencesWhenStationary: true),
            .continuous,
            "a live stream is a live stream whichever stationary mode is configured")
    }

    /// A live stream cannot promote a non-continuous *session* to continuous —
    /// only the posture within a continuous session is at stake.
    func testALiveStreamDoesNotOverrideANonContinuousSessionMode() {
        XCTAssertEqual(
            TraceletSmartMotionCoordinator.coordinatorMode(
                sessionMode: .geofences, isMoving: false, isStreamLive: true,
                useGeofencesWhenStationary: false),
            .stationaryGeofences)
        XCTAssertEqual(
            TraceletSmartMotionCoordinator.coordinatorMode(
                sessionMode: .periodic, isMoving: false, isStreamLive: true,
                useGeofencesWhenStationary: false),
            .stationaryPeriodic)
    }

    /// The core state machine driven through #409's exact sequence, so the trap
    /// is pinned rather than just the branch that avoids it.
    func testALiveStreamStillReachesTheStationarySwitch() {
        let core = SmartMotionCoordinator(useGeofencesWhenStationary: false)
        core.setCurrentMode(
            mode: TraceletSmartMotionCoordinator.coordinatorMode(
                sessionMode: .continuous, isMoving: false, isStreamLive: true,
                useGeofencesWhenStationary: false))

        XCTAssertEqual(
            core.onSpeedStateChange(isMoving: false), .switchToStationaryPeriodic,
            "#409: both inputs stationary with a live stream must stop it — this " +
            "returned .none before the posture accounted for the engine")
    }

    /// The field report's shape: the engine is streaming while both motion inputs
    /// say stationary, and no transition is available to say so.
    ///
    /// A session that starts or resumes stationary runs no stream by design —
    /// until something else opens one, which the #357 in-app fence evaluator
    /// does. `evaluate_state` speaks only on a *transition*, and both inputs are
    /// already where they were, so re-asserting either is deduped to `.none` and
    /// the stream survives every one of them. Only re-evaluating the state the
    /// coordinator is actually in can end it.
    func testAStreamInheritedByAStationarySessionIsEndedByAReEvaluation() {
        let core = SmartMotionCoordinator(useGeofencesWhenStationary: false)
        // A previous session settled stationary; `is_accel_moving` starts false.
        _ = core.onSpeedStateChange(isMoving: false)
        XCTAssertFalse(core.isSpeedMoving())
        XCTAssertFalse(core.isAccelMoving())

        // What reconcilePosture() writes: the engine's own state, not the pace.
        core.setCurrentMode(
            mode: TraceletSmartMotionCoordinator.coordinatorMode(
                sessionMode: .continuous, isMoving: false, isStreamLive: true,
                useGeofencesWhenStationary: false))

        XCTAssertEqual(
            core.onSpeedStateChange(isMoving: false), .none,
            "precondition: a flag the core already holds is deduped away, so the "
                + "session has nothing left to say that would stop the stream")

        XCTAssertEqual(
            core.evaluateConfigurationChange(useGeofences: false), .switchToStationaryPeriodic,
            "#409: continuous GPS on a device both inputs report as parked has to "
                + "end, and only a re-evaluation can end it")
    }

    /// The control: re-evaluating must not park a session that is genuinely moving.
    func testAReEvaluationLeavesAMovingSessionStreaming() {
        let core = SmartMotionCoordinator(useGeofencesWhenStationary: false)
        _ = core.onAccelStateChange(isMoving: true)
        core.setCurrentMode(
            mode: TraceletSmartMotionCoordinator.coordinatorMode(
                sessionMode: .continuous, isMoving: true, isStreamLive: true,
                useGeofencesWhenStationary: false))

        XCTAssertEqual(
            core.evaluateConfigurationChange(useGeofences: false), .none,
            "the accelerometer says the device is moving — the OR holds")
    }

    func testContinuousSessionStartedStationaryMapsToStationaryPosture() {
        XCTAssertEqual(
            TraceletSmartMotionCoordinator.coordinatorMode(
                sessionMode: .continuous, isMoving: false, isStreamLive: false, useGeofencesWhenStationary: false),
            .stationaryPeriodic)
    }

    func testContinuousSessionStartedStationaryHonoursGeofenceStationaryMode() {
        XCTAssertEqual(
            TraceletSmartMotionCoordinator.coordinatorMode(
                sessionMode: .continuous, isMoving: false, isStreamLive: false, useGeofencesWhenStationary: true),
            .stationaryGeofences)
    }

    func testContinuousSessionStartedMovingMapsToContinuous() {
        XCTAssertEqual(
            TraceletSmartMotionCoordinator.coordinatorMode(
                sessionMode: .continuous, isMoving: true, isStreamLive: false, useGeofencesWhenStationary: false),
            .continuous)
        // The stationary mode is irrelevant while moving.
        XCTAssertEqual(
            TraceletSmartMotionCoordinator.coordinatorMode(
                sessionMode: .continuous, isMoving: true, isStreamLive: false, useGeofencesWhenStationary: true),
            .continuous)
    }

    /// The dedicated stationary session modes are already postures — `isMoving`
    /// must not be allowed to promote them to continuous behind the caller's back.
    func testDedicatedStationarySessionModesAreUnaffectedByPace() {
        for moving in [true, false] {
            XCTAssertEqual(
                TraceletSmartMotionCoordinator.coordinatorMode(
                    sessionMode: .geofences, isMoving: moving, isStreamLive: false,
                    useGeofencesWhenStationary: false),
                .stationaryGeofences)
            XCTAssertEqual(
                TraceletSmartMotionCoordinator.coordinatorMode(
                    sessionMode: .periodic, isMoving: moving, isStreamLive: false,
                    useGeofencesWhenStationary: true),
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
                sessionMode: .continuous, isMoving: false, isStreamLive: false, useGeofencesWhenStationary: false))

        // A restored-stationary speed machine re-asserting itself must stay a no-op.
        XCTAssertEqual(core.onSpeedStateChange(isMoving: false), .none)

        XCTAssertEqual(core.onAccelStateChange(isMoving: true), .switchToContinuous)
    }

    func testGpsSpeedAlsoWakesTheSessionAfterAStationaryStart() {
        let core = makeCarriedOverCoordinator()

        core.setCurrentMode(
            mode: TraceletSmartMotionCoordinator.coordinatorMode(
                sessionMode: .continuous, isMoving: false, isStreamLive: false, useGeofencesWhenStationary: false))

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
                sessionMode: .continuous, isMoving: true, isStreamLive: false, useGeofencesWhenStationary: false))
        _ = core.onAccelStateChange(isMoving: true)

        XCTAssertEqual(core.onAccelStateChange(isMoving: false), .none, "speed still says moving")
        XCTAssertEqual(core.onSpeedStateChange(isMoving: false), .switchToStationaryPeriodic)
    }
}
