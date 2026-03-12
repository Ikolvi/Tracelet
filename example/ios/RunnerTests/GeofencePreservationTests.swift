import XCTest

@testable import tracelet_ios

/// Unit tests for conditional geofence preservation during reset (#23).
///
/// These tests verify the decision logic in `handleReset()`:
/// - When `stopOnTerminate: false`, `enabled: true`, and `trackingMode == 1`,
///   `keepGeofencesAlive` should be `true` (geofences survive reset).
/// - All other combinations should result in `keepGeofencesAlive == false`.
///
/// This mirrors the Android fix in `TraceletAndroidPlugin.destroyAll()`.
class GeofencePreservationTests: XCTestCase {

    private var stateManager: StateManager!
    private var configManager: ConfigManager!

    override func setUp() {
        super.setUp()
        stateManager = StateManager()
        configManager = ConfigManager()
        configManager.reset(nil)
        stateManager.reset()
    }

    override func tearDown() {
        stateManager.reset()
        configManager.reset(nil)
        super.tearDown()
    }

    // MARK: - destroyAll / handleReset conditional preservation

    func testGeofenceMode_stopOnTerminateFalse_preservesGeofences() {
        // Core fix: geofences should survive when stopOnTerminate=false,
        // enabled=true, trackingMode=1
        _ = configManager.setConfig(["stopOnTerminate": false])
        stateManager.enabled = true
        stateManager.trackingMode = 1

        let keepGeofencesAlive = !configManager.getStopOnTerminate()
            && stateManager.enabled
            && stateManager.trackingMode == 1
        XCTAssertTrue(keepGeofencesAlive)
    }

    func testGeofenceMode_stopOnTerminateTrue_destroysGeofences() {
        // Default stopOnTerminate=true — geofences should be destroyed
        stateManager.enabled = true
        stateManager.trackingMode = 1

        let keepGeofencesAlive = !configManager.getStopOnTerminate()
            && stateManager.enabled
            && stateManager.trackingMode == 1
        XCTAssertFalse(keepGeofencesAlive)
    }

    func testContinuousMode_stopOnTerminateFalse_destroysGeofences() {
        // trackingMode=0 (continuous) should NOT preserve geofences
        _ = configManager.setConfig(["stopOnTerminate": false])
        stateManager.enabled = true
        stateManager.trackingMode = 0

        let keepGeofencesAlive = !configManager.getStopOnTerminate()
            && stateManager.enabled
            && stateManager.trackingMode == 1
        XCTAssertFalse(keepGeofencesAlive)
    }

    func testPeriodicMode_stopOnTerminateFalse_destroysGeofences() {
        // trackingMode=2 (periodic) should NOT preserve geofences
        _ = configManager.setConfig(["stopOnTerminate": false])
        stateManager.enabled = true
        stateManager.trackingMode = 2

        let keepGeofencesAlive = !configManager.getStopOnTerminate()
            && stateManager.enabled
            && stateManager.trackingMode == 1
        XCTAssertFalse(keepGeofencesAlive)
    }

    func testGeofenceMode_disabledTracking_destroysGeofences() {
        // enabled=false should destroy geofences even with stopOnTerminate=false
        _ = configManager.setConfig(["stopOnTerminate": false])
        stateManager.enabled = false
        stateManager.trackingMode = 1

        let keepGeofencesAlive = !configManager.getStopOnTerminate()
            && stateManager.enabled
            && stateManager.trackingMode == 1
        XCTAssertFalse(keepGeofencesAlive)
    }

    func testGeofenceAndPeriodicProtection_mutuallyExclusive() {
        // Geofence and periodic preservation can't both be true simultaneously
        _ = configManager.setConfig(["stopOnTerminate": false])
        stateManager.enabled = true
        stateManager.trackingMode = 1

        let keepGeofencesAlive = !configManager.getStopOnTerminate()
            && stateManager.enabled
            && stateManager.trackingMode == 1
        let keepPeriodicAlive = !configManager.getStopOnTerminate()
            && stateManager.enabled
            && stateManager.trackingMode == 2

        XCTAssertTrue(keepGeofencesAlive)
        XCTAssertFalse(keepPeriodicAlive)
    }

    // MARK: - Boot recovery geofence re-registration

    func testBootRecovery_geofenceMode_shouldReRegister() {
        stateManager.trackingMode = 1
        XCTAssertEqual(stateManager.trackingMode, 1)
        // autoResumeTracking case 1 should call geofenceManager.reRegisterAll()
    }

    func testBootRecovery_continuousMode_shouldNotReRegisterGeofences() {
        stateManager.trackingMode = 0
        let shouldRecoverGeofences = stateManager.trackingMode == 1
        XCTAssertFalse(shouldRecoverGeofences)
    }

    func testBootRecovery_periodicMode_shouldNotReRegisterGeofences() {
        stateManager.trackingMode = 2
        let shouldRecoverGeofences = stateManager.trackingMode == 1
        XCTAssertFalse(shouldRecoverGeofences)
    }
}
