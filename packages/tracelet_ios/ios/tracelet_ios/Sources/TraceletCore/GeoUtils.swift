import Foundation

/// Pure-Swift geospatial utility functions.
///
/// Mirrors the Dart `GeoUtils` class — ray-casting point-in-polygon and
/// Haversine distance.
public enum GeoUtils {

    private static let deg2rad = Double.pi / 180.0

    /// Ray-casting point-in-polygon algorithm.
    ///
    /// Determines if the point (`lat`, `lng`) is inside the polygon defined
    /// by `vertices`. Each vertex is `[latitude, longitude]`.
    ///
    /// Returns `true` if the point is inside the polygon.
    public static func isPointInPolygon(
        lat: Double,
        lng: Double,
        vertices: [[Double]]
    ) -> Bool {
        let n = vertices.count
        guard n >= 3 else { return false }
        var inside = false
        var j = n - 1

        for i in 0..<n {
            let vi = vertices[i]
            guard vi.count >= 2 else { return false }
            let yi = vi[0] // lat
            let xi = vi[1] // lng
            let vj = vertices[j]
            guard vj.count >= 2 else { return false }
            let yj = vj[0]
            let xj = vj[1]

            if (yi > lat) != (yj > lat) &&
                lng < (xj - xi) * (lat - yi) / (yj - yi) + xi {
                inside = !inside
            }
            j = i
        }
        return inside
    }

    /// Haversine distance between two lat/lng points, in meters.
    public static func haversine(
        _ lat1: Double, _ lon1: Double,
        _ lat2: Double, _ lon2: Double
    ) -> Double {
        let r = 6371000.0
        let dLat = (lat2 - lat1) * deg2rad
        let dLon = (lon2 - lon1) * deg2rad
        let sinDLat = sin(dLat * 0.5)
        let sinDLon = sin(dLon * 0.5)
        let a = sinDLat * sinDLat +
            cos(lat1 * deg2rad) * cos(lat2 * deg2rad) *
            sinDLon * sinDLon
        return r * 2.0 * asin(sqrt(min(max(a, 0.0), 1.0)))
    }
}
