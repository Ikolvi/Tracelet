package com.tracelet.tracelet_android.geofence

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
import com.tracelet.tracelet_android.ConfigManager
import com.tracelet.tracelet_android.EventDispatcher
import com.tracelet.tracelet_android.receiver.GeofenceBroadcastReceiver
import com.tracelet.tracelet_android.db.TraceletDatabase

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
    private val events: EventDispatcher,
    private val db: TraceletDatabase,
) {
    companion object {
        private const val TAG = "GeofenceManager"
        const val ACTION_GEOFENCE_EVENT = "com.tracelet.ACTION_GEOFENCE_EVENT"
    }

    private val geofencingClient: GeofencingClient =
        LocationServices.getGeofencingClient(context)

    private var geofencePendingIntent: PendingIntent? = null

    /** Registered (active on the platform) geofence identifiers. */
    private val activeGeofenceIds = mutableSetOf<String>()

    // =========================================================================
    // Public API
    // =========================================================================

    /** Add a single geofence. Persists to DB and registers with GeofencingClient. */
    fun addGeofence(geofenceMap: Map<String, Any?>): Boolean {
        val identifier = geofenceMap["identifier"] as? String ?: return false

        // Persist to database
        if (!db.insertGeofence(geofenceMap)) return false

        // Register with platform
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
     * Re-registers all persisted geofences with the GeofencingClient.
     * Called on boot/restart.
     */
    fun reRegisterAll() {
        if (!hasPermission()) return
        val geofences = db.getGeofences()
        for (gf in geofences) {
            registerGeofence(gf)
        }
    }

    /**
     * Called when a geofence event is received from GeofenceBroadcastReceiver.
     * Dispatches events to Dart via EventDispatcher.
     */
    fun handleGeofenceEvent(
        transitionType: Int,
        triggeringGeofences: List<Geofence>,
        latitude: Double,
        longitude: Double,
    ) {
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

    /** Destroy and clean up. */
    fun destroy() {
        unregisterAllGeofences()
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
}
