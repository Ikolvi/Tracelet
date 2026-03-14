import XCTest
@testable import tracelet_ios
import TraceletCore

/// Unit tests for `ConfigManager` privacy zone getters.
///
/// Tests defaults, values set via nested `"privacyZone"` section,
/// flat keys, non-collision with audit `"enabled"` key, and reset.
///
/// Uses the public `setConfig` / `reset` API to populate the in-memory cache
/// without requiring mocks.
final class ConfigManagerPrivacyZoneTests: XCTestCase {

    /// Creates a fresh `ConfigManager` with optional initial values.
    private func createConfig(_ initialValues: [String: Any] = [:]) -> ConfigManager {
        let config = ConfigManager()
        // Clear any state from previous test runs
        config.reset(nil)
        if !initialValues.isEmpty {
            _ = config.setConfig(initialValues)
        }
        return config
    }

    // MARK: - Default values

    func testPrivacyZoneEnabled_defaultIsFalse() {
        XCTAssertEqual(createConfig().getPrivacyZoneEnabled(), false)
    }

    // MARK: - Nested "privacyZone" section

    func testPrivacyZoneEnabled_setToTrue_viaNestedSection() {
        let config = createConfig([
            "privacyZone": ["privacyZoneEnabled": true]
        ])
        XCTAssertTrue(config.getPrivacyZoneEnabled())
    }

    func testPrivacyZoneEnabled_setToFalse_viaNestedSection() {
        let config = createConfig([
            "privacyZone": ["privacyZoneEnabled": false]
        ])
        XCTAssertFalse(config.getPrivacyZoneEnabled())
    }

    // MARK: - Flat key

    func testPrivacyZoneEnabled_flatKeyWorks() {
        let config = createConfig([
            "privacyZoneEnabled": true
        ])
        XCTAssertTrue(config.getPrivacyZoneEnabled())
    }

    // MARK: - Non-collision with audit "enabled"

    func testPrivacyZoneEnabled_doesNotCollideWithAuditEnabled() {
        let config = createConfig([
            "audit": ["enabled": true],
            "privacyZone": ["privacyZoneEnabled": false],
        ])
        XCTAssertTrue(config.getAuditEnabled(), "audit.enabled should be true")
        XCTAssertFalse(config.getPrivacyZoneEnabled(), "privacyZoneEnabled should be false")
    }

    func testAuditEnabled_doesNotAffectPrivacyZone() {
        let config = createConfig([
            "audit": ["enabled": true]
        ])
        XCTAssertTrue(config.getAuditEnabled())
        XCTAssertFalse(config.getPrivacyZoneEnabled(), "privacyZoneEnabled should still default to false")
    }

    func testPrivacyZoneEnabled_doesNotAffectAudit() {
        let config = createConfig([
            "privacyZone": ["privacyZoneEnabled": true]
        ])
        XCTAssertFalse(config.getAuditEnabled(), "audit.enabled should still default to false")
        XCTAssertTrue(config.getPrivacyZoneEnabled())
    }

    // MARK: - Reset

    func testReset_clearsPrivacyZoneConfigToDefaults() {
        let config = createConfig([
            "privacyZone": ["privacyZoneEnabled": true]
        ])
        XCTAssertTrue(config.getPrivacyZoneEnabled())

        config.reset(nil)

        XCTAssertFalse(config.getPrivacyZoneEnabled())
    }

    func testReset_clearsPrivacyZoneWithoutAffectingSubsequentSets() {
        let config = createConfig([
            "privacyZone": ["privacyZoneEnabled": true]
        ])
        XCTAssertTrue(config.getPrivacyZoneEnabled())

        config.reset(nil)
        XCTAssertFalse(config.getPrivacyZoneEnabled())

        // Setting again should work
        _ = config.setConfig(["privacyZoneEnabled": true])
        XCTAssertTrue(config.getPrivacyZoneEnabled())
    }
}
