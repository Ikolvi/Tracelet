import CoreLocation
import XCTest

@testable import TraceletSDK

/// Regression tests for GitHub issue #407:
///   "the stall watchdog is fix-driven, so a stream that delivers nothing never
///    reports a stall — and the Doctor calls it healthy"
///
/// `noteFilterDecision` only runs when a fix arrives, so the one failure mode
/// where the SDK is completely blind — CoreLocation delivering nothing at all —
/// produced no signal at all. A Doctor report covering a 52-second dead window
/// (#405) printed *"the stream has been accepting fixes"*; it had accepted none.
///
/// The distinction these tests pin is not cosmetic. Rejection means the pipeline
/// is alive and mis-tuned, and a threshold change fixes it. Silence means the OS
/// has stopped talking to the app, and no threshold change will ever help. They
/// need different messages because they need different responses.
///
/// Assertions run at `logLevel: 0` — what a released app ships with — because a
/// line that only survives DEBUG answers nothing about a field report. The clock
/// is passed into ``LocationEngine/evaluateSilence(atUptime:)`` rather than
/// waited out: a suite that sleeps 45 seconds per case is a suite that gets
/// deleted, and Build iOS already flakes on a loaded runner (#329).
final class LocationEngineSilenceWatchdogTests: XCTestCase {

    private var db: DatabaseManager!
    private var dbPath: String!
    private var config: ConfigManager!
    private var engine: LocationEngine!

    override func setUpWithError() throws {
        try super.setUpWithError()

        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("silence_\(UUID().uuidString).db").path
        db = try DatabaseManager(dbPath: dbPath)
        try? db.setEncryptionKey(key: "")
        try? db.clearLogs()

        config = ConfigManager()
        config.reset(nil)
        _ = config.setConfig(["logLevel": 0])

        let logger = TraceletLogger(configManager: config)
        logger.rustDatabase = db
        TraceletLog.attach(logger)

        engine = LocationEngine(
            configManager: config,
            stateManager: StateManager(),
            eventDispatcher: SilenceNoopEventSender()
        )
        let manager = SilenceLocationManager()
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

    // MARK: - The reported failure

    /// A continuous stream that never delivers must say so on its own schedule —
    /// nothing else is going to call the watchdog.
    func testAStreamThatDeliversNothingAnnouncesSilenceOnItsOwnTimer() {
        engine.start()
        XCTAssertTrue(engine.isContinuousStreaming, "precondition: the stream is live")
        let start = ProcessInfo.processInfo.systemUptime

        engine.evaluateSilence(atUptime: start + 30)
        XCTAssertTrue(
            settledLifecycleLines(containing: "location stream silent").isEmpty,
            "30s is inside the announce window — announcing here would fire on every "
                + "stationary-to-moving transition and be tuned out")

        engine.evaluateSilence(atUptime: start + 60)
        XCTAssertFalse(
            lifecycleLines(containing: "location stream silent").isEmpty,
            "#407: 60s with no callback at all must be announced, and on the always-on "
                + "lifecycle channel so a released app can report it")
    }

    /// The line has to carry the request it is complaining about. "No fixes"
    /// with no numbers is the same dead end as the bare `DISTANCE_FILTER` line
    /// #397 replaced — unfalsifiable without the source open.
    func testTheSilenceLineCarriesTheRequestThatIsSupposedlyLive() {
        engine.start()
        engine.evaluateSilence(atUptime: ProcessInfo.processInfo.systemUptime + 60)

        guard let line = lifecycleLines(containing: "location stream silent").first else {
            return XCTFail("expected a silence line")
        }
        XCTAssertTrue(line.contains("interval="), "must name the interval: \(line)")
        XCTAssertTrue(line.contains("accuracy="), "must name the accuracy: \(line)")
        XCTAssertTrue(
            line.contains("not the filter"),
            "must say this is the provider, not the filter — the two have different "
                + "fixes and the report is read by someone deciding which: \(line)")
    }

    /// A delivered callback is a live stream, whatever the filter later decides
    /// about it. Sharing the filter's clock is exactly the bug.
    func testADeliveredFixKeepsTheStreamFromBeingCalledSilent() {
        engine.start()
        let start = ProcessInfo.processInfo.systemUptime

        engine.noteCallbackDelivered(atUptime: start + 30)
        engine.evaluateSilence(atUptime: start + 60)

        XCTAssertTrue(
            settledLifecycleLines(containing: "location stream silent").isEmpty,
            "the provider delivered inside the window, so the stream is not silent — "
                + "whether the filter kept that fix is a different question with a "
                + "different watchdog (#397)")
    }

    /// One line per silence, not one per tick — the lifecycle channel is
    /// always-on, and a watchdog that repeats every 15s drowns the trace it
    /// exists to make readable.
    func testSilenceIsAnnouncedOnceUntilItRecovers() {
        engine.start()
        let start = ProcessInfo.processInfo.systemUptime

        engine.evaluateSilence(atUptime: start + 60)
        engine.evaluateSilence(atUptime: start + 75)
        engine.evaluateSilence(atUptime: start + 90)

        XCTAssertEqual(
            settledLifecycleLines(containing: "location stream silent").count, 1,
            "the watchdog polls every 15s; announcing each tick would bury the trace")
    }

    /// Recovery has to be stated, not inferred from the next unrelated line — a
    /// report showing only the onset cannot say whether the stream came back.
    func testRecoveryFromSilenceIsAnnounced() {
        engine.start()
        let start = ProcessInfo.processInfo.systemUptime

        engine.evaluateSilence(atUptime: start + 60)
        XCTAssertFalse(lifecycleLines(containing: "location stream silent").isEmpty)

        engine.noteCallbackDelivered(atUptime: start + 70)

        XCTAssertFalse(
            lifecycleLines(containing: "location stream resumed").isEmpty,
            "#407: the stream coming back is as much a fact for the report as it going away")
    }

    // MARK: - The silences that are the design

    /// A stopped stream is silent by definition. Announcing it would put a red
    /// line in every bug report from a device that is simply not tracking.
    func testAStoppedStreamIsNotAnnouncedAsSilent() {
        engine.start()
        engine.stop()

        engine.evaluateSilence(atUptime: ProcessInfo.processInfo.systemUptime + 120)

        XCTAssertTrue(
            settledLifecycleLines(containing: "location stream silent").isEmpty,
            "stop() cancels the watchdog: silence after a deliberate stop is the design")
    }

    /// The one the issue calls out by name. Stationary-periodic spends nearly
    /// all of its life not delivering fixes — that is what it is for.
    func testAStationaryParkIsNotAnnouncedAsSilent() {
        engine.start()
        engine.switchToStationaryPeriodic()

        engine.evaluateSilence(atUptime: ProcessInfo.processInfo.systemUptime + 120)

        XCTAssertTrue(
            settledLifecycleLines(containing: "location stream silent").isEmpty,
            "#407: silence between periodic ticks is the designed behaviour, and a "
                + "watchdog that announces it makes every parked device look broken")
    }

    /// And the resume has to re-arm it, or a park early in a session disables
    /// the watchdog for everything after it.
    func testResumingOutOfAParkRearmsTheWatchdog() {
        engine.start()
        engine.switchToStationaryPeriodic()
        engine.switchToContinuous()
        XCTAssertTrue(engine.isContinuousStreaming, "precondition: the stream is live again")

        engine.evaluateSilence(atUptime: ProcessInfo.processInfo.systemUptime + 120)

        XCTAssertFalse(
            lifecycleLines(containing: "location stream silent").isEmpty,
            "the stream the resume reopened is a stream the watchdog has to cover — "
                + "otherwise one park early in a session blinds the rest of it")
    }
}

private final class SilenceLocationManager: CLLocationManager {
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

private final class SilenceNoopEventSender: TraceletEventSending {
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
