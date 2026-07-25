import XCTest
@testable import TraceletSDK

/// Regression tests for Issue #261 — `IosConfig.useSignificantChangesOnly` must
/// not open a `CLBackgroundActivitySession`.
///
/// On iOS 17+, `CLBackgroundActivitySession` keeps a background location
/// activity alive and auto-shows the system location indicator (Dynamic Island
/// / status-bar pill), even when continuous GPS is not running. That defeats
/// the entire point of significant-change monitoring, which is meant to be
/// low-power background location WITHOUT a persistent "ongoing location"
/// indicator.
///
/// `LocationEngine.start()` already honoured `useSignificantChangesOnly` by
/// skipping `startUpdatingLocation()`, but `TraceletSdk.start()` (and the
/// resume / motion-change paths) still opened the background activity session
/// whenever the engine was moving. Periodic mode and low-accuracy geofence-only
/// mode already avoid the session for exactly this reason; these tests lock in
/// the same treatment for significant-change-only mode.
final class SignificantChangesBackgroundSessionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // initialize() only wires up subsystems (safe before ready()); it does
        // NOT flip isReady, so we never touch reset()/stop() before a ready().
        TraceletSdk.shared.initialize()
    }

    override func tearDown() {
        let sdk = TraceletSdk.shared
        if sdk.isReadyState {
            sdk.stop()
            sdk.reset(nil)
        }
        super.tearDown()
    }

    /// The reported scenario: significant-change-only mode while moving. The
    /// SDK must NOT open a `CLBackgroundActivitySession` — doing so keeps the
    /// persistent location indicator on and breaks the feature (#261).
    func testSignificantChangesOnlyDoesNotStartBackgroundSession() {
        let sdk = TraceletSdk.shared
        // `useSignificantChangesOnly` is an iOS field; the plugin delivers iOS
        // fields at the top level of the config map (ConfigManager only
        // flattens geo/app/http/logger/motion/geofence/persistence sections),
        // which is where `getUseSignificantChangesOnly()` reads it.
        sdk.ready(config: [
            "useSignificantChangesOnly": true,
            // Force the moving state so start() takes the branch that used to
            // open the session unconditionally.
            "motion": [
                "isMoving": true,
                "disableStopDetection": true,
            ] as [String: Any],
        ])

        sdk.start()

        XCTAssertFalse(
            sdk.backgroundActivitySessionManager.isActive,
            "useSignificantChangesOnly must not open a CLBackgroundActivitySession (#261)"
        )
    }

    /// Contrast guard: WITHOUT `useSignificantChangesOnly`, continuous tracking
    /// while moving SHOULD open the background session on iOS 17+ (the normal
    /// path). Proves the #261 fix is scoped to significant-change-only mode and
    /// does not regress ordinary continuous tracking.
    func testContinuousMovingStartsBackgroundSession() {
        let sdk = TraceletSdk.shared
        sdk.ready(config: [
            "motion": [
                "isMoving": true,
                "disableStopDetection": true,
            ] as [String: Any],
        ])

        sdk.start()

        if #available(iOS 17.0, *) {
            XCTAssertTrue(
                sdk.backgroundActivitySessionManager.isActive,
                "continuous moving tracking should open a background session on iOS 17+"
            )
        } else {
            XCTAssertFalse(sdk.backgroundActivitySessionManager.isActive)
        }
    }

    /// The path that actually reproduced #261 in the app: the speed/smart
    /// motion pipeline confirms movement and calls `switchToContinuousForce()`,
    /// which switches to continuous GPS and (before the fix) unconditionally
    /// opened a `CLBackgroundActivitySession` — independent of start()'s moving
    /// branch. It must honor `useSignificantChangesOnly` too.
    func testSwitchToContinuousForceWithSignificantChangesOnlyDoesNotStartSession() {
        let sdk = TraceletSdk.shared
        sdk.ready(config: [
            "useSignificantChangesOnly": true,
            "motion": ["isMoving": true, "disableStopDetection": true] as [String: Any],
        ])
        sdk.start()

        // Simulate the motion pipeline confirming real movement.
        sdk.switchToContinuousForce()

        XCTAssertFalse(
            sdk.backgroundActivitySessionManager.isActive,
            "switchToContinuousForce() must not open a session under useSignificantChangesOnly (#261)"
        )
    }
}
