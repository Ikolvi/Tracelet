import 'dart:math' as math;

/// Pure-Dart geospatial utility functions.
///
/// Contains algorithms that were previously duplicated in native Kotlin and
/// Swift code. By living in shared Dart, they automatically work on every
/// platform — Android, iOS, web, macOS, Linux, Windows.
class GeoUtils {
  GeoUtils._(); // Prevent instantiation.

  /// Ray-casting point-in-polygon algorithm.
  ///
  /// Determines if the point ([lat], [lng]) is inside the polygon defined
  /// by [vertices]. Each vertex is `[latitude, longitude]`.
  ///
  /// Casts a horizontal ray from the test point to the right and counts
  /// how many polygon edges it crosses. An odd crossing count means the
  /// point is inside.
  ///
  /// Returns `true` if the point is inside the polygon.
  ///
  /// ```dart
  /// final inside = GeoUtils.isPointInPolygon(
  ///   lat: 37.422,
  ///   lng: -122.084,
  ///   vertices: [
  ///     [37.421, -122.085],
  ///     [37.423, -122.085],
  ///     [37.423, -122.083],
  ///     [37.421, -122.083],
  ///   ],
  /// );
  /// ```
  static bool isPointInPolygon({
    required double lat,
    required double lng,
    required List<List<double>> vertices,
  }) {
    var inside = false;
    final n = vertices.length;
    var j = n - 1;

    for (var i = 0; i < n; i++) {
      final vi = vertices[i];
      if (vi.length < 2) return false; // validate inline (D-M2)
      final yi = vi[0]; // lat
      final xi = vi[1]; // lng
      final vj = vertices[j];
      if (vj.length < 2) return false;
      final yj = vj[0];
      final xj = vj[1];

      if ((yi > lat) != (yj > lat) &&
          lng < (xj - xi) * (lat - yi) / (yj - yi) + xi) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  /// Haversine distance between two lat/lng points, in meters.
  ///
  /// ```dart
  /// final d = GeoUtils.haversine(37.421, -122.084, 37.423, -122.082);
  /// print('$d meters'); // ≈ 270m
  /// ```
  static double haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * _deg2rad;
    final dLon = (lon2 - lon1) * _deg2rad;
    final sinDLat = math.sin(dLat * 0.5);
    final sinDLon = math.sin(dLon * 0.5);
    final a =
        sinDLat * sinDLat +
        math.cos(lat1 * _deg2rad) *
            math.cos(lat2 * _deg2rad) *
            sinDLon *
            sinDLon;
    return r * 2.0 * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
  }

  static const double _deg2rad = math.pi / 180.0;
}
