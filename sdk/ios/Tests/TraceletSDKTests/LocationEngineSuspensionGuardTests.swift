import CoreLocation
import XCTest

@testable import TraceletSDK

/// #435: since iOS 16.4 an app running both `startUpdatingLocation()` and
/// significant-change monitoring can be suspended in the background when it
/// asks for a distance filter or coarse accuracy, unless the location
/// indicator is showing. With the indicator off and no background session
/// (3.8.8, #423) the continuous stream must run with CoreLocation's filter off
/// and accuracy of 100 m or better, while the configured filter keeps gating
/// what is recorded.
final class LocationEngineSuspensionGuardTests: XCTestCase {

    private func makeEngine(
        _ extra: [String: Any] = [:],
        status: CLAuthorizationStatus = .authorizedAlways
    ) -> (LocationEngine, SuspensionGuardLocationManager) {
        let config = ConfigManager()
        config.reset(nil)
        var settings: [String: Any] = [
            "desiredAccuracy": 0,
            "distanceFilter": 10.0,
            "pausesLocationUpdatesAutomatically": false,
        ]
        settings.merge(extra) { _, new in new }
        _ = config.setConfig(settings)

        let engine = LocationEngine(
            configManager: config,
            stateManager: StateManager(),
            eventDispatcher: SuspensionGuardEventSender()
        )
        let recorder = SuspensionGuardLocationManager(status: status)
        engine.locationManager = recorder
        recorder.delegate = engine
        return (engine, recorder)
    }

    func testIndicatorOffWithoutSessionDropsTheCoreLocationFilter() {
        let (engine, recorder) = makeEngine()
        engine.start()

        XCTAssertTrue(engine.needsSuspensionSafeProviderOptions)
        XCTAssertEqual(recorder.distanceFilter, kCLDistanceFilterNone)
        XCTAssertEqual(recorder.startUpdatingCount, 1)
        XCTAssertEqual(recorder.significantChangeCount, 1, "precondition: both are running, as in Apple's rule")

        engine.stop()
    }

    func testCoarseAccuracyIsRaisedToHundredMeters() {
        let (engine, recorder) = makeEngine(["desiredAccuracy": 3])
        engine.start()

        XCTAssertEqual(recorder.desiredAccuracy, kCLLocationAccuracyHundredMeters)

        engine.stop()
    }

    func testRuntimeOverrideCannotReintroduceTheFilter() {
        let (engine, recorder) = makeEngine()
        engine.start()

        XCTAssertTrue(engine.updateLocationProviderOptions(desiredAccuracy: 2, distanceFilter: 50))

        XCTAssertEqual(recorder.distanceFilter, kCLDistanceFilterNone)
        XCTAssertEqual(recorder.desiredAccuracy, kCLLocationAccuracyHundredMeters)

        engine.stop()
    }

    func testIndicatorOptInKeepsTheConfiguredFilter() {
        let (engine, recorder) = makeEngine(["showsBackgroundLocationIndicator": true])
        engine.start()

        XCTAssertFalse(engine.needsSuspensionSafeProviderOptions)
        XCTAssertEqual(recorder.distanceFilter, 10)

        engine.stop()
    }

    func testBackgroundSessionOptInKeepsTheConfiguredFilter() {
        let (engine, recorder) = makeEngine(["useBackgroundActivitySession": true])
        engine.start()

        XCTAssertFalse(engine.needsSuspensionSafeProviderOptions)
        XCTAssertEqual(recorder.distanceFilter, 10)

        engine.stop()
    }

    func testWhenInUseKeepsTheConfiguredFilter() {
        // The OS shows the indicator in the background under When-In-Use.
        let (engine, recorder) = makeEngine(status: .authorizedWhenInUse)
        engine.start()

        XCTAssertFalse(engine.needsSuspensionSafeProviderOptions)
        XCTAssertEqual(recorder.distanceFilter, 10)

        engine.stop()
    }
}

private final class SuspensionGuardLocationManager: CLLocationManager {
    private let status: CLAuthorizationStatus
    private var allowsBackground = false
    private(set) var startUpdatingCount = 0
    private(set) var significantChangeCount = 0

    init(status: CLAuthorizationStatus) {
        self.status = status
        super.init()
    }

    override var allowsBackgroundLocationUpdates: Bool {
        get { allowsBackground }
        set { allowsBackground = newValue }
    }

    override var authorizationStatus: CLAuthorizationStatus { status }

    override func startUpdatingLocation() { startUpdatingCount += 1 }
    override func stopUpdatingLocation() {}
    override func startMonitoringSignificantLocationChanges() { significantChangeCount += 1 }
    override func stopMonitoringSignificantLocationChanges() {}
}

private final class SuspensionGuardEventSender: TraceletEventSending {
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
