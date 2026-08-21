package com.ikolvi.tracelet.sdk.service

import android.Manifest
import android.app.Application
import android.content.Context
import android.location.Location
import android.os.Build
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.TraceletEventSender
import com.ikolvi.tracelet.sdk.location.LocationEngine
import com.ikolvi.tracelet.sdk.model.TrackingMode
import com.ikolvi.tracelet.sdk.motion.MotionDetector
import com.ikolvi.tracelet.sdk.motion.SmartMotionCoordinator
import com.ikolvi.tracelet.sdk.util.TraceletLogger
import com.ikolvi.tracelet.sdk.wrapper.TraceletActivityRecognitionClient
import com.ikolvi.tracelet.sdk.wrapper.TraceletCancellationToken
import com.ikolvi.tracelet.sdk.wrapper.TraceletEventExtractor
import com.ikolvi.tracelet.sdk.wrapper.TraceletGeofencingClient
import com.ikolvi.tracelet.sdk.wrapper.TraceletLocationCallback
import com.ikolvi.tracelet.sdk.wrapper.TraceletLocationClient
import com.ikolvi.tracelet.sdk.wrapper.TraceletLocationRequest
import com.ikolvi.tracelet.sdk.wrapper.TraceletServices
import com.ikolvi.tracelet.sdk.wrapper.TraceletServicesProvider
import java.time.Duration
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.kotlin.mock
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Regression test for GitHub issue #414:
 *   "an in-app fence wake-up promotes the session to moving, so a parked device
 *    streams GPS for the rest of its life"
 *
 * A fence too small for the OS to resolve is registered inflated, and the
 * transition the OS fires is only a *hint* that we are near it — the crossing
 * itself is decided in-app, from the location stream (#355). Claiming that
 * wake-up used to run through [LocationService.switchToContinuous], which is a
 * **motion** transition: it writes `isMoving = true`, flips the tracking mode,
 * and cancels the stationary schedule.
 *
 * Nothing about being near a fence says the device is moving, and the field
 * report shows the cost — a phone on a desk whose coordinator had just parked
 * it:
 *
 *   smart-motion: switching to STATIONARY_PERIODIC — accelMoving=false speedMoving=false
 *   [geofence] wake-up from the OS near an in-app fence — resuming the location stream
 *   location stream: continuous updates starting — distanceFilter=0.0m interval=2000ms
 *
 * From there the session reported `isMoving=true` for the rest of its life, so
 * every later resume read that pace, forced the speed machine back to MOVING,
 * and left both coordinator inputs moving — no stationary decision was ever
 * available to stop the stream.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P])
class LocationServiceEvaluatorStreamTest {

    private lateinit var context: Context
    private lateinit var config: ConfigManager
    private lateinit var state: StateManager
    private lateinit var engine: LocationEngine
    private val client = EvaluatorLocationClient()

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        shadowOf(context as Application).grantPermissions(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        )
        TraceletServices.setProvider(EvaluatorServicesProvider(client))

        config = ConfigManager.getInstance(context)
        config.reset(null)
        // The stationary switch runs through LocationService when the foreground
        // service is enabled, which is the path a real Android session takes.
        config.setConfig(
            mapOf(
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
        state.isMoving = false

        engine = LocationEngine(context, config, state, mock<TraceletEventSender>())
    }

    @After
    fun tearDown() {
        LocationService.cancelEvaluatorWindow()
        LocationService.stopStationaryTimer()
        LocationService.bootSmartMotionCoordinator = null
        engine.stop()
        TraceletServices.setProvider(null)
        ConfigManager.resetInstance()
    }

    private fun idle() = shadowOf(Looper.getMainLooper()).idle()

    @Test
    fun `the evaluator wake-up borrows the stream without claiming the device moved`() {
        LocationService.resumeStreamForEvaluator(engine, state)
        idle()

        assertTrue(
            "the evaluator needs the stream — that much the wake-up is for",
            engine.isTracking,
        )
        assertFalse(
            "#414: being near a fence is not a motion event. Writing the pace " +
                "here made every later resume force the speed machine back to " +
                "MOVING, so the session could never stand itself down again",
            state.isMoving,
        )
        assertEquals(
            "and the session mode is not the wake-up's to change either",
            TrackingMode.CONTINUOUS,
            state.trackingMode,
        )
    }

    /**
     * The control, and the reason the wake-up needed its own path: the motion
     * switch really does commit a pace, which is right when a motion input asked
     * for it and wrong when a fence did.
     */
    @Test
    fun `the motion switch still commits the pace`() {
        LocationService.switchToContinuous(engine, state)
        idle()

        assertTrue(engine.isTracking)
        assertTrue("a motion wake-up is exactly what does claim it", state.isMoving)
        assertEquals(TrackingMode.CONTINUOUS, state.trackingMode)
    }

    /**
     * The borrowed stream is returned. Without a bound the wake-up would still
     * cost the session: both motion inputs are already stationary, so no
     * transition is available and nothing else would ever stop it.
     */
    @Test
    fun `the borrowed stream is handed back when the window closes`() {
        val coordinator = SmartMotionCoordinator(
            context, config, state, mock<TraceletEventSender>(),
            engine, mock<MotionDetector>(), mock<TraceletLogger>(),
        )
        // A parked session: the pace is stationary and so is the speed machine.
        coordinator.syncCurrentMode()
        coordinator.onSpeedStateChange(false)
        idle()
        LocationService.bootSmartMotionCoordinator = coordinator

        LocationService.resumeStreamForEvaluator(engine, state)
        idle()
        assertTrue("precondition: the evaluator has the stream", engine.isTracking)

        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(61))

        assertFalse(
            "#414: the window closed and both inputs still say stationary, so the " +
                "cadence goes back to the stationary schedule instead of holding " +
                "full-rate GPS open for the rest of the session",
            engine.isTracking,
        )
    }
}

private class EvaluatorLocationClient : TraceletLocationClient {
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

private class EvaluatorServicesProvider(
    private val client: TraceletLocationClient,
) : TraceletServicesProvider {
    override fun getLocationClient(context: Context) = client
    override fun getGeofencingClient(context: Context) = mock<TraceletGeofencingClient>()
    override fun getActivityRecognitionClient(context: Context) =
        mock<TraceletActivityRecognitionClient>()
    override fun getEventExtractor() = mock<TraceletEventExtractor>()
}
