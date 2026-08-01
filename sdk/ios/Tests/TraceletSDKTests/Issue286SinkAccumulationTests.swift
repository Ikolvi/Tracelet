import CoreLocation
import XCTest
@testable import TraceletSDK

/// Regression tests for #286 — stale sync sinks staying subscribed to the
/// LocationEngine.
///
/// `registerSink` used to be a bare `sinks.append`, and there was no way to
/// detach a sink at all. Two consequences: the sync plugin subscribed the same
/// sink twice per engine (once directly, once through the
/// `TraceletSdk.syncProvider` didSet), and a superseded provider — a sink left
/// behind by an earlier `FlutterEngine`, or the NativeSyncProvider created during
/// a background boot — stayed subscribed for the life of the engine. Every extra
/// entry fans one persisted location out into another `insertLocation`, and each
/// distinct sink then debounces its own sync.
final class Issue286SinkAccumulationTests: XCTestCase {
    private final class CountingSink: LocationDataSink {
        var inserts = 0

        @discardableResult
        func insertLocation(_ location: [String: Any]) -> String {
            inserts += 1
            return ""
        }
    }

    private func makeEngine() -> LocationEngine {
        LocationEngine(
            configManager: ConfigManager(),
            stateManager: StateManager(),
            eventDispatcher: NoopSinkEventSender()
        )
    }

    func testRegisterSinkDedupesTheSameInstance() {
        let engine = makeEngine()
        let sink = CountingSink()

        // The three real paths that all register the current provider: the plugin,
        // the syncProvider didSet, and initialize() building a new engine.
        engine.registerSink(sink)
        engine.registerSink(sink)
        engine.registerSink(sink)

        XCTAssertEqual(
            engine.sinks.count, 1,
            "the same sink must be subscribed exactly once, else one persisted "
                + "location fans out into several insertLocation calls (#286)"
        )
    }

    func testDistinctSinksAreBothKept() {
        let engine = makeEngine()
        let persistence = CountingSink()
        let sync = CountingSink()

        engine.registerSink(persistence)
        engine.registerSink(sync)

        XCTAssertEqual(
            engine.sinks.count, 2,
            "dedupe must be by identity — different sinks still both subscribe"
        )
    }

    func testUnregisterSinkDetachesOnlyThatSink() {
        let engine = makeEngine()
        let stale = CountingSink()
        let current = CountingSink()
        engine.registerSink(stale)
        engine.registerSink(current)

        engine.unregisterSink(stale)

        XCTAssertEqual(engine.sinks.count, 1)
        XCTAssertTrue(
            engine.sinks.contains { ($0 as AnyObject) === current },
            "unregisterSink must remove the given sink and keep the rest (#286)"
        )
    }

    func testUnregisteringAnUnknownSinkIsANoOp() {
        let engine = makeEngine()
        let current = CountingSink()
        engine.registerSink(current)

        engine.unregisterSink(CountingSink())

        XCTAssertEqual(engine.sinks.count, 1)
    }
}

private final class NoopSinkEventSender: TraceletEventSending {
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
    func hasListener(eventName: String) -> Bool { false }
}
