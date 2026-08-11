package com.ikolvi.tracelet.sdk.geofence

import android.Manifest
import android.app.Application
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
import org.robolectric.Shadows
import org.robolectric.annotation.Config
import uniffi.tracelet_core.DatabaseManager
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * #356 — a geofence smaller than the OS can resolve must still work.
 *
 * #355 established that a 5–10 m fence is smaller than typical GPS error, so
 * Play Services never reports a crossing: registering while inside fires an
 * immediate ENTER from the initial trigger, the fence looks live, and then
 * nothing is ever reported again. The response then was a warning. The response
 * now is to support it: such a fence is evaluated in-app against its true
 * radius, with a hysteresis band scaled to the *measured* fix accuracy instead
 * of a flat 20 m — which on a 2–4 m-accurate handset is the difference between
 * needing 28 m of travel to EXIT and needing 8 m.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class GeofenceSmallRadiusTest {

    private lateinit var context: Context
    private lateinit var config: ConfigManager
    private lateinit var db: DatabaseManager
    private lateinit var geoManager: GeofenceManager
    private val transitions = mutableListOf<Pair<String, String>>()

    private val dbName = "test_geofence_small_radius.db"

    private val centerLat = 10.787929
    private val centerLng = 76.684183

    /** Approximate a point `meters` due north of the fence centre. */
    private fun north(meters: Double) = centerLat + meters / 111_320.0

    private fun geofenceLines(): List<String> =
        db.getLogs(500).map { it.message }.filter { it.contains("[geofence]") }

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        Shadows.shadowOf(context as Application)
            .grantPermissions(Manifest.permission.ACCESS_FINE_LOCATION)
        config = ConfigManager.getInstance(context)
        // OFF is the point: this must all hold in a release build's log level,
        // and — critically — with geofenceModeHighAccuracy left at its default
        // false. A small fence is evaluated in-app because the OS cannot serve
        // it, not because the caller opted in.
        config.setConfig(mapOf("logLevel" to TraceletLogger.LEVEL_OFF))

        val dbPath = context.filesDir.resolve(dbName).absolutePath
        db = DatabaseManager(dbPath)
        db.setEncryptionKey("")
        db.clearGeofences()
        db.clearLogs()

        val logger = TraceletLogger(context, config)
        logger.rustDatabase = db
        TraceletLog.attach(logger)

        geoManager = GeofenceManager(context, config, ListenerEventSender(), db)
        geoManager.onGeofenceEvent = { event ->
            @Suppress("UNCHECKED_CAST")
            val gf = event["geofence"] as? Map<String, Any?>
            if (gf != null) {
                transitions.add((gf["identifier"] as String) to (gf["action"] as String))
            }
        }
    }

    @After
    fun tearDown() {
        TraceletLog.detach()
        ConfigManager.resetInstance()
        transitions.clear()
        context.filesDir.resolve(dbName).delete()
    }

    private fun circle(id: String, radius: Double) = mapOf<String, Any?>(
        "identifier" to id,
        "latitude" to centerLat,
        "longitude" to centerLng,
        "radius" to radius,
    )

    // ── The capability ──────────────────────────────────────────────────────

    @Test
    fun `a 10m fence fires ENTER and EXIT over a short walk, at default settings`() {
        geoManager.addGeofence(circle("TINY", 10.0))

        // Arrive and hold still, then walk off — the reporter covered ~34 m and
        // saw no EXIT at all. 4 m accuracy is what the field device reported.
        geoManager.evaluateHighAccuracyProximity(north(3.0), centerLng, 4.0)
        geoManager.evaluateHighAccuracyProximity(north(2.0), centerLng, 4.0)
        geoManager.evaluateHighAccuracyProximity(north(25.0), centerLng, 4.0)
        geoManager.evaluateHighAccuracyProximity(north(30.0), centerLng, 4.0)

        assertEquals(
            listOf("TINY" to "ENTER", "TINY" to "EXIT"),
            transitions,
            "a 10 m fence must ENTER on arrival and EXIT on a 30 m departure, got: ${geofenceLines()}",
        )
    }

    @Test
    fun `a 10m fence does not flap while the device stands still`() {
        geoManager.addGeofence(circle("TINY", 10.0))

        for (d in listOf(2.0, 11.0, 6.0, 13.0, 4.0, 12.0, 5.0)) {
            geoManager.evaluateHighAccuracyProximity(north(d), centerLng, 6.0)
        }

        assertEquals(
            listOf("TINY" to "ENTER"),
            transitions,
            "jitter across a 10 m boundary must not produce repeated crossings",
        )
    }

    // ── Ownership: small fences are ours, ordinary ones are the OS's ────────

    @Test
    fun `a fence the OS can resolve is left to the OS`() {
        geoManager.addGeofence(circle("BIG", 500.0))

        // Standing at the centre of a 500 m fence produces nothing here: with
        // geofenceModeHighAccuracy off, Play Services owns it and reports it via
        // handleGeofenceEvent. Evaluating it in-app too would double-fire it.
        geoManager.evaluateHighAccuracyProximity(centerLat, centerLng, 4.0)

        assertTrue(
            transitions.isEmpty(),
            "a 500 m fence must not be evaluated in-app at default settings, got: $transitions",
        )
    }

    @Test
    fun `a polygon is evaluated in-app whatever the accuracy mode`() {
        // Play Services only monitors circles, so a polygon has always been ours
        // — but before #356 it was only evaluated when geofenceModeHighAccuracy
        // was on, which meant a polygon silently never fired at default settings.
        geoManager.addGeofence(
            mapOf(
                "identifier" to "POLY",
                "latitude" to 0.0,
                "longitude" to 0.0,
                "radius" to 0.0,
                "vertices" to listOf(
                    listOf(centerLat - 0.001, centerLng - 0.001),
                    listOf(centerLat + 0.001, centerLng - 0.001),
                    listOf(centerLat + 0.001, centerLng + 0.001),
                    listOf(centerLat - 0.001, centerLng + 0.001),
                ),
            ),
        )

        geoManager.evaluateHighAccuracyProximity(centerLat, centerLng, 4.0)

        assertEquals(
            listOf("POLY" to "ENTER"),
            transitions,
            "a polygon must fire without geofenceModeHighAccuracy, got: ${geofenceLines()}",
        )
    }

    // ── The wake-up ─────────────────────────────────────────────────────────

    @Test
    fun `an OS transition for a small fence claims the wake-up instead of being dropped`() {
        geoManager.addGeofence(circle("TINY", 10.0))
        var wokeUp = 0
        geoManager.onEvaluatorWakeup = { wokeUp++ }

        // Play Services reports EXIT from the *inflated* 100 m region. That
        // transition is about the wrong boundary and must not surface as a
        // crossing — but it is the only signal a killed app gets that it is near
        // a fence only the evaluator can decide, so it has to resume the stream.
        geoManager.handleGeofenceEvent(
            transitionType = 2, // EXIT
            triggeringGeofences = listOf(
                com.ikolvi.tracelet.sdk.wrapper.TraceletGeofence(
                    requestId = "TINY",
                    latitude = centerLat,
                    longitude = centerLng,
                    radiusMeters = 100f,
                    expirationTime = -1L,
                    transitionTypes = 3,
                    loiteringDelayMs = 0,
                ),
            ),
            latitude = north(120.0),
            longitude = centerLng,
        )

        assertEquals(1, wokeUp, "the OS wake-up must resume the location stream")
        assertTrue(
            transitions.isEmpty(),
            "the 100 m wake-up boundary must not be reported as a crossing, got: $transitions",
        )
    }

    @Test
    fun `an OS transition for a fence the OS owns does not claim the wake-up`() {
        geoManager.addGeofence(circle("BIG", 500.0))
        var wokeUp = 0
        geoManager.onEvaluatorWakeup = { wokeUp++ }

        geoManager.handleGeofenceEvent(
            transitionType = 1, // ENTER
            triggeringGeofences = listOf(
                com.ikolvi.tracelet.sdk.wrapper.TraceletGeofence(
                    requestId = "BIG",
                    latitude = centerLat,
                    longitude = centerLng,
                    radiusMeters = 500f,
                    expirationTime = -1L,
                    transitionTypes = 3,
                    loiteringDelayMs = 0,
                ),
            ),
            latitude = centerLat,
            longitude = centerLng,
        )

        assertEquals(
            0,
            wokeUp,
            "a fence the OS decides needs no stream, so it must not force one on",
        )
        assertEquals(
            listOf("BIG" to "ENTER"),
            transitions,
            "and its own transition must still be reported",
        )
    }

    // ── The always-on note ──────────────────────────────────────────────────

    @Test
    fun `a small fence records how it will be handled, even at logLevel OFF`() {
        geoManager.addGeofence(circle("TINY", 5.0))

        val notes = geofenceLines().filter { it.contains("TINY") }
        assertTrue(
            notes.any { it.contains("evaluated in-app") && it.contains("wake-up only") },
            "which component owns the fence must reach a release-build report, got: $notes",
        )
    }

    @Test
    fun `a fence the OS can resolve records no such note`() {
        geoManager.addGeofence(circle("FINE", 100.0))

        assertTrue(
            geofenceLines().none { it.contains("FINE") && it.contains("evaluated in-app") },
            "a resolvable radius needs no hand-off note, got: ${geofenceLines()}",
        )
    }
}
