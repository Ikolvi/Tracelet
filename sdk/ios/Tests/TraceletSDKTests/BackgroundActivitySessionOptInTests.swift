import XCTest
@testable import TraceletSDK

/// Regression tests for #423 — `IosConfig.useBackgroundActivitySession` is an
/// opt-in, and the continuous path must honour it.
///
/// `CLBackgroundActivitySession` shows the system location indicator for as
/// long as it exists, regardless of `showsBackgroundLocationIndicator`. Only
/// `LocationEngine.start()` ever checked the flag; every moving transition went
/// through `TraceletSdk.startBackgroundActivitySessionIfNeeded()`, which checked
/// `useSignificantChangesOnly` (#261) and nothing else. So an Always-authorized
/// app with the flag at its default `false` — the configuration #210 told users
/// to adopt to hide the indicator — showed the blue bar for the length of every
/// trip.
///
/// The simulator reports `notDetermined` authorization, which is the branch
/// where nothing but the flag can open the session. The When-In-Use exception
/// (the session is what keeps a suspended app's stream alive there, and the OS
/// shows the indicator anyway) needs a real authorization state and is
/// documented on `backgroundActivitySessionIsWanted()` rather than tested.
final class BackgroundActivitySessionOptInTests: XCTestCase {

    override func setUp() {
        super.setUp()
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

    private func readyMoving(_ extra: [String: Any] = [:]) {
        var config: [String: Any] = [
            "motion": [
                "isMoving": true,
                "disableStopDetection": true,
            ] as [String: Any],
        ]
        extra.forEach { config[$0.key] = $0.value }
        TraceletSdk.shared.ready(config: config)
    }

    /// The reported scenario: default config, continuous mode, moving. No
    /// session — this is exactly what the old contrast test in
    /// `SignificantChangesBackgroundSessionTests` asserted the other way.
    func testContinuousMovingWithoutOptInDoesNotStartSession() {
        let sdk = TraceletSdk.shared
        readyMoving()

        sdk.start()

        XCTAssertFalse(
            sdk.backgroundActivitySessionManager.isActive,
            "useBackgroundActivitySession defaults to false and must be honoured on the continuous path (#423)"
        )
    }

    /// An explicit `false` is the customer's configuration, stated in full.
    func testContinuousMovingWithExplicitFalseDoesNotStartSession() {
        let sdk = TraceletSdk.shared
        readyMoving([
            "useBackgroundActivitySession": false,
            "showsBackgroundLocationIndicator": false,
        ])

        sdk.start()

        XCTAssertFalse(sdk.backgroundActivitySessionManager.isActive)
    }

    /// The opt-in still works: this is the only thing that changed on the
    /// continuous path, so the flag must be the thing that opens it.
    func testContinuousMovingWithOptInStartsSession() {
        let sdk = TraceletSdk.shared
        readyMoving(["useBackgroundActivitySession": true])

        sdk.start()

        if #available(iOS 17.0, *) {
            XCTAssertTrue(sdk.backgroundActivitySessionManager.isActive)
        } else {
            XCTAssertFalse(sdk.backgroundActivitySessionManager.isActive)
        }
    }

    // `switchToContinuousForce()` — the path that reproduces in the field — is
    // not driven here: without `useSignificantChangesOnly` it sets
    // `allowsBackgroundLocationUpdates` on a test bundle with no location
    // background mode, which CoreLocation refuses. It reaches the same
    // `startBackgroundActivitySessionIfNeeded()` as the two paths above; the
    // gate is the one expression in `backgroundActivitySessionIsWanted()`.

    /// The in-app-evaluated geofence posture shared the same unconditional
    /// `start()`; under Always it needs the stream, not the session.
    func testHighAccuracyGeofencesWithoutOptInDoNotStartSession() {
        let sdk = TraceletSdk.shared
        sdk.ready(config: ["geofence": ["geofenceModeHighAccuracy": true]])

        sdk.startGeofences()

        XCTAssertFalse(
            sdk.backgroundActivitySessionManager.isActive,
            "high-accuracy geofence mode must not open a session without the opt-in (#423)"
        )
    }
}
