import CoreLocation
import XCTest

@testable import TraceletSDK

/// Regression for GitHub issue #404:
///   "a stale near-zero speed can veto an accelerometer wake, so a backgrounded
///    device may never leave stationary mode"
///
/// `TraceletSmartMotionCoordinator`'s hand-tremor override reads
/// `LocationEngine.lastEffectiveSpeed` to decide whether a *moving*
/// accelerometer is really hand tremor on a still device. It had no freshness
/// check, while the pace sink next door has enforced `maximumPaceFixAge` since
/// 3.8.7 — so the two disagreed about a reading neither could vouch for.
///
/// The failure needs no exotic state. A device parks, the stream stops, and
/// `lastEffectiveSpeed` freezes at whatever it last resolved (0.0057 m/s in the
/// reported trace, well under the 0.15 m/s tremor cutoff). Stationary-periodic
/// mode then produces no fresh fix **by construction**, so minutes later, when
/// the accelerometer fires on a genuine walk, the override reads that frozen
/// value and overrules the wake. Reopening the app calls `ready()`, which
/// produces a fresh fix and unwedges it — which is exactly why this was
/// reported as "the location indicator only appears in the foreground".
///
/// These tests pin `paceFixAge`, the seam the gate reads. The coordinator's own
/// decision is covered on Android (`SmartMotionCoordinatorTest`), where the
/// engine is a mock: this target cannot drive one, because `resolvedSpeed`
/// reaches the engine through `TraceletSdk.shared` and starting a session here
/// trips `setAllowsBackgroundLocationUpdates` on a bundle with no `location`
/// background mode.
final class PaceFixAgeTests: XCTestCase {

    private func makeEngine() -> (LocationEngine, PaceAgeLocationManager) {
        let config = ConfigManager()
        config.reset(nil)
        _ = config.setConfig([
            "desiredAccuracy": 0,
            "distanceFilter": 0.0,
            // persistMode 3 = none → dispatch skips DB writes, so the test
            // needs no native persistence wiring.
            "persistMode": 3,
            "resolveAddress": false,
            "rejectMockLocations": false,
            "pausesLocationUpdatesAutomatically": false,
        ])
        let engine = LocationEngine(
            configManager: config,
            stateManager: StateManager(),
            eventDispatcher: PaceAgeEventSender()
        )
        let recorder = PaceAgeLocationManager()
        engine.locationManager = recorder
        recorder.delegate = engine
        return (engine, recorder)
    }

    private func fix(at timestamp: Date) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 10.787929, longitude: 76.684183),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            timestamp: timestamp
        )
    }

    /// Nothing accepted yet is *unknown*, and must stay distinguishable from a
    /// speed of zero — the distinction #333 established and #404 extends to age.
    func testNoFixReportsNoAge() {
        let (engine, _) = makeEngine()
        XCTAssertNil(
            engine.paceFixAge,
            "no fix has been accepted, so there is no reading to be old or new")
    }

    func testACurrentFixReportsANegligibleAge() {
        let (engine, recorder) = makeEngine()
        engine.locationManager(recorder, didUpdateLocations: [fix(at: Date())])

        let age = try? XCTUnwrap(engine.paceFixAge)
        XCTAssertNotNil(age)
        XCTAssertLessThan(
            age ?? .greatestFiniteMagnitude, LocationEngine.maximumPaceFixAge,
            "a fix taken now is inside the window that may drive the pace machine")
    }

    /// The reported state: the fix behind the frozen speed is minutes old.
    func testAFixFromFiveMinutesAgoIsReportedAsStale() {
        let (engine, recorder) = makeEngine()
        engine.locationManager(
            recorder, didUpdateLocations: [fix(at: Date(timeIntervalSinceNow: -300))])

        let age = try? XCTUnwrap(engine.paceFixAge)
        XCTAssertNotNil(age)
        XCTAssertGreaterThan(
            age ?? 0, LocationEngine.maximumPaceFixAge,
            "five minutes is far outside the window, so the tremor override must " +
            "treat this speed as unknown rather than as proof the device is parked (#404)")
        // Not an arbitrary bound: it pins that the age is the *fix's* age and
        // not the time since the engine happened to be handed it.
        XCTAssertEqual(age ?? 0, 300, accuracy: 5)
    }

    /// The gate's constant is shared rather than duplicated, so the tremor
    /// override and the pace sink cannot drift apart — which is how they came
    /// to disagree in the first place.
    func testTheAgeLimitIsTheOneThePaceSinkUses() {
        XCTAssertEqual(
            LocationEngine.maximumPaceFixAge, 10,
            "ten seconds: longer than any live fix interval, far shorter than the " +
            "gap a cached fix survives across a stationary period")
    }
}

private final class PaceAgeLocationManager: CLLocationManager {
    private var allowsBackground = false
    private var storedDistanceFilter: CLLocationDistance = kCLDistanceFilterNone

    override var allowsBackgroundLocationUpdates: Bool {
        get { allowsBackground }
        set { allowsBackground = newValue }
    }

    override var distanceFilter: CLLocationDistance {
        get { storedDistanceFilter }
        set { storedDistanceFilter = newValue }
    }

    override var authorizationStatus: CLAuthorizationStatus { .authorizedAlways }

    override func startUpdatingLocation() {}
    override func stopUpdatingLocation() {}
    override func startMonitoringSignificantLocationChanges() {}
    override func stopMonitoringSignificantLocationChanges() {}
}

private final class PaceAgeEventSender: TraceletEventSending {
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
