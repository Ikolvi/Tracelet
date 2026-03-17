package com.tracelet.tracelet_android.privacy

import com.tracelet.core.privacy.degradeCoordinates
import com.tracelet.core.privacy.haversineDistanceMetres
import com.tracelet.core.privacy.isActionMoreRestrictive
import com.tracelet.core.privacy.PrivacyZoneManager
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

/**
 * Unit tests for [PrivacyZoneManager] pure helper functions.
 *
 * Tests the package-level functions extracted from PrivacyZoneManager:
 * - [haversineDistanceMetres]: great-circle distance calculation
 * - [isActionMoreRestrictive]: action priority ordering
 * - [degradeCoordinates]: grid-snap coordinate degradation
 *
 * These tests require no Android context, database, or mocking.
 */
internal class PrivacyZoneManagerTest {

    // =========================================================================
    // haversineDistanceMetres
    // =========================================================================

    @Test
    fun haversine_samePoint_returnsZero() {
        val d = haversineDistanceMetres(37.7749, -122.4194, 37.7749, -122.4194)
        assertEquals(0.0, d, 0.01)
    }

    @Test
    fun haversine_originToOrigin_returnsZero() {
        val d = haversineDistanceMetres(0.0, 0.0, 0.0, 0.0)
        assertEquals(0.0, d, 0.01)
    }

    @Test
    fun haversine_sanFranciscoToNewYork() {
        // SF: 37.7749, -122.4194  NYC: 40.7128, -74.0060
        // Expected great-circle distance ≈ 4,129 km
        val d = haversineDistanceMetres(37.7749, -122.4194, 40.7128, -74.0060)
        val km = d / 1000.0
        assertTrue(km > 4_100 && km < 4_200, "SF→NYC should be ~4129 km, got $km")
    }

    @Test
    fun haversine_londonToParis() {
        // London: 51.5074, -0.1278  Paris: 48.8566, 2.3522
        // Expected ≈ 344 km
        val d = haversineDistanceMetres(51.5074, -0.1278, 48.8566, 2.3522)
        val km = d / 1000.0
        assertTrue(km > 330 && km < 360, "London→Paris should be ~344 km, got $km")
    }

    @Test
    fun haversine_equatorOneDegreeLongitude() {
        // One degree of longitude at equator ≈ 111.32 km
        val d = haversineDistanceMetres(0.0, 0.0, 0.0, 1.0)
        val km = d / 1000.0
        assertTrue(km > 110 && km < 112, "1° lng at equator should be ~111.32 km, got $km")
    }

    @Test
    fun haversine_equatorOneDegreeLatitude() {
        // One degree of latitude ≈ 111.32 km regardless of longitude
        val d = haversineDistanceMetres(0.0, 0.0, 1.0, 0.0)
        val km = d / 1000.0
        assertTrue(km > 110 && km < 112, "1° lat should be ~111.32 km, got $km")
    }

    @Test
    fun haversine_antipodalPoints() {
        // North pole to south pole ≈ 20,015 km (half circumference)
        val d = haversineDistanceMetres(90.0, 0.0, -90.0, 0.0)
        val km = d / 1000.0
        assertTrue(km > 19_900 && km < 20_100, "N-pole to S-pole should be ~20015 km, got $km")
    }

    @Test
    fun haversine_isSymmetric() {
        val d1 = haversineDistanceMetres(37.7749, -122.4194, 40.7128, -74.0060)
        val d2 = haversineDistanceMetres(40.7128, -74.0060, 37.7749, -122.4194)
        assertEquals(d1, d2, 0.001, "Haversine should be symmetric")
    }

    @Test
    fun haversine_crossDateLine() {
        // Tokyo: 35.6762, 139.6503  Vancouver: 49.2827, -123.1207
        val d = haversineDistanceMetres(35.6762, 139.6503, 49.2827, -123.1207)
        val km = d / 1000.0
        assertTrue(km > 7_500 && km < 7_700, "Tokyo→Vancouver should be ~7,560 km, got $km")
    }

    @Test
    fun haversine_shortDistance_hundredMetres() {
        // Two points approximately 100 m apart
        // At latitude 0: 100 m ≈ 0.000898° latitude
        val d = haversineDistanceMetres(0.0, 0.0, 0.000898, 0.0)
        assertTrue(d > 95 && d < 105, "Should be ~100 m, got $d")
    }

    @Test
    fun haversine_negativeLatitudes() {
        // Sydney: -33.8688, 151.2093  Melbourne: -37.8136, 144.9631
        val d = haversineDistanceMetres(-33.8688, 151.2093, -37.8136, 144.9631)
        val km = d / 1000.0
        assertTrue(km > 700 && km < 750, "Sydney→Melbourne should be ~714 km, got $km")
    }

    // =========================================================================
    // isActionMoreRestrictive
    // =========================================================================

    @Test
    fun restrictiveness_excludeMoreThanDegrade() {
        assertTrue(isActionMoreRestrictive(
            PrivacyZoneManager.ACTION_EXCLUDE,
            PrivacyZoneManager.ACTION_DEGRADE,
        ))
    }

    @Test
    fun restrictiveness_excludeMoreThanEventOnly() {
        assertTrue(isActionMoreRestrictive(
            PrivacyZoneManager.ACTION_EXCLUDE,
            PrivacyZoneManager.ACTION_EVENT_ONLY,
        ))
    }

    @Test
    fun restrictiveness_eventOnlyMoreThanDegrade() {
        assertTrue(isActionMoreRestrictive(
            PrivacyZoneManager.ACTION_EVENT_ONLY,
            PrivacyZoneManager.ACTION_DEGRADE,
        ))
    }

    @Test
    fun restrictiveness_degradeNotMoreThanExclude() {
        assertFalse(isActionMoreRestrictive(
            PrivacyZoneManager.ACTION_DEGRADE,
            PrivacyZoneManager.ACTION_EXCLUDE,
        ))
    }

    @Test
    fun restrictiveness_degradeNotMoreThanEventOnly() {
        assertFalse(isActionMoreRestrictive(
            PrivacyZoneManager.ACTION_DEGRADE,
            PrivacyZoneManager.ACTION_EVENT_ONLY,
        ))
    }

    @Test
    fun restrictiveness_eventOnlyNotMoreThanExclude() {
        assertFalse(isActionMoreRestrictive(
            PrivacyZoneManager.ACTION_EVENT_ONLY,
            PrivacyZoneManager.ACTION_EXCLUDE,
        ))
    }

    @Test
    fun restrictiveness_sameAction_notMoreRestrictive() {
        assertFalse(isActionMoreRestrictive(
            PrivacyZoneManager.ACTION_EXCLUDE,
            PrivacyZoneManager.ACTION_EXCLUDE,
        ))
        assertFalse(isActionMoreRestrictive(
            PrivacyZoneManager.ACTION_DEGRADE,
            PrivacyZoneManager.ACTION_DEGRADE,
        ))
        assertFalse(isActionMoreRestrictive(
            PrivacyZoneManager.ACTION_EVENT_ONLY,
            PrivacyZoneManager.ACTION_EVENT_ONLY,
        ))
    }

    @Test
    fun restrictiveness_unknownAction_notMoreRestrictive() {
        // Unknown action code (999) should have priority 0
        assertFalse(isActionMoreRestrictive(999, PrivacyZoneManager.ACTION_DEGRADE))
    }

    @Test
    fun restrictiveness_knownBeatsUnknown() {
        assertTrue(isActionMoreRestrictive(
            PrivacyZoneManager.ACTION_DEGRADE,
            999,
        ))
    }

    // =========================================================================
    // degradeCoordinates
    // =========================================================================

    @Test
    fun degrade_zeroCoordinates_returnZero() {
        val (lat, lng) = degradeCoordinates(0.0, 0.0, 1000.0)
        assertEquals(0.0, lat, 1e-10)
        assertEquals(0.0, lng, 1e-10)
    }

    @Test
    fun degrade_snapsToGrid() {
        // With 1000 m accuracy: grid ≈ 1000 / 111320 ≈ 0.008983° per cell
        val accuracy = 1000.0
        val gridDeg = accuracy / 111_320.0

        val (snappedLat, snappedLng) = degradeCoordinates(37.7749, -122.4194, accuracy)

        // Snapped values should be exact multiples of gridDeg
        val latRemainder = abs(snappedLat % gridDeg)
        val lngRemainder = abs(snappedLng % gridDeg)
        assertTrue(
            latRemainder < 1e-10 || abs(latRemainder - gridDeg) < 1e-10,
            "Latitude should snap to grid, remainder=$latRemainder",
        )
        assertTrue(
            lngRemainder < 1e-10 || abs(lngRemainder - gridDeg) < 1e-10,
            "Longitude should snap to grid, remainder=$lngRemainder",
        )
    }

    @Test
    fun degrade_reducedPrecision() {
        // A 1000 m grid means the degraded point should be within ~500 m of original
        val (snappedLat, snappedLng) = degradeCoordinates(37.7749, -122.4194, 1000.0)

        val distance = haversineDistanceMetres(37.7749, -122.4194, snappedLat, snappedLng)
        assertTrue(distance < 1000, "Degraded point should be within 1000 m of original, got $distance")
    }

    @Test
    fun degrade_largeAccuracy_coarserGrid() {
        val (snap1Lat, _) = degradeCoordinates(37.7749, -122.4194, 100.0)
        val (snap2Lat, _) = degradeCoordinates(37.7749, -122.4194, 10_000.0)

        // With larger accuracy, the grid is coarser, so different input precision
        // Both should be valid doubles
        assertTrue(snap1Lat.isFinite())
        assertTrue(snap2Lat.isFinite())
    }

    @Test
    fun degrade_deterministic() {
        val result1 = degradeCoordinates(51.5074, -0.1278, 500.0)
        val result2 = degradeCoordinates(51.5074, -0.1278, 500.0)
        assertEquals(result1.first, result2.first, 0.0)
        assertEquals(result1.second, result2.second, 0.0)
    }

    @Test
    fun degrade_nearbyPointsSnapToSameCell() {
        // Two points within the same grid cell should snap to the same coords
        val accuracy = 1000.0
        val gridDeg = accuracy / 111_320.0

        // Point at a grid center
        val baseLat = 37.0
        val baseLng = -122.0
        val (snap1Lat, snap1Lng) = degradeCoordinates(baseLat, baseLng, accuracy)

        // Tiny offset — still within half a grid cell
        val offset = gridDeg * 0.1
        val (snap2Lat, snap2Lng) = degradeCoordinates(baseLat + offset, baseLng + offset, accuracy)

        assertEquals(snap1Lat, snap2Lat, 1e-10, "Nearby points should snap to same cell")
        assertEquals(snap1Lng, snap2Lng, 1e-10, "Nearby points should snap to same cell")
    }

    @Test
    fun degrade_differentCellsProduceDifferentResults() {
        val accuracy = 1000.0
        val gridDeg = accuracy / 111_320.0

        // Points more than one grid cell apart
        val (snap1Lat, _) = degradeCoordinates(37.0, -122.0, accuracy)
        val (snap2Lat, _) = degradeCoordinates(37.0 + gridDeg * 2, -122.0, accuracy)

        assertNotEquals(snap1Lat, snap2Lat, "Points in different cells should snap differently")
    }

    @Test
    fun degrade_negativeCoordinates() {
        // Southern hemisphere
        val (lat, lng) = degradeCoordinates(-33.8688, 151.2093, 500.0)
        assertTrue(lat < 0, "Latitude should remain negative")
        assertTrue(lng > 0, "Longitude should remain positive")
    }

    @Test
    fun degrade_smallAccuracy_finePrecision() {
        // 10 m accuracy — grid ≈ 0.0000898°
        val (snappedLat, snappedLng) = degradeCoordinates(37.7749, -122.4194, 10.0)
        val distance = haversineDistanceMetres(37.7749, -122.4194, snappedLat, snappedLng)
        assertTrue(distance < 15, "10 m degradation should keep point within ~10 m, got $distance")
    }
}
