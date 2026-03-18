import XCTest
@testable import tracelet_ios
import CoreLocation

/// Unit tests for `LocationEngine.isGpsFix(_:)` — the GPS-quality heuristic
/// that determines whether a location fix should reset the dead reckoning
/// activation timer.
final class LocationEngineGpsFixTests: XCTestCase {

    // MARK: - Helper

    private func buildLocation(
        accuracy: Double,
        lat: Double = 37.7749,
        lng: Double = -122.4194
    ) -> CLLocation {
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: -1,
            timestamp: Date()
        )
    }

    // MARK: - GPS-quality fixes (should return true)

    func testIsGpsFix_highAccuracy_returnsTrue() {
        let loc = buildLocation(accuracy: 5.0)
        XCTAssertTrue(LocationEngine.isGpsFix(loc))
    }

    func testIsGpsFix_mediumAccuracy_returnsTrue() {
        let loc = buildLocation(accuracy: 30.0)
        XCTAssertTrue(LocationEngine.isGpsFix(loc))
    }

    func testIsGpsFix_atThreshold_returnsTrue() {
        let loc = buildLocation(accuracy: 50.0)
        XCTAssertTrue(LocationEngine.isGpsFix(loc))
    }

    func testIsGpsFix_justBelowThreshold_returnsTrue() {
        let loc = buildLocation(accuracy: 49.9)
        XCTAssertTrue(LocationEngine.isGpsFix(loc))
    }

    // MARK: - Network/cell fixes (should return false)

    func testIsGpsFix_aboveThreshold_returnsFalse() {
        let loc = buildLocation(accuracy: 51.0)
        XCTAssertFalse(LocationEngine.isGpsFix(loc))
    }

    func testIsGpsFix_justAboveThreshold_returnsFalse() {
        let loc = buildLocation(accuracy: 50.1)
        XCTAssertFalse(LocationEngine.isGpsFix(loc))
    }

    func testIsGpsFix_networkAccuracy_returnsFalse() {
        let loc = buildLocation(accuracy: 150.0)
        XCTAssertFalse(LocationEngine.isGpsFix(loc))
    }

    func testIsGpsFix_cellTowerAccuracy_returnsFalse() {
        let loc = buildLocation(accuracy: 1500.0)
        XCTAssertFalse(LocationEngine.isGpsFix(loc))
    }

    // MARK: - Invalid accuracy (should return false)

    func testIsGpsFix_negativeAccuracy_returnsFalse() {
        // CLLocation uses negative accuracy to indicate invalid
        let loc = buildLocation(accuracy: -1.0)
        XCTAssertFalse(LocationEngine.isGpsFix(loc))
    }

    func testIsGpsFix_zeroAccuracy_returnsFalse() {
        // Zero accuracy is technically exact, but not a valid GPS fix
        let loc = buildLocation(accuracy: 0.0)
        XCTAssertFalse(LocationEngine.isGpsFix(loc))
    }

    // MARK: - Threshold constant

    func testGpsAccuracyThreshold_isCorrect() {
        XCTAssertEqual(LocationEngine.gpsAccuracyThreshold, 50.0)
    }
}
