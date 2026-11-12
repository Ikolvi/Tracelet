import CoreLocation
import XCTest
@testable import TraceletSDK

/// iOS ports of the Android #447/#448/#449 fixes. The SPEED/SMART pipeline
/// writes the stationary *pace* into `trackingMode` when it parks, so every
/// resume decision has to read the *strategy* the app started instead.
final class SessionStrategyResumeTests: XCTestCase {

    private let smartPeriodic: [String: Any] = [
        "motion": [
            "motionDetectionMode": 2,      // smart
            "stationaryTrackingMode": 0,   // periodic
        ] as [String: Any],
        "stopOnTerminate": false,
    ]

    override func setUp() {
        super.setUp()
        StateManager().reset()
        TraceletSdk.shared.initialize()
        // xctest has no background mode; the real manager throws when the
        // engine enables background updates.
        let manager = ResumeStubLocationManager()
        TraceletSdk.shared.locationEngine.locationManager = manager
        manager.delegate = TraceletSdk.shared.locationEngine
    }

    override func tearDown() {
        let sdk = TraceletSdk.shared
        if sdk.isReadyState {
            sdk.stop()
            sdk.reset(nil)
        }
        StateManager().reset()
        super.tearDown()
    }

    func testSessionModeFallsBackToTrackingModeAndIsClearedByReset() {
        let state = StateManager()
        state.trackingMode = .geofences
        XCTAssertEqual(state.sessionTrackingMode, .geofences, "no stored strategy: fall back")
        state.sessionTrackingMode = .continuous
        XCTAssertEqual(state.sessionTrackingMode, .continuous)
        state.reset()
        XCTAssertEqual(state.sessionTrackingMode, .continuous, "reset clears it back to the fallback")
    }

    /// #447: parking must not overwrite the started strategy, which is what the
    /// killed-state relaunch now reads.
    func testParkingKeepsTheStartedStrategy() {
        let sdk = TraceletSdk.shared
        sdk.ready(config: smartPeriodic)
        sdk.start()
        sdk.switchToStationaryGeofencesForce()
        XCTAssertEqual(sdk.stateManager.trackingMode, .geofences, "the pace is written as before")
        XCTAssertEqual(sdk.stateManager.sessionTrackingMode, .continuous, "the strategy survives (#447)")
    }

    /// #449: ready() in SMART mode resumes a periodic session as periodic.
    func testReadyInSmartModeResumesAPeriodicSession() {
        let sdk = TraceletSdk.shared
        sdk.ready(config: smartPeriodic)
        sdk.startPeriodic()
        sdk.ready(config: smartPeriodic)
        XCTAssertEqual(sdk.stateManager.trackingMode, .periodic, "SMART ready() must not resume continuous (#449)")
    }

    /// #448 is Android-only: on iOS a resumed start() re-arms the stationary
    /// periodic timer itself (via the restored speed machine) before the
    /// coordinator is asked. This pins that, so a refactor cannot open the gap.
    func testResumingAParkedSmartSessionRearmsTheStationaryTimer() {
        let sdk = TraceletSdk.shared
        sdk.ready(config: smartPeriodic)
        sdk.start()
        sdk.switchToStationaryPeriodicForce()
        XCTAssertTrue(sdk.locationEngine.isPeriodicTracking)

        _ = sdk.start(isResume: true)

        XCTAssertTrue(
            sdk.locationEngine.isPeriodicTracking,
            "a parked SMART session resumed by ready() must keep its stationary periodic timer (#448)")
    }
}

private final class ResumeStubLocationManager: CLLocationManager {
    private var allowsBackground = false
    override var allowsBackgroundLocationUpdates: Bool {
        get { allowsBackground }
        set { allowsBackground = newValue }
    }
    override var authorizationStatus: CLAuthorizationStatus { .authorizedAlways }
    override func startUpdatingLocation() {}
    override func stopUpdatingLocation() {}
    override func requestLocation() {}
    override func startMonitoringSignificantLocationChanges() {}
    override func stopMonitoringSignificantLocationChanges() {}
}
