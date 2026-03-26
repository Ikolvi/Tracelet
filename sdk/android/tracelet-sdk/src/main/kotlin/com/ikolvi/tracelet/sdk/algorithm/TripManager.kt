package com.ikolvi.tracelet.sdk.algorithm

/**
 * Tracks trips based on motion state transitions.
 *
 * A "trip" starts when the device transitions to moving and ends when it
 * transitions to stationary. Collects start/stop locations, waypoints,
 * total distance (Haversine), and duration.
 */
class TripManager {
    companion object {
        /** Maximum number of waypoints to retain during a trip. */
        private const val MAX_WAYPOINTS = 5000
    }

    /** Callback invoked when a trip ends with the full trip data map. */
    var onTripEnd: ((Map<String, Any?>) -> Unit)? = null

    /** Whether a trip is currently active. */
    var isTripActive: Boolean = false
        private set

    private var startLat: Double? = null
    private var startLng: Double? = null
    private var startTimeMs: Long = 0
    private var totalDistance: Double = 0.0
    private var lastWaypointLat: Double? = null
    private var lastWaypointLng: Double? = null
    private val waypoints = ArrayDeque<Map<String, Any?>>()

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
        if (isMoving && !isTripActive) {
            startTrip(latitude, longitude, timestamp)
        } else if (!isMoving && isTripActive) {
            endTrip(latitude, longitude, timestamp)
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
        if (!isTripActive) return

        // Accumulate distance.
        val prevLat = lastWaypointLat
        val prevLng = lastWaypointLng
        if (prevLat != null && prevLng != null) {
            totalDistance += GeoUtils.haversine(prevLat, prevLng, latitude, longitude)
        }
        lastWaypointLat = latitude
        lastWaypointLng = longitude

        // Record waypoint. Evict oldest when cap exceeded.
        if (waypoints.size >= MAX_WAYPOINTS) {
            waypoints.removeFirst()
        }
        waypoints.addLast(mapOf(
            "latitude" to latitude,
            "longitude" to longitude,
            "timestamp" to timestamp,
        ))
    }

    /** Reset the trip manager state. */
    fun reset() {
        isTripActive = false
        startLat = null
        startLng = null
        lastWaypointLat = null
        lastWaypointLng = null
        startTimeMs = 0
        totalDistance = 0.0
        waypoints.clear()
    }

    // =========================================================================
    // Private
    // =========================================================================

    private fun startTrip(lat: Double?, lng: Double?, timestamp: Any?) {
        isTripActive = true
        startLat = lat
        startLng = lng
        lastWaypointLat = lat
        lastWaypointLng = lng
        startTimeMs = System.currentTimeMillis()
        totalDistance = 0.0
        waypoints.clear()

        if (lat != null && lng != null) {
            waypoints.addLast(mapOf(
                "latitude" to lat,
                "longitude" to lng,
                "timestamp" to timestamp,
            ))
        }
    }

    private fun endTrip(lat: Double?, lng: Double?, timestamp: Any?) {
        isTripActive = false

        // Add final distance segment.
        val prevLat = lastWaypointLat
        val prevLng = lastWaypointLng
        if (lat != null && lng != null && prevLat != null && prevLng != null) {
            totalDistance += GeoUtils.haversine(prevLat, prevLng, lat, lng)
            waypoints.addLast(mapOf(
                "latitude" to lat,
                "longitude" to lng,
                "timestamp" to timestamp,
            ))
        }

        val durationMs = System.currentTimeMillis() - startTimeMs
        val durationSeconds = durationMs / 1000.0

        val startMap = mutableMapOf<String, Any?>()
        startLat?.let { startMap["latitude"] = it }
        startLng?.let { startMap["longitude"] = it }

        val stopMap = mutableMapOf<String, Any?>()
        lat?.let { stopMap["latitude"] = it }
        lng?.let { stopMap["longitude"] = it }

        val tripData = mapOf<String, Any?>(
            "isMoving" to false,
            "distance" to totalDistance,
            "duration" to durationSeconds,
            "startLocation" to startMap,
            "stopLocation" to stopMap,
            "waypoints" to waypoints.toList(),
        )

        onTripEnd?.invoke(tripData)

        // Clean up.
        startLat = null
        startLng = null
        lastWaypointLat = null
        lastWaypointLng = null
        startTimeMs = 0
        totalDistance = 0.0
        waypoints.clear()
    }
}
