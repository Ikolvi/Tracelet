import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet_web/src/web_event_dispatcher.dart';
import 'package:tracelet_web/src/web_geofence_engine.dart';

void main() {
  late WebEventDispatcher events;
  late WebGeofenceEngine engine;

  setUp(() {
    events = WebEventDispatcher();
    engine = WebGeofenceEngine(events);
  });

  tearDown(() {
    engine.dispose();
    events.dispose();
  });

  group('WebGeofenceEngine', () {
    test('addGeofence stores and retrieves geofence', () {
      final fence = <String, Object?>{
        'identifier': 'office',
        'latitude': 37.4220,
        'longitude': -122.0841,
        'radius': 200.0,
        'notifyOnEntry': true,
        'notifyOnExit': true,
        'notifyOnDwell': false,
      };

      expect(engine.addGeofence(fence), isTrue);
      expect(engine.geofenceExists('office'), isTrue);
      expect(engine.getGeofences(), hasLength(1));

      final retrieved = engine.getGeofence('office');
      expect(retrieved, isNotNull);
      expect(retrieved!['latitude'], 37.4220);
    });

    test('addGeofence rejects empty identifier', () {
      final fence = <String, Object?>{
        'identifier': '',
        'latitude': 0.0,
        'longitude': 0.0,
        'radius': 100.0,
      };

      expect(engine.addGeofence(fence), isFalse);
    });

    test('addGeofences adds multiple geofences', () {
      final fences = [
        <String, Object?>{
          'identifier': 'a',
          'latitude': 1.0,
          'longitude': 2.0,
          'radius': 100.0,
        },
        <String, Object?>{
          'identifier': 'b',
          'latitude': 3.0,
          'longitude': 4.0,
          'radius': 200.0,
        },
      ];

      expect(engine.addGeofences(fences), isTrue);
      expect(engine.getGeofences(), hasLength(2));
    });

    test('removeGeofence removes specific geofence', () {
      engine.addGeofence(<String, Object?>{
        'identifier': 'test',
        'latitude': 1.0,
        'longitude': 2.0,
        'radius': 100.0,
      });

      expect(engine.removeGeofence('test'), isTrue);
      expect(engine.geofenceExists('test'), isFalse);
    });

    test('removeGeofences clears all', () {
      engine.addGeofences([
        <String, Object?>{
          'identifier': 'a',
          'latitude': 1.0,
          'longitude': 2.0,
          'radius': 100.0,
        },
        <String, Object?>{
          'identifier': 'b',
          'latitude': 3.0,
          'longitude': 4.0,
          'radius': 200.0,
        },
      ]);

      expect(engine.removeGeofences(), isTrue);
      expect(engine.getGeofences(), isEmpty);
    });

    test('checkGeofences emits ENTER when entering geofence', () async {
      engine.addGeofence(<String, Object?>{
        'identifier': 'zone',
        'latitude': 37.4220,
        'longitude': -122.0841,
        'radius': 500.0,
        'notifyOnEntry': true,
        'notifyOnExit': true,
        'notifyOnDwell': false,
      });

      final completer = Completer<Map<String, Object?>>();
      events.onGeofence.listen(completer.complete);

      // Position inside the geofence (same point).
      final loc = <String, Object?>{
        'coords': <String, Object?>{
          'latitude': 37.4220,
          'longitude': -122.0841,
        },
      };
      engine.checkGeofences(37.4220, -122.0841, loc);

      final event = await completer.future.timeout(const Duration(seconds: 1));
      expect(event['identifier'], 'zone');
      expect(event['action'], 'ENTER');
    });

    test('checkGeofences emits EXIT when leaving geofence', () async {
      engine.addGeofence(<String, Object?>{
        'identifier': 'zone',
        'latitude': 37.4220,
        'longitude': -122.0841,
        'radius': 100.0,
        'notifyOnEntry': true,
        'notifyOnExit': true,
        'notifyOnDwell': false,
      });

      final geofenceEvents = <Map<String, Object?>>[];
      events.onGeofence.listen(geofenceEvents.add);

      // Enter.
      final loc1 = <String, Object?>{
        'coords': <String, Object?>{
          'latitude': 37.4220,
          'longitude': -122.0841,
        },
      };
      engine.checkGeofences(37.4220, -122.0841, loc1);

      // Exit (far away).
      final loc2 = <String, Object?>{
        'coords': <String, Object?>{'latitude': 38.0, 'longitude': -123.0},
      };
      engine.checkGeofences(38.0, -123.0, loc2);

      // Give async a moment.
      await Future<void>.delayed(Duration.zero);

      expect(geofenceEvents, hasLength(2));
      expect(geofenceEvents[0]['action'], 'ENTER');
      expect(geofenceEvents[1]['action'], 'EXIT');
    });

    test('getGeofence returns null for unknown identifier', () {
      expect(engine.getGeofence('nonexistent'), isNull);
    });

    test('geofenceExists returns false for unknown identifier', () {
      expect(engine.geofenceExists('nonexistent'), isFalse);
    });
  });
}
