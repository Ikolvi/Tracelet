package com.ikolvi.tracelet.sdk.motion

import android.Manifest
import android.app.Application
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.ListenerEventSender
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.TraceletSdk
import com.ikolvi.tracelet.sdk.util.TraceletLogger
import com.ikolvi.tracelet.sdk.wrapper.TraceletActivityRecognitionClient
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.kotlin.any
import org.mockito.kotlin.mock
import org.mockito.kotlin.never
import org.mockito.kotlin.times
import org.mockito.kotlin.verify
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowSensor
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * #433: crash/fall detection is fed from the motion detector's accelerometer,
 * and that sensor needs no runtime permission. The detector used to start only
 * once ACTIVITY_RECOGNITION was granted — so a denied prompt, or a background
 * start with no activity to ask from, left impact detection with no samples for
 * the whole session, even in accelerometer-only mode.
 *
 * Robolectric denies any permission the test does not grant, so
 * ACTIVITY_RECOGNITION is missing throughout unless a test grants it.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class MotionDetectorWithoutActivityRecognitionTest {

    private lateinit var context: Context

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        shadowOf(sensorManager).addSensor(
            Sensor.TYPE_ACCELEROMETER,
            ShadowSensor.newInstance(Sensor.TYPE_ACCELEROMETER),
        )
        resetSdkSingleton()
    }

    @After
    fun tearDown() {
        StateManager(context).reset()
        ConfigManager.resetInstance()
        resetSdkSingleton()
    }

    private fun resetSdkSingleton() {
        TraceletSdk::class.java.getDeclaredField("instance").apply {
            isAccessible = true
            set(null, null)
        }
    }

    private fun accelerometerListener(detector: MotionDetector): SensorEventListener? =
        MotionDetector::class.java.getDeclaredField("accelerometerListener").let {
            it.isAccessible = true
            it.get(detector) as? SensorEventListener
        }

    private fun detector(
        disableActivityUpdates: Boolean,
        activityClient: TraceletActivityRecognitionClient,
    ): MotionDetector {
        val config = ConfigManager(context)
        config.setConfig(mapOf("disableMotionActivityUpdates" to disableActivityUpdates))
        val state = StateManager(context).apply { isMoving = true }
        return MotionDetector(
            context, config, state, ListenerEventSender(),
            TraceletLogger(context, config), activityClient,
        )
    }

    @Test
    fun `full mode without the permission still runs the accelerometer`() {
        val activityClient = mock<TraceletActivityRecognitionClient>()
        val detector = detector(disableActivityUpdates = false, activityClient = activityClient)

        detector.start()

        assertTrue(detector.isRunning)
        assertNotNull(accelerometerListener(detector), "impact detection needs accelerometer samples (#433)")
        verify(activityClient, never()).requestActivityTransitionUpdates(any(), any(), any(), any())
        detector.stop()
    }

    @Test
    fun `a late grant registers the activity transitions on the running detector`() {
        val activityClient = mock<TraceletActivityRecognitionClient>()
        val detector = detector(disableActivityUpdates = false, activityClient = activityClient)
        detector.start()

        shadowOf(context as Application).grantPermissions(Manifest.permission.ACTIVITY_RECOGNITION)
        detector.onActivityRecognitionGranted()
        detector.onActivityRecognitionGranted()

        verify(activityClient, times(1)).requestActivityTransitionUpdates(any(), any(), any(), any())
        detector.stop()
    }

    @Test
    fun `accelerometer-only mode never touches activity transitions`() {
        val activityClient = mock<TraceletActivityRecognitionClient>()
        val detector = detector(disableActivityUpdates = true, activityClient = activityClient)
        detector.start()

        shadowOf(context as Application).grantPermissions(Manifest.permission.ACTIVITY_RECOGNITION)
        detector.onActivityRecognitionGranted()

        assertNotNull(accelerometerListener(detector))
        verify(activityClient, never()).requestActivityTransitionUpdates(any(), any(), any(), any())
        detector.stop()
    }

    @Test
    fun `sdk start runs the motion detector without ACTIVITY_RECOGNITION`() {
        shadowOf(context as Application).grantPermissions(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
            Manifest.permission.ACCESS_BACKGROUND_LOCATION,
        )
        androidx.work.testing.WorkManagerTestInitHelper.initializeTestWorkManager(
            context,
            androidx.work.Configuration.Builder()
                .setExecutor(androidx.work.testing.SynchronousExecutor())
                .build(),
        )
        val sdk = TraceletSdk.getInstance(context)
        sdk.setEventSender(ListenerEventSender())
        sdk.initialize()
        try {
            sdk.ready(mapOf("disableMotionActivityUpdates" to true)) {}
            shadowOf(Looper.getMainLooper()).idle()

            sdk.start()
            shadowOf(Looper.getMainLooper()).idle()

            assertTrue(
                sdk.motionDetector.isRunning,
                "start() must run the detector — it needs no permission in this mode (#433)",
            )
        } finally {
            try { sdk.stop() } catch (_: Exception) {}
            shadowOf(Looper.getMainLooper()).idle()
        }
    }
}
