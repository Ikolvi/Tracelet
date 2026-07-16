import CoreLocation
import XCTest

@testable import TraceletSDK

final class LocationEngineRuntimeProviderOptionsTests: XCTestCase {

    private func makeEngine() -> (LocationEngine, ConfigManager, RuntimeOptionsLocationManager) {
        let config = ConfigManager()
        config.reset(nil)
        _ = config.setConfig([
            "desiredAccuracy": 0,
            "distanceFilter": 10.0,
            "pausesLocationUpdatesAutomatically": false,
        ])

        let engine = LocationEngine(
            configManager: config,
            stateManager: StateManager(),
            eventDispatcher: RuntimeOptionsEventSender()
        )
        let recorder = RuntimeOptionsLocationManager()
        engine.locationManager = recorder
        recorder.delegate = engine
        return (engine, config, recorder)
    }

    func testAppliesLiveProviderOptionsWithoutRestartingCoreLocation() {
        let (engine, _, recorder) = makeEngine()
        engine.start()

        XCTAssertEqual(recorder.startUpdatingCount, 1)
        XCTAssertEqual(recorder.stopUpdatingCount, 0)

        let updated = engine.updateLocationProviderOptions(
            desiredAccuracy: 1,
            distanceFilter: 25
        )

        XCTAssertTrue(updated)
        XCTAssertEqual(recorder.desiredAccuracy, kCLLocationAccuracyHundredMeters)
        XCTAssertEqual(recorder.distanceFilter, 25)
        XCTAssertEqual(recorder.startUpdatingCount, 1)
        XCTAssertEqual(recorder.stopUpdatingCount, 0)

        engine.stop()
    }

    func testEmptyOptionsRestoreConfiguredProviderValues() {
        let (engine, _, recorder) = makeEngine()
        engine.start()
        XCTAssertTrue(
            engine.updateLocationProviderOptions(
                desiredAccuracy: 1,
                distanceFilter: 25
            )
        )

        XCTAssertTrue(
            engine.updateLocationProviderOptions(
                desiredAccuracy: nil,
                distanceFilter: nil
            )
        )

        XCTAssertEqual(recorder.desiredAccuracy, kCLLocationAccuracyBest)
        XCTAssertEqual(recorder.distanceFilter, 10)
        XCTAssertEqual(recorder.startUpdatingCount, 1)
        XCTAssertEqual(recorder.stopUpdatingCount, 0)

        engine.stop()
    }

    func testStopClearsRuntimeProviderOverride() {
        let (engine, _, recorder) = makeEngine()
        engine.start()
        XCTAssertTrue(
            engine.updateLocationProviderOptions(
                desiredAccuracy: 1,
                distanceFilter: 25
            )
        )

        engine.stop()
        engine.start()

        XCTAssertEqual(recorder.desiredAccuracy, kCLLocationAccuracyBest)
        XCTAssertEqual(recorder.distanceFilter, 10)

        engine.stop()
    }

    func testRejectsInvalidFilterAndInactiveTracking() {
        let (engine, _, recorder) = makeEngine()

        XCTAssertFalse(
            engine.updateLocationProviderOptions(
                desiredAccuracy: 1,
                distanceFilter: 25
            )
        )

        engine.start()
        XCTAssertFalse(
            engine.updateLocationProviderOptions(
                desiredAccuracy: 1,
                distanceFilter: -.infinity
            )
        )
        XCTAssertEqual(recorder.desiredAccuracy, kCLLocationAccuracyBest)
        XCTAssertEqual(recorder.distanceFilter, 10)

        engine.stop()
    }
}

private final class RuntimeOptionsLocationManager: CLLocationManager {
    private var allowsBackground = false
    private(set) var startUpdatingCount = 0
    private(set) var stopUpdatingCount = 0

    override var allowsBackgroundLocationUpdates: Bool {
        get { allowsBackground }
        set { allowsBackground = newValue }
    }

    override var authorizationStatus: CLAuthorizationStatus {
        .authorizedAlways
    }

    override func startUpdatingLocation() {
        startUpdatingCount += 1
    }

    override func stopUpdatingLocation() {
        stopUpdatingCount += 1
    }

    override func startMonitoringSignificantLocationChanges() {}

    override func stopMonitoringSignificantLocationChanges() {}
}

private final class RuntimeOptionsEventSender: TraceletEventSending {
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
