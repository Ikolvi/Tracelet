package com.ikolvi.tracelet.sdk.geofence
import com.ikolvi.tracelet.sdk.util.TraceletLog

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.TraceletEventSender
import com.ikolvi.tracelet.sdk.util.BatteryUtils
import uniffi.tracelet_core.GeofenceEvaluator
import uniffi.tracelet_core.CoreGeofence
import uniffi.tracelet_core.Coordinate
import com.ikolvi.tracelet.sdk.receiver.GeofenceBroadcastReceiver
import com.ikolvi.tracelet.sdk.wrapper.TraceletGeofence
import com.ikolvi.tracelet.sdk.wrapper.TraceletGeofencingClient
import com.ikolvi.tracelet.sdk.wrapper.TraceletGeofencingRequest
import com.ikolvi.tracelet.sdk.wrapper.TraceletServices
import android.os.Looper
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Geofencing engine using Google Play Services GeofencingClient.
 *
 * Features:
 * - Add/remove individual and batch geofences
 * - Persist geofence definitions in SQLite
 * - Proximity-based monitoring: registers only geofences within proximity radius
 * - Knock-out mode: auto-remove after first trigger
 * - Re-registers geofences on boot/restart
 */
class GeofenceManager(
    private val context: Context,
    private val config: ConfigManager,
    private val events: TraceletEventSender,
    private val rustDatabase: uniffi.tracelet_core.DatabaseManager? = null,
    private val geofencingClient: TraceletGeofencingClient = TraceletServices.getInstance(context).getGeofencingClient(context),
    /**
     * Provides the most recent GPS fix so geofence transition payloads can be
     * enriched with real coordinate telemetry (accuracy/speed/heading/altitude)
     * instead of hardcoded zeros (#231). Wired from [TraceletSdk] to the active
     * [com.ikolvi.tracelet.sdk.location.LocationEngine].
     */
    private val lastLocationProvider: (() -> Location?)? = null,
) {
    var onGeofenceEvent: ((Map<String, Any?>) -> Unit)? = null
    companion object {
        private const val TAG = "GeofenceManager"
        const val ACTION_GEOFENCE_EVENT = "com.tracelet.ACTION_GEOFENCE_EVENT"

        /** Google Play Services maximum geofences per app. */
        private const val PLATFORM_MAX_GEOFENCES = 100

        /** Timeout for Play Services geofence registration (ms). */
        private const val REGISTRATION_TIMEOUT_MS = 5000L
    }

    private var geofencePendingIntent: PendingIntent? = null

    /**
     * In-memory cache of geofences to prevent executing database queries per GPS location update.
     * Maps are preserved to maintain compatibility with system location callbacks and Dart channel handlers.
     */
    private var cachedGeofences: List<Map<String, Any?>>? = null

    /**
     * Retrieves geofences from the local cache. If the cache is empty or has been invalidated,
     * it performs a fresh query against the shared Rust database and maps the [CoreGeofence]
     * models to generic map structures.
     */
    private fun getCachedGeofences(): List<Map<String, Any?>> {
        val cached = cachedGeofences
        if (cached != null) {
            return cached
        }
        val loaded = rustDatabase?.getGeofences() ?: emptyList()
        val mapped = loaded.map { mapFromCoreGeofence(it) }
        cachedGeofences = mapped
        return mapped
    }

    /**
     * Invalidates the in-memory geofence cache. Forces a query against the Rust DB on the next access.
     */
    private fun invalidateGeofenceCache() {
        cachedGeofences = null
    }

    /**
     * Helper method to transform a Rust [CoreGeofence] record into a generic map structure.
     * Translates coordinates and poly-vertex lists into the standard JSON-compatible formats.
     */
    private fun mapFromCoreGeofence(gf: CoreGeofence): Map<String, Any?> {
        val verticesList = gf.vertices.map { listOf(it.lat, it.lng) }
        val result = mutableMapOf<String, Any?>(
            "identifier" to gf.identifier,
            "latitude" to gf.latitude,
            "longitude" to gf.longitude,
            "radius" to gf.radius,
            "vertices" to verticesList
        )
        
        gf.extras?.let { extrasStr ->
            try {
                val jsonObject = org.json.JSONObject(extrasStr)
                val map = mutableMapOf<String, Any?>()
                val keys = jsonObject.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    map[key] = jsonObject.get(key)
                }
                result["extras"] = map
            } catch (e: Exception) {
                TraceletLog.warning("Failed to parse geofence extras from DB: ${e.message}")
            }
        }
        return result
    }

    /** Registered (active on the platform) geofence identifiers (thread-safe, A-M6). */
    private val activeGeofenceIds: MutableSet<String> = ConcurrentHashMap.newKeySet()

    /** High-accuracy mode: track which geofences the device is currently inside. */
    private val insideGeofenceIds = mutableSetOf<String>()

    /** High-accuracy geofence evaluator (polygon + circular). */
    private val geofenceEvaluator = GeofenceEvaluator()

    /** Last known device location for proximity filtering. */
    private var lastLatitude: Double? = null
    private var lastLongitude: Double? = null

    // =========================================================================
    // Public API
    // =========================================================================

    /** Add a single geofence. Persists to DB and registers if within proximity. */
    fun addGeofence(geofenceMap: Map<String, Any?>): Boolean {
        val identifier = geofenceMap["identifier"] as? String ?: return false

        // Persist to database
        val lat = (geofenceMap["latitude"] as? Number)?.toDouble() ?: 0.0
        val lng = (geofenceMap["longitude"] as? Number)?.toDouble() ?: 0.0
        val radius = (geofenceMap["radius"] as? Number)?.toDouble() ?: 0.0
        
        val verticesRaw = geofenceMap["vertices"] as? List<*>
        var coreVertices: List<Coordinate>? = null
        if (verticesRaw != null) {
            val vList = mutableListOf<Coordinate>()
            for (v in verticesRaw) {
                if (v is List<*> && v.size >= 2) {
                    val vLat = (v[0] as? Number)?.toDouble()
                    val vLng = (v[1] as? Number)?.toDouble()
                    if (vLat != null && vLng != null) {
                        vList.add(Coordinate(vLat, vLng))
                    }
                }
            }
            coreVertices = vList.takeIf { it.isNotEmpty() }
        }

        val extrasRaw = geofenceMap["extras"] as? Map<*, *>
        var extrasStr: String? = null
        if (extrasRaw != null) {
            try {
                extrasStr = org.json.JSONObject(extrasRaw).toString()
            } catch (e: Exception) {
                TraceletLog.warning("Failed to stringify geofence extras: ${e.message}")
            }
        }
        
        try {
            rustDatabase?.insertGeofence(identifier, lat, lng, radius, coreVertices, extrasStr)
        } catch (e: Exception) {
            TraceletLog.error("Failed to persist geofence to Rust DB", e)
        }
        
        invalidateGeofenceCache()

        // Polygon geofences are evaluated in Dart — no system registration needed
        val vertices = geofenceMap["vertices"]
        if (vertices is List<*> && vertices.size >= 3) return true

        // If we have a known device location, use proximity-based registration
        val deviceLat = lastLatitude
        val deviceLng = lastLongitude
        if (deviceLat != null && deviceLng != null) {
            updateProximity(deviceLat, deviceLng)
            return true
        }

        // No known location — register directly (will be proximity-filtered later)
        return registerGeofence(geofenceMap)
    }

    /** Add multiple geofences. Returns true if all succeeded. */
    fun addGeofences(geofences: List<Map<String, Any?>>): Boolean {
        if (!hasPermission()) return false

        var allSuccess = true
        for (gf in geofences) {
            if (!addGeofence(gf)) allSuccess = false
        }
        return allSuccess
    }

    /** Remove a single geofence by identifier. */
    fun removeGeofence(identifier: String): Boolean {
        try {
            rustDatabase?.deleteGeofence(identifier)
        } catch (e: Exception) {
            TraceletLog.error("Failed to delete geofence from Rust DB", e)
        }
        invalidateGeofenceCache()
        return unregisterGeofence(identifier)
    }

    /** Remove all geofences. */
    fun removeGeofences(): Boolean {
        try {
            rustDatabase?.clearGeofences()
        } catch (e: Exception) {
            TraceletLog.error("Failed to clear geofences from Rust DB", e)
        }
        invalidateGeofenceCache()
        return unregisterAllGeofences()
    }

    fun getGeofences(): List<Map<String, Any?>> = getCachedGeofences()

    /** Get a single geofence by identifier. */
    fun getGeofence(identifier: String): Map<String, Any?>? = getCachedGeofences().find { it["identifier"] == identifier }

    /** Check if a geofence exists. */
    fun geofenceExists(identifier: String): Boolean = getGeofence(identifier) != null

    /**
     * Re-registers persisted geofences with the GeofencingClient.
     * Called on boot/restart. Uses proximity filtering when a device location
     * is available; otherwise registers all (up to platform max).
     */
    fun reRegisterAll() {
        if (!hasPermission()) return
        val lat = lastLatitude
        val lng = lastLongitude
        if (lat != null && lng != null) {
            updateProximity(lat, lng)
            return
        }
        // No known location — register all circular geofences (capped at platform max)
        val geofences = getCachedGeofences()
        var count = 0
        val maxMonitored = resolveMaxMonitored()
        for (gf in geofences) {
            if (count >= maxMonitored) break
            val vertices = gf["vertices"]
            if (vertices is List<*> && vertices.size >= 3) continue
            val radius = (gf["radius"] as? Number)?.toFloat() ?: 0f
            if (radius <= 0f) continue
            registerGeofence(gf)
            count++
        }
    }

    /**
     * Called when a geofence event is received from GeofenceBroadcastReceiver.
     * Dispatches events via TraceletEventSender.
     *
     * When geofenceModeHighAccuracy is active, OS-level events are suppressed
     * to avoid duplicates — transitions are handled by [evaluateHighAccuracyProximity].
     */
    fun handleGeofenceEvent(
        transitionType: Int,
        triggeringGeofences: List<TraceletGeofence>,
        latitude: Double,
        longitude: Double,
    ) {
        // Skip OS-level events when high-accuracy mode handles transitions
        if (config.getGeofenceModeHighAccuracy()) return

        val action = when (transitionType) {
            1 -> "ENTER" // Geofence.GEOFENCE_TRANSITION_ENTER
            2 -> "EXIT"  // Geofence.GEOFENCE_TRANSITION_EXIT
            4 -> "DWELL" // Geofence.GEOFENCE_TRANSITION_DWELL
            else -> return
        }

        for (geofence in triggeringGeofences) {
            val identifier = geofence.requestId
            val storedGf = getGeofence(identifier)

            val eventData = mapOf(
                "uuid" to java.util.UUID.randomUUID().toString(),
                "event" to "geofence",
                "timestamp" to java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US).apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }.format(java.util.Date()),
                "coords" to buildCoords(latitude, longitude),
                "battery" to currentBattery(),
                "geofence" to mapOf(
                    "identifier" to identifier,
                    "action" to action,
                    "extras" to storedGf?.get("extras")
                )
            )

            onGeofenceEvent?.invoke(eventData)
            events.sendGeofence(eventData)

            // Knock-out mode: remove geofence after EXIT
            if (action == "EXIT" && config.getGeofenceModeKnockOut()) {
                removeGeofence(identifier)
            }
        }

        // Fire geofencesChange event
        val on = mutableListOf<Map<String, Any?>>()
        val off = mutableListOf<Map<String, Any?>>()
        for (gf in triggeringGeofences) {
            val gfMap = getGeofence(gf.requestId) ?: mapOf("identifier" to gf.requestId)
            when (action) {
                "ENTER" -> on.add(gfMap)
                "EXIT" -> off.add(gfMap)
            }
        }
        if (on.isNotEmpty() || off.isNotEmpty()) {
            events.sendGeofencesChange(mapOf("on" to on, "off" to off))
        }
    }

    /**
     * High-accuracy geofence evaluation.
     *
     * Uses [GeofenceEvaluator] to perform software-based ENTER/EXIT detection
     * for both circular and polygon geofences. Dispatches transition events
     * and geofencesChange events via [TraceletEventSender].
     *
     * Called on each location update when `geofenceModeHighAccuracy` is enabled.
     */
    fun evaluateHighAccuracyProximity(latitude: Double, longitude: Double) {
        val allGeofences = getCachedGeofences()
        if (allGeofences.isEmpty()) return

        val coreGeofences = allGeofences.map { mapToCoreGeofence(it) }
        val transitions = geofenceEvaluator.evaluateProximity(
            latitude = latitude,
            longitude = longitude,
            geofences = coreGeofences,
        )
        if (transitions.isEmpty()) return

        val on = mutableListOf<Map<String, Any?>>()
        val off = mutableListOf<Map<String, Any?>>()
        val geofenceMapById = allGeofences.associateBy { it["identifier"] as? String }

        for (t in transitions) {
            val gfMap = geofenceMapById[t.identifier]
            val eventData = mapOf(
                "uuid" to java.util.UUID.randomUUID().toString(),
                "event" to "geofence",
                "timestamp" to java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US).apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }.format(java.util.Date()),
                "coords" to buildCoords(latitude, longitude),
                "battery" to currentBattery(),
                "geofence" to mapOf(
                    "identifier" to t.identifier,
                    "action" to t.action,
                    "extras" to gfMap?.get("extras")
                )
            )
            
            onGeofenceEvent?.invoke(eventData)
            events.sendGeofence(eventData)

            when (t.action) {
                "ENTER" -> gfMap?.let { on.add(it) }
                "EXIT" -> {
                    gfMap?.let { off.add(it) }
                    if (config.getGeofenceModeKnockOut()) {
                        removeGeofence(t.identifier)
                        geofenceEvaluator.removeGeofence(t.identifier)
                    }
                }
            }
        }

        if (on.isNotEmpty() || off.isNotEmpty()) {
            events.sendGeofencesChange(mapOf("on" to on, "off" to off))
        }
    }

    /**
     * Update proximity-based geofence monitoring.
     *
     * Evaluates which stored geofences are within [ConfigManager.getGeofenceProximityRadius]
     * of the given device location, sorts them by distance, and registers only the closest
     * N geofences with the OS (where N = min(maxMonitoredGeofences, PLATFORM_MAX_GEOFENCES)).
     *
     * Geofences that move out of proximity are unregistered. Geofences that move into
     * proximity are registered. A `geofencesChange` event is fired for any changes.
     *
     * This enables monitoring thousands of geofences despite the Android limit of 100.
     */
    fun updateProximity(latitude: Double, longitude: Double) {
        lastLatitude = latitude
        lastLongitude = longitude

        if (!hasPermission()) return

        val proximityRadius = config.getGeofenceProximityRadius()
        val maxMonitored = resolveMaxMonitored()

        // Get all stored geofences from cache, filter to circular ones with valid radius
        val candidates = getCachedGeofences()
            .filter { gf ->
                val vertices = gf["vertices"]
                !(vertices is List<*> && vertices.size >= 3)
            }
            .filter { gf ->
                val radius = (gf["radius"] as? Number)?.toFloat() ?: 0f
                radius > 0f
            }
            .map { gf ->
                val lat = (gf["latitude"] as? Number)?.toDouble() ?: 0.0
                val lng = (gf["longitude"] as? Number)?.toDouble() ?: 0.0
                val distance = haversine(latitude, longitude, lat, lng)
                Pair(gf, distance)
            }
            .filter { (_, distance) -> distance <= proximityRadius }
            .sortedBy { (_, distance) -> distance }
            .take(maxMonitored)

        val newActiveIds = candidates
            .mapNotNull { (gf, _) -> gf["identifier"] as? String }
            .toSet()

        val toRemove = activeGeofenceIds - newActiveIds
        val toAdd = newActiveIds - activeGeofenceIds

        if (toRemove.isEmpty() && toAdd.isEmpty()) return

        // Unregister geofences that left the proximity zone
        for (id in toRemove) {
            unregisterGeofence(id)
        }

        // Register geofences that entered the proximity zone
        val candidateMap = candidates.associate { (gf, _) ->
            (gf["identifier"] as? String ?: "") to gf
        }
        for (id in toAdd) {
            candidateMap[id]?.let { registerGeofence(it) }
        }

        // Fire geofencesChange event (on = activated, off = deactivated)
        val on = toAdd.mapNotNull { candidateMap[it] }
        val off = toRemove.map { getGeofence(it) ?: mapOf<String, Any?>("identifier" to it) }
        if (on.isNotEmpty() || off.isNotEmpty()) {
            events.sendGeofencesChange(mapOf("on" to on, "off" to off))
        }

        TraceletLog.debug("Proximity update: ${activeGeofenceIds.size} active, +${toAdd.size}/-${toRemove.size}")
    }

    /** Clear high-accuracy tracking state. */
    fun clearHighAccuracyState() {
        insideGeofenceIds.clear()
        geofenceEvaluator.clear()
    }

    /** Destroy and clean up. */
    fun destroy() {
        unregisterAllGeofences()
        insideGeofenceIds.clear()
        geofenceEvaluator.clear()
        invalidateGeofenceCache()
    }

    // =========================================================================
    // Private methods
    // =========================================================================

    /**
     * Builds the `coords` payload for a geofence transition event.
     *
     * The geofence boundary latitude/longitude come from the triggering event,
     * but the remaining telemetry (accuracy, speed, heading, altitude and their
     * per-field accuracies) is sourced from the most recent GPS fix when
     * available. Previously these were hardcoded to `0.0`, leaving backends
     * blind to speed/heading/accuracy at the crossing (#231).
     */
    private fun buildCoords(latitude: Double, longitude: Double): Map<String, Any?> {
        val last = lastLocationProvider?.invoke()
            ?: return mapOf(
                "latitude" to latitude,
                "longitude" to longitude,
                "accuracy" to 0.0,
                "speed" to 0.0,
                "heading" to 0.0,
                "altitude" to 0.0,
            )

        return buildMap {
            put("latitude", latitude)
            put("longitude", longitude)
            put("accuracy", last.accuracy.toDouble())
            put("speed", if (last.hasSpeed()) last.speed.toDouble() else 0.0)
            put("heading", if (last.hasBearing()) last.bearing.toDouble() else 0.0)
            put("altitude", if (last.hasAltitude()) last.altitude else 0.0)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                put("speedAccuracy", if (last.hasSpeedAccuracy()) last.speedAccuracyMetersPerSecond.toDouble() else -1.0)
                put("headingAccuracy", if (last.hasBearingAccuracy()) last.bearingAccuracyDegrees.toDouble() else -1.0)
                put("altitudeAccuracy", if (last.hasVerticalAccuracy()) last.verticalAccuracyMeters.toDouble() else -1.0)
            } else {
                put("speedAccuracy", -1.0)
                put("headingAccuracy", -1.0)
                put("altitudeAccuracy", -1.0)
            }
        }
    }

    /** Current battery snapshot for geofence transition payloads (#231). */
    private fun currentBattery(): Map<String, Any?> = BatteryUtils.getBatteryInfo(context)

    private fun registerGeofence(geofenceMap: Map<String, Any?>): Boolean {
        if (!hasPermission()) return false

        val identifier = geofenceMap["identifier"] as? String ?: return false
        val latitude = (geofenceMap["latitude"] as? Number)?.toDouble() ?: return false
        val longitude = (geofenceMap["longitude"] as? Number)?.toDouble() ?: return false
        val radius = (geofenceMap["radius"] as? Number)?.toFloat() ?: 200f

        // Guard against invalid radius (e.g. polygon geofences with radius=0)
        if (radius <= 0f) return false
        val notifyOnEntry = geofenceMap["notifyOnEntry"] != false
        val notifyOnExit = geofenceMap["notifyOnExit"] != false
        val notifyOnDwell = geofenceMap["notifyOnDwell"] == true
        val loiteringDelay = (geofenceMap["loiteringDelay"] as? Number)?.toInt() ?: 0

        var transitionTypes = 0
        if (notifyOnEntry) transitionTypes = transitionTypes or 1 // ENTER
        if (notifyOnExit) transitionTypes = transitionTypes or 2  // EXIT
        if (notifyOnDwell) transitionTypes = transitionTypes or 4 // DWELL

        val initialTrigger = if (config.getGeofenceInitialTriggerEntry()) 1 else 0

        val request = TraceletGeofencingRequest(
            geofences = listOf(
                TraceletGeofence(
                    requestId = identifier,
                    latitude = latitude,
                    longitude = longitude,
                    radiusMeters = radius,
                    expirationTime = -1L, // Geofence.NEVER_EXPIRE
                    transitionTypes = transitionTypes,
                    loiteringDelayMs = loiteringDelay
                )
            ),
            initialTrigger = initialTrigger
        )

        return try {
            val latch = CountDownLatch(1)
            var success = false
            // The Flutter host invokes addGeofence()/registerGeofence() on the
            // Android main thread. GeofencingClient.addGeofences() is asynchronous
            // and also delivers its success/failure callback on the main looper,
            // so we must NOT block the main thread waiting for it. Off the main
            // thread we await the callback and return its real result; on the main
            // thread we return true once the request has been scheduled without
            // throwing synchronously — the geofence is already persisted and
            // registration is in flight. Returning the initial `success` on the
            // main thread reported a stale false for a geofence that was actually
            // created and shows up in getGeofences() (#265).
            val isMainThread = Looper.myLooper() == Looper.getMainLooper()
            geofencingClient.addGeofences(
                request = request,
                pendingIntent = getGeofencePendingIntent(),
                onSuccess = {
                    activeGeofenceIds.add(identifier)
                    success = true
                    latch.countDown()
                    TraceletLog.debug("Geofence registered: $identifier")
                },
                onFailure = { e ->
                    latch.countDown()
                    TraceletLog.error("Failed to register geofence $identifier: ${e.message}")
                }
            )
            if (!isMainThread) {
                latch.await(REGISTRATION_TIMEOUT_MS, TimeUnit.MILLISECONDS)
            }
            isMainThread || success
        } catch (e: SecurityException) {
            TraceletLog.error("Permission denied for geofencing: ${e.message}")
            false
        }
    }

    private fun unregisterGeofence(identifier: String): Boolean {
        val latch = CountDownLatch(1)
        geofencingClient.removeGeofences(
            requestIds = listOf(identifier),
            onSuccess = {
                activeGeofenceIds.remove(identifier)
                latch.countDown()
                TraceletLog.debug("Geofence removed: $identifier")
            },
            onFailure = { e ->
                latch.countDown()
                TraceletLog.warning("Failed to remove geofence $identifier: ${e.message}")
            }
        )
        if (Looper.myLooper() != Looper.getMainLooper()) {
            latch.await(REGISTRATION_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        }
        return true
    }

    private fun unregisterAllGeofences(): Boolean {
        geofencePendingIntent?.let {
            geofencingClient.removeGeofences(
                pendingIntent = it,
                onSuccess = {
                    activeGeofenceIds.clear()
                    TraceletLog.debug("All geofences removed")
                },
                onFailure = { e ->
                    TraceletLog.warning("Failed to remove all geofences: ${e.message}")
                }
            )
        }
        return true
    }

    private fun getGeofencePendingIntent(): PendingIntent {
        if (geofencePendingIntent != null) return geofencePendingIntent!!

        val intent = Intent(context, GeofenceBroadcastReceiver::class.java).apply {
            action = ACTION_GEOFENCE_EVENT
        }
        geofencePendingIntent = PendingIntent.getBroadcast(
            context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )
        return geofencePendingIntent!!
    }

    private fun hasPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
    }

    /**
     * Resolve the effective maximum number of simultaneously monitored geofences.
     * Uses [ConfigManager.getMaxMonitoredGeofences] if set (> 0), otherwise
     * falls back to the platform maximum (100 for Android).
     */
    private fun resolveMaxMonitored(): Int {
        val configured = config.getMaxMonitoredGeofences()
        return if (configured > 0) minOf(configured, PLATFORM_MAX_GEOFENCES)
        else PLATFORM_MAX_GEOFENCES
    }

    /**
     * Haversine formula — distance in meters between two lat/lng points.
     */
    private fun haversine(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val r = 6_371_000.0 // Earth radius in meters
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
                Math.sin(dLon / 2) * Math.sin(dLon / 2)
        val c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        return r * c
    }

    private fun mapToCoreGeofence(gf: Map<String, Any?>): CoreGeofence {
        val identifier = gf["identifier"] as? String ?: ""
        val latitude = (gf["latitude"] as? Number)?.toDouble() ?: 0.0
        val longitude = (gf["longitude"] as? Number)?.toDouble() ?: 0.0
        val radius = (gf["radius"] as? Number)?.toDouble() ?: 0.0
        val verticesRaw = gf["vertices"]
        val vertices = mutableListOf<Coordinate>()
        if (verticesRaw is List<*>) {
            for (v in verticesRaw) {
                if (v is List<*> && v.size >= 2) {
                    val lat = (v[0] as? Number)?.toDouble()
                    val lng = (v[1] as? Number)?.toDouble()
                    if (lat != null && lng != null) {
                        vertices.add(Coordinate(lat, lng))
                    }
                }
            }
        }
        val extrasRaw = gf["extras"] as? Map<*, *>
        var extrasStr: String? = null
        if (extrasRaw != null) {
            try {
                extrasStr = org.json.JSONObject(extrasRaw).toString()
            } catch (e: Exception) {
                TraceletLog.warning("Failed to stringify geofence extras: ${e.message}")
            }
        }
        return CoreGeofence(identifier, latitude, longitude, radius, vertices, extrasStr)
    }
}
