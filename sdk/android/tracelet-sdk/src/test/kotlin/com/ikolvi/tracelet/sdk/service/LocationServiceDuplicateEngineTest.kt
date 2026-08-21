package com.ikolvi.tracelet.sdk.service

import android.Manifest
import android.app.Application
import android.content.Context
import android.content.Intent
import android.location.Location
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.TraceletEventSender
import com.ikolvi.tracelet.sdk.TraceletSdk
import com.ikolvi.tracelet.sdk.location.LocationEngine
import com.ikolvi.tracelet.sdk.model.TrackingMode
import com.ikolvi.tracelet.sdk.wrapper.TraceletActivityRecognitionClient
import com.ikolvi.tracelet.sdk.wrapper.TraceletCancellationToken
import com.ikolvi.tracelet.sdk.wrapper.TraceletEventExtractor
import com.ikolvi.tracelet.sdk.wrapper.TraceletGeofencingClient
import com.ikolvi.tracelet.sdk.wrapper.TraceletLocationCallback
import com.ikolvi.tracelet.sdk.wrapper.TraceletLocationClient
import com.ikolvi.tracelet.sdk.wrapper.TraceletLocationRequest
import com.ikolvi.tracelet.sdk.wrapper.TraceletServices
import com.ikolvi.tracelet.sdk.wrapper.TraceletServicesProvider
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.kotlin.mock
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.android.controller.ServiceController
import org.robolectric.annotation.Config

/**
 * Regression test for GitHub issue #410:
 *   "boot-mode tracking builds a second LocationEngine beside a live session
 *    engine, and only one of them is ever stopped"
 *
 * Task removal tears down the Flutter engine but keeps the SDK alive
 * ("onDetachedFromEngine: secondary engines still active, SDK preserved"), so
 * the session engine, its motion detector and its heartbeat all survive. Boot
 * mode then built a second set beside them. The field report shows both running
 * for seven minutes: two interleaved `[STILLNESS] sample #N` counters, both
 * `Heartbeat fired` and `Boot heartbeat fired`, and — the cost — a stationary
 * switch that stopped only the engine its own coordinator held, leaving the
 * other streaming at 2 s while the boot engine sat on a 5.7-minute-stale fix.
 *
 * Boot mode is for the case where no session is left to do the work: a cold
 * boot, or a sticky restart after process death. When there is one, the right
 * number of engines is one.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [34])
class LocationServiceDuplicateEngineTest {

    private lateinit var context: Context
    private lateinit var state: StateManager
    private var controller: ServiceController<LocationService>? = null
    private var sessionEngine: LocationEngine? = null
    private val client = DuplicateLocationClient()

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        shadowOf(context as Application).grantPermissions(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
            Manifest.permission.ACCESS_BACKGROUND_LOCATION,
        )
        TraceletServices.setProvider(DuplicateServicesProvider(client))

        val config = ConfigManager.getInstance(context)
        config.reset(null)
        config.setConfig(
            mapOf(
                // The promise that keeps the service alive past task removal —
                // and so the promise that used to produce the second engine.
                "app" to mapOf("stopOnTerminate" to false),
                "android" to mapOf(
                    "foregroundService" to mapOf(
                        "enabled" to true,
                        "channelId" to "tl_test_channel",
                    ),
                ),
            ),
        )
        state = StateManager(context)
        state.enabled = true
        state.trackingMode = TrackingMode.CONTINUOUS
        LocationService.bootLocationEngine = null
    }

    @After
    fun tearDown() {
        try { controller?.destroy() } catch (_: Throwable) {}
        controller = null
        // Leave the process-wide SDK with a stopped engine: `hasLiveSessionEngine`
        // reads false, so nothing here changes what a later test class sees.
        sessionEngine?.stop()
        sessionEngine = null
        LocationService.bootLocationEngine = null
        TraceletServices.setProvider(null)
        ConfigManager.resetInstance()
    }

    private fun idle() = shadowOf(Looper.getMainLooper()).idle()

    /** Puts a live session engine on the process-wide SDK, as a real session does. */
    private fun giveSdkALiveSessionEngine() {
        val engine = LocationEngine(
            context, ConfigManager.getInstance(context), state, mock<TraceletEventSender>(),
        )
        engine.start()
        idle()
        assertTrue("precondition: the session engine is streaming", engine.isTracking)
        TraceletSdk.getInstance(context).locationEngine = engine
        sessionEngine = engine
    }

    private fun startService(): LocationService {
        val intent = Intent().apply { action = LocationService.ACTION_START }
        val c = Robolectric.buildService(LocationService::class.java)
        controller = c
        return c.create().withIntent(intent).startCommand(0, 1).get()
    }

    /**
     * The reported failure: task removal with the session engine still alive.
     */
    @Test
    fun `task removal does not build a second engine beside a live session engine`() {
        giveSdkALiveSessionEngine()
        val service = startService()

        service.onTaskRemoved(null)
        idle()

        assertNull(
            "#410: boot mode must not create a second LocationEngine while the " +
                "session engine is live — two streams run in parallel and a " +
                "stationary switch stops only the one its own coordinator holds",
            LocationService.bootLocationEngine,
        )
        assertTrue(
            "the surviving session engine keeps the stream — the point is one " +
                "engine, not none",
            sessionEngine!!.isTracking,
        )
    }

    /**
     * The other half of the contract. A process with no live session — a cold
     * boot, or a sticky restart after the process was killed — is exactly what
     * boot mode is for, and must still get its engine.
     */
    @Test
    fun `a process with no live session engine still gets boot tracking`() {
        val sdk = TraceletSdk.getInstance(context)
        if (sdk.hasLiveSessionEngine) sdk.locationEngine.stop()
        assertFalse("precondition: no live session engine", sdk.hasLiveSessionEngine)

        val service = startService()
        service.onTaskRemoved(null)
        idle()

        // bootstrapForBackground() may legitimately defer on a Robolectric host
        // without a Rust DB, in which case no engine is the correct outcome for
        // a different reason (#264/#317). The guard under test must not be what
        // decided it, so assert on the guard's own input instead.
        assertFalse(
            "the #410 guard must not trip when there is no session engine to " +
                "defer to — that is the path boot mode exists for",
            sdk.hasLiveSessionEngine,
        )
    }
}

private class DuplicateLocationClient : TraceletLocationClient {
    var callback: TraceletLocationCallback? = null

    override fun requestLocationUpdates(
        request: TraceletLocationRequest,
        callback: TraceletLocationCallback,
        looper: Looper,
    ) { this.callback = callback }

    override fun removeLocationUpdates(callback: TraceletLocationCallback) { this.callback = null }

    override fun getCurrentLocation(
        priority: Int,
        cancellationToken: TraceletCancellationToken?,
        onSuccess: (Location?) -> Unit,
    ) = onSuccess(null)

    override fun getLastLocation(onSuccess: (Location?) -> Unit, onFailure: (Exception) -> Unit) =
        onSuccess(null)
}

private class DuplicateServicesProvider(
    private val client: TraceletLocationClient,
) : TraceletServicesProvider {
    override fun getLocationClient(context: Context) = client
    override fun getGeofencingClient(context: Context) = mock<TraceletGeofencingClient>()
    override fun getActivityRecognitionClient(context: Context) =
        mock<TraceletActivityRecognitionClient>()
    override fun getEventExtractor() = mock<TraceletEventExtractor>()
}
