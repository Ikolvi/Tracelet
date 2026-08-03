package com.ikolvi.tracelet.sdk

import android.Manifest
import android.app.Application
import android.content.Context
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Regression for #292 (integration): calling `startGeofences()` again while
 * already tracking in GEOFENCES mode — the common "refresh my fences on every
 * app launch" pattern — must be treated as a resume and must NOT wipe the
 * high-accuracy inside-set. Otherwise a stationary device inside a fence
 * re-emits ENTER (a false attendance punch-in) on every launch.
 *
 * Driven through the real SDK pipeline and asserted on emitted ENTER events, so
 * it is robust to the process-wide singleton's in-memory-vs-persisted state.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class GeofenceStartIdempotencyTest {

    private lateinit var context: Context
    private lateinit var sdk: TraceletSdk
    private val captured = mutableListOf<Map<String, Any?>>()

    private val centerLat = 10.787929
    private val centerLng = 76.684183
    private val radius = 50.0

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()

        androidx.work.testing.WorkManagerTestInitHelper.initializeTestWorkManager(
            context,
            androidx.work.Configuration.Builder()
                .setExecutor(androidx.work.testing.SynchronousExecutor())
                .build(),
        )

        shadowOf(context as Application).grantPermissions(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
            Manifest.permission.ACCESS_BACKGROUND_LOCATION,
        )

        sdk = TraceletSdk.getInstance(context)
        sdk.setEventSender(ListenerEventSender())
        sdk.initialize()
    }

    @After
    fun tearDown() {
        try { sdk.geofenceManager.onGeofenceEvent = null } catch (_: Exception) {}
        try { sdk.removeGeofences() } catch (_: Exception) {}
        try { sdk.stop() } catch (_: Exception) {}
        idle()
        ConfigManager.resetInstance()
    }

    private fun idle() = shadowOf(Looper.getMainLooper()).idle()

    private fun enterCount(): Int = captured.count {
        ((it["geofence"] as? Map<*, *>)?.get("action") as? String) == "ENTER"
    }

    @Test
    fun `a redundant startGeofences does not re-ENTER a stationary device`() {
        var ready = false
        sdk.ready(mapOf("geofenceModeHighAccuracy" to true)) { ready = true }
        idle()
        assert(ready)
        // Guard against config leaking from a prior test in the shared singleton:
        // startGeofences() only resets/preserves inside-state in high-accuracy mode.
        assertTrue(
            sdk.configManager.getGeofenceModeHighAccuracy(),
            "test precondition: geofenceModeHighAccuracy must be active",
        )

        // A fence the device is sitting inside.
        sdk.addGeofence(
            mapOf(
                "identifier" to "OFFICE",
                "latitude" to centerLat,
                "longitude" to centerLng,
                "radius" to radius,
            ),
        )
        val mgr = sdk.geofenceManager
        mgr.onGeofenceEvent = { captured.add(it) }
        // Clean, synced baseline (in-memory evaluator + persisted set).
        mgr.resetHighAccuracyInsideState()
        captured.clear()

        // Start geofences and register the initial entry.
        sdk.startGeofences()
        idle()
        mgr.evaluateHighAccuracyProximity(centerLat, centerLng, 8.0)
        assertEquals(1, enterCount(), "the first fix inside must ENTER once")

        // The app calls startGeofences() again while already enabled + GEOFENCES
        // (the "refresh fences on every launch" pattern). It must be treated as a
        // resume and preserve the inside-set — the stationary device must NOT
        // re-ENTER (#292). Were it treated as a fresh start it would reset the
        // set and this fix would ENTER a second time.
        sdk.startGeofences()
        idle()
        mgr.evaluateHighAccuracyProximity(centerLat, centerLng, 8.0)
        assertEquals(1, enterCount(), "a redundant startGeofences() must not re-emit ENTER")
    }
}
