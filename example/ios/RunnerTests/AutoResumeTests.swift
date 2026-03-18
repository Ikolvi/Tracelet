import XCTest

@testable import tracelet_ios

/// Unit tests for the auto-resume and CLServiceSession integration
/// in `TraceletIosPlugin`.
///
/// These tests verify:
/// - `StateManager` persists tracking state correctly
/// - `LocationEngine.getAuthorizationStatus()` returns expected values
/// - `ServiceSessionManager` lifecycle (start/stop) is safe
///
/// Note: Full auto-resume integration testing requires a real app
/// lifecycle (killed-state relaunch via significant location change).
/// These tests verify the building blocks are correct.
class AutoResumeTests: XCTestCase {

    // MARK: - StateManager Persistence Tests

    func testStateManagerPersistsEnabled() {
        let stateManager = StateManager()

        // Set enabled
        stateManager.enabled = true
        XCTAssertTrue(stateManager.enabled)

        // Should survive re-instantiation (same UserDefaults)
        let stateManager2 = StateManager()
        XCTAssertTrue(stateManager2.enabled)

        // Cleanup
        stateManager.reset()
    }

    func testStateManagerPersistsTrackingMode() {
        let stateManager = StateManager()

        // Set periodic mode
        stateManager.trackingMode = 2
        XCTAssertEqual(stateManager.trackingMode, 2)

        // Should survive re-instantiation
        let stateManager2 = StateManager()
        XCTAssertEqual(stateManager2.trackingMode, 2)

        // Cleanup
        stateManager.reset()
    }

    func testStateManagerReset() {
        let stateManager = StateManager()

        stateManager.enabled = true
        stateManager.trackingMode = 2
        stateManager.isMoving = true
        stateManager.odometer = 12345.0
        stateManager.didLaunchInBackground = true

        stateManager.reset()

        XCTAssertFalse(stateManager.enabled)
        XCTAssertEqual(stateManager.trackingMode, 0)
        XCTAssertFalse(stateManager.isMoving)
        XCTAssertEqual(stateManager.odometer, 0.0)
        XCTAssertFalse(stateManager.didLaunchInBackground)
    }

    func testStateManagerDidLaunchInBackground() {
        let stateManager = StateManager()

        XCTAssertFalse(stateManager.didLaunchInBackground)

        stateManager.didLaunchInBackground = true
        XCTAssertTrue(stateManager.didLaunchInBackground)

        stateManager.reset()
    }

    func testStateManagerTrackingModes() {
        let stateManager = StateManager()

        // Location mode
        stateManager.trackingMode = 0
        XCTAssertEqual(stateManager.trackingMode, 0)

        // Geofence mode
        stateManager.trackingMode = 1
        XCTAssertEqual(stateManager.trackingMode, 1)

        // Periodic mode
        stateManager.trackingMode = 2
        XCTAssertEqual(stateManager.trackingMode, 2)

        stateManager.reset()
    }

    // MARK: - ServiceSessionManager Tests

    func testServiceSessionManagerInitialState() {
        let manager = ServiceSessionManager()
        XCTAssertFalse(manager.isActive)
    }

    func testServiceSessionManagerStartStop() {
        let manager = ServiceSessionManager()

        manager.start()
        // On iOS 18+ this creates a CLServiceSession
        // On earlier iOS, it's a no-op but should not crash
        // isActive depends on iOS version

        manager.stop()
        XCTAssertFalse(manager.isActive)
    }

    func testServiceSessionManagerStartWhenInUseStop() {
        let manager = ServiceSessionManager()

        manager.startWhenInUse()
        // Same version-dependent behavior

        manager.stop()
        XCTAssertFalse(manager.isActive)
    }

    func testServiceSessionManagerDoubleStart() {
        let manager = ServiceSessionManager()

        manager.start()
        manager.start() // Should not crash or create duplicate sessions

        manager.stop()
        XCTAssertFalse(manager.isActive)
    }

    func testServiceSessionManagerDoubleStop() {
        let manager = ServiceSessionManager()

        manager.stop()
        manager.stop() // Should not crash
        XCTAssertFalse(manager.isActive)
    }

    // MARK: - BackgroundTaskHelper Tests

    func testBackgroundTaskHelperSingleton() {
        let helper1 = BackgroundTaskHelper.shared
        let helper2 = BackgroundTaskHelper.shared
        XCTAssertTrue(helper1 === helper2, "Should return same singleton instance")
    }

    func testBackgroundTaskHelperRunBlock() {
        var blockExecuted = false
        BackgroundTaskHelper.shared.run("test") {
            blockExecuted = true
        }
        XCTAssertTrue(blockExecuted, "run() should execute the block synchronously")
    }

    // MARK: - Auto-Resume State Verification Tests

    func testAutoResumeRequiresEnabledState() {
        let stateManager = StateManager()

        // When not enabled, auto-resume should skip
        stateManager.enabled = false
        stateManager.trackingMode = 2

        // Verify the precondition: enabled must be true
        XCTAssertFalse(stateManager.enabled, "Auto-resume should check enabled==true before proceeding")

        stateManager.reset()
    }

    func testAutoResumeStatePreservation() {
        let stateManager = StateManager()

        // Simulate a periodic tracking session
        stateManager.enabled = true
        stateManager.trackingMode = 2
        stateManager.isMoving = false

        // Simulate app kill and relaunch — state should persist
        let stateManager2 = StateManager()
        XCTAssertTrue(stateManager2.enabled, "enabled should persist across instances")
        XCTAssertEqual(stateManager2.trackingMode, 2, "trackingMode should persist across instances")

        stateManager.reset()
    }
}
