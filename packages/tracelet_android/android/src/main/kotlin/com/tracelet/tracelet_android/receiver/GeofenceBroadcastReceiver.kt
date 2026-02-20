package com.tracelet.tracelet_android.receiver

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.location.GeofenceStatusCodes
import com.google.android.gms.location.GeofencingEvent
import com.tracelet.tracelet_android.geofence.GeofenceManager

/**
 * Receives geofence transition events from the platform.
 *
 * Registered in AndroidManifest.xml and triggered by GeofencingClient
 * when the device enters/exits/dwells in a monitored geofence.
 */
class GeofenceBroadcastReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "GeofenceBroadcastRcvr"

        /**
         * Static reference to GeofenceManager for dispatching events.
         * Set by TraceletAndroidPlugin when the plugin initializes.
         */
        var geofenceManager: GeofenceManager? = null
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent == null || context == null) return

        val geofencingEvent = GeofencingEvent.fromIntent(intent)
        if (geofencingEvent == null) {
            Log.w(TAG, "GeofencingEvent.fromIntent returned null")
            return
        }

        if (geofencingEvent.hasError()) {
            val errorMessage = GeofenceStatusCodes.getStatusCodeString(geofencingEvent.errorCode)
            Log.e(TAG, "Geofence error: $errorMessage (code=${geofencingEvent.errorCode})")
            return
        }

        val transitionType = geofencingEvent.geofenceTransition
        val triggeringGeofences = geofencingEvent.triggeringGeofences ?: return
        val triggeringLocation = geofencingEvent.triggeringLocation

        val latitude = triggeringLocation?.latitude ?: 0.0
        val longitude = triggeringLocation?.longitude ?: 0.0

        Log.d(TAG, "Geofence transition: type=$transitionType, " +
                "geofences=${triggeringGeofences.map { it.requestId }}")

        geofenceManager?.handleGeofenceEvent(
            transitionType = transitionType,
            triggeringGeofences = triggeringGeofences,
            latitude = latitude,
            longitude = longitude,
        )
    }
}
