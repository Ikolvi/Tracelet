package com.ikolvi.tracelet.sdk.motion

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.Looper
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.TraceletEventSender
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import java.lang.reflect.Field
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

@RunWith(RobolectricTestRunner::class)
class MotionDetectorTest {

    private lateinit var config: ConfigManager
    private lateinit var state: StateManager
    private lateinit var events: DummyEventSender
    private lateinit var detector: MotionDetector

    @Before
    fun setUp() {
        val context = RuntimeEnvironment.getApplication()
        
        // Setup Robolectric ShadowSensorManager
        val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val shadowSensorManager = shadowOf(sensorManager)
        val accelerometer = org.robolectric.shadows.ShadowSensor.newInstance(Sensor.TYPE_ACCELEROMETER)
        shadowSensorManager.addSensor(Sensor.TYPE_ACCELEROMETER, accelerometer)
        
        config = ConfigManager(context)
        state = StateManager(context)
        events = DummyEventSender()

        // Force accelerometer-only mode
        config.setConfig(mapOf(
            "disableMotionActivityUpdates" to true,
            "stopTimeout" to 1 // 1 minute
        ))
        
        state.isMoving = true // Start in moving state

        val logger = com.ikolvi.tracelet.sdk.util.TraceletLogger(context, config)
        detector = MotionDetector(context, config, state, events, logger)
        detector.start()
    }

    @Test
    fun `sustained stillness starts stop timeout and keeps stillness sampler running`() {
        val listener = getAccelerometerListener()
        assertNotNull(listener, "Accelerometer should be listening for stillness")

        // Send STILL_SAMPLE_COUNT - 1 samples of stillness (magnitude = 0.0)
        repeat(24) {
            sendSensorEvent(listener, floatArrayOf(0f, 0f, 9.81f)) // Magnitude = 0.0
        }
        assertNull(getStopTimeoutRunnable(), "Timeout should not be started yet")

        // 25th sample triggers the countdown.
        sendSensorEvent(listener, floatArrayOf(0f, 0f, 9.81f))
        assertNotNull(getStopTimeoutRunnable(), "Timeout should be started after sustained stillness")

        // The stillness sampler MUST stay registered during the countdown so
        // that genuine, sustained motion can still abort it. Shutting it down
        // (a previous regression) stranded the detector in the moving state
        // when a stale batched sample cancelled the timeout right after start.
        assertNotNull(
            getAccelerometerListener(),
            "Stillness sampler must keep running during the stop countdown",
        )
    }

    @Test
    fun `single stray motion sample after countdown starts does not cancel the timeout`() {
        val listener = getAccelerometerListener()!!

        // Build the still streak that starts the countdown.
        repeat(25) { sendSensorEvent(listener, floatArrayOf(0f, 0f, 9.81f)) }
        assertNotNull(getStopTimeoutRunnable(), "Countdown should be running")

        // One above-threshold sample (e.g. a stale sample left in the same
        // batched burst, or sensor noise) must NOT abort the countdown.
        sendSensorEvent(listener, floatArrayOf(5f, 0f, 9.81f)) // magnitude ≈ 5 >> 0.4

        assertNotNull(
            getStopTimeoutRunnable(),
            "A single stray motion sample must not cancel the stop timeout",
        )
    }

    @Test
    fun `sustained motion after countdown starts cancels the timeout`() {
        val listener = getAccelerometerListener()!!

        repeat(25) { sendSensorEvent(listener, floatArrayOf(0f, 0f, 9.81f)) }
        assertNotNull(getStopTimeoutRunnable(), "Countdown should be running")

        // MOTION_ABORT_COUNT (5) consecutive above-threshold samples represent
        // real resumed movement and must abort the pending stationary decision.
        repeat(5) { sendSensorEvent(listener, floatArrayOf(5f, 0f, 9.81f)) }

        assertNull(
            getStopTimeoutRunnable(),
            "Sustained motion must cancel the stop timeout",
        )
        assertTrue(state.isMoving, "Device must remain in the moving state after a real abort")
    }

    @Test
    fun `stop timeout fires and declares stationary when stillness is sustained`() {
        val listener = getAccelerometerListener()!!

        repeat(25) { sendSensorEvent(listener, floatArrayOf(0f, 0f, 9.81f)) }
        assertNotNull(getStopTimeoutRunnable(), "Countdown should be running")

        // Advance past the stop timeout (configured to 1 minute in setUp).
        shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofMinutes(2))

        assertFalse(state.isMoving, "Detector must transition to stationary when the timeout fires")
    }

    /**
     * #357: a phone carried at a tilt while walking must not be declared
     * stationary.
     *
     * These are real samples from the field report, replayed in the order they
     * were logged. Every one of them passes the `|‖a‖ - g| < 0.4` test — the
     * norms are 9.64–9.71, so the scalar deviation never exceeds 0.17 — because
     * a scalar norm cannot see a vector that is rotating rather than growing.
     * Under the old test they accumulated a 25-sample still streak, started the
     * countdown, and turned a walking user stationary a minute later.
     */
    @Test
    fun `a tilted phone carried while walking never starts the stop countdown`() {
        val listener = getAccelerometerListener()!!

        val walking = listOf(
            floatArrayOf(-0.418f, 6.349f, 7.244f), // ‖a‖ = 9.64 → mag -0.17
            floatArrayOf(0.163f, 6.234f, 7.426f),  // ‖a‖ = 9.70 → mag -0.11
            floatArrayOf(-0.126f, 5.527f, 7.933f), // ‖a‖ = 9.67 → mag -0.14
            floatArrayOf(0.754f, 4.907f, 8.345f),  // ‖a‖ = 9.71 → mag -0.10
        )
        repeat(10) { i -> sendSensorEvent(listener, walking[i % walking.size]) }

        assertNull(
            getStopTimeoutRunnable(),
            "samples whose norm sits at g but whose direction swings are motion, not stillness",
        )

        // And it must still be moving after the timeout would have elapsed.
        shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofMinutes(2))
        assertTrue(state.isMoving, "a walking device must not be declared stationary (#357)")
    }

    /**
     * The other half of #357: tightening the stillness test must not break stop
     * detection for a device that is genuinely at rest but not lying flat — a
     * phone face-up on a desk at a slight angle, or propped in a holder.
     */
    @Test
    fun `a resting phone at a tilt still detects stillness`() {
        val listener = getAccelerometerListener()!!

        // Steady tilt: a non-trivial orientation whose norm is g and whose
        // direction does not change. Deviation and delta are both ~0.
        repeat(25) { sendSensorEvent(listener, floatArrayOf(0f, 6.937f, 6.937f)) }

        assertNotNull(
            getStopTimeoutRunnable(),
            "a steady vector at any orientation is stillness, whatever the tilt",
        )
        shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofMinutes(2))
        assertFalse(state.isMoving, "a resting device must still go stationary")
    }

    /**
     * #412: the stop countdown was armed on the single sample where the still
     * streak *crossed* the threshold, so any cancellation that did not also
     * reset the streak was permanent — the streak only grows, so it could never
     * equal the threshold a second time.
     *
     * [handleActivityTransition] is exactly that cancellation. Every ENTER of a
     * moving activity calls `cancelStopTimeout()` unconditionally, but only
     * resets the streak through `declareMoving()`, which it skips when the pace
     * is already moving. Walking for a while therefore disarmed the countdown
     * for the rest of the session, and the device never went stationary again.
     */
    @Test
    fun `a countdown cancelled without resetting the still streak is armed again`() {
        val listener = getAccelerometerListener()!!

        repeat(25) { sendSensorEvent(listener, floatArrayOf(0f, 0f, 9.81f)) }
        assertNotNull(getStopTimeoutRunnable(), "Countdown should be running")

        // What a walking activity transition does to a moving session.
        invokeCancelStopTimeout()
        assertNull(getStopTimeoutRunnable(), "precondition: the countdown was cancelled")

        // The device is still and the streak is already saturated. It must arm
        // a new countdown rather than wait for an equality that cannot recur.
        repeat(3) { sendSensorEvent(listener, floatArrayOf(0f, 0f, 9.81f)) }
        assertNotNull(
            getStopTimeoutRunnable(),
            "a saturated still streak must re-arm the stop countdown (#412)",
        )

        shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofMinutes(2))
        assertFalse(state.isMoving, "and the device must actually go stationary")
    }

    /**
     * #412: in SMART mode `state.isMoving` is the *coordinator's* answer — the
     * OR of this detector and the GPS-speed machine — and
     * [SpeedMotionManager.transitionTo] writes it directly the moment its own
     * countdown reaches STATIONARY.
     *
     * [declareStationary] refused to write that field in SMART mode because the
     * coordinator owns it, but still *read* it to decide whether it had
     * anything to report. So the speed machine going stationary first silenced
     * the accelerometer's own edge — and that edge is unrecoverable: the
     * coordinator's accel flag only moves on an edge from here, and the speed
     * machine only calls the coordinator on *entering* STATIONARY. The OR stays
     * true with nothing left to flip it, and continuous GPS runs for the rest
     * of the session on a stationary device.
     */
    @Test
    fun `in SMART mode a stationary speed machine does not swallow the accelerometer edge`() {
        detector.stop()

        val context = RuntimeEnvironment.getApplication()
        config.setConfig(
            mapOf(
                "disableMotionActivityUpdates" to true,
                "stopTimeout" to 1,
                "motionDetectionMode" to
                    com.ikolvi.tracelet.sdk.model.MotionDetectionMode.SMART.value,
            ),
        )
        state.isMoving = true

        val reported = mutableListOf<Boolean>()
        val logger = com.ikolvi.tracelet.sdk.util.TraceletLogger(context, config)
        detector = MotionDetector(context, config, state, events, logger)
        detector.onMotionStateChanged = { reported.add(it) }
        detector.start()

        val listener = getAccelerometerListener()!!
        repeat(25) { sendSensorEvent(listener, floatArrayOf(0f, 0f, 9.81f)) }
        assertNotNull(getStopTimeoutRunnable(), "precondition: the countdown is armed")

        // The GPS-speed machine reaches STATIONARY first and writes the shared
        // field. Nothing about the accelerometer changed.
        state.isMoving = false

        shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofMinutes(2))

        assertEquals(
            listOf(false),
            reported,
            "the accelerometer must still report its own stationary edge (#412)",
        )
    }

    // =========================================================================
    // Reflection Helpers
    // =========================================================================

    private fun getAccelerometerListener(): SensorEventListener? {
        val field = MotionDetector::class.java.getDeclaredField("accelerometerListener")
        field.isAccessible = true
        return field.get(detector) as? SensorEventListener
    }

    private fun getStopTimeoutRunnable(): Runnable? {
        val field = MotionDetector::class.java.getDeclaredField("stopTimeoutRunnable")
        field.isAccessible = true
        return field.get(detector) as? Runnable
    }

    private fun invokeCancelStopTimeout() {
        val method = MotionDetector::class.java.getDeclaredMethod("cancelStopTimeout")
        method.isAccessible = true
        method.invoke(detector)
    }

    private fun sendSensorEvent(listener: SensorEventListener, values: FloatArray) {
        // Create a mock SensorEvent using reflection (constructor is package-private in Android)
        val constructor = SensorEvent::class.java.getDeclaredConstructors().first { it.parameterTypes.size == 1 }
        constructor.isAccessible = true
        val event = constructor.newInstance(values.size) as SensorEvent
        System.arraycopy(values, 0, event.values, 0, values.size)
        listener.onSensorChanged(event)
    }

    private class DummyEventSender : TraceletEventSender {
        override fun sendDrivingEvent(data: Map<String, Any?>) {}
        override fun sendImpact(data: Map<String, Any?>) {}
        override fun sendModeChange(data: Map<String, Any?>) {}
        override fun sendMotionChange(data: Map<String, Any?>) {}
        override fun sendSpeedMotionChange(data: Map<String, Any?>) {}
        override fun sendLocation(data: Map<String, Any?>) {}
        override fun sendActivityChange(data: Map<String, Any?>) {}
        override fun sendGeofencesChange(data: Map<String, Any?>) {}
        override fun sendGeofence(data: Map<String, Any?>) {}
        override fun sendHeartbeat(data: Map<String, Any?>) {}
        override fun sendHttp(data: Map<String, Any?>) {}
        override fun sendProviderChange(data: Map<String, Any?>) {}
        override fun sendConnectivityChange(data: Map<String, Any?>) {}
        override fun sendEnabledChange(enabled: Boolean) {}
        override fun sendPowerSaveChange(isPowerSaveMode: Boolean) {}
        override fun sendNotificationAction(action: String) {}
        override fun sendAuthorization(data: Map<String, Any?>) {}
        override fun sendRemoteConfigEvent(data: Map<String, Any?>) {}
        override fun sendSchedule(data: Map<String, Any?>) {}
        override fun sendWatchPosition(data: Map<String, Any?>) {}
        override fun sendTrip(data: Map<String, Any?>) {}
        override fun sendBudgetAdjustment(data: Map<String, Any?>) {}
        override fun hasListener(eventName: String): Boolean = false
    }
}

/**
 * Regression tests for who owns `isMoving` in SMART mode.
 *
 * In SMART mode the accelerometer is only one of two inputs: the coordinator
 * combines it with the GPS-speed machine and decides. `declareStationary()` used
 * to write `state.isMoving = false` itself, so the accelerometer claimed the
 * transition on its own word — leaving `getState().isMoving` reporting stationary
 * while the coordinator (and therefore the last motionchange event, and the
 * actual GPS behaviour) still said moving.
 */
@RunWith(RobolectricTestRunner::class)
class MotionDetectorSmartModeStateOwnershipTest {

    private lateinit var config: ConfigManager
    private lateinit var state: StateManager
    private lateinit var detector: MotionDetector
    private val reportedTransitions = mutableListOf<Boolean>()

    private fun start(smart: Boolean) {
        val context = RuntimeEnvironment.getApplication()
        val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        shadowOf(sensorManager).addSensor(
            Sensor.TYPE_ACCELEROMETER,
            org.robolectric.shadows.ShadowSensor.newInstance(Sensor.TYPE_ACCELEROMETER),
        )

        config = ConfigManager(context)
        state = StateManager(context)
        config.setConfig(
            mapOf(
                "disableMotionActivityUpdates" to true,
                "stopTimeout" to 1,
                // 2 = smart, 0 = accelerometer
                "motionDetectionMode" to if (smart) 2 else 0,
            ),
        )
        state.isMoving = true

        val logger = com.ikolvi.tracelet.sdk.util.TraceletLogger(context, config)
        detector = MotionDetector(context, config, state, DummySender(), logger)
        detector.onMotionStateChanged = { isMoving -> reportedTransitions.add(isMoving) }
        detector.start()
    }

    private fun driveToStationary() {
        val listener = accelerometerListener()!!
        repeat(25) { sendSample(listener, floatArrayOf(0f, 0f, 9.81f)) }
        shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofMinutes(2))
    }

    @Test
    fun `smart mode reports the transition but leaves isMoving to the coordinator`() {
        start(smart = true)

        driveToStationary()

        assertEquals(
            listOf(false),
            reportedTransitions,
            "the detector must still report stationary to the coordinator",
        )
        assertTrue(
            state.isMoving,
            "in SMART mode the coordinator owns isMoving — the accelerometer must " +
                "not claim the transition on its own",
        )
    }

    @Test
    fun `accelerometer mode still owns isMoving itself`() {
        start(smart = false)

        driveToStationary()

        assertEquals(listOf(false), reportedTransitions)
        assertFalse(
            state.isMoving,
            "outside SMART mode the detector is the only input and still owns the flag",
        )
    }

    private fun accelerometerListener(): SensorEventListener? {
        val field = MotionDetector::class.java.getDeclaredField("accelerometerListener")
        field.isAccessible = true
        return field.get(detector) as? SensorEventListener
    }

    private fun sendSample(listener: SensorEventListener, values: FloatArray) {
        val constructor = SensorEvent::class.java.declaredConstructors
            .first { it.parameterTypes.size == 1 }
        constructor.isAccessible = true
        val event = constructor.newInstance(values.size) as SensorEvent
        System.arraycopy(values, 0, event.values, 0, values.size)
        listener.onSensorChanged(event)
    }

    private class DummySender : TraceletEventSender {
        override fun sendDrivingEvent(data: Map<String, Any?>) {}
        override fun sendImpact(data: Map<String, Any?>) {}
        override fun sendModeChange(data: Map<String, Any?>) {}
        override fun sendMotionChange(data: Map<String, Any?>) {}
        override fun sendSpeedMotionChange(data: Map<String, Any?>) {}
        override fun sendLocation(data: Map<String, Any?>) {}
        override fun sendActivityChange(data: Map<String, Any?>) {}
        override fun sendGeofencesChange(data: Map<String, Any?>) {}
        override fun sendGeofence(data: Map<String, Any?>) {}
        override fun sendHeartbeat(data: Map<String, Any?>) {}
        override fun sendHttp(data: Map<String, Any?>) {}
        override fun sendProviderChange(data: Map<String, Any?>) {}
        override fun sendConnectivityChange(data: Map<String, Any?>) {}
        override fun sendEnabledChange(enabled: Boolean) {}
        override fun sendPowerSaveChange(isPowerSaveMode: Boolean) {}
        override fun sendNotificationAction(action: String) {}
        override fun sendAuthorization(data: Map<String, Any?>) {}
        override fun sendRemoteConfigEvent(data: Map<String, Any?>) {}
        override fun sendSchedule(data: Map<String, Any?>) {}
        override fun sendWatchPosition(data: Map<String, Any?>) {}
        override fun sendTrip(data: Map<String, Any?>) {}
        override fun sendBudgetAdjustment(data: Map<String, Any?>) {}
        override fun hasListener(eventName: String): Boolean = false
    }
}
