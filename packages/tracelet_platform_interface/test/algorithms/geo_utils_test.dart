import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

void main() {
  group('GeoUtils.isPointInPolygon', () {
    // A square polygon: 37.42–37.43 lat, -122.085–-122.083 lng
    final square = <List<double>>[
      <double>[37.42, -122.085],
      <double>[37.43, -122.085],
      <double>[37.43, -122.083],
      <double>[37.42, -122.083],
    ];

    test('point inside returns true', () {
      expect(
        GeoUtils.isPointInPolygon(lat: 37.425, lng: -122.084, vertices: square),
        isTrue,
      );
    });

    test('point outside returns false', () {
      expect(
        GeoUtils.isPointInPolygon(lat: 37.410, lng: -122.084, vertices: square),
        isFalse,
      );
    });

    test('point far outside returns false', () {
      expect(
        GeoUtils.isPointInPolygon(lat: 0.0, lng: 0.0, vertices: square),
        isFalse,
      );
    });

    test('triangle polygon', () {
      final triangle = <List<double>>[
        <double>[0.0, 0.0],
        <double>[10.0, 0.0],
        <double>[5.0, 10.0],
      ];

      // Centroid roughly at (5, 3.3)
      expect(
        GeoUtils.isPointInPolygon(lat: 5.0, lng: 3.0, vertices: triangle),
        isTrue,
      );

      // Outside below the triangle
      expect(
        GeoUtils.isPointInPolygon(lat: 5.0, lng: 11.0, vertices: triangle),
        isFalse,
      );
    });

    test('concave polygon (L-shape)', () {
      final lShape = <List<double>>[
        <double>[0.0, 0.0],
        <double>[10.0, 0.0],
        <double>[10.0, 5.0],
        <double>[5.0, 5.0],
        <double>[5.0, 10.0],
        <double>[0.0, 10.0],
      ];

      // Inside the bottom part
      expect(
        GeoUtils.isPointInPolygon(lat: 2.0, lng: 2.0, vertices: lShape),
        isTrue,
      );

      // Inside the left leg
      expect(
        GeoUtils.isPointInPolygon(lat: 7.0, lng: 2.0, vertices: lShape),
        isTrue,
      );

      // Outside the concave cutout (upper-right)
      expect(
        GeoUtils.isPointInPolygon(lat: 7.0, lng: 7.0, vertices: lShape),
        isFalse,
      );
    });

    test('returns false for invalid vertices (less than 2 coords)', () {
      final bad = <List<double>>[
        <double>[37.42],
        <double>[37.43, -122.085],
        <double>[37.43, -122.083],
      ];
      expect(
        GeoUtils.isPointInPolygon(lat: 37.425, lng: -122.084, vertices: bad),
        isFalse,
      );
    });

    test('returns false for degenerate polygon (fewer than 3 vertices)', () {
      final line = <List<double>>[
        <double>[0.0, 0.0],
        <double>[10.0, 0.0],
      ];
      // A 2-vertex "polygon" is just a line — should not contain anything
      // (technically the algorithm will run but produce consistent results)
      expect(
        GeoUtils.isPointInPolygon(lat: 5.0, lng: 0.0, vertices: line),
        isFalse,
      );
    });
  });

  group('GeoUtils.haversine', () {
    test('same point returns 0', () {
      expect(GeoUtils.haversine(37.42, -122.08, 37.42, -122.08), 0.0);
    });

    test('1 degree latitude ≈ 111 km', () {
      final distance = GeoUtils.haversine(37.0, -122.0, 38.0, -122.0);
      expect(distance, closeTo(111195, 500));
    });

    test('known distance: San Francisco to Los Angeles ≈ 559 km', () {
      // SF: 37.7749, -122.4194
      // LA: 34.0522, -118.2437
      final distance = GeoUtils.haversine(
        37.7749,
        -122.4194,
        34.0522,
        -118.2437,
      );
      expect(distance, closeTo(559000, 5000));
    });

    test('short distance ~100m', () {
      // ~100m north of a point (roughly 0.0009 degrees latitude)
      final distance = GeoUtils.haversine(37.4220, -122.084, 37.4229, -122.084);
      expect(distance, closeTo(100, 5));
    });

    test('symmetry: haversine(A,B) == haversine(B,A)', () {
      final d1 = GeoUtils.haversine(37.0, -122.0, 38.0, -121.0);
      final d2 = GeoUtils.haversine(38.0, -121.0, 37.0, -122.0);
      expect(d1, closeTo(d2, 0.001));
    });

    test('antipodal points ≈ 20,000 km', () {
      // North pole to south pole
      final distance = GeoUtils.haversine(90.0, 0.0, -90.0, 0.0);
      expect(distance, closeTo(20015000, 5000));
    });
  });
}
