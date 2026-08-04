import CoreLocation
import XCTest
@testable import TraceletSDK

/// Regression for #292: in `geofenceModeHighAccuracy`, a stationary device inside
/// a geofence must emit exactly ONE ENTER across the resume/boot cycles that wipe
/// the evaluator's in-memory inside-set.
///
/// `startGeofences()` runs on every `ready()`/takeover and calls
/// `clearHighAccuracyState()`, so each takeover forgot the device was inside and
/// re-fired ENTER — a false attendance punch-in on the backend. The persisted
/// `knownInsideIds` set now dedups those re-entries.
final class GeofenceManagerResumeChurnTests: XCTestCase {

    private var db: DatabaseManager!
    private var config: ConfigManager!
    private var manager: GeofenceManager!
    private var dbPath: String!
    private var captured: [[String: Any]] = []

    private let centerLat = 10.787929
    private let centerLng = 76.684183
    private let radius = 50.0 // exit threshold = radius + max(radius*0.1, 20) = 70 m

    private func north(_ meters: Double) -> Double { centerLat + meters / 111_320.0 }

    override func setUpWithError() throws {
        try super.setUpWithError()

        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("geofence_resume_\(UUID().uuidString).db").path
        db = try DatabaseManager(dbPath: dbPath)
        try? db.setEncryptionKey(key: "")
        try? db.clearGeofences()
        try db.insertGeofence(
            identifier: "OFFICE",
            lat: centerLat,
            lng: centerLng,
            radius: radius,
            vertices: nil,
            extras: nil
        )

        config = ConfigManager()
        _ = config.setConfig([
            "geofenceModeHighAccuracy": true,
            // Full gating so these tests exercise the resume/boot path, not the
            // exitAccuracyMax clamp.
            "geofenceExitAccuracyMax": -1,
        ])

        captured = []
        manager = newManager()
        // Isolate persisted crossing state from any previous test run.
        manager.resetHighAccuracyInsideState()
    }

    override func tearDown() {
        manager?.resetHighAccuracyInsideState()
        if let dbPath { try? FileManager.default.removeItem(atPath: dbPath) }
        super.tearDown()
    }

    private func newManager() -> GeofenceManager {
        let mgr = GeofenceManager(
            configManager: config,
            eventSender: NoopResumeChurnEventSender(),
            rustDatabase: db
        )
        mgr.onGeofenceEvent = { [weak self] in self?.captured.append($0) }
        return mgr
    }

    private func count(_ action: String) -> Int {
        captured.filter { (($0["geofence"] as? [String: Any])?["action"] as? String) == action }.count
    }

    /// A resume/takeover that wipes the evaluator's in-memory state — exactly what
    /// `startGeofences(isResume: true)` does.
    private func simulateResume() { manager.clearHighAccuracyState() }

    func testResumeDoesNotReEmitEnterForAStationaryDeviceInsideAFence() {
        manager.evaluateHighAccuracyProximity(latitude: centerLat, longitude: centerLng, accuracy: 8.0)
        XCTAssertEqual(count("ENTER"), 1, "first fix inside must ENTER once")

        for _ in 0..<3 {
            simulateResume()
            manager.evaluateHighAccuracyProximity(latitude: north(12.0), longitude: centerLng, accuracy: 8.0)
        }

        XCTAssertEqual(count("ENTER"), 1, "resume must not re-emit ENTER (#292)")
        XCTAssertEqual(count("EXIT"), 0, "a stationary device must not EXIT")
    }

    func testColdStartAfterProcessDeathDoesNotReEmitEnter() {
        manager.evaluateHighAccuracyProximity(latitude: centerLat, longitude: centerLng, accuracy: 8.0)
        XCTAssertEqual(count("ENTER"), 1)

        // A brand-new manager models a fresh process: the evaluator starts empty,
        // but knownInsideIds is reloaded from persisted UserDefaults.
        manager = newManager()
        manager.evaluateHighAccuracyProximity(latitude: north(12.0), longitude: centerLng, accuracy: 8.0)

        XCTAssertEqual(count("ENTER"), 1, "cold start must not re-emit ENTER (#292)")
    }

    func testGenuineDepartureThenReturnStillEmitsExitThenAFreshEnter() {
        manager.evaluateHighAccuracyProximity(latitude: centerLat, longitude: centerLng, accuracy: 8.0)      // ENTER
        // Sustained departure confirmed across two fixes (first is held).
        manager.evaluateHighAccuracyProximity(latitude: north(120.0), longitude: centerLng, accuracy: 8.0)   // held
        manager.evaluateHighAccuracyProximity(latitude: north(120.0), longitude: centerLng, accuracy: 8.0)   // confirmed EXIT
        XCTAssertEqual(count("ENTER"), 1)
        XCTAssertEqual(count("EXIT"), 1)

        simulateResume()
        manager.evaluateHighAccuracyProximity(latitude: north(12.0), longitude: centerLng, accuracy: 8.0)    // genuine return

        XCTAssertEqual(count("ENTER"), 2, "a genuine return after EXIT must re-ENTER")
        XCTAssertEqual(count("EXIT"), 1)
    }

    func testLeaveWhileDeadIsReportedAsExitOnColdStartNotStuck() {
        // Device ENTERs the office; the app is later killed with the persisted
        // inside-set still holding OFFICE.
        manager.evaluateHighAccuracyProximity(latitude: centerLat, longitude: centerLng, accuracy: 8.0)
        XCTAssertEqual(count("ENTER"), 1)

        // New process (evaluator starts empty). The device left the office while
        // dead, so the fixes are well outside. Seeded from the persisted set, the
        // cold-started evaluator confirms the departure across two fixes and
        // EXITs rather than getting stuck inside.
        manager = newManager()
        manager.evaluateHighAccuracyProximity(latitude: north(200.0), longitude: centerLng, accuracy: 8.0)  // held
        manager.evaluateHighAccuracyProximity(latitude: north(200.0), longitude: centerLng, accuracy: 8.0)  // confirmed EXIT
        XCTAssertEqual(count("EXIT"), 1, "a sustained leave-while-dead must EXIT on cold start (#292)")

        // Returning to the office then fires a fresh ENTER — state was not stuck.
        manager.evaluateHighAccuracyProximity(latitude: north(12.0), longitude: centerLng, accuracy: 8.0)
        XCTAssertEqual(count("ENTER"), 2, "a genuine return after the exit must ENTER")
    }

    func testRemoveGeofenceClearsInsideStateSoAReAddedFenceCanEnterAgain() {
        manager.evaluateHighAccuracyProximity(latitude: centerLat, longitude: centerLng, accuracy: 8.0)
        XCTAssertEqual(count("ENTER"), 1)

        // Remove the fence, then add it back (a fence-list refresh, or an id
        // reused for a different location).
        _ = manager.removeGeofence("OFFICE")
        try? db.insertGeofence(identifier: "OFFICE", lat: centerLat, lng: centerLng, radius: radius, vertices: nil, extras: nil)

        // Being inside the re-added fence must ENTER again.
        manager.evaluateHighAccuracyProximity(latitude: centerLat, longitude: centerLng, accuracy: 8.0)
        XCTAssertEqual(count("ENTER"), 2, "a re-added fence must be able to ENTER again (#292)")
    }

    func testFreshStartReEmitsTheInitialEnter() {
        manager.evaluateHighAccuracyProximity(latitude: centerLat, longitude: centerLng, accuracy: 8.0)
        XCTAssertEqual(count("ENTER"), 1)

        // Fresh, explicit start (mirrors startGeofences(isResume: false)).
        manager.resetHighAccuracyInsideState()
        manager.evaluateHighAccuracyProximity(latitude: centerLat, longitude: centerLng, accuracy: 8.0)

        XCTAssertEqual(count("ENTER"), 2, "a fresh start re-emits the initial-entry ENTER")
    }
}

private final class NoopResumeChurnEventSender: TraceletEventSending {
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
