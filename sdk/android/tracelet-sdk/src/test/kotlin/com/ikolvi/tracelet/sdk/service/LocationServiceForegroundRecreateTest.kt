package com.ikolvi.tracelet.sdk.service

import android.app.ActivityManager
import android.app.Application
import android.content.Context
import android.content.Intent
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.ProcessLifecycleOwner
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.sdk.ConfigManager
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.android.controller.ServiceController
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * #436: a START_STICKY restart creates the service record in the background, and
 * Android denies that record location for its whole life (#405). When the app
 * came to the foreground, `ready()` -> `start()` sent ACTION_START to that same
 * record, so opening the app did not recover tracking either. A foreground
 * `start()` must drop the background-created record so a new one is created.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [34])
class LocationServiceForegroundRecreateTest {

    private lateinit var context: Context
    private var controller: ServiceController<LocationService>? = null
    private val lifecycle get() = ProcessLifecycleOwner.get().lifecycle as LifecycleRegistry

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        ConfigManager.getInstance(context).reset(null)
        ConfigManager.getInstance(context).setConfig(mapOf("fg_enabled" to true))
        lifecycle.currentState = Lifecycle.State.CREATED
    }

    @After
    fun tearDown() {
        try { controller?.destroy() } catch (_: Throwable) {}
        controller = null
        lifecycle.currentState = Lifecycle.State.CREATED
        ConfigManager.getInstance(context).reset(null)
    }

    /** A service created while the process is only a background service. */
    private fun createInBackground() {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val info = ActivityManager.RunningAppProcessInfo(context.packageName, android.os.Process.myPid(), emptyArray())
        info.importance = ActivityManager.RunningAppProcessInfo.IMPORTANCE_SERVICE
        info.uid = android.os.Process.myUid()
        shadowOf(am).setProcesses(listOf(info))
        val c = Robolectric.buildService(LocationService::class.java)
        controller = c
        c.create().withIntent(Intent().apply { action = LocationService.ACTION_START }).startCommand(0, 1)
        assertEquals(false, LocationService.foregroundServiceHealth()["serviceStartedInForeground"])
    }

    @Test
    fun `a foreground start replaces a background-created service`() {
        createInBackground()
        lifecycle.currentState = Lifecycle.State.STARTED

        LocationService.start(context)

        val stopped = shadowOf(context as Application).nextStoppedService
        assertEquals(
            LocationService::class.java.name, stopped?.component?.className,
            "the background-created record must be stopped so Android creates a new one from the foreground (#436)",
        )
    }

    @Test
    fun `a background start leaves the running service alone`() {
        createInBackground()

        LocationService.start(context)

        assertNull(
            shadowOf(context as Application).nextStoppedService,
            "re-creating from the background would only produce another location-blind record",
        )
    }
}
