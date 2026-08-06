import XCTest
@testable import TraceletSDK

/// Regression tests for the nested `filter` block reaching the flat config cache
/// (#303).
///
/// Every transport serialises `LocationFilter` as a sub-map nested inside `geo`:
/// the Pigeon bridge, `TraceletConfig.toMap()`, its Obj-C twin, and remote-config
/// JSON. `setConfig` flattened `geo` one level and then stored the block
/// underneath it as a single opaque `cache["filter"]` value, while every getter
/// read a flat top-level key — so the whole filter section was accepted,
/// persisted, and read by nothing. On iOS `trackingAccuracyThreshold`,
/// `odometerAccuracyThreshold` and `maxImpliedSpeed` were therefore pinned to
/// 100 / 0 / 80 regardless of configuration, and #303's own change detection
/// compared key names absent from both snapshots, so a filter change triggered
/// neither the processor rebuild nor `setBaseTuning`.
///
/// These tests exercise the real wire shape rather than the flat keys the older
/// unit tests used, which is why the bug survived a green suite.
final class ConfigManagerFilterSectionTests: XCTestCase {

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

    /// The shape the Pigeon bridge actually sends: `filter` nested inside `geo`.
    func testNestedFilterSectionReachesTheFlatGetters() {
        _ = config.setConfig([
            "geo": [
                "distanceFilter": 12,
                "filter": [
                    "trackingAccuracyThreshold": 30,
                    "odometerAccuracyThreshold": 15,
                    "maxImpliedSpeed": 25,
                    "rejectMockLocations": true,
                    "mockDetectionLevel": 2,
                    "useKalmanFilter": true,
                    "policy": 2,
                ],
            ],
        ])

        XCTAssertEqual(config.getTrackingAccuracyThreshold(), 30)
        XCTAssertEqual(config.getOdometerAccuracyThreshold(), 15)
        XCTAssertEqual(config.getMaxImpliedSpeed(), 25)
        XCTAssertTrue(config.getRejectMockLocations())
        XCTAssertEqual(config.getMockDetectionLevel(), 2)
        XCTAssertTrue(config.getEnableKalmanFilter())
        // `policy` on the wire, `filterPolicy` everywhere it is read.
        XCTAssertEqual(config.getFilterPolicy(), 2)
    }

    /// The native Swift API hands the same nested block over at the top level
    /// (`TraceletConfig.toMap()` is already flat apart from `filter`).
    func testTopLevelFilterSectionIsLiftedToo() {
        _ = config.setConfig([
            "filter": [
                "trackingAccuracyThreshold": 45,
                "odometerAccuracyThreshold": 22,
                "maxImpliedSpeed": 33,
            ],
        ])

        XCTAssertEqual(config.getTrackingAccuracyThreshold(), 45)
        XCTAssertEqual(config.getOdometerAccuracyThreshold(), 22)
        XCTAssertEqual(config.getMaxImpliedSpeed(), 33)
    }

    /// The lifted values must land in the merged cache the change detection in
    /// `TraceletSdk.setConfig` diffs — it compares `getConfig()` snapshots by key
    /// name, so a value reachable only through a getter would still fire nothing.
    func testLiftedKeysAppearInTheMergedConfigUnderTheirFlatNames() {
        let merged = config.setConfig([
            "geo": ["filter": ["trackingAccuracyThreshold": 30, "policy": 1]],
        ])

        XCTAssertEqual((merged["trackingAccuracyThreshold"] as? NSNumber)?.intValue, 30)
        XCTAssertEqual((merged["filterPolicy"] as? NSNumber)?.intValue, 1)
        XCTAssertNil(merged["filter"], "the nested copy must not survive alongside the lifted keys")
        XCTAssertNil(merged["policy"], "the wire name must not linger under a key nothing reads")
    }

    /// A partial `setConfig` must not reset the rest of the filter — the cache
    /// merges, and the NSNull guard that protects every other key has to apply to
    /// the lifted ones as well.
    func testPartialFilterUpdateKeepsPreviouslyConfiguredValues() {
        _ = config.setConfig([
            "geo": [
                "filter": [
                    "trackingAccuracyThreshold": 30,
                    "odometerAccuracyThreshold": 15,
                    "maxImpliedSpeed": 25,
                ],
            ],
        ])
        _ = config.setConfig([
            "geo": [
                "filter": [
                    "trackingAccuracyThreshold": 45,
                    "odometerAccuracyThreshold": NSNull(),
                ],
            ],
        ])

        XCTAssertEqual(config.getTrackingAccuracyThreshold(), 45)
        XCTAssertEqual(config.getOdometerAccuracyThreshold(), 15, "NSNull must not overwrite")
        XCTAssertEqual(config.getMaxImpliedSpeed(), 25, "an omitted key must not be reset")
    }

    /// A flat key passed in the same call wins over the nested block, matching
    /// the order Android applies the two in.
    func testExplicitFlatKeyWinsOverTheNestedBlock() {
        _ = config.setConfig([
            "trackingAccuracyThreshold": 70,
            "geo": ["filter": ["trackingAccuracyThreshold": 30]],
        ])

        XCTAssertEqual(config.getTrackingAccuracyThreshold(), 70)
    }

    /// A cache persisted by a build that stored the block nested must be lifted
    /// on load: `autoResumeTracking()` starts the pipeline straight off it with no
    /// `ready()` in between, so a relaunch would otherwise run on the defaults.
    func testCachePersistedInTheNestedShapeIsLiftedOnLoad() {
        let stale: [String: Any] = [
            "distanceFilter": 12.0,
            "filter": [
                "trackingAccuracyThreshold": 45,
                "odometerAccuracyThreshold": 22,
                "maxImpliedSpeed": 33,
                "policy": 2,
            ],
        ]
        UserDefaults.standard.set(
            try! JSONSerialization.data(withJSONObject: stale),
            forKey: "com.tracelet.config"
        )

        let reloaded = ConfigManager()

        XCTAssertEqual(reloaded.getTrackingAccuracyThreshold(), 45)
        XCTAssertEqual(reloaded.getOdometerAccuracyThreshold(), 22)
        XCTAssertEqual(reloaded.getMaxImpliedSpeed(), 33)
        XCTAssertEqual(reloaded.getFilterPolicy(), 2)

        reloaded.reset(nil)
    }
}
