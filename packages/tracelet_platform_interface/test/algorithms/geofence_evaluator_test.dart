import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

void main() async {
  await RustLib.init();
  group('GeofenceEvaluator', () {
    late GeofenceEvaluator evaluator;

    setUp(() {
      evaluator = GeofenceEvaluator();
    });

    test('detects ENTER for circular geofence', () {
      final geofences = <Map<String, Object?>>[
        {
          'identifier': 'office',
          'latitude': 37.4220,
          'longitude': -122.0841,
          'radius': 100.0,
        },
      ];

      final transitions = evaluator.evaluateProximity(
        latitude: 37.4220,
        longitude: -122.0841,
        geofences: geofences,
      );

      expect(transitions, hasLength(1));
      expect(transitions[0].action, 'ENTER');
      expect(transitions[0].identifier, 'office');
      expect(transitions[0].distance, isNotNull);
    });

    test('no transition when already inside', () {
      final geofences = <Map<String, Object?>>[
        {
          'identifier': 'office',
          'latitude': 37.4220,
          'longitude': -122.0841,
          'radius': 100.0,
        },
      ];

      // First call — ENTER.
      evaluator.evaluateProximity(
        latitude: 37.4220,
        longitude: -122.0841,
        geofences: geofences,
      );

      // Second call — still inside, no new transition.
      final transitions = evaluator.evaluateProximity(
        latitude: 37.42201,
        longitude: -122.08411,
        geofences: geofences,
      );

      expect(transitions, isEmpty);
    });

    test('detects EXIT when moving outside radius', () {
      final geofences = <Map<String, Object?>>[
        {
          'identifier': 'office',
          'latitude': 37.4220,
          'longitude': -122.0841,
          'radius': 100.0,
        },
      ];

      // ENTER.
      evaluator.evaluateProximity(
        latitude: 37.4220,
        longitude: -122.0841,
        geofences: geofences,
      );

      // EXIT — far away.
      final transitions = evaluator.evaluateProximity(
        latitude: 37.4300,
        longitude: -122.0841,
        geofences: geofences,
      );

      expect(transitions, hasLength(1));
      expect(transitions[0].action, 'EXIT');
      expect(transitions[0].identifier, 'office');
    });

    test('detects ENTER for polygon geofence', () {
      final geofences = <Map<String, Object?>>[
        {
          'identifier': 'campus',
          'latitude': 37.4220,
          'longitude': -122.0841,
          'radius': 0.0,
          'vertices': <List<double>>[
            [37.421, -122.085],
            [37.423, -122.085],
            [37.423, -122.083],
            [37.421, -122.083],
          ],
        },
      ];

      // Inside the polygon.
      final transitions = evaluator.evaluateProximity(
        latitude: 37.4220,
        longitude: -122.0840,
        geofences: geofences,
      );

      expect(transitions, hasLength(1));
      expect(transitions[0].action, 'ENTER');
      expect(transitions[0].identifier, 'campus');
      expect(transitions[0].distance, isNull); // No distance for polygons.
    });

    test('detects EXIT for polygon geofence', () {
      final geofences = <Map<String, Object?>>[
        {
          'identifier': 'campus',
          'latitude': 37.4220,
          'longitude': -122.0841,
          'radius': 0.0,
          'vertices': <List<double>>[
            [37.421, -122.085],
            [37.423, -122.085],
            [37.423, -122.083],
            [37.421, -122.083],
          ],
        },
      ];

      // ENTER.
      evaluator.evaluateProximity(
        latitude: 37.4220,
        longitude: -122.0840,
        geofences: geofences,
      );

      // EXIT — outside polygon.
      final transitions = evaluator.evaluateProximity(
        latitude: 37.4200,
        longitude: -122.0800,
        geofences: geofences,
      );

      expect(transitions, hasLength(1));
      expect(transitions[0].action, 'EXIT');
    });

    test('handles multiple geofences with mixed transitions', () {
      final geofences = <Map<String, Object?>>[
        {
          'identifier': 'a',
          'latitude': 37.4220,
          'longitude': -122.0841,
          'radius': 100.0,
        },
        {
          'identifier': 'b',
          'latitude': 37.5000,
          'longitude': -122.0841,
          'radius': 100.0,
        },
      ];

      // Inside A, outside B → ENTER A.
      final t1 = evaluator.evaluateProximity(
        latitude: 37.4220,
        longitude: -122.0841,
        geofences: geofences,
      );
      expect(t1, hasLength(1));
      expect(t1[0].identifier, 'a');
      expect(t1[0].action, 'ENTER');

      // Outside A, inside B → EXIT A + ENTER B.
      final t2 = evaluator.evaluateProximity(
        latitude: 37.5000,
        longitude: -122.0841,
        geofences: geofences,
      );
      expect(t2, hasLength(2));
      final actions = t2.map((t) => '${t.action}:${t.identifier}').toSet();
      expect(actions, containsAll(['EXIT:a', 'ENTER:b']));
    });

    test('skips geofences with invalid data', () {
      final geofences = <Map<String, Object?>>[
        {'identifier': null},
        {'identifier': 'noCoords'},
        {
          'identifier': 'valid',
          'latitude': 37.4220,
          'longitude': -122.0841,
          'radius': 100.0,
        },
      ];

      final transitions = evaluator.evaluateProximity(
        latitude: 37.4220,
        longitude: -122.0841,
        geofences: geofences,
      );

      expect(transitions, hasLength(1));
      expect(transitions[0].identifier, 'valid');
    });

    test('skips geofences with radius <= 0', () {
      final geofences = <Map<String, Object?>>[
        {
          'identifier': 'zeroRadius',
          'latitude': 37.4220,
          'longitude': -122.0841,
          'radius': 0.0,
        },
      ];

      final transitions = evaluator.evaluateProximity(
        latitude: 37.4220,
        longitude: -122.0841,
        geofences: geofences,
      );

      expect(transitions, isEmpty);
    });

    test('clear resets inside state', () {
      final geofences = <Map<String, Object?>>[
        {
          'identifier': 'office',
          'latitude': 37.4220,
          'longitude': -122.0841,
          'radius': 100.0,
        },
      ];

      evaluator.evaluateProximity(
        latitude: 37.4220,
        longitude: -122.0841,
        geofences: geofences,
      );
      expect(evaluator.insideGeofenceIds, contains('office'));

      evaluator.clear();
      expect(evaluator.insideGeofenceIds, isEmpty);

      // Should trigger ENTER again.
      final transitions = evaluator.evaluateProximity(
        latitude: 37.4220,
        longitude: -122.0841,
        geofences: geofences,
      );
      expect(transitions, hasLength(1));
      expect(transitions[0].action, 'ENTER');
    });

    test('removeGeofence removes from inside set', () {
      final geofences = <Map<String, Object?>>[
        {
          'identifier': 'office',
          'latitude': 37.4220,
          'longitude': -122.0841,
          'radius': 100.0,
        },
      ];

      evaluator.evaluateProximity(
        latitude: 37.4220,
        longitude: -122.0841,
        geofences: geofences,
      );
      expect(evaluator.insideGeofenceIds, contains('office'));

      evaluator.removeGeofence('office');
      expect(evaluator.insideGeofenceIds, isEmpty);
    });

    // Regression for #268: a stationary device near the edge whose fixes
    // jitter across the boundary must not flap between ENTER and EXIT.
    ({double lat, double lng}) pointNorth(
      double centerLat,
      double centerLng,
      double distanceMeters,
    ) => (lat: centerLat + distanceMeters / 111320.0, lng: centerLng);

    test('stationary boundary jitter does not flap (#268)', () {
      const centerLat = 37.4219983;
      const centerLng = -122.084;
      final geofences = <Map<String, Object?>>[
        {
          'identifier': 'flap',
          'latitude': centerLat,
          'longitude': centerLng,
          'radius': 100.0,
        },
      ];

      // Initial solid fix inside, then jitter straddling the 100 m boundary
      // but staying within radius + buffer (120 m).
      const distances = <double>[40, 96, 104, 95, 106, 97, 103];
      var enters = 0;
      var exits = 0;
      for (final d in distances) {
        final p = pointNorth(centerLat, centerLng, d);
        final transitions = evaluator.evaluateProximity(
          latitude: p.lat,
          longitude: p.lng,
          geofences: geofences,
        );
        for (final t in transitions) {
          if (t.action == 'ENTER') enters++;
          if (t.action == 'EXIT') exits++;
        }
      }

      expect(enters, 1, reason: 'expected exactly one ENTER');
      expect(exits, 0, reason: 'boundary jitter must not produce any EXIT');
    });

    test('genuine exit beyond the hysteresis band still fires (#268)', () {
      const centerLat = 37.4219983;
      const centerLng = -122.084;
      final geofences = <Map<String, Object?>>[
        {
          'identifier': 'home',
          'latitude': centerLat,
          'longitude': centerLng,
          'radius': 100.0,
        },
      ];

      // Enter well inside.
      final inside = pointNorth(centerLat, centerLng, 20);
      evaluator.evaluateProximity(
        latitude: inside.lat,
        longitude: inside.lng,
        geofences: geofences,
      );

      // Move clearly outside (well past radius + 20 m buffer).
      final far = pointNorth(centerLat, centerLng, 400);
      final transitions = evaluator.evaluateProximity(
        latitude: far.lat,
        longitude: far.lng,
        geofences: geofences,
      );

      expect(transitions, hasLength(1));
      expect(transitions[0].action, 'EXIT');
    });

    test('polygon with integer vertices works', () {
      final geofences = <Map<String, Object?>>[
        {
          'identifier': 'campus',
          'latitude': 37.4220,
          'longitude': -122.0841,
          'radius': 0,
          'vertices': <List<num>>[
            [37, -123],
            [38, -123],
            [38, -122],
            [37, -122],
          ],
        },
      ];

      final transitions = evaluator.evaluateProximity(
        latitude: 37.5,
        longitude: -122.5,
        geofences: geofences,
      );

      expect(transitions, hasLength(1));
      expect(transitions[0].action, 'ENTER');
    });
  });
}
