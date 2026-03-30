package com.ikolvi.tracelet.sdk.location

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.core.location.LocationManagerCompat
import com.google.android.gms.location.*
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.TraceletEventSender
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.audit.AuditTrailManager
import com.ikolvi.tracelet.sdk.privacy.PrivacyZoneManager
import com.ikolvi.tracelet.sdk.db.TraceletDatabase
import com.ikolvi.tracelet.sdk.util.BatteryUtils
import android.os.SystemClock
import android.os.Handler
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
    private val events: TraceletEventSender,
    private val db: TraceletDatabase,
) {
    companion object {
        private const val TAG = "LocationEngine"

        /** Cached ISO 8601 formatter — thread-confined to the main/location thread. */
        private val isoFormatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }

        /** Retention pruning runs every N inserts instead of on every insert. */
        private const val PRUNE_EVERY_N_INSERTS = 100

        /** Maximum accuracy (meters) to consider a fused fix as GPS-sourced. */
        const val GPS_ACCURACY_THRESHOLD = 50f

        /**
         * Determines if a location fix is GPS-sourced (not network/cell).
         * FusedLocationProvider uses "fused" as provider, so we also check
         * accuracy as a heuristic: GPS fixes typically have accuracy ≤ 50m.
         */
        fun isGpsFix(location: Location): Boolean {
            return location.provider == "gps" ||
                (location.provider == "fused" && location.accuracy <= GPS_ACCURACY_THRESHOLD)
        }

        /**
         * Checks whether the hardware GPS provider is enabled on the device.
         * Returns false when the user has toggled GPS off in system settings.
         */
        fun isGpsProviderEnabled(context: Context): Boolean {
            val lm = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            return lm?.isProviderEnabled(LocationManager.GPS_PROVIDER) ?: false
        }
    }

    private val fusedClient: FusedLocationProviderClient =
        LocationServices.getFusedLocationProviderClient(context)

    private var trackingCallback: LocationCallback? = null
    private var lastLocation: Location? = null
    /** Last GPS-quality location (accuracy ≤ 100m).
     *  Used by heartbeat to avoid returning low-accuracy significant-change fixes. */
    private var lastGpsLocation: Location? = null
    private var currentActivityType: String = "unknown"
    private var currentActivityConfidence: Int = -1

    /** Counter for throttling DB retention pruning — runs every N inserts. */
    private var insertCountSincePrune = 0

    /** Last computed effective speed (m/s) from tracking location updates.
     *  Used by the plugin for motionchange events since the cached Location.speed
     *  may be stale or 0. */
    var lastEffectiveSpeed: Double = 0.0
        private set

    /** Optional callback invoked on every accepted location (for geofenceModeHighAccuracy). */
    var onLocationUpdate: ((Double, Double) -> Unit)? = null

    /** Optional callback invoked after a location is persisted to the database.
     *  Used by the plugin to trigger HTTP auto-sync. */
    var onLocationPersisted: (() -> Unit)? = null

    /** Optional audit trail manager (Enterprise). Set by the plugin after construction. */
    var auditTrailManager: AuditTrailManager? = null

    /** Optional privacy zone manager (Enterprise). Set by the plugin after construction. */
    var privacyZoneManager: PrivacyZoneManager? = null

    // watchPosition watchers: watchId -> LocationCallback
    private val watchers = ConcurrentHashMap<Int, LocationCallback>()
    private var nextWatchId = 1

    /** Whether a mock location warning has already been fired for this session. */
    private var mockLocationWarningFired = false

    /**
     * Whether continuous tracking priority was auto-downgraded because the
     * GPS hardware provider is disabled (user toggled GPS off).
     *
     * When true, the engine is using [Priority.PRIORITY_BALANCED_POWER_ACCURACY]
     * to obtain Wi-Fi / cell tower fixes instead of the configured priority.
     * Once GPS is re-enabled, the engine restores the original priority and
     * re-subscribes to location updates.
     */
    private var gpsFallbackActive = false

    /** Whether continuous tracking is active. */
    val isTracking: Boolean get() = trackingCallback != null

    // =========================================================================
    // Dead Reckoning
    // =========================================================================

    private var deadReckoningEngine: DeadReckoningEngine? = null
    private val drHandler = Handler(Looper.getMainLooper())
    private var gpsLossRunnable: Runnable? = null

    /**
     * Starts continuous location tracking based on current config.
     *
     * If the GPS provider is disabled (user toggled GPS off in system
     * settings), the engine automatically downgrades to
     * [Priority.PRIORITY_BALANCED_POWER_ACCURACY] so that
     * Wi-Fi / cell-tower fixes are delivered instead of nothing.
     * When GPS is re-enabled, [restoreOriginalPriority] re-subscribes
     * with the configured accuracy.
     */
    fun start() {
        if (!hasPermission()) return
        stop() // Ensure clean state

        val request = buildLocationRequestWithGpsFallback()

        trackingCallback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                for (location in result.locations) {
                    onLocationReceived(location, "location")
                }
            }

            override fun onLocationAvailability(availability: LocationAvailability) {
                val providerState = buildProviderState()
                val gpsNowEnabled = providerState["gps"] as? Boolean ?: false

                if (gpsFallbackActive && gpsNowEnabled) {
                    // GPS was re-enabled — restore original priority.
                    Log.d(TAG, "GPS re-enabled — restoring original priority")
                    restoreOriginalPriority()
                } else if (!gpsFallbackActive && !gpsNowEnabled && isHighAccuracyConfigured()) {
                    // GPS just disabled while we were expecting it — downgrade.
                    Log.d(TAG, "GPS disabled during tracking — downgrading to Wi-Fi/cell")
                    activateGpsFallback()
                }

                if (!availability.isLocationAvailable) {
                    events.sendProviderChange(providerState)
                }
            }
        }

        try {
            fusedClient.requestLocationUpdates(request, trackingCallback!!, Looper.getMainLooper())
            state.enabled = true
            startGpsLossTimer()
        } catch (e: SecurityException) {
            trackingCallback = null
        }
    }

    /** Stops continuous location tracking. */
    fun stop() {
        gpsFallbackActive = false
        trackingCallback?.let {
            fusedClient.removeLocationUpdates(it)
            trackingCallback = null
        }
        stopPeriodic()
        deactivateDeadReckoning()
        cancelGpsLossTimer()
        state.enabled = false
    }

    // =========================================================================
    // Periodic one-shot tracking (foreground service + timer strategy)
    // =========================================================================

    private var periodicRunnable: Runnable? = null
    private val periodicHandler = android.os.Handler(Looper.getMainLooper())

    /** Whether periodic one-shot tracking is active. */
    val isPeriodicTracking: Boolean get() = periodicRunnable != null

    /**
     * Starts periodic one-shot location tracking using a Handler timer.
     *
     * This is the foreground-service strategy: the service stays alive with a
     * notification, but GPS is only activated for ~5 seconds per fix. Between
     * fixes the GPS radio is off and no GPS icon is shown.
     *
     * For the WorkManager strategy (no foreground service), see
     * [PeriodicLocationWorker].
     */
    fun startPeriodic() {
        if (!hasPermission()) {
            Log.w(TAG, "startPeriodic() — no location permission, aborting")
            return
        }
        stopPeriodic()

        val intervalMs = config.getPeriodicLocationInterval() * 1000L
        Log.d(TAG, "startPeriodic() — interval=${intervalMs}ms")

        periodicRunnable = object : Runnable {
            override fun run() {
                if (!state.enabled) {
                    Log.d(TAG, "periodic tick — state.enabled=false, skipping")
                    return
                }

                Log.d(TAG, "periodic tick — requesting one-shot fix")

                // Perform a one-shot fix using the periodic accuracy setting
                val options = mapOf<String, Any?>(
                    "desiredAccuracy" to config.getPeriodicDesiredAccuracy(),
                    "persist" to true,
                    "samples" to 1,
                )
                getCurrentPosition(options) { location ->
                    val resolved = location ?: run {
                        // Fallback: use last known location if fresh fix failed
                        Log.w(TAG, "periodic fix returned null — trying lastKnownLocation fallback")
                        val last = getLastLocation()
                        if (last != null) enrichLocation(last, "periodic") else null
                    }

                    if (resolved != null) {
                        val lat = resolved["latitude"] as? Double
                        val lng = resolved["longitude"] as? Double
                        val accuracy = resolved["accuracy"] as? Double
                            ?: (resolved["coords"] as? Map<*, *>)?.get("accuracy") as? Double
                            ?: 0.0

                        // Update odometer from distance since last periodic fix
                        if (lat != null && lng != null) {
                            val lastLat = state.lastPeriodicLatitude
                            val lastLng = state.lastPeriodicLongitude
                            if (!lastLat.isNaN() && !lastLng.isNaN()) {
                                val results = FloatArray(1)
                                android.location.Location.distanceBetween(
                                    lastLat, lastLng, lat, lng, results,
                                )
                                val distance = results[0].toDouble()
                                val threshold = config.getOdometerAccuracyThreshold()
                                if (threshold <= 0 || accuracy <= threshold) {
                                    state.addOdometer(distance)
                                }
                            }
                            state.lastPeriodicLatitude = lat
                            state.lastPeriodicLongitude = lng
                        }

                        // Enrich with periodic event tag and updated odometer
                        val enriched = resolved.toMutableMap()
                        enriched["event"] = "periodic"
                        enriched["odometer"] = state.odometer
                        events.sendLocation(enriched)
                        Log.d(TAG, "periodic fix dispatched — lat=$lat, lng=$lng, acc=$accuracy")

                        // Notify proximity-based geofence monitoring
                        if (lat != null && lng != null) {
                            onLocationUpdate?.invoke(lat, lng)
                        }
                    } else {
                        Log.w(TAG, "periodic fix — no location available (fresh + fallback both null)")
                    }
                }

                periodicHandler.postDelayed(this, intervalMs)
            }
        }

        // Fire immediately, then repeat at interval
        periodicHandler.post(periodicRunnable!!)
    }

    /** Stops periodic one-shot tracking. */
    fun stopPeriodic() {
        periodicRunnable?.let { periodicHandler.removeCallbacks(it) }
        periodicRunnable = null
        // Reset last periodic coordinates so the next start doesn't
        // compute distance from a stale position.
        state.lastPeriodicLatitude = Double.NaN
        state.lastPeriodicLongitude = Double.NaN
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
                    if (persist) {
                        db.insertLocationAsync(enriched)
                        onLocationPersisted?.invoke()
                    }
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
                    val resolved = location ?: lastLocation
                    if (resolved != null) {
                        val enriched = enrichLocation(resolved, "getCurrentPosition").toMutableMap()
                        if (extras.isNotEmpty()) enriched["extras"] = extras
                        if (persist) {
                            db.insertLocationAsync(enriched)
                            onLocationPersisted?.invoke()
                        }
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
            if (persist) {
                db.insertLocationAsync(enriched)
                onLocationPersisted?.invoke()
            }
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
                        if (persist) {
                            db.insertLocationAsync(enriched)
                            onLocationPersisted?.invoke()
                        }
                        callback(enriched)
                    } else {
                        // 3. Fallback to system LocationManager — works even when
                        //    FusedLocationProviderClient has no cache.
                        val fallback = getSystemLastKnownLocation()
                        if (fallback != null) {
                            lastLocation = fallback
                            val enriched = enrichLocation(fallback, "getLastKnownLocation").toMutableMap()
                            if (extras.isNotEmpty()) enriched["extras"] = extras
                            if (persist) {
                                db.insertLocationAsync(enriched)
                                onLocationPersisted?.invoke()
                            }
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
                        if (persist) {
                            db.insertLocationAsync(enriched)
                            onLocationPersisted?.invoke()
                        }
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
                    // enrichLocation() already returns a MutableMap; avoid
                    // unnecessary shallow copy from toMutableMap() (A-L3).
                    val data = enrichLocation(location, "watchPosition") as MutableMap<String, Any?>
                    data["watchId"] = watchId
                    events.sendWatchPosition(data)
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
        val locationMap = lastLocation?.let { enrichLocation(it, "motionchange", lastEffectiveSpeed) }
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

    /** Returns the best location for heartbeat: prefers the last GPS-quality
     *  fix (≤100m accuracy) over a potentially stale significant-change fix.
     *  Falls back to lastLocation if no GPS fix exists. */
    fun getLastGpsLocation(): Location? = lastGpsLocation ?: lastLocation

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
            "enabled" to (lm?.let { LocationManagerCompat.isLocationEnabled(it) } ?: false),
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
        // Only reset DR timer when GPS hardware is enabled AND the fix
        // is GPS-quality.  When the user has toggled GPS off,
        // FusedLocationProvider can still deliver accurate Wi-Fi / cell
        // fixes — those must NOT prevent DR from activating.
        val gpsEnabled = isGpsProviderEnabled(context)
        if (gpsEnabled && isGpsFix(location)) {
            resetGpsLossTimer()
            if (deadReckoningEngine?.isActive == true) {
                Log.d(TAG, "GPS signal recovered — deactivating dead reckoning")
                deactivateDeadReckoning()
            }
        }

        // --- Mock location rejection (defense-in-depth) ---
        if (config.getRejectMockLocations() && isLocationMock(location)) {
            // Fire a provider change event to notify Dart that mock was detected.
            if (!mockLocationWarningFired) {
                mockLocationWarningFired = true
                val providerState = buildProviderState().toMutableMap()
                providerState["mockLocationsDetected"] = true
                events.sendProviderChange(providerState)
            }
            return // Drop the mock location entirely.
        }

        // Calculate distance from last location for odometer
        val distance = lastLocation?.distanceTo(location)?.toDouble() ?: 0.0

        // --- Compute speed from distance/time as fallback ---
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

        // --- Filtering (elasticity, accuracy, speed) is now in shared Dart ---
        // LocationProcessor in tracelet_platform_interface handles all filtering.
        // Native sends ALL locations; Dart filters before delivering to user.

        // Odometer accuracy check: only add to odometer if accurate enough
        val odometerAccuracyThreshold = config.getOdometerAccuracyThreshold()
        val addToOdometer = odometerAccuracyThreshold <= 0 || location.accuracy <= odometerAccuracyThreshold
        if (addToOdometer) {
            state.addOdometer(distance)
        }
        lastLocation = location
        if (location.accuracy > 0 && location.accuracy <= 100) {
            lastGpsLocation = location
        }
        lastEffectiveSpeed = effectiveSpeed
        state.lastLocationTime = location.time

        val enriched = enrichLocation(location, event, effectiveSpeed)

        // Privacy zone check (Enterprise) — BEFORE audit + persist + send.
        // Evaluates whether the location falls inside a registered privacy zone
        // and applies the configured action (exclude / degrade / event-only).
        val privacyResult = privacyZoneManager?.processLocation(enriched)
        if (privacyResult != null) {
            when (privacyResult.action) {
                PrivacyZoneManager.ProcessedLocation.Action.DROP -> {
                    // Exclusion zone — drop this location entirely.
                    return
                }
                PrivacyZoneManager.ProcessedLocation.Action.EVENT_ONLY -> {
                    // Dispatch to Dart but do NOT persist or audit.
                    val locationData = privacyResult.location ?: enriched
                    events.sendLocation(locationData)
                    onLocationUpdate?.invoke(location.latitude, location.longitude)
                    return
                }
                PrivacyZoneManager.ProcessedLocation.Action.DEGRADED -> {
                    // Use the degraded location for audit + persist + dispatch.
                    val degraded = privacyResult.location ?: enriched
                    val auditFields = auditTrailManager?.appendToChain(degraded)
                    val withAudit = if (auditFields != null) {
                        degraded.toMutableMap().apply { putAll(auditFields) }
                    } else {
                        degraded
                    }
                    persistLocationIfAllowed(withAudit, event)
                    events.sendLocation(withAudit)
                    onLocationUpdate?.invoke(location.latitude, location.longitude)
                    return
                }
                else -> { /* PASS_THROUGH — fall through to normal flow */ }
            }
        }

        // Compute audit trail hash (Enterprise) — must happen BEFORE persist
        // so the chain is sequential with DB inserts.
        val auditFields = auditTrailManager?.appendToChain(enriched)
        val enrichedWithAudit = if (auditFields != null) {
            enriched.toMutableMap().apply { putAll(auditFields) }
        } else {
            enriched
        }

        // Persist to database (respecting persistMode)
        persistLocationIfAllowed(enrichedWithAudit, event)

        // Dispatch to Dart
        events.sendLocation(enrichedWithAudit)

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
    fun enrichLocation(location: Location, event: String, speed: Double? = null): Map<String, Any?> {
        val battery = BatteryUtils.getBatteryInfo(context)
        val timestamp = isoFormatter.format(Date(location.time))

        // Use provided effective speed, or fall back to platform speed.
        val effectiveSpeed = speed ?: location.speed.toDouble()

        val mock = isLocationMock(location)

        // Build optional heuristic metadata when detection level is 'heuristic'.
        val mockHeuristics: Map<String, Any?>? = if (config.getMockDetectionLevel() >= 2) {
            val extras = location.extras
            val satellites = extras?.getInt("satellites", -1) ?: -1
            val driftNanos = SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos
            val driftMs = driftNanos / 1_000_000.0
            mapOf(
                "satellites" to satellites,
                "elapsedRealtimeDriftMs" to driftMs,
                "platformFlagMock" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) location.isMock else location.isFromMockProvider,
            )
        } else null

        // Classify the location source based on provider and accuracy.
        val locationSource = when {
            location.provider == "gps" -> "gps"
            location.provider == "fused" && location.accuracy <= GPS_ACCURACY_THRESHOLD -> "gps"
            location.provider == "network" || gpsFallbackActive -> "network"
            location.provider == "fused" && location.accuracy <= 200f -> "wifi"
            location.provider == "fused" -> "cell"
            else -> "unknown"
        }

        val result = mutableMapOf<String, Any?>(
            "uuid" to UUID.randomUUID().toString(),
            "timestamp" to timestamp,
            "isMoving" to state.isMoving,
            "odometer" to state.odometer,
            "event" to event,
            "locationSource" to locationSource,
            "reducedAccuracy" to false,  // Android has no reduced-accuracy concept like iOS 14+
            "mock" to mock,
            "mockHeuristics" to mockHeuristics,
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
                    // Fallback to last known location (e.g. emulator with no GPS)
                    val fallback = lastLocation
                    if (fallback != null) {
                        deliver(listOf(fallback), persist, extras, callback)
                    } else {
                        callback(null)
                    }
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
        if (persist) {
            db.insertLocationAsync(enriched)
            onLocationPersisted?.invoke()
        }
        callback(enriched)
    }

    private fun buildLocationRequest(): LocationRequest {
        val priority = accuracyToPriority(config.getDesiredAccuracy())
        val builder = LocationRequest.Builder(priority, config.getLocationUpdateInterval())
            .setMinUpdateDistanceMeters(config.getDistanceFilter().toFloat())
            .setMinUpdateIntervalMillis(config.getFastestLocationUpdateInterval())

        // Apply batched delivery delay if configured (A-M9).
        // This allows the platform to batch location fixes and deliver them
        // together, significantly reducing wakeup frequency and saving battery.
        val deferTime = config.getDeferTime().toLong()
        if (deferTime > 0) {
            builder.setMaxUpdateDelayMillis(deferTime)
        }

        return builder.build()
    }

    /**
     * Builds a [LocationRequest] with automatic GPS-off fallback.
     *
     * If the configured accuracy requires GPS ([Priority.PRIORITY_HIGH_ACCURACY])
     * but the GPS provider is disabled, downgrades to
     * [Priority.PRIORITY_BALANCED_POWER_ACCURACY] so the fused engine delivers
     * Wi-Fi / cell-tower fixes instead of timing out.
     */
    private fun buildLocationRequestWithGpsFallback(): LocationRequest {
        val configuredPriority = accuracyToPriority(config.getDesiredAccuracy())
        val effectivePriority = if (configuredPriority == Priority.PRIORITY_HIGH_ACCURACY &&
            !isGpsProviderEnabled(context)
        ) {
            gpsFallbackActive = true
            Log.d(TAG, "GPS provider disabled — using BALANCED_POWER_ACCURACY (Wi-Fi/cell)")
            Priority.PRIORITY_BALANCED_POWER_ACCURACY
        } else {
            gpsFallbackActive = false
            configuredPriority
        }

        val builder = LocationRequest.Builder(effectivePriority, config.getLocationUpdateInterval())
            .setMinUpdateDistanceMeters(config.getDistanceFilter().toFloat())
            .setMinUpdateIntervalMillis(config.getFastestLocationUpdateInterval())

        val deferTime = config.getDeferTime().toLong()
        if (deferTime > 0) {
            builder.setMaxUpdateDelayMillis(deferTime)
        }

        return builder.build()
    }

    /** Returns true if the configured desired accuracy requires GPS hardware. */
    private fun isHighAccuracyConfigured(): Boolean {
        return config.getDesiredAccuracy() == 0 // 0 = high accuracy (GPS)
    }

    /**
     * Downgrades to Wi-Fi/cell priority while keeping the existing tracking
     * callback. Re-subscribes with [PRIORITY_BALANCED_POWER_ACCURACY].
     */
    private fun activateGpsFallback() {
        if (gpsFallbackActive) return
        gpsFallbackActive = true

        val callback = trackingCallback ?: return
        val fallbackRequest = LocationRequest.Builder(
            Priority.PRIORITY_BALANCED_POWER_ACCURACY,
            config.getLocationUpdateInterval(),
        )
            .setMinUpdateDistanceMeters(config.getDistanceFilter().toFloat())
            .setMinUpdateIntervalMillis(config.getFastestLocationUpdateInterval())
            .build()

        try {
            // Re-subscribe with lower priority (replaces existing request).
            fusedClient.requestLocationUpdates(fallbackRequest, callback, Looper.getMainLooper())
            Log.d(TAG, "GPS fallback active — now using Wi-Fi/cell positioning")
            val providerState = buildProviderState().toMutableMap()
            providerState["gpsFallback"] = true
            events.sendProviderChange(providerState)
        } catch (_: SecurityException) { /* permission lost */ }
    }

    /**
     * Restores the original configured priority after GPS is re-enabled.
     * Re-subscribes with the user's configured accuracy.
     */
    private fun restoreOriginalPriority() {
        if (!gpsFallbackActive) return
        gpsFallbackActive = false

        val callback = trackingCallback ?: return
        val originalRequest = buildLocationRequest()

        try {
            fusedClient.requestLocationUpdates(originalRequest, callback, Looper.getMainLooper())
            Log.d(TAG, "GPS restored — using original priority")
            val providerState = buildProviderState().toMutableMap()
            providerState["gpsFallback"] = false
            events.sendProviderChange(providerState)
        } catch (_: SecurityException) { /* permission lost */ }
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
     * Returns `true` if the app holds ACCESS_BACKGROUND_LOCATION (API 29+).
     * On API < 29, foreground permission implies background access.
     */
    fun hasBackgroundPermission(): Boolean {
        if (!hasPermission()) return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ContextCompat.checkSelfPermission(
                context, Manifest.permission.ACCESS_BACKGROUND_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true // Pre-Q: foreground grant implies background
        }
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

        // Notify HTTP sync manager (if wired) so auto-sync can fire.
        onLocationPersisted?.invoke()

        // Throttle retention pruning — only run every N inserts instead of on
        // each insert. This avoids a COUNT query + potential DELETE on every
        // single location fix (A-H2, A-H3).
        insertCountSincePrune++
        if (insertCountSincePrune >= PRUNE_EVERY_N_INSERTS) {
            insertCountSincePrune = 0
            val maxDays = config.getMaxDaysToPersist()
            if (maxDays > 0) db.pruneOldLocations(maxDays)
            val maxRecords = config.getMaxRecordsToPersist()
            if (maxRecords > 0) db.enforceMaxRecords(maxRecords)
        }
    }

    /**
     * Detects whether a [Location] was produced by a mock/spoofing provider.
     *
     * Detection level is controlled by `mockDetectionLevel` in config:
     * - **0 (disabled)**: Always returns `false`.
     * - **1 (basic)**: Uses `Location.isMock()` (API 31+) or
     *   `Location.isFromMockProvider()` (API 18–30).
     * - **2 (heuristic)**: Basic + satellite count check + elapsed realtime
     *   drift check.
     *
     * **Note:** On rooted devices with Xposed/Magisk modules, platform flags
     * can be stripped. Heuristic checks partially compensate for this.
     */
    @Suppress("DEPRECATION")
    private fun isLocationMock(location: Location): Boolean {
        val level = config.getMockDetectionLevel()
        if (level == 0) return false

        // Level 1+ (basic): Platform API flag
        val platformFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            location.isMock
        } else {
            location.isFromMockProvider
        }
        if (platformFlag) return true
        if (level < 2) return false

        // Level 2 (heuristic): Additional native-side checks

        // 1. Satellite count: real GPS fixes report 4–30 satellites.
        //    Mock locations from Fake GPS apps typically report 0.
        //    Skip this check when GPS hardware is disabled because
        //    Wi-Fi/cell locations legitimately have 0 satellites.
        val gpsEnabled = isGpsProviderEnabled(context)
        val extras = location.extras
        if (gpsEnabled && extras != null) {
            val satellites = extras.getInt("satellites", -1)
            // Only flag if satellites is explicitly 0 (not missing/-1) and
            // accuracy suggests an outdoor fix (< 50m).
            if (satellites == 0 && location.accuracy < 50.0) {
                return true
            }
        }

        // 2. Elapsed realtime drift: Compare the location's elapsedRealtimeNanos
        //    (set by GPS hardware using the monotonic clock) against the current
        //    SystemClock.elapsedRealtimeNanos(). A large discrepancy means the
        //    location was not produced by real hardware at the claimed time.
        val locationElapsedNanos = location.elapsedRealtimeNanos
        val currentElapsedNanos = SystemClock.elapsedRealtimeNanos()
        // Location should be recent — within 10 seconds. Old or future values
        // indicate replay or time manipulation.
        val driftNanos = currentElapsedNanos - locationElapsedNanos
        val driftSeconds = driftNanos / 1_000_000_000.0
        if (driftSeconds < -1.0 || driftSeconds > 10.0) {
            return true
        }

        return false
    }

    // =========================================================================
    // Dead Reckoning (Enterprise) — IMU sensor fusion
    // =========================================================================

    /**
     * Get the current dead reckoning state.
     *
     * Returns null when dead reckoning is not active (GPS available or
     * feature is disabled). When active, returns a map with:
     * - "active" (Boolean) — true if DR is currently estimating position
     * - "elapsed" (Int) — seconds since DR was activated
     * - "estimatedAccuracy" (Double) — estimated position accuracy in meters
     */
    fun getDeadReckoningState(): Map<String, Any?>? {
        return deadReckoningEngine?.getState()
    }

    /**
     * Starts the GPS-loss timer. After [deadReckoningActivationDelay] seconds
     * without a GPS fix, dead reckoning activates automatically.
     */
    private fun startGpsLossTimer() {
        if (!config.getEnableDeadReckoning()) return
        cancelGpsLossTimer()

        val delayMs = config.getDeadReckoningActivationDelay() * 1000L
        Log.d(TAG, "DR: GPS-loss timer started (${delayMs}ms)")
        gpsLossRunnable = Runnable { activateDeadReckoning() }
        drHandler.postDelayed(gpsLossRunnable!!, delayMs)
    }

    /** Resets the GPS-loss timer (called on each GPS fix). */
    private fun resetGpsLossTimer() {
        if (!config.getEnableDeadReckoning()) return
        cancelGpsLossTimer()
        startGpsLossTimer()
    }

    private fun cancelGpsLossTimer() {
        gpsLossRunnable?.let { drHandler.removeCallbacks(it) }
        gpsLossRunnable = null
    }

    /** Activates dead reckoning from the last known GPS position. */
    private fun activateDeadReckoning() {
        val last = lastLocation
        if (last == null) {
            Log.w(TAG, "DR: Cannot activate — no last known location")
            // Restart timer so we try again once a location arrives.
            startGpsLossTimer()
            return
        }
        Log.d(TAG, "DR: GPS lost for ${config.getDeadReckoningActivationDelay()}s — activating (last=${last.latitude},${last.longitude} acc=${last.accuracy})")

        val engine = DeadReckoningEngine(context, config)
        engine.onEstimatedLocation = { drLocation -> onDrLocationEstimated(drLocation) }
        engine.onDeactivated = {
            Log.d(TAG, "Dead reckoning auto-stopped (max duration)")
        }
        engine.activate(
            lat = last.latitude,
            lng = last.longitude,
            altitude = last.altitude,
            heading = last.bearing.toDouble(),
            activity = currentActivityType,
        )
        deadReckoningEngine = engine
    }

    /** Deactivates dead reckoning. */
    private fun deactivateDeadReckoning() {
        deadReckoningEngine?.deactivate()
        deadReckoningEngine = null
    }

    /**
     * Processes a dead-reckoned location estimate.
     * Enriches it into the standard location format and dispatches it.
     */
    private fun onDrLocationEstimated(drLocation: Map<String, Any?>) {
        val lat = drLocation["latitude"] as? Double ?: return
        val lng = drLocation["longitude"] as? Double ?: return
        val altitude = drLocation["altitude"] as? Double ?: 0.0
        val heading = drLocation["heading"] as? Double ?: 0.0
        val accuracy = drLocation["accuracy"] as? Double ?: 50.0
        val speed = drLocation["speed"] as? Double ?: 0.0

        val timestamp = isoFormatter.format(Date())
        val battery = BatteryUtils.getBatteryInfo(context)

        val enriched = mutableMapOf<String, Any?>(
            "uuid" to UUID.randomUUID().toString(),
            "timestamp" to timestamp,
            "isMoving" to state.isMoving,
            "odometer" to state.odometer,
            "event" to "dead_reckoning",
            "mock" to false,
            "isDeadReckoned" to true,
            "coords" to mapOf(
                "latitude" to lat,
                "longitude" to lng,
                "altitude" to altitude,
                "speed" to speed,
                "heading" to heading,
                "accuracy" to accuracy,
                "speedAccuracy" to -1.0,
                "headingAccuracy" to -1.0,
                "altitudeAccuracy" to -1.0,
            ),
            "activity" to mapOf(
                "type" to currentActivityType,
                "confidence" to currentActivityConfidence,
            ),
            "battery" to battery,
        )

        // Persist and dispatch
        persistLocationIfAllowed(enriched, "dead_reckoning")
        events.sendLocation(enriched)
    }
}
