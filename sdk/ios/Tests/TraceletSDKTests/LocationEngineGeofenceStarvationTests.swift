import CoreLocation
import XCTest

@testable import TraceletSDK

/// Regression for the high-accuracy geofence **starvation** bug (missing
/// ENTER/EXIT, intermittent): a stationary device with `distanceFilter > 0`
/// receives no fixes from CoreLocation, so the in-app crossing evaluator is
/// never fed and transitions are silently dropped.
///
/// The fix decouples geofence crossing evaluation from persistence:
///  1. CoreLocation is configured with `distanceFilter = kCLDistanceFilterNone`
///     so a stationary device still receives fixes, and
///  2. crossings evaluate on the **raw** fix stream — before the Rust
///     `LocationProcessor` distance filter — so a fix the filter drops for
///     *persistence* is still evaluated for a *crossing*.
///
/// Persistence volume is unchanged: the processor keeps its distance filter, so
/// `onLocationUpdate` (the persistence-side geofence-proximity callback) still
/// only fires on accepted fixes.
final class LocationEngineGeofenceStarvationTests: XCTestCase {

    private func makeEngine() -> (LocationEngine, ConfigManager, StarvationLocationManager) {
        let config = ConfigManager()
        config.reset(nil)
        _ = config.setConfig([
            "desiredAccuracy": 0,
            "distanceFilter": 10.0,
            // persistMode 3 = none → dispatch skips DB writes so the test needs
            // no native persistence wiring.
            "persistMode": 3,
            "resolveAddress": false,
            "rejectMockLocations": false,
            "pausesLocationUpdatesAutomatically": false,
        ])

        let engine = LocationEngine(
            configManager: config,
            stateManager: StateManager(),
            eventDispatcher: StarvationEventSender()
        )
        let recorder = StarvationLocationManager()
        engine.locationManager = recorder
        recorder.delegate = engine
        return (engine, config, recorder)
    }

    func testHighAccuracyGeofenceModeRequestsTimeBasedUpdates() {
        let (engine, _, recorder) = makeEngine()
        engine.geofenceHighAccuracyMode = true
        engine.start()

        // The configured filter is 10 m; the mode must override it to None so a
        // stationary device is still delivered fixes to evaluate crossings.
        XCTAssertEqual(
            recorder.distanceFilter,
            kCLDistanceFilterNone,
            "high-accuracy geofence mode must request time-based delivery"
        )
        engine.stop()
    }

    func testNormalTrackingKeepsTheConfiguredDistanceFilter() {
        let (engine, _, recorder) = makeEngine()
        engine.geofenceHighAccuracyMode = false
        engine.start()

        XCTAssertEqual(
            recorder.distanceFilter,
            10,
            "normal tracking must keep its distance filter to limit fix volume"
        )
        engine.stop()
    }

    func testCrossingsEvaluateOnEveryRawFixEvenWhenPersistenceRejectsTheDuplicate() {
        let (engine, _, recorder) = makeEngine()
        var rawEvaluations = 0
        var persistedUpdates = 0
        engine.geofenceHighAccuracyMode = true
        engine.onRawGeofenceLocation = { _, _, _ in rawEvaluations += 1 }
        engine.onLocationUpdate = { _, _, _ in persistedUpdates += 1 }
        engine.start()

        // Two fixes from a stationary device: identical position, later time.
        // The processor accepts the first and rejects the second (distance 0 <
        // 10 m filter) for persistence.
        let coord = CLLocationCoordinate2D(latitude: 10.787929, longitude: 76.684183)
        func fix(_ t: TimeInterval) -> CLLocation {
            CLLocation(
                coordinate: coord,
                altitude: 0,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                timestamp: Date(timeIntervalSince1970: t)
            )
        }
        engine.locationManager(recorder, didUpdateLocations: [fix(1_000)])
        engine.locationManager(recorder, didUpdateLocations: [fix(2_000)])

        XCTAssertEqual(
            rawEvaluations, 2,
            "both raw fixes must reach the geofence evaluator — a stationary " +
            "duplicate the persistence filter drops must NOT starve crossings"
        )
        XCTAssertEqual(
            persistedUpdates, 1,
            "persistence stays filtered: the stationary duplicate is dropped, so " +
            "the persistence-side geofence callback fires only for the accepted fix"
        )
        engine.stop()
    }
}

private final class StarvationLocationManager: CLLocationManager {
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

private final class StarvationEventSender: TraceletEventSending {
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
