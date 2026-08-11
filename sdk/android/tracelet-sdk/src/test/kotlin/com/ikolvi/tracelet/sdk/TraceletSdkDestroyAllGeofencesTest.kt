package com.ikolvi.tracelet.sdk

import android.Manifest
import android.app.Application
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.work.Configuration
import androidx.work.testing.SynchronousExecutor
import androidx.work.testing.WorkManagerTestInitHelper
import com.ikolvi.tracelet.sdk.model.TrackingMode
import com.ikolvi.tracelet.sdk.receiver.GeofenceBroadcastReceiver
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows
import org.robolectric.annotation.Config
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Regression for #353 — `destroyAll()` must not unregister standalone
 * geofences (added via addGeofence()/addGeofences(), which never set
 * trackingMode = GEOFENCES) just because the active tracking mode is
 * CONTINUOUS rather than the dedicated geofence-only session mode.
 *
 * `destroyAll()` runs from the plugin's `onDetachedFromEngine` during
 * engine/Activity teardown — i.e. on ordinary task removal, not only process
 * death. It previously gated `keepGeofencesAlive` on
 * `trackingMode == TrackingMode.GEOFENCES` in addition to `keepAlive`, so a
 * `start()` (continuous) session with geofences added via addGeofences() — a
 * fully supported, documented combination — had every geofence unregistered
 * from Play Services (and `GeofenceBroadcastReceiver.geofenceManager` nulled)
 * on the very first task removal, with nothing ever re-registering them.
 * Continuous tracking itself kept working, which is why the geofence feature
 * could die silently.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class TraceletSdkDestroyAllGeofencesTest {

    private lateinit var context: Context

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        Shadows.shadowOf(context as Application).grantPermissions(
            Manifest.permission.ACCESS_FINE_LOCATION,
        )
        WorkManagerTestInitHelper.initializeTestWorkManager(
            context,
            Configuration.Builder().setExecutor(SynchronousExecutor()).build(),
        )
    }

    @After
    fun tearDown() {
        ConfigManager.resetInstance()
        GeofenceBroadcastReceiver.geofenceManager = null
    }

    /** A fresh, isolated SDK instance so this test cannot pollute the process-wide
     *  singleton other test classes rely on. */
    private fun isolatedSdk(): TraceletSdk {
        val ctor = TraceletSdk::class.java.getDeclaredConstructor(Context::class.java)
        ctor.isAccessible = true
        return ctor.newInstance(context.applicationContext) as TraceletSdk
    }

    @Test
    fun `destroyAll keeps standalone geofences alive in CONTINUOUS mode when stopOnTerminate is false`() {
        ConfigManager.getInstance(context).setConfig(mapOf("stopOnTerminate" to false))

        val sdk = isolatedSdk()
        assertTrue(sdk.bootstrapForBackground(ListenerEventSender()), "test setup: bootstrap must succeed")
        sdk.stateManager.enabled = true
        sdk.stateManager.trackingMode = TrackingMode.CONTINUOUS

        sdk.destroyAll()

        assertNotNull(
            GeofenceBroadcastReceiver.geofenceManager,
            "geofences must survive destroyAll() in CONTINUOUS mode when stopOnTerminate=false " +
                "(#353) — otherwise Play Services registrations are wiped and never restored",
        )
    }

    @Test
    fun `destroyAll tears down geofences when stopOnTerminate is true, regardless of mode`() {
        ConfigManager.getInstance(context).setConfig(mapOf("stopOnTerminate" to true))

        val sdk = isolatedSdk()
        assertTrue(sdk.bootstrapForBackground(ListenerEventSender()), "test setup: bootstrap must succeed")
        sdk.stateManager.enabled = true
        sdk.stateManager.trackingMode = TrackingMode.CONTINUOUS

        sdk.destroyAll()

        assertNull(
            GeofenceBroadcastReceiver.geofenceManager,
            "an explicit stopOnTerminate=true must still tear geofences down on teardown",
        )
    }
}
