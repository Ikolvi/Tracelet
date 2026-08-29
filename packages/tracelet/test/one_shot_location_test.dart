import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet/tracelet.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

import 'permission_degradation_test.dart' show EmptyEventStreamsMixin;

/// Mock platform for testing one-shot location and foreground service features.
class MockTraceletPlatform extends TraceletPlatform
    with EmptyEventStreamsMixin {
  /// Tracks all method calls for assertion.
  final List<({String method, Object? args})> calls = [];

  /// The next result to return from [getCurrentPosition].
  Map<String, Object?> currentPositionResult = _defaultLocation();

  /// The next result to return from [getLastKnownLocation].
  Map<String, Object?> lastKnownResult = {};

  /// Whether [getCurrentPosition] should fail.
  bool failCurrentPosition = false;

  @override
  Future<Map<String, Object?>> ready(TlConfig config) async {
    calls.add((method: 'ready', args: config));
    return {'enabled': false, 'trackingMode': 0};
  }

  @override
  Future<Map<String, Object?>> getCurrentPosition(
    TlCurrentPositionOptions options,
  ) async {
    calls.add((method: 'getCurrentPosition', args: options));
    if (failCurrentPosition) {
      throw PlatformException(code: 'LOCATION_UNAVAILABLE', message: 'Failed');
    }
    return Map<String, Object?>.from(currentPositionResult);
  }

  @override
  Future<bool> cancelCurrentPosition(String requestId) async {
    calls.add((method: 'cancelCurrentPosition', args: requestId));
    return true;
  }

  @override
  Future<Map<String, Object?>> getLastKnownLocation([
    TlCurrentPositionOptions? options,
  ]) async {
    calls.add((method: 'getLastKnownLocation', args: options));
    return Map<String, Object?>.from(lastKnownResult);
  }

  static Map<String, Object?> _defaultLocation() => {
    'uuid': 'test-uuid-001',
    'timestamp': '2025-01-15T10:30:00.000Z',
    'isMoving': false,
    'odometer': 0.0,
    'event': 'getCurrentPosition',
    'coords': {
      'latitude': 37.7749,
      'longitude': -122.4194,
      'altitude': 0.0,
      'speed': 0.0,
      'heading': 0.0,
      'accuracy': 5.0,
    },
    'activity': {'type': 'unknown', 'confidence': -1},
    'battery': {'level': 0.85, 'isCharging': false},
  };
}

void main() {
  late MockTraceletPlatform mock;

  setUp(() {
    mock = MockTraceletPlatform();
    TraceletPlatform.instance = mock;
  });

  tearDown(() {
    mock.calls.clear();
  });

  // ==========================================================================
  // getCurrentPosition — parameter forwarding
  // ==========================================================================
  group('getCurrentPosition', () {
    test('uses typed defaults when called with no overrides', () async {
      final location = await Tracelet.getCurrentPosition();

      expect(location.uuid, 'test-uuid-001');
      expect(location.coords.latitude, 37.7749);
      expect(mock.calls.length, 1);
      // Phase 2 (#206): an explicit one-shot defaults to high accuracy.
      final o = mock.calls.first.args! as TlCurrentPositionOptions;
      expect(o.desiredAccuracy, TlDesiredAccuracy.high);
      expect(o.timeout, 30);
      expect(o.maximumAge, 0);
      expect(o.persist, true);
      expect(o.samples, 1);
      expect(o.accuracyTarget, isNull);
      expect(o.requestId, isNull);
      expect(o.extras, isNull);
    });

    test('forwards desiredAccuracy', () async {
      await Tracelet.getCurrentPosition(
        desiredAccuracy: DesiredAccuracy.medium,
      );

      final o = mock.calls.first.args! as TlCurrentPositionOptions;
      expect(o.desiredAccuracy, TlDesiredAccuracy.medium);
    });

    test('forwards timeout', () async {
      await Tracelet.getCurrentPosition(timeout: 15);

      final o = mock.calls.first.args! as TlCurrentPositionOptions;
      expect(o.timeout, 15);
    });

    test('forwards maximumAge', () async {
      await Tracelet.getCurrentPosition(maximumAge: 5000);

      final o = mock.calls.first.args! as TlCurrentPositionOptions;
      expect(o.maximumAge, 5000);
    });

    test('forwards persist: false', () async {
      await Tracelet.getCurrentPosition(persist: false);

      final o = mock.calls.first.args! as TlCurrentPositionOptions;
      expect(o.persist, false);
    });

    test('forwards persist: true explicitly', () async {
      await Tracelet.getCurrentPosition(persist: true);

      final o = mock.calls.first.args! as TlCurrentPositionOptions;
      expect(o.persist, true);
    });

    test('forwards samples', () async {
      await Tracelet.getCurrentPosition(samples: 3);

      final o = mock.calls.first.args! as TlCurrentPositionOptions;
      expect(o.samples, 3);
    });

    test('forwards accuracy target and request identifier', () async {
      await Tracelet.getCurrentPosition(
        accuracyTarget: 100,
        requestId: 'display-7',
      );

      final o = mock.calls.first.args! as TlCurrentPositionOptions;
      expect(o.accuracyTarget, 100);
      expect(o.requestId, 'display-7');
    });

    test('forwards cancellation by request identifier', () async {
      expect(await Tracelet.cancelCurrentPosition('display-7'), isTrue);
      expect(mock.calls.single.method, 'cancelCurrentPosition');
      expect(mock.calls.single.args, 'display-7');
    });

    test('forwards extras', () async {
      await Tracelet.getCurrentPosition(
        extras: {'route': 'delivery-42', 'driver': 'A1'},
      );

      final o = mock.calls.first.args! as TlCurrentPositionOptions;
      final extras = o.extras!;
      expect(extras['route'], 'delivery-42');
      expect(extras['driver'], 'A1');
    });

    test('forwards all options together', () async {
      await Tracelet.getCurrentPosition(
        desiredAccuracy: DesiredAccuracy.high,
        timeout: 20,
        maximumAge: 10000,
        persist: false,
        samples: 5,
        extras: {'key': 'value'},
      );

      final o = mock.calls.first.args! as TlCurrentPositionOptions;
      expect(o.desiredAccuracy, TlDesiredAccuracy.high);
      expect(o.timeout, 20);
      expect(o.maximumAge, 10000);
      expect(o.persist, false);
      expect(o.samples, 5);
      expect(o.extras, {'key': 'value'});
    });

    test('returns Location on success', () async {
      final loc = await Tracelet.getCurrentPosition();

      expect(loc, isA<Location>());
      expect(loc.uuid, 'test-uuid-001');
      expect(loc.coords.latitude, closeTo(37.7749, 0.001));
      expect(loc.coords.longitude, closeTo(-122.4194, 0.001));
      expect(loc.event, 'getCurrentPosition');
    });

    test('propagates PlatformException on failure', () async {
      mock.failCurrentPosition = true;

      expect(Tracelet.getCurrentPosition, throwsA(isA<PlatformException>()));
    });

    test('applies typed defaults when params omitted', () async {
      await Tracelet.getCurrentPosition();

      final o = mock.calls.first.args! as TlCurrentPositionOptions;
      expect(o.desiredAccuracy, TlDesiredAccuracy.high);
      expect(o.timeout, 30);
      expect(o.maximumAge, 0);
      expect(o.persist, true);
      expect(o.samples, 1);
      expect(o.extras, isNull);
    });
  });

  // ==========================================================================
  // getLastKnownLocation
  // ==========================================================================
  group('getLastKnownLocation', () {
    test('returns null when no cached location exists', () async {
      mock.lastKnownResult = {}; // empty → no cached location
      final loc = await Tracelet.getLastKnownLocation();

      expect(loc, isNull);
      expect(mock.calls.length, 1);
      expect(mock.calls.first.method, 'getLastKnownLocation');
    });

    test('returns Location when cached location exists', () async {
      mock.lastKnownResult = {
        'uuid': 'cached-uuid',
        'timestamp': '2025-01-10T08:00:00.000Z',
        'isMoving': false,
        'odometer': 500.0,
        'event': 'getLastKnownLocation',
        'coords': {'latitude': 48.8566, 'longitude': 2.3522},
      };

      final loc = await Tracelet.getLastKnownLocation();

      expect(loc, isNotNull);
      expect(loc!.uuid, 'cached-uuid');
      expect(loc.coords.latitude, closeTo(48.8566, 0.001));
      expect(loc.coords.longitude, closeTo(2.3522, 0.001));
    });

    test('forwards persist: false by default', () async {
      mock.lastKnownResult = {
        'uuid': 'x',
        'timestamp': '2025-01-01T00:00:00Z',
        'coords': {'latitude': 0.0, 'longitude': 0.0},
      };

      await Tracelet.getLastKnownLocation();

      final o = mock.calls.first.args! as TlCurrentPositionOptions;
      expect(o.persist, false);
    });

    test('forwards persist: true when specified', () async {
      mock.lastKnownResult = {
        'uuid': 'x',
        'timestamp': '2025-01-01T00:00:00Z',
        'coords': {'latitude': 0.0, 'longitude': 0.0},
      };

      await Tracelet.getLastKnownLocation(persist: true);

      final o = mock.calls.first.args! as TlCurrentPositionOptions;
      expect(o.persist, true);
    });

    test('forwards extras', () async {
      mock.lastKnownResult = {
        'uuid': 'x',
        'timestamp': '2025-01-01T00:00:00Z',
        'coords': {'latitude': 0.0, 'longitude': 0.0},
      };

      await Tracelet.getLastKnownLocation(extras: {'source': 'cache'});

      final o = mock.calls.first.args! as TlCurrentPositionOptions;
      expect(o.extras, {'source': 'cache'});
    });

    test('extras is null when not provided', () async {
      mock.lastKnownResult = {};

      await Tracelet.getLastKnownLocation();

      final o = mock.calls.first.args! as TlCurrentPositionOptions;
      expect(o.extras, isNull);
    });
  });

  // ==========================================================================
  // ForegroundServiceConfig.enabled
  // ==========================================================================
  group('ForegroundServiceConfig.enabled', () {
    test('defaults to true in Config', () {
      const config = Config();
      expect(config.android.foregroundService.enabled, true);
    });

    test('can be set to false', () {
      const config = Config(
        android: AndroidConfig(
          foregroundService: ForegroundServiceConfig(enabled: false),
        ),
      );
      expect(config.android.foregroundService.enabled, false);
    });

    test('serializes to map and back', () {
      const config = Config(
        android: AndroidConfig(
          foregroundService: ForegroundServiceConfig(enabled: false),
        ),
      );

      final map = config.toMap();
      final restored = Config.fromMap(map);
      expect(restored.android.foregroundService.enabled, false);
    });

    test('enabled: true round-trip', () {
      const config = Config();

      final map = config.toMap();
      final restored = Config.fromMap(map);
      expect(restored.android.foregroundService.enabled, true);
    });

    test('Config ready passes foreground enabled flag to platform', () async {
      const config = Config(
        android: AndroidConfig(
          foregroundService: ForegroundServiceConfig(enabled: false),
        ),
      );

      await Tracelet.ready(config);

      final configArg = mock.calls.first.args! as TlConfig;
      // ready() sends a fully resolved baseline, so the section and the flag
      // are both present rather than omitted as unset (#321).
      expect(configArg.android.foregroundService!.enabled, false);
    });
  });

  // ==========================================================================
  // One-shot without tracking (enterprise use case)
  // ==========================================================================
  group('One-shot without tracking (enterprise pattern)', () {
    test('getCurrentPosition without starting tracking', () async {
      // Enterprise pattern: ready → getCurrentPosition → done
      // No start() call, no foreground service
      await Tracelet.ready(
        const Config(
          android: AndroidConfig(
            foregroundService: ForegroundServiceConfig(enabled: false),
          ),
        ),
      );

      final location = await Tracelet.getCurrentPosition(
        desiredAccuracy: DesiredAccuracy.high,
        persist: false,
        timeout: 10,
      );

      expect(location, isA<Location>());
      expect(mock.calls.length, 2); // ready + getCurrentPosition
      expect(mock.calls[0].method, 'ready');
      expect(mock.calls[1].method, 'getCurrentPosition');
    });

    test('getLastKnownLocation works without ready()', () async {
      mock.lastKnownResult = {
        'uuid': 'fast-uuid',
        'timestamp': '2025-01-01T00:00:00Z',
        'coords': {'latitude': 40.7128, 'longitude': -74.0060},
      };

      final loc = await Tracelet.getLastKnownLocation();

      expect(loc, isNotNull);
      expect(loc!.coords.latitude, closeTo(40.7128, 0.001));
      expect(mock.calls.length, 1);
    });
  });
}
