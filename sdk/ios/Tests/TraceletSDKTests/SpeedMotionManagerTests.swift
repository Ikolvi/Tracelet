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

    // MARK: - Recording doubles

    private final class RecordingDelegate: SpeedMotionDelegate {
        var switchedToContinuous = false
        var switchedToStationaryPeriodic = false
        var switchedToStationaryGeofences = false
        var speedMotionEvents: [[String: String]] = []

        func switchToContinuous() { switchedToContinuous = true }
        func switchToStationaryPeriodic() { switchedToStationaryPeriodic = true }
        func switchToStationaryGeofences() { switchedToStationaryGeofences = true }
        func emitSpeedMotionEvent(state: Int, previousState: Int, trackingMode: Int) {
            speedMotionEvents.append([
                "state": String(state),
                "previousState": String(previousState),
                "trackingMode": String(trackingMode),
            ])
        }
    }
}
