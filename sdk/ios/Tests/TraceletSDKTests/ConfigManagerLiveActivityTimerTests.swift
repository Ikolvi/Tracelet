import XCTest

@testable import TraceletSDK

final class ConfigManagerLiveActivityTimerTests: XCTestCase {
    private var config: ConfigManager!

    override func setUp() {
        super.setUp()
        config = ConfigManager()
        config.reset(nil)
    }

    func testMissingTimerKeysDefaultOff() {
        _ = config.setConfig([
            "liveActivityConfig": [
                "title": "Tracking",
                "body": "Moving",
            ],
        ])

        let live = config.getLiveActivityConfig()
        XCTAssertNotNil(live)
        XCTAssertNil(live?.startedAt)
        XCTAssertFalse(live?.showTimer ?? true)
    }

    func testEpochMillisecondsConvertExactlyToDate() {
        let milliseconds: Int64 = 4_294_967_296
        _ = config.setConfig([
            "liveActivityConfig": [
                "title": "Tracking",
                "body": "Moving",
                "startedAt": milliseconds,
                "showTimer": true,
            ],
        ])

        let live = config.getLiveActivityConfig()
        XCTAssertEqual(
            live?.startedAt,
            Date(timeIntervalSince1970: Double(milliseconds) / 1000.0)
        )
        XCTAssertTrue(live?.showTimer ?? false)
    }

    func testReplacingWholeLiveActivityMapPreservesUnrelatedConfig() {
        _ = config.setConfig([
            "url": "https://example.test/locations",
            "liveActivityConfig": [
                "title": "Old",
                "body": "Old body",
                "showTimer": false,
            ],
        ])

        _ = config.setConfig([
            "liveActivityConfig": [
                "title": "New",
                "body": "New body",
                "startedAt": 1234,
                "showTimer": true,
            ],
        ])

        XCTAssertEqual(config.getUrl(), "https://example.test/locations")
        XCTAssertEqual(config.getLiveActivityConfig()?.title, "New")
        XCTAssertEqual(config.getLiveActivityConfig()?.body, "New body")
        XCTAssertTrue(config.getLiveActivityConfig()?.showTimer ?? false)
    }
}
