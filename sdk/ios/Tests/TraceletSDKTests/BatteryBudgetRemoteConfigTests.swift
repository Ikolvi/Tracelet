import XCTest
@testable import TraceletSDK

/// Regression tests for the remote-config battery-budget bug.
///
/// `batteryBudgetPerHour` used to be read only at `ready()`, so a value that
/// arrived afterwards — e.g. a remote config push of
/// `{"geo":{"batteryBudgetPerHour":1.0}}` applied at runtime via `setConfig()` —
/// was written into the config cache but never acted on: the battery-budget
/// engine stayed exactly as `ready()` had left it. It only appeared to work
/// after a cold restart (the cached remote config is applied *before* `ready()`
/// builds the engine).
///
/// These tests drive the exact runtime path the remote-config fetch uses
/// (`setConfig`) and assert the engine is (re)built / torn down accordingly.
/// Every `ready()`/`setConfig()` passes `batteryBudgetPerHour` explicitly so the
/// assertions are immune to any value persisted by a previous run.
final class BatteryBudgetRemoteConfigTests: XCTestCase {

    private func geo(_ budget: Double) -> [String: Any] {
        return ["geo": ["batteryBudgetPerHour": budget] as [String: Any]]
    }

    override func setUp() {
        super.setUp()
        // initialize() only wires up subsystems (safe to call before ready());
        // it does NOT flip isReady. Touching reset()/stop()/getState() before any
        // ready() would dereference nil IUOs, so we never do that here.
        TraceletSdk.shared.initialize()
    }

    override func tearDown() {
        let sdk = TraceletSdk.shared
        if sdk.isReadyState {
            sdk.stop()
            sdk.reset(nil)
        }
        super.tearDown()
    }

    /// The reported scenario: `ready()` starts with the budget OFF (mirroring
    /// `Config.balanced()` used by the remote-config example card), then the
    /// budget arrives at runtime via `setConfig()`. The engine MUST become
    /// active — before the fix it stayed nil until a cold restart.
    func testRuntimeConfigEnablesBatteryBudget() {
        let sdk = TraceletSdk.shared
        sdk.ready(config: geo(0.0))
        XCTAssertFalse(
            sdk.isBatteryBudgetEngineActive,
            "battery budget must be off when ready() had batteryBudgetPerHour=0"
        )

        // Simulate the remote-config fetch applying the gist at runtime.
        _ = sdk.setConfig(geo(1.0))

        XCTAssertTrue(
            sdk.isBatteryBudgetEngineActive,
            "runtime setConfig({geo:{batteryBudgetPerHour:1.0}}) must (re)build the engine"
        )
    }

    /// Same as above but while tracking is active — the real remote-config
    /// timing, since the background fetch lands after `ready()` + `start()`.
    func testRuntimeConfigEnablesBatteryBudgetWhileTracking() {
        let sdk = TraceletSdk.shared
        sdk.ready(config: geo(0.0))
        sdk.start()
        XCTAssertFalse(sdk.isBatteryBudgetEngineActive)

        _ = sdk.setConfig(geo(1.0))

        XCTAssertTrue(
            sdk.isBatteryBudgetEngineActive,
            "an active tracking session must pick up a remote batteryBudgetPerHour"
        )
    }

    /// An integer-encoded value (`1` rather than `1.0`) must be honoured too —
    /// JSON from a remote endpoint frequently drops the decimal point.
    func testRuntimeConfigEnablesBatteryBudgetIntEncoded() {
        let sdk = TraceletSdk.shared
        sdk.ready(config: geo(0.0))

        _ = sdk.setConfig(["geo": ["batteryBudgetPerHour": 1] as [String: Any]])

        XCTAssertTrue(
            sdk.isBatteryBudgetEngineActive,
            "integer-encoded batteryBudgetPerHour (1) must build the engine"
        )
    }

    /// The inverse: a runtime config of `0` must tear the engine down, so remote
    /// config can disable the budget as well as enable it.
    func testRuntimeConfigDisablesBatteryBudget() {
        let sdk = TraceletSdk.shared
        sdk.ready(config: geo(2.0))
        XCTAssertTrue(
            sdk.isBatteryBudgetEngineActive,
            "battery budget must be on when ready() supplied batteryBudgetPerHour=2"
        )

        _ = sdk.setConfig(geo(0.0))

        XCTAssertFalse(
            sdk.isBatteryBudgetEngineActive,
            "runtime setConfig with batteryBudgetPerHour=0 must disable the engine"
        )
    }
}
