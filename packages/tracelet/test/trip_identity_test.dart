import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet/tracelet.dart';

/// #402: the trip identity carried by trip events.
void main() {
  group('TripStartEvent', () {
    test('parses the native trip-start map', () {
      final event = TripStartEvent.fromMap(const <String, Object?>{
        'tripId': '9f2c0f1e-4c31-4b2a-9a77-1d0f3b5e7c88',
        'startedAt': 1755000000000,
        'startLocation': <String, Object?>{
          'latitude': 24.86,
          'longitude': 67.0,
        },
      });

      expect(event.tripId, '9f2c0f1e-4c31-4b2a-9a77-1d0f3b5e7c88');
      expect(event.startedAt.millisecondsSinceEpoch, 1755000000000);
      expect(event.startLocation?.coords.latitude, 24.86);
    });

    test('tolerates a trip that opened before any fix resolved', () {
      // A trip can start on a motion transition with no location yet.
      final event = TripStartEvent.fromMap(const <String, Object?>{
        'tripId': 'trip-1',
        'startedAt': 1755000000000,
        'startLocation': <String, Object?>{},
      });

      expect(event.tripId, 'trip-1');
      expect(event.startLocation, isNull);
    });

    test('round-trips through toMap', () {
      const map = <String, Object?>{
        'tripId': 'trip-1',
        'startedAt': 1755000000000,
        'startLocation': <String, Object?>{'latitude': 1.0, 'longitude': 2.0},
      };
      final event = TripStartEvent.fromMap(map);
      expect(TripStartEvent.fromMap(event.toMap()), event);
    });
  });

  group('TripEvent', () {
    test('carries the trip id and absolute bounds', () {
      final trip = TripEvent.fromMap(const <String, Object?>{
        'isMoving': false,
        'tripId': '9f2c0f1e-4c31-4b2a-9a77-1d0f3b5e7c88',
        'startedAt': 1755000000000,
        'endedAt': 1755000120000,
        'distance': 18420.0,
        'duration': 120.0,
        'startLocation': <String, Object?>{'latitude': 1.0, 'longitude': 2.0},
        'stopLocation': <String, Object?>{'latitude': 3.0, 'longitude': 4.0},
      });

      expect(trip.tripId, '9f2c0f1e-4c31-4b2a-9a77-1d0f3b5e7c88');
      expect(trip.startedAt?.millisecondsSinceEpoch, 1755000000000);
      expect(trip.endedAt?.millisecondsSinceEpoch, 1755000120000);
      // The bounds must agree with the duration they summarise.
      expect(
        trip.endedAt!.difference(trip.startedAt!).inSeconds,
        trip.duration.round(),
      );
      expect(trip.averageSpeed, closeTo(153.5, 0.1));
    });

    test('a trip from an older SDK reads as having no identity', () {
      // Upgrade path: nothing in the map, and the getters are nullable rather
      // than defaulted, so an app can tell "no trip id" from a real one.
      final trip = TripEvent.fromMap(const <String, Object?>{
        'isMoving': false,
        'distance': 100.0,
        'duration': 10.0,
        'startLocation': <String, Object?>{'latitude': 1.0, 'longitude': 2.0},
        'stopLocation': <String, Object?>{'latitude': 3.0, 'longitude': 4.0},
      });

      expect(trip.tripId, isNull);
      expect(trip.startedAt, isNull);
      expect(trip.endedAt, isNull);
      expect(trip.distance, 100.0);
    });

    test('identity participates in equality', () {
      TripEvent build(String? id) => TripEvent.fromMap(<String, Object?>{
        'isMoving': false,
        'tripId': id,
        'distance': 1.0,
        'duration': 1.0,
        'startLocation': const <String, Object?>{
          'latitude': 1.0,
          'longitude': 2.0,
        },
        'stopLocation': const <String, Object?>{
          'latitude': 1.0,
          'longitude': 2.0,
        },
      });

      expect(build('a'), build('a'));
      expect(build('a'), isNot(build('b')));
    });
  });
}
