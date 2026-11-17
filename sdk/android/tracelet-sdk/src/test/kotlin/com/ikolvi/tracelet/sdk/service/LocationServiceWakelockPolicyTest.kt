package com.ikolvi.tracelet.sdk.service

import android.Manifest
import android.app.Application
import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorManager
import android.os.Looper
import android.os.PowerManager
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.ListenerEventSender
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.TraceletSdk
import com.ikolvi.tracelet.sdk.location.LocationEngine
import com.ikolvi.tracelet.sdk.model.MotionDetectionMode
import com.ikolvi.tracelet.sdk.model.SpeedMotionState
import com.ikolvi.tracelet.sdk.model.StationaryTrackingMode
import com.ikolvi.tracelet.sdk.model.TrackingMode
import com.ikolvi.tracelet.sdk.motion.MotionDetector
import com.ikolvi.tracelet.sdk.motion.SmartMotionCoordinator
import com.ikolvi.tracelet.sdk.wrapper.TraceletServices
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.kotlin.mock
import org.mockito.kotlin.never
import org.mockito.kotlin.verify
import org.mockito.kotlin.whenever
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.android.controller.ServiceController
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowSensor
import java.time.Duration
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class LocationServiceWakelockPolicyTest {
    private lateinit var context: Context
    private lateinit var config: ConfigManager
    private lateinit var state: StateManager
    private lateinit var sensors: SensorManager
    private lateinit var engine: LocationEngine
    private var controller: ServiceController<LocationService>? = null

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        shadowOf(context as Application).grantPermissions(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
            Manifest.permission.ACCESS_BACKGROUND_LOCATION,
        )
        resetSdk()
        TraceletServices.setProvider(null)
        config = ConfigManager.getInstance(context)
        config.reset(null)
        config.setConfig(mapOf(
            "motionDetectionMode" to MotionDetectionMode.SMART.value,
            "stationaryTrackingMode" to StationaryTrackingMode.CONTINUOUS.value,
            "stationaryPeriodicInterval" to 3600,
            "disableMotionActivityUpdates" to true,
            "releaseWakelockWhenStationary" to true,
            "foregroundService" to mapOf("enabled" to true, "channelId" to "wakelock_test"),
        ))
        state = StateManager(context)
        state.reset()
        state.enabled = true
        state.isMoving = true
        state.sessionTrackingMode = TrackingMode.CONTINUOUS
        TraceletSdk.getInstance(context).setEventSender(ListenerEventSender())
        sensors = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        shadowOf(sensors).addSensor(Sensor.TYPE_ACCELEROMETER, ShadowSensor.newInstance(Sensor.TYPE_ACCELEROMETER))
        engine = mock()
        whenever(engine.context).thenReturn(context)
        whenever(engine.keepsStationaryStream).thenAnswer {
            config.getStationaryTrackingMode() == StationaryTrackingMode.CONTINUOUS
        }
    }

    @After
    fun tearDown() {
        controller?.destroy()
        LocationService.stopStationaryTimer()
        TraceletServices.setProvider(null)
        state.reset()
        ConfigManager.resetInstance()
        resetSdk()
    }

    private fun resetSdk() {
        TraceletSdk::class.java.getDeclaredField("instance").apply {
            isAccessible = true
            set(null, null)
        }
    }

    private fun addWakeSensor() {
        shadowOf(sensors).addSensor(Sensor.TYPE_SIGNIFICANT_MOTION, ShadowSensor.newInstance(Sensor.TYPE_SIGNIFICANT_MOTION))
    }

    private fun startService(sticky: Boolean = false): LocationService {
        check(controller == null)
        val created = Robolectric.buildService(LocationService::class.java).create()
        controller = created
        val intent = if (sticky) null else Intent(context, LocationService::class.java).apply {
            action = LocationService.ACTION_START
        }
        created.get().onStartCommand(intent, 0, 1)
        idle()
        return created.get()
    }

    private fun idle() {
        shadowOf(Looper.getMainLooper()).idle()
        val app = shadowOf(context as Application)
        while (true) {
            val intent = app.nextStartedService ?: break
            check(intent.component?.className == LocationService::class.java.name)
            controller?.get()?.onStartCommand(intent, 0, 2)
        }
        shadowOf(Looper.getMainLooper()).idle()
    }

    private fun wakelock(service: LocationService = controller!!.get()): PowerManager.WakeLock? =
        LocationService::class.java.getDeclaredField("wakeLock").let {
            it.isAccessible = true
            it.get(service) as PowerManager.WakeLock?
        }

    private fun park(mode: StationaryTrackingMode) {
        config.setConfig(mapOf("stationaryTrackingMode" to mode.value))
        when (mode) {
            StationaryTrackingMode.CONTINUOUS -> LocationService.switchToStationaryContinuous(engine, state)
            StationaryTrackingMode.PERIODIC -> LocationService.switchToStationaryPeriodic(engine, config, state)
            StationaryTrackingMode.GEOFENCES -> LocationService.switchToStationaryGeofences(engine, state, config)
        }
        idle()
    }

    @Test
    fun `all stationary strategies release and reacquire without stopping the service`() {
        addWakeSensor()
        startService()
        for (mode in StationaryTrackingMode.entries) {
            assertTrue(assertNotNull(wakelock()).isHeld)
            park(mode)
            assertNull(wakelock(), mode.name)
            assertFalse(state.isMoving)
            assertTrue(LocationService.isServiceRunning())
            assertNotNull(shadowOf(controller!!.get()).lastForegroundNotification)
            LocationService.switchToContinuous(engine, state)
            idle()
            assertTrue(assertNotNull(wakelock()).isHeld, mode.name)
        }
    }

    @Test
    fun `continuous stationary pace retains its location subscription`() {
        addWakeSensor()
        startService()
        park(StationaryTrackingMode.CONTINUOUS)
        assertNull(wakelock())
        verify(engine).applyContinuousPace(stationary = true)
        verify(engine, never()).stop()
        assertEquals(TrackingMode.CONTINUOUS, state.trackingMode)
        assertFalse(LocationService.isStationaryTimerActive())
    }

    @Test
    fun `accel still keeps the lock while speed moves and speed transitions manage it`() {
        addWakeSensor()
        startService()
        val detector = mock<MotionDetector>()
        whenever(detector.getSensors()).thenReturn(mapOf("significantMotion" to true))
        val coordinator = SmartMotionCoordinator(context, config, state, mock(), engine, detector, mock())
        val sdk = TraceletSdk.getInstance(context)
        for ((name, value) in mapOf("smartMotionCoordinator" to coordinator, "motionDetector" to detector)) {
            TraceletSdk::class.java.getDeclaredField(name).apply { isAccessible = true; set(sdk, value) }
        }
        TraceletSdk::class.java.getDeclaredMethod("handleMotionStateChange", Boolean::class.javaPrimitiveType).apply {
            isAccessible = true
            invoke(sdk, false)
        }
        idle()
        assertTrue(state.isMoving)
        assertTrue(assertNotNull(wakelock()).isHeld)

        coordinator.onSpeedStateChange(false)
        idle()
        assertFalse(state.isMoving)
        assertNull(wakelock())
        coordinator.onSpeedStateChange(true)
        idle()
        assertTrue(state.isMoving)
        assertTrue(assertNotNull(wakelock()).isHeld)
    }

    @Test
    fun `stationary startup applies the configured release without a new motion event`() {
        addWakeSensor()
        state.isMoving = false
        startService()
        assertNull(wakelock())
    }

    @Test
    fun `changing the release option while stationary applies without restarting tracking`() {
        addWakeSensor()
        config.setConfig(mapOf("releaseWakelockWhenStationary" to false))
        state.isMoving = false
        startService()
        assertTrue(assertNotNull(wakelock()).isHeld)
        val sdk = TraceletSdk.getInstance(context)
        TraceletSdk::class.java.getDeclaredField("isReady").apply {
            isAccessible = true
            setBoolean(sdk, true)
        }
        TraceletSdk::class.java.getDeclaredField("locationEngine").apply {
            isAccessible = true
            set(sdk, engine)
        }
        sdk.setConfig(mapOf("android" to mapOf("releaseWakelockWhenStationary" to true)))
        idle()
        assertNull(wakelock())
        sdk.setConfig(mapOf("android" to mapOf("releaseWakelockWhenStationary" to false)))
        idle()
        assertTrue(assertNotNull(wakelock()).isHeld)
        verify(engine, never()).stop()
    }

    @Test
    fun `sticky restarts restore the lock policy and motion transitions for all strategies`() {
        addWakeSensor()
        for (mode in StationaryTrackingMode.entries) {
            config.setConfig(mapOf("stationaryTrackingMode" to mode.value))
            state.isMoving = false
            state.speedMotionState = SpeedMotionState.STATIONARY
            startService(sticky = true)
            assertNull(wakelock(), mode.name)
            val nativeEngine = assertNotNull(LocationService.bootLocationEngine)
            if (mode == StationaryTrackingMode.CONTINUOUS) {
                assertTrue(nativeEngine.isTracking)
                assertTrue(nativeEngine.isStationaryContinuous)
            }
            val detector = assertNotNull(LocationService.bootMotionDetector)
            assertNotNull(detector.onMotionStateChanged).invoke(true)
            idle()
            assertTrue(state.isMoving)
            assertTrue(assertNotNull(wakelock()).isHeld, mode.name)
            assertNotNull(detector.onMotionStateChanged).invoke(false)
            idle()
            assertFalse(state.isMoving)
            assertNull(wakelock(), mode.name)
            controller!!.destroy()
            controller = null
        }
    }

    @Test
    fun `disabled option retains the lock for every stationary strategy`() {
        addWakeSensor()
        config.setConfig(mapOf("releaseWakelockWhenStationary" to false))
        startService()
        for (mode in StationaryTrackingMode.entries) {
            park(mode)
            assertTrue(assertNotNull(wakelock()).isHeld, mode.name)
        }
    }

    @Test
    fun `a missing wake sensor retains the lock`() {
        assertNull(sensors.getDefaultSensor(Sensor.TYPE_SIGNIFICANT_MOTION))
        state.isMoving = false
        startService()
        assertTrue(assertNotNull(wakelock()).isHeld)
    }

    @Test
    fun `non smart motion modes retain their existing lock policy`() {
        addWakeSensor()
        for (mode in listOf(MotionDetectionMode.SPEED, MotionDetectionMode.ACCELEROMETER)) {
            config.setConfig(mapOf("motionDetectionMode" to mode.value))
            state.isMoving = false
            startService()
            assertTrue(assertNotNull(wakelock()).isHeld, mode.name)
            controller!!.destroy()
            controller = null
        }
    }

    @Test
    fun `stationary release cancels automatic lock renewal`() {
        addWakeSensor()
        startService()
        park(StationaryTrackingMode.CONTINUOUS)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMinutes(11))
        assertNull(wakelock())
    }

    @Test
    fun `queued updates cannot reacquire a destroyed service's lock`() {
        addWakeSensor()
        val oldService = startService()
        val oldLock = assertNotNull(wakelock())
        LocationService.switchToStationaryContinuous(engine, state)
        controller!!.destroy()
        controller = null
        state.enabled = true
        state.isMoving = true
        startService()
        assertFalse(oldLock.isHeld)
        assertNull(wakelock(oldService))
        assertTrue(assertNotNull(wakelock()).isHeld)
    }
}
