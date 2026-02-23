import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet/tracelet.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

/// Mock platform for testing one-shot location and foreground service features.
class MockTraceletPlatform extends TraceletPlatform {
  /// Tracks all method calls for assertion.
  final List<({String method, Object? args})> calls = [];

  /// The next result to return from [getCurrentPosition].
  Map<String, Object?> currentPositionResult = _defaultLocation();

  /// The next result to return from [getLastKnownLocation].
  Map<String, Object?> lastKnownResult = {};

  /// Whether [getCurrentPosition] should fail.
  bool failCurrentPosition = false;

  @override
  Future<Map<String, Object?>> ready(Map<String, Object?> config) async {
    calls.add((method: 'ready', args: config));
    return {'enabled': false, 'trackingMode': 0};
  }

  @override
  Future<Map<String, Object?>> getCurrentPosition(
    Map<String, Object?> options,
  ) async {
    calls.add((method: 'getCurrentPosition', args: options));
    if (failCurrentPosition) {
      throw PlatformException(
        code: 'LOCATION_UNAVAILABLE',
        message: 'Failed',
      );
    }
    return Map<String, Object?>.from(currentPositionResult);
  }

  @override
  Future<Map<String, Object?>> getLastKnownLocation([
    Map<String, Object?>? options,
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
    test('passes no options when called with defaults', () async {
      final location = await Tracelet.getCurrentPosition();

      expect(location.uuid, 'test-uuid-001');
      expect(location.coords.latitude, 37.7749);
      expect(mock.calls.length, 1);
      final args = mock.calls.first.args as Map<String, Object?>;
      expect(args, isEmpty); // No overrides → empty options
    });

    test('forwards desiredAccuracy as index', () async {
      await Tracelet.getCurrentPosition(
        desiredAccuracy: DesiredAccuracy.medium,
      );

      final args = mock.calls.first.args as Map<String, Object?>;
      expect(args['desiredAccuracy'], DesiredAccuracy.medium.index);
    });

    test('forwards timeout', () async {
      await Tracelet.getCurrentPosition(timeout: 15);

      final args = mock.calls.first.args as Map<String, Object?>;
      expect(args['timeout'], 15);
    });

    test('forwards maximumAge', () async {
      await Tracelet.getCurrentPosition(maximumAge: 5000);

      final args = mock.calls.first.args as Map<String, Object?>;
      expect(args['maximumAge'], 5000);
    });

    test('forwards persist: false', () async {
      await Tracelet.getCurrentPosition(persist: false);

      final args = mock.calls.first.args as Map<String, Object?>;
      expect(args['persist'], false);
    });

    test('forwards persist: true explicitly', () async {
      await Tracelet.getCurrentPosition(persist: true);

      final args = mock.calls.first.args as Map<String, Object?>;
      expect(args['persist'], true);
    });

    test('forwards samples', () async {
      await Tracelet.getCurrentPosition(samples: 3);

      final args = mock.calls.first.args as Map<String, Object?>;
      expect(args['samples'], 3);
    });

    test('forwards extras', () async {
      await Tracelet.getCurrentPosition(
        extras: {'route': 'delivery-42', 'driver': 'A1'},
      );

      final args = mock.calls.first.args as Map<String, Object?>;
      final extras = args['extras'] as Map<String, Object?>;
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

      final args = mock.calls.first.args as Map<String, Object?>;
      expect(args['desiredAccuracy'], DesiredAccuracy.high.index);
      expect(args['timeout'], 20);
      expect(args['maximumAge'], 10000);
      expect(args['persist'], false);
      expect(args['samples'], 5);
      expect(args['extras'], {'key': 'value'});
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

      expect(
        () => Tracelet.getCurrentPosition(),
        throwsA(isA<PlatformException>()),
      );
    });

    test('omits null parameters from options map', () async {
      await Tracelet.getCurrentPosition(
        desiredAccuracy: null,
        timeout: null,
        maximumAge: null,
        persist: null,
        samples: null,
        extras: null,
      );

      final args = mock.calls.first.args as Map<String, Object?>;
      expect(args.containsKey('desiredAccuracy'), false);
      expect(args.containsKey('timeout'), false);
      expect(args.containsKey('maximumAge'), false);
      expect(args.containsKey('persist'), false);
      expect(args.containsKey('samples'), false);
      expect(args.containsKey('extras'), false);
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

      final args = mock.calls.first.args as Map<String, Object?>;
      expect(args['persist'], false);
    });

    test('forwards persist: true when specified', () async {
      mock.lastKnownResult = {
        'uuid': 'x',
        'timestamp': '2025-01-01T00:00:00Z',
        'coords': {'latitude': 0.0, 'longitude': 0.0},
      };

      await Tracelet.getLastKnownLocation(persist: true);

      final args = mock.calls.first.args as Map<String, Object?>;
      expect(args['persist'], true);
    });

    test('forwards extras', () async {
      mock.lastKnownResult = {
        'uuid': 'x',
        'timestamp': '2025-01-01T00:00:00Z',
        'coords': {'latitude': 0.0, 'longitude': 0.0},
      };

      await Tracelet.getLastKnownLocation(
        extras: {'source': 'cache'},
      );

      final args = mock.calls.first.args as Map<String, Object?>;
      expect(args['extras'], {'source': 'cache'});
    });

    test('does not include extras key when extras is null', () async {
      mock.lastKnownResult = {};

      await Tracelet.getLastKnownLocation();

      final args = mock.calls.first.args as Map<String, Object?>;
      expect(args.containsKey('extras'), false);
    });
  });

  // ==========================================================================
  // ForegroundServiceConfig.enabled
  // ==========================================================================
  group('ForegroundServiceConfig.enabled', () {
    test('defaults to true in Config', () {
      const config = Config();
      expect(config.app.foregroundService.enabled, true);
    });

    test('can be set to false', () {
      const config = Config(
        app: AppConfig(
          foregroundService: ForegroundServiceConfig(enabled: false),
        ),
      );
      expect(config.app.foregroundService.enabled, false);
    });

    test('serializes to map and back', () {
      const config = Config(
        app: AppConfig(
          foregroundService: ForegroundServiceConfig(enabled: false),
        ),
      );

      final map = config.toMap();
      final restored = Config.fromMap(map);
      expect(restored.app.foregroundService.enabled, false);
    });

    test('enabled: true round-trip', () {
      const config = Config(
        app: AppConfig(
          foregroundService: ForegroundServiceConfig(enabled: true),
        ),
      );

      final map = config.toMap();
      final restored = Config.fromMap(map);
      expect(restored.app.foregroundService.enabled, true);
    });

    test('Config ready passes foreground enabled flag to platform', () async {
      const config = Config(
        app: AppConfig(
          foregroundService: ForegroundServiceConfig(enabled: false),
        ),
      );

      await Tracelet.ready(config);

      final args = mock.calls.first.args as Map<String, Object?>;
      final appMap = args['app'] as Map<String, Object?>;
      final fgMap = appMap['foregroundService'] as Map<String, Object?>;
      expect(fgMap['enabled'], false);
    });
  });

  // ==========================================================================
  // One-shot without tracking (enterprise use case)
  // ==========================================================================
  group('One-shot without tracking (enterprise pattern)', () {
    test('getCurrentPosition without starting tracking', () async {
      // Enterprise pattern: ready → getCurrentPosition → done
      // No start() call, no foreground service
      await Tracelet.ready(const Config(
        app: AppConfig(
          foregroundService: ForegroundServiceConfig(enabled: false),
        ),
      ));

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
