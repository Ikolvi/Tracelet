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
import kotlin.test.assertNotNull

/**
 * Regression for #352 — geofence **proximity scope** must be driven from the
 * raw fix stream, not the persistence-filtered one.
 *
 * `GeofenceManager.updateProximity()` is what registers fences with Play
 * Services, so in standard (OS) geofence mode it *is* the whole feature: the
 * SDK detects nothing itself. It used to be wired to
 * `LocationEngine.onLocationUpdate`, which only fires for fixes the Rust
 * processor accepts — so the persistence filter silently decided whether
 * geofencing worked at all, and `onRawGeofenceLocation` was left null whenever
 * `geofenceModeHighAccuracy` was off.
 *
 * 3.8.0's transport-mode auto-tune (#299) made that fatal: a committed `still`
 * mode retunes `maxImpliedSpeed` to 3 m/s and `trackingAccuracy` to 15 m, so
 * the moment the device starts moving every fix is rejected — registration
 * froze and ENTER/EXIT never fired again.
 *
 * These tests assert the wiring itself, because the engine already delivered
 * raw fixes correctly (#297); what was broken was that nothing was listening
 * on that stream in standard mode.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class GeofenceProximityStreamWiringTest {

    private lateinit var context: Context
    private lateinit var sdk: TraceletSdk

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
        try { sdk.removeGeofences() } catch (_: Exception) {}
        try { sdk.stop() } catch (_: Exception) {}
        idle()
        ConfigManager.resetInstance()
    }

    private fun idle() = shadowOf(Looper.getMainLooper()).idle()

    private fun ready(highAccuracy: Boolean) {
        var ready = false
        sdk.ready(mapOf("geofenceModeHighAccuracy" to highAccuracy)) { ready = true }
        idle()
        assert(ready) { "test precondition: ready() must complete" }
    }

    @Test
    fun `standard geofence-only mode drives proximity from the raw stream`() {
        ready(highAccuracy = false)

        sdk.startGeofences()
        idle()

        assertNotNull(
            sdk.locationEngine.onRawGeofenceLocation,
            "standard (OS) geofence mode must listen on the RAW stream — proximity " +
                "scope is what registers fences with Play Services, and riding the " +
                "persistence-filtered stream lets an auto-tuned filter freeze " +
                "registration entirely (#352)",
        )
    }

    @Test
    fun `continuous tracking with geofences drives proximity from the raw stream`() {
        // The configuration in the field report: trackingMode=location
        // (continuous) with standard geofences, auto-tune active.
        ready(highAccuracy = false)

        sdk.start()
        idle()

        assertNotNull(
            sdk.locationEngine.onRawGeofenceLocation,
            "continuous tracking with standard geofences must listen on the RAW " +
                "stream, otherwise a rejected fix freezes Play Services " +
                "registration and ENTER/EXIT never fire (#352)",
        )
    }

    @Test
    fun `high-accuracy geofence mode still drives the raw stream`() {
        // The #297 guarantee must survive the #352 rewiring.
        ready(highAccuracy = true)

        sdk.startGeofences()
        idle()

        assertNotNull(
            sdk.locationEngine.onRawGeofenceLocation,
            "high-accuracy crossings must keep evaluating on the raw stream (#297)",
        )
    }
}
