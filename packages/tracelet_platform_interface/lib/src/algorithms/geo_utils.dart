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
    if (vertices.any((v) => v.length < 2)) return false;

    var inside = false;
    final n = vertices.length;
    var j = n - 1;

    for (var i = 0; i < n; i++) {
      final yi = vertices[i][0]; // lat
      final xi = vertices[i][1]; // lng
      final yj = vertices[j][0];
      final xj = vertices[j][1];

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
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _toRad(double deg) => deg * (math.pi / 180.0);
}
