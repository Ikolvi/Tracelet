package com.tracelet.tracelet_android.location

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Looper
import androidx.core.content.ContextCompat
import com.google.android.gms.location.*
import com.tracelet.tracelet_android.ConfigManager
import com.tracelet.tracelet_android.EventDispatcher
import com.tracelet.tracelet_android.StateManager
import com.tracelet.tracelet_android.db.TraceletDatabase
import com.tracelet.tracelet_android.util.BatteryUtils
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * Core location tracking engine wrapping FusedLocationProviderClient.
 *
 * Handles:
 * - Continuous location tracking (start/stop)
 * - One-shot getCurrentPosition
 * - watchPosition (multiple concurrent watchers)
 * - Odometer calculation
 * - Location result enrichment (UUID, battery, activity, odometer)
 * - Persist to SQLite and dispatch to EventChannels
 */
class LocationEngine(
    private val context: Context,
    private val config: ConfigManager,
    private val state: StateManager,
    private val events: EventDispatcher,
    private val db: TraceletDatabase,
) {
    private val fusedClient: FusedLocationProviderClient =
        LocationServices.getFusedLocationProviderClient(context)

    private var trackingCallback: LocationCallback? = null
    private var lastLocation: Location? = null
    private var currentActivityType: String = "unknown"
    private var currentActivityConfidence: Int = -1

    // watchPosition watchers: watchId -> LocationCallback
    private val watchers = ConcurrentHashMap<Int, LocationCallback>()
    private var nextWatchId = 1

    /** Whether continuous tracking is active. */
    val isTracking: Boolean get() = trackingCallback != null

    /**
     * Starts continuous location tracking based on current config.
     */
    fun start() {
        if (!hasPermission()) return
        stop() // Ensure clean state

        val request = buildLocationRequest()

        trackingCallback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                for (location in result.locations) {
                    onLocationReceived(location, "motionchange")
                }
            }

            override fun onLocationAvailability(availability: LocationAvailability) {
                if (!availability.isLocationAvailable) {
                    events.sendProviderChange(buildProviderState())
                }
            }
        }

        try {
            fusedClient.requestLocationUpdates(request, trackingCallback!!, Looper.getMainLooper())
            state.enabled = true
        } catch (e: SecurityException) {
            trackingCallback = null
        }
    }

    /** Stops continuous location tracking. */
    fun stop() {
        trackingCallback?.let {
            fusedClient.removeLocationUpdates(it)
            trackingCallback = null
        }
        state.enabled = false
    }

    /**
     * One-shot current position with high accuracy.
     * [callback] receives the enriched location map or null.
     */
    fun getCurrentPosition(options: Map<String, Any?>, callback: (Map<String, Any?>?) -> Unit) {
        if (!hasPermission()) {
            callback(null)
            return
        }

        val timeout = (options["timeout"] as? Number)?.toLong() ?: 30000L
        val desiredAccuracy = (options["desiredAccuracy"] as? Number)?.toInt()
            ?: config.getDesiredAccuracy()
        val priority = accuracyToPriority(desiredAccuracy)

        try {
            fusedClient.getCurrentLocation(priority, null)
                .addOnSuccessListener { location ->
                    if (location != null) {
                        callback(enrichLocation(location, "getCurrentPosition"))
                    } else {
                        callback(null)
                    }
                }
                .addOnFailureListener {
                    callback(null)
                }
        } catch (e: SecurityException) {
            callback(null)
        }
    }

    /**
     * Starts a watch position with the given options.
     * Returns the watchId.
     */
    fun watchPosition(options: Map<String, Any?>): Int {
        if (!hasPermission()) return -1

        val watchId = nextWatchId++
        val interval = (options["interval"] as? Number)?.toLong() ?: 1000L
        val distanceFilter = (options["distanceFilter"] as? Number)?.toFloat() ?: 0f
        val desiredAccuracy = (options["desiredAccuracy"] as? Number)?.toInt() ?: 0
        val priority = accuracyToPriority(desiredAccuracy)

        val request = LocationRequest.Builder(priority, interval)
            .setMinUpdateDistanceMeters(distanceFilter)
            .build()

        val watchCallback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                for (location in result.locations) {
                    val data = enrichLocation(location, "watchPosition")
                    data.toMutableMap().apply {
                        this["watchId"] = watchId
                        events.sendWatchPosition(this)
                    }
                }
            }
        }

        try {
            fusedClient.requestLocationUpdates(request, watchCallback, Looper.getMainLooper())
            watchers[watchId] = watchCallback
        } catch (e: SecurityException) {
            return -1
        }

        return watchId
    }

    /** Stops a specific watch position. */
    fun stopWatchPosition(watchId: Int): Boolean {
        val callback = watchers.remove(watchId) ?: return false
        fusedClient.removeLocationUpdates(callback)
        return true
    }

    /** Stops all watch positions. */
    fun stopAllWatchers() {
        for ((_, callback) in watchers) {
            fusedClient.removeLocationUpdates(callback)
        }
        watchers.clear()
    }

    /**
     * Toggle pace: if [isMoving] is true, switch to high-frequency tracking;
     * if false, stop location updates (simulate stationary).
     */
    fun changePace(isMoving: Boolean): Boolean {
        state.isMoving = isMoving
        if (isMoving && !isTracking) {
            start()
        } else if (!isMoving && isTracking) {
            stop()
        }
        // Dispatch motionChange event
        val locationMap = lastLocation?.let { enrichLocation(it, "motionchange") }
            ?: mapOf("isMoving" to isMoving)
        events.sendMotionChange(locationMap)
        return true
    }

    /** Returns the current odometer value. */
    fun getOdometer(): Double = state.odometer

    /** Sets the odometer to a specific value. */
    fun setOdometer(value: Double): Map<String, Any?> {
        state.odometer = value
        return lastLocation?.let { enrichLocation(it, "setOdometer") }
            ?: mapOf("odometer" to value)
    }

    /** Updates the current activity (from MotionDetector). */
    fun setCurrentActivity(type: String, confidence: Int) {
        currentActivityType = type
        currentActivityConfidence = confidence
    }

    /** Returns the last known location or null. */
    fun getLastLocation(): Location? = lastLocation

    /** Returns provider state info. */
    fun buildProviderState(): Map<String, Any?> {
        val lm = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        val hasFine = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
        val hasCoarse = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
        val hasBackground = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION) ==
                PackageManager.PERMISSION_GRANTED

        val status = when {
            hasBackground -> 3 // ALWAYS
            hasFine || hasCoarse -> 2 // WHEN_IN_USE
            else -> 0 // DENIED
        }

        return mapOf(
            "enabled" to (lm?.isLocationEnabled ?: false),
            "status" to status,
            "gps" to (lm?.isProviderEnabled(LocationManager.GPS_PROVIDER) ?: false),
            "network" to (lm?.isProviderEnabled(LocationManager.NETWORK_PROVIDER) ?: false),
            "accuracyAuthorization" to if (hasFine) 0 else 1, // 0=full, 1=reduced
            "platform" to "android",
        )
    }

    /** Destroys resources. */
    fun destroy() {
        stop()
        stopAllWatchers()
    }

    // =========================================================================
    // Private methods
    // =========================================================================

    private fun onLocationReceived(location: Location, event: String) {
        // Calculate distance from last location for odometer
        val distance = lastLocation?.distanceTo(location)?.toDouble() ?: 0.0

        // Check distance filter
        val minDistance = config.getDistanceFilter()
        if (lastLocation != null && distance < minDistance) {
            return // Below distance filter threshold
        }

        state.addOdometer(distance)
        lastLocation = location
        state.lastLocationTime = location.time

        val enriched = enrichLocation(location, event)

        // Persist to database
        db.insertLocationAsync(enriched)

        // Dispatch to Dart
        events.sendLocation(enriched)
    }

    private fun enrichLocation(location: Location, event: String): Map<String, Any?> {
        val battery = BatteryUtils.getBatteryInfo(context)
        val isoFormatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
        val timestamp = isoFormatter.format(Date(location.time))
        return mapOf(
            "uuid" to UUID.randomUUID().toString(),
            "timestamp" to timestamp,
            "isMoving" to state.isMoving,
            "odometer" to state.odometer,
            "event" to event,
            "coords" to mapOf(
                "latitude" to location.latitude,
                "longitude" to location.longitude,
                "altitude" to location.altitude,
                "speed" to location.speed.toDouble(),
                "heading" to location.bearing.toDouble(),
                "accuracy" to location.accuracy.toDouble(),
                "speedAccuracy" to if (location.hasSpeedAccuracy()) location.speedAccuracyMetersPerSecond.toDouble() else -1.0,
                "headingAccuracy" to if (location.hasBearingAccuracy()) location.bearingAccuracyDegrees.toDouble() else -1.0,
                "altitudeAccuracy" to if (location.hasVerticalAccuracy()) location.verticalAccuracyMeters.toDouble() else -1.0,
            ),
            "activity" to mapOf(
                "type" to currentActivityType,
                "confidence" to currentActivityConfidence,
            ),
            "battery" to battery,
            // Flatten for DB insert (db expects flat keys)
            "latitude" to location.latitude,
            "longitude" to location.longitude,
            "altitude" to location.altitude,
            "speed" to location.speed.toDouble(),
            "heading" to location.bearing.toDouble(),
            "accuracy" to location.accuracy.toDouble(),
            "batteryLevel" to (battery["level"] as? Double ?: -1.0),
            "batteryCharging" to (battery["isCharging"] as? Boolean ?: false),
            "activityType" to currentActivityType,
            "activityConfidence" to currentActivityConfidence,
        )
    }

    private fun buildLocationRequest(): LocationRequest {
        val priority = accuracyToPriority(config.getDesiredAccuracy())
        return LocationRequest.Builder(priority, config.getLocationUpdateInterval())
            .setMinUpdateDistanceMeters(config.getDistanceFilter().toFloat())
            .setMinUpdateIntervalMillis(config.getFastestLocationUpdateInterval())
            .build()
    }

    private fun accuracyToPriority(accuracy: Int): Int {
        return when (accuracy) {
            0 -> Priority.PRIORITY_HIGH_ACCURACY       // high
            1 -> Priority.PRIORITY_BALANCED_POWER_ACCURACY // medium
            2 -> Priority.PRIORITY_LOW_POWER            // low
            3 -> Priority.PRIORITY_PASSIVE              // passive
            else -> Priority.PRIORITY_HIGH_ACCURACY
        }
    }

    private fun hasPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED ||
                ContextCompat.checkSelfPermission(
                    context, Manifest.permission.ACCESS_COARSE_LOCATION
                ) == PackageManager.PERMISSION_GRANTED
    }
}
