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
 * Motion detection engine using Google Activity Recognition + accelerometer.
 *
 * Transition flow:
 * 1. MOVING: ActivityRecognition detects STILL → start stopTimeout countdown
 * 2. After stopTimeout elapses → declare STATIONARY → fire onMotionChange(false) → stop location
 * 3. Start low-power accelerometer monitoring
 * 4. Accelerometer shake detected → declare MOVING → fire onMotionChange(true) → restart location
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

        // Accelerometer shake threshold (m/s²)
        private const val SHAKE_THRESHOLD = 2.5
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val activityClient: ActivityRecognitionClient =
        ActivityRecognition.getClient(context)

    private var transitionPendingIntent: PendingIntent? = null
    private var stopTimeoutRunnable: Runnable? = null
    private var sensorManager: SensorManager? = null
    private var accelerometerListener: SensorEventListener? = null

    // Callback to notify LocationEngine to start/stop
    var onMotionStateChanged: ((isMoving: Boolean) -> Unit)? = null

    // Current detected activity
    private var currentActivity: String = "unknown"
    private var currentConfidence: Int = -1

    /** Whether accelerometer monitoring is active (stationary state). */
    private var isMonitoringAccelerometer = false

    /** Start activity recognition. */
    fun start() {
        if (config.isMotionActivityUpdatesDisabled()) return
        registerActivityTransitions()
    }

    /** Stop all motion detection. */
    fun stop() {
        unregisterActivityTransitions()
        cancelStopTimeout()
        stopAccelerometerMonitoring()
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

    /** Returns current detected activity. */
    fun getCurrentActivity(): Pair<String, Int> = Pair(currentActivity, currentConfidence)

    // =========================================================================
    // Activity Recognition
    // =========================================================================

    private fun registerActivityTransitions() {
        val transitions = listOf(
            // Monitor transition INTO these activities
            ActivityTransition.Builder()
                .setActivityType(DetectedActivity.STILL)
                .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_ENTER)
                .build(),
            ActivityTransition.Builder()
                .setActivityType(DetectedActivity.STILL)
                .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_EXIT)
                .build(),
            ActivityTransition.Builder()
                .setActivityType(DetectedActivity.WALKING)
                .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_ENTER)
                .build(),
            ActivityTransition.Builder()
                .setActivityType(DetectedActivity.RUNNING)
                .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_ENTER)
                .build(),
            ActivityTransition.Builder()
                .setActivityType(DetectedActivity.ON_BICYCLE)
                .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_ENTER)
                .build(),
            ActivityTransition.Builder()
                .setActivityType(DetectedActivity.IN_VEHICLE)
                .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_ENTER)
                .build(),
            ActivityTransition.Builder()
                .setActivityType(DetectedActivity.ON_FOOT)
                .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_ENTER)
                .build(),
        )

        val request = ActivityTransitionRequest(transitions)
        val intent = Intent(ACTION_ACTIVITY_TRANSITION)
        intent.setPackage(context.packageName)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        transitionPendingIntent = PendingIntent.getBroadcast(context, 0, intent, flags)

        try {
            activityClient.requestActivityTransitionUpdates(request, transitionPendingIntent!!)
                .addOnSuccessListener {
                    Log.d(TAG, "Activity transition updates registered")
                }
                .addOnFailureListener { e ->
                    Log.w(TAG, "Failed to register activity transitions: ${e.message}")
                }
        } catch (e: SecurityException) {
            Log.w(TAG, "ACTIVITY_RECOGNITION permission not granted: ${e.message}")
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
        transitionPendingIntent?.let {
            try {
                activityClient.removeActivityTransitionUpdates(it)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to remove activity transitions: ${e.message}")
            }
        }
        transitionPendingIntent = null

        try {
            context.unregisterReceiver(transitionReceiver)
        } catch (e: Exception) {
            // Receiver not registered
        }
    }

    private val transitionReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            if (intent == null) return
            if (ActivityTransitionResult.hasResult(intent)) {
                val result = ActivityTransitionResult.extractResult(intent) ?: return
                for (event in result.transitionEvents) {
                    handleTransitionEvent(event)
                }
            }
        }
    }

    private fun handleTransitionEvent(event: ActivityTransitionEvent) {
        val activityType = activityTypeToString(event.activityType)
        val isEntering = event.transitionType == ActivityTransition.ACTIVITY_TRANSITION_ENTER

        currentActivity = activityType
        currentConfidence = 100 // Transition API doesn't provide confidence

        // Fire activity change event
        events.sendActivityChange(mapOf(
            "activity" to activityType,
            "confidence" to currentConfidence,
        ))

        when {
            // Device became STILL → start stop-timeout countdown
            event.activityType == DetectedActivity.STILL && isEntering -> {
                startStopTimeoutCountdown()
            }
            // Device exited STILL (started moving)
            event.activityType == DetectedActivity.STILL && !isEntering -> {
                cancelStopTimeout()
                if (!state.isMoving) {
                    declareMoving()
                }
            }
            // Any moving activity detected
            isEntering && event.activityType != DetectedActivity.STILL -> {
                cancelStopTimeout()
                if (!state.isMoving) {
                    declareMoving()
                }
            }
        }
    }

    // =========================================================================
    // Stop timeout logic
    // =========================================================================

    private fun startStopTimeoutCountdown() {
        cancelStopTimeout()
        val timeoutMs = config.getStopTimeout() * 60 * 1000L
        if (timeoutMs <= 0) return

        stopTimeoutRunnable = Runnable {
            declareStationary()
        }
        mainHandler.postDelayed(stopTimeoutRunnable!!, timeoutMs)
    }

    private fun cancelStopTimeout() {
        stopTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        stopTimeoutRunnable = null
    }

    private fun declareStationary() {
        if (!state.isMoving) return // Already stationary
        state.isMoving = false
        onMotionStateChanged?.invoke(false)
        startAccelerometerMonitoring()
    }

    private fun declareMoving() {
        state.isMoving = true
        stopAccelerometerMonitoring()

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
    }

    // =========================================================================
    // Accelerometer shake detection (low-power stationary→moving trigger)
    // =========================================================================

    private fun startAccelerometerMonitoring() {
        if (isMonitoringAccelerometer) return
        sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        val accelerometer = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) ?: return

        accelerometerListener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                val x = event.values[0]
                val y = event.values[1]
                val z = event.values[2]

                // Remove gravity component (~9.8 m/s²)
                val magnitude = sqrt((x * x + y * y + z * z).toDouble()) - 9.81
                if (magnitude > SHAKE_THRESHOLD) {
                    // Motion detected while stationary
                    stopAccelerometerMonitoring()
                    declareMoving()
                }
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }

        // SENSOR_DELAY_NORMAL (~200ms) is low power
        sensorManager?.registerListener(
            accelerometerListener, accelerometer, SensorManager.SENSOR_DELAY_NORMAL
        )
        isMonitoringAccelerometer = true
    }

    private fun stopAccelerometerMonitoring() {
        if (!isMonitoringAccelerometer) return
        accelerometerListener?.let {
            sensorManager?.unregisterListener(it)
        }
        accelerometerListener = null
        sensorManager = null
        isMonitoringAccelerometer = false
    }

    // =========================================================================
    // Helpers
    // =========================================================================

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
