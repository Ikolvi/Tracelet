package com.ikolvi.tracelet.sdk.service

import android.Manifest
import android.app.Application
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.ListenerEventSender
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.TraceletSdk
import com.ikolvi.tracelet.sdk.geofence.GeofenceManager
import com.ikolvi.tracelet.sdk.model.TrackingMode
import com.ikolvi.tracelet.sdk.receiver.GeofenceBroadcastReceiver
import com.ikolvi.tracelet.sdk.wrapper.TraceletGeofencingClient
import com.ikolvi.tracelet.sdk.wrapper.TraceletGeofencingRequest
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows
import org.robolectric.annotation.Config
import kotlin.test.assertTrue

/**
 * Regression for #353 — a `start()` (CONTINUOUS) session with standalone
 * geofences (added via addGeofence()/addGeofences(), which never set
 * trackingMode = GEOFENCES — that mode is only the dedicated geofence-only
 * session started by startGeofences()) must have its geofences re-registered
 * with Play Services after boot/task-removal, exactly like a dedicated
 * startGeofences() session does.
 *
 * `LocationService.startBootTracking()` previously called `reRegisterAll()`
 * only when `trackingMode == TrackingMode.GEOFENCES`, so a continuous-tracking
 * app's geofences — which Play Services clears on every reboot — were never
 * restored, and ENTER/EXIT silently stopped firing forever after the first
 * task removal (paired with the same fix in TraceletSdk.destroyAll()).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class LocationServiceGeofenceRestoreTest {

    private lateinit var context: Context
    private lateinit var config: ConfigManager
    private lateinit var state: StateManager
    private lateinit var serviceController: org.robolectric.android.controller.ServiceController<LocationService>

    /** Records every geofence-registration request so the test can observe
     *  whether reRegisterAll() actually ran, without needing real Play Services. */
    private class RecordingClient : TraceletGeofencingClient {
        val registeredIds = mutableListOf<String>()

        override fun addGeofences(
            request: TraceletGeofencingRequest,
            pendingIntent: PendingIntent,
            onSuccess: () -> Unit,
            onFailure: (Exception) -> Unit,
        ) {
            registeredIds.addAll(request.geofences.map { it.requestId })
            onSuccess()
        }

        override fun removeGeofences(
            pendingIntent: PendingIntent,
            onSuccess: () -> Unit,
            onFailure: (Exception) -> Unit,
        ) { onSuccess() }

        override fun removeGeofences(
            requestIds: List<String>,
            onSuccess: () -> Unit,
            onFailure: (Exception) -> Unit,
        ) { onSuccess() }
    }

    private val recordingClient = RecordingClient()

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        Shadows.shadowOf(context as Application).grantPermissions(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_BACKGROUND_LOCATION,
        )
        config = ConfigManager.getInstance(context)
        config.setConfig(
            mapOf(
                "trackingMode" to 0, // CONTINUOUS — the point of the regression
                "foregroundChannelId" to "test_channel",
                "bootStrategy" to true,
            ),
        )
        state = StateManager(context)
        state.enabled = true
        state.trackingMode = TrackingMode.CONTINUOUS

        // Force the singleton fully initialized up front, persist a geofence
        // directly to its Rust DB, then swap in a manager wired to a recording
        // client. initialize()/bootstrapForBackground() are idempotent (guarded
        // by initStarted), so startBootTracking()'s later call finds init
        // already done and reuses this swapped-in manager instead of
        // overwriting it with a fresh one.
        val sdk = TraceletSdk.getInstance(context)
        assertTrue(sdk.bootstrapForBackground(ListenerEventSender()), "test setup: bootstrap must succeed")
        sdk.rustDatabase?.insertGeofence("issue-353-office", 10.787929, 76.684183, 100.0, null, null)
        sdk.geofenceManager = GeofenceManager(
            context, config, ListenerEventSender(), sdk.rustDatabase, recordingClient,
        )

        serviceController = Robolectric.buildService(LocationService::class.java)
    }

    @After
    fun tearDown() {
        ConfigManager.resetInstance()
        GeofenceBroadcastReceiver.geofenceManager = null
        LocationService.bootLocationEngine?.destroy()
        LocationService.bootLocationEngine = null
        try {
            serviceController.destroy()
        } catch (e: Exception) {}
    }

    @Test
    fun `boot in CONTINUOUS mode re-registers standalone geofences with Play Services`() {
        val intent = Intent(context, LocationService::class.java)
        intent.action = LocationService.ACTION_START
        intent.putExtra("boot_start", true)
        serviceController.create().withIntent(intent).startCommand(0, 1)

        assertTrue(
            recordingClient.registeredIds.contains("issue-353-office"),
            "reRegisterAll() must run on boot/task-removal in CONTINUOUS mode too, " +
                "not only when trackingMode == GEOFENCES (#353)",
        )
    }
}
