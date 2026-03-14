package com.tracelet.core.geofence

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.util.Log
import androidx.core.content.ContextCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import com.tracelet.core.ConfigManager
import com.tracelet.core.TraceletEventSender
import com.tracelet.core.receiver.GeofenceBroadcastReceiver
import com.tracelet.core.db.TraceletDatabase
import java.util.concurrent.ConcurrentHashMap

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
    private val db: TraceletDatabase,
) {
    companion object {
        private const val TAG = "GeofenceManager"
        const val ACTION_GEOFENCE_EVENT = "com.tracelet.ACTION_GEOFENCE_EVENT"

        /** Google Play Services maximum geofences per app. */
        private const val PLATFORM_MAX_GEOFENCES = 100
    }

    private val geofencingClient: GeofencingClient =
        LocationServices.getGeofencingClient(context)

    private var geofencePendingIntent: PendingIntent? = null

    /** Cached geofences — invalidated on add/remove to avoid DB query per location. */
    private var cachedGeofences: List<Map<String, Any?>>? = null

    /** Returns geofences from cache, refreshing from DB only when invalidated. */
    private fun getCachedGeofences(): List<Map<String, Any?>> {
        return cachedGeofences ?: db.getGeofences().also { cachedGeofences = it }
    }

    /** Invalidate the geofence cache — forces DB re-query on next access. */
    private fun invalidateGeofenceCache() {
        cachedGeofences = null
    }

    /** Registered (active on the platform) geofence identifiers (thread-safe, A-M6). */
    private val activeGeofenceIds: MutableSet<String> = ConcurrentHashMap.newKeySet()

    /** High-accuracy mode: track which geofences the device is currently inside. */
    private val insideGeofenceIds = mutableSetOf<String>()

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
        if (!db.insertGeofence(geofenceMap)) return false
        invalidateGeofenceCache()

        // Polygon geofences are evaluated in Dart — no system registration needed
        val vertices = geofenceMap["vertices"]
        if (vertices is List<*> && vertices.size >= 3) return true

        // If we have a known device location, use proximity-based registration
        val lat = lastLatitude
        val lng = lastLongitude
        if (lat != null && lng != null) {
            updateProximity(lat, lng)
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
        db.deleteGeofence(identifier)
        invalidateGeofenceCache()
        return unregisterGeofence(identifier)
    }

    /** Remove all geofences. */
    fun removeGeofences(): Boolean {
        db.deleteAllGeofences()
        return unregisterAllGeofences()
    }

    /** Get all stored geofences (from database). */
    fun getGeofences(): List<Map<String, Any?>> = db.getGeofences()

    /** Get a single geofence by identifier. */
    fun getGeofence(identifier: String): Map<String, Any?>? = db.getGeofence(identifier)

    /** Check if a geofence exists. */
    fun geofenceExists(identifier: String): Boolean = db.geofenceExists(identifier)

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
        val geofences = db.getGeofences()
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
        triggeringGeofences: List<Geofence>,
        latitude: Double,
        longitude: Double,
    ) {
        // Skip OS-level events when high-accuracy mode handles transitions
        if (config.getGeofenceModeHighAccuracy()) return

        val action = when (transitionType) {
            Geofence.GEOFENCE_TRANSITION_ENTER -> "ENTER"
            Geofence.GEOFENCE_TRANSITION_EXIT -> "EXIT"
            Geofence.GEOFENCE_TRANSITION_DWELL -> "DWELL"
            else -> return
        }

        for (geofence in triggeringGeofences) {
            val identifier = geofence.requestId
            val storedGf = db.getGeofence(identifier)

            val eventData = mapOf(
                "identifier" to identifier,
                "action" to action,
                "location" to mapOf(
                    "coords" to mapOf(
                        "latitude" to latitude,
                        "longitude" to longitude,
                    )
                ),
                "extras" to storedGf?.get("extras"),
            )
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
            val gfMap = db.getGeofence(gf.requestId) ?: mapOf("identifier" to gf.requestId)
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
     * High-accuracy geofence evaluation is now handled by shared Dart code
     * (GeofenceEvaluator in tracelet_platform_interface). This method is kept
     * as a no-op stub for call-site compatibility.
     */
    fun evaluateHighAccuracyProximity(latitude: Double, longitude: Double) {
        // Proximity evaluation moved to shared Dart GeofenceEvaluator.
        // This method is intentionally empty — Dart handles all ENTER/EXIT
        // transitions via GeofenceEvaluator.evaluateProximity() in the
        // onLocation stream pipeline.
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
        val off = toRemove.map { db.getGeofence(it) ?: mapOf<String, Any?>("identifier" to it) }
        if (on.isNotEmpty() || off.isNotEmpty()) {
            events.sendGeofencesChange(mapOf("on" to on, "off" to off))
        }

        Log.d(TAG, "Proximity update: ${activeGeofenceIds.size} active, +${toAdd.size}/-${toRemove.size}")
    }

    /** Clear high-accuracy tracking state. */
    fun clearHighAccuracyState() {
        insideGeofenceIds.clear()
    }

    /** Destroy and clean up. */
    fun destroy() {
        unregisterAllGeofences()
        insideGeofenceIds.clear()
        invalidateGeofenceCache()
    }

    // =========================================================================
    // Private methods
    // =========================================================================

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
        if (notifyOnEntry) transitionTypes = transitionTypes or Geofence.GEOFENCE_TRANSITION_ENTER
        if (notifyOnExit) transitionTypes = transitionTypes or Geofence.GEOFENCE_TRANSITION_EXIT
        if (notifyOnDwell) transitionTypes = transitionTypes or Geofence.GEOFENCE_TRANSITION_DWELL

        val geofence = Geofence.Builder()
            .setRequestId(identifier)
            .setCircularRegion(latitude, longitude, radius)
            .setTransitionTypes(transitionTypes)
            .setExpirationDuration(Geofence.NEVER_EXPIRE)
            .apply {
                if (notifyOnDwell && loiteringDelay > 0) {
                    setLoiteringDelay(loiteringDelay)
                }
            }
            .build()

        val initialTrigger = if (config.getGeofenceInitialTriggerEntry()) {
            GeofencingRequest.INITIAL_TRIGGER_ENTER
        } else {
            0
        }

        val request = GeofencingRequest.Builder()
            .setInitialTrigger(initialTrigger)
            .addGeofence(geofence)
            .build()

        return try {
            geofencingClient.addGeofences(request, getGeofencePendingIntent())
                .addOnSuccessListener {
                    activeGeofenceIds.add(identifier)
                    Log.d(TAG, "Geofence registered: $identifier")
                }
                .addOnFailureListener { e ->
                    Log.e(TAG, "Failed to register geofence $identifier: ${e.message}")
                }
            true
        } catch (e: SecurityException) {
            Log.e(TAG, "Permission denied for geofencing: ${e.message}")
            false
        }
    }

    private fun unregisterGeofence(identifier: String): Boolean {
        geofencingClient.removeGeofences(listOf(identifier))
            .addOnSuccessListener {
                activeGeofenceIds.remove(identifier)
                Log.d(TAG, "Geofence removed: $identifier")
            }
            .addOnFailureListener { e ->
                Log.w(TAG, "Failed to remove geofence $identifier: ${e.message}")
            }
        return true
    }

    private fun unregisterAllGeofences(): Boolean {
        geofencePendingIntent?.let {
            geofencingClient.removeGeofences(it)
                .addOnSuccessListener {
                    activeGeofenceIds.clear()
                    Log.d(TAG, "All geofences removed")
                }
                .addOnFailureListener { e ->
                    Log.w(TAG, "Failed to remove all geofences: ${e.message}")
                }
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
}
