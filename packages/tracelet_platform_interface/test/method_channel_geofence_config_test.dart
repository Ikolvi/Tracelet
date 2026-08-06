import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

import 'mock_tl_config.dart';

/// Regression tests for #305 — the method-channel transport silently dropped
/// three of the five geofence keys.
///
/// `_geofenceToMap` emitted only `geofenceInitialTriggerEntry` and
/// `geofenceProximityRadius`, discarding:
///
/// - `geofenceModeHighAccuracy` — so the cross-platform flag never reached
///   native on this path, and no OR with the deprecated Android-only flag was
///   performed at all;
/// - `geofenceInitialTrigger`;
/// - `geofenceExitAccuracyMax` — the #276 EXIT-gating tunable.
///
/// These assert the map that actually crosses the channel, which is the code
/// that was broken. A `Config.toMap()/fromMap()` round-trip would NOT catch
/// this: the Dart model always serialized all five keys, so a model-level test
/// passes on a build where the transport drops them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannelTracelet channel;
  final log = <MethodCall>[];

  setUp(() {
    channel = MethodChannelTracelet();
    log.clear();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(TraceletPlatform.methodChannelName),
          (MethodCall call) async {
            log.add(call);
            return <String, Object?>{};
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(TraceletPlatform.methodChannelName),
          null,
        );
  });

  /// Sends [config] over the channel and returns the `geofence` sub-map that
  /// actually went across.
  Future<Map<Object?, Object?>> geofenceMapFor(TlConfig config) async {
    await channel.setConfig(config);
    final args = log.last.arguments as Map<Object?, Object?>;
    return args['geofence']! as Map<Object?, Object?>;
  }

  /// Returns the `android` sub-map that actually went across.
  Future<Map<Object?, Object?>> androidMapFor(TlConfig config) async {
    await channel.setConfig(config);
    final args = log.last.arguments as Map<Object?, Object?>;
    return args['android']! as Map<Object?, Object?>;
  }

  TlConfig configWith({
    bool geofenceHighAccuracy = false,
    bool androidHighAccuracy = false,
    bool initialTrigger = true,
    int exitAccuracyMax = -1,
  }) => createMockTlConfig(
    geofenceHighAccuracy: geofenceHighAccuracy,
    androidHighAccuracy: androidHighAccuracy,
    initialTrigger: initialTrigger,
    exitAccuracyMax: exitAccuracyMax,
  );

  group('#305 method-channel geofence config', () {
    test('carries all five geofence keys', () async {
      final map = await geofenceMapFor(
        configWith(
          geofenceHighAccuracy: true,
          initialTrigger: false,
          exitAccuracyMax: 35,
        ),
      );

      // The two that always worked.
      expect(map.containsKey('geofenceInitialTriggerEntry'), isTrue);
      expect(map.containsKey('geofenceProximityRadius'), isTrue);
      // The three that were silently dropped before #305.
      expect(map['geofenceModeHighAccuracy'], isTrue);
      expect(map['geofenceInitialTrigger'], isFalse);
      expect(map['geofenceExitAccuracyMax'], 35);
    });

    test('geofenceExitAccuracyMax survives every #276 policy value', () async {
      for (final policy in <int>[-1, 0, 30]) {
        final map = await geofenceMapFor(configWith(exitAccuracyMax: policy));
        expect(
          map['geofenceExitAccuracyMax'],
          policy,
          reason: 'exitAccuracyMax=$policy must reach native verbatim',
        );
      }
    });

    test('the cross-platform flag alone enables high accuracy', () async {
      final map = await geofenceMapFor(configWith(geofenceHighAccuracy: true));
      expect(
        map['geofenceModeHighAccuracy'],
        isTrue,
        reason: 'GeofenceConfig flag must not require the deprecated one',
      );
    });

    test('the deprecated Android-only flag alone still enables it', () async {
      final map = await geofenceMapFor(configWith(androidHighAccuracy: true));
      expect(
        map['geofenceModeHighAccuracy'],
        isTrue,
        reason: 'backward compatibility: the old flag must keep working',
      );
    });

    test('neither flag leaves high accuracy off', () async {
      final map = await geofenceMapFor(configWith());
      expect(map['geofenceModeHighAccuracy'], isFalse);
    });

    test(
      'the android block carries the same OR as the geofence block',
      () async {
        // Native reads this key from BOTH blocks; they must agree, or behavior
        // depends on which one the platform happens to consult.
        for (final pair in <List<bool>>[
          <bool>[true, false],
          <bool>[false, true],
          <bool>[true, true],
          <bool>[false, false],
        ]) {
          final cfg = configWith(
            geofenceHighAccuracy: pair[0],
            androidHighAccuracy: pair[1],
          );
          final geofence = await geofenceMapFor(cfg);
          final android = await androidMapFor(cfg);
          expect(
            android['geofenceModeHighAccuracy'],
            geofence['geofenceModeHighAccuracy'],
            reason:
                'blocks disagree for geofence=${pair[0]} android=${pair[1]}',
          );
          expect(geofence['geofenceModeHighAccuracy'], pair[0] || pair[1]);
        }
      },
    );
  });
}
