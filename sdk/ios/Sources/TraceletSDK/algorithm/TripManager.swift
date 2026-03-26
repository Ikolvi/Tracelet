import Foundation

/// Tracks trips based on motion state transitions.
///
/// A "trip" starts when the device transitions to moving and ends when it
/// transitions to stationary. Collects start/stop locations, waypoints,
/// total distance (Haversine), and duration.
public class TripManager {
    /// Maximum number of waypoints to retain during a trip.
    private static let maxWaypoints = 5000

    /// Callback invoked when a trip ends with the full trip data map.
    public var onTripEnd: (([String: Any?]) -> Void)?

    /// Whether a trip is currently active.
    public private(set) var isTripActive = false

    private var startLat: Double?
    private var startLng: Double?
    private var startTime: Date?
    private var totalDistance: Double = 0
    private var lastWaypointLat: Double?
    private var lastWaypointLng: Double?
    // Note: Array.removeFirst() is O(n) due to element shifting, unlike
    // Kotlin's ArrayDeque which is O(1). For this use case (maxWaypoints=5000,
    // small dictionary elements), the worst-case cost is ~50µs per eviction
    // and occurs only after the cap is hit — acceptable for a location callback
    // firing at most once per second. Swift's standard library does not provide
    // a Deque, and adding swift-collections would violate the iOS deps policy
    // (Apple frameworks only).
    private var waypoints: [[String: Any?]] = []

    public init() {}

    /// Called on every motion state change.
    ///
    /// - Parameters:
    ///   - isMoving: whether the device is now moving
    ///   - latitude: current latitude (if available)
    ///   - longitude: current longitude (if available)
    ///   - timestamp: current timestamp string or nil
    public func onMotionStateChanged(
        isMoving: Bool,
        latitude: Double? = nil,
        longitude: Double? = nil,
        timestamp: Any? = nil
    ) {
        if isMoving && !isTripActive {
            startTrip(lat: latitude, lng: longitude, timestamp: timestamp)
        } else if !isMoving && isTripActive {
            endTrip(lat: latitude, lng: longitude, timestamp: timestamp)
        }
    }

    /// Called on every accepted tracking location to record waypoints.
    ///
    /// - Parameters:
    ///   - latitude: location latitude
    ///   - longitude: location longitude
    ///   - timestamp: location timestamp
    public func onLocationReceived(
        latitude: Double,
        longitude: Double,
        timestamp: Any? = nil
    ) {
        guard isTripActive else { return }

        // Accumulate distance.
        if let prevLat = lastWaypointLat, let prevLng = lastWaypointLng {
            totalDistance += GeoUtils.haversine(
                prevLat, prevLng,
                latitude, longitude
            )
        }
        lastWaypointLat = latitude
        lastWaypointLng = longitude

        // Record waypoint. Evict oldest when cap exceeded.
        if waypoints.count >= Self.maxWaypoints {
            waypoints.removeFirst()
        }
        waypoints.append([
            "latitude": latitude,
            "longitude": longitude,
            "timestamp": timestamp,
        ])
    }

    /// Reset the trip manager state.
    public func reset() {
        isTripActive = false
        startLat = nil
        startLng = nil
        lastWaypointLat = nil
        lastWaypointLng = nil
        startTime = nil
        totalDistance = 0
        waypoints.removeAll()
    }

    // MARK: - Private

    private func startTrip(lat: Double?, lng: Double?, timestamp: Any?) {
        isTripActive = true
        startLat = lat
        startLng = lng
        lastWaypointLat = lat
        lastWaypointLng = lng
        startTime = Date()
        totalDistance = 0
        waypoints.removeAll()

        if let lat = lat, let lng = lng {
            waypoints.append([
                "latitude": lat,
                "longitude": lng,
                "timestamp": timestamp,
            ])
        }
    }

    private func endTrip(lat: Double?, lng: Double?, timestamp: Any?) {
        isTripActive = false

        // Add final distance segment.
        if let lat = lat, let lng = lng,
           let prevLat = lastWaypointLat, let prevLng = lastWaypointLng {
            totalDistance += GeoUtils.haversine(
                prevLat, prevLng,
                lat, lng
            )
            waypoints.append([
                "latitude": lat,
                "longitude": lng,
                "timestamp": timestamp,
            ])
        }

        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0

        var startMap: [String: Any?] = [:]
        if let sLat = startLat { startMap["latitude"] = sLat }
        if let sLng = startLng { startMap["longitude"] = sLng }

        var stopMap: [String: Any?] = [:]
        if let lat = lat { stopMap["latitude"] = lat }
        if let lng = lng { stopMap["longitude"] = lng }

        let tripData: [String: Any?] = [
            "isMoving": false,
            "distance": totalDistance,
            "duration": duration,
            "startLocation": startMap,
            "stopLocation": stopMap,
            "waypoints": waypoints,
        ]

        onTripEnd?(tripData)

        // Clean up.
        startLat = nil
        startLng = nil
        lastWaypointLat = nil
        lastWaypointLng = nil
        startTime = nil
        totalDistance = 0
        waypoints.removeAll()
    }
}
