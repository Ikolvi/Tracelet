import CoreLocation
import XCTest
@testable import TraceletSDK

/// #356 — a geofence smaller than CoreLocation can resolve must still work.
///
/// #355 established that a 5–10 m fence is smaller than typical GPS error, so
/// region monitoring never reports a crossing: entering a region the device is
/// already inside reports state immediately, the fence looks live, and then
/// nothing is ever reported again. The response then was a warning. The response
/// now is to support it — such a fence is evaluated in-app against its true
/// radius, with a hysteresis band scaled to the *measured* fix accuracy instead
/// of a flat 20 m, which on a 2–4 m-accurate handset is the difference between
/// needing 28 m of travel to EXIT and needing 8 m.
///
/// The iOS half of `GeofenceSmallRadiusTest` on Android.
final class GeofenceSmallRadiusTests: XCTestCase {

    private var db: DatabaseManager!
    private var config: ConfigManager!
    private var manager: GeofenceManager!
    private var dbPath: String!
    private var transitions: [(String, String)] = []

    private let centerLat = 10.787929
    private let centerLng = 76.684183

    private func north(_ meters: Double) -> Double { centerLat + meters / 111_320.0 }

    private func makeManager(radius: Double, vertices: [[Double]]? = nil) throws {
        try db.insertGeofence(
            identifier: "TINY",
            lat: centerLat,
            lng: centerLng,
            radius: radius,
            vertices: vertices?.map { Coordinate(lat: $0[0], lng: $0[1]) },
            extras: nil,
            notifyOnEntry: true,
            notifyOnExit: true,
            notifyOnDwell: false,
            loiteringDelay: 0
        )
        manager = GeofenceManager(
            configManager: config,
            eventSender: NoopSmallRadiusEventSender(),
            rustDatabase: db
        )
        manager.onGeofenceEvent = { [weak self] event in
            guard let gf = event["geofence"] as? [String: Any],
                  let id = gf["identifier"] as? String,
                  let action = gf["action"] as? String else { return }
            self?.transitions.append((id, action))
        }
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("geofence_small_\(UUID().uuidString).db").path
        db = try DatabaseManager(dbPath: dbPath)
        try? db.setEncryptionKey(key: "")
        try? db.clearGeofences()
        try? db.clearLogs()

        config = ConfigManager()
        // Explicitly false, not merely defaulted: ConfigManager persists to
        // UserDefaults, so a sibling suite that turns high accuracy on leaves it
        // on for whoever runs next. Stating it here is also the point of these
        // tests — a small fence is evaluated in-app because CoreLocation cannot
        // serve it, not because the caller opted in.
        _ = config.setConfig([
            "geofenceModeHighAccuracy": false,
            "logLevel": 4, // DEBUG
        ])

        // Attach the real logger so assertions run against the persisted store
        // that Doctor exports from.
        let logger = TraceletLogger(configManager: config)
        logger.rustDatabase = db
        TraceletLog.attach(logger)

        UserDefaults.standard.removeObject(forKey: "com.tracelet.geofence.knownInsideIds")
        transitions = []
    }

    override func tearDownWithError() throws {
        TraceletLog.detach()
        manager = nil
        db = nil
        UserDefaults.standard.removeObject(forKey: "com.tracelet.geofence.knownInsideIds")
        try? FileManager.default.removeItem(atPath: dbPath)
        try super.tearDownWithError()
    }

    // MARK: - The capability

    func testSmallFenceEntersAndExitsOverAShortWalk() throws {
        try makeManager(radius: 10.0)

        // Arrive and hold still, then walk off. 4 m accuracy is what the field
        // device reported; the reporter covered ~34 m and saw no EXIT at all.
        manager.evaluateHighAccuracyProximity(latitude: north(3.0), longitude: centerLng, accuracy: 4.0)
        manager.evaluateHighAccuracyProximity(latitude: north(2.0), longitude: centerLng, accuracy: 4.0)
        manager.evaluateHighAccuracyProximity(latitude: north(25.0), longitude: centerLng, accuracy: 4.0)
        manager.evaluateHighAccuracyProximity(latitude: north(30.0), longitude: centerLng, accuracy: 4.0)

        XCTAssertEqual(transitions.map { $0.1 }, ["ENTER", "EXIT"],
                       "a 10 m fence must ENTER on arrival and EXIT on a 30 m departure")
    }

    func testSmallFenceDoesNotFlapWhileStationary() throws {
        try makeManager(radius: 10.0)

        for d in [2.0, 11.0, 6.0, 13.0, 4.0, 12.0, 5.0] {
            manager.evaluateHighAccuracyProximity(latitude: north(d), longitude: centerLng, accuracy: 6.0)
        }

        XCTAssertEqual(transitions.map { $0.1 }, ["ENTER"],
                       "jitter across a 10 m boundary must not produce repeated crossings")
    }

    // MARK: - Ownership

    func testResolvableFenceIsLeftToCoreLocation() throws {
        try makeManager(radius: 500.0)

        // Standing at the centre of a 500 m fence produces nothing here: with
        // geofenceModeHighAccuracy off, region monitoring owns it and reports it
        // via handleTransition. Evaluating it in-app too would double-fire it.
        manager.evaluateHighAccuracyProximity(latitude: centerLat, longitude: centerLng, accuracy: 4.0)

        XCTAssertTrue(transitions.isEmpty,
                      "a 500 m fence must not be evaluated in-app at default settings")
    }

    func testPolygonIsEvaluatedInAppWithoutHighAccuracyMode() throws {
        // CoreLocation only monitors circular regions, so a polygon has always
        // been ours — but before #356 it was evaluated only when
        // geofenceModeHighAccuracy was on, which meant a polygon silently never
        // fired at default settings.
        try makeManager(radius: 0.0, vertices: [
            [centerLat - 0.001, centerLng - 0.001],
            [centerLat + 0.001, centerLng - 0.001],
            [centerLat + 0.001, centerLng + 0.001],
            [centerLat - 0.001, centerLng + 0.001],
        ])

        manager.evaluateHighAccuracyProximity(latitude: centerLat, longitude: centerLng, accuracy: 4.0)

        XCTAssertEqual(transitions.map { $0.1 }, ["ENTER"],
                       "a polygon must fire without geofenceModeHighAccuracy")
    }

    // MARK: - The always-on note

    func testSmallRadiusRecordsHowItWillBeHandled() throws {
        try makeManager(radius: 10.0)

        _ = manager.addGeofence([
            "identifier": "ADDED_TINY",
            "latitude": centerLat,
            "longitude": centerLng,
            "radius": 5.0,
        ])

        let notes = ((try? db.getLogs(limit: 500)) ?? [])
            .map { $0.message }
            .filter { $0.contains("[geofence]") && $0.contains("ADDED_TINY") }

        XCTAssertTrue(
            notes.contains { $0.contains("evaluated in-app") && $0.contains("wake-up only") },
            "which component owns the fence must reach a release-build report, got: \(notes)")
    }
}

/// Minimal sink — these tests assert through `onGeofenceEvent` and the log store.
private final class NoopSmallRadiusEventSender: TraceletEventSending {
    func sendLocation(_ params: [String: Any]) {}
    func sendSpeedMotionEvent(_ params: [String: Any]) {}
    func sendMotionChange(_ params: [String: Any]) {}
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
    func sendDrivingEvent(_ data: [String: Any]) {}
    func sendImpact(_ data: [String: Any]) {}
    func sendModeChange(_ data: [String: Any]) {}
    func hasListener(eventName: String) -> Bool { false }
}
