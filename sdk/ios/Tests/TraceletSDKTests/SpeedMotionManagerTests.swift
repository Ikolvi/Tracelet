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
        stationaryMode: String = "periodic",
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
        XCTAssertEqual(event?["state"], "slowing")
        XCTAssertEqual(event?["previousState"], "moving")
        XCTAssertEqual(event?["trackingMode"], "continuous")
    }

    func testSlowingReturnsToMovingWhenSpeedClimbs() {
        makeManager(stationaryDelaySeconds: 60)

        manager.onLocation(speed: 5.0)
        manager.onLocation(speed: 0.5)
        XCTAssertEqual(manager.state, .slowing)

        manager.onLocation(speed: 3.0)
        XCTAssertEqual(manager.state, .moving)
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
        makeManager(stationaryDelaySeconds: 0, stationaryMode: "geofences")

        manager.onLocation(speed: 5.0)
        manager.onLocation(speed: 0.1)
        manager.onLocation(speed: 0.1)

        XCTAssertEqual(manager.state, .stationary)
        XCTAssertTrue(delegate.switchedToStationaryGeofences)
        XCTAssertFalse(delegate.switchedToStationaryPeriodic)
        XCTAssertEqual(delegate.speedMotionEvents.last?["trackingMode"], "geofences")
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
        XCTAssertEqual(event?["state"], "moving")
        XCTAssertEqual(event?["previousState"], "stationary")
        XCTAssertEqual(event?["trackingMode"], "continuous")
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
        XCTAssertEqual(stateManager.speedMotionState, "slowing")

        manager.onLocation(speed: 0.1)
        XCTAssertEqual(stateManager.speedMotionState, "stationary")
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
        func emitSpeedMotionEvent(state: String, previousState: String, trackingMode: String) {
            speedMotionEvents.append([
                "state": state,
                "previousState": previousState,
                "trackingMode": trackingMode,
            ])
        }
    }
}
