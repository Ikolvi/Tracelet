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
import android.os.SystemClock
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

    /** Optional callback invoked on every accepted location (for geofenceModeHighAccuracy). */
    var onLocationUpdate: ((Double, Double) -> Unit)? = null

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
     * One-shot current position with configurable accuracy and sampling.
     *
     * Supported [options]:
     * - `desiredAccuracy` (Int): Accuracy level override.
     * - `timeout` (Long): Timeout in seconds (default 30).
     * - `maximumAge` (Long): Max age in ms of acceptable cached location.
     * - `persist` (Boolean): Whether to persist to DB (default true).
     * - `samples` (Int): Number of samples to collect; returns best accuracy (default 1).
     * - `extras` (Map): Extra data to attach to the location.
     *
     * [callback] receives the enriched location map or null.
     */
    fun getCurrentPosition(options: Map<String, Any?>, callback: (Map<String, Any?>?) -> Unit) {
        if (!hasPermission()) {
            callback(null)
            return
        }

        val timeout = (options["timeout"] as? Number)?.toLong() ?: 30L
        val desiredAccuracy = (options["desiredAccuracy"] as? Number)?.toInt()
            ?: config.getDesiredAccuracy()
        val maximumAge = (options["maximumAge"] as? Number)?.toLong() ?: 0L
        val persist = options["persist"] as? Boolean ?: true
        val samples = (options["samples"] as? Number)?.toInt()?.coerceAtLeast(1) ?: 1
        @Suppress("UNCHECKED_CAST")
        val extras = options["extras"] as? Map<String, Any?> ?: emptyMap()
        val priority = accuracyToPriority(desiredAccuracy)

        // Check if a cached location satisfies maximumAge
        if (maximumAge > 0) {
            val cached = lastLocation
            if (cached != null) {
                val age = System.currentTimeMillis() - cached.time
                if (age <= maximumAge) {
                    val enriched = enrichLocation(cached, "getCurrentPosition").toMutableMap()
                    if (extras.isNotEmpty()) enriched["extras"] = extras
                    if (persist) db.insertLocationAsync(enriched)
                    callback(enriched)
                    return
                }
            }
        }

        // Multi-sample collection
        if (samples > 1) {
            collectSamples(priority, samples, timeout, persist, extras, callback)
            return
        }

        // Single sample
        try {
            fusedClient.getCurrentLocation(priority, null)
                .addOnSuccessListener { location ->
                    if (location != null) {
                        val enriched = enrichLocation(location, "getCurrentPosition").toMutableMap()
                        if (extras.isNotEmpty()) enriched["extras"] = extras
                        if (persist) db.insertLocationAsync(enriched)
                        callback(enriched)
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
     * Returns the last known location from the fused provider cache.
     *
     * This never activates any location provider — it is a zero-battery-cost
     * operation. Returns null if no cached location is available.
     *
     * Supported [options]:
     * - `persist` (Boolean): Whether to persist to DB (default false).
     * - `extras` (Map): Extra data to attach to the location.
     */
    fun getLastKnownLocation(options: Map<String, Any?>, callback: (Map<String, Any?>?) -> Unit) {
        if (!hasPermission()) {
            callback(null)
            return
        }

        val persist = options["persist"] as? Boolean ?: false
        @Suppress("UNCHECKED_CAST")
        val extras = options["extras"] as? Map<String, Any?> ?: emptyMap()

        // 1. Check our own in-memory cache first (most reliable).
        val cached = lastLocation
        if (cached != null) {
            val enriched = enrichLocation(cached, "getLastKnownLocation").toMutableMap()
            if (extras.isNotEmpty()) enriched["extras"] = extras
            if (persist) db.insertLocationAsync(enriched)
            callback(enriched)
            return
        }

        // 2. Try FusedLocationProviderClient cache.
        try {
            fusedClient.lastLocation
                .addOnSuccessListener { location ->
                    if (location != null) {
                        lastLocation = location
                        val enriched = enrichLocation(location, "getLastKnownLocation").toMutableMap()
                        if (extras.isNotEmpty()) enriched["extras"] = extras
                        if (persist) db.insertLocationAsync(enriched)
                        callback(enriched)
                    } else {
                        // 3. Fallback to system LocationManager — works even when
                        //    FusedLocationProviderClient has no cache.
                        val fallback = getSystemLastKnownLocation()
                        if (fallback != null) {
                            lastLocation = fallback
                            val enriched = enrichLocation(fallback, "getLastKnownLocation").toMutableMap()
                            if (extras.isNotEmpty()) enriched["extras"] = extras
                            if (persist) db.insertLocationAsync(enriched)
                            callback(enriched)
                        } else {
                            callback(null)
                        }
                    }
                }
                .addOnFailureListener {
                    // Fallback to system LocationManager on failure too.
                    val fallback = getSystemLastKnownLocation()
                    if (fallback != null) {
                        lastLocation = fallback
                        val enriched = enrichLocation(fallback, "getLastKnownLocation").toMutableMap()
                        if (extras.isNotEmpty()) enriched["extras"] = extras
                        if (persist) db.insertLocationAsync(enriched)
                        callback(enriched)
                    } else {
                        callback(null)
                    }
                }
        } catch (e: SecurityException) {
            callback(null)
        }
    }

    /**
     * Fallback: queries the Android [LocationManager] for cached GPS /
     * network locations. Returns the most recent one, or null.
     */
    private fun getSystemLastKnownLocation(): Location? {
        val lm = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            ?: return null
        return try {
            val gps = lm.getLastKnownLocation(LocationManager.GPS_PROVIDER)
            val network = lm.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
            when {
                gps != null && network != null ->
                    if (gps.time >= network.time) gps else network
                gps != null -> gps
                else -> network
            }
        } catch (_: SecurityException) {
            null
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

        // --- Compute speed from distance/time as fallback ---
        // GPS-reported speed can be 0 when walking slowly, during cold starts,
        // or when the provider doesn't calculate speed. We compute it ourselves
        // from consecutive location pairs so that speed is always available.
        val timeDelta = if (lastLocation != null) {
            (location.time - lastLocation!!.time).toDouble() / 1000.0 // seconds
        } else {
            0.0
        }
        val computedSpeed = if (distance > 0 && timeDelta > 0) distance / timeDelta else 0.0

        // Use platform speed if available, otherwise use computed speed
        val effectiveSpeed = if (location.hasSpeed() && location.speed > 0) {
            location.speed.toDouble()
        } else {
            computedSpeed
        }

        // --- Elasticity: dynamically scale distanceFilter based on speed ---
        val baseDistance = config.getDistanceFilter()
        val effectiveDistance = if (!config.getDisableElasticity() && effectiveSpeed > 0) {
            val multiplier = config.getElasticityMultiplier().coerceAtLeast(0.1)
            // Scale: faster speed → larger distance filter
            val speedFactor = (effectiveSpeed / 10.0).coerceIn(1.0, 10.0)
            baseDistance * speedFactor * multiplier
        } else {
            baseDistance
        }

        // Check distance filter (using elasticity-adjusted value)
        if (lastLocation != null && distance < effectiveDistance) {
            return // Below distance filter threshold
        }

        // --- Location Filtering / Denoising ---
        val trackingAccuracyThreshold = config.getTrackingAccuracyThreshold()
        if (trackingAccuracyThreshold > 0 && location.accuracy > trackingAccuracyThreshold) {
            // Location accuracy too poor
            val policy = config.getFilterPolicy() // 0=adjust, 1=ignore, 2=discard
            when (policy) {
                2 -> { // discard: drop + emit error event
                    events.sendLocation(mapOf("error" to "ACCURACY_FILTER", "message" to "Location accuracy ${location.accuracy}m exceeds threshold ${trackingAccuracyThreshold}m"))
                    return
                }
                1 -> return // ignore: drop silently
                else -> { /* adjust: fall through — use last-known-good if available */
                    if (lastLocation != null) return // skip this inaccurate point
                }
            }
        }

        val maxImpliedSpeed = config.getMaxImpliedSpeed()
        if (maxImpliedSpeed > 0 && lastLocation != null) {
            if (timeDelta > 0) {
                val impliedSpeed = distance / timeDelta // m/s
                if (impliedSpeed > maxImpliedSpeed) {
                    val policy = config.getFilterPolicy()
                    when (policy) {
                        2 -> {
                            events.sendLocation(mapOf("error" to "SPEED_FILTER", "message" to "Implied speed ${impliedSpeed}m/s exceeds max ${maxImpliedSpeed}m/s"))
                            return
                        }
                        1 -> return
                        else -> return // adjust: reject impossible speed
                    }
                }
            }
        }

        // Odometer accuracy check: only add to odometer if accurate enough
        val odometerAccuracyThreshold = config.getOdometerAccuracyThreshold()
        val addToOdometer = odometerAccuracyThreshold <= 0 || location.accuracy <= odometerAccuracyThreshold
        if (addToOdometer) {
            state.addOdometer(distance)
        }
        lastLocation = location
        state.lastLocationTime = location.time

        val enriched = enrichLocation(location, event, effectiveSpeed)

        // Persist to database (respecting persistMode)
        persistLocationIfAllowed(enriched, event)

        // Dispatch to Dart
        events.sendLocation(enriched)

        // Notify geofenceModeHighAccuracy listener (if active)
        onLocationUpdate?.invoke(location.latitude, location.longitude)
    }

    /**
     * Enriches a raw [Location] into a full map ready for Dart/DB.
     *
     * @param location   The raw platform location.
     * @param event      The event name (e.g. "motionchange").
     * @param speed      Pre-computed effective speed (m/s). Uses platform speed
     *                   if available, otherwise distance/time from consecutive
     *                   locations. Pass `null` to fall back to platform speed.
     */
    private fun enrichLocation(location: Location, event: String, speed: Double? = null): Map<String, Any?> {
        val battery = BatteryUtils.getBatteryInfo(context)
        val isoFormatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
        val timestamp = isoFormatter.format(Date(location.time))

        // Use provided effective speed, or fall back to platform speed.
        val effectiveSpeed = speed ?: location.speed.toDouble()

        val result = mutableMapOf<String, Any?>(
            "uuid" to UUID.randomUUID().toString(),
            "timestamp" to timestamp,
            "isMoving" to state.isMoving,
            "odometer" to state.odometer,
            "event" to event,
            "coords" to mapOf(
                "latitude" to location.latitude,
                "longitude" to location.longitude,
                "altitude" to location.altitude,
                "speed" to effectiveSpeed,
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
            "speed" to effectiveSpeed,
            "heading" to location.bearing.toDouble(),
            "accuracy" to location.accuracy.toDouble(),
            "batteryLevel" to (battery["level"] as? Double ?: -1.0),
            "batteryCharging" to (battery["isCharging"] as? Boolean ?: false),
            "activityType" to currentActivityType,
            "activityConfidence" to currentActivityConfidence,
        )

        // enableTimestampMeta: attach additional timing metadata
        if (config.getEnableTimestampMeta()) {
            result["timestampMeta"] = mapOf(
                "time" to location.time,
                "systemTime" to System.currentTimeMillis(),
                "systemClockElapsedRealtime" to SystemClock.elapsedRealtime(),
            )
        }

        return result
    }

    /**
     * Collects [count] location samples using repeated [getCurrentLocation] calls
     * and returns the one with the best (lowest) horizontal accuracy.
     *
     * Uses the one-shot [getCurrentLocation] API which works reliably on all
     * devices, even without a foreground service. This avoids the issue where
     * [requestLocationUpdates] is throttled or blocked by aggressive battery
     * optimization on budget Android devices.
     */
    private fun collectSamples(
        priority: Int,
        count: Int,
        timeoutSeconds: Long,
        persist: Boolean,
        extras: Map<String, Any?>,
        callback: (Map<String, Any?>?) -> Unit,
    ) {
        val collected = mutableListOf<Location>()
        val handler = android.os.Handler(Looper.getMainLooper())
        var finished = false

        // Timeout guard — deliver whatever we have when time runs out.
        handler.postDelayed({
            if (!finished) {
                finished = true
                if (collected.isNotEmpty()) {
                    deliver(collected, persist, extras, callback)
                } else {
                    callback(null)
                }
            }
        }, timeoutSeconds * 1000L)

        // Fire sequential getCurrentLocation calls on the main thread.
        fun fetchNext() {
            if (finished) return
            try {
                fusedClient.getCurrentLocation(priority, null)
                    .addOnSuccessListener { location ->
                        if (finished) return@addOnSuccessListener
                        if (location != null) {
                            collected.add(location)
                        }
                        if (collected.size >= count) {
                            finished = true
                            deliver(collected, persist, extras, callback)
                        } else {
                            // Small delay between samples to let GPS settle
                            handler.postDelayed({ fetchNext() }, 800L)
                        }
                    }
                    .addOnFailureListener {
                        if (finished) return@addOnFailureListener
                        // Continue trying even if one sample fails
                        handler.postDelayed({ fetchNext() }, 800L)
                    }
            } catch (_: SecurityException) {
                if (!finished) {
                    finished = true
                    callback(null)
                }
            }
        }

        fetchNext()
    }

    /**
     * Picks the best-accuracy location from [samples] and delivers it.
     */
    private fun deliver(
        samples: List<Location>,
        persist: Boolean,
        extras: Map<String, Any?>,
        callback: (Map<String, Any?>?) -> Unit,
    ) {
        val best = samples.minByOrNull { it.accuracy } ?: run {
            callback(null)
            return
        }
        val enriched = enrichLocation(best, "getCurrentPosition").toMutableMap()
        if (extras.isNotEmpty()) enriched["extras"] = extras
        if (persist) db.insertLocationAsync(enriched)
        callback(enriched)
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

    /**
     * Persists a location to the database only if allowed by persistMode.
     * Also runs retention pruning (maxDaysToPersist / maxRecordsToPersist).
     *
     * persistMode: 0 = all, 1 = location only, 2 = geofence only, 3 = none
     */
    private fun persistLocationIfAllowed(location: Map<String, Any?>, event: String) {
        val persistMode = config.getPersistMode()
        // Mode 3 = none, Mode 2 = geofence only → skip location inserts
        if (persistMode == 3 || persistMode == 2) return
        // Mode 1 = location only → fine for location events
        // Skip provider change records if disabled
        if (event == "providerchange" && config.getDisableProviderChangeRecord()) return

        db.insertLocationAsync(location)

        // Enforce retention limits
        val maxDays = config.getMaxDaysToPersist()
        if (maxDays > 0) db.pruneOldLocations(maxDays)
        val maxRecords = config.getMaxRecordsToPersist()
        if (maxRecords > 0) db.enforceMaxRecords(maxRecords)
    }
}
