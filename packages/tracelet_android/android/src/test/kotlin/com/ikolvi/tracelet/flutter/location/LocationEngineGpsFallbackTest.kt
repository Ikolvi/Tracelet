package com.ikolvi.tracelet.flutter.location

import android.content.Context
import android.location.Location
import android.location.LocationManager
import com.ikolvi.tracelet.sdk.location.LocationEngine
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Unit tests for the GPS-off fallback and location source classification
 * added in v1.4.3.
 *
 * Tests companion-object utilities ([LocationEngine.isGpsFix] and
 * [LocationEngine.isGpsProviderEnabled]) that drive the automatic
 * priority downgrade when GPS hardware is disabled.
 *
 * Full integration tests for the `activateGpsFallback()` /
 * `restoreOriginalPriority()` flow require FusedLocationProviderClient
 * instrumentation and are covered by device-level integration tests.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
internal class LocationEngineGpsFallbackTest {

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

    // ── GPS provider state transitions ──────────────────────────────────────

    @Test
    fun gpsOff_networkOn_isGpsProviderEnabled_returnsFalse() {
        val context = RuntimeEnvironment.getApplication()
        val lm = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        Shadows.shadowOf(lm).setProviderEnabled(LocationManager.GPS_PROVIDER, false)
        Shadows.shadowOf(lm).setProviderEnabled(LocationManager.NETWORK_PROVIDER, true)

        assertFalse(LocationEngine.isGpsProviderEnabled(context))
    }

    @Test
    fun gpsOn_networkOn_isGpsProviderEnabled_returnsTrue() {
        val context = RuntimeEnvironment.getApplication()
        val lm = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        Shadows.shadowOf(lm).setProviderEnabled(LocationManager.GPS_PROVIDER, true)
        Shadows.shadowOf(lm).setProviderEnabled(LocationManager.NETWORK_PROVIDER, true)

        assertTrue(LocationEngine.isGpsProviderEnabled(context))
    }

    @Test
    fun gpsToggleOff_thenOn_isGpsProviderEnabled_returnsTrue() {
        val context = RuntimeEnvironment.getApplication()
        val lm = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val shadow = Shadows.shadowOf(lm)

        shadow.setProviderEnabled(LocationManager.GPS_PROVIDER, true)
        assertTrue(LocationEngine.isGpsProviderEnabled(context))

        shadow.setProviderEnabled(LocationManager.GPS_PROVIDER, false)
        assertFalse(LocationEngine.isGpsProviderEnabled(context))

        shadow.setProviderEnabled(LocationManager.GPS_PROVIDER, true)
        assertTrue(LocationEngine.isGpsProviderEnabled(context))
    }

    @Test
    fun bothProvidersOff_isGpsProviderEnabled_returnsFalse() {
        val context = RuntimeEnvironment.getApplication()
        val lm = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        Shadows.shadowOf(lm).setProviderEnabled(LocationManager.GPS_PROVIDER, false)
        Shadows.shadowOf(lm).setProviderEnabled(LocationManager.NETWORK_PROVIDER, false)

        assertFalse(LocationEngine.isGpsProviderEnabled(context))
    }

    // ── Location source classification via isGpsFix ─────────────────────────

    @Test
    fun fusedFix_wifiAccuracy_isNotGps() {
        // 80m accuracy — typical Wi-Fi positioning
        val loc = buildLocation("fused", 80f)
        assertFalse(LocationEngine.isGpsFix(loc))
    }

    @Test
    fun fusedFix_cellAccuracy_isNotGps() {
        // 500m accuracy — typical cell tower triangulation
        val loc = buildLocation("fused", 500f)
        assertFalse(LocationEngine.isGpsFix(loc))
    }

    @Test
    fun fusedFix_gpsAccuracy_isGps() {
        // 8m accuracy — typical GPS fix
        val loc = buildLocation("fused", 8f)
        assertTrue(LocationEngine.isGpsFix(loc))
    }

    @Test
    fun networkProvider_anyAccuracy_isNeverGps() {
        // Even very accurate network fixes are not GPS
        for (accuracy in listOf(5f, 30f, 100f, 1000f)) {
            val loc = buildLocation("network", accuracy)
            assertFalse(
                LocationEngine.isGpsFix(loc),
                "network provider with accuracy=${accuracy}m should not be GPS",
            )
        }
    }

    @Test
    fun gpsProvider_anyAccuracy_isAlwaysGps() {
        // GPS provider is always trusted regardless of accuracy
        for (accuracy in listOf(5f, 50f, 100f, 500f)) {
            val loc = buildLocation("gps", accuracy)
            assertTrue(
                LocationEngine.isGpsFix(loc),
                "gps provider with accuracy=${accuracy}m should be GPS",
            )
        }
    }

    // ── GPS accuracy threshold constant ─────────────────────────────────────

    @Test
    fun gpsAccuracyThreshold_is50m() {
        assertEquals(50f, LocationEngine.GPS_ACCURACY_THRESHOLD)
    }
}
