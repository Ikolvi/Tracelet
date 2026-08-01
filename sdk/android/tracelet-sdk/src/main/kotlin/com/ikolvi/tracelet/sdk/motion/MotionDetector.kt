package com.ikolvi.tracelet.sdk.motion

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.TriggerEvent
import android.hardware.TriggerEventListener
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.TraceletEventSender
import com.ikolvi.tracelet.sdk.util.TraceletLogger
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.wrapper.TraceletActivityRecognitionClient
import com.ikolvi.tracelet.sdk.wrapper.TraceletActivityTransition
import com.ikolvi.tracelet.sdk.wrapper.TraceletActivityTransitionRequest
import com.ikolvi.tracelet.sdk.wrapper.TraceletServices
import kotlin.math.sqrt

/**
 * Motion detection engine with two operating modes:
 *
 * ## Full mode (default)
 * Uses Google Activity Transition API for rich activity classification
 * (still, walking, running, cycling, vehicle) plus accelerometer fallback.
 * Requires `ACTIVITY_RECOGNITION` permission on Android 10+.
 *
 * ## Accelerometer-only mode (`disableMotionActivityUpdates = true`)
 * Uses hardware accelerometer + TYPE_SIGNIFICANT_MOTION sensor for basic
 * stationary↔moving detection. **No permissions required.** Does not provide
 * activity classification — only fires `onMotionStateChanged(isMoving)`.
 *
 * Transition flow (both modes):
 * 1. MOVING → activity/accelerometer detects stillness → start stopTimeout
 * 2. After stopTimeout elapses → declare STATIONARY → fire onMotionChange(false)
 * 3. In stationary: listen for shake/significant motion → declare MOVING
 * 4. Fire onMotionChange(true) → restart location tracking
 */
class MotionDetector(
    private val context: Context,
    private val config: ConfigManager,
    private val state: StateManager,
    var events: TraceletEventSender,
    private val logger: TraceletLogger,
    private val activityClient: TraceletActivityRecognitionClient = TraceletServices.getInstance(context).getActivityRecognitionClient(context),
) {
    private val extractor = TraceletServices.getInstance(context).getEventExtractor()
    companion object {
        private const val TAG = "MotionDetector"
        private const val ACTION_ACTIVITY_TRANSITION =
            "com.tracelet.ACTION_ACTIVITY_TRANSITION"

        /**
         * Accelerometer shake threshold in m/s² (gravity-subtracted).
         *
         * Android's SensorEvent provides raw accelerometer values including
         * gravity (~9.81 m/s²). We subtract gravity magnitude first, then
         * compare the residual user-acceleration to this threshold.
         *
         * This value is intentionally higher than the iOS equivalent (0.35)
         * because Android SENSOR_DELAY_NORMAL has lower sampling resolution
         * (~5 Hz vs iOS 50 Hz) and noisier readings on many devices.
         *
         * @see iOS MotionDetector.shakeThreshold (0.35 — CMMotionManager
         *      reports gravity-subtracted user-acceleration directly)
         */
        private const val SHAKE_THRESHOLD = 2.5

        /**
         * Consecutive low-acceleration samples required to trigger stationary
         * in accelerometer-only mode. At SENSOR_DELAY_NORMAL (~200ms intervals),
         * 25 samples ≈ 5 seconds of sustained stillness.
         *
         * iOS uses 150 samples at 50 Hz ≈ 3 seconds. Android uses fewer samples
         * at a lower rate to achieve a longer dwell window, reducing false
         * stationary transitions from brief stops (e.g. traffic lights).
         *
         * @see iOS MotionDetector.stillSampleCount (150 at 50 Hz ≈ 3s)
         */
        private const val STILL_SAMPLE_COUNT = 25

        /**
         * Acceleration magnitude below which a sample counts as "still".
         *
         * Higher than the iOS equivalent (0.15) because Android's
         * SENSOR_DELAY_NORMAL produces noisier, lower-resolution readings.
         * This value was empirically tuned across Pixel, Samsung, and Xiaomi
         * devices to minimize false positives.
         *
         * @see iOS MotionDetector.stillThreshold (0.15 — CoreMotion provides
         *      cleaner, higher-resolution accelerometer data)
         */
        private const val STILL_THRESHOLD = 0.4

        /**
         * Sensor batching latency for shake detection (stationary monitoring).
         * 3 seconds allows the CPU to sleep between burst deliveries,
         * reducing power by ~30-40% vs unbatched. The latency trade-off
         * is acceptable: a 0-3s delay in detecting initial motion won't
         * affect user experience.
         */
        private const val SENSOR_BATCH_LATENCY_US = 3_000_000

        /**
         * Sensor batching latency for stillness detection (moving state).
         * 5 seconds — longer than shake detection because the stillness
         * algorithm already requires [STILL_SAMPLE_COUNT] consecutive
         * quiet samples, so additional batching latency has minimal
         * impact on total detection time.
         */
        private const val STILLNESS_BATCH_LATENCY_US = 5_000_000

        /**
         * Number of consecutive above-threshold accelerometer samples required
         * to abort an in-progress stop-timeout countdown.
         *
         * The stillness sampler batches deliveries ([STILLNESS_BATCH_LATENCY_US]),
         * so a single burst can contain both the still streak that *starts* the
         * countdown and stray motion/noise samples that immediately follow it.
         * Requiring sustained motion (not one stray sample) to cancel the
         * countdown prevents those stale in-burst spikes — and ordinary sensor
         * noise during the long countdown — from stranding the detector in the
         * moving state and never transitioning to stationary.
         */
        private const val MOTION_ABORT_COUNT = 5
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    private var transitionPendingIntent: PendingIntent? = null

    // Timeout & sensor state
    private var stopTimeoutRunnable: Runnable? = null
    private var sensorManager: SensorManager? = null
    private var accelerometerListener: SensorEventListener? = null
    private var significantMotionListener: TriggerEventListener? = null

    /** Callback: notify LocationEngine to start/stop GPS. */
    var onMotionStateChanged: ((isMoving: Boolean) -> Unit)? = null

    /**
     * Callback: the detected activity (type, confidence) changed. The SDK binds
     * this to push the activity into the LocationEngine so enriched locations
     * carry the real activity instead of a permanent "unknown" (#155).
     */
    var onActivityChanged: ((type: String, confidence: Int) -> Unit)? = null

    /**
     * Emitted per accelerometer sample with the gravity-subtracted magnitude
     * expressed in g (1 g ≈ 9.81 m/s²). Feeds the 3.3.0 transport-mode
     * classifier and impact detector via the accel-window keystone. Only fires
     * while an accelerometer listener is active (moving/stillness sampling).
     */
    var onAccelSample: ((magnitudeG: Double) -> Unit)? = null

    /**
     * When `true` (crash/fall detection enabled), the accelerometer is sampled at
     * a higher rate so short impact spikes (~50-150 ms) are actually captured
     * instead of being missed between the ~5 Hz motion-detection samples. Applies
     * on the next listener registration (i.e. the next start). Costs more battery,
     * which is acceptable because impact detection is opt-in.
     */
    var impactHighRate: Boolean = false

    /** Accelerometer sampling rate — faster when impact detection is active. */
    private fun accelSamplingDelay(): Int =
        if (impactHighRate) SensorManager.SENSOR_DELAY_GAME else SensorManager.SENSOR_DELAY_NORMAL

    /** Batch latency — disabled under high-rate so impact spikes arrive promptly,
     *  otherwise the caller's normal batching latency. */
    private fun accelBatchLatencyUs(normalUs: Int): Int =
        if (impactHighRate) 0 else normalUs

    /** Callback: request full tracking stop (`stopOnStationary` mode). */
    var onStopRequested: (() -> Unit)? = null

    /**
     * Emitted per gyroscope sample with the rotation-rate magnitude in deg/s,
     * for crash corroboration (#179). Only sampled while [gyroEnabled] is set
     * (i.e. crash/fall detection is on), so there's no battery cost otherwise.
     * Decoupled from the motion-detection state machine — gyro samples never
     * affect stationary/moving decisions.
     */
    var onGyroSample: ((dps: Double) -> Unit)? = null

    /** Enables gyroscope sampling (set when crash/fall detection is active). */
    var gyroEnabled: Boolean = false

    private var gyroscopeListener: SensorEventListener? = null

    /**
     * Emitted per barometer sample with the ambient pressure in hPa (millibar),
     * for the cabin-pressure crash cue (#173). A severe collision / airbag
     * deployment produces a sudden pressure transient. Only sampled while
     * [baroEnabled] is set (crash/fall detection on), and only on devices that
     * actually have a pressure sensor — most phones don't, so the cue is strictly
     * best-effort ("where available"). Decoupled from the motion state machine.
     */
    var onPressureSample: ((hpa: Double) -> Unit)? = null

    /** Enables barometer sampling (set when crash/fall detection is active). */
    var baroEnabled: Boolean = false

    private var pressureListener: SensorEventListener? = null

    /**
     * Emitted per accelerometer sample with the **raw total** magnitude in g
     * (gravity included; ~1 g at rest, ~0 g in free-fall). Used to detect the
     * free-fall phase of a fall (#180); the gravity-subtracted [onAccelSample]
     * can't distinguish free-fall (0 g total) from a 2 g impact.
     */
    var onAccelRawSample: ((totalG: Double) -> Unit)? = null

    // Current detected activity (full mode only)
    private var currentActivity: String = "unknown"
    private var currentConfidence: Int = -1

    /** Whether accelerometer monitoring is active (stationary state). */
    private var isMonitoringAccelerometer = false

    /** Whether operating in accelerometer-only mode (no permissions needed). */
    private val isAccelerometerOnlyMode: Boolean
        get() = config.isMotionActivityUpdatesDisabled()

    /** Counter for consecutive still samples in accelerometer-only mode (A-M10). */
    @Volatile
    private var consecutiveStillSamples = 0

    /**
     * Counter for consecutive above-threshold samples seen *after* the
     * stop-timeout countdown has started. Used to require sustained motion
     * before aborting the countdown — see [MOTION_ABORT_COUNT].
     */
    @Volatile
    private var consecutiveMotionSamples = 0

    @Volatile
    var isRunning = false
        private set

    // =========================================================================
    // Public API
    // =========================================================================

    /**
     * Start motion detection.
     *
     * In full mode, registers Activity Transition API + accelerometer fallback.
     * In accelerometer-only mode, starts accelerometer + significant-motion
     * sensor only — no permissions required.
     */
    fun start() {
        logger.debug("start() called — isRunning=$isRunning, isAccelOnlyMode=$isAccelerometerOnlyMode, state.isMoving=${state.isMoving}, isMonitoringAccel=$isMonitoringAccelerometer, sigMotionListener=${significantMotionListener != null}")
        if (isRunning) {
            logger.debug("start() SKIPPED — already running")
            return
        }
        isRunning = true
        if (gyroEnabled) startGyroMonitoring()
        if (baroEnabled) startBaroMonitoring()
        if (isAccelerometerOnlyMode) {
            logger.debug("start() → startAccelerometerOnlyMode()")
            startAccelerometerOnlyMode()
        } else {
            logger.debug("start() → startFullMode()")
            startFullMode()
        }
    }

    /** Registers a gyroscope listener (crash corroboration). Emits deg/s magnitudes. */
    private fun startGyroMonitoring() {
        val sm = sensorManager ?: (context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager)
            ?.also { sensorManager = it } ?: return
        val gyro = sm.getDefaultSensor(Sensor.TYPE_GYROSCOPE) ?: return
        if (gyroscopeListener != null) return
        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                // TYPE_GYROSCOPE values are rad/s; convert magnitude to deg/s.
                val x = event.values[0]
                val y = event.values[1]
                val z = event.values[2]
                val dps = sqrt((x * x + y * y + z * z).toDouble()) * (180.0 / Math.PI)
                onGyroSample?.invoke(dps)
            }
            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }
        sm.registerListener(listener, gyro, accelSamplingDelay(), accelBatchLatencyUs(SENSOR_BATCH_LATENCY_US))
        gyroscopeListener = listener
    }

    private fun stopGyroMonitoring() {
        gyroscopeListener?.let { sensorManager?.unregisterListener(it) }
        gyroscopeListener = null
    }

    /** Registers a barometer listener (crash cabin-pressure cue, #173). Emits hPa. */
    private fun startBaroMonitoring() {
        val sm = sensorManager ?: (context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager)
            ?.also { sensorManager = it } ?: return
        val pressure = sm.getDefaultSensor(Sensor.TYPE_PRESSURE) ?: return
        if (pressureListener != null) return
        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                // TYPE_PRESSURE reports ambient air pressure in hPa (millibar).
                onPressureSample?.invoke(event.values[0].toDouble())
            }
            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }
        sm.registerListener(listener, pressure, accelSamplingDelay(), accelBatchLatencyUs(SENSOR_BATCH_LATENCY_US))
        pressureListener = listener
    }

    private fun stopBaroMonitoring() {
        pressureListener?.let { sensorManager?.unregisterListener(it) }
        pressureListener = null
    }

    /** Stop all motion detection and clean up resources. */
    fun stop() {
        logger.debug("stop() called — isRunning=$isRunning")
        if (!isRunning) {
            logger.debug("stop() SKIPPED — not running")
            return
        }
        isRunning = false
        unregisterActivityTransitions()
        cancelStopTimeout()
        stopAccelerometerMonitoring()
        stopGyroMonitoring()
        stopBaroMonitoring()
        cancelSignificantMotionListener()
        logger.debug("stop() complete")
    }

    /**
     * Re-sync internal sensor state after an external (caller-driven) pace
     * change via `Tracelet.changePace(isMoving)`.
     *
     * Without this, manually forcing the SDK into the stationary state leaves
     * MotionDetector with no listeners registered (because `declareMoving()`
     * had stopped the stationary-side sensors and `declareStationary()` is
     * never invoked from outside). The result is a permanent dead-state: no
     * accelerometer or significant-motion sensor is listening, so no future
     * real movement can wake tracking back up.
     *
     * iOS does not need this hook because CMMotionActivityManager runs
     * continuously at the kernel level regardless of isMoving state.
     */
    fun onManualPaceChange(isMoving: Boolean) {
        logger.debug("onManualPaceChange($isMoving) called — isRunning=$isRunning, isMonitoringAccel=$isMonitoringAccelerometer, sigMotionListener=${significantMotionListener != null}, state.isMoving=${state.isMoving}")
        if (isMoving) {
            logger.debug("onManualPaceChange: MOVING — stopping stationary sensors, starting stillness monitoring")
            stopAccelerometerMonitoring()
            cancelSignificantMotionListener()
            cancelStopTimeout()
            startAccelerometerStillnessMonitoring()
        } else {
            logger.debug("onManualPaceChange: STATIONARY — stopping stillness monitoring, starting shake+sigMotion")
            stopAccelerometerMonitoring()
            cancelStopTimeout()
            startAccelerometerMonitoring()
            startSignificantMotionListener()
            logger.debug("onManualPaceChange: DONE — isMonitoringAccel=$isMonitoringAccelerometer, sigMotionListener=${significantMotionListener != null}")
        }
    }

    /** Returns sensors availability info. */
    fun getSensors(): Map<String, Any?> {
        val sm = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        return mapOf(
            "platform" to "android",
            "accelerometer" to (sm?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) != null),
            "gyroscope" to (sm?.getDefaultSensor(Sensor.TYPE_GYROSCOPE) != null),
            "magnetometer" to (sm?.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD) != null),
            "significantMotion" to (sm?.getDefaultSensor(Sensor.TYPE_SIGNIFICANT_MOTION) != null),
        )
    }

    /** Returns the current detected activity type and confidence. */
    fun getCurrentActivity(): Pair<String, Int> = Pair(currentActivity, currentConfidence)

    // =========================================================================
    // Full mode — Activity Recognition + accelerometer fallback
    // =========================================================================

    private fun startFullMode() {
        logger.debug("startFullMode() — state.isMoving=${state.isMoving}")
        registerActivityTransitions()

        if (!state.isMoving) {
            logger.debug("startFullMode: STATIONARY — starting shake+sigMotion monitoring")
            startAccelerometerMonitoring()
            startSignificantMotionListener()
        } else {
            logger.debug("startFullMode: MOVING — starting stillness monitoring")
            startAccelerometerStillnessMonitoring()
        }
    }

    // =========================================================================
    // Accelerometer-only mode — no permissions, basic motion detection
    // =========================================================================

    /**
     * Start permission-free motion detection using hardware sensors only.
     *
     * Moving state: accelerometer monitors for sustained stillness.
     * Stationary state: significant-motion trigger + accelerometer shake detect.
     */
    private fun startAccelerometerOnlyMode() {
        logger.debug("startAccelerometerOnlyMode() — state.isMoving=${state.isMoving}")

        if (state.isMoving) {
            logger.debug("startAccelerometerOnlyMode: MOVING — starting stillness monitoring")
            startAccelerometerStillnessMonitoring()
        } else {
            logger.debug("startAccelerometerOnlyMode: STATIONARY — starting shake+sigMotion")
            startAccelerometerMonitoring()
            startSignificantMotionListener()
        }
    }

    // =========================================================================
    // Activity Recognition (full mode only)
    // =========================================================================

    private fun registerActivityTransitions() {
        val transitions = listOf(
            TraceletActivityTransition(3, 0), // STILL, ENTER
            TraceletActivityTransition(3, 1), // STILL, EXIT
            TraceletActivityTransition(7, 0), // WALKING, ENTER
            TraceletActivityTransition(8, 0), // RUNNING, ENTER
            TraceletActivityTransition(1, 0), // ON_BICYCLE, ENTER
            TraceletActivityTransition(0, 0), // IN_VEHICLE, ENTER
            TraceletActivityTransition(2, 0), // ON_FOOT, ENTER
        )

        val request = TraceletActivityTransitionRequest(transitions)
        val intent = Intent(context, com.ikolvi.tracelet.sdk.receiver.ActivityTransitionReceiver::class.java).apply {
            action = ACTION_ACTIVITY_TRANSITION
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        transitionPendingIntent = PendingIntent.getBroadcast(context, 0, intent, flags)

        try {
            activityClient.requestActivityTransitionUpdates(
                request = request,
                pendingIntent = transitionPendingIntent!!,
                onSuccess = {
                    logger.debug("Activity transition updates registered with static receiver")
                },
                onFailure = { e ->
                    logger.warning("Failed to register activity transitions: ${e.message}")
                    // Fallback: start accelerometer-only if AT API fails
                    if (!isMonitoringAccelerometer && !state.isMoving) {
                        startAccelerometerMonitoring()
                    }
                }
            )
        } catch (e: SecurityException) {
            logger.warning("ACTIVITY_RECOGNITION permission not granted — " +
                    "falling back to accelerometer-only: ${e.message}")
            // Graceful degradation: use accelerometer instead
            startAccelerometerOnlyMode()
        }
    }

    private fun unregisterActivityTransitions() {
        transitionPendingIntent?.let { pi ->
            activityClient.removeActivityTransitionUpdates(
                pendingIntent = pi,
                onSuccess = { },
                onFailure = { e ->
                    logger.warning("Failed to remove activity transitions: ${e.message}")
                }
            )
        }
        transitionPendingIntent = null
    }

    /**
     * Public callback called by the static ActivityTransitionReceiver to pass
     * incoming broadcast events back to the active MotionDetector instance.
     */
    fun handleTransitionIntent(intent: Intent) {
        if (!isRunning) return
        val result = extractor.extractActivityTransitionResult(intent) ?: return
        for (event in result.transitionEvents) {
            handleTransitionEvent(
                activityType = event.activityType,
                transitionType = event.transitionType
            )
        }
    }

    private fun handleTransitionEvent(activityType: Int, transitionType: Int) {
        if (!isRunning) return
        val activityTypeStr = activityTypeToString(activityType)
        val isEntering = transitionType == 0 // ACTIVITY_TRANSITION_ENTER

        currentActivity = activityTypeStr
        currentConfidence = 100 // Transition API always reports 100% confidence

        // Propagate the activity to the LocationEngine immediately — before the
        // confidence/trigger filters below — so enriched locations always carry
        // the current activity (#155).
        onActivityChanged?.invoke(currentActivity, currentConfidence)

        // Apply confidence filter
        val minConfidence = config.getMinimumActivityRecognitionConfidence()
        if (currentConfidence < minConfidence) return

        // Apply activity type filter
        val triggerActivities = config.getTriggerActivities()
        if (triggerActivities.isNotEmpty()) {
            val allowed = triggerActivities.split(",").map { it.trim().lowercase() }
            if (activityTypeStr.lowercase() !in allowed && activityTypeStr != "still") return
        }

        // Dispatch activity change event to Dart
        events.sendActivityChange(mapOf(
            "activity" to activityTypeStr,
            "confidence" to currentConfidence,
        ))

        val disableStopDetection = config.getDisableStopDetection()

        when {
            // Device became STILL → start stop-timeout countdown
            activityType == 3 && isEntering -> { // STILL = 3 in GMS (Wait! I should check constant values)
                if (!disableStopDetection) {
                    startStopTimeoutCountdown()
                }
            }
            // Device exited STILL or any moving activity detected
            activityType == 3 && !isEntering -> {
                cancelStopTimeout()
                if (!state.isMoving) declareMoving()
            }
            isEntering && activityType != 3 -> {
                cancelStopTimeout()
                if (!state.isMoving) declareMoving()
            }
        }
    }

    // =========================================================================
    // Stop timeout (shared by both modes)
    // =========================================================================

    private fun startStopTimeoutCountdown() {
        cancelStopTimeout()
        val timeoutMs = config.getStopTimeout() * 60 * 1000L
        val stopDetectionDelayMs = config.getStopDetectionDelay() * 1000L
        val totalDelayMs = timeoutMs + stopDetectionDelayMs
        logger.debug("startStopTimeoutCountdown() — timeoutMs=$timeoutMs, delayMs=$stopDetectionDelayMs, totalMs=$totalDelayMs")
        if (totalDelayMs <= 0) {
            logger.debug("startStopTimeoutCountdown() — totalDelay<=0, immediate declareStationary()")
            declareStationary()
            return
        }

        stopTimeoutRunnable = Runnable {
            logger.debug("stopTimeout FIRED — declaring stationary")
            declareStationary()
        }
        mainHandler.postDelayed(stopTimeoutRunnable!!, totalDelayMs)
    }

    private fun cancelStopTimeout() {
        val had = stopTimeoutRunnable != null
        stopTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        stopTimeoutRunnable = null
        if (had) logger.debug("cancelStopTimeout() — cancelled pending timeout")
    }

    // =========================================================================
    // State transitions
    // =========================================================================

    private fun declareStationary() {
        logger.debug("declareStationary() called — state.isMoving=${state.isMoving}, onMotionStateChanged=${onMotionStateChanged != null}")
        if (!state.isMoving) {
            logger.debug("declareStationary() SKIPPED — already stationary")
            return
        }
        // In SMART mode the accelerometer is only one of two inputs: the
        // coordinator ANDs it with the GPS-speed machine and owns isMoving. Writing
        // it here would claim STATIONARY on the accelerometer's word alone, leaving
        // getState().isMoving disagreeing with the last motionchange event whenever
        // the coordinator decides to stay continuous.
        val smartMode = config.getMotionDetectionMode() ==
            com.ikolvi.tracelet.sdk.model.MotionDetectionMode.SMART
        if (smartMode) {
            logger.debug("declareStationary() — SMART mode: leaving isMoving to the coordinator")
        } else {
            state.isMoving = false
        }
        
        // Stop the stillness monitor before we transition to stationary state
        stopAccelerometerMonitoring()
        
        logger.debug("declareStationary() → invoking onMotionStateChanged(false)")
        onMotionStateChanged?.invoke(false)

        if (config.getStopOnStationary()) {
            logger.debug("declareStationary() → stopOnStationary=true, invoking onStopRequested")
            onStopRequested?.invoke()
            return
        }

        logger.debug("declareStationary() → starting shake+sigMotion monitoring for wake-up")
        startAccelerometerMonitoring()
        startSignificantMotionListener()
        logger.debug("declareStationary() DONE — isMonitoringAccel=$isMonitoringAccelerometer, sigMotionListener=${significantMotionListener != null}")
    }

    private fun declareMoving() {
        logger.debug("declareMoving() called — state.isMoving=${state.isMoving}, onMotionStateChanged=${onMotionStateChanged != null}")
        state.isMoving = true
        stopAccelerometerMonitoring()
        cancelSignificantMotionListener()
        consecutiveStillSamples = 0
        consecutiveMotionSamples = 0

        val delay = config.getMotionTriggerDelay().toLong()
        if (delay > 0) {
            logger.debug("declareMoving() → delayed dispatch (${delay}ms)")
            mainHandler.postDelayed({
                if (state.isMoving) {
                    logger.debug("declareMoving() → delayed onMotionStateChanged(true) firing now")
                    onMotionStateChanged?.invoke(true)
                } else {
                    logger.debug("declareMoving() → delayed callback SKIPPED — state.isMoving is now false")
                }
            }, delay)
        } else {
            logger.debug("declareMoving() → invoking onMotionStateChanged(true) immediately")
            onMotionStateChanged?.invoke(true)
        }

        logger.debug("declareMoving() → starting stillness monitoring")
        startAccelerometerStillnessMonitoring()
    }

    // =========================================================================
    // Accelerometer — shake detection (stationary → moving)
    // =========================================================================

    /**
     * Monitors accelerometer for shake/movement while device is stationary.
     * Uses SENSOR_DELAY_NORMAL (~200ms) for low power consumption.
     *
     * **Sensor batching:** A `maxReportLatencyUs` of 3 seconds allows the
     * CPU to remain in a low-power sleep state between burst deliveries,
     * reducing overall power consumption by ~30-40% compared to unbatched
     * delivery. The trade-off is a 0-3 second latency on shake detection
     * which is acceptable for the stationary→moving transition.
     */
    private fun startAccelerometerMonitoring() {
        logger.debug("startAccelerometerMonitoring() [SHAKE] called — isMonitoringAccel=$isMonitoringAccelerometer")
        if (isMonitoringAccelerometer) {
            logger.warning("startAccelerometerMonitoring() [SHAKE] SKIPPED — already monitoring!")
            return
        }
        val sm = obtainSensorManager()
        if (sm == null) {
            logger.error("startAccelerometerMonitoring() [SHAKE] FAILED — SensorManager is null!")
            return
        }
        val accelerometer = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        if (accelerometer == null) {
            logger.warning("Accelerometer sensor not available — relying on significant-motion sensor only")
            startSignificantMotionListener()
            return
        }

        // Log sensor details
        logger.debug("Accelerometer details: name=${accelerometer.name}, vendor=${accelerometer.vendor}, version=${accelerometer.version}, power=${accelerometer.power}mA, resolution=${accelerometer.resolution}m/s²")

        val shakeThreshold = config.getShakeThreshold()
        logger.debug("startAccelerometerMonitoring() [SHAKE] registering listener — shakeThreshold=$shakeThreshold")
        accelerometerListener = object : SensorEventListener {
            private var sampleCount = 0
            private var lastX = 0f
            private var lastY = 0f
            private var lastZ = 0f
            private var consecutiveFrozenCount = 0
            private var maxMagLast10 = 0.0

            override fun onSensorChanged(event: SensorEvent) {
                if (!isRunning) return
                val x = event.values[0]
                val y = event.values[1]
                val z = event.values[2]
                val magnitude = sqrt((x * x + y * y + z * z).toDouble()) - 9.81
                sampleCount++

                // Frozen check
                if (x == lastX && y == lastY && z == lastZ) {
                    consecutiveFrozenCount++
                    if (consecutiveFrozenCount == 5 || consecutiveFrozenCount % 10000 == 0) {
                        logger.warning("[SHAKE] WARNING: Accelerometer values are 100% frozen! consecutiveFrozenCount=$consecutiveFrozenCount, x=$x, y=$y, z=$z. OS background sensor throttling might be active.")
                    }
                } else {
                    if (consecutiveFrozenCount >= 5) {
                        logger.debug("[SHAKE] Accelerometer unfrozen after $consecutiveFrozenCount frozen samples.")
                    }
                    consecutiveFrozenCount = 0
                }
                lastX = x
                lastY = y
                lastZ = z

                // Track max magnitude in last 10 samples
                val absMag = Math.abs(magnitude)
                onAccelSample?.invoke(absMag / 9.81)
                onAccelRawSample?.invoke((magnitude + 9.81) / 9.81)
                if (absMag > maxMagLast10) {
                    maxMagLast10 = absMag
                }

                // Log periodically to avoid spam but show sensor details
                val isFrozen = consecutiveFrozenCount >= 5
                val logInterval = if (isFrozen) 5000 else 50
                if (sampleCount % logInterval == 1) {
                    logger.debug("[SHAKE] sample #$sampleCount: current_mag=${String.format("%.3f", magnitude)}, max_mag_last_10=${String.format("%.3f", maxMagLast10)}, threshold=$shakeThreshold, raw=[$x, $y, $z]")
                }
                // Always reset max mag every 10 samples
                if (sampleCount % 10 == 0) {
                    maxMagLast10 = 0.0
                }

                if (absMag > shakeThreshold) {
                    logger.debug("[SHAKE] ★★★ SHAKE DETECTED! mag=${String.format("%.3f", magnitude)} > threshold=$shakeThreshold (raw=[$x, $y, $z]) → declareMoving()")
                    stopAccelerometerMonitoring()
                    declareMoving()
                }
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }

        val success = sm.registerListener(
            accelerometerListener, accelerometer,
            accelSamplingDelay(),
            accelBatchLatencyUs(SENSOR_BATCH_LATENCY_US)
        )
        isMonitoringAccelerometer = success
        logger.debug("startAccelerometerMonitoring() [SHAKE] registered — success=$success, isMonitoringAccel=$isMonitoringAccelerometer")
        if (!success) {
            logger.error("startAccelerometerMonitoring() [SHAKE] FAILED to register sensor listener!")
        }
    }

    private fun stopAccelerometerMonitoring() {
        logger.debug("stopAccelerometerMonitoring() called — isMonitoringAccel=$isMonitoringAccelerometer")
        if (!isMonitoringAccelerometer) {
            logger.debug("stopAccelerometerMonitoring() SKIPPED — not monitoring")
            return
        }
        accelerometerListener?.let { sensorManager?.unregisterListener(it) }
        accelerometerListener = null
        isMonitoringAccelerometer = false
        logger.debug("stopAccelerometerMonitoring() DONE — unregistered")
    }

    // =========================================================================
    // Accelerometer — stillness detection (moving → stationary, accel-only mode)
    // =========================================================================

    /**
     * Monitors accelerometer for sustained stillness while device is moving.
     * Used only in accelerometer-only mode to detect when the user stops moving.
     *
     * Requires [STILL_SAMPLE_COUNT] consecutive samples below [STILL_THRESHOLD]
     * before starting the stop-timeout countdown, preventing false triggers
     * from brief pauses (e.g. standing at a traffic light).
     *
     * Uses sensor batching (5-second latency) since stillness detection is
     * inherently tolerant of delayed delivery.
     */
    private fun startAccelerometerStillnessMonitoring() {
        logger.debug("startAccelerometerStillnessMonitoring() [STILLNESS] called — isMonitoringAccel=$isMonitoringAccelerometer")
        if (isMonitoringAccelerometer) {
            logger.warning("startAccelerometerStillnessMonitoring() [STILLNESS] SKIPPED — already monitoring!")
            return
        }
        if (config.getDisableStopDetection()) {
            logger.debug("startAccelerometerStillnessMonitoring() [STILLNESS] SKIPPED — stopDetection disabled")
            return
        }

        val sm = obtainSensorManager()
        if (sm == null) {
            logger.error("startAccelerometerStillnessMonitoring() [STILLNESS] FAILED — SensorManager is null!")
            return
        }
        val accelerometer = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        if (accelerometer == null) {
            logger.warning("Accelerometer not available — cannot monitor for stillness")
            return
        }
        consecutiveStillSamples = 0
        consecutiveMotionSamples = 0

        // Log sensor details
        logger.debug("Accelerometer details (stillness): name=${accelerometer.name}, vendor=${accelerometer.vendor}, version=${accelerometer.version}, power=${accelerometer.power}mA, resolution=${accelerometer.resolution}m/s²")

        val stillThreshold = config.getStillThreshold()
        val stillCount = config.getStillSampleCount()
        logger.debug("startAccelerometerStillnessMonitoring() [STILLNESS] registering — stillThreshold=$stillThreshold, stillCount=$stillCount")

        accelerometerListener = object : SensorEventListener {
            private var sampleCount = 0
            private var lastX = 0f
            private var lastY = 0f
            private var lastZ = 0f
            private var consecutiveFrozenCount = 0
            private var maxMagLast10 = 0.0

            override fun onSensorChanged(event: SensorEvent) {
                if (!isRunning) return
                val x = event.values[0]
                val y = event.values[1]
                val z = event.values[2]
                val magnitude = sqrt((x * x + y * y + z * z).toDouble()) - 9.81
                sampleCount++

                // Frozen check
                if (x == lastX && y == lastY && z == lastZ) {
                    consecutiveFrozenCount++
                    if (consecutiveFrozenCount == 5 || consecutiveFrozenCount % 10000 == 0) {
                        logger.warning("[STILLNESS] WARNING: Accelerometer values are 100% frozen! consecutiveFrozenCount=$consecutiveFrozenCount, x=$x, y=$y, z=$z. OS background sensor throttling might be active.")
                    }
                } else {
                    if (consecutiveFrozenCount >= 5) {
                        logger.debug("[STILLNESS] Accelerometer unfrozen after $consecutiveFrozenCount frozen samples.")
                    }
                    consecutiveFrozenCount = 0
                }
                lastX = x
                lastY = y
                lastZ = z

                // Track max magnitude in last 10 samples
                val absMag = Math.abs(magnitude)
                onAccelSample?.invoke(absMag / 9.81)
                onAccelRawSample?.invoke((magnitude + 9.81) / 9.81)
                if (absMag > maxMagLast10) {
                    maxMagLast10 = absMag
                }

                // Log periodically to avoid spam but show sensor details
                val isFrozen = consecutiveFrozenCount >= 5
                val logInterval = if (isFrozen) 5000 else 50
                if (sampleCount % logInterval == 1) {
                    logger.debug("[STILLNESS] sample #$sampleCount: current_mag=${String.format("%.3f", magnitude)}, max_mag_last_10=${String.format("%.3f", maxMagLast10)}, still=$consecutiveStillSamples/$stillCount, raw=[$x, $y, $z]")
                }
                // Always reset max mag every 10 samples
                if (sampleCount % 10 == 0) {
                    maxMagLast10 = 0.0
                }

                if (absMag < stillThreshold) {
                    // A quiet sample — reset any motion streak that was building
                    // toward an abort, then count toward the still threshold.
                    consecutiveMotionSamples = 0
                    consecutiveStillSamples++
                    if (consecutiveStillSamples == stillCount) {
                        logger.debug("[STILLNESS] ★★★ sustained stillness detected ($stillCount samples) → startStopTimeoutCountdown()")
                        // NOTE: We intentionally keep the stillness sampler running
                        // during the countdown. It must stay alive so that genuine,
                        // sustained motion can abort the timeout below — stopping the
                        // sensor here (as a previous fix did) strands the detector in
                        // the moving state when a stale, still-batched motion sample
                        // cancels the countdown right after it starts.
                        startStopTimeoutCountdown()
                    }
                } else if (consecutiveStillSamples >= stillCount) {
                    // The countdown is running. Only abort on *sustained* motion —
                    // a single above-threshold sample is almost always sensor noise
                    // or a stale sample left over from the same batched delivery that
                    // started the countdown. Aborting on one such sample is exactly
                    // what left the device stuck in the moving state.
                    consecutiveMotionSamples++
                    if (consecutiveMotionSamples >= MOTION_ABORT_COUNT) {
                        logger.debug("[STILLNESS] Sustained motion resumed during stop-timeout ($consecutiveMotionSamples samples ≥ threshold=$stillThreshold) → cancelStopTimeout()")
                        cancelStopTimeout()
                        consecutiveStillSamples = 0
                        consecutiveMotionSamples = 0
                    }
                } else {
                    // Not yet in a countdown — a normal motion sample just breaks
                    // the still streak.
                    consecutiveStillSamples = 0
                }
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }

        val success = sm.registerListener(
            accelerometerListener, accelerometer,
            accelSamplingDelay(),
            accelBatchLatencyUs(STILLNESS_BATCH_LATENCY_US)
        )
        isMonitoringAccelerometer = success
        logger.debug("startAccelerometerStillnessMonitoring() [STILLNESS] registered — success=$success, isMonitoringAccel=$isMonitoringAccelerometer")
        if (!success) {
            logger.error("startAccelerometerStillnessMonitoring() [STILLNESS] FAILED to register sensor listener!")
        }
    }

    // =========================================================================
    // Significant Motion sensor (ultra-low-power wakeup, accel-only mode)
    // =========================================================================

    /**
     * Registers the TYPE_SIGNIFICANT_MOTION trigger sensor as an ultra-low-power
     * wakeup mechanism when stationary. This is a one-shot trigger that fires
     * when the device detects "significant" motion (walking, driving, etc.).
     *
     * Unlike continuous accelerometer monitoring, the significant-motion sensor
     * is implemented in hardware on most devices and consumes near-zero power.
     * It complements the accelerometer shake detector: the shake detector catches
     * immediate jolts, while the significant-motion sensor catches sustained
     * movement that starts gradually.
     *
     * No permissions required — this is a hardware sensor API.
     */
    private fun startSignificantMotionListener() {
        logger.debug("startSignificantMotionListener() called — existing=${significantMotionListener != null}")
        if (significantMotionListener != null) {
            logger.debug("startSignificantMotionListener() SKIPPED — already listening")
            return
        }
        val sm = obtainSensorManager()
        if (sm == null) {
            logger.error("startSignificantMotionListener() FAILED — SensorManager is null!")
            return
        }
        val sigMotionSensor = sm.getDefaultSensor(Sensor.TYPE_SIGNIFICANT_MOTION)
        if (sigMotionSensor == null) {
            logger.warning("startSignificantMotionListener() FAILED — TYPE_SIGNIFICANT_MOTION sensor not available!")
            return
        }

        // Log significant motion details
        logger.debug("Significant motion details: name=${sigMotionSensor.name}, vendor=${sigMotionSensor.vendor}, version=${sigMotionSensor.version}, power=${sigMotionSensor.power}mA")

        significantMotionListener = object : TriggerEventListener() {
            override fun onTrigger(event: TriggerEvent?) {
                logger.debug("★★★ SIGNIFICANT MOTION TRIGGERED! — declaring moving")
                significantMotionListener = null
                declareMoving()
            }
        }

        val success = sm.requestTriggerSensor(significantMotionListener, sigMotionSensor)
        logger.debug("startSignificantMotionListener() registered — success=$success, sensor=${sigMotionSensor.name}")
        if (!success) {
            logger.error("startSignificantMotionListener() FAILED to register significant motion sensor!")
            significantMotionListener = null
        }
    }

    private fun cancelSignificantMotionListener() {
        logger.debug("cancelSignificantMotionListener() called — existing=${significantMotionListener != null}")
        significantMotionListener?.let { listener ->
            val sm = obtainSensorManager()
            val sensor = sm?.getDefaultSensor(Sensor.TYPE_SIGNIFICANT_MOTION)
            if (sm != null && sensor != null) {
                sm.cancelTriggerSensor(listener, sensor)
                logger.debug("cancelSignificantMotionListener() — trigger sensor cancelled")
            }
        }
        significantMotionListener = null
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    private fun obtainSensorManager(): SensorManager? {
        if (sensorManager == null) {
            sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        }
        return sensorManager
    }

    private fun activityTypeToString(type: Int): String = when (type) {
        3 -> "still" // DetectedActivity.STILL
        7 -> "walking" // DetectedActivity.WALKING
        8 -> "running" // DetectedActivity.RUNNING
        1 -> "on_bicycle" // DetectedActivity.ON_BICYCLE
        0 -> "in_vehicle" // DetectedActivity.IN_VEHICLE
        2 -> "on_foot" // DetectedActivity.ON_FOOT
        4 -> "tilting" // DetectedActivity.TILTING
        else -> "unknown"
    }
}
