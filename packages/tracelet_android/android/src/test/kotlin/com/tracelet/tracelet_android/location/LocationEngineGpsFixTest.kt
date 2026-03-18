package com.tracelet.tracelet_android.location

import android.location.Location
import com.tracelet.core.location.LocationEngine
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Unit tests for [LocationEngine.isGpsFix] — the GPS-quality heuristic
 * that determines whether a location fix should reset the dead reckoning
 * activation timer.
 *
 * GPS-sourced fixes reset the timer; network/cell fixes do not, allowing
 * dead reckoning to activate when satellite signal is lost but network
 * positioning remains available.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
internal class LocationEngineGpsFixTest {

    // ── Helper ──────────────────────────────────────────────────────────────

    private fun buildLocation(
        provider: String,
        accuracy: Float,
        lat: Double = 37.7749,
        lng: Double = -122.4194,
    ): Location {
        return Location(provider).apply {
            latitude = lat
            longitude = lng
            this.accuracy = accuracy
            time = System.currentTimeMillis()
        }
    }

    // ── GPS provider tests ──────────────────────────────────────────────────

    @Test
    fun isGpsFix_gpsProvider_highAccuracy_returnsTrue() {
        val loc = buildLocation("gps", 5f)
        assertTrue(LocationEngine.isGpsFix(loc))
    }

    @Test
    fun isGpsFix_gpsProvider_lowAccuracy_returnsTrue() {
        // GPS provider is always trusted, even with poor accuracy
        val loc = buildLocation("gps", 200f)
        assertTrue(LocationEngine.isGpsFix(loc))
    }

    @Test
    fun isGpsFix_gpsProvider_exactThreshold_returnsTrue() {
        val loc = buildLocation("gps", 50f)
        assertTrue(LocationEngine.isGpsFix(loc))
    }

    @Test
    fun isGpsFix_gpsProvider_zeroAccuracy_returnsTrue() {
        val loc = buildLocation("gps", 0f)
        assertTrue(LocationEngine.isGpsFix(loc))
    }

    // ── Fused provider tests ────────────────────────────────────────────────

    @Test
    fun isGpsFix_fusedProvider_highAccuracy_returnsTrue() {
        val loc = buildLocation("fused", 10f)
        assertTrue(LocationEngine.isGpsFix(loc))
    }

    @Test
    fun isGpsFix_fusedProvider_atThreshold_returnsTrue() {
        val loc = buildLocation("fused", 50f)
        assertTrue(LocationEngine.isGpsFix(loc))
    }

    @Test
    fun isGpsFix_fusedProvider_aboveThreshold_returnsFalse() {
        val loc = buildLocation("fused", 51f)
        assertFalse(LocationEngine.isGpsFix(loc))
    }

    @Test
    fun isGpsFix_fusedProvider_networkAccuracy_returnsFalse() {
        // Typical network/cell accuracy: 100–2000m
        val loc = buildLocation("fused", 150f)
        assertFalse(LocationEngine.isGpsFix(loc))
    }

    @Test
    fun isGpsFix_fusedProvider_cellTowerAccuracy_returnsFalse() {
        val loc = buildLocation("fused", 1500f)
        assertFalse(LocationEngine.isGpsFix(loc))
    }

    @Test
    fun isGpsFix_fusedProvider_zeroAccuracy_returnsTrue() {
        val loc = buildLocation("fused", 0f)
        assertTrue(LocationEngine.isGpsFix(loc))
    }

    // ── Network provider tests ──────────────────────────────────────────────

    @Test
    fun isGpsFix_networkProvider_returnsFalse() {
        val loc = buildLocation("network", 30f)
        assertFalse(LocationEngine.isGpsFix(loc))
    }

    @Test
    fun isGpsFix_networkProvider_highAccuracy_returnsFalse() {
        // Even with sub-50m accuracy, network provider is not GPS
        val loc = buildLocation("network", 10f)
        assertFalse(LocationEngine.isGpsFix(loc))
    }

    // ── Other provider tests ────────────────────────────────────────────────

    @Test
    fun isGpsFix_passiveProvider_returnsFalse() {
        val loc = buildLocation("passive", 25f)
        assertFalse(LocationEngine.isGpsFix(loc))
    }

    @Test
    fun isGpsFix_unknownProvider_returnsFalse() {
        val loc = buildLocation("unknown", 20f)
        assertFalse(LocationEngine.isGpsFix(loc))
    }

    @Test
    fun isGpsFix_emptyProvider_returnsFalse() {
        val loc = buildLocation("", 10f)
        assertFalse(LocationEngine.isGpsFix(loc))
    }

    // ── Threshold boundary tests ────────────────────────────────────────────

    @Test
    fun gpsAccuracyThreshold_isCorrect() {
        kotlin.test.assertEquals(50f, LocationEngine.GPS_ACCURACY_THRESHOLD)
    }

    @Test
    fun isGpsFix_fusedProvider_justBelowThreshold_returnsTrue() {
        val loc = buildLocation("fused", 49.9f)
        assertTrue(LocationEngine.isGpsFix(loc))
    }

    @Test
    fun isGpsFix_fusedProvider_justAboveThreshold_returnsFalse() {
        val loc = buildLocation("fused", 50.1f)
        assertFalse(LocationEngine.isGpsFix(loc))
    }
}
