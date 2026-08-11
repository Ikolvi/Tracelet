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
 * Verifies the geofenceModeHighAccuracy "proximity" path — the software-based
 * ENTER/EXIT detection that runs off the live location stream
 * (LocationEngine.onLocationUpdate → evaluateHighAccuracyProximity). This is the
 * path the boot/headless flow relies on (issue #185): OS-level geofence events
 * are suppressed in high-accuracy mode, so transitions come ONLY from here.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class GeofenceManagerProximityTest {

    private lateinit var context: Context
    private lateinit var config: ConfigManager
    private lateinit var db: DatabaseManager
    private lateinit var geoManager: GeofenceManager
    private val captured = mutableListOf<Map<String, Any?>>()

    private val centerLat = 10.787929
    private val centerLng = 76.684183
    private val radius = 150.0

    @Before
    fun setUp() {
        org.robolectric.shadows.ShadowLog.stream = System.out
        context = ApplicationProvider.getApplicationContext()
        config = ConfigManager.getInstance(context)
        config.setConfig(mapOf("geofenceModeHighAccuracy" to true))

        val dbPath = context.filesDir.resolve("test_geofence_proximity.db").absolutePath
        db = DatabaseManager(dbPath)
        db.setEncryptionKey("")
        db.clearGeofences()
        db.insertGeofence("ISSUE_185_ZONE", centerLat, centerLng, radius, null, null, true, true, false, 0)

        geoManager = GeofenceManager(context, config, ListenerEventSender(), db)
        geoManager.onGeofenceEvent = { captured.add(it) }
        geoManager.clearHighAccuracyState()
    }

    @After
    fun tearDown() {
        ConfigManager.resetInstance()
        context.filesDir.resolve("test_geofence_proximity.db").delete()
    }

    private fun lastAction(): String? {
        val gf = captured.lastOrNull()?.get("geofence") as? Map<*, *>
        return gf?.get("action") as? String
    }

    private fun enterCount(): Int = captured.count {
        ((it["geofence"] as? Map<*, *>)?.get("action") as? String) == "ENTER"
    }

    @Test
    fun `high-accuracy proximity fires ENTER then EXIT crossing the boundary`() {
        // ~1.1 km north — establishes the "outside" baseline, no event.
        geoManager.evaluateHighAccuracyProximity(centerLat + 0.01, centerLng)
        assertTrue(enterCount() == 0, "Should not ENTER while outside the zone")

        // Move to the centre → crosses inside → ENTER.
        geoManager.evaluateHighAccuracyProximity(centerLat, centerLng)
        assertEquals("ENTER", lastAction(), "Crossing inside should fire ENTER")

        // Move ~1.1 km away → a sustained departure confirmed across two fixes
        // fires EXIT (the first out-of-fence fix is held for confirmation).
        geoManager.evaluateHighAccuracyProximity(centerLat + 0.01, centerLng)
        geoManager.evaluateHighAccuracyProximity(centerLat + 0.01, centerLng)
        assertEquals("EXIT", lastAction(), "Crossing back outside should fire EXIT")
    }

    @Test
    fun `staying inside does not re-fire ENTER`() {
        geoManager.evaluateHighAccuracyProximity(centerLat, centerLng) // ENTER
        val afterFirst = enterCount()
        // ~11 m away — still well inside the 150 m radius.
        geoManager.evaluateHighAccuracyProximity(centerLat + 0.0001, centerLng)
        assertEquals(afterFirst, enterCount(), "Staying inside must not re-fire ENTER")
    }
}
