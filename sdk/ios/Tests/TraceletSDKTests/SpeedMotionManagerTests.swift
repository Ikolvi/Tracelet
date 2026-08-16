import XCTest
@testable import TraceletSDK

/// Unit tests for `SpeedMotionManager` — GPS-speed motion state machine.
final class SpeedMotionManagerTests: XCTestCase {

    private var stateManager: StateManager!
    private var delegate: RecordingDelegate!
    private var manager: SpeedMotionManager!

    override func setUp() {
        super.setUp()
        stateManager = StateManager()
        stateManager.reset()
        stateManager.speedMotionState = nil
        stateManager.speedLowCount = 0
        stateManager.speedWakeCount = 0
        stateManager.speedLastTransition = 0
        delegate = RecordingDelegate()
    }

    override func tearDown() {
        manager?.stop()
        manager = nil
        delegate = nil
        stateManager = nil
        super.tearDown()
    }

    private func makeManager(
        movingThreshold: Double = 1.5,
        stationaryDelaySeconds: Int = 2,
        stationaryMode: StationaryTrackingMode = .periodic,
        wakeConfirmCount: Int = 1
    ) {
        manager = SpeedMotionManager(stateManager: stateManager)
        manager.speedMovingThreshold = movingThreshold
        manager.speedStationaryDelay = stationaryDelaySeconds
        manager.stationaryTrackingMode = stationaryMode
        manager.speedWakeConfirmCount = wakeConfirmCount
        manager.delegate = delegate
        manager.start()
    }

    // MARK: - Default state

    func testStartsInMovingStateWithNoPersistedState() {
        makeManager()
        XCTAssertEqual(manager.state, .moving)
    }

    func testRestoresStationaryStateFromPersistence() {
        stateManager.speedMotionState = SpeedMotionManager.SpeedMotionState.stationary.rawValue
        makeManager()
        XCTAssertEqual(manager.state, .stationary)
    }

    // MARK: - Hysteresis band

    /// Leaving MOVING takes a clearer signal than entering it did.
    ///
    /// One threshold used to govern both directions, so a pace that varied
    /// either side of it — every ordinary walk does — oscillated
    /// MOVING → SLOWING → STATIONARY → MOVING, and a completed countdown took
    /// the continuous stream down while the user was still walking. The default
    /// entry threshold was 1.5 m/s, above an average walking pace of ~1.4.
    func testAWalkingPaceStaysMovingInsideTheHysteresisBand() {
        makeManager(movingThreshold: 0.9, stationaryDelaySeconds: 60)

        // Enters on a brisk fix, then drifts across the entry threshold the way
        // a real walk does.
        manager.onLocation(speed: 1.5)
        XCTAssertEqual(manager.state, .moving)

        for speed in [1.31, 0.85, 1.48, 0.72, 1.40] {
            manager.onLocation(speed: speed)
            XCTAssertEqual(
                manager.state, .moving,
                "\(speed) m/s is above the stationary threshold — a walk must not stand down"
            )
        }
    }

    func testDroppingBelowTheStationaryThresholdStillSlows() {
        makeManager(movingThreshold: 0.9, stationaryDelaySeconds: 60)

        manager.onLocation(speed: 1.5)
        // 0.9 * 0.65 = 0.585, so this is genuinely stopped rather than walking.
        manager.onLocation(speed: 0.2)
        XCTAssertEqual(manager.state, .slowing)
    }

    func testAnExplicitStationaryThresholdIsClampedToTheMovingOne() {
        makeManager(movingThreshold: 2.0, stationaryDelaySeconds: 60)
        manager.speedStationaryThreshold = 5.0

        XCTAssertEqual(
            manager.effectiveStationaryThreshold, 2.0,
            "an exit threshold above the entry one would re-create the flapping"
        )
    }

    // MARK: - MOVING -> SLOWING

    func testMovingTransitionsToSlowingBelowThreshold() {
        makeManager(stationaryDelaySeconds: 60)

        manager.onLocation(speed: 5.0)
        XCTAssertEqual(manager.state, .moving)

        manager.onLocation(speed: 0.5)
        XCTAssertEqual(manager.state, .slowing)

        let event = delegate.speedMotionEvents.last
        XCTAssertEqual(event?["state"], "1")
        XCTAssertEqual(event?["previousState"], "0")
        XCTAssertEqual(event?["trackingMode"], "0")
    }

    func testSlowingReturnsToMovingWhenSpeedStaysHigh() {
        makeManager(stationaryDelaySeconds: 60)

        manager.onLocation(speed: 5.0)
        manager.onLocation(speed: 0.5)
        XCTAssertEqual(manager.state, .slowing)

        // Sustained motion is required — see SpeedMotionManager.speedAbortFixCount.
        for _ in 0..<SpeedMotionManager.speedAbortFixCount {
            manager.onLocation(speed: 3.0)
        }
        XCTAssertEqual(manager.state, .moving)
    }

    // MARK: - GPS speed noise must not restart the SLOWING countdown

    /// A still device reports a stream of `0.00 m/s` fixes with the occasional
    /// blip above the threshold (observed on-device: `1.56 m/s`). Cancelling the
    /// countdown on one such fix restarted the whole `speedStationaryDelay`
    /// window, so the device could stay MOVING indefinitely (#286 follow-up).
    func testSingleHighSpeedBlipDoesNotCancelSlowing() {
        makeManager(stationaryDelaySeconds: 60)

        manager.onLocation(speed: 5.0)
        manager.onLocation(speed: 0.0)
        XCTAssertEqual(manager.state, .slowing)

        manager.onLocation(speed: 1.56)
        XCTAssertEqual(manager.state, .slowing, "one high fix is GPS noise")

        manager.onLocation(speed: 1.56)
        XCTAssertEqual(manager.state, .slowing, "two high fixes are still noise")
    }

    func testLowFixResetsTheNoiseStreak() {
        makeManager(stationaryDelaySeconds: 60)

        manager.onLocation(speed: 5.0)
        manager.onLocation(speed: 0.0)
        // Two blips, a quiet fix, two more blips: never `speedAbortFixCount` in a row.
        manager.onLocation(speed: 1.6)
        manager.onLocation(speed: 1.6)
        manager.onLocation(speed: 0.0)
        manager.onLocation(speed: 1.6)
        manager.onLocation(speed: 1.6)
        XCTAssertEqual(manager.state, .slowing)
    }

    func testCountdownKeepsItsStartTimeAcrossANoiseBlip() {
        // 0s delay: the fix *after* entering SLOWING trips the elapsed check. If a
        // blip reset the countdown, the following low fix would not transition.
        makeManager(stationaryDelaySeconds: 0)

        manager.onLocation(speed: 5.0)
        manager.onLocation(speed: 0.1)   // enter SLOWING
        manager.onLocation(speed: 1.56)  // noise — must not restart anything
        manager.onLocation(speed: 0.1)   // elapsed >= 0 => STATIONARY

        XCTAssertEqual(manager.state, .stationary)
        XCTAssertTrue(delegate.switchedToStationaryPeriodic)
    }

    // MARK: - SLOWING -> STATIONARY

    func testSlowingTransitionsToStationaryAfterDelay() {
        // Use 0s delay so second low-speed fix trips the check immediately.
        makeManager(stationaryDelaySeconds: 0)

        manager.onLocation(speed: 5.0)
        manager.onLocation(speed: 0.1)   // enter SLOWING; slowingStartTime set
        manager.onLocation(speed: 0.1)   // elapsed >= 0 => STATIONARY

        XCTAssertEqual(manager.state, .stationary)
        XCTAssertTrue(delegate.switchedToStationaryPeriodic)
        XCTAssertFalse(delegate.switchedToStationaryGeofences)
    }

    func testSlowingTransitionsToStationaryGeofencesWhenConfigured() {
        makeManager(stationaryDelaySeconds: 0, stationaryMode: .geofences)

        manager.onLocation(speed: 5.0)
        manager.onLocation(speed: 0.1)
        manager.onLocation(speed: 0.1)

        XCTAssertEqual(manager.state, .stationary)
        XCTAssertTrue(delegate.switchedToStationaryGeofences)
        XCTAssertFalse(delegate.switchedToStationaryPeriodic)
        XCTAssertEqual(delegate.speedMotionEvents.last?["trackingMode"], "1")
    }

    // MARK: - STATIONARY -> MOVING (wake)

    func testStationaryWakesToMovingAfterWakeConfirmCount() {
        stateManager.speedMotionState = SpeedMotionManager.SpeedMotionState.stationary.rawValue
        makeManager(wakeConfirmCount: 2)

        manager.onLocation(speed: 3.0)   // wakeCount=1 — still stationary
        XCTAssertEqual(manager.state, .stationary)
        XCTAssertFalse(delegate.switchedToContinuous)

        manager.onLocation(speed: 3.0)   // wakeCount=2 => wake
        XCTAssertEqual(manager.state, .moving)
        XCTAssertTrue(delegate.switchedToContinuous)

        let event = delegate.speedMotionEvents.last
        XCTAssertEqual(event?["state"], "0")
        XCTAssertEqual(event?["previousState"], "2")
        XCTAssertEqual(event?["trackingMode"], "0")
    }

    func testStationaryLowSpeedResetsWakeCount() {
        stateManager.speedMotionState = SpeedMotionManager.SpeedMotionState.stationary.rawValue
        makeManager(wakeConfirmCount: 3)

        manager.onLocation(speed: 3.0)
        manager.onLocation(speed: 3.0)
        manager.onLocation(speed: 0.1)   // reset
        XCTAssertEqual(manager.wakeCount, 0)
        XCTAssertEqual(manager.state, .stationary)

        manager.onLocation(speed: 3.0)
        XCTAssertEqual(manager.state, .stationary)
    }

    // MARK: - Persistence

    func testStateTransitionsPersistToStateManager() {
        makeManager(stationaryDelaySeconds: 0)

        manager.onLocation(speed: 5.0)
        manager.onLocation(speed: 0.1)
        XCTAssertEqual(stateManager.speedMotionState, SpeedMotionManager.SpeedMotionState.slowing.rawValue)

        manager.onLocation(speed: 0.1)
        XCTAssertEqual(stateManager.speedMotionState, SpeedMotionManager.SpeedMotionState.stationary.rawValue)
    }

    // MARK: - Negative speed (invalid CLLocation.speed) is clamped

    func testNegativeSpeedTreatedAsStationary() {
        makeManager(stationaryDelaySeconds: 60)

        // CLLocation.speed is -1 when invalid; SpeedMotionManager must treat
        // that as "not moving" rather than signaling wake.
        manager.onLocation(speed: 5.0)
        manager.onLocation(speed: -1.0)
        XCTAssertEqual(manager.state, .slowing)
    }

    // MARK: - A moving vehicle stays MOVING (#332)

    /// The failure this guards: `LocationProcessorResult::filtered` reported a
    /// hardcoded `effective_speed: 0.0`, and both hosts feed *every* fix —
    /// accepted or not — into this machine. At a 30 m vehicle distance filter
    /// and ~1 Hz fixes, most of a 10 m/s drive is rejected, so the machine saw
    /// a stream of zeros on a motorway and ran its SLOWING countdown to
    /// completion. Given truthful speeds it must never leave MOVING.
    func testSustainedVehicleSpeedNeverLeavesMoving() {
        makeManager(stationaryDelaySeconds: 0)

        for _ in 0..<30 {
            manager.onLocation(speed: 10.0)
        }

        XCTAssertEqual(manager.state, .moving)
        XCTAssertTrue(delegate.speedMotionEvents.isEmpty, "a steady drive is not a state change")
        XCTAssertFalse(delegate.switchedToStationaryPeriodic)
    }

    /// The shape the bug actually took on the wire: real fixes at vehicle speed
    /// interleaved with the fabricated zeros the rejected ones contributed. Two
    /// filtered fixes per accepted one is the ratio a 30 m filter produces at
    /// 10 m/s. Each zero reset the high-speed streak, so the abort counter never
    /// reached `speedAbortFixCount` and the countdown expired mid-drive.
    ///
    /// Kept as a characterisation of the *input* contract: if anything ever
    /// feeds this machine a zero per rejected fix again, this fails.
    func testInterleavedFabricatedZerosWouldStrandTheMachineInSlowing() {
        makeManager(stationaryDelaySeconds: 60)

        manager.onLocation(speed: 10.0)
        manager.onLocation(speed: 0.0)   // the first fabricated zero: MOVING -> SLOWING
        XCTAssertEqual(manager.state, .slowing)

        for _ in 0..<10 {
            manager.onLocation(speed: 10.0)  // accepted fix, genuinely driving
            manager.onLocation(speed: 0.0)   // rejected fix, fabricated
            manager.onLocation(speed: 0.0)   // rejected fix, fabricated
        }

        XCTAssertEqual(
            manager.state, .slowing,
            "10 fixes at 10 m/s could not rescue the machine — which is why the "
                + "fabricated zeros had to stop at the source (#332)")
    }

    // MARK: - One event per transition (#335)

    /// Every edge used to hand-roll persist+emit and `onLocation` re-ran it
    /// afterwards, so most transitions emitted twice while `STATIONARY -> MOVING`
    /// emitted once.
    func testEachTransitionEmitsExactlyOneEvent() {
        makeManager(stationaryDelaySeconds: 0)

        manager.onLocation(speed: 5.0)
        XCTAssertEqual(delegate.speedMotionEvents.count, 0, "no transition, no event")

        manager.onLocation(speed: 0.1)   // MOVING -> SLOWING
        XCTAssertEqual(delegate.speedMotionEvents.count, 1)

        manager.onLocation(speed: 0.1)   // SLOWING -> STATIONARY
        XCTAssertEqual(delegate.speedMotionEvents.count, 2)

        manager.onLocation(speed: 5.0)   // STATIONARY -> MOVING
        XCTAssertEqual(delegate.speedMotionEvents.count, 3)

        XCTAssertEqual(
            delegate.speedMotionEvents.map { $0["previousState"]! + "->" + $0["state"]! },
            ["0->1", "1->2", "2->0"])
    }

    func testSlowingBackToMovingEmitsExactlyOneEvent() {
        makeManager(stationaryDelaySeconds: 60)

        manager.onLocation(speed: 5.0)
        manager.onLocation(speed: 0.5)   // MOVING -> SLOWING
        for _ in 0..<SpeedMotionManager.speedAbortFixCount {
            manager.onLocation(speed: 3.0)
        }

        XCTAssertEqual(manager.state, .moving)
        XCTAssertEqual(delegate.speedMotionEvents.count, 2, "one in, one out")
        XCTAssertEqual(delegate.speedMotionEvents.last?["previousState"], "1")
        XCTAssertEqual(delegate.speedMotionEvents.last?["state"], "0")
    }

    // MARK: - A no-op transition is not a transition (#337)

    /// Android emitted a `stationary → stationary` event for a `changePace(false)`
    /// on an already-stationary machine, because its `transitionTo` had no
    /// equivalent of `commitTransition`'s guard. iOS was correct; this pins it so
    /// the platforms cannot drift apart again.
    func testChangePaceThatChangesNothingEmitsNoEvent() {
        makeManager()

        manager.onManualPaceChange(isMoving: false)
        XCTAssertEqual(manager.state, .stationary)
        let afterFirst = delegate.speedMotionEvents.count

        manager.onManualPaceChange(isMoving: false)

        XCTAssertEqual(manager.state, .stationary)
        XCTAssertEqual(
            delegate.speedMotionEvents.count, afterFirst,
            "the second call agreed with the current state, so there was no edge to report")
    }

    func testNoEmittedEventReportsATransitionToTheStateItCameFrom() {
        makeManager()

        manager.onManualPaceChange(isMoving: false)
        manager.onManualPaceChange(isMoving: false)
        manager.onManualPaceChange(isMoving: true)
        manager.onManualPaceChange(isMoving: true)

        let degenerate = delegate.speedMotionEvents.filter { $0["state"] == $0["previousState"] }
        XCTAssertTrue(
            degenerate.isEmpty,
            "events reporting previousState == state: \(degenerate)")
    }

    /// The counterpart, and the reason the two above are not vacuous: a guard
    /// that suppressed everything would satisfy them both.
    func testChangePaceThatDoesChangeTheStateStillEmits() {
        makeManager()

        manager.onManualPaceChange(isMoving: false)
        let stops = delegate.speedMotionEvents.count
        manager.onManualPaceChange(isMoving: true)

        XCTAssertEqual(manager.state, .moving)
        XCTAssertEqual(delegate.speedMotionEvents.count, stops + 1)
    }

    /// A no-op still re-asserts the tracking mode: an explicit `changePace()`
    /// should re-issue the switch even when the state machine already agreed.
    func testNoOpChangePaceStillReAssertsTheTrackingMode() {
        makeManager()

        manager.onManualPaceChange(isMoving: false)
        delegate.switchedToStationaryPeriodic = false

        manager.onManualPaceChange(isMoving: false)

        XCTAssertTrue(
            delegate.switchedToStationaryPeriodic,
            "suppressing the event must not suppress the mode switch")
    }

    // MARK: - Recording doubles

    private final class RecordingDelegate: SpeedMotionDelegate {
        var switchedToContinuous = false
        var switchedToStationaryPeriodic = false
        var switchedToStationaryGeofences = false
        var slowingStartedCount = 0
        var slowingCancelledCount = 0
        var speedMotionEvents: [[String: String]] = []

        func switchToContinuous() { switchedToContinuous = true }
        func switchToStationaryPeriodic() { switchedToStationaryPeriodic = true }
        func switchToStationaryGeofences() { switchedToStationaryGeofences = true }
        func speedMotionDidStartSlowing() { slowingStartedCount += 1 }
        func speedMotionDidCancelSlowing() { slowingCancelledCount += 1 }
        func emitSpeedMotionEvent(state: Int, previousState: Int, trackingMode: Int) {
            speedMotionEvents.append([
                "state": String(state),
                "previousState": String(previousState),
                "trackingMode": String(trackingMode),
            ])
        }
    }
}
