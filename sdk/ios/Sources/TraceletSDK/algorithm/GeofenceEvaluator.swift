import Foundation

/// A single geofence state transition detected by `GeofenceEvaluator`.
public struct GeofenceTransition {
    /// The geofence identifier that triggered.
    public let identifier: String
    /// `"ENTER"` or `"EXIT"`.
    public let action: String
    /// Distance in meters from the geofence center (circular only).
    public let distance: Double?
    /// The full geofence data map.
    public let geofence: [String: Any?]

    public init(
        identifier: String,
        action: String,
        distance: Double? = nil,
        geofence: [String: Any?] = [:]
    ) {
        self.identifier = identifier
        self.action = action
        self.distance = distance
        self.geofence = geofence
    }
}

/// High-accuracy geofence proximity evaluator.
///
/// On each location update, computes the distance from the current position
/// to every registered geofence and fires ENTER/EXIT transitions based on
/// threshold crossings.
///
/// Supports both **circular** geofences (distance ≤ radius) and **polygon**
/// geofences (ray-casting point-in-polygon via `GeoUtils`).
///
/// When the registered geofence count exceeds ~50, call `indexGeofences`
/// to build an R-tree spatial index for O(log n) queries.
public class GeofenceEvaluator {
    /// Set of geofence identifiers the device is currently inside.
    private var _insideGeofenceIds = Set<String>()

    /// Cached unmodifiable view.
    private var _cachedInsideView: Set<String>?

    /// Spatial index for O(log n) geofence queries.
    private var rtree: RTree<[String: Any?]>?

    /// Geofence data indexed by identifier, for EXIT detection on indexed path.
    private var indexedGeofences: [String: [String: Any?]]?

    /// Read-only view of the geofence identifiers currently marked as "inside".
    public var insideGeofenceIds: Set<String> {
        if _cachedInsideView == nil {
            _cachedInsideView = _insideGeofenceIds
        }
        return _cachedInsideView!
    }

    /// Whether a spatial index is currently active.
    public var isIndexed: Bool { rtree != nil }

    public init() {}

    /// Build an R-tree spatial index over `geofences` for O(log n) queries.
    ///
    /// When the index is present, `evaluateProximity` uses it to narrow
    /// candidates before computing exact distances.
    public func indexGeofences(_ geofences: [[String: Any?]]) {
        let tree = RTree<[String: Any?]>(maxEntries: 8)
        var lookup: [String: [String: Any?]] = [:]

        for gf in geofences {
            guard let id = gf["identifier"] as? String,
                  let lat = Self.toDouble(gf["latitude"]),
                  let lng = Self.toDouble(gf["longitude"]) else { continue }
            let radius = Self.toDouble(gf["radius"]) ?? 100.0
            tree.insert(lat: lat, lng: lng, radius: radius, data: gf)
            lookup[id] = gf
        }

        rtree = tree
        indexedGeofences = lookup
    }

    /// Remove the spatial index.
    public func clearIndex() {
        rtree?.clear()
        rtree = nil
        indexedGeofences = nil
    }

    /// Evaluate all geofences against the current position.
    ///
    /// Returns a list of `GeofenceTransition`s that occurred (may be empty).
    public func evaluateProximity(
        latitude: Double,
        longitude: Double,
        geofences: [[String: Any?]]
    ) -> [GeofenceTransition] {
        let effectiveGeofences = resolveGeofences(latitude, longitude, geofences)
        var transitions: [GeofenceTransition] = []

        for gf in effectiveGeofences {
            guard let identifier = gf["identifier"] as? String else { continue }
            let gfLat = Self.toDouble(gf["latitude"])
            let gfLng = Self.toDouble(gf["longitude"])

            // ── Polygon geofence ──────────────────────────────────────
            if let rawVertices = gf["vertices"] as? [Any], rawVertices.count >= 3 {
                var vertices: [[Double]] = []
                var valid = true
                for v in rawVertices {
                    if let arr = v as? [Any], arr.count >= 2,
                       let lat = Self.toDouble(arr[0]),
                       let lng = Self.toDouble(arr[1]) {
                        vertices.append([lat, lng])
                    } else {
                        valid = false
                        break
                    }
                }

                if valid && vertices.count >= 3 {
                    let isInside = GeoUtils.isPointInPolygon(
                        lat: latitude,
                        lng: longitude,
                        vertices: vertices
                    )
                    let wasInside = _insideGeofenceIds.contains(identifier)

                    if isInside && !wasInside {
                        _insideGeofenceIds.insert(identifier)
                        _cachedInsideView = nil
                        transitions.append(GeofenceTransition(
                            identifier: identifier,
                            action: "ENTER",
                            geofence: gf
                        ))
                    } else if !isInside && wasInside {
                        _insideGeofenceIds.remove(identifier)
                        _cachedInsideView = nil
                        transitions.append(GeofenceTransition(
                            identifier: identifier,
                            action: "EXIT",
                            geofence: gf
                        ))
                    }
                    continue
                }
            }

            // ── Circular geofence ─────────────────────────────────────
            guard let gfLat = gfLat, let gfLng = gfLng else { continue }

            let gfRadius = Self.toDouble(gf["radius"]) ?? 100.0
            guard gfRadius > 0 else { continue }

            let distance = GeoUtils.haversine(latitude, longitude, gfLat, gfLng)
            let wasInside = _insideGeofenceIds.contains(identifier)
            let isInside = distance <= gfRadius

            if isInside && !wasInside {
                _insideGeofenceIds.insert(identifier)
                _cachedInsideView = nil
                transitions.append(GeofenceTransition(
                    identifier: identifier,
                    action: "ENTER",
                    distance: distance,
                    geofence: gf
                ))
            } else if !isInside && wasInside {
                _insideGeofenceIds.remove(identifier)
                _cachedInsideView = nil
                transitions.append(GeofenceTransition(
                    identifier: identifier,
                    action: "EXIT",
                    distance: distance,
                    geofence: gf
                ))
            }
        }

        return transitions
    }

    /// Clear all tracking state. Call when tracking restarts.
    public func clear() {
        _insideGeofenceIds.removeAll()
        _cachedInsideView = nil
        clearIndex()
    }

    /// Remove a specific geofence from the "inside" set.
    public func removeGeofence(_ identifier: String) {
        _insideGeofenceIds.remove(identifier)
        _cachedInsideView = nil
    }

    // MARK: - Private

    private func resolveGeofences(
        _ lat: Double,
        _ lng: Double,
        _ allGeofences: [[String: Any?]]
    ) -> [[String: Any?]] {
        guard let tree = rtree, let lookup = indexedGeofences else {
            return allGeofences
        }

        let searchRadius = 50000.0 // 50 km
        let nearby = tree.queryCircle(lat: lat, lng: lng, radiusMeters: searchRadius)

        if _insideGeofenceIds.isEmpty { return nearby }

        var seen = Set<String>()
        var merged: [[String: Any?]] = []
        for gf in nearby {
            if let id = gf["identifier"] as? String { seen.insert(id) }
            merged.append(gf)
        }
        for id in _insideGeofenceIds {
            if !seen.contains(id), let gf = lookup[id] {
                merged.append(gf)
            }
        }
        return merged
    }

    private static func toDouble(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }
}
