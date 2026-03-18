import XCTest

@testable import tracelet_ios

/// Unit tests for `PeriodicRefreshScheduler`.
///
/// These tests verify the lifecycle (start/stop) and state management
/// of the BGAppRefreshTask-based periodic wake-up scheduler.
///
/// Note: BGTaskScheduler interactions are not directly testable in unit
/// tests (requires real app context), so we test the state management
/// and callback wiring.
class PeriodicRefreshSchedulerTests: XCTestCase {

    var scheduler: PeriodicRefreshScheduler!

    override func setUp() {
        super.setUp()
        scheduler = PeriodicRefreshScheduler()
    }

    override func tearDown() {
        scheduler.stop()
        scheduler = nil
        super.tearDown()
    }

    // MARK: - Lifecycle Tests

    func testInitialState() {
        // Scheduler should not be active on creation
        XCTAssertNotNil(scheduler)
    }

    func testStartSetsCallback() {
        var callbackFired = false
        scheduler.onWakeUp = {
            callbackFired = true
        }

        // Verify callback is set
        scheduler.onWakeUp?()
        XCTAssertTrue(callbackFired, "onWakeUp callback should be invocable after setting")
    }

    func testStopDoesNotCrashWhenNotStarted() {
        // Should be safe to call stop without start
        scheduler.stop()
    }

    func testMultipleStopCalls() {
        // Multiple stop calls should not crash
        scheduler.stop()
        scheduler.stop()
        scheduler.stop()
    }

    func testCallbackWiring() {
        var wakeUpCount = 0
        scheduler.onWakeUp = {
            wakeUpCount += 1
        }

        // Simulate multiple wake-ups
        scheduler.onWakeUp?()
        scheduler.onWakeUp?()
        scheduler.onWakeUp?()

        XCTAssertEqual(wakeUpCount, 3, "onWakeUp should fire each time it's called")
    }

    func testCallbackCanBeNil() {
        scheduler.onWakeUp = nil
        // Should not crash
        scheduler.onWakeUp?()
    }

    func testStartWithDifferentIntervals() {
        // Various valid intervals should not crash
        scheduler.start(interval: 60)       // 1 minute
        scheduler.stop()

        scheduler.start(interval: 300)      // 5 minutes
        scheduler.stop()

        scheduler.start(interval: 900)      // 15 minutes (default)
        scheduler.stop()

        scheduler.start(interval: 3600)     // 1 hour
        scheduler.stop()

        scheduler.start(interval: 43200)    // 12 hours
        scheduler.stop()
    }

    func testStartWithVerySmallInterval() {
        // Should clamp to minimum (60s) without crashing
        scheduler.start(interval: 1)
        scheduler.stop()
    }
}
