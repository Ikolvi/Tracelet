import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

void main() {
  group('TripManager', () {
    late TripManager tripManager;
    late List<Map<String, Object?>> tripEvents;

    setUp(() {
      tripManager = TripManager();
      tripEvents = <Map<String, Object?>>[];
      tripManager.onTripEnd = (data) => tripEvents.add(data);
    });

    test('starts inactive', () {
      expect(tripManager.isTripActive, isFalse);
    });

    test('starts trip on isMoving=true', () {
      tripManager.onMotionStateChanged(
        isMoving: true,
        latitude: 37.4220,
        longitude: -122.0840,
        timestamp: '2024-01-01T00:00:00Z',
      );

      expect(tripManager.isTripActive, isTrue);
      expect(tripEvents, isEmpty); // No trip end yet
    });

    test('ends trip on isMoving=false and emits event', () {
      tripManager.onMotionStateChanged(
        isMoving: true,
        latitude: 37.4220,
        longitude: -122.0840,
        timestamp: '2024-01-01T00:00:00Z',
      );

      tripManager.onMotionStateChanged(
        isMoving: false,
        latitude: 37.4230,
        longitude: -122.0830,
        timestamp: '2024-01-01T00:05:00Z',
      );

      expect(tripManager.isTripActive, isFalse);
      expect(tripEvents.length, 1);

      final trip = tripEvents.first;
      expect(trip['isMoving'], false);
      expect(trip['distance'], isA<double>());
      expect(trip['duration'], isA<double>());
      expect(trip['startLocation'], isA<Map>());
      expect(trip['stopLocation'], isA<Map>());
      expect(trip['waypoints'], isA<List>());
    });

    test('records start location in trip event', () {
      tripManager.onMotionStateChanged(
        isMoving: true,
        latitude: 37.4220,
        longitude: -122.0840,
      );
      tripManager.onMotionStateChanged(
        isMoving: false,
        latitude: 37.4230,
        longitude: -122.0830,
      );

      final startLoc =
          tripEvents.first['startLocation'] as Map<String, Object?>;
      expect(startLoc['latitude'], 37.4220);
      expect(startLoc['longitude'], -122.0840);

      final stopLoc = tripEvents.first['stopLocation'] as Map<String, Object?>;
      expect(stopLoc['latitude'], 37.4230);
      expect(stopLoc['longitude'], -122.0830);
    });

    test('accumulates waypoints during trip', () {
      tripManager.onMotionStateChanged(
        isMoving: true,
        latitude: 37.4220,
        longitude: -122.0840,
      );

      // Feed locations during trip
      tripManager.onLocationReceived(
        latitude: 37.4221,
        longitude: -122.0841,
        timestamp: 'ts1',
      );
      tripManager.onLocationReceived(
        latitude: 37.4222,
        longitude: -122.0842,
        timestamp: 'ts2',
      );
      tripManager.onLocationReceived(
        latitude: 37.4223,
        longitude: -122.0843,
        timestamp: 'ts3',
      );

      tripManager.onMotionStateChanged(
        isMoving: false,
        latitude: 37.4224,
        longitude: -122.0844,
      );

      final waypoints =
          tripEvents.first['waypoints'] as List<Map<String, Object?>>;
      // start waypoint + 3 locations + stop waypoint = 5
      expect(waypoints.length, 5);
    });

    test('ignores locations when no trip active', () {
      tripManager.onLocationReceived(latitude: 37.4220, longitude: -122.0840);

      // Start and immediately stop
      tripManager.onMotionStateChanged(
        isMoving: true,
        latitude: 10,
        longitude: 20,
      );
      tripManager.onMotionStateChanged(
        isMoving: false,
        latitude: 11,
        longitude: 21,
      );

      final waypoints =
          tripEvents.first['waypoints'] as List<Map<String, Object?>>;
      // Only start + stop = 2
      expect(waypoints.length, 2);
    });

    test('calculates distance using Haversine', () {
      tripManager.onMotionStateChanged(
        isMoving: true,
        latitude: 37.0,
        longitude: -122.0,
      );

      // Move ~111 km north (1 degree latitude)
      tripManager.onLocationReceived(latitude: 38.0, longitude: -122.0);

      tripManager.onMotionStateChanged(
        isMoving: false,
        latitude: 38.0,
        longitude: -122.0,
      );

      final distance = tripEvents.first['distance'] as double;
      // 1 degree latitude ≈ 111,195 meters (±500m tolerance)
      expect(distance, closeTo(111195, 500));
    });

    test('reset clears state', () {
      tripManager.onMotionStateChanged(
        isMoving: true,
        latitude: 10,
        longitude: 20,
      );
      expect(tripManager.isTripActive, isTrue);

      tripManager.reset();

      expect(tripManager.isTripActive, isFalse);
      // No trip end event should be fired on reset
      expect(tripEvents, isEmpty);
    });

    test('duplicate isMoving=true does not restart trip', () {
      tripManager.onMotionStateChanged(
        isMoving: true,
        latitude: 10,
        longitude: 20,
      );
      tripManager.onLocationReceived(latitude: 11, longitude: 21);
      tripManager.onMotionStateChanged(
        isMoving: true,
        latitude: 12,
        longitude: 22,
      );

      // Should still be the same trip
      expect(tripManager.isTripActive, isTrue);

      tripManager.onMotionStateChanged(
        isMoving: false,
        latitude: 13,
        longitude: 23,
      );

      expect(tripEvents.length, 1);
      // Waypoints: start(10,20) + location(11,21) + stop(13,23) = 3
      final waypoints =
          tripEvents.first['waypoints'] as List<Map<String, Object?>>;
      expect(waypoints.length, 3);
    });

    test('duplicate isMoving=false does not emit multiple trips', () {
      tripManager.onMotionStateChanged(
        isMoving: true,
        latitude: 10,
        longitude: 20,
      );
      tripManager.onMotionStateChanged(
        isMoving: false,
        latitude: 11,
        longitude: 21,
      );
      tripManager.onMotionStateChanged(
        isMoving: false,
        latitude: 12,
        longitude: 22,
      );

      expect(tripEvents.length, 1);
    });

    test('onTripEnd not called if callback is null', () {
      tripManager.onTripEnd = null;

      tripManager.onMotionStateChanged(
        isMoving: true,
        latitude: 10,
        longitude: 20,
      );
      tripManager.onMotionStateChanged(
        isMoving: false,
        latitude: 11,
        longitude: 21,
      );

      // Should not throw
      expect(tripEvents, isEmpty);
    });

    test('trip with null start/stop coordinates', () {
      tripManager.onMotionStateChanged(isMoving: true);
      tripManager.onMotionStateChanged(isMoving: false);

      expect(tripEvents.length, 1);
      final startLoc =
          tripEvents.first['startLocation'] as Map<String, Object?>;
      expect(startLoc, isEmpty);
    });
  });
}
