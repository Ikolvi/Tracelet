package com.ikolvi.tracelet.sdk.geofence

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.ListenerEventSender
import com.ikolvi.tracelet.sdk.util.TraceletLog
import com.ikolvi.tracelet.sdk.util.TraceletLogger
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import uniffi.tracelet_core.DatabaseManager
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Covers the `[geofence]` decision trace emitted on every high-accuracy
 * transition.
 *
 * Before this existed, `evaluateHighAccuracyProximity` logged nothing at all —
 * not even at DEBUG — so a field report of "occasional false EXIT" produced a
 * bug report with zero geofence content, and triage had to proceed from config
 * alone.
 *
 * These assertions read back through the **persisted** log store
 * (`DatabaseManager.getLogs`), which is the same source `Tracelet.getLogs()` and
 * the Doctor bug report use. That makes this an end-to-end check that the trace
 * actually reaches an exported report, not just logcat.
 *
 * Pinned properties:
 *  1. transitions are logged at INFO, because production apps run at INFO
 *  2. the line carries every input to the accuracy-aware EXIT test (#274/#276)
 *  3. it never carries raw coordinates, so it is safe to paste into an issue
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class GeofenceManagerTransitionLogTest {

    private lateinit var context: Context
    private lateinit var config: ConfigManager
    private lateinit var db: DatabaseManager
    private lateinit var geoManager: GeofenceManager

    private val centerLat = 10.787929
    private val centerLng = 76.684183
    private val radius = 50.0 // exit threshold = radius + max(radius*0.1, 20) = 70 m

    private fun north(meters: Double) = centerLat + meters / 111320.0

    /** Persisted log lines carrying the geofence category tag, oldest first. */
    private fun geofenceLines(): List<Pair<String, String>> =
        db.getLogs(500)
            .filter { it.message.contains("[geofence]") }
            .map { it.level to it.message }
            .reversed()

    private fun linesAt(level: String): List<String> =
        geofenceLines().filter { it.first == level }.map { it.second }

    private fun firstExitAtInfo(): String? = linesAt("INFO").firstOrNull { it.contains("EXIT") }

    private fun configureLogLevel(level: Int) {
        config.setConfig(mapOf("logLevel" to level))
    }

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        config = ConfigManager.getInstance(context)
        config.setConfig(
            mapOf(
                "geofenceModeHighAccuracy" to true,
                "logLevel" to TraceletLogger.LEVEL_DEBUG,
            ),
        )

        val dbPath = context.filesDir.resolve("test_geofence_transition_log.db").absolutePath
        db = DatabaseManager(dbPath)
        db.setEncryptionKey("")
        db.clearGeofences()
        db.clearLogs()
        db.insertGeofence("ZONE_LOG", centerLat, centerLng, radius, null, null)

        // Attach the real logger so assertions run against the persisted store
        // that Doctor exports from.
        val logger = TraceletLogger(context, config)
        logger.rustDatabase = db
        TraceletLog.attach(logger)

        geoManager = GeofenceManager(context, config, ListenerEventSender(), db)
        geoManager.clearHighAccuracyState()
    }

    @After
    fun tearDown() {
        TraceletLog.detach()
        ConfigManager.resetInstance()
        context.filesDir.resolve("test_geofence_transition_log.db").delete()
    }

    // ── Transitions must be visible at INFO ─────────────────────────────────

    @Test
    fun `ENTER is logged at INFO with the geofence category tag`() {
        geoManager.evaluateHighAccuracyProximity(centerLat, centerLng, 8.0)

        assertTrue(
            linesAt("INFO").any { it.contains("ENTER") && it.contains("ZONE_LOG") },
            "expected an INFO [geofence] ENTER line, got: ${geofenceLines()}",
        )
    }

    @Test
    fun `EXIT is logged at INFO carrying every input to the accuracy-aware test`() {
        geoManager.evaluateHighAccuracyProximity(centerLat, centerLng, 8.0)
        // Genuine departure: 200 m out with a tight ±10 m fix -> 190 > 70 -> EXIT.
        geoManager.evaluateHighAccuracyProximity(north(200.0), centerLng, 10.0)

        val exit = firstExitAtInfo()
        requireNotNull(exit) { "expected an INFO [geofence] EXIT line, got: ${geofenceLines()}" }

        // Without these fields a reader cannot tell drift from a real departure.
        for (field in listOf("dist=", "radius=", "buffer=", "thr=", "accRaw=", "accEff=")) {
            assertTrue(exit.contains(field), "EXIT trace is missing '$field': $exit")
        }
    }

    @Test
    fun `transitions survive at logLevel INFO`() {
        // Regression guard for the level choice. If these move to DEBUG,
        // production apps at INFO go back to reporting undiagnosable EXITs.
        db.clearLogs()
        configureLogLevel(TraceletLogger.LEVEL_INFO)
        geoManager.evaluateHighAccuracyProximity(centerLat, centerLng, 8.0)

        assertTrue(
            linesAt("INFO").isNotEmpty(),
            "transitions must survive at logLevel=INFO, got: ${geofenceLines()}",
        )
    }

    // ── Privacy ─────────────────────────────────────────────────────────────

    @Test
    fun `trace does not leak raw coordinates`() {
        geoManager.evaluateHighAccuracyProximity(centerLat, centerLng, 8.0)
        geoManager.evaluateHighAccuracyProximity(north(200.0), centerLng, 10.0)

        // These reports get pasted into public issues. Distance-from-centre is
        // all triage needs; absolute position is not.
        for ((_, message) in geofenceLines()) {
            assertFalse(
                message.contains("10.787") || message.contains("76.684"),
                "geofence log line leaked coordinates: $message",
            )
        }
    }

    // ── The #276 clamp must be visible ──────────────────────────────────────

    @Test
    fun `trace surfaces the exitAccuracyMax clamp when it binds`() {
        // Exactly the confusion behind the field report: a clamp is configured
        // and the operator cannot tell whether it took effect.
        config.setConfig(mapOf("geofenceExitAccuracyMax" to 20))
        geoManager.evaluateHighAccuracyProximity(centerLat, centerLng, 8.0)
        geoManager.evaluateHighAccuracyProximity(north(200.0), centerLng, 150.0)

        val exit = firstExitAtInfo()
        requireNotNull(exit) { "expected an EXIT line, got: ${geofenceLines()}" }
        assertTrue(exit.contains("accRaw=150.0"), "raw accuracy must be reported: $exit")
        assertTrue(exit.contains("accEff=20.0"), "clamped accuracy must be reported: $exit")
        assertTrue(exit.contains("clampApplied=true"), "clamp must be flagged: $exit")
        assertTrue(exit.contains("exitAccuracyMax=20"), "the configured knob must be echoed: $exit")
    }

    @Test
    fun `trace reports pass-through accuracy under the default policy`() {
        config.setConfig(mapOf("geofenceExitAccuracyMax" to -1))
        geoManager.evaluateHighAccuracyProximity(centerLat, centerLng, 8.0)
        geoManager.evaluateHighAccuracyProximity(north(200.0), centerLng, 12.0)

        val exit = firstExitAtInfo()
        requireNotNull(exit) { "expected an EXIT line, got: ${geofenceLines()}" }
        assertTrue(exit.contains("accRaw=12.0") && exit.contains("accEff=12.0"), exit)
        assertFalse(exit.contains("clampApplied=true"), "no clamp should be flagged at -1: $exit")
    }

    // ── The logged threshold must match the evaluator's real behavior ────────

    @Test
    fun `logged exit threshold agrees with the evaluator at the boundary`() {
        // The hysteresis constants are mirrored in Kotlin for logging while the
        // Rust core owns the decision. This pins the mirror: if Rust changes its
        // fraction or floor, the logged threshold stops matching real behavior
        // and this fails instead of silently misreporting.
        geoManager.evaluateHighAccuracyProximity(centerLat, centerLng, 8.0)

        // Just inside the logged threshold (70 m) with a perfect fix -> held.
        geoManager.evaluateHighAccuracyProximity(north(69.0), centerLng, 0.0)
        assertTrue(
            firstExitAtInfo() == null,
            "69 m must not exit a 70 m threshold: ${geofenceLines()}",
        )

        // Just outside -> exits, and the line must report thr=70.0.
        geoManager.evaluateHighAccuracyProximity(north(71.0), centerLng, 0.0)
        val exit = firstExitAtInfo()
        requireNotNull(exit) { "71 m must exit a 70 m threshold: ${geofenceLines()}" }
        assertTrue(
            exit.contains("thr=70.0") && exit.contains("buffer=20.0"),
            "logged threshold must match the Rust constants: $exit",
        )
    }

    // ── Proximity scope changes must not read as crossings ──────────────────

    @Test
    fun `proximity scope updates are labelled as not being ENTER or EXIT`() {
        // updateProximity emits geofencesChange on/off for monitoring scope, not
        // boundary crossings. Apps that conflate the two see phantom exits, so
        // the log must not read like a transition.
        geoManager.updateProximity(centerLat, centerLng)

        val scopeLines = geofenceLines().map { it.second }.filter { it.contains("proximity scope") }
        for (line in scopeLines) {
            assertTrue(line.contains("not ENTER/EXIT"), "ambiguous proximity log: $line")
        }
    }

    @Test
    fun `evaluation with no geofences logs nothing`() {
        // Volume guard: the trace must not fire on every location update.
        db.clearGeofences()
        val emptyManager = GeofenceManager(context, config, ListenerEventSender(), db)
        emptyManager.clearHighAccuracyState()
        db.clearLogs()

        emptyManager.evaluateHighAccuracyProximity(centerLat, centerLng, 8.0)
        assertEquals(
            0,
            geofenceLines().size,
            "no geofences means no geofence logging: ${geofenceLines()}",
        )
    }
}
