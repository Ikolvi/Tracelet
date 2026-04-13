package com.ikolvi.tracelet.sdk.motion

import android.util.Log
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.TraceletEventSender

/**
 * Speed-based motion detection state machine.
 *
 * Uses GPS speed from location fixes to transition between MOVING, SLOWING,
 * and STATIONARY states, switching the native location engine between
 * continuous tracking and low-power periodic/geofence fixes.
 *
 * This is a peer to [MotionDetector] (accelerometer-based) — the two are
 * mutually exclusive, selected via `MotionConfig.motionDetectionMode`.
 *
 * State machine:
 * ```
 * MOVING  --speed<threshold-->  SLOWING  --delay elapsed-->  STATIONARY
 *   ^                              |                             |
 *   |          speed>=threshold----+     wakeConfirmCount fixes--+
 *   +------------------------------------------------------------+
 * ```
 */
class SpeedMotionManager(
    private val config: ConfigManager,
    private val state: StateManager,
    private val events: TraceletEventSender,
    private val callback: SpeedMotionCallback,
) {
    companion object {
        private const val TAG = "SpeedMotion"
    }

    enum class State(val value: String) {
        MOVING("moving"),
        SLOWING("slowing"),
        STATIONARY("stationary");

        companion object {
            fun fromString(s: String?): State = when (s) {
                "slowing" -> SLOWING
                "stationary" -> STATIONARY
                else -> MOVING
            }
        }
    }

    /**
     * Callback interface for mode switching, implemented by the host
     * (LocationService or equivalent).
     */
    interface SpeedMotionCallback {
        fun switchToContinuous()
        fun switchToStationaryPeriodic()
        fun switchToStationaryGeofences()
    }

    // Current state
    private var currentState: State = State.MOVING
    private var lowSpeedCount: Int = 0
    private var wakeCount: Int = 0

    // Timing for SLOWING -> STATIONARY countdown
    private var lastFixTime: Long = 0L
    private var avgIntervalMs: Long = 0L
    private var fixCount: Long = 0L

    // Config values (cached on start)
    private var speedMovingThreshold: Double = 1.5
    private var speedStationaryDelay: Int = 180
    private var stationaryTrackingMode: String = "periodic"
    private var speedWakeConfirmCount: Int = 1

    private var started = false

    // =========================================================================
    // Public API
    // =========================================================================

    /**
     * Start speed-based motion detection.
     *
     * Loads persisted state from [StateManager] so the correct mode is
     * resumed after process death / reboot.
     */
    fun start() {
        if (started) return
        started = true

        // Cache config
        speedMovingThreshold = config.getSpeedMovingThreshold()
        speedStationaryDelay = config.getSpeedStationaryDelay()
        stationaryTrackingMode = config.getStationaryTrackingMode()
        speedWakeConfirmCount = config.getSpeedWakeConfirmCount()

        // Restore persisted state
        currentState = State.fromString(state.speedMotionState)
        lowSpeedCount = state.speedLowCount
        wakeCount = state.speedWakeCount
        lastFixTime = state.speedLastTransition

        Log.d(TAG, "start() — restored state=$currentState, lowCount=$lowSpeedCount, wakeCount=$wakeCount")
    }

    /** Stop speed-based motion detection. */
    fun stop() {
        if (!started) return
        started = false
        Log.d(TAG, "stop()")
    }

    /** Returns the current state value string. */
    fun getCurrentState(): String = currentState.value

    /**
     * Feed a new location fix's speed into the state machine.
     *
     * Called by [LocationEngine] on every continuous or periodic fix
     * when speed-based motion detection is active.
     *
     * @param speedMetersPerSecond GPS speed from the location fix.
     */
    fun onLocation(speedMetersPerSecond: Double) {
        if (!started) return

        // Track inter-fix interval for SLOWING countdown
        val now = System.currentTimeMillis()
        if (lastFixTime > 0) {
            val interval = now - lastFixTime
            fixCount++
            avgIntervalMs = if (avgIntervalMs == 0L) {
                interval
            } else {
                // Exponential moving average
                (avgIntervalMs * 3 + interval) / 4
            }
        }
        lastFixTime = now

        when (currentState) {
            State.MOVING -> onLocationMoving(speedMetersPerSecond)
            State.SLOWING -> onLocationSlowing(speedMetersPerSecond)
            State.STATIONARY -> onLocationStationary(speedMetersPerSecond)
        }
    }

    // =========================================================================
    // State handlers
    // =========================================================================

    private fun onLocationMoving(speed: Double) {
        if (speed < speedMovingThreshold) {
            Log.d(TAG, "MOVING -> SLOWING (speed=${formatSpeed(speed)} < threshold=$speedMovingThreshold)")
            lowSpeedCount = 1
            transitionTo(State.SLOWING)
        }
    }

    private fun onLocationSlowing(speed: Double) {
        if (speed >= speedMovingThreshold) {
            Log.d(TAG, "SLOWING -> MOVING (speed=${formatSpeed(speed)} >= threshold=$speedMovingThreshold)")
            lowSpeedCount = 0
            transitionTo(State.MOVING)
            return
        }

        lowSpeedCount++
        state.speedLowCount = lowSpeedCount

        // Check if elapsed time exceeds stationaryDelay
        val elapsedMs = if (avgIntervalMs > 0) {
            lowSpeedCount.toLong() * avgIntervalMs
        } else {
            // Fallback: assume 1s interval if we have no data yet
            lowSpeedCount.toLong() * 1000L
        }
        val delayMs = speedStationaryDelay * 1000L

        Log.d(TAG, "SLOWING: lowCount=$lowSpeedCount, elapsed=${elapsedMs}ms, delay=${delayMs}ms, speed=${formatSpeed(speed)}")

        if (elapsedMs >= delayMs) {
            Log.d(TAG, "SLOWING -> STATIONARY (elapsed ${elapsedMs}ms >= delay ${delayMs}ms)")
            lowSpeedCount = 0
            wakeCount = 0
            transitionTo(State.STATIONARY)

            // Switch to stationary tracking mode
            when (stationaryTrackingMode) {
                "geofences" -> {
                    Log.d(TAG, "Switching to stationary geofences mode")
                    callback.switchToStationaryGeofences()
                }
                else -> {
                    Log.d(TAG, "Switching to stationary periodic mode")
                    callback.switchToStationaryPeriodic()
                }
            }
        }
    }

    private fun onLocationStationary(speed: Double) {
        if (speed >= speedMovingThreshold) {
            wakeCount++
            state.speedWakeCount = wakeCount
            Log.d(TAG, "STATIONARY: wake fix (speed=${formatSpeed(speed)}), wakeCount=$wakeCount/$speedWakeConfirmCount")

            if (wakeCount >= speedWakeConfirmCount) {
                Log.d(TAG, "STATIONARY -> MOVING (wakeCount=$wakeCount >= confirm=$speedWakeConfirmCount)")
                wakeCount = 0
                transitionTo(State.MOVING)
                callback.switchToContinuous()
            }
        } else {
            // Low speed — reset wake counter, stay stationary
            if (wakeCount > 0) {
                Log.d(TAG, "STATIONARY: low speed, resetting wakeCount ($wakeCount -> 0)")
            }
            wakeCount = 0
            state.speedWakeCount = 0
        }
    }

    // =========================================================================
    // State transition + persistence + event emission
    // =========================================================================

    private fun transitionTo(newState: State) {
        val previousState = currentState
        currentState = newState

        // Persist to SharedPreferences
        state.speedMotionState = newState.value
        state.speedLowCount = lowSpeedCount
        state.speedWakeCount = wakeCount
        state.speedLastTransition = System.currentTimeMillis()

        // Update isMoving for compatibility with existing consumers
        state.isMoving = newState != State.STATIONARY

        // Emit speed motion change event
        val eventData = mapOf(
            "state" to newState.value,
            "previousState" to previousState.value,
            "trackingMode" to when (newState) {
                State.STATIONARY -> stationaryTrackingMode
                else -> "continuous"
            },
        )
        events.sendSpeedMotionChange(eventData)

        // Also emit standard motionChange on MOVING<->STATIONARY transitions
        // for backward compatibility with existing onMotionChange listeners
        if ((previousState == State.STATIONARY && newState == State.MOVING) ||
            (previousState != State.STATIONARY && newState == State.STATIONARY)) {
            events.sendMotionChange(mapOf("is_moving" to (newState != State.STATIONARY)))
        }

        Log.d(TAG, "State transition: ${previousState.value} -> ${newState.value}")
    }

    private fun formatSpeed(speed: Double): String = "%.2f m/s".format(speed)
}
