package com.ikolvi.tracelet.sdk.motion

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
import com.ikolvi.tracelet.sdk.service.LocationService
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
import org.junit.After
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
 * Regression test for GitHub issue #409:
 *   "a stationary start locks the SMART coordinator into a live stream, so
 *    continuous GPS runs forever while parked"
 *
 * The Rust core only emits the stop action when it believes the posture is
 * Continuous (`state/smart_motion_coordinator.rs:105`). `syncCurrentMode()` read
 * that posture from `stateManager.isMoving` alone, so a session resuming
 * stationary while a stream was still live wrote StationaryPeriodic into a
 * coordinator whose engine was streaming — and every later stationary decision
 * returned `None`. The field report shows the consequence: six unbroken minutes
 * of 2-second GPS fixes at 3 m accuracy, every one of them `is_moving: false`,
 * on a phone parked on a desk.
 *
 * The two directions are one bug seen from two sides, so both are pinned here.
 * Fixing #344 by reading `isMoving` created this one; fixing this one by reading
 * the engine instead would recreate #344.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P])
class SmartMotionPostureSyncTest {

    private lateinit var context: Context
    private lateinit var config: ConfigManager
    private lateinit var state: StateManager
    private lateinit var engine: LocationEngine
    private lateinit var coordinator: SmartMotionCoordinator
    private val client = PostureLocationClient()

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        shadowOf(context as Application).grantPermissions(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        )
        TraceletServices.setProvider(PostureServicesProvider(client))

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
        // These drive fixes through the engine as a *running* session does.
        // `onLocationReceived` drops a fix when the session is not enabled,
        // because after `stop()` a straggling delivery is not ours to record
        // (#412) — and an engine streaming into a disabled session is a state
        // production never reaches: `start()` sets this before it starts the
        // engine or asks for the startup fix.
        state.enabled = true
        state.trackingMode = TrackingMode.CONTINUOUS

        engine = LocationEngine(context, config, state, mock<TraceletEventSender>())
        coordinator = SmartMotionCoordinator(
            context, config, state, mock<TraceletEventSender>(),
            engine, mock<MotionDetector>(), mock<TraceletLogger>(),
        )
    }

    @After
    fun tearDown() {
        engine.stop()
        LocationService.stopStationaryTimer()
        TraceletServices.setProvider(null)
        ConfigManager.resetInstance()
    }

    private fun idle() = shadowOf(Looper.getMainLooper()).idle()

    /**
     * The reported failure. A live stream plus a stationary committed pace is
     * exactly the state a `ready()` takeover lands in after the boot engine has
     * handed over.
     */
    @Test
    fun `a stationary pace with a live stream still reaches the stationary switch`() {
        engine.start()
        idle()
        assertTrue("precondition: the stream is live", engine.isTracking)

        state.isMoving = false
        coordinator.syncCurrentMode()

        // Both inputs stationary — the decision that used to return None.
        coordinator.onSpeedStateChange(false)
        idle()

        assertFalse(
            "#409: the coordinator must still see the posture as Continuous when a " +
                "stream is live, or it emits no stop action and GPS runs at the " +
                "configured interval for the rest of the session",
            engine.isTracking,
        )
    }

    /**
     * The field report, start to finish: a stationary start that also has a
     * fence too small for the OS to resolve.
     *
     * The pace branch runs no stream by design, and then the #357 branch starts
     * one so the fence has something to be decided from — leaving a full-rate
     * stream (`distanceFilter=0.0m interval=2000ms`) on a device that never
     * moved, with the location indicator lit for the whole session. Nothing the
     * session could say would stop it: the coordinator was parked, and both
     * motion inputs were already stationary, which the core dedupes to NONE.
     */
    @Test
    fun `a stationary start that inherited a fence stream is parked`() {
        state.isMoving = false
        coordinator.syncCurrentMode()

        // The #357 branch: the session starts stationary, so this is the only
        // thing running.
        engine.start()
        idle()
        assertTrue("precondition: the in-app fence evaluator's stream is live", engine.isTracking)

        // A motion input re-asserting what it already said cannot rescue this —
        // the core answers a repeat with NONE, so the stream survives it.
        coordinator.onSpeedStateChange(false)
        idle()
        assertTrue(
            "precondition: no transition is available to stop the stream",
            engine.isTracking,
        )

        coordinator.reconcilePosture()
        idle()

        assertFalse(
            "#409: a session whose engine is streaming while both motion inputs " +
                "say stationary must be parked into the stationary schedule — the " +
                "fence is still evaluated there, at the stationary cadence rather " +
                "than at 2-second full rate",
            engine.isTracking,
        )
    }

    /** The control: reconciling must not park a session that is genuinely moving. */
    @Test
    fun `reconciling a moving session leaves its stream alone`() {
        state.isMoving = true
        coordinator.syncCurrentMode()
        coordinator.onAccelStateChange(true)
        engine.start()
        idle()

        coordinator.reconcilePosture()
        idle()

        assertTrue(
            "the accelerometer says the device is moving — the OR holds and the " +
                "stream stays open",
            engine.isTracking,
        )
    }

    /**
     * The same wedge one layer down, and what the #409 example card actually
     * ran into: the decision was reached and then dropped on the floor.
     *
     * `onSpeedStateChange(false)` with a *moving* accelerometer and a near-zero
     * resolved speed reads the accelerometer as hand tremor and overrides it to
     * stationary. That override is a real accel transition, and when the speed
     * flag is already stationary it is the transition that carries the whole
     * stop decision — `evaluate_state` answers it with
     * SWITCH_TO_STATIONARY_PERIODIC. The return value went unread, and the
     * `onSpeedStateChange` that followed deduped to NONE because the flag it
     * would have flipped was already false. Nothing was handled, the engine was
     * never told, and continuous GPS ran on a parked device.
     *
     * A stale stationary speed flag is not exotic: `isSpeedMoving` is
     * process-lived state behind the FFI, and until this fix only a
     * *non*-forced start re-asserted it, so any session that parked handed the
     * next forced-moving one a `false` it could never clear.
     */
    @Test
    fun `a tremor override with a stale speed flag still stops the stream`() {
        // A previous session that parked stationary.
        state.isMoving = false
        coordinator.syncCurrentMode()
        coordinator.onSpeedStateChange(false)
        idle()
        assertFalse("precondition: the speed input is stale-stationary", coordinator.isSpeedMoving)

        // The next session: a moving pace, a live stream, the accelerometer
        // seeded moving exactly as start() seeds it.
        state.isMoving = true
        coordinator.syncCurrentMode()
        coordinator.onAccelStateChange(true)
        engine.start()
        idle()
        assertTrue("precondition: the stream is live", engine.isTracking)
        assertTrue("precondition: only the accelerometer holds the OR up", coordinator.isAccelMoving)

        // A phone lying on a desk: fixes keep arriving, all at ~0 m/s.
        deliverFix(speedMps = 0f)
        assertTrue(
            "precondition: a resolved near-zero speed is what reads a moving " +
                "accelerometer as hand tremor",
            engine.getLastLocation() != null && engine.lastEffectiveSpeed <= 0.15,
        )

        coordinator.onSpeedStateChange(false)
        idle()

        assertFalse(
            "#409: the tremor override produced the stationary switch and it was " +
                "discarded, so the stop was never handled and GPS kept running " +
                "for the rest of the session",
            engine.isTracking,
        )
    }

    /**
     * The override must not fire on a device that is genuinely moving slowly —
     * the walking case #333 protects. Pinned alongside the fix above so
     * handling the action cannot quietly become "park on any low-speed fix".
     */
    @Test
    fun `a slow walk keeps the stream open`() {
        state.isMoving = true
        coordinator.syncCurrentMode()
        coordinator.onAccelStateChange(true)
        engine.start()
        idle()

        deliverFix(speedMps = 0.8f) // above the 0.15 m/s tremor threshold
        assertTrue(
            "precondition: the walk is resolved above the tremor threshold",
            engine.lastEffectiveSpeed > 0.15,
        )

        coordinator.onSpeedStateChange(false)
        idle()

        assertTrue(
            "the accelerometer is the one telling the truth below the speed " +
                "threshold — overruling it here is #333",
            engine.isTracking,
        )
    }

    /**
     * The half #409, #412 and #414 left open, and what the field report shows:
     * the park itself moves the session out of the branch that can park it.
     *
     * Android's stationary switch writes `trackingMode = PERIODIC` — iOS
     * deliberately leaves it alone — so once a session has parked *once*, every
     * later `syncCurrentMode()` takes the PERIODIC branch, which used to answer
     * STATIONARY_PERIODIC without ever looking at the engine. That is the
     * posture the core already holds, and `evaluate_state` emits the stop only
     * from Continuous, so the reconcile returned NONE.
     *
     * Both routes that open a stream behind the coordinator run *after* the
     * first park in a real session — a fence added from the map
     * (`applyGeofenceEvaluationCadence`, #357) and an OS wake-up near an in-app
     * fence (`resumeStreamForEvaluator`, #414) — and both then ask for exactly
     * this reconcile. The device trace is a phone on a desk reporting
     * `Is moving: false` in `periodic` mode while delivering a fix every two
     * seconds, with the location indicator lit until tracking was stopped.
     */
    @Test
    fun `a stream opened after the session has parked is still parked again`() {
        // The park: this is what writes PERIODIC, exactly as a real session does.
        // The core defaults `is_speed_moving` to true, so the speed machine has
        // to report stationary before both halves of the OR are down.
        state.isMoving = false
        coordinator.syncCurrentMode()
        engine.start()
        idle()
        coordinator.onSpeedStateChange(false)
        coordinator.reconcilePosture()
        idle()
        assertFalse("precondition: the session parked", engine.isTracking)
        org.junit.Assert.assertEquals(
            "precondition: the stationary switch moved the session mode to PERIODIC",
            TrackingMode.PERIODIC,
            state.trackingMode,
        )

        // A fence too small for the OS is added from the map: #357 opens a
        // stream for the in-app evaluator, behind the coordinator's back.
        engine.start()
        idle()
        assertTrue("precondition: the evaluator's stream is live", engine.isTracking)

        coordinator.reconcilePosture()
        idle()

        assertFalse(
            "#412/#414: both motion inputs still say stationary, so the borrowed " +
                "stream must be handed back — the session mode being PERIODIC is " +
                "what the park itself wrote, not evidence that nothing is running",
            engine.isTracking,
        )
    }

    /**
     * The control for the branch above: a parked session whose device really did
     * start moving keeps the stream it was given.
     */
    @Test
    fun `a parked session that is moving again keeps its stream`() {
        state.isMoving = false
        coordinator.syncCurrentMode()
        engine.start()
        idle()
        coordinator.onSpeedStateChange(false)
        coordinator.reconcilePosture()
        idle()
        assertFalse("precondition: the session parked", engine.isTracking)

        // The wake-up: the accelerometer fires and the coordinator resumes.
        coordinator.onAccelStateChange(true)
        idle()
        assertTrue("precondition: the wake-up resumed the stream", engine.isTracking)

        coordinator.reconcilePosture()
        idle()

        assertTrue(
            "an input that says moving holds the OR up — reconciling must not " +
                "park a session the device is actually driving",
            engine.isTracking,
        )
    }

    /**
     * Feeds one accepted fix so `resolvedSpeed` is a resolved ~0 rather than
     * `null`, which the coordinator reads as *unknown* and refuses to override
     * the accelerometer on (#333).
     */
    private fun deliverFix(speedMps: Float) {
        client.callback?.onLocationResult(
            listOf(
                Location("fused").apply {
                    latitude = 10.787929
                    longitude = 76.684183
                    accuracy = 5f
                    speed = speedMps
                    time = System.currentTimeMillis()
                    elapsedRealtimeNanos = android.os.SystemClock.elapsedRealtimeNanos()
                },
            ),
        )
        idle()
    }

    /**
     * #344, which the #409 fix must not undo: a session that starts stationary
     * with no stream has to be able to wake up. Reading the posture off the
     * engine alone would write Continuous here and deafen the accelerometer.
     */
    @Test
    fun `a stationary start with no stream can still be woken`() {
        assertFalse("precondition: no stream yet", engine.isTracking)

        state.isMoving = false
        coordinator.syncCurrentMode()

        val action = coordinator.onAccelStateChange(true)

        org.junit.Assert.assertEquals(
            "#344: a parked posture must produce the wake-up on the first real " +
                "accelerometer event",
            uniffi.tracelet_core.CoordinatorAction.SWITCH_TO_CONTINUOUS,
            action,
        )
    }

    /**
     * A moving start syncs before `start()` has subscribed anything, so the
     * committed pace is the only signal available at that instant. Dropping it
     * in favour of the engine would park the coordinator and wedge the stream
     * open — #409 again, by a different route.
     */
    @Test
    fun `a moving start syncs Continuous before the engine has subscribed`() {
        assertFalse("precondition: syncCurrentMode runs before start()", engine.isTracking)

        state.isMoving = true
        coordinator.syncCurrentMode()
        engine.start()
        idle()

        coordinator.onSpeedStateChange(false)
        idle()

        assertFalse(
            "the posture came from the committed pace, so the stationary decision " +
                "still lands and the stream stops",
            engine.isTracking,
        )
    }

}

private class PostureLocationClient : TraceletLocationClient {
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

private class PostureServicesProvider(
    private val client: TraceletLocationClient,
) : TraceletServicesProvider {
    override fun getLocationClient(context: Context) = client
    override fun getGeofencingClient(context: Context) = mock<TraceletGeofencingClient>()
    override fun getActivityRecognitionClient(context: Context) =
        mock<TraceletActivityRecognitionClient>()
    override fun getEventExtractor() = mock<TraceletEventExtractor>()
}
