import CoreLocation
import XCTest

@testable import TraceletSDK

/// #409 — the iOS half of the evidence a "GPS ran all day while parked" report
/// is triaged from.
///
/// The speed/smart pipeline parks by stopping continuous updates *without*
/// tearing the session down: `CLServiceSession` / `CLBackgroundActivitySession`
/// survive, and `isTracking` deliberately stays true so delegate callbacks keep
/// being processed. Nothing on the always-on channel recorded that transition —
/// `stop()` was the only place that logged it, and a park never goes through
/// `stop()`. Android runs the same switch through `LocationEngine.stop()` and
/// records it, so `location stream: continuous updates stopping` was present on
/// one platform and unobtainable on the other, at any `logLevel`.
///
/// Two things depend on getting this right, and both are pinned here:
///
///  * the report. `logLevel: off` is what a released app ships with, so these
///    assertions run at `off` — a line that only survives DEBUG answers nothing.
///  * the posture. `TraceletSmartMotionCoordinator.syncCurrentMode()` ORs the
///    committed pace with the engine's state to decide whether the coordinator
///    believes it is streaming (#409). `isTracking` is true on a parked engine,
///    so that question needed a signal that means what it asks —
///    ``LocationEngine/isContinuousStreaming``.
final class LocationEngineStationaryParkLogTests: XCTestCase {

    private var db: DatabaseManager!
    private var dbPath: String!
    private var config: ConfigManager!
    private var engine: LocationEngine!

    override func setUpWithError() throws {
        try super.setUpWithError()

        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("park_log_\(UUID().uuidString).db").path
        db = try DatabaseManager(dbPath: dbPath)
        try? db.setEncryptionKey(key: "")
        try? db.clearLogs()

        config = ConfigManager()
        config.reset(nil)
        // What a released app ships with. The park has to be legible from a
        // report taken at this level or it is not evidence.
        _ = config.setConfig(["logLevel": 0])

        let logger = TraceletLogger(configManager: config)
        logger.rustDatabase = db
        TraceletLog.attach(logger)

        engine = LocationEngine(
            configManager: config,
            stateManager: StateManager(),
            eventDispatcher: ParkLogNoopEventSender()
        )
        let manager = ParkLogLocationManager()
        engine.locationManager = manager
        manager.delegate = engine
    }

    override func tearDown() {
        engine.stop()
        TraceletLog.detach()
        if let dbPath { try? FileManager.default.removeItem(atPath: dbPath) }
        super.tearDown()
    }

    // MARK: - Helpers

    /// Logs persist asynchronously on a serial queue, so poll rather than
    /// assuming the write has landed.
    private func lifecycleLines(
        containing needle: String,
        timeout: TimeInterval = 2.0
    ) -> [String] {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let hits = ((try? db.getLogs(limit: 500)) ?? [])
                .filter { $0.level == TraceletLogger.lifecycleLevelName && $0.message.contains(needle) }
                .map(\.message)
            if !hits.isEmpty { return hits }
            usleep(25_000)
        } while Date() < deadline
        return []
    }

    /// The negative direction needs the whole window to elapse — an empty read
    /// taken immediately would pass before the write it is denying could land.
    private func settledLifecycleLines(containing needle: String) -> [String] {
        usleep(300_000)
        return ((try? db.getLogs(limit: 500)) ?? [])
            .filter { $0.level == TraceletLogger.lifecycleLevelName && $0.message.contains(needle) }
            .map(\.message)
    }

    // MARK: - The park

    func testParkingALiveStreamIsRecordedOnTheAlwaysOnChannel() {
        engine.start()
        XCTAssertTrue(engine.isContinuousStreaming, "precondition: the stream is live")
        XCTAssertFalse(
            lifecycleLines(containing: "continuous updates starting").isEmpty,
            "precondition: the start of the stream is already recorded")

        engine.switchToStationaryPeriodic()

        XCTAssertFalse(
            lifecycleLines(containing: "continuous updates stopping").isEmpty,
            "#409: a released app's report has to be able to say when GPS was "
                + "parked. Without this line the only readable trace of a session "
                + "that never parked is identical to one that did")
    }

    func testParkingIntoGeofencesIsRecordedToo() {
        engine.start()
        engine.switchToStationaryGeofences()

        XCTAssertFalse(
            lifecycleLines(containing: "continuous updates stopping").isEmpty,
            "the geofence park stops the same stream the periodic one does")
    }

    /// The line has to mean "updates stopped", not "the switch method ran".
    func testParkingWithNoStreamRunningRecordsNothing() {
        // A session resuming stationary parks an engine that never streamed.
        engine.switchToStationaryPeriodic()

        XCTAssertTrue(
            settledLifecycleLines(containing: "continuous updates stopping").isEmpty,
            "narrating a stop that never happened puts a park in the report at a "
                + "time the device was not streaming")
    }

    /// A `stop()` after a park must not date the parking to the moment the user
    /// stopped tracking — minutes or hours later.
    func testStoppingAfterAParkDoesNotRecordASecondStop() {
        engine.start()
        engine.switchToStationaryPeriodic()
        XCTAssertEqual(lifecycleLines(containing: "continuous updates stopping").count, 1)

        engine.stop()

        XCTAssertEqual(
            settledLifecycleLines(containing: "continuous updates stopping").count, 1,
            "the stream stopped once, at the park")
    }

    func testResumingOutOfAParkIsRecorded() {
        engine.start()
        engine.switchToStationaryPeriodic()
        let startsBeforeResume = lifecycleLines(containing: "continuous updates starting").count

        engine.switchToContinuous()

        XCTAssertEqual(
            settledLifecycleLines(containing: "continuous updates starting").count,
            startsBeforeResume + 1,
            "the wake-up out of a park reopens the stream the park closed, and "
                + "the report needs both ends of that interval")
    }

    /// A mode that deliberately starts no stream must not report one, or the
    /// report carries a start with no stop — the shape of the session #409 is
    /// about.
    func testASessionThatSkipsContinuousGpsSaysSo() {
        _ = config.setConfig(["useSignificantChangesOnly": true])

        engine.start()

        XCTAssertFalse(engine.isContinuousStreaming)
        XCTAssertTrue(
            settledLifecycleLines(containing: "continuous updates starting").isEmpty,
            "significant-changes-only starts no continuous stream by design")
        XCTAssertFalse(
            lifecycleLines(containing: "continuous updates skipped").isEmpty,
            "and the report has to say which of the two skip modes it is in")
    }

    // MARK: - The signal the posture reads

    /// Why `syncCurrentMode()` cannot ask `isTracking`.
    func testAParkedEngineIsStillTrackingButNoLongerStreaming() {
        engine.start()
        XCTAssertTrue(engine.isTracking)
        XCTAssertTrue(engine.isContinuousStreaming)

        engine.switchToStationaryPeriodic()

        XCTAssertTrue(
            engine.isTracking,
            "the session is alive by design — delegate callbacks still have to "
                + "be processed while parked")
        XCTAssertFalse(
            engine.isContinuousStreaming,
            "#409: ORing `isTracking` into the posture writes Continuous into a "
                + "coordinator whose engine is parked, and the core emits no "
                + "wake-up for a posture it already believes is Continuous — "
                + "#344's swallowed shake, re-entered from the other side")

        engine.switchToContinuous()
        XCTAssertTrue(engine.isContinuousStreaming, "the resume restores the stream")
    }

    func testAGeofenceParkAlsoClearsTheStreamingSignal() {
        engine.start()

        engine.switchToStationaryGeofences()

        XCTAssertFalse(
            engine.isContinuousStreaming,
            "the geofence park leaves `isPeriodicTracking` false, so nothing "
                + "else in the engine records that continuous updates ended")
    }
}

private final class ParkLogLocationManager: CLLocationManager {
    private var _allowsBackground = false

    // The real setter raises without the UIBackgroundModes:location entitlement,
    // which the test bundle lacks.
    override var allowsBackgroundLocationUpdates: Bool {
        get { _allowsBackground }
        set { _allowsBackground = newValue }
    }

    override var authorizationStatus: CLAuthorizationStatus { .authorizedAlways }

    override func requestLocation() {}
    override func startUpdatingLocation() {}
    override func stopUpdatingLocation() {}
    override func startMonitoringSignificantLocationChanges() {}
    override func stopMonitoringSignificantLocationChanges() {}
}

private final class ParkLogNoopEventSender: TraceletEventSending {
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
