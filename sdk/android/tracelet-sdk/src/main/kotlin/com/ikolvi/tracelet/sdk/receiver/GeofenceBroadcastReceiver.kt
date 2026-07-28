package com.ikolvi.tracelet.sdk.receiver
import com.ikolvi.tracelet.sdk.util.TraceletLog

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.ikolvi.tracelet.sdk.ListenerEventSender
import com.ikolvi.tracelet.sdk.TraceletBootstrap
import com.ikolvi.tracelet.sdk.geofence.GeofenceManager
import com.ikolvi.tracelet.sdk.wrapper.TraceletServices
import com.ikolvi.tracelet.sdk.wrapper.TraceletGeofence
import com.ikolvi.tracelet.sdk.wrapper.TraceletGeofencingEvent

class GeofenceBroadcastReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "GeofenceBroadcastRcvr"
        var geofenceManager: GeofenceManager? = null
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent == null || context == null) return

        val extractor = TraceletServices.getInstance(context).getEventExtractor()
        val event: TraceletGeofencingEvent = extractor.extractGeofencingEvent(intent) ?: return

        if (event.hasError) {
            TraceletLog.error("Geofence error: code=${event.errorCode}")
            return
        }

        val transitionType = event.geofenceTransition
        val triggeringGeofences = event.triggeringGeofences ?: emptyList<TraceletGeofence>()
        
        val location = event.triggeringLocation
        val lat = location?.latitude ?: 0.0
        val lng = location?.longitude ?: 0.0

        TraceletLog.debug("Geofence transition: type=$transitionType, " +
                "geofences=${triggeringGeofences.map { g: TraceletGeofence -> g.requestId }}")

        val manager = geofenceManager ?: run {
            try {
                val sdk = com.ikolvi.tracelet.sdk.TraceletSdk.getInstance(context)
                try {
                    sdk.geofenceManager
                } catch (_: UninitializedPropertyAccessException) {
                    val sender = TraceletBootstrap.eventSenderFactory?.invoke(context)
                        ?: ListenerEventSender()
                    sdk.setEventSender(sender)
                    // initialize() wires geofenceManager on a background thread and
                    // returns immediately; wait for it before reading the lateinit,
                    // otherwise this throws again, the transition is dropped, and a
                    // cold-boot geofence enter/exit (a trip start) is silently lost.
                    sdk.initialize()
                    if (sdk.awaitInit()) sdk.geofenceManager else null
                }
            } catch (e: Exception) {
                TraceletLog.error("Failed to bootstrap SDK: ${e.message}")
                null
            }
        }

        if (manager == null) return

        manager.handleGeofenceEvent(
            transitionType = transitionType,
            triggeringGeofences = triggeringGeofences,
            latitude = lat,
            longitude = lng,
        )
    }
}
