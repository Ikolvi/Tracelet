package com.ikolvi.tracelet.sdk.motion
import com.ikolvi.tracelet.sdk.util.TraceletLog

import android.os.SystemClock
import android.util.Log
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.TraceletEventSender
import com.ikolvi.tracelet.sdk.model.SpeedMotionState
import com.ikolvi.tracelet.sdk.model.StationaryTrackingMode

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
    var events: TraceletEventSender,
    private val callback: SpeedMotionCallback,
) {
    companion object {
        private const val TAG = "SpeedMotion"

        /**
         * Fraction of [speedMovingThreshold] used as the slowing threshold when
         * the host has not configured one. Mirrors the Rust core's default.
         */
        private const val STATIONARY_THRESHOLD_RATIO = 0.65

        /**
         * Consecutive above-threshold fixes required to abandon an in-progress
         * SLOWING countdown.
         *
         * GPS speed is noisy while the device is physically still: a stream of
         * `0.00 m/s` fixes can contain an isolated blip well above the threshold
         * (observed: `1.56 m/s` on a phone sitting on a desk). Treating one such
         * fix as "moving again" cancelled the countdown and restarted it from
         * zero, so a still device took several `speedStationaryDelay` windows —
         * or never — to reach STATIONARY, while the accelerometer had already
         * reported sustained stillness.
         *
         * Requiring sustained motion is the same remedy [MotionDetector] applies
         * to accelerometer noise (`MOTION_ABORT_COUNT`). It is safe because
         * SLOWING is still *continuous* tracking: delaying the return to MOVING
         * by a couple of fixes costs no location fidelity, it only stops sensor
         * noise from stranding the device in the moving state.
         */
        private const val SPEED_ABORT_FIX_COUNT = 3
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
    private var currentState: SpeedMotionState = SpeedMotionState.MOVING
    private var lowSpeedCount: Int = 0
    private var wakeCount: Int = 0

    /**
     * Consecutive above-threshold fixes seen while SLOWING — see
     * [SPEED_ABORT_FIX_COUNT]. Not persisted: an isolated blip must not survive
     * a process restart.
     */
    private var highSpeedCount: Int = 0

    // Timing for SLOWING -> STATIONARY countdown
    private var lastFixTime: Long = 0L
    private var avgIntervalMs: Long = 0L
    private var fixCount: Long = 0L

    // Config values (cached on start)
    private var speedMovingThreshold: Double = 0.9

    /**
     * Speed below which a *moving* session begins slowing down (m/s).
     *
     * The lower half of a hysteresis band, and the reason a walker no longer
     * oscillates. One threshold used to govern both directions, so a pace that
     * varied either side of it — every ordinary walk does — produced
     * MOVING → SLOWING → STATIONARY → MOVING in a loop, and a completed
     * countdown stopped the continuous stream while the user was still walking
     * (pedestrian pace hysteresis, PR #399).
     *
     * `<= 0` derives it from [speedMovingThreshold].
     */
    private var speedStationaryThreshold: Double = 0.0

    /** The speed a moving session must drop below to start slowing. */
    private val effectiveStationaryThreshold: Double
        get() = if (speedStationaryThreshold > 0) {
            minOf(speedStationaryThreshold, speedMovingThreshold)
        } else {
            speedMovingThreshold * STATIONARY_THRESHOLD_RATIO
        }

    private var speedStationaryDelay: Int = 180
    private var stationaryTrackingMode: StationaryTrackingMode = StationaryTrackingMode.PERIODIC
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
    fun start(forceMoving: Boolean = false) {
        if (started) return
        started = true

        // Cache config with bounds enforcement
        speedMovingThreshold = config.getSpeedMovingThreshold()
        speedStationaryThreshold = config.getSpeedStationaryThreshold()
        stationaryTrackingMode = config.getStationaryTrackingMode()

        val rawDelay = config.getSpeedStationaryDelay()
        speedStationaryDelay = rawDelay.coerceAtLeast(0)
        if (rawDelay < 0) {
            TraceletLog.warning("speedStationaryDelay was $rawDelay, clamped to 0")
        } else if (rawDelay == 0) {
            TraceletLog.warning("speedStationaryDelay is 0 — device will transition to STATIONARY immediately after a single low-speed fix")
        }

        val rawWakeCount = config.getSpeedWakeConfirmCount()
        speedWakeConfirmCount = rawWakeCount.coerceAtLeast(1)
        if (rawWakeCount < 1) {
            TraceletLog.warning("speedWakeConfirmCount was $rawWakeCount, clamped to 1")
        }

        // Restore persisted state
        currentState = state.speedMotionState ?: SpeedMotionState.MOVING
        lowSpeedCount = state.speedLowCount
        wakeCount = state.speedWakeCount
        lastFixTime = state.speedLastTransition

        // If explicitly forced, ensure we start in MOVING state.
        if (forceMoving) {
            currentState = SpeedMotionState.MOVING
            lowSpeedCount = 0
            wakeCount = 0
            highSpeedCount = 0
            state.speedMotionState = currentState
            state.speedLowCount = 0
            state.speedWakeCount = 0
            state.isMoving = true
            // Always-on, and the mirror of the `speed-motion: restored` line in
            // the `else` branch below: between them they say what pace this
            // session began at and where it came from. A report that shows a
            // session moving on a parked device — or stationary on a moving one
            // — has to name that, and a release build runs at the default
            // logLevel where a `debug` line is discarded (#318).
            TraceletLog.lifecycle(
                "speed-motion: forced to MOVING by start() — the session begins at " +
                    "the pace it was asked for, not the one it restored",
            )
        } else {
            // #334: a relaunched process inherits this state, and inheriting
            // STATIONARY is indistinguishable from "tracking silently stopped"
            // unless the trace says so. Once per session, so it belongs on the
            // always-on channel.
            TraceletLog.lifecycle(
                "speed-motion: restored $currentState (lowSpeedCount=$lowSpeedCount, wakeCount=$wakeCount)"
            )

            if (currentState == SpeedMotionState.STATIONARY) {
                switchToStationary()
            } else if (currentState == SpeedMotionState.SLOWING) {
                slowingStartTimeMs = android.os.SystemClock.elapsedRealtime()
                startSlowingTimer()
            }
        }
    }

    /** Stop speed-based motion detection. */
    fun stop() {
        if (!started) return
        started = false
        TraceletLog.debug("stop()")
    }

    /**
     * Handle manual pace changes triggered by the caller.
     */
    fun onManualPaceChange(isMoving: Boolean) {
        if (!started) return
        TraceletLog.debug("onManualPaceChange(isMoving=$isMoving)")
        if (isMoving) {
            lowSpeedCount = 0
            wakeCount = 0
            highSpeedCount = 0
            stopSlowingTimer()
            transitionTo(SpeedMotionState.MOVING, "manual pace change")
            callback.switchToContinuous()
        } else {
            lowSpeedCount = 0
            wakeCount = 0
            highSpeedCount = 0
            stopSlowingTimer()
            transitionTo(SpeedMotionState.STATIONARY, "manual pace change")
            switchToStationary()
        }
    }

    /** Returns the current state value string (legacy compatibility). */
    fun getCurrentState(): String = currentState.name.lowercase()

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
        val speed = if (speedMetersPerSecond < 0) 0.0 else speedMetersPerSecond

        // Track inter-fix interval for SLOWING countdown.
        // Use elapsedRealtime() which is monotonic and immune to NTP / manual clock changes.
        val now = SystemClock.elapsedRealtime()
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
            SpeedMotionState.MOVING -> onLocationMoving(speed)
            SpeedMotionState.SLOWING -> onLocationSlowing(speed)
            SpeedMotionState.STATIONARY -> onLocationStationary(speed)
        }
    }

    // =========================================================================
    // State handlers
    // =========================================================================

    private fun onLocationMoving(speed: Double) {
        // The *stationary* threshold, not the moving one: leaving MOVING takes a
        // clearer signal than entering it did, which is what keeps a walk whose
        // pace varies either side of the entry threshold from flapping (pedestrian pace hysteresis, PR #399).
        val exitThreshold = effectiveStationaryThreshold
        if (speed < exitThreshold) {
            TraceletLog.debug(
                "MOVING -> SLOWING (speed=${formatSpeed(speed)} < stationary threshold=$exitThreshold)",
            )
            lowSpeedCount = 1
            highSpeedCount = 0
            slowingStartTimeMs = SystemClock.elapsedRealtime()
            transitionTo(
                SpeedMotionState.SLOWING,
                "speed=${formatSpeed(speed)} < stationary threshold=$exitThreshold " +
                    "(moving threshold=$speedMovingThreshold)",
            )
            startSlowingTimer()
        }
    }

    private var slowingStartTimeMs: Long = 0L
    private var slowingTimerRunnable: java.lang.Runnable? = null
    private val slowingHandler = android.os.Handler(android.os.Looper.getMainLooper())

    private fun startSlowingTimer() {
        stopSlowingTimer()
        val delayMs = speedStationaryDelay * 1000L
        slowingTimerRunnable = java.lang.Runnable {
            if (currentState == SpeedMotionState.SLOWING) {
                TraceletLog.debug("SLOWING timer expired -> STATIONARY")
                lowSpeedCount = 0
                wakeCount = 0
                transitionTo(
                    SpeedMotionState.STATIONARY,
                    "SLOWING countdown of ${speedStationaryDelay}s expired",
                )
                switchToStationary()
            }
        }
        slowingHandler.postDelayed(slowingTimerRunnable!!, delayMs)
    }

    private fun stopSlowingTimer() {
        slowingTimerRunnable?.let { slowingHandler.removeCallbacks(it) }
        slowingTimerRunnable = null
    }

    private fun switchToStationary() {
        when (stationaryTrackingMode) {
            StationaryTrackingMode.GEOFENCES -> {
                TraceletLog.debug("Switching to stationary geofences mode")
                callback.switchToStationaryGeofences()
            }
            else -> {
                TraceletLog.debug("Switching to stationary periodic mode")
                callback.switchToStationaryPeriodic()
            }
        }
    }

    private fun onLocationSlowing(speed: Double) {
        if (speed >= speedMovingThreshold) {
            highSpeedCount++
            if (highSpeedCount < SPEED_ABORT_FIX_COUNT) {
                // Almost certainly GPS noise on a still device. Keep the countdown
                // running: cancelling it here restarted the whole
                // speedStationaryDelay window, which could postpone STATIONARY
                // indefinitely.
                TraceletLog.debug(
                    "SLOWING: ignoring high-speed fix $highSpeedCount/$SPEED_ABORT_FIX_COUNT " +
                        "(speed=${formatSpeed(speed)} >= threshold=$speedMovingThreshold) — countdown continues"
                )
                return
            }
            TraceletLog.debug(
                "SLOWING -> MOVING (sustained speed=${formatSpeed(speed)} >= " +
                    "threshold=$speedMovingThreshold for $highSpeedCount fixes)"
            )
            lowSpeedCount = 0
            highSpeedCount = 0
            stopSlowingTimer()
            transitionTo(
                SpeedMotionState.MOVING,
                "sustained speed=${formatSpeed(speed)} >= threshold=$speedMovingThreshold " +
                    "for $SPEED_ABORT_FIX_COUNT fixes",
            )
            return
        }

        // A low fix — any partial high-speed streak was noise.
        highSpeedCount = 0
        lowSpeedCount++
        state.speedLowCount = lowSpeedCount

        val elapsedMs = SystemClock.elapsedRealtime() - slowingStartTimeMs
        val delayMs = speedStationaryDelay * 1000L

        TraceletLog.debug("SLOWING: lowCount=$lowSpeedCount, elapsed=${elapsedMs}ms, delay=${delayMs}ms, speed=${formatSpeed(speed)}")

        if (elapsedMs >= delayMs) {
            TraceletLog.debug("SLOWING -> STATIONARY (elapsed ${elapsedMs}ms >= delay ${delayMs}ms)")
            lowSpeedCount = 0
            wakeCount = 0
            stopSlowingTimer()
            transitionTo(
                SpeedMotionState.STATIONARY,
                "speed=${formatSpeed(speed)}, elapsed=${elapsedMs}ms >= delay=${delayMs}ms",
            )
            switchToStationary()
        }
    }

    private fun onLocationStationary(speed: Double) {
        if (speed >= speedMovingThreshold) {
            wakeCount++
            state.speedWakeCount = wakeCount
            TraceletLog.debug("STATIONARY: wake fix (speed=${formatSpeed(speed)}), wakeCount=$wakeCount/$speedWakeConfirmCount")

            if (wakeCount >= speedWakeConfirmCount) {
                TraceletLog.debug("STATIONARY -> MOVING (wakeCount=$wakeCount >= confirm=$speedWakeConfirmCount)")
                wakeCount = 0
                transitionTo(
                    SpeedMotionState.MOVING,
                    "woke on speed=${formatSpeed(speed)} >= threshold=$speedMovingThreshold " +
                        "($speedWakeConfirmCount confirming fixes)",
                )
                callback.switchToContinuous()
            }
        } else {
            // Low speed — reset wake counter, stay stationary
            if (wakeCount > 0) {
                TraceletLog.debug("STATIONARY: low speed, resetting wakeCount ($wakeCount -> 0)")
            }
            wakeCount = 0
            state.speedWakeCount = 0
        }
    }

    // =========================================================================
    // State transition + persistence + event emission
    // =========================================================================

    /**
     * Commits a state change: persists it, emits the event, and records it on
     * the always-on lifecycle channel.
     *
     * #334: this machine decides whether a moving vehicle keeps continuous
     * tracking, and at the shipped log levels (`info` for Flutter, `off` for a
     * direct SDK consumer) its reasoning left no trace at all — a bug report
     * showed the downgrade with nothing to say why. [reason] carries the speed
     * the decision was made on, which is the whole story in the case that
     * motivated it: a fabricated `speed=0.00` while the car was doing 10 m/s
     * (#332). Transitions fire a handful of times per trip, not per fix, which
     * is the bar [TraceletLogger.lifecycle] sets for the channel.
     */
    private fun transitionTo(newState: SpeedMotionState, reason: String) {
        val previousState = currentState
        currentState = newState

        // Persist to SharedPreferences
        state.speedMotionState = newState
        state.speedLowCount = lowSpeedCount
        state.speedWakeCount = wakeCount
        state.speedLastTransition = SystemClock.elapsedRealtime()

        // Update isMoving for compatibility with existing consumers.
        //
        // Deliberately outside the no-op guard below: this is also where
        // isMoving is re-synced, and SmartMotionCoordinator.handleAction writes
        // the same field directly, so a changePace() that agrees with the
        // current state is a legitimate re-assertion of it.
        state.isMoving = newState != SpeedMotionState.STATIONARY

        // #337: a "transition" that changes nothing is not a transition. An
        // event whose previousState equals its state tells a consumer nothing
        // while still driving every listener that reacts to one, and
        // `speed-motion: STATIONARY -> STATIONARY` is a fabricated edge in the
        // one trace meant to settle what actually happened during a trip
        // (#334). iOS's `commitTransition` has always guarded this; Android had
        // no equivalent, so the two platforms disagreed on the same call.
        if (newState == previousState) return

        // Emit speed motion change event
        val eventData = mapOf<String, Any>(
            "state" to newState.ordinal,
            "previousState" to previousState.ordinal,
            "trackingMode" to when (newState) {
                SpeedMotionState.STATIONARY -> if (stationaryTrackingMode == StationaryTrackingMode.GEOFENCES) 1 else 2
                else -> 0
            }
        )
        events.sendSpeedMotionChange(eventData)

        TraceletLog.lifecycle("speed-motion: ${previousState.name} -> ${newState.name} — $reason")
    }

    private fun formatSpeed(speed: Double): String = "%.2f m/s".format(speed)
}
