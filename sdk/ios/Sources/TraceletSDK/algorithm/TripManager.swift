import Foundation

/// Tracks trips based on motion state transitions, delegating core logic to Rust.
public class TraceletTripManager {
    /// Callback invoked when a trip ends with the full trip data map.
    public var onTripEnd: (([String: Any?]) -> Void)?

    /// Callback invoked when a trip *starts*, with its freshly minted id (#402).
    ///
    /// Before #402 a trip only became observable once it was over, so anything
    /// wanting to tag records with the trip they belong to had no moment to act
    /// on and had to re-derive the boundary from raw motion changes.
    public var onTripStart: (([String: Any?]) -> Void)?

    private let rustTripManager = TripManager()

    /// Whether a trip is currently active.
    public var isTripActive: Bool {
        return rustTripManager.isTripActive()
    }

    /// The active trip's id, or nil between trips (#402).
    public var currentTripId: String? {
        return rustTripManager.currentTripId()
    }

    public init() {}

    public func onMotionStateChanged(
        isMoving: Bool,
        latitude: Double? = nil,
        longitude: Double? = nil,
        timestamp: Any? = nil
    ) {
        let now = Date()
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let timestampMs = (timestamp as? NSNumber)?.int64Value ?? nowMs

        guard let transition = rustTripManager.onMotionStateChanged(
            isMoving: isMoving,
            latitude: latitude,
            longitude: longitude,
            timestampMs: timestampMs,
            nowMs: nowMs
        ) else {
            // Not a trip boundary — moving while already moving, or stopped
            // while already stopped.
            return
        }

        if case .started(let start) = transition {
            var startMap: [String: Any?] = [:]
            if let startLoc = start.startLocation {
                startMap["latitude"] = startLoc.latitude
                startMap["longitude"] = startLoc.longitude
            }
            onTripStart?([
                "tripId": start.tripId,
                "startedAt": start.startedAtMs,
                "startLocation": startMap
            ])
            return
        }

        guard case .ended(let tripData) = transition else { return }

        var startMap: [String: Any?] = [:]
        if let startLoc = tripData.startLocation {
            startMap["latitude"] = startLoc.latitude
            startMap["longitude"] = startLoc.longitude
        }

        var stopMap: [String: Any?] = [:]
        if let stopLoc = tripData.stopLocation {
            stopMap["latitude"] = stopLoc.latitude
            stopMap["longitude"] = stopLoc.longitude
        }

        let waypoints = tripData.waypoints.map { wp in
            [
                "latitude": wp.latitude,
                "longitude": wp.longitude,
                "timestamp": wp.timestampMs
            ]
        }

        let outData: [String: Any?] = [
            "isMoving": false,
            // #402: the join key shared with every location and driving
            // event recorded during this trip.
            "tripId": tripData.tripId,
            "startedAt": tripData.startedAtMs,
            "endedAt": tripData.endedAtMs,
            "distance": tripData.distanceMeters,
            "duration": tripData.durationSeconds,
            "startLocation": startMap,
            "stopLocation": stopMap,
            "waypoints": waypoints
        ]

        onTripEnd?(outData)
    }

    public func onLocationReceived(
        latitude: Double,
        longitude: Double,
        timestamp: Any? = nil
    ) {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let timestampMs = (timestamp as? NSNumber)?.int64Value ?? nowMs
        rustTripManager.onLocationReceived(
            latitude: latitude,
            longitude: longitude,
            timestampMs: timestampMs
        )
    }

    public func reset() {
        rustTripManager.reset()
    }
}
