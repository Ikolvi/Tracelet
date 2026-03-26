package com.ikolvi.tracelet.sdk.location

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import com.ikolvi.tracelet.sdk.ConfigManager
import kotlin.math.*

/**
 * Inertial dead reckoning engine for GPS-denied environments.
 *
 * Uses accelerometer + magnetometer to estimate position when GPS is lost.
 * Implements Pedestrian Dead Reckoning (PDR) with step detection and heading
 * estimation. For vehicle/cycling modes, uses direct acceleration integration
 * with a high-pass filter.
 *
 * Accuracy degrades linearly with elapsed time:
 * - Pedestrian: base 5m + 1m/s
 * - Vehicle: base 10m + 3m/s
 *
 * Lifecycle:
 * 1. [activate] — start sensors, begin estimating from last known GPS position
 * 2. Engine emits estimated positions via [onEstimatedLocation] every ~1s
 * 3. [deactivate] — stop sensors, clean up
 * 4. Auto-stops after [ConfigManager.getDeadReckoningMaxDuration] seconds
 */
class DeadReckoningEngine(
    private val context: Context,
    private val config: ConfigManager,
) {
    companion object {
        private const val TAG = "DeadReckoningEngine"

        /** Meters per degree of latitude (approximate). */
        private const val METERS_PER_DEG_LAT = 111_139.0

        /** Sensor update interval: 50 Hz (20ms) for IMU fusion. */
        private const val SENSOR_DELAY_US = 20_000

        /** Minimum acceleration peak-to-trough for a valid step (m/s²). */
        private const val STEP_THRESHOLD = 2.0

        /** Minimum time between steps (ms) — prevents double-counting. */
        private const val MIN_STEP_INTERVAL_MS = 250L

        /** Maximum time between steps (ms) — if exceeded, reset peak detector. */
        private const val MAX_STEP_INTERVAL_MS = 2000L

        /** High-pass filter coefficient for vehicle acceleration integration. */
        private const val HIGH_PASS_ALPHA = 0.8

        /** Location emission interval (ms). */
        private const val EMIT_INTERVAL_MS = 1000L
    }

    // State
    @Volatile
    var isActive: Boolean = false
        private set
    private var activationTimeMs: Long = 0

    // Position
    private var currentLat: Double = 0.0
    private var currentLng: Double = 0.0
    private var currentAltitude: Double = 0.0
    private var currentHeading: Double = 0.0 // degrees from true north

    // Step detection (PDR)
    private var lastAccelMagnitude: Double = 0.0
    private var accelPeak: Double = 0.0
    private var accelTrough: Double = Double.MAX_VALUE
    private var lastStepTimeMs: Long = 0
    private var stepCount: Int = 0
    private var isAscending: Boolean = false

    // Vehicle mode integration
    private var velocityX: Double = 0.0
    private var velocityY: Double = 0.0
    private var lastSensorTimeNs: Long = 0
    private var filteredAccelX: Double = 0.0
    private var filteredAccelY: Double = 0.0

    // Heading from rotation matrix
    private val gravity = FloatArray(3)
    private val geomagnetic = FloatArray(3)
    private var hasGravity = false
    private var hasMagnetic = false

    // Sensors
    private var sensorManager: SensorManager? = null
    private var sensorThread: HandlerThread? = null
    private var sensorHandler: Handler? = null
    private val accelListener = AccelListener()
    private val magnetListener = MagnetListener()

    // Main thread for callbacks and timers
    private val mainHandler = Handler(Looper.getMainLooper())
    private var emitRunnable: Runnable? = null
    private var maxDurationRunnable: Runnable? = null

    // Activity type for algorithm selection
    private var activityType: String = "unknown"

    /** Callback: emits estimated location data. */
    var onEstimatedLocation: ((Map<String, Any?>) -> Unit)? = null

    /** Callback: notifies when dead reckoning auto-stops (max duration). */
    var onDeactivated: (() -> Unit)? = null

    // =========================================================================
    // Public API
    // =========================================================================

    /**
     * Activate dead reckoning from the last known GPS position.
     *
     * @param lat Last GPS latitude
     * @param lng Last GPS longitude
     * @param altitude Last GPS altitude
     * @param heading Last GPS heading (degrees)
     * @param activity Current detected activity type (e.g. "walking", "in_vehicle")
     */
    fun activate(
        lat: Double,
        lng: Double,
        altitude: Double,
        heading: Double,
        activity: String,
    ) {
        if (isActive) return

        currentLat = lat
        currentLng = lng
        currentAltitude = altitude
        currentHeading = if (heading >= 0) heading else 0.0
        activityType = activity
        activationTimeMs = System.currentTimeMillis()
        isActive = true

        // Reset state
        stepCount = 0
        lastStepTimeMs = 0
        accelPeak = 0.0
        accelTrough = Double.MAX_VALUE
        isAscending = false
        velocityX = 0.0
        velocityY = 0.0
        lastSensorTimeNs = 0
        filteredAccelX = 0.0
        filteredAccelY = 0.0
        hasGravity = false
        hasMagnetic = false

        Log.d(TAG, "Activated at ($lat, $lng), heading=$heading, activity=$activity")

        startSensors()
        startEmitTimer()
        startMaxDurationTimer()
    }

    /** Deactivate dead reckoning and release all sensor resources. */
    fun deactivate() {
        if (!isActive) return
        isActive = false

        stopSensors()
        stopEmitTimer()
        stopMaxDurationTimer()

        Log.d(TAG, "Deactivated after ${getElapsedSeconds()}s, $stepCount steps")
    }

    /** Returns the current DR state, or null if not active. */
    fun getState(): Map<String, Any?>? {
        if (!isActive) return null
        val elapsed = getElapsedSeconds()
        return mapOf(
            "active" to true,
            "elapsed" to elapsed,
            "estimatedAccuracy" to computeAccuracy(elapsed),
            "latitude" to currentLat,
            "longitude" to currentLng,
            "heading" to currentHeading,
            "stepCount" to stepCount,
            "activityType" to activityType,
        )
    }

    // =========================================================================
    // Sensor management
    // =========================================================================

    private fun startSensors() {
        sensorThread = HandlerThread("DeadReckoningSensors").apply { start() }
        sensorHandler = Handler(sensorThread!!.looper)

        val sm = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager ?: return
        sensorManager = sm

        // Accelerometer for step detection / acceleration integration
        sm.getDefaultSensor(Sensor.TYPE_LINEAR_ACCELERATION)?.let { sensor ->
            sm.registerListener(accelListener, sensor, SENSOR_DELAY_US, sensorHandler)
        } ?: run {
            // Fallback: use raw accelerometer (includes gravity)
            sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)?.let { sensor ->
                sm.registerListener(accelListener, sensor, SENSOR_DELAY_US, sensorHandler)
            }
        }

        // Magnetometer for heading
        sm.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)?.let { sensor ->
            sm.registerListener(magnetListener, sensor, SENSOR_DELAY_US, sensorHandler)
        }

        // Gravity sensor for rotation matrix (separate from linear acceleration)
        sm.getDefaultSensor(Sensor.TYPE_GRAVITY)?.let { sensor ->
            sm.registerListener(gravityListener, sensor, SENSOR_DELAY_US, sensorHandler)
        }
    }

    private fun stopSensors() {
        sensorManager?.let { sm ->
            sm.unregisterListener(accelListener)
            sm.unregisterListener(magnetListener)
            sm.unregisterListener(gravityListener)
        }
        sensorManager = null

        sensorThread?.quitSafely()
        sensorThread = null
        sensorHandler = null
    }

    // =========================================================================
    // Sensor listeners
    // =========================================================================

    private inner class AccelListener : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            if (!isActive) return

            val x = event.values[0].toDouble()
            val y = event.values[1].toDouble()
            val z = event.values[2].toDouble()
            val magnitude = sqrt(x * x + y * y + z * z)

            if (isVehicleMode()) {
                processVehicleAcceleration(x, y, event.timestamp)
            } else {
                processStepDetection(magnitude)
            }
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }

    private inner class MagnetListener : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            if (!isActive) return
            geomagnetic[0] = event.values[0]
            geomagnetic[1] = event.values[1]
            geomagnetic[2] = event.values[2]
            hasMagnetic = true
            updateHeading()
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }

    private val gravityListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            if (!isActive) return
            gravity[0] = event.values[0]
            gravity[1] = event.values[1]
            gravity[2] = event.values[2]
            hasGravity = true
            updateHeading()
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }

    // =========================================================================
    // Heading computation
    // =========================================================================

    private fun updateHeading() {
        if (!hasGravity || !hasMagnetic) return

        val rotationMatrix = FloatArray(9)
        val inclinationMatrix = FloatArray(9)
        if (!SensorManager.getRotationMatrix(rotationMatrix, inclinationMatrix, gravity, geomagnetic)) {
            return
        }

        val orientation = FloatArray(3)
        SensorManager.getOrientation(rotationMatrix, orientation)

        // orientation[0] = azimuth in radians (-π to π)
        var azimuthDeg = Math.toDegrees(orientation[0].toDouble())
        if (azimuthDeg < 0) azimuthDeg += 360.0
        currentHeading = azimuthDeg
    }

    // =========================================================================
    // Pedestrian Dead Reckoning (PDR) — step detection
    // =========================================================================

    /**
     * Step detection via peak-trough analysis on acceleration magnitude.
     * Uses Weinberg step length estimation: stepLength = K * (peak - trough)^0.25
     */
    private fun processStepDetection(magnitude: Double) {
        val now = System.currentTimeMillis()

        // Track peaks and troughs
        if (magnitude > lastAccelMagnitude) {
            if (!isAscending && lastAccelMagnitude < accelTrough) {
                accelTrough = lastAccelMagnitude
            }
            isAscending = true
        } else {
            if (isAscending && lastAccelMagnitude > accelPeak) {
                accelPeak = lastAccelMagnitude
            }
            isAscending = false

            // Check for step: peak-to-trough exceeds threshold
            val diff = accelPeak - accelTrough
            if (diff > STEP_THRESHOLD) {
                val timeSinceLastStep = now - lastStepTimeMs
                if (timeSinceLastStep >= MIN_STEP_INTERVAL_MS) {
                    // Valid step detected
                    val stepLength = estimateStepLength(diff)
                    advancePosition(stepLength)
                    stepCount++
                    lastStepTimeMs = now

                    // Reset peak/trough for next step
                    accelPeak = 0.0
                    accelTrough = Double.MAX_VALUE
                }
            }
        }

        // Reset peak detector if no step for too long (stopped walking?)
        if (lastStepTimeMs > 0 && (now - lastStepTimeMs) > MAX_STEP_INTERVAL_MS) {
            accelPeak = 0.0
            accelTrough = Double.MAX_VALUE
        }

        lastAccelMagnitude = magnitude
    }

    /**
     * Estimate step length using the Weinberg formula.
     * stepLength = K * (accelPeak - accelTrough)^0.25
     * K ≈ 0.7 for average adult walking
     */
    private fun estimateStepLength(peakToDiff: Double): Double {
        return 0.7 * peakToDiff.pow(0.25)
    }

    // =========================================================================
    // Vehicle mode — acceleration integration
    // =========================================================================

    /**
     * For vehicle/cycling: integrate linear acceleration to estimate displacement.
     * Uses a high-pass filter to reduce drift from sensor bias.
     */
    private fun processVehicleAcceleration(ax: Double, ay: Double, timestampNs: Long) {
        if (lastSensorTimeNs == 0L) {
            lastSensorTimeNs = timestampNs
            return
        }

        val dt = (timestampNs - lastSensorTimeNs) / 1_000_000_000.0
        lastSensorTimeNs = timestampNs

        if (dt <= 0 || dt > 0.5) return // Skip invalid intervals

        // High-pass filter to remove low-frequency drift
        filteredAccelX = HIGH_PASS_ALPHA * (filteredAccelX + ax)
        filteredAccelY = HIGH_PASS_ALPHA * (filteredAccelY + ay)

        // Integrate acceleration → velocity
        velocityX += filteredAccelX * dt
        velocityY += filteredAccelY * dt

        // Apply velocity damping to prevent runaway drift
        velocityX *= 0.98
        velocityY *= 0.98

        // Integrate velocity → displacement (in device frame)
        val dx = velocityX * dt
        val dy = velocityY * dt

        // Transform from device frame to world frame using heading
        val headingRad = Math.toRadians(currentHeading)
        val worldDx = dx * cos(headingRad) - dy * sin(headingRad)
        val worldDy = dx * sin(headingRad) + dy * cos(headingRad)

        // Convert meters to degrees
        val metersPerDegLng = METERS_PER_DEG_LAT * cos(Math.toRadians(currentLat))
        currentLat += worldDy / METERS_PER_DEG_LAT
        currentLng += worldDx / metersPerDegLng
    }

    // =========================================================================
    // Position advancement (PDR)
    // =========================================================================

    /** Advance position by [stepLength] meters in the current heading direction. */
    private fun advancePosition(stepLength: Double) {
        val headingRad = Math.toRadians(currentHeading)

        // North displacement = stepLength * cos(heading)
        // East displacement = stepLength * sin(heading)
        val metersPerDegLng = METERS_PER_DEG_LAT * cos(Math.toRadians(currentLat))

        currentLat += (stepLength * cos(headingRad)) / METERS_PER_DEG_LAT
        currentLng += (stepLength * sin(headingRad)) / metersPerDegLng
    }

    // =========================================================================
    // Location emission
    // =========================================================================

    private fun startEmitTimer() {
        emitRunnable = object : Runnable {
            override fun run() {
                if (!isActive) return
                emitLocation()
                mainHandler.postDelayed(this, EMIT_INTERVAL_MS)
            }
        }
        mainHandler.postDelayed(emitRunnable!!, EMIT_INTERVAL_MS)
    }

    private fun stopEmitTimer() {
        emitRunnable?.let { mainHandler.removeCallbacks(it) }
        emitRunnable = null
    }

    private fun emitLocation() {
        val elapsed = getElapsedSeconds()
        val accuracy = computeAccuracy(elapsed)

        val location = mapOf<String, Any?>(
            "latitude" to currentLat,
            "longitude" to currentLng,
            "altitude" to currentAltitude,
            "heading" to currentHeading,
            "accuracy" to accuracy,
            "speed" to estimateSpeed(),
            "elapsed" to elapsed,
            "isDeadReckoned" to true,
        )

        onEstimatedLocation?.invoke(location)
    }

    // =========================================================================
    // Max duration auto-stop
    // =========================================================================

    private fun startMaxDurationTimer() {
        val maxDurationMs = config.getDeadReckoningMaxDuration() * 1000L
        maxDurationRunnable = Runnable {
            Log.d(TAG, "Max duration reached (${config.getDeadReckoningMaxDuration()}s)")
            deactivate()
            onDeactivated?.invoke()
        }
        mainHandler.postDelayed(maxDurationRunnable!!, maxDurationMs)
    }

    private fun stopMaxDurationTimer() {
        maxDurationRunnable?.let { mainHandler.removeCallbacks(it) }
        maxDurationRunnable = null
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    private fun getElapsedSeconds(): Int {
        return ((System.currentTimeMillis() - activationTimeMs) / 1000).toInt()
    }

    /** Accuracy degrades linearly with time. */
    private fun computeAccuracy(elapsedSeconds: Int): Double {
        return if (isVehicleMode()) {
            10.0 + elapsedSeconds * 3.0
        } else {
            5.0 + elapsedSeconds * 1.0
        }
    }

    /** Estimate current speed from step frequency or velocity magnitude. */
    private fun estimateSpeed(): Double {
        if (isVehicleMode()) {
            return sqrt(velocityX * velocityX + velocityY * velocityY)
        }
        // Pedestrian: estimate from recent step timing
        val timeSinceLastStep = System.currentTimeMillis() - lastStepTimeMs
        return if (lastStepTimeMs > 0 && timeSinceLastStep < MAX_STEP_INTERVAL_MS) {
            // Average walking speed ~1.4 m/s
            0.7 * STEP_THRESHOLD.pow(0.25) * 1000.0 / timeSinceLastStep.coerceAtLeast(250)
        } else {
            0.0
        }
    }

    private fun isVehicleMode(): Boolean {
        return activityType in listOf("in_vehicle", "on_bicycle")
    }
}
