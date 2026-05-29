import Foundation

public struct GeoUtils {
    /// Calculates the great-circle distance between two points on the Earth's surface
    /// using the Haversine formula. Returns the distance in meters.
    public static func haversine(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        return tracelet_ios.haversine(lat1: lat1, lon1: lon1, lat2: lat2, lon2: lon2)
    }

    /// Determines if a given point is inside a polygon using the Ray-Casting algorithm.
    public static func isPointInPolygon(_ latitude: Double, _ longitude: Double, _ polygon: [[Double]]) -> Bool {
        let coords = polygon.map { Coordinate(lat: $0[0], lng: $0[1]) }
        return tracelet_ios.isPointInPolygon(lat: latitude, lng: longitude, vertices: coords)
    }
}
