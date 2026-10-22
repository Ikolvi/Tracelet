import CoreLocation
import XCTest

@testable import TraceletSDK

/// #442: the motion change `changePace` sends must pass through the SDK's
/// trip recording before it leaves. It used to be sent unstamped, ahead of the
/// trip manager seeing the transition, so Dart minted a trip id of its own and
/// no native trip (and no stored summary, #401) existed for the journey.
final class MotionChangeTripStampTests: XCTestCase {

    private func makeEngine() -> (LocationEngine, StampRecordingSender) {
        let config = ConfigManager()
        config.reset(nil)
        _ = config.setConfig(["desiredAccuracy": 0, "distanceFilter": 10.0])
        let sender = StampRecordingSender()
        let engine = LocationEngine(
            configManager: config,
            stateManager: StateManager(),
            eventDispatcher: sender
        )
        let manager = StampLocationManager()
        engine.locationManager = manager
        manager.delegate = engine
        return (engine, sender)
    }

    func testTheSentMotionChangeCarriesWhatTheTransformReturned() {
        let (engine, sender) = makeEngine()
        var seen: [Bool] = []
        engine.motionChangeTransform = { data in
            seen.append(data["isMoving"] as? Bool ?? false)
            var stamped = data
            stamped["tripId"] = "trip-under-test"
            return stamped
        }

        _ = engine.changePace(true)

        XCTAssertEqual(seen, [true], "the transition is recorded once, before sending")
        XCTAssertEqual(sender.motionChanges.last?["tripId"] as? String, "trip-under-test")
        XCTAssertEqual(sender.motionChanges.last?["isMoving"] as? Bool, true)
        engine.stop()
    }

    func testTheTripManagerOpensAndClosesATripFromChangePace() {
        let (engine, sender) = makeEngine()
        let trips = TraceletTripManager()
        var summaries: [TripData] = []
        trips.onTripSummary = { summaries.append($0) }
        engine.motionChangeTransform = { data in
            trips.onMotionStateChanged(isMoving: data["isMoving"] as? Bool ?? false)
            var stamped = data
            stamped["tripId"] = trips.currentTripId
            return stamped
        }

        _ = engine.changePace(true)
        let openedId = sender.motionChanges.last?["tripId"] as? String
        XCTAssertNotNil(openedId, "the moving event carries the native trip id")

        _ = engine.changePace(false)
        XCTAssertEqual(summaries.map { $0.tripId }, [openedId!])
        engine.stop()
    }
}

private final class StampLocationManager: CLLocationManager {
    private var allowsBackground = false
    override var allowsBackgroundLocationUpdates: Bool {
        get { allowsBackground }
        set { allowsBackground = newValue }
    }
    override var authorizationStatus: CLAuthorizationStatus { .authorizedAlways }
    override func startUpdatingLocation() {}
    override func stopUpdatingLocation() {}
    override func startMonitoringSignificantLocationChanges() {}
    override func stopMonitoringSignificantLocationChanges() {}
}

private final class StampRecordingSender: TraceletEventSending {
    var motionChanges: [[String: Any]] = []
    func sendLocation(_ data: [String: Any]) {}
    func sendMotionChange(_ data: [String: Any]) { motionChanges.append(data) }
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
