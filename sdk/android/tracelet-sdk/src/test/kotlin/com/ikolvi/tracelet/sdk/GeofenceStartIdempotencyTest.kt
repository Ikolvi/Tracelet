package com.ikolvi.tracelet.sdk

import android.Manifest
import android.app.Application
import android.content.Context
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.sdk.model.TrackingMode
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import kotlin.test.assertEquals

/**
 * Regression for #292 (integration): calling `startGeofences()` again while
 * already tracking in GEOFENCES mode — the common "refresh my fences on every
 * app launch" pattern — must be treated as a resume and must NOT wipe the
 * persisted high-accuracy inside-set. Otherwise a stationary device inside a
 * fence re-emits ENTER (a false attendance punch-in) on every launch.
 *
 * A genuine fresh start (first enable, or after `stop()`) is a new session and
 * DOES reset the inside-set so the initial-entry ENTER fires exactly once.
 *
 * The persisted set is observed directly through its SharedPreferences store
 * (`com.tracelet.geofence.state` / `knownInsideIds`).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class GeofenceStartIdempotencyTest {

    private lateinit var context: Context
    private lateinit var sdk: TraceletSdk

    private val prefsName = "com.tracelet.geofence.state"
    private val key = "knownInsideIds"

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()

        // Isolate from any process-wide singleton state a prior test left behind
        // (enabled/trackingMode live in com.tracelet.state; the inside-set in
        // com.tracelet.geofence.state).
        context.getSharedPreferences("com.tracelet.state", Context.MODE_PRIVATE)
            .edit().clear().commit()
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit().clear().commit()

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
        try { sdk.stop() } catch (_: Exception) {}
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE).edit().clear().commit()
        idle()
        ConfigManager.resetInstance()
    }

    private fun idle() = shadowOf(Looper.getMainLooper()).idle()

    private fun prefs() = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)

    private fun seedInside(vararg ids: String) {
        prefs().edit().putStringSet(key, ids.toSet()).commit()
    }

    private fun persistedInside(): Set<String> =
        prefs().getStringSet(key, emptySet()) ?: emptySet()

    @Test
    fun `fresh start clears inside-state and a redundant re-start preserves it`() {
        var ready = false
        sdk.ready(mapOf("geofenceModeHighAccuracy" to true)) { ready = true }
        idle()
        assert(ready)

        // Force a deterministic "not yet tracking" baseline: TraceletSdk is a
        // process-wide singleton and a prior test's drained async work can leave
        // enabled=true on it. StateManager reads this straight from prefs.
        context.getSharedPreferences("com.tracelet.state", Context.MODE_PRIVATE)
            .edit().putBoolean("enabled", false).commit()

        // A stale inside-set from before. The FIRST startGeofences() is a genuine
        // transition into geofence mode (not yet enabled) → a fresh session that
        // MUST reset the inside-set so the initial-entry ENTER fires once.
        seedInside("STALE_ZONE")
        sdk.startGeofences()
        idle()
        assertEquals(TrackingMode.GEOFENCES, sdk.stateManager.trackingMode)
        assertEquals(
            emptySet(),
            persistedInside(),
            "a fresh start must clear the persisted inside-set so the initial ENTER fires",
        )

        // The device ENTERs the fence.
        seedInside("OFFICE_ZONE")

        // Redundant re-start: the app calls startGeofences() again (e.g. on the
        // next launch to "refresh" fences) while already enabled + GEOFENCES.
        // This is NOT a fresh session — it must be treated as a resume and must
        // NOT wipe the inside-set, or a stationary device re-ENTERs (#292).
        sdk.startGeofences()
        idle()
        assertEquals(
            setOf("OFFICE_ZONE"),
            persistedInside(),
            "a redundant startGeofences() must preserve the persisted inside-set (#292)",
        )
    }
}
