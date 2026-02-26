package com.tracelet.tracelet_android.motion

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
import android.util.Log
import com.google.android.gms.location.*
import com.tracelet.tracelet_android.ConfigManager
import com.tracelet.tracelet_android.EventDispatcher
import com.tracelet.tracelet_android.StateManager
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
    private val events: EventDispatcher,
) {
    companion object {
        private const val TAG = "MotionDetector"
        private const val ACTION_ACTIVITY_TRANSITION =
            "com.tracelet.ACTION_ACTIVITY_TRANSITION"

        /** Accelerometer shake threshold in m/s² (gravity-subtracted). */
        private const val SHAKE_THRESHOLD = 2.5

        /**
         * Consecutive low-acceleration samples required to trigger stationary
         * in accelerometer-only mode. At SENSOR_DELAY_NORMAL (~200ms intervals),
         * 25 samples ≈ 5 seconds of sustained stillness.
         */
        private const val STILL_SAMPLE_COUNT = 25

        /** Acceleration magnitude below which a sample counts as "still". */
        private const val STILL_THRESHOLD = 0.4
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    // Activity Recognition (full mode only — lazily initialized)
    private var activityClient: ActivityRecognitionClient? = null
    private var transitionPendingIntent: PendingIntent? = null

    // Timeout & sensor state
    private var stopTimeoutRunnable: Runnable? = null
    private var sensorManager: SensorManager? = null
    private var accelerometerListener: SensorEventListener? = null
    private var significantMotionListener: TriggerEventListener? = null

    /** Callback: notify LocationEngine to start/stop GPS. */
    var onMotionStateChanged: ((isMoving: Boolean) -> Unit)? = null

    /** Callback: request full tracking stop (`stopOnStationary` mode). */
    var onStopRequested: (() -> Unit)? = null

    // Current detected activity (full mode only)
    private var currentActivity: String = "unknown"
    private var currentConfidence: Int = -1

    /** Whether accelerometer monitoring is active (stationary state). */
    private var isMonitoringAccelerometer = false

    /** Whether operating in accelerometer-only mode (no permissions needed). */
    private val isAccelerometerOnlyMode: Boolean
        get() = config.isMotionActivityUpdatesDisabled()

    /** Counter for consecutive still samples in accelerometer-only mode. */
    private var consecutiveStillSamples = 0

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
        if (isAccelerometerOnlyMode) {
            startAccelerometerOnlyMode()
        } else {
            startFullMode()
        }
    }

    /** Stop all motion detection and clean up resources. */
    fun stop() {
        unregisterActivityTransitions()
        cancelStopTimeout()
        stopAccelerometerMonitoring()
        cancelSignificantMotionListener()
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
        registerActivityTransitions()

        // If starting in stationary state, also start accelerometer monitoring.
        // The Activity Transition API can take minutes to fire its first event
        // (and may never fire on budget devices). The accelerometer provides a
        // fast, reliable fallback to detect the initial stationary→moving
        // transition.
        if (!state.isMoving) {
            startAccelerometerMonitoring()
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
        Log.d(TAG, "Starting accelerometer-only mode (no ACTIVITY_RECOGNITION)")

        if (state.isMoving) {
            // Already moving — monitor for stillness to auto-stop
            startAccelerometerStillnessMonitoring()
        } else {
            // Stationary — monitor for shake/significant-motion to wake up
            startAccelerometerMonitoring()
            startSignificantMotionListener()
        }
    }

    // =========================================================================
    // Activity Recognition (full mode only)
    // =========================================================================

    private fun registerActivityTransitions() {
        if (activityClient == null) {
            activityClient = ActivityRecognition.getClient(context)
        }

        val transitions = listOf(
            activityTransition(DetectedActivity.STILL, ActivityTransition.ACTIVITY_TRANSITION_ENTER),
            activityTransition(DetectedActivity.STILL, ActivityTransition.ACTIVITY_TRANSITION_EXIT),
            activityTransition(DetectedActivity.WALKING, ActivityTransition.ACTIVITY_TRANSITION_ENTER),
            activityTransition(DetectedActivity.RUNNING, ActivityTransition.ACTIVITY_TRANSITION_ENTER),
            activityTransition(DetectedActivity.ON_BICYCLE, ActivityTransition.ACTIVITY_TRANSITION_ENTER),
            activityTransition(DetectedActivity.IN_VEHICLE, ActivityTransition.ACTIVITY_TRANSITION_ENTER),
            activityTransition(DetectedActivity.ON_FOOT, ActivityTransition.ACTIVITY_TRANSITION_ENTER),
        )

        val request = ActivityTransitionRequest(transitions)
        val intent = Intent(ACTION_ACTIVITY_TRANSITION).apply {
            setPackage(context.packageName)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        transitionPendingIntent = PendingIntent.getBroadcast(context, 0, intent, flags)

        try {
            activityClient!!.requestActivityTransitionUpdates(request, transitionPendingIntent!!)
                .addOnSuccessListener {
                    Log.d(TAG, "Activity transition updates registered")
                }
                .addOnFailureListener { e ->
                    Log.w(TAG, "Failed to register activity transitions: ${e.message}")
                    // Fallback: start accelerometer-only if AT API fails
                    if (!isMonitoringAccelerometer && !state.isMoving) {
                        startAccelerometerMonitoring()
                    }
                }
        } catch (e: SecurityException) {
            Log.w(TAG, "ACTIVITY_RECOGNITION permission not granted — " +
                    "falling back to accelerometer-only: ${e.message}")
            // Graceful degradation: use accelerometer instead
            startAccelerometerOnlyMode()
        }

        // Register broadcast receiver for transition events
        val filter = IntentFilter(ACTION_ACTIVITY_TRANSITION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(transitionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(transitionReceiver, filter)
        }
    }

    private fun unregisterActivityTransitions() {
        transitionPendingIntent?.let { pi ->
            activityClient?.let { client ->
                try {
                    client.removeActivityTransitionUpdates(pi)
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to remove activity transitions: ${e.message}")
                }
            }
        }
        transitionPendingIntent = null

        try {
            context.unregisterReceiver(transitionReceiver)
        } catch (_: Exception) {
            // Receiver was not registered — safe to ignore
        }
    }

    private val transitionReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            if (intent == null) return
            if (!ActivityTransitionResult.hasResult(intent)) return
            val result = ActivityTransitionResult.extractResult(intent) ?: return
            for (event in result.transitionEvents) {
                handleTransitionEvent(event)
            }
        }
    }

    private fun handleTransitionEvent(event: ActivityTransitionEvent) {
        val activityType = activityTypeToString(event.activityType)
        val isEntering = event.transitionType == ActivityTransition.ACTIVITY_TRANSITION_ENTER

        currentActivity = activityType
        currentConfidence = 100 // Transition API always reports 100% confidence

        // Apply confidence filter
        val minConfidence = config.getMinimumActivityRecognitionConfidence()
        if (currentConfidence < minConfidence) return

        // Apply activity type filter
        val triggerActivities = config.getTriggerActivities()
        if (triggerActivities.isNotEmpty()) {
            val allowed = triggerActivities.split(",").map { it.trim().lowercase() }
            if (activityType.lowercase() !in allowed && activityType != "still") return
        }

        // Dispatch activity change event to Dart
        events.sendActivityChange(mapOf(
            "activity" to activityType,
            "confidence" to currentConfidence,
        ))

        val disableStopDetection = config.getDisableStopDetection()

        when {
            // Device became STILL → start stop-timeout countdown
            event.activityType == DetectedActivity.STILL && isEntering -> {
                if (!disableStopDetection) {
                    startStopTimeoutCountdown()
                }
            }
            // Device exited STILL or any moving activity detected
            event.activityType == DetectedActivity.STILL && !isEntering -> {
                cancelStopTimeout()
                if (!state.isMoving) declareMoving()
            }
            isEntering && event.activityType != DetectedActivity.STILL -> {
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
        if (totalDelayMs <= 0) return

        stopTimeoutRunnable = Runnable { declareStationary() }
        mainHandler.postDelayed(stopTimeoutRunnable!!, totalDelayMs)
    }

    private fun cancelStopTimeout() {
        stopTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        stopTimeoutRunnable = null
    }

    // =========================================================================
    // State transitions
    // =========================================================================

    private fun declareStationary() {
        if (!state.isMoving) return // Already stationary
        state.isMoving = false
        onMotionStateChanged?.invoke(false)

        if (config.getStopOnStationary()) {
            onStopRequested?.invoke()
            return // Full stop requested — no further monitoring needed
        }

        // Begin monitoring to detect next movement
        startAccelerometerMonitoring()
        if (isAccelerometerOnlyMode) {
            startSignificantMotionListener()
        }
    }

    private fun declareMoving() {
        state.isMoving = true
        stopAccelerometerMonitoring()
        cancelSignificantMotionListener()
        consecutiveStillSamples = 0

        val delay = config.getMotionTriggerDelay().toLong()
        if (delay > 0) {
            mainHandler.postDelayed({
                if (state.isMoving) {
                    onMotionStateChanged?.invoke(true)
                }
            }, delay)
        } else {
            onMotionStateChanged?.invoke(true)
        }

        // In accelerometer-only mode, start monitoring for stillness
        if (isAccelerometerOnlyMode) {
            startAccelerometerStillnessMonitoring()
        }
    }

    // =========================================================================
    // Accelerometer — shake detection (stationary → moving)
    // =========================================================================

    /**
     * Monitors accelerometer for shake/movement while device is stationary.
     * Uses SENSOR_DELAY_NORMAL (~200ms) for low power consumption.
     */
    private fun startAccelerometerMonitoring() {
        if (isMonitoringAccelerometer) return
        val sm = obtainSensorManager() ?: return
        val accelerometer = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) ?: return

        accelerometerListener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                val x = event.values[0]
                val y = event.values[1]
                val z = event.values[2]
                val magnitude = sqrt((x * x + y * y + z * z).toDouble()) - 9.81

                if (magnitude > SHAKE_THRESHOLD) {
                    stopAccelerometerMonitoring()
                    declareMoving()
                }
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }

        sm.registerListener(accelerometerListener, accelerometer, SensorManager.SENSOR_DELAY_NORMAL)
        isMonitoringAccelerometer = true
    }

    private fun stopAccelerometerMonitoring() {
        if (!isMonitoringAccelerometer) return
        accelerometerListener?.let { sensorManager?.unregisterListener(it) }
        accelerometerListener = null
        isMonitoringAccelerometer = false
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
     */
    private fun startAccelerometerStillnessMonitoring() {
        if (isMonitoringAccelerometer) return
        if (config.getDisableStopDetection()) return

        val sm = obtainSensorManager() ?: return
        val accelerometer = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) ?: return
        consecutiveStillSamples = 0

        accelerometerListener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                val x = event.values[0]
                val y = event.values[1]
                val z = event.values[2]
                val magnitude = sqrt((x * x + y * y + z * z).toDouble()) - 9.81

                if (Math.abs(magnitude) < STILL_THRESHOLD) {
                    consecutiveStillSamples++
                    if (consecutiveStillSamples >= STILL_SAMPLE_COUNT) {
                        // Sustained stillness detected — start stop-timeout
                        stopAccelerometerMonitoring()
                        startStopTimeoutCountdown()
                    }
                } else {
                    consecutiveStillSamples = 0
                }
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }

        sm.registerListener(accelerometerListener, accelerometer, SensorManager.SENSOR_DELAY_NORMAL)
        isMonitoringAccelerometer = true
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
        val sm = obtainSensorManager() ?: return
        val sigMotionSensor = sm.getDefaultSensor(Sensor.TYPE_SIGNIFICANT_MOTION) ?: return

        significantMotionListener = object : TriggerEventListener() {
            override fun onTrigger(event: TriggerEvent?) {
                Log.d(TAG, "Significant motion detected — declaring moving")
                significantMotionListener = null
                declareMoving()
            }
        }

        sm.requestTriggerSensor(significantMotionListener, sigMotionSensor)
    }

    private fun cancelSignificantMotionListener() {
        significantMotionListener?.let { listener ->
            val sm = obtainSensorManager()
            val sensor = sm?.getDefaultSensor(Sensor.TYPE_SIGNIFICANT_MOTION)
            if (sm != null && sensor != null) {
                sm.cancelTriggerSensor(listener, sensor)
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

    private fun activityTransition(activityType: Int, transitionType: Int): ActivityTransition =
        ActivityTransition.Builder()
            .setActivityType(activityType)
            .setActivityTransition(transitionType)
            .build()

    private fun activityTypeToString(type: Int): String = when (type) {
        DetectedActivity.STILL -> "still"
        DetectedActivity.WALKING -> "walking"
        DetectedActivity.RUNNING -> "running"
        DetectedActivity.ON_BICYCLE -> "on_bicycle"
        DetectedActivity.IN_VEHICLE -> "in_vehicle"
        DetectedActivity.ON_FOOT -> "on_foot"
        DetectedActivity.TILTING -> "tilting"
        DetectedActivity.UNKNOWN -> "unknown"
        else -> "unknown"
    }
}
