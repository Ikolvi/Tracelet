package com.ikolvi.tracelet.sdk.geofence

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.ListenerEventSender
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import uniffi.tracelet_core.DatabaseManager
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Verifies `GeofenceConfig.geofenceExitAccuracyMax` (#276) tunes the
 * accuracy-aware EXIT gating introduced in #274.
 *
 * Scenario for a 50 m geofence (exit threshold = radius + max(radius*0.1, 20) =
 * 70 m): ENTER at center, then a *stationary* ±150 m drift spike reported ~85 m
 * out (the device never moved). The gating policy decides whether that spike
 * fires a (false) EXIT:
 * - `-1` (default): full gating → `85 - 150 < 70` → held, no EXIT.
 * - `0`: gating off → `85 - 0 > 70` → EXIT (drift-prone).
 * - `20`: clamp → `85 - 20 = 65 < 70` → held, yet a genuine accurate departure
 *   still exits.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class GeofenceManagerExitAccuracyTest {

    private lateinit var context: Context
    private lateinit var config: ConfigManager
    private lateinit var db: DatabaseManager
    private lateinit var geoManager: GeofenceManager
    private val captured = mutableListOf<Map<String, Any?>>()

    private val centerLat = 10.787929
    private val centerLng = 76.684183
    private val radius = 50.0 // exit threshold = 70 m

    // ~meters due north of the center (1 deg lat ~= 111_320 m).
    private fun north(meters: Double) = centerLat + meters / 111320.0

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        config = ConfigManager.getInstance(context)

        val dbPath = context.filesDir.resolve("test_geofence_exit_accuracy.db").absolutePath
        db = DatabaseManager(dbPath)
        db.setEncryptionKey("")
        db.clearGeofences()
        db.insertGeofence("ZONE_276", centerLat, centerLng, radius, null, null)

        geoManager = GeofenceManager(context, config, ListenerEventSender(), db)
        geoManager.onGeofenceEvent = { captured.add(it) }
        geoManager.clearHighAccuracyState()
    }

    @After
    fun tearDown() {
        ConfigManager.resetInstance()
        context.filesDir.resolve("test_geofence_exit_accuracy.db").delete()
    }

    private fun exitCount(): Int = captured.count {
        ((it["geofence"] as? Map<*, *>)?.get("action") as? String) == "EXIT"
    }

    private fun configure(exitAccuracyMax: Int) {
        config.setConfig(
            mapOf(
                "geofenceModeHighAccuracy" to true,
                "geofenceExitAccuracyMax" to exitAccuracyMax,
            ),
        )
    }

    /** ENTER inside, then a stationary ±150 m drift spike reported ~85 m out. */
    private fun enterThenDrift() {
        geoManager.evaluateHighAccuracyProximity(centerLat, centerLng, 8.0)
        geoManager.evaluateHighAccuracyProximity(north(85.0), centerLng, 150.0)
    }

    @Test
    fun `default full gating absorbs a high-drift fix (no false EXIT)`() {
        configure(-1)
        enterThenDrift()
        assertEquals(0, exitCount(), "full gating must not EXIT on a ±150 m drift spike")
    }

    @Test
    fun `gating disabled fires EXIT on the drift spike`() {
        configure(0)
        enterThenDrift()
        // With gating off the spike is "confidently outside"; a second such fix
        // confirms it (a single fix is held by the confirmation gate).
        geoManager.evaluateHighAccuracyProximity(north(85.0), centerLng, 150.0)
        assertTrue(exitCount() >= 1, "with gating off, the sustained drift spike should fire EXIT")
    }

    @Test
    fun `clamp absorbs drift but still allows a genuine departure to EXIT`() {
        configure(20)
        enterThenDrift()
        assertEquals(0, exitCount(), "clamp 20 m must absorb the ±150 m drift spike")

        // Genuine, accurate, sustained departure ~120 m out: 120 - 10 = 110 > 70.
        // Two consecutive fixes confirm the EXIT.
        geoManager.evaluateHighAccuracyProximity(north(120.0), centerLng, 10.0)
        geoManager.evaluateHighAccuracyProximity(north(120.0), centerLng, 10.0)
        assertTrue(exitCount() >= 1, "a genuine, sustained departure must still EXIT")
    }
}
