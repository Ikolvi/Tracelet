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

/**
 * Regression for #292: in `geofenceModeHighAccuracy`, a stationary device inside
 * a geofence must emit exactly ONE ENTER across the resume/boot cycles that wipe
 * the evaluator's in-memory inside-set.
 *
 * Field symptom: on an attendance backend the device logged ~9 auto IN/OUT pairs
 * in a day while the employee never left the office, because `startGeofences()`
 * — run on every `ready()`/takeover and after boot — calls
 * `clearHighAccuracyState()`, so each takeover forgot the device was inside and
 * re-fired ENTER. The persisted `knownInsideIds` set now dedups those re-entries.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class GeofenceManagerResumeChurnTest {

    private lateinit var context: Context
    private lateinit var config: ConfigManager
    private lateinit var db: DatabaseManager
    private lateinit var geoManager: GeofenceManager
    private val captured = mutableListOf<Map<String, Any?>>()

    private val centerLat = 10.787929
    private val centerLng = 76.684183
    private val radius = 50.0 // exit threshold = radius + max(radius*0.1, 20) = 70 m

    private val dbName = "test_geofence_resume_churn.db"

    // ~meters due north of the center (1 deg lat ~= 111_320 m).
    private fun north(meters: Double) = centerLat + meters / 111320.0

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        config = ConfigManager.getInstance(context)
        config.setConfig(
            mapOf(
                "geofenceModeHighAccuracy" to true,
                // Full gating so the tests exercise the resume/boot path, not the
                // exitAccuracyMax clamp (covered by GeofenceManagerExitAccuracyTest).
                "geofenceExitAccuracyMax" to -1,
            ),
        )

        val dbPath = context.filesDir.resolve(dbName).absolutePath
        db = DatabaseManager(dbPath)
        db.setEncryptionKey("")
        db.clearGeofences()
        db.insertGeofence("OFFICE", centerLat, centerLng, radius, null, null)

        geoManager = newManager()
        // Isolate persisted crossing state from any previous test run.
        geoManager.resetHighAccuracyInsideState()
    }

    @After
    fun tearDown() {
        geoManager.resetHighAccuracyInsideState()
        ConfigManager.resetInstance()
        context.filesDir.resolve(dbName).delete()
    }

    private fun newManager(): GeofenceManager =
        GeofenceManager(context, config, ListenerEventSender(), db).also { mgr ->
            mgr.onGeofenceEvent = { captured.add(it) }
        }

    private fun countAction(action: String): Int = captured.count {
        ((it["geofence"] as? Map<*, *>)?.get("action") as? String) == action
    }

    /** A resume/takeover that wipes the evaluator's in-memory state — exactly what
     *  `startGeofences(isResume = true)` and the boot restore do. */
    private fun simulateResume() = geoManager.clearHighAccuracyState()

    @Test
    fun `resume does not re-emit ENTER for a stationary device inside a fence`() {
        geoManager.evaluateHighAccuracyProximity(centerLat, centerLng, 8.0)
        assertEquals(1, countAction("ENTER"), "first fix inside must ENTER once")

        // Three ready()/takeover resumes; the device never moved.
        repeat(3) {
            simulateResume()
            geoManager.evaluateHighAccuracyProximity(north(12.0), centerLng, 8.0)
        }

        assertEquals(1, countAction("ENTER"), "resume must not re-emit ENTER (#292)")
        assertEquals(0, countAction("EXIT"), "a stationary device must not EXIT")
    }

    @Test
    fun `cold start after process death does not re-emit ENTER`() {
        geoManager.evaluateHighAccuracyProximity(centerLat, centerLng, 8.0)
        assertEquals(1, countAction("ENTER"))

        // A brand-new GeofenceManager models a fresh process: the Rust evaluator
        // starts empty, but knownInsideIds is reloaded from persisted prefs.
        geoManager = newManager()
        geoManager.evaluateHighAccuracyProximity(north(12.0), centerLng, 8.0)

        assertEquals(1, countAction("ENTER"), "cold start must not re-emit ENTER (#292)")
    }

    @Test
    fun `genuine departure then return still emits EXIT then a fresh ENTER`() {
        geoManager.evaluateHighAccuracyProximity(centerLat, centerLng, 8.0)     // ENTER
        // A sustained departure: two consecutive out-of-fence fixes confirm the
        // EXIT (the first is held pending confirmation).
        geoManager.evaluateHighAccuracyProximity(north(120.0), centerLng, 8.0)  // held
        geoManager.evaluateHighAccuracyProximity(north(120.0), centerLng, 8.0)  // confirmed EXIT
        assertEquals(1, countAction("ENTER"))
        assertEquals(1, countAction("EXIT"))

        simulateResume()
        geoManager.evaluateHighAccuracyProximity(north(12.0), centerLng, 8.0)   // genuine return

        assertEquals(2, countAction("ENTER"), "a genuine return after EXIT must re-ENTER")
        assertEquals(1, countAction("EXIT"))
    }

    @Test
    fun `leave while the app is dead is reported as EXIT on cold start, not stuck`() {
        // Device ENTERs the office; the app is later killed with the persisted
        // inside-set still holding OFFICE.
        geoManager.evaluateHighAccuracyProximity(centerLat, centerLng, 8.0)
        assertEquals(1, countAction("ENTER"))

        // New process (evaluator starts empty). The device left the office while
        // dead, so the fixes are well outside. Seeded from the persisted set, the
        // cold-started evaluator confirms the departure across two fixes and
        // EXITs rather than getting stuck inside.
        geoManager = newManager()
        geoManager.evaluateHighAccuracyProximity(north(200.0), centerLng, 8.0)  // held
        geoManager.evaluateHighAccuracyProximity(north(200.0), centerLng, 8.0)  // confirmed EXIT
        assertEquals(1, countAction("EXIT"), "a sustained leave-while-dead must EXIT on cold start (#292)")

        // Returning to the office then fires a fresh ENTER — the state was not stuck.
        geoManager.evaluateHighAccuracyProximity(north(12.0), centerLng, 8.0)
        assertEquals(2, countAction("ENTER"), "a genuine return after the exit must ENTER")
    }

    @Test
    fun `removeGeofence clears inside-state so a re-added fence can ENTER again`() {
        geoManager.evaluateHighAccuracyProximity(centerLat, centerLng, 8.0)
        assertEquals(1, countAction("ENTER"))

        // Remove the fence, then add it back (a fence-list refresh, or an id
        // reused for a different location).
        geoManager.removeGeofence("OFFICE")
        db.insertGeofence("OFFICE", centerLat, centerLng, radius, null, null)

        // Being inside the re-added fence must ENTER again — the prior
        // inside-state must not suppress it.
        geoManager.evaluateHighAccuracyProximity(centerLat, centerLng, 8.0)
        assertEquals(2, countAction("ENTER"), "a re-added fence must be able to ENTER again (#292)")
    }

    @Test
    fun `fresh start re-emits the initial ENTER`() {
        geoManager.evaluateHighAccuracyProximity(centerLat, centerLng, 8.0)
        assertEquals(1, countAction("ENTER"))

        // Fresh, explicit start (mirrors startGeofences(isResume = false)).
        geoManager.resetHighAccuracyInsideState()
        geoManager.evaluateHighAccuracyProximity(centerLat, centerLng, 8.0)

        assertEquals(2, countAction("ENTER"), "a fresh start re-emits the initial-entry ENTER")
    }
}
