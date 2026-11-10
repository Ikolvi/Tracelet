package com.ikolvi.tracelet.sdk.receiver

import android.app.Application
import android.content.Context
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.service.LocationService
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull

/**
 * Verifies that `startOnBoot` means "survive reboots", not "auto-start":
 * a reboot must only resume tracking that was still enabled when the
 * device shut down. If the user explicitly called stop(), BOOT_COMPLETED
 * must not resurrect tracking.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [33])
class BootReceiverTest {

    private lateinit var context: Context

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        shadowOf(context as Application).grantPermissions(
            android.Manifest.permission.ACCESS_FINE_LOCATION,
            android.Manifest.permission.ACCESS_BACKGROUND_LOCATION,
        )
        ConfigManager.getInstance(context).setConfig(
            mapOf(
                "startOnBoot" to true,
                "stopOnTerminate" to false,
            ),
        )
    }

    @After
    fun tearDown() {
        StateManager(context).reset()
        ConfigManager.resetInstance()
    }

    @Test
    fun `boot does not resume tracking that was explicitly stopped`() {
        StateManager(context).enabled = false

        BootReceiver().onReceive(context, Intent(Intent.ACTION_BOOT_COMPLETED))

        assertFalse(
            StateManager(context).enabled,
            "BOOT_COMPLETED must not re-enable tracking the user stopped",
        )
        assertNull(
            shadowOf(context as Application).nextStartedService,
            "No tracking service may be started when tracking was stopped",
        )
    }

    @Test
    fun `boot restores the started strategy, not a parked SMART pace (#447)`() {
        val state = StateManager(context)
        state.enabled = true
        state.sessionTrackingMode = com.ikolvi.tracelet.sdk.model.TrackingMode.CONTINUOUS
        // What switchToStationaryPeriodic persists when a SMART session parks.
        state.trackingMode = com.ikolvi.tracelet.sdk.model.TrackingMode.PERIODIC

        BootReceiver().onReceive(context, Intent(Intent.ACTION_BOOT_COMPLETED))

        assertEquals(
            LocationService::class.java.name,
            shadowOf(context as Application).nextStartedService?.component?.className,
            "a start() session must reboot through the service, not a 15-min WorkManager fix (#447)",
        )
    }

    @Test
    fun `boot resumes tracking that was enabled at shutdown`() {
        StateManager(context).enabled = true

        BootReceiver().onReceive(context, Intent(Intent.ACTION_BOOT_COMPLETED))

        val started = shadowOf(context as Application).nextStartedService
        assertNotNull(started, "Tracking service must be restarted on boot")
        assertEquals(
            LocationService::class.java.name,
            started.component?.className,
            "BootReceiver must start the LocationService",
        )
    }
}
