import XCTest
@testable import TraceletSDK

/// Tests for `TraceletSmartMotionCoordinator` — the native layer that arbitrates
/// between the accelerometer and the GPS-speed machine, keeps the core's posture
/// in sync with the SDK, and turns the core's verdict into a mode switch.
///
/// This suite predates #344 but was never listed in the test target's `sources:`
/// allowlist in `Package.swift`, so it had never been compiled — and it did not
/// compile: `coordinator` was typed as the Rust `SmartMotionCoordinator` while
/// `sdk.smartMotionCoordinator` is the native `TraceletSmartMotionCoordinator`
/// wrapper. It also passed `"motionDetectionMode": "smart"` as a *string* to a
/// getter that only reads `as? Int`, so the config fell back to `.activity` and
/// nothing in the file would have exercised smart mode even if it had built.
/// `testSetUpActuallySelectedSmartMode` now pins that so the suite cannot
/// quietly go back to testing nothing.
///
/// **Why tracking is never started here.** `locationEngine.start()` reaches
/// `CLLocationManager.setAllowsBackgroundLocationUpdates`, which throws
/// `NSInternalInconsistencyException` unless the running bundle declares the
/// `location` background mode — a SwiftPM xctest bundle does not, and there is
/// no app host to borrow one from. So these tests set `stateManager` directly
/// and leave `enabled == false`; the force-switch handlers then bail on their
/// own `stateManager.enabled` guard and the engine is never touched, which
/// leaves the coordinator's **decision** — the returned `CoordinatorAction` and
/// the flags behind it — as the thing under test. That decision is the entire
/// product of this layer. Applying it end to end (engine, `isMoving`,
/// `motionchange`) is what the #344 issue card checks on a real device.
///
/// A fresh coordinator is built per test rather than reusing
/// `sdk.smartMotionCoordinator`: that one is created in `initialize()` and
/// survives `reset()`, so its motion flags leak between tests in this process.
final class SmartMotionCoordinatorTests: XCTestCase {

    private var sdk: TraceletSdk!
    private var coordinator: TraceletSmartMotionCoordinator!

    /// Ints, not strings — see the note above. `stopTimeout`/`heartbeatInterval`
    /// are pinned so no timer fires mid-assertion.
    private static let config: [String: Any] = [
        "motion": [
            "motionDetectionMode": MotionDetectionMode.smart.rawValue,
            "stationaryTrackingMode": StationaryTrackingMode.periodic.rawValue,
            "isMoving": false,
            "stopTimeout": 600,
        ],
        "app": ["heartbeatInterval": 0],
    ]

    override func setUp() {
        super.setUp()
        sdk = TraceletSdk.shared
        // The SDK is a process-wide singleton, so reset() is what isolates this
        // test from whatever ran before it. It has to be sandwiched: it needs
        // the managers to exist (built by ready()) and it clears `isReady` on
        // the way out.
        _ = sdk.ready(config: SmartMotionCoordinatorTests.config)
        _ = sdk.reset(SmartMotionCoordinatorTests.config)
        _ = sdk.ready(config: SmartMotionCoordinatorTests.config)

        coordinator = TraceletSmartMotionCoordinator(sdk: sdk)
    }

    override func tearDown() {
        coordinator = nil
        _ = sdk.reset()
        sdk = nil
        super.tearDown()
    }

    /// Puts the SDK in the state `start()` would leave it in, without starting
    /// the location engine.
    private func enterSession(mode: TraceletTrackingMode, isMoving: Bool) {
        sdk.stateManager.trackingMode = mode
        sdk.stateManager.isMoving = isMoving
        coordinator.syncCurrentMode()
    }

    /// Drives both coordinator inputs to stationary, the state a session that
    /// settled and stopped leaves behind.
    private func seedBothInputsStationary() {
        coordinator.onAccelStateChange(isMoving: false)
        coordinator.onSpeedStateChange(isMoving: false)
        XCTAssertFalse(coordinator.isAccelMoving)
        XCTAssertFalse(coordinator.isSpeedMoving)
    }

    // MARK: - The suite's own guard

    /// Makes every other test in this file mean something.
    func testSetUpActuallySelectedSmartMode() {
        XCTAssertEqual(sdk.configManager.getMotionDetectionMode(), .smart)
        XCTAssertEqual(sdk.configManager.getStationaryTrackingMode(), .periodic)
    }

    func testAFreshCoordinatorStartsAccelFalseSpeedTrue() {
        XCTAssertFalse(coordinator.isAccelMoving)
        XCTAssertTrue(coordinator.isSpeedMoving)
    }

    // MARK: - Posture sync (#344)

    /// The regression. A `start()` on a continuous session whose committed pace
    /// is stationary must leave the coordinator able to hear the accelerometer.
    ///
    /// The seeding is the field precondition: a previous session in the same
    /// process settled stationary, so both inputs are already false and the
    /// re-assert inside `startSpeedMotionManager()` dedupes to a no-op — the
    /// posture written by `syncCurrentMode()` is all that stands between a shake
    /// and a wake-up.
    func testAccelWakesAContinuousSessionThatStartedStationary() {
        seedBothInputsStationary()
        enterSession(mode: .continuous, isMoving: false)

        XCTAssertEqual(
            coordinator.onAccelStateChange(isMoving: true), .switchToContinuous,
            "before #344 the posture said Continuous already, so this returned .none forever")
    }

    /// The same session, woken by GPS speed instead of the accelerometer.
    func testSpeedWakesAContinuousSessionThatStartedStationary() {
        seedBothInputsStationary()
        enterSession(mode: .continuous, isMoving: false)

        XCTAssertEqual(coordinator.onSpeedStateChange(isMoving: true), .switchToContinuous)
        XCTAssertTrue(coordinator.isSpeedMoving)
    }

    /// A session that really did start moving keeps the continuous posture, so a
    /// redundant wake-up is correctly a no-op.
    func testAContinuousSessionThatStartedMovingHoldsItsPosture() {
        enterSession(mode: .continuous, isMoving: true)
        coordinator.onAccelStateChange(isMoving: true)

        XCTAssertEqual(coordinator.onAccelStateChange(isMoving: true), .none)
    }

    /// The dedicated stationary session modes are already postures and were
    /// never affected by #344 — pinned so the fix cannot regress them.
    func testAPeriodicSessionIsPromotedByTheAccelerometer() {
        seedBothInputsStationary()
        enterSession(mode: .periodic, isMoving: false)

        XCTAssertEqual(coordinator.onAccelStateChange(isMoving: true), .switchToContinuous)
        XCTAssertTrue(coordinator.isAccelMoving)
    }

    // MARK: - The OR

    func testBothInputsStationaryDowngradesOutOfContinuous() {
        enterSession(mode: .continuous, isMoving: true)
        coordinator.onAccelStateChange(isMoving: true)

        XCTAssertEqual(
            coordinator.onAccelStateChange(isMoving: false), .none,
            "speed still says moving, so the OR holds continuous")

        XCTAssertEqual(
            coordinator.onSpeedStateChange(isMoving: false), .switchToStationaryPeriodic)
    }

    /// #333: an unresolved GPS speed is *unknown*, not zero, and must not be
    /// read as proof the device is parked. No fix is ever delivered in this
    /// target, so this is the path every other test here also runs on.
    func testUnresolvedGpsSpeedDoesNotOverruleAMovingAccelerometer() {
        enterSession(mode: .continuous, isMoving: true)
        coordinator.onAccelStateChange(isMoving: true)

        coordinator.onSpeedStateChange(isMoving: false)

        XCTAssertTrue(
            coordinator.isAccelMoving,
            "the accelerometer must be left standing when no speed was resolved")
    }
}
