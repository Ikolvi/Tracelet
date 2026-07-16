import XCTest
import CoreMotion
@testable import TraceletSDK

final class MotionDetectorTests: XCTestCase {

    var configManager: ConfigManager!
    var stateManager: StateManager!
    var eventDispatcher: DummyEventDispatcher!
    var logger: TraceletLogger!
    var detector: MotionDetector!

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        defaults.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        configManager = ConfigManager()
        stateManager = StateManager()
        eventDispatcher = DummyEventDispatcher()

        // Force accelerometer-only mode with a 1-min timeout. Seed the still
        // threshold/sample-count so the state-machine assertions below are
        // deterministic regardless of config defaults.
        _ = configManager.setConfig([
            "motion": [
                "disableMotionActivityUpdates": true,
                "stopTimeout": 1,
                "stillThreshold": 0.15,
                "stillSampleCount": 50
            ]
        ])

        stateManager.isMoving = true

        logger = TraceletLogger(configManager: configManager)
        detector = MotionDetector(
            configManager: configManager,
            stateManager: stateManager,
            eventDispatcher: eventDispatcher,
            logger: logger
        )
        detector.start()
    }

    override func tearDown() {
        detector.stop()
        super.tearDown()
    }

    func testSustainedStillnessStartsStopTimeoutButKeepsAccelerometerRunning() {
        XCTAssertTrue(stateManager.isMoving, "Should start in moving state")

        // Send 49 samples of stillness (1.0g on Z axis)
        // 50 samples are required (MotionDetector.stillSampleCount = 50)
        let stillAcc = CMAcceleration(x: 0, y: 0, z: 1.0)
        for _ in 0..<49 {
            detector.handleAcceleration(stillAcc)
        }

        // We can't directly check the internal Timer, but we can verify StateManager
        XCTAssertTrue(stateManager.isMoving, "Should still be moving before 50th sample")

        var timeoutStarted = false
        detector.onStopTimeoutStarted = {
            timeoutStarted = true
        }

        // 50th sample should trigger the stop-timeout countdown
        detector.handleAcceleration(stillAcc)

        let expectation = XCTestExpectation(description: "Timeout started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(timeoutStarted, "Stop timeout should be started")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testSustainedMotionDuringStopTimeoutAbortsStopTransition() {
        var timeoutStarted = false
        var timeoutCancelled = false

        detector.onStopTimeoutStarted = { timeoutStarted = true }
        detector.onStopTimeoutCancelled = { timeoutCancelled = true }

        // Send 50 samples of stillness to trigger countdown
        let stillAcc = CMAcceleration(x: 0, y: 0, z: 1.0)
        for _ in 0..<50 {
            detector.handleAcceleration(stillAcc)
        }

        // Wait for main queue dispatch of startStopTimeoutCountdown
        let startExpectation = XCTestExpectation(description: "Timeout started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(timeoutStarted, "Stop timeout should be started")
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 1.0)

        // Simulate SUSTAINED motion: motionAbortCount (5) consecutive bumps
        // (magnitude 0.5 > 0.15 threshold). Only sustained motion may abort.
        let bumpAcc = CMAcceleration(x: 0, y: 0, z: 1.5)
        for _ in 0..<5 {
            detector.handleAcceleration(bumpAcc)
        }

        let cancelExpectation = XCTestExpectation(description: "Timeout cancelled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(timeoutCancelled, "Stop timeout should be cancelled because sustained motion resumed")
            XCTAssertTrue(self.stateManager.isMoving, "State should remain moving")
            cancelExpectation.fulfill()
        }
        wait(for: [cancelExpectation], timeout: 1.0)
    }

    /// A single above-threshold sample (sensor noise / a stray bump) during the
    /// stop-timeout countdown must NOT abort it. Aborting on one sample resets
    /// all stillness progress and can keep the device stuck in the moving state
    /// (continuous GPS, battery drain) — the regression this guards against.
    func testSingleBumpDuringStopTimeoutDoesNotAbort() {
        var timeoutCancelled = false
        detector.onStopTimeoutCancelled = { timeoutCancelled = true }

        let stillAcc = CMAcceleration(x: 0, y: 0, z: 1.0)
        for _ in 0..<50 { detector.handleAcceleration(stillAcc) }

        let startExpectation = XCTestExpectation(description: "Timeout started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { startExpectation.fulfill() }
        wait(for: [startExpectation], timeout: 1.0)

        // Four bumps — below motionAbortCount (5) — must not cancel.
        let bumpAcc = CMAcceleration(x: 0, y: 0, z: 1.5)
        for _ in 0..<4 { detector.handleAcceleration(bumpAcc) }

        let exp = XCTestExpectation(description: "Timeout survives single bumps")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertFalse(timeoutCancelled, "A few stray bumps must not cancel the stop timeout")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    /// A still sample arriving between stray bumps resets the motion streak, so
    /// the countdown survives intermittent noise indefinitely.
    func testIntermittentNoiseDuringStopTimeoutDoesNotAbort() {
        var timeoutCancelled = false
        detector.onStopTimeoutCancelled = { timeoutCancelled = true }

        let stillAcc = CMAcceleration(x: 0, y: 0, z: 1.0)
        for _ in 0..<50 { detector.handleAcceleration(stillAcc) }

        let startExpectation = XCTestExpectation(description: "Timeout started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { startExpectation.fulfill() }
        wait(for: [startExpectation], timeout: 1.0)

        // Alternate bumps and still samples: the motion streak never reaches 5.
        let bumpAcc = CMAcceleration(x: 0, y: 0, z: 1.5)
        for _ in 0..<10 {
            detector.handleAcceleration(bumpAcc)
            detector.handleAcceleration(bumpAcc)
            detector.handleAcceleration(stillAcc) // resets motion streak
        }

        let exp = XCTestExpectation(description: "Timeout survives intermittent noise")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertFalse(timeoutCancelled, "Intermittent noise must not cancel the stop timeout")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    /// Issue #130: while stationary, a shake-magnitude sample must declare
    /// moving. This exercises the stationary branch that now stops the duty
    /// cycle (instead of the old continuous accelerometer) before resuming.
    func testShakeWhileStationaryDeclaresMoving() {
        stateManager.isMoving = false   // enter STATIONARY

        // magnitude = sqrt(0+0+2.0^2) - 1.0 = 1.0, well above the shake threshold.
        let shake = CMAcceleration(x: 0, y: 0, z: 2.0)
        detector.handleAcceleration(shake)

        let exp = XCTestExpectation(description: "moving declared after shake")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertTrue(self.stateManager.isMoving,
                          "A shake while stationary should declare moving")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    /// Issue #130: a still sample below the shake threshold while stationary
    /// must NOT declare moving (no spurious wakeups from minor noise).
    func testSmallNoiseWhileStationaryStaysStationary() {
        stateManager.isMoving = false   // enter STATIONARY

        // magnitude = sqrt(1.05^2) - 1.0 = 0.05, below the 0.15 shake threshold.
        let noise = CMAcceleration(x: 0, y: 0, z: 1.05)
        for _ in 0..<10 { detector.handleAcceleration(noise) }

        let exp = XCTestExpectation(description: "remains stationary")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertFalse(self.stateManager.isMoving,
                           "Sub-threshold noise must not wake the detector")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
}

// Dummy dispatcher for testing
class DummyEventDispatcher: TraceletEventSending {
    func sendMotionChange(_ data: [String : Any]) {}
    func sendSpeedMotionChange(_ data: [String : Any]) {}
    func sendLocation(_ data: [String : Any]) {}
    func sendActivityChange(_ data: [String : Any]) {}
    func sendGeofencesChange(_ data: [String : Any]) {}
    func sendGeofence(_ data: [String : Any]) {}
    func sendHeartbeat(_ data: [String : Any]) {}
    func sendHttp(_ data: [String : Any]) {}
    func sendProviderChange(_ data: [String : Any]) {}
    func sendConnectivityChange(_ data: [String : Any]) {}
    func sendEnabledChange(_ enabled: Bool) {}
    func sendPowerSaveChange(_ isPowerSave: Bool) {}
    func sendNotificationAction(_ data: [String : Any]) {}
    func sendAuthorization(_ data: [String : Any]) {}
    func sendRemoteConfigEvent(_ data: [String : Any]) {}
    func sendSchedule(_ data: [String : Any]) {}
    func sendWatchPosition(_ data: [String : Any]) {}
    func sendTrip(_ data: [String : Any]) {}
    func sendBudgetAdjustment(_ data: [String : Any]) {}
    func sendSpeedMotionEvent(_ data: [String : Any]) {}
    func sendDrivingEvent(_ data: [String : Any]) {}
    func sendImpact(_ data: [String : Any]) {}
    func sendModeChange(_ data: [String : Any]) {}
    func hasListener(eventName: String) -> Bool { return false }
}
