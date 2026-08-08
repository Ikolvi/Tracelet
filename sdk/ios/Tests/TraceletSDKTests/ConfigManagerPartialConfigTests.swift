import XCTest

@testable import TraceletSDK

/// #321: a partial `setConfig()` must not overwrite persisted values.
///
/// `ConfigManager.setConfig` is a merge that skips `NSNull`/absent keys, and
/// that guard was always correct — but the Dart model declared every field
/// non-nullable with a default, so the bridge never sent an absent key. A
/// `setConfig()` that mentioned nothing arrived as a complete dictionary of
/// defaults and was written over the stored configuration.
///
/// On iOS the visible damage was the flags that keep background tracking
/// alive: `showsBackgroundLocationIndicator`, `preventSuspend` and
/// `useBackgroundActivitySession` all silently reverted to `false`. That is the
/// same defect as the Android foreground-service one in #320, reached through
/// different fields.
///
/// These tests pin the native half of the contract: an absent key preserves,
/// an explicit value overwrites — including when it equals the default.
final class ConfigManagerPartialConfigTests: XCTestCase {

    private var cm: ConfigManager!

    /// What an app configures once, through `ready()`.
    private let configured: [String: Any] = [
        "showsBackgroundLocationIndicator": true,
        "preventSuspend": true,
        "useBackgroundActivitySession": true,
        "distanceFilter": 25.0,
        "url": "https://example.com/sync",
    ]

    override func setUp() {
        super.setUp()
        cm = ConfigManager()
        cm.reset(nil)
    }

    /// The reported failure: configure, then call setConfig() about something
    /// else entirely.
    func testPartialSetConfigPreservesUnmentionedKeys() {
        _ = cm.setConfig(configured)
        XCTAssertTrue(cm.getShowsBackgroundLocationIndicator())

        _ = cm.setConfig(["heartbeatInterval": 30])

        XCTAssertTrue(
            cm.getShowsBackgroundLocationIndicator(),
            "the background location indicator setting must survive an unrelated setConfig()")
        XCTAssertTrue(cm.getPreventSuspend())
        XCTAssertTrue(cm.getUseBackgroundActivitySession())
        XCTAssertEqual(cm.getDistanceFilter(), 25.0)
        XCTAssertEqual(cm.getUrl(), "https://example.com/sync")
    }

    /// What the fixed Dart layer now puts on the wire for a `Config()` that
    /// configures nothing: the keys are simply not there.
    func testEmptyPayloadChangesNothing() {
        _ = cm.setConfig(configured)

        _ = cm.setConfig([:])

        XCTAssertTrue(cm.getShowsBackgroundLocationIndicator())
        XCTAssertTrue(cm.getPreventSuspend())
        XCTAssertEqual(cm.getDistanceFilter(), 25.0)
    }

    /// NSNull is treated as absent, which is how a nulled Pigeon field arrives.
    func testNSNullIsTreatedAsAbsent() {
        _ = cm.setConfig(configured)

        _ = cm.setConfig([
            "showsBackgroundLocationIndicator": NSNull(),
            "preventSuspend": NSNull(),
        ])

        XCTAssertTrue(cm.getShowsBackgroundLocationIndicator())
        XCTAssertTrue(cm.getPreventSuspend())
    }

    /// A supplied value must still win, even when it equals the default —
    /// "unset" means *not provided*, never *equal to the default*. A fix that
    /// dropped default-valued fields would leave these flags impossible to
    /// turn back off.
    func testExplicitFalseOverwritesStoredTrue() {
        _ = cm.setConfig(configured)
        XCTAssertTrue(cm.getPreventSuspend())

        _ = cm.setConfig(["preventSuspend": false])

        XCTAssertFalse(cm.getPreventSuspend())
        // Everything alongside it was not supplied, so it is untouched.
        XCTAssertTrue(cm.getShowsBackgroundLocationIndicator())
        XCTAssertEqual(cm.getDistanceFilter(), 25.0)
    }

    /// Nothing configured still yields the documented defaults, so omitting an
    /// unset field cannot change behaviour on a fresh install.
    func testUnconfiguredFallsBackToDefaults() {
        _ = cm.setConfig(["heartbeatInterval": 60])

        XCTAssertFalse(cm.getShowsBackgroundLocationIndicator())
        XCTAssertFalse(cm.getPreventSuspend())
        XCTAssertFalse(cm.getUseBackgroundActivitySession())
    }
}
