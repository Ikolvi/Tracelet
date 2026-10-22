package com.ikolvi.tracelet.sdk.wrapper

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.location.Location
import android.os.Looper
import com.google.android.gms.location.*
import com.google.android.gms.tasks.CancellationTokenSource
import java.util.concurrent.ConcurrentHashMap

class PlayServicesProvider : TraceletServicesProvider {
    override fun getLocationClient(context: Context) = PlayLocationClient(context)
    override fun getGeofencingClient(context: Context) = PlayGeofencingClient(context)
    override fun getActivityRecognitionClient(context: Context) = PlayActivityRecognitionClient(context)
    override fun getEventExtractor() = PlayEventExtractor()
}

class PlayLocationClient internal constructor(
    private val fusedClient: FusedLocationProviderClient,
) : TraceletLocationClient {
    constructor(context: Context) : this(LocationServices.getFusedLocationProviderClient(context))

    private val callbackMap = ConcurrentHashMap<TraceletLocationCallback, LocationCallback>()

    @SuppressLint("MissingPermission")
    override fun requestLocationUpdates(request: TraceletLocationRequest, callback: TraceletLocationCallback, looper: Looper) {
        val builder = LocationRequest.Builder(request.priority, request.intervalMillis)
            .setMinUpdateDistanceMeters(request.minUpdateDistanceMeters)
            .setMinUpdateIntervalMillis(request.minUpdateIntervalMillis)
        if (request.maxUpdateDelayMillis > 0) builder.setMaxUpdateDelayMillis(request.maxUpdateDelayMillis)

        val playRequest = builder.build()
        // Re-registering an existing callback must replace its subscription, not
        // add a second one (#432). The engine's live re-subscription paths
        // (`updateLocationProviderOptions`, the GPS fallback and its restore, the
        // budget overlay) all pass the same callback again and rely on that. The
        // fused client only replaces the request when it gets the *same*
        // `LocationCallback`, so a fresh wrapper per call left the previous one
        // registered with nothing pointing at it. `removeLocationUpdates` could
        // then reach only the newest wrapper, and the orphan kept delivering
        // fixes after `stop()` until the process died.
        val playCallback = callbackMap.getOrPut(callback) { PlayCallback(callback) }
        fusedClient.requestLocationUpdates(playRequest, playCallback, looper)
    }

    /**
     * Forwards fused-provider results to [callback] for as long as it is the
     * registered wrapper for that callback. A wrapper that was removed but still
     * gets a delivery (removal is asynchronous, and any wrapper leaked before
     * #432) unregisters itself and drops the fix.
     */
    private inner class PlayCallback(private val callback: TraceletLocationCallback) : LocationCallback() {
        private fun isCurrent(): Boolean {
            if (callbackMap[callback] === this) return true
            fusedClient.removeLocationUpdates(this)
            return false
        }

        override fun onLocationResult(result: LocationResult) {
            if (isCurrent()) callback.onLocationResult(result.locations)
        }

        override fun onLocationAvailability(availability: LocationAvailability) {
            if (isCurrent()) callback.onLocationAvailability(availability.isLocationAvailable)
        }
    }

    override fun removeLocationUpdates(callback: TraceletLocationCallback) {
        val playCallback = callbackMap.remove(callback)
        if (playCallback != null) fusedClient.removeLocationUpdates(playCallback)
    }

    @SuppressLint("MissingPermission")
    override fun getCurrentLocation(priority: Int, cancellationToken: TraceletCancellationToken?, onSuccess: (Location?) -> Unit) {
        val cts = CancellationTokenSource()
        cancellationToken?.onCanceled { cts.cancel() }
        fusedClient.getCurrentLocation(priority, cts.token)
            .addOnSuccessListener { onSuccess(it) }
            .addOnFailureListener { onSuccess(null) }
    }

    @SuppressLint("MissingPermission")
    override fun getLastLocation(onSuccess: (Location?) -> Unit, onFailure: (Exception) -> Unit) {
        fusedClient.lastLocation
            .addOnSuccessListener { onSuccess(it) }
            .addOnFailureListener { onFailure(it) }
    }
}

class PlayGeofencingClient(context: Context) : TraceletGeofencingClient {
    private val client: GeofencingClient = LocationServices.getGeofencingClient(context)

    @SuppressLint("MissingPermission")
    override fun addGeofences(request: TraceletGeofencingRequest, pendingIntent: PendingIntent, onSuccess: () -> Unit, onFailure: (Exception) -> Unit) {
        val playGeofences = request.geofences.map {
            Geofence.Builder()
                .setRequestId(it.requestId)
                .setCircularRegion(it.latitude, it.longitude, it.radiusMeters)
                .setExpirationDuration(it.expirationTime)
                .setTransitionTypes(it.transitionTypes)
                .setLoiteringDelay(it.loiteringDelayMs)
                .build()
        }
        val playRequest = GeofencingRequest.Builder().setInitialTrigger(request.initialTrigger).addGeofences(playGeofences).build()
        client.addGeofences(playRequest, pendingIntent).addOnSuccessListener { onSuccess() }.addOnFailureListener { onFailure(it) }
    }

    override fun removeGeofences(pendingIntent: PendingIntent, onSuccess: () -> Unit, onFailure: (Exception) -> Unit) {
        client.removeGeofences(pendingIntent).addOnSuccessListener { onSuccess() }.addOnFailureListener { onFailure(it) }
    }

    override fun removeGeofences(requestIds: List<String>, onSuccess: () -> Unit, onFailure: (Exception) -> Unit) {
        client.removeGeofences(requestIds).addOnSuccessListener { onSuccess() }.addOnFailureListener { onFailure(it) }
    }
}

class PlayActivityRecognitionClient(context: Context) : TraceletActivityRecognitionClient {
    private val client: ActivityRecognitionClient = ActivityRecognition.getClient(context)

    @SuppressLint("MissingPermission")
    override fun requestActivityUpdates(detectionIntervalMillis: Long, callbackIntent: PendingIntent, onSuccess: () -> Unit, onFailure: (Exception) -> Unit) {
        client.requestActivityUpdates(detectionIntervalMillis, callbackIntent).addOnSuccessListener { onSuccess() }.addOnFailureListener { onFailure(it) }
    }

    @SuppressLint("MissingPermission")
    override fun removeActivityUpdates(callbackIntent: PendingIntent, onSuccess: () -> Unit, onFailure: (Exception) -> Unit) {
        client.removeActivityUpdates(callbackIntent).addOnSuccessListener { onSuccess() }.addOnFailureListener { onFailure(it) }
    }

    @SuppressLint("MissingPermission")
    override fun requestActivityTransitionUpdates(request: TraceletActivityTransitionRequest, pendingIntent: PendingIntent, onSuccess: () -> Unit, onFailure: (Exception) -> Unit) {
        val playTransitions = request.transitions.map { ActivityTransition.Builder().setActivityType(it.activityType).setActivityTransition(it.transitionType).build() }
        val playRequest = ActivityTransitionRequest(playTransitions)
        client.requestActivityTransitionUpdates(playRequest, pendingIntent).addOnSuccessListener { onSuccess() }.addOnFailureListener { onFailure(it) }
    }

    @SuppressLint("MissingPermission")
    override fun removeActivityTransitionUpdates(pendingIntent: PendingIntent, onSuccess: () -> Unit, onFailure: (Exception) -> Unit) {
        client.removeActivityTransitionUpdates(pendingIntent).addOnSuccessListener { onSuccess() }.addOnFailureListener { onFailure(it) }
    }
}

class PlayEventExtractor : TraceletEventExtractor {
    override fun extractGeofencingEvent(intent: Intent): TraceletGeofencingEvent? {
        val event = GeofencingEvent.fromIntent(intent) ?: return null
        return TraceletGeofencingEvent(
            hasError = event.hasError(),
            errorCode = event.errorCode,
            geofenceTransition = event.geofenceTransition,
            triggeringGeofences = event.triggeringGeofences?.map { TraceletGeofence(it.requestId, 0.0, 0.0, 0f, 0, 0, 0) },
            triggeringLocation = event.triggeringLocation
        )
    }

    override fun extractActivityRecognitionResult(intent: Intent): TraceletActivityRecognitionResult? {
        if (!ActivityRecognitionResult.hasResult(intent)) return null
        val result = ActivityRecognitionResult.extractResult(intent) ?: return null
        return TraceletActivityRecognitionResult(
            probableActivities = result.probableActivities.map { TraceletDetectedActivity(it.type, it.confidence) },
            mostProbableActivity = TraceletDetectedActivity(result.mostProbableActivity.type, result.mostProbableActivity.confidence)
        )
    }

    override fun extractActivityTransitionResult(intent: Intent): TraceletActivityTransitionResult? {
        if (!ActivityTransitionResult.hasResult(intent)) return null
        val result = ActivityTransitionResult.extractResult(intent) ?: return null
        return TraceletActivityTransitionResult(
            transitionEvents = result.transitionEvents.map { TraceletActivityTransitionEvent(it.activityType, it.transitionType, it.elapsedRealTimeNanos) }
        )
    }
}
