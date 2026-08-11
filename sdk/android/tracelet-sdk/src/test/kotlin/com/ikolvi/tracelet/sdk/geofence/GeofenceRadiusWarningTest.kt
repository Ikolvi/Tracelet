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
import kotlin.test.assertTrue

/**
 * Regression for #355 — a geofence whose radius the platform cannot service
 * must say so, loudly and at any `logLevel`.
 *
 * A 5-10 m fence is smaller than typical GPS error, so neither Play Services
 * nor the in-app evaluator can ever report a crossing: EXIT alone needs
 * `radius + max(radius * 0.1, 20 m)` of separation. The failure is deceptive
 * rather than obvious — registering while inside fires an immediate ENTER from
 * the initial trigger, so the fence looks live, and then nothing is ever
 * reported again. A field report of "ENTER fired once, EXIT never fires" came
 * from exactly this.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class GeofenceRadiusWarningTest {

    private lateinit var context: Context
    private lateinit var config: ConfigManager
    private lateinit var db: DatabaseManager
    private lateinit var geoManager: GeofenceManager

    private val dbName = "test_geofence_radius_warning.db"

    private fun warningLines(): List<String> =
        db.getLogs(500)
            .filter { it.message.contains("[geofence]") && it.message.contains("WARNING") }
            .map { it.message }

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        Shadows.shadowOf(context as Application)
            .grantPermissions(Manifest.permission.ACCESS_FINE_LOCATION)
        config = ConfigManager.getInstance(context)
        // OFF is the point: the warning must survive a release build's level.
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
    }

    @After
    fun tearDown() {
        TraceletLog.detach()
        ConfigManager.resetInstance()
        context.filesDir.resolve(dbName).delete()
    }

    private fun circle(id: String, radius: Double) = mapOf<String, Any?>(
        "identifier" to id,
        "latitude" to 10.787929,
        "longitude" to 76.684183,
        "radius" to radius,
    )

    @Test
    fun `a 5m fence warns that it cannot produce crossings, even at logLevel OFF`() {
        geoManager.addGeofence(circle("TINY", 5.0))

        val warnings = warningLines()
        assertTrue(
            warnings.any { it.contains("TINY") },
            "a 5m fence must warn that the platform cannot service it (#355), got: ${db.getLogs(50).map { it.message }}",
        )
        // The number that actually explains the symptom: 5 + max(0.5, 20) = 25m.
        assertTrue(
            warnings.any { it.contains("25.0m of travel") },
            "the warning must state the travel EXIT needs, got: $warnings",
        )
    }

    @Test
    fun `a 100m fence does not warn`() {
        geoManager.addGeofence(circle("FINE", 100.0))

        assertTrue(
            warningLines().none { it.contains("FINE") },
            "a serviceable radius must not warn, got: ${warningLines()}",
        )
    }

    @Test
    fun `a polygon is not judged on its radius`() {
        // Polygons are evaluated point-in-polygon; radius does not participate,
        // and they are stored with radius 0.
        geoManager.addGeofence(
            mapOf(
                "identifier" to "POLY",
                "latitude" to 0.0,
                "longitude" to 0.0,
                "radius" to 0.0,
                "vertices" to listOf(
                    listOf(10.7879, 76.6841),
                    listOf(10.7881, 76.6841),
                    listOf(10.7881, 76.6843),
                ),
            ),
        )

        assertTrue(
            warningLines().none { it.contains("POLY") },
            "a polygon must not be warned about its radius, got: ${warningLines()}",
        )
    }
}
