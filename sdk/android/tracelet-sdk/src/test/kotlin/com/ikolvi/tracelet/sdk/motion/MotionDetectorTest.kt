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
