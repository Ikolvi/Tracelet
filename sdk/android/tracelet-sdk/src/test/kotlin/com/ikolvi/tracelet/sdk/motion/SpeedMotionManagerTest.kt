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
                    "stationaryTrackingMode" to if (stationaryMode == "geofences") 1 else 0,
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
        state.speedMotionState = com.ikolvi.tracelet.sdk.model.SpeedMotionState.STATIONARY
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
        assertEquals(1, event["state"]) // SLOWING
        assertEquals(0, event["previousState"]) // MOVING
        assertEquals(0, event["trackingMode"]) // CONTINUOUS
    }

    // =========================================================================
    // GPS speed noise must not restart the SLOWING countdown
    // =========================================================================

    /**
     * A phone sitting on a desk reports a stream of `0.00 m/s` fixes with the
     * occasional blip above the threshold (observed on-device: `1.56 m/s`).
     * Cancelling the countdown on one such fix restarted the whole
     * `speedStationaryDelay` window, so the device stayed MOVING indefinitely
     * while the accelerometer had already reported sustained stillness.
     */
    @Test
    fun `single high-speed blip does not cancel the SLOWING countdown`() {
        configure(movingThreshold = 1.5, stationaryDelaySeconds = 30)

        manager.onLocation(5.0)
        manager.onLocation(0.0) // SLOWING — countdown starts
        assertEquals("slowing", manager.getCurrentState())

        org.robolectric.shadows.ShadowSystemClock.advanceBy(java.time.Duration.ofSeconds(20))
        manager.onLocation(1.56) // isolated noise blip, 20s into the countdown
        assertEquals("slowing", manager.getCurrentState())

        // The countdown kept its original start time, so only the remaining ~10s
        // is needed — not another full 30s window.
        org.robolectric.shadows.ShadowSystemClock.advanceBy(java.time.Duration.ofSeconds(11))
        manager.onLocation(0.0)
        assertEquals("stationary", manager.getCurrentState())
        assertTrue(callback.switchedToStationaryPeriodic)
    }

    @Test
    fun `two high-speed blips still do not cancel the countdown`() {
        configure(movingThreshold = 1.5, stationaryDelaySeconds = 30)

        manager.onLocation(5.0)
        manager.onLocation(0.0)
        manager.onLocation(1.6)
        manager.onLocation(1.6)
        assertEquals("slowing", manager.getCurrentState())
    }

    @Test
    fun `a low fix resets the noise streak so blips cannot accumulate`() {
        configure(movingThreshold = 1.5, stationaryDelaySeconds = 30)

        manager.onLocation(5.0)
        manager.onLocation(0.0)
        // Two blips, a quiet fix, two more blips: never 3 in a row.
        manager.onLocation(1.6)
        manager.onLocation(1.6)
        manager.onLocation(0.0)
        manager.onLocation(1.6)
        manager.onLocation(1.6)
        assertEquals("slowing", manager.getCurrentState())
    }

    @Test
    fun `SLOWING returns to MOVING when speed stays above threshold`() {
        configure(movingThreshold = 1.5, stationaryDelaySeconds = 60)

        manager.onLocation(5.0)
        manager.onLocation(0.3)        // slowing
        assertEquals("slowing", manager.getCurrentState())

        // Sustained motion — 3 consecutive fixes, see SPEED_ABORT_FIX_COUNT.
        manager.onLocation(3.0)
        manager.onLocation(3.0)
        manager.onLocation(3.0)
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
        
        org.robolectric.shadows.ShadowSystemClock.advanceBy(java.time.Duration.ofSeconds(1))
        manager.onLocation(0.1)   // lowCount=2
        
        org.robolectric.shadows.ShadowSystemClock.advanceBy(java.time.Duration.ofSeconds(2))
        manager.onLocation(0.1)   // elapsed >= 2s => transitions to STATIONARY

        assertEquals("stationary", manager.getCurrentState())
        assertTrue(callback.switchedToStationaryPeriodic)
        assertFalse(callback.switchedToStationaryGeofences)
        assertFalse(callback.switchedToContinuous)
    }

    @Test
    fun `STATIONARY invokes switchToStationaryGeofences when configured`() {
        configure(stationaryDelaySeconds = 2, stationaryMode = "geofences")

        manager.onLocation(5.0)
        manager.onLocation(0.1)
        org.robolectric.shadows.ShadowSystemClock.advanceBy(java.time.Duration.ofSeconds(3))
        manager.onLocation(0.1)

        assertEquals("stationary", manager.getCurrentState())
        assertTrue(callback.switchedToStationaryGeofences)
        assertFalse(callback.switchedToStationaryPeriodic)

        val lastEvent = events.speedMotionEvents.last()
        assertEquals(1, lastEvent["trackingMode"]) // GEOFENCES
    }

    // =========================================================================
    // STATIONARY -> MOVING (wake)
    // =========================================================================

    @Test
    fun `STATIONARY wakes to MOVING after wakeConfirmCount high-speed fixes`() {
        state.speedMotionState = com.ikolvi.tracelet.sdk.model.SpeedMotionState.STATIONARY
        configure(wakeConfirmCount = 2)

        manager.onLocation(3.0)   // wakeCount=1, stay stationary
        assertEquals("stationary", manager.getCurrentState())
        assertFalse(callback.switchedToContinuous)

        manager.onLocation(3.0)   // wakeCount=2 => wake
        assertEquals("moving", manager.getCurrentState())
        assertTrue(callback.switchedToContinuous)

        val lastEvent = events.speedMotionEvents.last()
        assertEquals(0, lastEvent["state"]) // MOVING
        assertEquals(2, lastEvent["previousState"]) // STATIONARY
        assertEquals(0, lastEvent["trackingMode"]) // CONTINUOUS
    }

    @Test
    fun `STATIONARY low-speed fix resets wakeCount`() {
        state.speedMotionState = com.ikolvi.tracelet.sdk.model.SpeedMotionState.STATIONARY
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
        assertEquals(com.ikolvi.tracelet.sdk.model.SpeedMotionState.SLOWING, state.speedMotionState)

        org.robolectric.shadows.ShadowSystemClock.advanceBy(java.time.Duration.ofSeconds(3))
        manager.onLocation(0.1)
        assertEquals(com.ikolvi.tracelet.sdk.model.SpeedMotionState.STATIONARY, state.speedMotionState)
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
    // A moving vehicle stays MOVING (#332)
    // =========================================================================

    /**
     * The failure this guards: `LocationProcessorResult::filtered` reported a
     * hardcoded `effective_speed = 0.0`, and [LocationEngine] feeds *every* fix
     * — accepted or not — into this machine. At a 30 m vehicle distance filter
     * and ~1 Hz fixes, most of a 10 m/s drive is rejected, so the machine saw a
     * stream of zeros on a motorway and ran its SLOWING countdown to completion.
     * Given truthful speeds it must never leave MOVING.
     */
    @Test
    fun `sustained vehicle speed never leaves MOVING`() {
        configure(stationaryDelaySeconds = 0)

        repeat(30) { manager.onLocation(10.0) }

        assertEquals("moving", manager.getCurrentState())
        assertTrue(events.speedMotionEvents.isEmpty(), "a steady drive is not a state change")
        assertFalse(callback.switchedToStationaryPeriodic)
    }

    /**
     * The shape the bug took on the wire: real fixes at vehicle speed
     * interleaved with the fabricated zeros the rejected ones contributed. Two
     * filtered fixes per accepted one is the ratio a 30 m filter produces at
     * 10 m/s. Each zero reset the high-speed streak, so the abort counter never
     * reached `SPEED_ABORT_FIX_COUNT` and the countdown expired mid-drive.
     *
     * Kept as a characterisation of the *input* contract: if anything ever feeds
     * this machine a zero per rejected fix again, this fails.
     */
    @Test
    fun `interleaved fabricated zeros would strand the machine in SLOWING`() {
        configure(stationaryDelaySeconds = 600)

        manager.onLocation(10.0)
        manager.onLocation(0.0) // the first fabricated zero: MOVING -> SLOWING
        assertEquals("slowing", manager.getCurrentState())

        repeat(10) {
            manager.onLocation(10.0) // accepted fix, genuinely driving
            manager.onLocation(0.0) // rejected fix, fabricated
            manager.onLocation(0.0) // rejected fix, fabricated
        }

        assertEquals(
            "slowing",
            manager.getCurrentState(),
            "10 fixes at 10 m/s could not rescue the machine — which is why the " +
                "fabricated zeros had to stop at the source (#332)",
        )
    }

    // =========================================================================
    // A no-op transition is not a transition (#337)
    // =========================================================================

    /**
     * Found by the #335 verification card on a device: `changePace(false)` on a
     * machine that was already STATIONARY emitted a `stationary → stationary`
     * event. iOS's `commitTransition` has always guarded this; Android had no
     * equivalent, so the same call behaved differently on the two platforms.
     */
    @Test
    fun `a changePace that changes nothing emits no event`() {
        configure()

        manager.onManualPaceChange(false)
        assertEquals("stationary", manager.getCurrentState())
        val afterFirst = events.speedMotionEvents.size

        manager.onManualPaceChange(false)

        assertEquals("stationary", manager.getCurrentState())
        assertEquals(
            afterFirst,
            events.speedMotionEvents.size,
            "the second call agreed with the current state, so there was no edge to report",
        )
    }

    /** Every emitted event must name a real edge. */
    @Test
    fun `no emitted event reports a transition to the state it came from`() {
        configure()

        manager.onManualPaceChange(false)
        manager.onManualPaceChange(false)
        manager.onManualPaceChange(true)
        manager.onManualPaceChange(true)

        val degenerate = events.speedMotionEvents.filter {
            it["state"] == it["previousState"]
        }
        assertTrue(
            degenerate.isEmpty(),
            "events reporting previousState == state: $degenerate",
        )
    }

    /**
     * The counterpart, and the reason the two rows above are not vacuous: a
     * guard that suppressed everything would satisfy them both.
     */
    @Test
    fun `a changePace that does change the state still emits`() {
        configure()

        manager.onManualPaceChange(false)
        val stops = events.speedMotionEvents.size
        manager.onManualPaceChange(true)

        assertEquals("moving", manager.getCurrentState())
        assertEquals(stops + 1, events.speedMotionEvents.size)
    }

    /**
     * `isMoving` is re-synced inside `transitionTo` and is written directly by
     * `SmartMotionCoordinator` too, so the no-op guard must not skip it.
     */
    @Test
    fun `a no-op transition still re-asserts isMoving`() {
        configure()

        manager.onManualPaceChange(false)
        assertFalse(state.isMoving)

        // Something else moved the flag out from under the machine.
        state.isMoving = true

        manager.onManualPaceChange(false)

        assertFalse(state.isMoving, "the re-assertion must survive the no-op guard")
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

        override fun sendDrivingEvent(data: Map<String, Any?>) {}
        override fun sendImpact(data: Map<String, Any?>) {}
        override fun sendModeChange(data: Map<String, Any?>) {}

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
