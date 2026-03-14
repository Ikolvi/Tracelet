import XCTest
@testable import tracelet_ios
import TraceletCore

/// Unit tests for `ConfigManager` HTTP-related getters.
///
/// Validates the fixes for:
/// - `getHttpMethod()` — correctly maps Int (0 = POST, 1 = PUT) from Dart
/// - `getHttpHeaders()` — handles both `[String: String]` and `[String: Any]`
/// - `getMaxBatchSize()` — defaults to 250 (matching Dart & Android)
///
/// Uses the public `setConfig` / `reset` API to populate the in-memory
/// cache without requiring mocks.
final class ConfigManagerHttpTests: XCTestCase {

    /// Creates a fresh `ConfigManager` with optional initial values.
    private func createConfig(_ initialValues: [String: Any] = [:]) -> ConfigManager {
        let config = ConfigManager()
        config.reset(nil)
        if !initialValues.isEmpty {
            _ = config.setConfig(initialValues)
        }
        return config
    }

    // MARK: - getHttpMethod()

    func testGetHttpMethod_defaultsToPost() {
        let config = createConfig()
        XCTAssertEqual(config.getHttpMethod(), "POST")
    }

    func testGetHttpMethod_intZeroReturnsPost() {
        // Dart serializes HttpMethod.post as 0
        let config = createConfig(["http": ["method": 0]])
        XCTAssertEqual(config.getHttpMethod(), "POST")
    }

    func testGetHttpMethod_intOneReturnsPut() {
        // Dart serializes HttpMethod.put as 1
        let config = createConfig(["http": ["method": 1]])
        XCTAssertEqual(config.getHttpMethod(), "PUT")
    }

    func testGetHttpMethod_unknownIntDefaultsToPost() {
        let config = createConfig(["http": ["method": 99]])
        XCTAssertEqual(config.getHttpMethod(), "POST")
    }

    func testGetHttpMethod_stringFallbackStillWorks() {
        // Legacy: if a string is somehow in the cache, it should still work
        let config = createConfig(["http": ["method": "PUT"]])
        XCTAssertEqual(config.getHttpMethod(), "PUT")
    }

    // MARK: - getHttpHeaders()

    func testGetHttpHeaders_defaultsToEmpty() {
        let config = createConfig()
        XCTAssertTrue(config.getHttpHeaders().isEmpty)
    }

    func testGetHttpHeaders_stringStringMap() {
        let config = createConfig([
            "http": ["headers": ["x-api-key": "abc", "x-account-id": "123"]]
        ])
        let headers = config.getHttpHeaders()
        XCTAssertEqual(headers["x-api-key"], "abc")
        XCTAssertEqual(headers["x-account-id"], "123")
    }

    func testGetHttpHeaders_stringAnyMap_coercesToStrings() {
        // Platform channel may deliver header values as Any (e.g. Int, Bool)
        let config = createConfig([
            "http": ["headers": ["x-version": 42, "x-debug": true] as [String: Any]]
        ])
        let headers = config.getHttpHeaders()
        XCTAssertEqual(headers["x-version"], "42")
        XCTAssertEqual(headers["x-debug"], "true")
    }

    // MARK: - getMaxBatchSize()

    func testGetMaxBatchSize_defaultsTo250() {
        let config = createConfig()
        XCTAssertEqual(config.getMaxBatchSize(), 250)
    }

    func testGetMaxBatchSize_customValue() {
        let config = createConfig(["http": ["maxBatchSize": 500]])
        XCTAssertEqual(config.getMaxBatchSize(), 500)
    }

    // MARK: - getUrl()

    func testGetUrl_defaultsToEmpty() {
        let config = createConfig()
        XCTAssertEqual(config.getUrl(), "")
    }

    func testGetUrl_customValue() {
        let config = createConfig(["http": ["url": "https://example.com/api"]])
        XCTAssertEqual(config.getUrl(), "https://example.com/api")
    }

    // MARK: - getAutoSync()

    func testGetAutoSync_defaultsToTrue() {
        let config = createConfig()
        XCTAssertTrue(config.getAutoSync())
    }

    func testGetAutoSync_disabledWhenFalse() {
        let config = createConfig(["http": ["autoSync": false]])
        XCTAssertFalse(config.getAutoSync())
    }
}
