import 'dart:convert' show jsonDecode;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet/tracelet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const syncBodyChannel = MethodChannel('com.tracelet/sync_body');
  const methodsChannel = MethodChannel('com.tracelet/methods');

  // Track calls made to com.tracelet/methods (for setSyncBodyResponse tests).
  final methodsLog = <MethodCall>[];

  setUp(() {
    methodsLog.clear();

    // Reset the static state between tests. Because _syncBodyChannelReady
    // is a private static field on Tracelet, we clear the builder which
    // effectively makes the handler return null. We can't reset
    // _syncBodyChannelReady directly, so the first call to
    // setSyncBodyBuilder in the test suite sets up the handler once and
    // subsequent tests reuse it (which is fine — the handler reads the
    // current _syncBodyBuilder dynamically).
    Tracelet.setSyncBodyBuilder(null);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodsChannel, (MethodCall call) async {
          methodsLog.add(call);
          return null;
        });
  });

  tearDown(() {
    Tracelet.setSyncBodyBuilder(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodsChannel, null);
  });

  // ==========================================================================
  // setSyncBodyBuilder — foreground MethodChannel handler
  // ==========================================================================
  group('trip summaries in the custom builder (#401)', () {
    test('trips from native reach context.trips', () async {
      Tracelet.setSyncBodyBuilder((SyncBodyContext context) async {
        return <String, Object?>{
          'points': context.locations,
          'trips': context.trips,
        };
      });

      final response = await _invokeSyncBodyChannelRaw(
        syncBodyChannel,
        'buildSyncBody',
        <String, Object?>{
          'locations': <Object?>[
            <String, Object?>{'uuid': 'loc-1'},
          ],
          'telematics': <Object?>[],
          'trips': <Object?>[
            <String, Object?>{
              'trip_id': '9f2c0f1e-4c31-4b2a-9a77-1d0f3b5e7c88',
              'distance': 18420.0,
              'start_location': <String, Object?>{
                'latitude': 24.81,
                'longitude': 67.05,
              },
              'stop_location': null,
            },
          ],
        },
      );

      final decoded = jsonDecode(response!) as Map<String, Object?>;
      final trips = decoded['trips']! as List;
      expect(trips, hasLength(1));
      final trip = trips.single as Map<String, Object?>;
      expect(trip['trip_id'], '9f2c0f1e-4c31-4b2a-9a77-1d0f3b5e7c88');
      expect((trip['start_location']! as Map)['latitude'], 24.81);
      expect(trip['stop_location'], isNull);
    });

    test('a native without trip summaries yields empty trips', () async {
      Tracelet.setSyncBodyBuilder((SyncBodyContext context) async {
        return <String, Object?>{'tripCount': context.trips.length};
      });

      final response = await _invokeSyncBodyChannelRaw(
        syncBodyChannel,
        'buildSyncBody',
        <String, Object?>{'locations': <Object?>[], 'telematics': <Object?>[]},
      );

      expect(jsonDecode(response!), <String, Object?>{'tripCount': 0});
    });

    test('fromMap and toMap carry trips', () {
      final context = SyncBodyContext.fromMap(const <String, Object?>{
        'locations': <Object?>[],
        'trips': <Object?>[
          <String, Object?>{'trip_id': 'a'},
        ],
      });
      expect(context.trips.single['trip_id'], 'a');
      expect(context.toMap()['trips']! as List, hasLength(1));
    });
  });

  group('setSyncBodyBuilder (foreground MethodChannel)', () {
    test('handler invokes builder and returns JSON-encoded body', () async {
      Tracelet.setSyncBodyBuilder((SyncBodyContext context) async {
        return <String, Object?>{
          'deviceId': 'dev-1',
          'points': context.locations,
        };
      });

      // Simulate native calling buildSyncBody with a list of locations
      final locations = <Object?>[
        <String, Object?>{'lat': 51.5, 'lng': -0.1, 'uuid': 'loc-1'},
        <String, Object?>{'lat': 51.6, 'lng': -0.2, 'uuid': 'loc-2'},
      ];

      final response = await _invokeSyncBodyChannel(syncBodyChannel, locations);
      expect(response, isNotNull);
      final decoded = jsonDecode(response!) as Map<String, Object?>;
      expect(decoded['deviceId'], 'dev-1');
      expect(decoded['points'], isList);
      expect((decoded['points']! as List).length, 2);
    });

    test('handler returns JSON with builder output', () async {
      Tracelet.setSyncBodyBuilder((SyncBodyContext context) async {
        return <String, Object?>{
          'custom': true,
          'count': context.locations.length,
        };
      });

      final response = await _invokeSyncBodyChannel(syncBodyChannel, <Object?>[
        <String, Object?>{'lat': 1.0},
        <String, Object?>{'lat': 2.0},
        <String, Object?>{'lat': 3.0},
      ]);

      expect(response, isNotNull);
      final decoded = jsonDecode(response!) as Map<String, Object?>;
      expect(decoded['custom'], true);
      expect(decoded['count'], 3);
    });

    test('handler returns null when builder is null', () async {
      Tracelet.setSyncBodyBuilder(null);

      final response = await _invokeSyncBodyChannel(syncBodyChannel, <Object?>[
        <String, Object?>{'lat': 1.0},
      ]);

      expect(response, '__tracelet_no_sync_body_builder__');
    });

    test('handler returns null for non-list arguments', () async {
      Tracelet.setSyncBodyBuilder((SyncBodyContext context) async {
        return <String, Object?>{'data': true};
      });

      final response = await _invokeSyncBodyChannelRaw(
        syncBodyChannel,
        'buildSyncBody',
        'not-a-list',
      );

      expect(response, isNull);
    });

    test('handler returns null for unrecognized methods', () async {
      Tracelet.setSyncBodyBuilder((SyncBodyContext context) async {
        return <String, Object?>{'data': true};
      });

      final response = await _invokeSyncBodyChannelRaw(
        syncBodyChannel,
        'unknownMethod',
        <Object?>[],
      );

      expect(response, isNull);
    });

    test('handler filters non-Map entries from locations list', () async {
      late List<Map<String, Object?>> receivedLocations;
      Tracelet.setSyncBodyBuilder((SyncBodyContext context) async {
        receivedLocations = context.locations;
        return <String, Object?>{'count': context.locations.length};
      });

      final response = await _invokeSyncBodyChannel(syncBodyChannel, <Object?>[
        <String, Object?>{'lat': 1.0},
        'not-a-map',
        42,
        <String, Object?>{'lat': 2.0},
      ]);

      expect(response, isNotNull);
      final decoded = jsonDecode(response!) as Map<String, Object?>;
      expect(decoded['count'], 2);
      expect(receivedLocations, hasLength(2));
    });

    test('replacing builder updates behavior dynamically', () async {
      Tracelet.setSyncBodyBuilder((SyncBodyContext context) async {
        return <String, Object?>{'version': 1};
      });

      var response = await _invokeSyncBodyChannel(syncBodyChannel, <Object?>[
        <String, Object?>{'lat': 1.0},
      ]);
      var decoded = jsonDecode(response!) as Map<String, Object?>;
      expect(decoded['version'], 1);

      // Replace builder
      Tracelet.setSyncBodyBuilder((SyncBodyContext context) async {
        return <String, Object?>{'version': 2};
      });

      response = await _invokeSyncBodyChannel(syncBodyChannel, <Object?>[
        <String, Object?>{'lat': 1.0},
      ]);
      decoded = jsonDecode(response!) as Map<String, Object?>;
      expect(decoded['version'], 2);
    });
  });

  // ==========================================================================
  // setSyncBodyResponse — headless response
  // ==========================================================================
  group('setSyncBodyResponse (headless)', () {
    test('sends JSON-encoded body via methods channel', () async {
      await Tracelet.setSyncBodyResponse(<String, Object?>{
        'deviceId': 'dev-1',
        'locations': [
          {'lat': 51.5},
        ],
      });

      expect(methodsLog, hasLength(1));
      expect(methodsLog.first.method, 'setSyncBodyResponse');

      final sentJson = methodsLog.first.arguments as String;
      final decoded = jsonDecode(sentJson) as Map<String, Object?>;
      expect(decoded['deviceId'], 'dev-1');
      expect(decoded['locations'], isList);
    });

    test('sends correct JSON for empty body', () async {
      await Tracelet.setSyncBodyResponse(<String, Object?>{});

      expect(methodsLog, hasLength(1));
      final sentJson = methodsLog.first.arguments as String;
      expect(sentJson, '{}');
    });
  });

  // ==========================================================================
  // Channel teardown — clearing builder removes handler
  // ==========================================================================
  group('channel teardown', () {
    test('clearing builder with null tears down handler', () async {
      // Set a builder to register the handler
      Tracelet.setSyncBodyBuilder((SyncBodyContext context) async {
        return <String, Object?>{'active': true};
      });

      // Verify it works
      var response = await _invokeSyncBodyChannel(syncBodyChannel, <Object?>[
        <String, Object?>{'lat': 1.0},
      ]);
      expect(response, isNotNull);

      // Clear the builder
      Tracelet.setSyncBodyBuilder(null);

      // Handler should be torn down — channel call should return null
      response = await _invokeSyncBodyChannel(syncBodyChannel, <Object?>[
        <String, Object?>{'lat': 1.0},
      ]);
      expect(response, '__tracelet_no_sync_body_builder__');

      // Re-registering should work
      Tracelet.setSyncBodyBuilder((SyncBodyContext context) async {
        return <String, Object?>{'reactivated': true};
      });

      response = await _invokeSyncBodyChannel(syncBodyChannel, <Object?>[
        <String, Object?>{'lat': 1.0},
      ]);
      expect(response, isNotNull);
      final decoded = jsonDecode(response!) as Map<String, Object?>;
      expect(decoded['reactivated'], true);
    });
  });

  // ==========================================================================
  // Deep cast — nested maps and lists are properly typed
  // ==========================================================================
  group('deep cast of locations', () {
    test('nested maps are cast to Map<String, Object?>', () async {
      late List<Map<String, Object?>> receivedLocations;
      Tracelet.setSyncBodyBuilder((SyncBodyContext context) async {
        receivedLocations = context.locations;
        return <String, Object?>{'ok': true};
      });

      final response = await _invokeSyncBodyChannel(syncBodyChannel, <Object?>[
        <String, Object?>{
          'lat': 51.5,
          'extras': <String, Object?>{
            'nested': <String, Object?>{'deep': 'value'},
          },
        },
      ]);

      expect(response, isNotNull);
      expect(receivedLocations, hasLength(1));
      final extras = receivedLocations[0]['extras'];
      expect(extras, isA<Map<String, Object?>>());
      final nested = (extras! as Map<String, Object?>)['nested'];
      expect(nested, isA<Map<String, Object?>>());
      expect((nested! as Map<String, Object?>)['deep'], 'value');
    });

    test(
      'lists inside locations are preserved with nested maps cast',
      () async {
        late List<Map<String, Object?>> receivedLocations;
        Tracelet.setSyncBodyBuilder((SyncBodyContext context) async {
          receivedLocations = context.locations;
          return <String, Object?>{'ok': true};
        });

        final response = await _invokeSyncBodyChannel(
          syncBodyChannel,
          <Object?>[
            <String, Object?>{
              'lat': 51.5,
              'tags': <Object?>[
                <String, Object?>{'key': 'a'},
                'plain-string',
              ],
            },
          ],
        );

        expect(response, isNotNull);
        final tags = receivedLocations[0]['tags']! as List;
        expect(tags[0], isA<Map<String, Object?>>());
        expect((tags[0] as Map<String, Object?>)['key'], 'a');
        expect(tags[1], 'plain-string');
      },
    );
    test(
      '#214: map arg exposes locations + telematics to the builder',
      () async {
        late SyncBodyContext received;
        Tracelet.setSyncBodyBuilder((SyncBodyContext context) async {
          received = context;
          return <String, Object?>{'ok': true};
        });

        final response = await _invokeSyncBodyChannelRaw(
          syncBodyChannel,
          'buildSyncBody',
          <String, Object?>{
            'locations': <Object?>[
              <String, Object?>{'lat': 1.0},
            ],
            'telematics': <Object?>[
              <String, Object?>{'event_type': 'harsh_braking', 'severity': 0.8},
            ],
          },
        );

        expect(response, isNotNull);
        expect(received.locations, hasLength(1));
        expect(received.telematics, hasLength(1));
        expect(received.telematics.first['event_type'], 'harsh_braking');
      },
    );

    test('#214: legacy bare-list arg still works (empty telematics)', () async {
      late SyncBodyContext received;
      Tracelet.setSyncBodyBuilder((SyncBodyContext context) async {
        received = context;
        return <String, Object?>{'ok': true};
      });

      final response = await _invokeSyncBodyChannel(syncBodyChannel, <Object?>[
        <String, Object?>{'lat': 1.0},
      ]);

      expect(response, isNotNull);
      expect(received.locations, hasLength(1));
      expect(received.telematics, isEmpty);
    });
  });
}

// =============================================================================
// Helpers
// =============================================================================

/// Simulate native → Dart MethodChannel call for `buildSyncBody`.
Future<String?> _invokeSyncBodyChannel(
  MethodChannel channel,
  List<Object?> locations,
) {
  return _invokeSyncBodyChannelRaw(channel, 'buildSyncBody', locations);
}

/// Simulate native → Dart MethodChannel call with arbitrary method/args.
Future<String?> _invokeSyncBodyChannelRaw(
  MethodChannel channel,
  String method,
  Object? arguments,
) async {
  String? result;

  final encoded = channel.codec.encodeMethodCall(MethodCall(method, arguments));

  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(channel.name, encoded, (ByteData? response) {
        if (response != null) {
          try {
            result = channel.codec.decodeEnvelope(response) as String?;
          } catch (_) {
            result = null;
          }
        }
      });

  // Give async handler time to complete
  await Future<void>.delayed(Duration.zero);

  return result;
}
