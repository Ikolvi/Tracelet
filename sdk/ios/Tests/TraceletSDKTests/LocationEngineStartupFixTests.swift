import CoreLocation
import XCTest

@testable import TraceletSDK

/// #385 — a session that *starts* stationary must still acquire one location.
///
/// `motion.isMoving` defaults to false, so `TraceletSdk.start()` takes its
/// stationary branch: no continuous stream (by design), and `changePace(false)`
/// hands the pace to motion subsystems that are already stationary and so
/// change nothing. Nothing called CoreLocation at all. The only one-shot in the
/// engine was fired from `changePace(true)` — a stationary → moving
/// *transition* that a session beginning stationary never takes — so the app
/// got no position until the device physically moved.
///
/// `start()` acquired unconditionally until 3.2.0 (bb8af6a0) replaced
/// `locationEngine.start()` with the pace branch; the stream had been doing
/// double duty as feed *and* initial fix, and only the feed was replaced.
///
/// The guards matter as much as the request: the moving path and the
/// in-app-evaluated-geofence path (#357) are already acquiring, and a second
/// request there is battery spent for a fix that was arriving anyway.
final class LocationEngineStartupFixTests: XCTestCase {

    private func makeEngine(
        authorization: CLAuthorizationStatus = .authorizedAlways
    ) -> (LocationEngine, StartupFixLocationManager) {
        let config = ConfigManager()
        // Persisted config outlives the process here; start from the defaults
        // an app that configures nothing would get, which is the case #385 is
        // about.
        config.reset(nil)

        let engine = LocationEngine(
            configManager: config,
            stateManager: StateManager(),
            eventDispatcher: StartupFixNoopEventSender()
        )
        let recorder = StartupFixLocationManager()
        recorder.stubbedAuthorization = authorization
        engine.locationManager = recorder
        recorder.delegate = engine
        return (engine, recorder)
    }

    func testStartupFixAcquiresOnceWhenIdle() {
        let (engine, recorder) = makeEngine()

        engine.requestStartupFix()

        XCTAssertEqual(
            recorder.requestLocationCallCount, 1,
            "a stationary start runs no stream — this one-shot is the only thing "
                + "that can hand the app the position it started at")
    }

    func testStartupFixIsSkippedWhileTheStreamIsAlreadyRunning() {
        let (engine, recorder) = makeEngine()

        // What a moving start — or the #357 geofence branch of a stationary one
        // — leaves behind: the continuous stream, already acquiring.
        _ = engine.changePace(true)
        let baseline = recorder.requestLocationCallCount
        XCTAssertTrue(engine.isTracking, "precondition: the stream is running")

        engine.requestStartupFix()

        XCTAssertEqual(
            recorder.requestLocationCallCount, baseline,
            "the stream is already acquiring — #385 must not add a redundant "
                + "second request to a path that never had the bug")
    }

    func testStartupFixIsSkippedWithoutAuthorization() {
        let (engine, recorder) = makeEngine(authorization: .denied)

        engine.requestStartupFix()

        XCTAssertEqual(
            recorder.requestLocationCallCount, 0,
            "requestLocation() without authorization only produces a delegate "
                + "error; the app is told about permission through providerChange")
    }

    /// The anchor takes the processor's first-fix slot, and the processor
    /// waives its distance filter only for a fix with no predecessor. The fix
    /// that wakes a stationary session sits metres from the anchor, so without
    /// the hand-back it is dropped as a duplicate and the app is told it is
    /// moving with no position to go with it.
    func testAnchorArmsTheForceAcceptSlotForTheWakeFix() {
        let (engine, _) = makeEngine()
        XCTAssertFalse(engine.forceAcceptNextFilteredLocation)

        engine.requestStartupFix()
        engine.locationManager(
            engine.locationManager,
            didUpdateLocations: [Self.fix(latitude: 10.787929)])

        XCTAssertTrue(
            engine.forceAcceptNextFilteredLocation,
            "an accepted anchor must hand back the free pass it consumed, or the "
                + "wake fix is filtered as a ~0 m duplicate of it")
    }

    /// The slot belongs to the session that took the anchor.
    func testStopReleasesTheForceAcceptSlot() {
        let (engine, _) = makeEngine()
        engine.requestStartupFix()
        engine.locationManager(
            engine.locationManager,
            didUpdateLocations: [Self.fix(latitude: 10.787929)])
        XCTAssertTrue(engine.forceAcceptNextFilteredLocation)

        _ = engine.changePace(true)  // start() adopts the stream
        engine.stop()

        XCTAssertFalse(
            engine.forceAcceptNextFilteredLocation,
            "a stopped session must not leave a free pass for the next one's first fix")
    }

    private static func fix(latitude: Double) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: 76.684183),
            altitude: 0,
            horizontalAccuracy: 8,
            verticalAccuracy: 8,
            course: -1,
            speed: -1,
            timestamp: Date())
    }

    /// The transition one-shot is a separate mechanism with its own trigger
    /// (#54). Pinned here because both now live on the same private request
    /// path: a startup fix must not consume or suppress the transition fix.
    func testTransitionOneShotStillFiresAfterAStartupFix() {
        let (engine, recorder) = makeEngine()

        engine.requestStartupFix()
        XCTAssertEqual(recorder.requestLocationCallCount, 1)

        _ = engine.changePace(true)

        XCTAssertEqual(
            recorder.requestLocationCallCount, 2,
            "the device moving after a stationary start must still get its own "
                + "immediate fix — that is #54, and it is unchanged")
    }
}

// MARK: - Test doubles

/// CLLocationManager subclass that records `requestLocation()` calls and
/// suppresses CoreLocation side effects (background updates, hardware access)
/// that would require entitlements or simulator runtime.
private final class StartupFixLocationManager: CLLocationManager {
    var requestLocationCallCount = 0
    var stubbedAuthorization: CLAuthorizationStatus = .authorizedAlways
    private var _allowsBackground = false

    // Override the entitlement-gated property to a no-op getter/setter pair.
    // The real setter raises NSInternalInconsistencyException without the
    // UIBackgroundModes:location entitlement, which the test bundle lacks.
    override var allowsBackgroundLocationUpdates: Bool {
        get { _allowsBackground }
        set { _allowsBackground = newValue }
    }

    override var authorizationStatus: CLAuthorizationStatus { stubbedAuthorization }

    override func requestLocation() {
        requestLocationCallCount += 1
        // Do NOT call super — avoids hitting real CoreLocation in unit tests.
    }

    override func startUpdatingLocation() {}
    override func stopUpdatingLocation() {}
    override func startMonitoringSignificantLocationChanges() {}
    override func stopMonitoringSignificantLocationChanges() {}
}

private final class StartupFixNoopEventSender: TraceletEventSending {
    func sendLocation(_ data: [String: Any]) {}
    func sendMotionChange(_ data: [String: Any]) {}
    func sendActivityChange(_ data: [String: Any]) {}
    func sendProviderChange(_ data: [String: Any]) {}
    func sendGeofence(_ data: [String: Any]) {}
    func sendGeofencesChange(_ data: [String: Any]) {}
    func sendHeartbeat(_ data: [String: Any]) {}
    func sendHttp(_ data: [String: Any]) {}
    func sendSchedule(_ data: [String: Any]) {}
    func sendPowerSaveChange(_ isPowerSave: Bool) {}
    func sendConnectivityChange(_ data: [String: Any]) {}
    func sendEnabledChange(_ enabled: Bool) {}
    func sendNotificationAction(_ data: [String: Any]) {}
    func sendAuthorization(_ data: [String: Any]) {}
    func sendWatchPosition(_ data: [String: Any]) {}
    func sendRemoteConfigEvent(_ data: [String: Any]) {}
    func sendTrip(_ data: [String: Any]) {}
    func sendBudgetAdjustment(_ data: [String: Any]) {}
    func sendSpeedMotionEvent(_ data: [String: Any]) {}
    func sendDrivingEvent(_ data: [String: Any]) {}
    func sendImpact(_ data: [String: Any]) {}
    func sendModeChange(_ data: [String: Any]) {}
    func hasListener(eventName: String) -> Bool { false }
}
