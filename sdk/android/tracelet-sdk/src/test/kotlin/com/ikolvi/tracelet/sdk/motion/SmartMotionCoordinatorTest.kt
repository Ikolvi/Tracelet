package com.ikolvi.tracelet.sdk.motion

import android.content.Context
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.TraceletEventSender
import com.ikolvi.tracelet.sdk.location.LocationEngine
import com.ikolvi.tracelet.sdk.model.TrackingMode
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.motion.MotionDetector
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify
import org.mockito.Mockito.times
import org.mockito.Mockito.never
import org.mockito.Mockito.anyString
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

@RunWith(RobolectricTestRunner::class)
class SmartMotionCoordinatorTest {

    private lateinit var context: Context
    private lateinit var config: ConfigManager
    private lateinit var state: StateManager
    private lateinit var eventSender: TraceletEventSender
    private lateinit var locationEngine: LocationEngine
    private lateinit var motionDetector: MotionDetector
    private lateinit var coordinator: SmartMotionCoordinator

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        config = ConfigManager(context)
        state = StateManager(context)
        eventSender = mock(TraceletEventSender::class.java)
        locationEngine = mock(LocationEngine::class.java)
        motionDetector = mock(MotionDetector::class.java)

        // Default state: not moving, periodic tracking
        state.isMoving = false
        state.trackingMode = TrackingMode.PERIODIC

        val logger = mock(com.ikolvi.tracelet.sdk.util.TraceletLogger::class.java)
        coordinator = SmartMotionCoordinator(context, config, state, eventSender, locationEngine, motionDetector, logger)
        coordinator.syncCurrentMode()
    }

    /** Makes [LocationEngine] report a resolved effective speed of [speed] m/s. */
    private fun resolveSpeed(speed: Double) {
        org.mockito.Mockito.`when`(locationEngine.getLastLocation())
            .thenReturn(android.location.Location("test"))
        org.mockito.Mockito.`when`(locationEngine.lastEffectiveSpeed).thenReturn(speed)
    }

    @Test
    fun `initial state is Accel=false, Speed=true`() {
        assertFalse(coordinator.isAccelMoving)
        assertTrue(coordinator.isSpeedMoving)
    }

    @Test
    fun `onAccelStateChange to true switches to CONTINUOUS`() {
        // Given that Speed is initially true, Accel changing to true should trigger CONTINUOUS switch
        // Actually, if Speed is true and Accel changes to true, the combined state is still true.
        // Wait, if trackingMode is PERIODIC, it should switch to CONTINUOUS.
        
        coordinator.onAccelStateChange(true)
        
        assertTrue(coordinator.isAccelMoving)
        assertEquals(TrackingMode.CONTINUOUS, state.trackingMode)
        assertTrue(state.isMoving)
        verify(locationEngine).start()
    }

    @Test
    fun `both sensors false switches to STATIONARY`() {
        // First simulate being in CONTINUOUS mode
        state.trackingMode = TrackingMode.CONTINUOUS
        state.isMoving = true
        coordinator.syncCurrentMode()
        
        // Speed becomes false -> combined = false (because Accel is initially false)
        coordinator.onSpeedStateChange(false)
        
        assertFalse(coordinator.isSpeedMoving)
        assertFalse(coordinator.isAccelMoving)
        
        // Should switch to PERIODIC by default
        assertEquals(TrackingMode.PERIODIC, state.trackingMode)
        assertFalse(state.isMoving)
        verify(locationEngine).stop()
    }
    
    @Test
    fun `speed stationary overrides accel moving (hand tremor failsafe)`() {
        state.trackingMode = TrackingMode.CONTINUOUS
        state.isMoving = true
        coordinator.syncCurrentMode()

        // #333: "GPS confirms still" has to mean GPS actually resolved a
        // near-zero speed. This used to pass with no fix at all, because an
        // absent reading reported 0.0 and was accepted as confirmation.
        resolveSpeed(0.0)

        // Accel is true (hand tremor), Speed becomes false (GPS confirms still)
        coordinator.onAccelStateChange(true)
        coordinator.onSpeedStateChange(false)
        
        // GPS speed takes priority: should switch to STATIONARY because the
        // speed failsafe overrides accel jitter when GPS confirms stationary.
        assertFalse(state.isMoving)
    }

    @Test
    fun `consecutive duplicate states do not trigger engine`() {
        coordinator.onAccelStateChange(true)
        // Now tracking mode is CONTINUOUS
        
        // Accel is true, Speed is true -> still CONTINUOUS
        coordinator.onSpeedStateChange(true)
        
        // start() should only be called once when it initially switched to CONTINUOUS
        verify(locationEngine, times(1)).start()
    }
}

/**
 * Regression tests for the accelerometer flag being unseeded at start().
 *
 * The Rust coordinator initialises `is_accel_moving = false` and
 * `on_accel_state_change()` early-returns when the flag is unchanged. Starting a
 * session in MOVING therefore left the accelerometer input inert: the
 * stop-timeout would fire, report stationary, and the coordinator would see no
 * change and emit no action — so the accelerometer could never contribute to a
 * stationary decision until something had first declared moving.
 *
 * `TraceletSdk.start()` now seeds the flag when it starts in MOVING. These tests
 * pin both halves of that behaviour.
 */
@RunWith(RobolectricTestRunner::class)
class SmartMotionCoordinatorAccelSeedTest {
    private lateinit var config: ConfigManager
    private lateinit var state: StateManager
    private lateinit var locationEngine: LocationEngine
    private lateinit var coordinator: SmartMotionCoordinator

    @Before
    fun setUp() {
        val context = RuntimeEnvironment.getApplication()
        config = ConfigManager(context)
        state = StateManager(context)
        state.isMoving = true
        state.trackingMode = TrackingMode.CONTINUOUS
        locationEngine = mock(LocationEngine::class.java)
        coordinator = SmartMotionCoordinator(
            context,
            config,
            state,
            mock(TraceletEventSender::class.java),
            locationEngine,
            mock(MotionDetector::class.java),
            mock(com.ikolvi.tracelet.sdk.util.TraceletLogger::class.java),
        )
        coordinator.syncCurrentMode()
    }

    @Test
    fun `unseeded accel flag makes a stationary accel report a no-op`() {
        // Speed says stationary, accel reports stationary — but the flag was never
        // true, so the coordinator sees no transition at all.
        coordinator.onSpeedStateChange(false)
        val action = coordinator.onAccelStateChange(false)

        assertEquals(uniffi.tracelet_core.CoordinatorAction.NONE, action)
    }

    @Test
    fun `seeding the accel flag lets the accelerometer drive a stationary switch`() {
        // Walking speed: above the 0.15 m/s hand-tremor cutoff, so onSpeedStateChange
        // trusts the accelerometer instead of overriding it to false. That leaves the
        // accelerometer as the last input to settle — the exact case that was inert
        // when the flag started at false.
        // #333: the resolved speed is what the coordinator reads now, not the raw
        // `Location.speed` — that reports 0.0 when the fix carries no speed at all.
        resolveSpeed(0.5)

        // What start() now does when it starts in MOVING.
        coordinator.onAccelStateChange(true)
        assertTrue(coordinator.isAccelMoving)

        // Speed settles first; accel still reports moving, so nothing changes yet.
        coordinator.onSpeedStateChange(false)
        assertTrue(state.isMoving)

        // Now the accelerometer's stop-timeout fires. With the flag seeded this is a
        // real transition, so both inputs agree and the pace finally changes.
        val action = coordinator.onAccelStateChange(false)

        assertEquals(
            uniffi.tracelet_core.CoordinatorAction.SWITCH_TO_STATIONARY_PERIODIC,
            action,
        )
        assertFalse(state.isMoving)
    }

    @Test
    fun `seeded accel alone does not force stationary while speed still moves`() {
        coordinator.onAccelStateChange(true)

        // Accel goes still but GPS speed still reports motion: both inputs must
        // agree before the pace changes.
        val action = coordinator.onAccelStateChange(false)

        assertEquals(uniffi.tracelet_core.CoordinatorAction.NONE, action)
        assertTrue(state.isMoving)
    }

    // =========================================================================
    // #333: an unresolved speed is "unknown", not "parked"
    // =========================================================================

    /** Makes [LocationEngine] report a resolved effective speed of [speed] m/s. */
    private fun resolveSpeed(speed: Double) {
        org.mockito.Mockito.`when`(locationEngine.getLastLocation())
            .thenReturn(android.location.Location("test"))
        org.mockito.Mockito.`when`(locationEngine.lastEffectiveSpeed).thenReturn(speed)
    }

    @Test
    fun `an unresolved speed does not overrule a moving accelerometer`() {
        // No fix has been accepted, so there is no speed to judge by. The old code
        // read the raw `Location.speed`, got the 0.0 an absent reading reports, and
        // treated "we don't know" as proof the device was parked — overriding the
        // one input that was reporting motion.
        coordinator.onAccelStateChange(true)
        assertTrue(coordinator.isAccelMoving)

        coordinator.onSpeedStateChange(false)

        assertTrue(
            coordinator.isAccelMoving,
            "missing data is not evidence of standing still",
        )
        assertEquals(TrackingMode.CONTINUOUS, state.trackingMode)
        assertTrue(state.isMoving)
    }

    @Test
    fun `a vehicle speed does not overrule a moving accelerometer`() {
        resolveSpeed(10.0)
        coordinator.onAccelStateChange(true)

        coordinator.onSpeedStateChange(false)

        assertTrue(coordinator.isAccelMoving)
        assertEquals(TrackingMode.CONTINUOUS, state.trackingMode)
        assertTrue(state.isMoving)
    }

    @Test
    fun `a genuinely near-zero speed still overrules hand tremor`() {
        // The case the override exists for: the device is physically still and the
        // accelerometer is reading tremor. That must keep working.
        resolveSpeed(0.05)
        coordinator.onAccelStateChange(true)

        coordinator.onSpeedStateChange(false)

        assertFalse(coordinator.isAccelMoving)
        assertFalse(state.isMoving)
    }
}

/**
 * #344: a `start()` whose committed pace is stationary must not leave the SMART
 * coordinator deaf to the accelerometer.
 *
 * `syncCurrentMode()` used to map the *session* mode (`stateManager.trackingMode`,
 * which `start()` pins to CONTINUOUS for the whole session) straight onto the
 * coordinator's *posture*. On a start with `isMoving == false` that wrote
 * CONTINUOUS into a coordinator whose accel and speed inputs both said stationary
 * — a pair the core emits no action for in either direction. Every subsequent
 * shake returned NONE, the engine was never switched to continuous, no fixes were
 * recorded and nothing synced, for the rest of the process.
 */
@RunWith(RobolectricTestRunner::class)
class SmartMotionCoordinatorStationaryStartTest {
    private lateinit var state: StateManager
    private lateinit var locationEngine: LocationEngine
    private lateinit var coordinator: SmartMotionCoordinator

    @Before
    fun setUp() {
        val context = RuntimeEnvironment.getApplication()
        state = StateManager(context)
        locationEngine = mock(LocationEngine::class.java)
        coordinator = SmartMotionCoordinator(
            context,
            ConfigManager(context),
            state,
            mock(TraceletEventSender::class.java),
            locationEngine,
            mock(MotionDetector::class.java),
            mock(com.ikolvi.tracelet.sdk.util.TraceletLogger::class.java),
        )
        // A previous session in the same process settled to stationary. The speed
        // flag defaults to true, so this is the flip the *next* session then
        // dedupes away — which is why the usual self-correction in start() cannot
        // rescue the mapping on its own.
        coordinator.onSpeedStateChange(false)
        assertFalse(coordinator.isSpeedMoving)
        assertFalse(coordinator.isAccelMoving)
    }

    /** start(): CONTINUOUS session, pace committed as stationary. */
    private fun startStationary() {
        state.trackingMode = TrackingMode.CONTINUOUS
        state.isMoving = false
        coordinator.syncCurrentMode()
    }

    @Test
    fun `a shake after a stationary start wakes the session`() {
        startStationary()

        // A restored-stationary speed machine re-asserting itself stays a no-op.
        coordinator.onSpeedStateChange(false)
        assertFalse(state.isMoving)

        assertEquals(
            uniffi.tracelet_core.CoordinatorAction.SWITCH_TO_CONTINUOUS,
            coordinator.onAccelStateChange(true),
        )
        assertTrue(state.isMoving)
        assertEquals(TrackingMode.CONTINUOUS, state.trackingMode)
    }

    @Test
    fun `gps speed after a stationary start also wakes the session`() {
        startStationary()

        coordinator.onSpeedStateChange(true)

        assertTrue(state.isMoving)
        assertEquals(TrackingMode.CONTINUOUS, state.trackingMode)
        verify(locationEngine).start()
    }

    @Test
    fun `a moving start still holds the continuous posture`() {
        state.trackingMode = TrackingMode.CONTINUOUS
        state.isMoving = true
        coordinator.syncCurrentMode()

        // Already continuous — a wake-up has nothing to do.
        assertEquals(
            uniffi.tracelet_core.CoordinatorAction.NONE,
            coordinator.onAccelStateChange(true),
        )
        assertTrue(state.isMoving)
    }
}
