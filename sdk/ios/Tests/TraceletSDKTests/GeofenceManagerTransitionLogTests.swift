import CoreLocation
import XCTest
@testable import TraceletSDK

/// Covers the `[geofence]` decision trace emitted on every high-accuracy
/// transition — the iOS half of the Android `GeofenceManagerTransitionLogTest`.
///
/// `evaluateHighAccuracyProximity` and `handleTransition` logged nothing at all
/// on either platform, so a field report of "occasional false EXIT" produced a
/// bug report with zero geofence content and triage had to proceed from config
/// alone.
///
/// Parity here is not cosmetic. The Doctor bug report lifts geofence activity
/// into its own section by filtering for the literal `[geofence]`, so if the tag
/// or the field names drift between platforms that section silently becomes
/// Android-only. These tests pin the tag and the field set.
///
/// Assertions read back through the persisted log store (`DatabaseManager`),
/// which is the same source `Tracelet.getLogs()` and Doctor export from.
final class GeofenceManagerTransitionLogTests: XCTestCase {

    private var db: DatabaseManager!
    private var config: ConfigManager!
    private var manager: GeofenceManager!
    private var dbPath: String!

    private let centerLat = 10.787929
    private let centerLng = 76.684183
    private let radius = 50.0 // exit threshold = radius + max(radius*0.1, 20) = 70 m

    private func north(_ meters: Double) -> Double { centerLat + meters / 111_320.0 }

    override func setUpWithError() throws {
        try super.setUpWithError()

        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("geofence_trace_\(UUID().uuidString).db").path
        db = try DatabaseManager(dbPath: dbPath)
        try? db.setEncryptionKey(key: "")
        try? db.clearGeofences()
        try? db.clearLogs()
        try db.insertGeofence(
            identifier: "ZONE_LOG",
            lat: centerLat,
            lng: centerLng,
            radius: radius,
            vertices: nil,
            extras: nil
        )

        config = ConfigManager()
        _ = config.setConfig([
            "geofenceModeHighAccuracy": true,
            "logLevel": 4, // DEBUG
        ])

        // Attach the real logger so assertions run against the persisted store
        // that Doctor exports from.
        let logger = TraceletLogger(configManager: config)
        logger.rustDatabase = db
        TraceletLog.attach(logger)

        manager = GeofenceManager(
            configManager: config,
            eventSender: NoopGeofenceEventSender(),
            rustDatabase: db
        )
        manager.clearHighAccuracyState()
    }

    override func tearDown() {
        TraceletLog.detach()
        if let dbPath { try? FileManager.default.removeItem(atPath: dbPath) }
        super.tearDown()
    }

    // MARK: - Helpers

    /// iOS persists logs asynchronously on a serial queue, so poll rather than
    /// assuming the write has landed.
    private func geofenceLines(timeout: TimeInterval = 2.0) -> [(level: String, message: String)] {
        let deadline = Date().addingTimeInterval(timeout)
        var found: [(level: String, message: String)] = []
        repeat {
            let entries = (try? db.getLogs(limit: 500)) ?? []
            found = entries
                .filter { $0.message.contains("[geofence]") }
                .map { (level: $0.level, message: $0.message) }
                .reversed()
            if !found.isEmpty { return found }
            usleep(25_000)
        } while Date() < deadline
        return found
    }

    private func infoLines() -> [String] {
        geofenceLines().filter { $0.level == "INFO" }.map { $0.message }
    }

    private func firstExitAtInfo() -> String? {
        infoLines().first { $0.contains("EXIT") }
    }

    // MARK: - Transitions must be visible at INFO

    func testEnterIsLoggedAtInfoWithTheGeofenceCategoryTag() {
        manager.evaluateHighAccuracyProximity(latitude: centerLat, longitude: centerLng, accuracy: 8.0)

        XCTAssertTrue(
            infoLines().contains { $0.contains("ENTER") && $0.contains("ZONE_LOG") },
            "expected an INFO [geofence] ENTER line, got: \(geofenceLines())"
        )
    }

    func testExitIsLoggedAtInfoCarryingEveryInputToTheAccuracyAwareTest() {
        manager.evaluateHighAccuracyProximity(latitude: centerLat, longitude: centerLng, accuracy: 8.0)
        // Genuine, sustained departure: 200 m out with a tight ±10 m fix ->
        // 190 > 70. Two consecutive fixes confirm the EXIT.
        manager.evaluateHighAccuracyProximity(latitude: north(200.0), longitude: centerLng, accuracy: 10.0)
        manager.evaluateHighAccuracyProximity(latitude: north(200.0), longitude: centerLng, accuracy: 10.0)

        guard let exit = firstExitAtInfo() else {
            return XCTFail("expected an INFO [geofence] EXIT line, got: \(geofenceLines())")
        }

        // Field names must match Android exactly — a bug report should read the
        // same on both platforms.
        for field in ["dist=", "radius=", "buffer=", "thr=", "accRaw=", "accEff="] {
            XCTAssertTrue(exit.contains(field), "EXIT trace is missing '\(field)': \(exit)")
        }
    }

    // MARK: - Privacy

    func testTraceDoesNotLeakRawCoordinates() {
        manager.evaluateHighAccuracyProximity(latitude: centerLat, longitude: centerLng, accuracy: 8.0)
        manager.evaluateHighAccuracyProximity(latitude: north(200.0), longitude: centerLng, accuracy: 10.0)
        manager.evaluateHighAccuracyProximity(latitude: north(200.0), longitude: centerLng, accuracy: 10.0)

        // These reports get pasted into public issues. Distance-from-centre is
        // all triage needs; absolute position is not.
        for line in geofenceLines() {
            XCTAssertFalse(
                line.message.contains("10.787") || line.message.contains("76.684"),
                "geofence log line leaked coordinates: \(line.message)"
            )
        }
    }

    // MARK: - The #276 clamp and invalid accuracy must be visible

    func testTraceSurfacesTheExitAccuracyMaxClampWhenItBinds() {
        // Exactly the confusion behind the field report: a clamp is configured
        // and the operator cannot tell whether it took effect.
        _ = config.setConfig(["geofenceExitAccuracyMax": 20])
        manager.evaluateHighAccuracyProximity(latitude: centerLat, longitude: centerLng, accuracy: 8.0)
        manager.evaluateHighAccuracyProximity(latitude: north(200.0), longitude: centerLng, accuracy: 150.0)
        manager.evaluateHighAccuracyProximity(latitude: north(200.0), longitude: centerLng, accuracy: 150.0)

        guard let exit = firstExitAtInfo() else {
            return XCTFail("expected an EXIT line, got: \(geofenceLines())")
        }
        XCTAssertTrue(exit.contains("accRaw=150.0"), "raw accuracy must be reported: \(exit)")
        XCTAssertTrue(exit.contains("accEff=20.0"), "clamped accuracy must be reported: \(exit)")
        XCTAssertTrue(exit.contains("clampApplied=true"), "clamp must be flagged: \(exit)")
        XCTAssertTrue(exit.contains("exitAccuracyMax=20"), "the knob must be echoed: \(exit)")
    }

    func testTraceFlagsNegativeAccuracyAsGatingDisabled() {
        // CoreLocation reports a negative horizontalAccuracy when the fix has no
        // valid accuracy, and LocationEngine forwards it unchanged. The evaluator
        // maps any non-positive value to "gating disabled", so unknown
        // uncertainty behaves as zero uncertainty — an inverted safe default that
        // makes a false EXIT far more likely and is invisible without this flag.
        manager.evaluateHighAccuracyProximity(latitude: centerLat, longitude: centerLng, accuracy: 8.0)
        manager.evaluateHighAccuracyProximity(latitude: north(200.0), longitude: centerLng, accuracy: -1.0)
        manager.evaluateHighAccuracyProximity(latitude: north(200.0), longitude: centerLng, accuracy: -1.0)

        guard let exit = firstExitAtInfo() else {
            return XCTFail("expected an EXIT line, got: \(geofenceLines())")
        }
        XCTAssertTrue(exit.contains("accuracyInvalid=true"), "invalid accuracy must be flagged: \(exit)")
        XCTAssertTrue(exit.contains("gatingDisabled=true"), "disabled gating must be flagged: \(exit)")
    }

    // MARK: - The logged threshold must match the evaluator's real behavior

    func testLoggedExitThresholdAgreesWithTheEvaluatorAtTheBoundary() {
        // The hysteresis constants are mirrored in Swift for logging while the
        // Rust core owns the decision. This pins the mirror: if Rust changes its
        // fraction or floor, the logged threshold stops matching real behavior
        // and this fails instead of silently misreporting.
        manager.evaluateHighAccuracyProximity(latitude: centerLat, longitude: centerLng, accuracy: 8.0)

        // Just inside the logged threshold (70 m) with a perfect fix -> held.
        manager.evaluateHighAccuracyProximity(latitude: north(69.0), longitude: centerLng, accuracy: 0.0)
        XCTAssertNil(firstExitAtInfo(), "69 m must not exit a 70 m threshold: \(geofenceLines())")

        // Just outside -> exits (confirmed across two fixes), and the line must
        // report thr=70.0.
        manager.evaluateHighAccuracyProximity(latitude: north(71.0), longitude: centerLng, accuracy: 0.0)
        manager.evaluateHighAccuracyProximity(latitude: north(71.0), longitude: centerLng, accuracy: 0.0)
        guard let exit = firstExitAtInfo() else {
            return XCTFail("71 m must exit a 70 m threshold: \(geofenceLines())")
        }
        XCTAssertTrue(
            exit.contains("thr=70.0") && exit.contains("buffer=20.0"),
            "logged threshold must match the Rust constants: \(exit)"
        )
    }

    // MARK: - Volume guard

    func testEvaluationWithNoGeofencesLogsNothing() {
        // The trace must not fire on every location update.
        try? db.clearGeofences()
        let emptyManager = GeofenceManager(
            configManager: config,
            eventSender: NoopGeofenceEventSender(),
            rustDatabase: db
        )
        emptyManager.clearHighAccuracyState()
        try? db.clearLogs()

        emptyManager.evaluateHighAccuracyProximity(latitude: centerLat, longitude: centerLng, accuracy: 8.0)
        XCTAssertTrue(
            geofenceLines(timeout: 0.5).isEmpty,
            "no geofences means no geofence logging: \(geofenceLines(timeout: 0.5))"
        )
    }
}

private final class NoopGeofenceEventSender: TraceletEventSending {
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
