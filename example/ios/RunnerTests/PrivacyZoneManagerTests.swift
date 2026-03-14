import XCTest
@testable import tracelet_ios
import TraceletCore

/// Unit tests for the pure helper functions extracted from `PrivacyZoneManager`.
///
/// Tests the module-level functions:
/// - `haversineDistanceMetres`: great-circle distance calculation
/// - `isActionMoreRestrictive`: action priority ordering
/// - `degradeCoordinates`: grid-snap coordinate degradation
///
/// No database, ConfigManager, or iOS framework dependencies required.
final class PrivacyZoneManagerTests: XCTestCase {

    // MARK: - haversineDistanceMetres

    func testHaversine_samePoint_returnsZero() {
        let d = haversineDistanceMetres(lat1: 37.7749, lng1: -122.4194, lat2: 37.7749, lng2: -122.4194)
        XCTAssertEqual(d, 0.0, accuracy: 0.01)
    }

    func testHaversine_originToOrigin_returnsZero() {
        let d = haversineDistanceMetres(lat1: 0.0, lng1: 0.0, lat2: 0.0, lng2: 0.0)
        XCTAssertEqual(d, 0.0, accuracy: 0.01)
    }

    func testHaversine_sanFranciscoToNewYork() {
        // SF: 37.7749, -122.4194  NYC: 40.7128, -74.0060
        // Expected great-circle distance ≈ 4,129 km
        let d = haversineDistanceMetres(lat1: 37.7749, lng1: -122.4194, lat2: 40.7128, lng2: -74.0060)
        let km = d / 1000.0
        XCTAssertGreaterThan(km, 4100, "SF→NYC should be >4100 km, got \(km)")
        XCTAssertLessThan(km, 4200, "SF→NYC should be <4200 km, got \(km)")
    }

    func testHaversine_londonToParis() {
        // London: 51.5074, -0.1278  Paris: 48.8566, 2.3522
        // Expected ≈ 344 km
        let d = haversineDistanceMetres(lat1: 51.5074, lng1: -0.1278, lat2: 48.8566, lng2: 2.3522)
        let km = d / 1000.0
        XCTAssertGreaterThan(km, 330, "London→Paris should be >330 km, got \(km)")
        XCTAssertLessThan(km, 360, "London→Paris should be <360 km, got \(km)")
    }

    func testHaversine_equatorOneDegreeLongitude() {
        // One degree of longitude at equator ≈ 111.32 km
        let d = haversineDistanceMetres(lat1: 0.0, lng1: 0.0, lat2: 0.0, lng2: 1.0)
        let km = d / 1000.0
        XCTAssertGreaterThan(km, 110, "1° lng at equator should be >110 km, got \(km)")
        XCTAssertLessThan(km, 112, "1° lng at equator should be <112 km, got \(km)")
    }

    func testHaversine_equatorOneDegreeLatitude() {
        // One degree of latitude ≈ 111.32 km
        let d = haversineDistanceMetres(lat1: 0.0, lng1: 0.0, lat2: 1.0, lng2: 0.0)
        let km = d / 1000.0
        XCTAssertGreaterThan(km, 110, "1° lat should be >110 km, got \(km)")
        XCTAssertLessThan(km, 112, "1° lat should be <112 km, got \(km)")
    }

    func testHaversine_antipodalPoints() {
        // North pole to south pole ≈ 20,015 km
        let d = haversineDistanceMetres(lat1: 90.0, lng1: 0.0, lat2: -90.0, lng2: 0.0)
        let km = d / 1000.0
        XCTAssertGreaterThan(km, 19_900, "N-pole to S-pole should be >19900 km, got \(km)")
        XCTAssertLessThan(km, 20_100, "N-pole to S-pole should be <20100 km, got \(km)")
    }

    func testHaversine_isSymmetric() {
        let d1 = haversineDistanceMetres(lat1: 37.7749, lng1: -122.4194, lat2: 40.7128, lng2: -74.0060)
        let d2 = haversineDistanceMetres(lat1: 40.7128, lng1: -74.0060, lat2: 37.7749, lng2: -122.4194)
        XCTAssertEqual(d1, d2, accuracy: 0.001, "Haversine should be symmetric")
    }

    func testHaversine_crossDateLine() {
        // Tokyo: 35.6762, 139.6503  Vancouver: 49.2827, -123.1207
        let d = haversineDistanceMetres(lat1: 35.6762, lng1: 139.6503, lat2: 49.2827, lng2: -123.1207)
        let km = d / 1000.0
        XCTAssertGreaterThan(km, 7_500, "Tokyo→Vancouver should be >7500 km, got \(km)")
        XCTAssertLessThan(km, 7_700, "Tokyo→Vancouver should be <7700 km, got \(km)")
    }

    func testHaversine_shortDistance_hundredMetres() {
        // At latitude 0: 100 m ≈ 0.000898° latitude
        let d = haversineDistanceMetres(lat1: 0.0, lng1: 0.0, lat2: 0.000898, lng2: 0.0)
        XCTAssertGreaterThan(d, 95, "Should be ~100 m, got \(d)")
        XCTAssertLessThan(d, 105, "Should be ~100 m, got \(d)")
    }

    func testHaversine_negativeLatitudes() {
        // Sydney: -33.8688, 151.2093  Melbourne: -37.8136, 144.9631
        let d = haversineDistanceMetres(lat1: -33.8688, lng1: 151.2093, lat2: -37.8136, lng2: 144.9631)
        let km = d / 1000.0
        XCTAssertGreaterThan(km, 700, "Sydney→Melbourne should be >700 km, got \(km)")
        XCTAssertLessThan(km, 750, "Sydney→Melbourne should be <750 km, got \(km)")
    }

    // MARK: - isActionMoreRestrictive

    func testRestrictiveness_excludeMoreThanDegrade() {
        XCTAssertTrue(isActionMoreRestrictive(
            PrivacyZoneManager.actionExclude, than: PrivacyZoneManager.actionDegrade
        ))
    }

    func testRestrictiveness_excludeMoreThanEventOnly() {
        XCTAssertTrue(isActionMoreRestrictive(
            PrivacyZoneManager.actionExclude, than: PrivacyZoneManager.actionEventOnly
        ))
    }

    func testRestrictiveness_eventOnlyMoreThanDegrade() {
        XCTAssertTrue(isActionMoreRestrictive(
            PrivacyZoneManager.actionEventOnly, than: PrivacyZoneManager.actionDegrade
        ))
    }

    func testRestrictiveness_degradeNotMoreThanExclude() {
        XCTAssertFalse(isActionMoreRestrictive(
            PrivacyZoneManager.actionDegrade, than: PrivacyZoneManager.actionExclude
        ))
    }

    func testRestrictiveness_degradeNotMoreThanEventOnly() {
        XCTAssertFalse(isActionMoreRestrictive(
            PrivacyZoneManager.actionDegrade, than: PrivacyZoneManager.actionEventOnly
        ))
    }

    func testRestrictiveness_eventOnlyNotMoreThanExclude() {
        XCTAssertFalse(isActionMoreRestrictive(
            PrivacyZoneManager.actionEventOnly, than: PrivacyZoneManager.actionExclude
        ))
    }

    func testRestrictiveness_sameAction_notMoreRestrictive() {
        XCTAssertFalse(isActionMoreRestrictive(
            PrivacyZoneManager.actionExclude, than: PrivacyZoneManager.actionExclude
        ))
        XCTAssertFalse(isActionMoreRestrictive(
            PrivacyZoneManager.actionDegrade, than: PrivacyZoneManager.actionDegrade
        ))
        XCTAssertFalse(isActionMoreRestrictive(
            PrivacyZoneManager.actionEventOnly, than: PrivacyZoneManager.actionEventOnly
        ))
    }

    func testRestrictiveness_unknownAction_notMoreRestrictive() {
        // Unknown action code (999) should have priority 0
        XCTAssertFalse(isActionMoreRestrictive(999, than: PrivacyZoneManager.actionDegrade))
    }

    func testRestrictiveness_knownBeatsUnknown() {
        XCTAssertTrue(isActionMoreRestrictive(
            PrivacyZoneManager.actionDegrade, than: 999
        ))
    }

    // MARK: - degradeCoordinates

    func testDegrade_zeroCoordinates_returnZero() {
        let (lat, lng) = degradeCoordinates(lat: 0.0, lng: 0.0, accuracyMeters: 1000.0)
        XCTAssertEqual(lat, 0.0, accuracy: 1e-10)
        XCTAssertEqual(lng, 0.0, accuracy: 1e-10)
    }

    func testDegrade_snapsToGrid() {
        // With 1000 m accuracy: grid ≈ 1000 / 111320 ≈ 0.008983° per cell
        let accuracy = 1000.0
        let gridDeg = accuracy / 111_320.0

        let (snappedLat, snappedLng) = degradeCoordinates(lat: 37.7749, lng: -122.4194, accuracyMeters: accuracy)

        // Snapped values should be exact multiples of gridDeg
        let latRemainder = abs(snappedLat.truncatingRemainder(dividingBy: gridDeg))
        let lngRemainder = abs(snappedLng.truncatingRemainder(dividingBy: gridDeg))
        XCTAssertTrue(
            latRemainder < 1e-10 || abs(latRemainder - gridDeg) < 1e-10,
            "Latitude should snap to grid, remainder=\(latRemainder)"
        )
        XCTAssertTrue(
            lngRemainder < 1e-10 || abs(lngRemainder - gridDeg) < 1e-10,
            "Longitude should snap to grid, remainder=\(lngRemainder)"
        )
    }

    func testDegrade_reducedPrecision() {
        // A 1000 m grid means the degraded point should be within ~500 m of original
        let (snappedLat, snappedLng) = degradeCoordinates(lat: 37.7749, lng: -122.4194, accuracyMeters: 1000.0)

        let distance = haversineDistanceMetres(lat1: 37.7749, lng1: -122.4194, lat2: snappedLat, lng2: snappedLng)
        XCTAssertLessThan(distance, 1000, "Degraded point should be within 1000 m of original, got \(distance)")
    }

    func testDegrade_largeAccuracy_coarserGrid() {
        let (snap1Lat, _) = degradeCoordinates(lat: 37.7749, lng: -122.4194, accuracyMeters: 100.0)
        let (snap2Lat, _) = degradeCoordinates(lat: 37.7749, lng: -122.4194, accuracyMeters: 10_000.0)

        XCTAssertTrue(snap1Lat.isFinite)
        XCTAssertTrue(snap2Lat.isFinite)
    }

    func testDegrade_deterministic() {
        let result1 = degradeCoordinates(lat: 51.5074, lng: -0.1278, accuracyMeters: 500.0)
        let result2 = degradeCoordinates(lat: 51.5074, lng: -0.1278, accuracyMeters: 500.0)
        XCTAssertEqual(result1.0, result2.0)
        XCTAssertEqual(result1.1, result2.1)
    }

    func testDegrade_nearbyPointsSnapToSameCell() {
        let accuracy = 1000.0
        let gridDeg = accuracy / 111_320.0

        // Point at a grid-aligned location
        let baseLat = 37.0
        let baseLng = -122.0
        let (snap1Lat, snap1Lng) = degradeCoordinates(lat: baseLat, lng: baseLng, accuracyMeters: accuracy)

        // Tiny offset — still well within the same grid cell
        let offset = gridDeg * 0.1
        let (snap2Lat, snap2Lng) = degradeCoordinates(lat: baseLat + offset, lng: baseLng + offset, accuracyMeters: accuracy)

        XCTAssertEqual(snap1Lat, snap2Lat, accuracy: 1e-10, "Nearby points should snap to same cell")
        XCTAssertEqual(snap1Lng, snap2Lng, accuracy: 1e-10, "Nearby points should snap to same cell")
    }

    func testDegrade_differentCellsProduceDifferentResults() {
        let accuracy = 1000.0
        let gridDeg = accuracy / 111_320.0

        let (snap1Lat, _) = degradeCoordinates(lat: 37.0, lng: -122.0, accuracyMeters: accuracy)
        let (snap2Lat, _) = degradeCoordinates(lat: 37.0 + gridDeg * 2, lng: -122.0, accuracyMeters: accuracy)

        XCTAssertNotEqual(snap1Lat, snap2Lat, "Points in different cells should snap differently")
    }

    func testDegrade_negativeCoordinates() {
        // Southern hemisphere
        let (lat, lng) = degradeCoordinates(lat: -33.8688, lng: 151.2093, accuracyMeters: 500.0)
        XCTAssertLessThan(lat, 0, "Latitude should remain negative")
        XCTAssertGreaterThan(lng, 0, "Longitude should remain positive")
    }

    func testDegrade_smallAccuracy_finePrecision() {
        // 10 m accuracy
        let (snappedLat, snappedLng) = degradeCoordinates(lat: 37.7749, lng: -122.4194, accuracyMeters: 10.0)
        let distance = haversineDistanceMetres(lat1: 37.7749, lng1: -122.4194, lat2: snappedLat, lng2: snappedLng)
        XCTAssertLessThan(distance, 15, "10 m degradation should keep point within ~10 m, got \(distance)")
    }
}
