package com.ikolvi.tracelet.sdk.motion

import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.TraceletEventSender
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Unit tests for [SpeedMotionManager] — the GPS-speed state machine used when
 * `MotionConfig.motionDetectionMode: speed` is active.
 *
 * Focus: state transitions (MOVING ⇄ SLOWING ⇄ STATIONARY), persistence into
 * SharedPreferences via [StateManager], event emission, and callback
 * invocations (continuous/periodic/geofences switches).
 */
@RunWith(RobolectricTestRunner::class)
class SpeedMotionManagerTest {

    private lateinit var config: ConfigManager
    private lateinit var state: StateManager
    private lateinit var events: RecordingEventSender
    private lateinit var callback: RecordingCallback
    private lateinit var manager: SpeedMotionManager

    @Before
    fun setUp() {
        val context = RuntimeEnvironment.getApplication()
        config = ConfigManager(context)
        state = StateManager(context)
        events = RecordingEventSender()
        callback = RecordingCallback()
        // Fresh state (new test => new package install in Robolectric isolation).
        state.speedMotionState = null
        state.speedLowCount = 0
        state.speedWakeCount = 0
        state.speedLastTransition = 0L
    }

    private fun configure(
        movingThreshold: Double = 1.5,
        stationaryDelaySeconds: Int = 4,
        stationaryMode: String = "periodic",
        wakeConfirmCount: Int = 1,
    ) {
        config.setConfig(
            mapOf(
                "motion" to mapOf(
                    "motionDetectionMode" to "speed",
                    "speedMovingThreshold" to movingThreshold,
                    "speedStationaryDelay" to stationaryDelaySeconds,
                    "stationaryTrackingMode" to stationaryMode,
                    "speedWakeConfirmCount" to wakeConfirmCount,
                )
            )
        )
        manager = SpeedMotionManager(config, state, events, callback)
        manager.start()
    }

    // =========================================================================
    // Default state
    // =========================================================================

    @Test
    fun `starts in MOVING state with no persisted state`() {
        configure()
        assertEquals("moving", manager.getCurrentState())
    }

    @Test
    fun `restores STATIONARY state from StateManager on start`() {
        state.speedMotionState = "stationary"
        configure()
        assertEquals("stationary", manager.getCurrentState())
    }

    // =========================================================================
    // MOVING -> SLOWING
    // =========================================================================

    @Test
    fun `MOVING transitions to SLOWING when speed drops below threshold`() {
        configure(movingThreshold = 1.5)

        manager.onLocation(5.0)        // still moving
        assertEquals("moving", manager.getCurrentState())

        manager.onLocation(0.5)        // slowing
        assertEquals("slowing", manager.getCurrentState())

        val event = events.speedMotionEvents.last()
        assertEquals("slowing", event["state"])
        assertEquals("moving", event["previousState"])
        assertEquals("continuous", event["trackingMode"])
    }

    @Test
    fun `SLOWING returns to MOVING when speed climbs back above threshold`() {
        configure(movingThreshold = 1.5, stationaryDelaySeconds = 60)

        manager.onLocation(5.0)
        manager.onLocation(0.3)        // slowing
        assertEquals("slowing", manager.getCurrentState())

        manager.onLocation(3.0)        // back to moving
        assertEquals("moving", manager.getCurrentState())
        assertEquals(0, state.speedLowCount)
    }

    // =========================================================================
    // SLOWING -> STATIONARY
    // =========================================================================

    @Test
    fun `SLOWING transitions to STATIONARY after stationaryDelay elapses`() {
        // delay 2s, avg interval estimated at ~1s => ~2 low fixes to trip.
        configure(stationaryDelaySeconds = 2)

        manager.onLocation(5.0)
        manager.onLocation(0.1)   // SLOWING (lowCount=1)
        manager.onLocation(0.1)   // lowCount=2 — but elapsed=2s only after avg is primed
        manager.onLocation(0.1)
        manager.onLocation(0.1)
        manager.onLocation(0.1)   // after several fixes, elapsed should clearly exceed 2s

        assertEquals("stationary", manager.getCurrentState())
        assertTrue(callback.switchedToStationaryPeriodic)
        assertFalse(callback.switchedToStationaryGeofences)
        assertFalse(callback.switchedToContinuous)
    }

    @Test
    fun `STATIONARY invokes switchToStationaryGeofences when configured`() {
        configure(stationaryDelaySeconds = 2, stationaryMode = "geofences")

        manager.onLocation(5.0)
        repeat(10) { manager.onLocation(0.1) }

        assertEquals("stationary", manager.getCurrentState())
        assertTrue(callback.switchedToStationaryGeofences)
        assertFalse(callback.switchedToStationaryPeriodic)

        val lastEvent = events.speedMotionEvents.last()
        assertEquals("geofences", lastEvent["trackingMode"])
    }

    // =========================================================================
    // STATIONARY -> MOVING (wake)
    // =========================================================================

    @Test
    fun `STATIONARY wakes to MOVING after wakeConfirmCount high-speed fixes`() {
        state.speedMotionState = "stationary"
        configure(wakeConfirmCount = 2)

        manager.onLocation(3.0)   // wakeCount=1, stay stationary
        assertEquals("stationary", manager.getCurrentState())
        assertFalse(callback.switchedToContinuous)

        manager.onLocation(3.0)   // wakeCount=2 => wake
        assertEquals("moving", manager.getCurrentState())
        assertTrue(callback.switchedToContinuous)

        val lastEvent = events.speedMotionEvents.last()
        assertEquals("moving", lastEvent["state"])
        assertEquals("stationary", lastEvent["previousState"])
        assertEquals("continuous", lastEvent["trackingMode"])
    }

    @Test
    fun `STATIONARY low-speed fix resets wakeCount`() {
        state.speedMotionState = "stationary"
        configure(wakeConfirmCount = 3)

        manager.onLocation(3.0)   // wakeCount=1
        manager.onLocation(3.0)   // wakeCount=2
        manager.onLocation(0.1)   // reset
        assertEquals(0, state.speedWakeCount)
        assertEquals("stationary", manager.getCurrentState())

        manager.onLocation(3.0)   // wakeCount=1 again — still stationary
        assertEquals("stationary", manager.getCurrentState())
    }

    // =========================================================================
    // Persistence
    // =========================================================================

    @Test
    fun `state transitions persist to StateManager`() {
        configure(stationaryDelaySeconds = 2)

        manager.onLocation(5.0)
        manager.onLocation(0.1)
        assertEquals("slowing", state.speedMotionState)

        repeat(10) { manager.onLocation(0.1) }
        assertEquals("stationary", state.speedMotionState)
        assertTrue(state.speedLastTransition > 0L)
    }

    // =========================================================================
    // Backward-compat onMotionChange emission
    // =========================================================================

    // Note: backward-compat onMotionChange is now emitted by TraceletSdk's
    // SpeedMotionCallback implementations (where the last known location is
    // available), not by SpeedMotionManager itself.

    @Test
    fun `SpeedMotionManager does not emit onMotionChange directly`() {
        configure(stationaryDelaySeconds = 2)

        manager.onLocation(5.0)
        repeat(10) { manager.onLocation(0.1) }

        // motionChange events should be empty — they are emitted by the host callback
        assertTrue(events.motionChangeEvents.isEmpty())
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    private class RecordingEventSender : TraceletEventSender {
        val motionChangeEvents = mutableListOf<Map<String, Any?>>()
        val speedMotionEvents = mutableListOf<Map<String, Any?>>()

        override fun sendMotionChange(data: Map<String, Any?>) {
            motionChangeEvents.add(data)
        }
        override fun sendSpeedMotionChange(data: Map<String, Any?>) {
            speedMotionEvents.add(data)
        }

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

    private class RecordingCallback : SpeedMotionManager.SpeedMotionCallback {
        var switchedToContinuous = false
        var switchedToStationaryPeriodic = false
        var switchedToStationaryGeofences = false

        override fun switchToContinuous() { switchedToContinuous = true }
        override fun switchToStationaryPeriodic() { switchedToStationaryPeriodic = true }
        override fun switchToStationaryGeofences() { switchedToStationaryGeofences = true }
    }
}
