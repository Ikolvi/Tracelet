import CoreLocation
import XCTest

@testable import TraceletSDK

final class LocationEngineQualityTargetTests: XCTestCase {
    private func makeEngine() -> (LocationEngine, QualityTargetLocationManager) {
        let config = ConfigManager()
        config.reset(nil)
        let engine = LocationEngine(
            configManager: config,
            stateManager: StateManager(),
            eventDispatcher: QualityTargetNoopEventSender()
        )
        let manager = QualityTargetLocationManager()
        engine.locationManager = manager
        manager.delegate = engine
        return (engine, manager)
    }

    func testAccuracyTargetKeepsProviderWarmUntilQualityArrives() {
        let (engine, manager) = makeEngine()
        let completed = expectation(description: "quality fix")
        var result: [String: Any]?

        engine.getCurrentPosition(
            options: [
                "timeout": 30,
                "samples": 1,
                "accuracyTarget": 100.0,
                "requestId": "quality",
                "persist": false,
            ]
        ) {
            result = $0
            completed.fulfill()
        }

        manager.delegate?.locationManager?(manager, didUpdateLocations: [fix(accuracy: -1)])
        XCTAssertNil(result)
        XCTAssertEqual(manager.stopUpdatingCallCount, 0)

        manager.delegate?.locationManager?(manager, didUpdateLocations: [fix(accuracy: 1_500)])
        XCTAssertNil(result)
        XCTAssertEqual(manager.stopUpdatingCallCount, 0)

        manager.delegate?.locationManager?(manager, didUpdateLocations: [fix(accuracy: 20)])
        wait(for: [completed], timeout: 1)

        let coords = result?["coords"] as? [String: Any]
        XCTAssertEqual(coords?["accuracy"] as? Double, 20)
        XCTAssertEqual(manager.stopUpdatingCallCount, 1)
    }

    func testAccuracyTargetTimeoutReturnsBestCoarseCandidate() {
        let (engine, manager) = makeEngine()
        let completed = expectation(description: "coarse fallback")
        var result: [String: Any]?

        engine.getCurrentPosition(
            options: [
                "timeout": 0,
                "accuracyTarget": 100.0,
                "requestId": "quality",
                "persist": false,
            ]
        ) {
            result = $0
            completed.fulfill()
        }

        manager.delegate?.locationManager?(
            manager,
            didUpdateLocations: [fix(accuracy: 1_500)]
        )
        wait(for: [completed], timeout: 1)

        let coords = result?["coords"] as? [String: Any]
        XCTAssertEqual(coords?["accuracy"] as? Double, 1_500)
        XCTAssertEqual(manager.stopUpdatingCallCount, 1)
    }

    func testCancellationStopsProviderAndSuppressesLateResult() {
        let (engine, manager) = makeEngine()
        let cancelled = expectation(description: "cancel callback")
        var result: [String: Any]? = ["sentinel": true]

        engine.getCurrentPosition(
            options: [
                "timeout": 30,
                "accuracyTarget": 100.0,
                "requestId": "quality",
                "persist": false,
            ]
        ) {
            result = $0
            cancelled.fulfill()
        }

        XCTAssertTrue(engine.cancelCurrentPosition("quality"))
        manager.delegate?.locationManager?(manager, didUpdateLocations: [fix(accuracy: 5)])
        wait(for: [cancelled], timeout: 1)

        XCTAssertNil(result)
        XCTAssertEqual(manager.stopUpdatingCallCount, 1)
    }

    private func fix(accuracy: CLLocationAccuracy) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 45, longitude: -122),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 5,
            timestamp: Date()
        )
    }
}

private final class QualityTargetLocationManager: CLLocationManager {
    var stopUpdatingCallCount = 0
    private var allowsBackground = false

    override var authorizationStatus: CLAuthorizationStatus { .authorizedAlways }

    override var allowsBackgroundLocationUpdates: Bool {
        get { allowsBackground }
        set { allowsBackground = newValue }
    }

    override func startUpdatingLocation() {}

    override func stopUpdatingLocation() {
        stopUpdatingCallCount += 1
    }
}

private final class QualityTargetNoopEventSender: TraceletEventSending {
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
