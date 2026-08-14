import XCTest
@testable import TraceletSDK

/// #383 — `persistMode` was not honoured for geofence ENTER/EXIT transitions.
///
/// `GeofenceManager.onGeofenceEvent` was wired straight to
/// `TraceletSdk.insertLocation`, bypassing the only persist-mode check on the
/// platform (`LocationEngine.persistLocationIfAllowed`). `location` and `none`
/// therefore persisted — and HTTP-synced — every crossing, contradicting their
/// documented meaning. `none` is the privacy-relevant case: an app wanting
/// geofence callbacks without a location history still accumulated one.
///
/// **Scope.** This suite covers the decision itself —
/// `ConfigManager.shouldPersistGeofenceRecords`, the predicate the fix routes
/// the geofence path through. It does not cover `TraceletSdk`'s wiring, whose
/// `rustDatabase` is `public private(set)` and so cannot be injected from a
/// test; that wiring is a mirror of the Android one covered by
/// `TraceletSdkGeofencePersistModeTest`, and is verified end-to-end on device by
/// the #383 example card. This is the same split `DatabaseRetentionCapsTests`
/// documents for #361.
final class ConfigManagerGeofencePersistModeTests: XCTestCase {

    private var config: ConfigManager!

    override func setUp() {
        super.setUp()
        config = ConfigManager()
        config.reset(nil)
    }

    override func tearDown() {
        config.reset(nil)
        config = nil
        super.tearDown()
    }

    /// Sets the mode through the nested `persistence` section — the shape every
    /// transport actually sends — rather than the flat key.
    private func setPersistMode(_ mode: Int) {
        _ = config.setConfig(["persistence": ["persistMode": mode]])
        XCTAssertEqual(config.getPersistMode(), mode, "config precondition")
    }

    /// Mode 0 = all, and the default when the key was never set. Both must keep
    /// persisting geofence rows — the fix must not turn into data loss for the
    /// apps that never configured `persistMode` at all.
    func testModeAllPersistsGeofenceRecords() {
        XCTAssertEqual(config.getPersistMode(), 0, "default is `all`")
        XCTAssertTrue(config.shouldPersistGeofenceRecords(), "unset default must persist")

        setPersistMode(0)
        XCTAssertTrue(config.shouldPersistGeofenceRecords(), "mode `all` must persist")
    }

    /// Mode 1 = location only. Documented as "persist only location records",
    /// it persisted the geofence records it excludes by name.
    func testModeLocationSkipsGeofenceRecords() {
        setPersistMode(1)
        XCTAssertFalse(
            config.shouldPersistGeofenceRecords(),
            "mode `location` must not persist geofence rows"
        )
    }

    /// Mode 2 = geofence only: the one mode that exists to keep these rows.
    func testModeGeofencePersistsGeofenceRecords() {
        setPersistMode(2)
        XCTAssertTrue(
            config.shouldPersistGeofenceRecords(),
            "mode `geofence` must persist geofence rows"
        )
    }

    /// Mode 3 = none. The privacy-relevant half of #383.
    func testModeNoneSkipsGeofenceRecords() {
        setPersistMode(3)
        XCTAssertFalse(
            config.shouldPersistGeofenceRecords(),
            "mode `none` must not persist geofence rows"
        )
    }

    /// The predicate reads config live, so a `setConfig` mid-session takes effect
    /// on the next transition rather than being latched at SDK setup.
    func testModeChangeTakesEffectImmediately() {
        setPersistMode(0)
        XCTAssertTrue(config.shouldPersistGeofenceRecords())

        setPersistMode(3)
        XCTAssertFalse(
            config.shouldPersistGeofenceRecords(),
            "switching to `none` must stop new geofence rows"
        )

        setPersistMode(2)
        XCTAssertTrue(
            config.shouldPersistGeofenceRecords(),
            "switching back to `geofence` must resume them"
        )
    }

    /// An out-of-range mode must not silently disable persistence — the enum has
    /// four values today, and an unknown one falls back to the `all` default the
    /// rest of the config layer uses.
    func testUnknownModeFallsBackToPersisting() {
        setPersistMode(99)
        XCTAssertTrue(
            config.shouldPersistGeofenceRecords(),
            "unknown mode must fall back to persisting, not to silent data loss"
        )
    }
}
