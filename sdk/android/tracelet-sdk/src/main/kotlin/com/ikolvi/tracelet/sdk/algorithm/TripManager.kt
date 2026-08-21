package com.ikolvi.tracelet.sdk.algorithm

import uniffi.tracelet_core.TripManager as RustTripManager

/**
 * Tracks trips based on motion state transitions, delegating core logic to Rust.
 *
 * A "trip" starts when the device transitions to moving and ends when it
 * transitions to stationary. Collects start/stop locations, waypoints,
 * total distance (Haversine), and duration.
 */
class TripManager {
    /** Callback invoked when a trip ends with the full trip data map. */
    var onTripEnd: ((Map<String, Any?>) -> Unit)? = null

    /**
     * Callback invoked when a trip *starts*, with its freshly minted id (#402).
     *
     * Before #402 a trip only became observable once it was over, so anything
     * wanting to tag records with the trip they belong to had no moment to act
     * on and had to re-derive the boundary from raw motion changes.
     */
    var onTripStart: ((Map<String, Any?>) -> Unit)? = null

    private val rustTripManager = RustTripManager()

    /** Whether a trip is currently active. */
    val isTripActive: Boolean
        get() = rustTripManager.isTripActive()

    /** The active trip's id, or null between trips (#402). */
    val currentTripId: String?
        get() = rustTripManager.currentTripId()

    /**
     * Called on every motion state change.
     *
     * @param isMoving whether the device is now moving
     * @param latitude current latitude (if available)
     * @param longitude current longitude (if available)
     * @param timestamp current timestamp string or null
     */
    fun onMotionStateChanged(
        isMoving: Boolean,
        latitude: Double? = null,
        longitude: Double? = null,
        timestamp: Any? = null,
    ) {
        val nowMs = System.currentTimeMillis()
        val timestampMs = (timestamp as? Number)?.toLong() ?: nowMs

        val transition = rustTripManager.onMotionStateChanged(
            isMoving,
            latitude,
            longitude,
            timestampMs,
            nowMs
        )

        if (transition is uniffi.tracelet_core.TripTransition.Started) {
            val start = transition.start
            val startMap = mutableMapOf<String, Any?>()
            start.startLocation?.let {
                startMap["latitude"] = it.latitude
                startMap["longitude"] = it.longitude
            }
            onTripStart?.invoke(
                mapOf(
                    "tripId" to start.tripId,
                    "startedAt" to start.startedAtMs,
                    "startLocation" to startMap,
                ),
            )
            return
        }

        val tripData = (transition as? uniffi.tracelet_core.TripTransition.Ended)?.data

        if (tripData != null) {
            val startMap = mutableMapOf<String, Any?>()
            tripData.startLocation?.let {
                startMap["latitude"] = it.latitude
                startMap["longitude"] = it.longitude
            }

            val stopMap = mutableMapOf<String, Any?>()
            tripData.stopLocation?.let {
                stopMap["latitude"] = it.latitude
                stopMap["longitude"] = it.longitude
            }

            val waypointsMapList = tripData.waypoints.map { wp ->
                mapOf(
                    "latitude" to wp.latitude,
                    "longitude" to wp.longitude,
                    "timestamp" to wp.timestampMs,
                )
            }

            val outMap = mapOf<String, Any?>(
                "isMoving" to false,
                // #402: the join key shared with every location and driving
                // event recorded during this trip.
                "tripId" to tripData.tripId,
                "startedAt" to tripData.startedAtMs,
                "endedAt" to tripData.endedAtMs,
                "distance" to tripData.distanceMeters,
                "duration" to tripData.durationSeconds,
                "startLocation" to startMap,
                "stopLocation" to stopMap,
                "waypoints" to waypointsMapList,
            )

            onTripEnd?.invoke(outMap)
        }
    }

    /**
     * Called on every accepted tracking location to record waypoints.
     *
     * @param latitude location latitude
     * @param longitude location longitude
     * @param timestamp location timestamp
     */
    fun onLocationReceived(
        latitude: Double,
        longitude: Double,
        timestamp: Any? = null,
    ) {
        val nowMs = System.currentTimeMillis()
        val timestampMs = (timestamp as? Number)?.toLong() ?: nowMs
        rustTripManager.onLocationReceived(latitude, longitude, timestampMs)
    }

    /** Reset the trip manager state. */
    fun reset() {
        rustTripManager.reset()
    }
}
