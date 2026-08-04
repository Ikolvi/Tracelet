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

      // EXIT — far away. Confirmed across two consecutive out-of-fence fixes
      // (#294): the first is held, the second fires EXIT.
      evaluator.evaluateProximity(
        latitude: 37.4300,
        longitude: -122.0841,
        geofences: geofences,
      );
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

      // EXIT — outside polygon, confirmed across two consecutive fixes (#294).
      evaluator.evaluateProximity(
        latitude: 37.4200,
        longitude: -122.0800,
        geofences: geofences,
      );
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

      // Move to B. ENTER B fires immediately (accuracy-agnostic); EXIT A is held
      // for confirmation on this first out-of-A fix (#294).
      final t2 = evaluator.evaluateProximity(
        latitude: 37.5000,
        longitude: -122.0841,
        geofences: geofences,
      );
      expect(t2.map((t) => '${t.action}:${t.identifier}').toSet(), {'ENTER:b'});

      // Second fix at B confirms the departure from A → EXIT A.
      final t3 = evaluator.evaluateProximity(
        latitude: 37.5000,
        longitude: -122.0841,
        geofences: geofences,
      );
      expect(t3.map((t) => '${t.action}:${t.identifier}').toSet(), {'EXIT:a'});
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

      // Move clearly outside (well past radius + 20 m buffer), sustained across
      // two consecutive fixes → confirmed EXIT (#294).
      final far = pointNorth(centerLat, centerLng, 400);
      evaluator.evaluateProximity(
        latitude: far.lat,
        longitude: far.lng,
        geofences: geofences,
      );
      final transitions = evaluator.evaluateProximity(
        latitude: far.lat,
        longitude: far.lng,
        geofences: geofences,
      );

      expect(transitions, hasLength(1));
      expect(transitions[0].action, 'EXIT');
    });

    test('high-accuracy drift does not fire a false EXIT (#274)', () {
      const centerLat = 37.4219983;
      const centerLng = -122.084;
      final geofences = <Map<String, Object?>>[
        {
          'identifier': 'attendance',
          'latitude': centerLat,
          'longitude': centerLng,
          'radius': 50.0, // exit threshold = 70 m
        },
      ];

      // Solid fix inside with good accuracy → ENTER.
      final inside = pointNorth(centerLat, centerLng, 10);
      final enter = evaluator.evaluateProximity(
        latitude: inside.lat,
        longitude: inside.lng,
        accuracy: 8,
        geofences: geofences,
      );
      expect(enter, hasLength(1));
      expect(enter[0].action, 'ENTER');

      // Drift spike: reported 160 m out but with ±150 m accuracy. The nearest
      // plausible position (160 - 150 = 10 m) is still inside → hold, no EXIT.
      final drift = pointNorth(centerLat, centerLng, 160);
      final driftTransitions = evaluator.evaluateProximity(
        latitude: drift.lat,
        longitude: drift.lng,
        accuracy: 150,
        geofences: geofences,
      );
      expect(
        driftTransitions,
        isEmpty,
        reason: 'high-drift low-confidence fix must not fire EXIT',
      );
    });

    test(
      'accurate genuine departure still EXITs with gating active (#274)',
      () {
        const centerLat = 37.4219983;
        const centerLng = -122.084;
        final geofences = <Map<String, Object?>>[
          {
            'identifier': 'attendance',
            'latitude': centerLat,
            'longitude': centerLng,
            'radius': 50.0, // exit threshold = 70 m
          },
        ];

        final inside = pointNorth(centerLat, centerLng, 10);
        evaluator.evaluateProximity(
          latitude: inside.lat,
          longitude: inside.lng,
          accuracy: 8,
          geofences: geofences,
        );

        // 120 m out with ±10 m accuracy: 120 - 10 = 110 > 70. Sustained across
        // two consecutive fixes → real EXIT (#294).
        final far = pointNorth(centerLat, centerLng, 120);
        evaluator.evaluateProximity(
          latitude: far.lat,
          longitude: far.lng,
          accuracy: 10,
          geofences: geofences,
        );
        final transitions = evaluator.evaluateProximity(
          latitude: far.lat,
          longitude: far.lng,
          accuracy: 10,
          geofences: geofences,
        );
        expect(transitions, hasLength(1));
        expect(transitions[0].action, 'EXIT');
      },
    );

    test('single over-confident fix is absorbed, no false EXIT (#294)', () {
      const centerLat = 10.787929;
      const centerLng = 76.684183;
      final geofences = <Map<String, Object?>>[
        {
          'identifier': 'office',
          'latitude': centerLat,
          'longitude': centerLng,
          'radius': 50.0, // exit threshold = 70 m
        },
      ];

      final inside = pointNorth(centerLat, centerLng, 10);
      evaluator.evaluateProximity(
        latitude: inside.lat,
        longitude: inside.lng,
        accuracy: 5,
        geofences: geofences,
      );

      // Over-confident glitch: 200 m out at 1.7 m accuracy (200 - 1.7 = 198 >
      // 70, so it passes the accuracy gate) — but it is a lone fix.
      final glitch = pointNorth(centerLat, centerLng, 200);
      final held = evaluator.evaluateProximity(
        latitude: glitch.lat,
        longitude: glitch.lng,
        accuracy: 1.7,
        geofences: geofences,
      );
      expect(held, isEmpty, reason: 'a lone over-confident fix must not EXIT');

      // Back inside on the very next fix → no EXIT, no re-ENTER.
      final back = pointNorth(centerLat, centerLng, 9);
      final recovered = evaluator.evaluateProximity(
        latitude: back.lat,
        longitude: back.lng,
        accuracy: 5,
        geofences: geofences,
      );
      expect(recovered, isEmpty, reason: 'the glitch must leave no trace');
    });

    test('alternating out/in glitches never confirm an EXIT (#294)', () {
      const centerLat = 10.787929;
      const centerLng = 76.684183;
      final geofences = <Map<String, Object?>>[
        {
          'identifier': 'office',
          'latitude': centerLat,
          'longitude': centerLng,
          'radius': 50.0,
        },
      ];

      final inside = pointNorth(centerLat, centerLng, 10);
      evaluator.evaluateProximity(
        latitude: inside.lat,
        longitude: inside.lng,
        accuracy: 5,
        geofences: geofences,
      );

      var exits = 0;
      for (final d in <double>[200, 10, 220, 12, 210]) {
        final p = pointNorth(centerLat, centerLng, d);
        final ts = evaluator.evaluateProximity(
          latitude: p.lat,
          longitude: p.lng,
          accuracy: 1.7,
          geofences: geofences,
        );
        exits += ts.where((t) => t.action == 'EXIT').length;
      }
      expect(
        exits,
        0,
        reason: 'alternating glitches must never confirm an EXIT',
      );
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

    // ── geofenceExitAccuracyMax regimes (#276) ────────────────────────────
    //
    // The native GeofenceManager clamps the raw fix accuracy before it reaches
    // the evaluator. These tests exercise the evaluator with the exact clamp
    // (`effectiveExitAccuracy`) the native layer applies, for a 50 m fence
    // (exit threshold 70 m): ENTER inside, then a *stationary* ±150 m drift
    // spike reported ~85 m out.
    double effectiveExitAccuracy(double accuracy, int exitAccuracyMax) {
      if (exitAccuracyMax < 0) return accuracy;
      if (exitAccuracyMax == 0) return 0;
      return accuracy < exitAccuracyMax ? accuracy : exitAccuracyMax.toDouble();
    }

    bool driftExitsUnder(int exitAccuracyMax, {required GeofenceEvaluator ev}) {
      const centerLat = 37.4219983;
      const centerLng = -122.084;
      final geofences = <Map<String, Object?>>[
        {
          'identifier': 'gate',
          'latitude': centerLat,
          'longitude': centerLng,
          'radius': 50.0,
        },
      ];
      final inside = pointNorth(centerLat, centerLng, 10);
      ev.evaluateProximity(
        latitude: inside.lat,
        longitude: inside.lng,
        accuracy: effectiveExitAccuracy(8, exitAccuracyMax),
        geofences: geofences,
      );
      // Feed the drift spike twice: a config under which the spike is
      // "confidently outside" confirms the EXIT on the second fix (#294); a
      // config that absorbs it produces no EXIT on either.
      final drift = pointNorth(centerLat, centerLng, 85);
      var sawExit = false;
      for (var i = 0; i < 2; i++) {
        final t = ev.evaluateProximity(
          latitude: drift.lat,
          longitude: drift.lng,
          accuracy: effectiveExitAccuracy(150, exitAccuracyMax),
          geofences: geofences,
        );
        if (t.any((e) => e.action == 'EXIT')) sawExit = true;
      }
      return sawExit;
    }

    test('geofenceExitAccuracyMax = -1 (full gating) absorbs drift (#276)', () {
      expect(driftExitsUnder(-1, ev: evaluator), isFalse);
    });

    test('geofenceExitAccuracyMax = 0 (disabled) lets drift EXIT (#276)', () {
      expect(driftExitsUnder(0, ev: evaluator), isTrue);
    });

    test('geofenceExitAccuracyMax = 20 (clamp) absorbs drift (#276)', () {
      expect(driftExitsUnder(20, ev: evaluator), isFalse);
    });

    test(
      'geofenceExitAccuracyMax = 20 still allows a genuine departure (#276)',
      () {
        const centerLat = 37.4219983;
        const centerLng = -122.084;
        final geofences = <Map<String, Object?>>[
          {
            'identifier': 'gate',
            'latitude': centerLat,
            'longitude': centerLng,
            'radius': 50.0,
          },
        ];
        final inside = pointNorth(centerLat, centerLng, 10);
        evaluator.evaluateProximity(
          latitude: inside.lat,
          longitude: inside.lng,
          accuracy: effectiveExitAccuracy(8, 20),
          geofences: geofences,
        );
        // 120 m out, ±10 m: clamp keeps 10 → 120 - 10 = 110 > 70. Sustained
        // across two fixes → EXIT (#294).
        final far = pointNorth(centerLat, centerLng, 120);
        evaluator.evaluateProximity(
          latitude: far.lat,
          longitude: far.lng,
          accuracy: effectiveExitAccuracy(10, 20),
          geofences: geofences,
        );
        final t = evaluator.evaluateProximity(
          latitude: far.lat,
          longitude: far.lng,
          accuracy: effectiveExitAccuracy(10, 20),
          geofences: geofences,
        );
        expect(t.where((e) => e.action == 'EXIT'), hasLength(1));
      },
    );
  });
}
