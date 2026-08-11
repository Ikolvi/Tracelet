package com.ikolvi.tracelet.sdk.geofence

import android.content.Context
import android.location.Location
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
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * Regression for #231 — geofence transition events were emitted with hardcoded
 * zero coordinate metrics (accuracy/speed/heading/altitude) and no `battery`
 * key, leaving backends blind to telemetry at the crossing.
 *
 * These tests assert the enriched `coords` (sourced from the last GPS fix via
 * the wired `lastLocationProvider`) and the presence of the `battery` payload.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class GeofenceManagerEnrichmentTest {

    private lateinit var context: Context
    private lateinit var config: ConfigManager
    private lateinit var db: DatabaseManager
    private val captured = mutableListOf<Map<String, Any?>>()

    private val centerLat = 10.787929
    private val centerLng = 76.684183
    private val radius = 150.0

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        config = ConfigManager.getInstance(context)
        config.setConfig(mapOf("geofenceModeHighAccuracy" to true))

        val dbPath = context.filesDir.resolve("test_geofence_enrich.db").absolutePath
        db = DatabaseManager(dbPath)
        db.setEncryptionKey("")
        db.clearGeofences()
        db.insertGeofence("ENRICH_ZONE", centerLat, centerLng, radius, null, null, true, true, false, 0)
    }

    @After
    fun tearDown() {
        ConfigManager.resetInstance()
        context.filesDir.resolve("test_geofence_enrich.db").delete()
        captured.clear()
    }

    private fun managerWith(provider: (() -> Location?)?): GeofenceManager =
        GeofenceManager(
            context, config, ListenerEventSender(), db,
            lastLocationProvider = provider,
        ).apply { onGeofenceEvent = { captured.add(it) }; clearHighAccuracyState() }

    private fun fix(): Location = Location("gps").apply {
        latitude = centerLat
        longitude = centerLng
        accuracy = 25.0f
        speed = 3.5f
        bearing = 90.0f
        altitude = 100.0
        speedAccuracyMetersPerSecond = 0.5f
        bearingAccuracyDegrees = 2.0f
        verticalAccuracyMeters = 4.0f
    }

    @Suppress("UNCHECKED_CAST")
    private fun lastCoords(): Map<String, Any?> =
        captured.last()["coords"] as Map<String, Any?>

    @Test
    fun `geofence event is enriched with real GPS metrics from last fix`() {
        val geo = managerWith { fix() }

        // Establish "outside" then cross inside to fire ENTER.
        geo.evaluateHighAccuracyProximity(centerLat + 0.01, centerLng)
        geo.evaluateHighAccuracyProximity(centerLat, centerLng)

        val coords = lastCoords()
        assertEquals(25.0, coords["accuracy"], "accuracy must come from last fix, not 0.0")
        assertEquals(3.5, coords["speed"] as Double, 1e-4, "speed must come from last fix, not 0.0")
        assertEquals(90.0, coords["heading"] as Double, 1e-4, "heading must come from last fix, not 0.0")
        assertEquals(100.0, coords["altitude"], "altitude must come from last fix, not 0.0")
        // Per-field accuracies surfaced on API 26+.
        assertEquals(0.5, coords["speedAccuracy"] as Double, 1e-4)
        assertEquals(2.0, coords["headingAccuracy"] as Double, 1e-4)
        assertEquals(4.0, coords["altitudeAccuracy"] as Double, 1e-4)
    }

    @Test
    fun `geofence event always carries a battery payload`() {
        val geo = managerWith { fix() }

        geo.evaluateHighAccuracyProximity(centerLat + 0.01, centerLng)
        geo.evaluateHighAccuracyProximity(centerLat, centerLng)

        @Suppress("UNCHECKED_CAST")
        val battery = captured.last()["battery"] as? Map<String, Any?>
        assertNotNull(battery, "battery key must be present (#231)")
        assertTrue(battery.containsKey("level"), "battery must include level")
        assertTrue(battery.containsKey("is_charging"), "battery must include is_charging")
    }

    @Test
    fun `falls back to zeroed coords and battery when no last fix available`() {
        val geo = managerWith(null)

        geo.evaluateHighAccuracyProximity(centerLat + 0.01, centerLng)
        geo.evaluateHighAccuracyProximity(centerLat, centerLng)

        val coords = lastCoords()
        // Geofence boundary lat/lng still populated; metrics fall back to 0.0.
        assertEquals(0.0, coords["accuracy"])
        assertEquals(0.0, coords["speed"])
        assertEquals(0.0, coords["heading"])
        assertEquals(0.0, coords["altitude"])
        // Battery is still emitted even without a GPS fix.
        assertTrue(captured.last().containsKey("battery"))
    }
}
