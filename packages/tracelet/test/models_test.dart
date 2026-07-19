import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet/tracelet.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart'
    show TlIosActivityType;

void main() {
  // ==========================================================================
  // Config
  // ==========================================================================
  group('Config', () {
    test('has sensible defaults', () {
      const config = Config();
      expect(config.geo.desiredAccuracy, DesiredAccuracy.high);
      expect(config.geo.distanceFilter, 10.0);
      expect(config.geo.stationaryRadius, 25.0);
      expect(config.app.stopOnTerminate, true);
      expect(config.app.startOnBoot, false);
      expect(config.app.heartbeatInterval, 60);
      expect(config.logger.debug, false);
      expect(config.http.autoSync, true);
      expect(config.http.url, isNull);
      expect(config.http.method, HttpMethod.post);
      expect(config.logger.logLevel, LogLevel.info);
      expect(config.motion.stopTimeout, 5);
      expect(config.geofence.geofenceInitialTriggerEntry, true);
      // Periodic mode defaults
      expect(config.geo.periodicLocationInterval, 900);
      expect(config.geo.periodicDesiredAccuracy, DesiredAccuracy.medium);
    });

    test('round-trip serialization preserves all fields', () {
      const config = Config(
        geo: GeoConfig(
          distanceFilter: 50,
          stationaryRadius: 30,
          desiredAccuracy: DesiredAccuracy.medium,
        ),
        app: AppConfig(
          heartbeatInterval: 120,
          stopOnTerminate: false,
          startOnBoot: true,
        ),
        http: HttpConfig(
          url: 'https://example.com/api',
          method: HttpMethod.put,
          autoSync: false,
          batchSync: true,
        ),
        motion: MotionConfig(stopTimeout: 10, isMoving: true),
        geofence: GeofenceConfig(geofenceInitialTriggerEntry: false),
        logger: LoggerConfig(logMaxDays: 7, debug: true),
      );

      final map = config.toMap();
      final restored = Config.fromMap(map);

      expect(restored.geo.distanceFilter, 50.0);
      expect(restored.geo.stationaryRadius, 30.0);
      expect(restored.geo.desiredAccuracy, DesiredAccuracy.medium);
      expect(restored.app.heartbeatInterval, 120);
      expect(restored.app.stopOnTerminate, false);
      expect(restored.app.startOnBoot, true);
      expect(restored.http.url, 'https://example.com/api');
      expect(restored.http.method, HttpMethod.put);
      expect(restored.http.autoSync, false);
      expect(restored.http.batchSync, true);
      expect(restored.motion.stopTimeout, 10);
      expect(restored.motion.isMoving, true);
      expect(restored.geofence.geofenceInitialTriggerEntry, false);
      expect(restored.logger.logLevel, LogLevel.info);
      expect(restored.logger.logMaxDays, 7);
      expect(restored.logger.debug, true);
    });

    test('equality based on all sub-configs', () {
      const a = Config();
      const b = Config();
      const c = Config(geo: GeoConfig(distanceFilter: 20));
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('fromMap handles empty map', () {
      final config = Config.fromMap(const {});
      expect(config.geo.distanceFilter, 10.0);
      expect(config.logger.debug, false);
    });

    test('round-trip preserves periodic config options', () {
      const config = Config(
        geo: GeoConfig(
          periodicLocationInterval: 1800,
          periodicDesiredAccuracy: DesiredAccuracy.high,
        ),
      );

      final map = config.toMap();
      final restored = Config.fromMap(map);

      expect(restored.geo.periodicLocationInterval, 1800);
      expect(restored.geo.periodicDesiredAccuracy, DesiredAccuracy.high);
    });

    test('periodic config defaults are correct in fromMap with empty map', () {
      final config = Config.fromMap(const {});
      expect(config.geo.periodicLocationInterval, 900);
      expect(config.geo.periodicDesiredAccuracy, DesiredAccuracy.medium);
    });

    test('fromMap supports both nested and flat formats', () {
      // Flat format
      final flat = Config.fromMap(const {
        'distanceFilter': 42.0,
        'heartbeatInterval': 90,
      });
      expect(flat.geo.distanceFilter, 42.0);
      expect(flat.app.heartbeatInterval, 90);

      // Nested format
      final nested = Config.fromMap(const {
        'geo': {'distanceFilter': 42.0},
        'app': {'heartbeatInterval': 90},
      });
      expect(nested.geo.distanceFilter, 42.0);
      expect(nested.app.heartbeatInterval, 90);
    });

    test('HttpConfig equality includes all scalar fields', () {
      const a = HttpConfig(url: 'https://a.com', maxBatchSize: 100);
      const b = HttpConfig(url: 'https://a.com', maxBatchSize: 200);
      expect(a, isNot(equals(b)));
    });

    group('MotionConfig', () {
      test('defaults', () {
        const config = MotionConfig();
        expect(config.stopTimeout, 5);
        expect(config.shakeThreshold, 2.5);
        expect(config.stillThreshold, 0.4);
        expect(config.stillSampleCount, 25);
      });

      test('round-trip serialization', () {
        const config = MotionConfig(
          stopTimeout: 10,
          shakeThreshold: 3.5,
          stillThreshold: 0.1,
          stillSampleCount: 50,
        );
        final map = config.toMap();
        expect(map['shakeThreshold'], 3.5);
        expect(map['stillThreshold'], 0.1);
        expect(map['stillSampleCount'], 50);

        final restored = MotionConfig.fromMap(map);
        expect(restored.shakeThreshold, 3.5);
        expect(restored.stillThreshold, 0.1);
        expect(restored.stillSampleCount, 50);
      });

      test('equality', () {
        const a = MotionConfig(shakeThreshold: 2);
        const b = MotionConfig(shakeThreshold: 2);
        const c = MotionConfig(shakeThreshold: 3);
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });

      test('hashCode equality', () {
        const a = MotionConfig(stillThreshold: 0.5);
        const b = MotionConfig(stillThreshold: 0.5);
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    test('HttpConfig.toMap serializes method as int index', () {
      const postConfig = HttpConfig();
      const putConfig = HttpConfig(method: HttpMethod.put);
      expect(postConfig.toMap()['method'], 0);
      expect(putConfig.toMap()['method'], 1);
    });

    test('HttpConfig.fromMap restores method from int index', () {
      // Simulates what the native platform receives after Config.toMap()
      final fromPost = HttpConfig.fromMap(const {'method': 0});
      final fromPut = HttpConfig.fromMap(const {'method': 1});
      expect(fromPost.method, HttpMethod.post);
      expect(fromPut.method, HttpMethod.put);
    });

    test('HttpConfig.toMap includes headers map', () {
      const config = HttpConfig(
        headers: {'x-api-key': 'abc123', 'x-account-id': 'acct'},
      );
      final map = config.toMap();
      final headers = map['headers']! as Map<String, String>;
      expect(headers['x-api-key'], 'abc123');
      expect(headers['x-account-id'], 'acct');
    });

    test('HttpConfig.fromMap handles missing headers gracefully', () {
      final config = HttpConfig.fromMap(const {});
      expect(config.headers, isNull);
    });

    test('HttpConfig maxBatchSize defaults to 250', () {
      const config = HttpConfig();
      expect(config.maxBatchSize, 250);
      final fromMap = HttpConfig.fromMap(const {});
      expect(fromMap.maxBatchSize, 250);
    });

    test(
      'HttpConfig round-trip preserves httpRootProperty and extras (Issue #107)',
      () {
        const config = HttpConfig(
          httpRootProperty: 'events',
          extras: {'custom': 123},
        );
        final map = config.toMap();
        expect(map['httpRootProperty'], 'events');
        final extras = map['extras'] as Map?;
        expect(extras?['custom'], 123);

        final restored = HttpConfig.fromMap(map);
        expect(restored.httpRootProperty, 'events');
        expect(restored.extras?['custom'], 123);
      },
    );

    test(
      'GeofenceConfig round-trip preserves geofenceInitialTrigger (Issue #107)',
      () {
        const config = GeofenceConfig(geofenceInitialTrigger: false);
        final map = config.toMap();
        expect(map['geofenceInitialTrigger'], false);

        final restored = GeofenceConfig.fromMap(map);
        expect(restored.geofenceInitialTrigger, false);
      },
    );

    test(
      'GeofenceConfig round-trip preserves geofenceModeHighAccuracy (#210)',
      () {
        const config = GeofenceConfig(geofenceModeHighAccuracy: true);
        final map = config.toMap();
        expect(map['geofenceModeHighAccuracy'], true);

        final restored = GeofenceConfig.fromMap(map);
        expect(restored.geofenceModeHighAccuracy, true);

        // Pigeon conversion carries the flag too.
        expect(config.toTlConfig().geofenceModeHighAccuracy, true);

        // Default stays false (standard region monitoring, no iOS indicator).
        expect(const GeofenceConfig().geofenceModeHighAccuracy, false);
      },
    );

    test('ForegroundServiceConfig equality includes all fields', () {
      const a = ForegroundServiceConfig(
        channelId: 'ch1',
        notificationTitle: 'T',
        notificationText: 'B',
      );
      const b = ForegroundServiceConfig(
        channelId: 'ch1',
        notificationTitle: 'T',
        notificationText: 'B',
        notificationPriority: NotificationPriority.max,
      );
      expect(a, isNot(equals(b)));
    });

    test('ForegroundServiceConfig.enabled defaults to true', () {
      const config = ForegroundServiceConfig();
      expect(config.enabled, true);
    });

    test('ForegroundServiceConfig.enabled can be disabled', () {
      const config = ForegroundServiceConfig(enabled: false);
      expect(config.enabled, false);
    });

    test('ForegroundServiceConfig.enabled round-trip serialization', () {
      const config = ForegroundServiceConfig(enabled: false);
      final map = config.toMap();
      expect(map['enabled'], false);
      final restored = ForegroundServiceConfig.fromMap(map);
      expect(restored.enabled, false);
    });

    test('ForegroundServiceConfig.enabled affects equality', () {
      const a = ForegroundServiceConfig();
      const b = ForegroundServiceConfig(enabled: false);
      expect(a, isNot(equals(b)));
    });

    test('ForegroundServiceConfig.enabled from map defaults to true', () {
      final config = ForegroundServiceConfig.fromMap(const {});
      expect(config.enabled, true);
    });
  });

  // ==========================================================================
  // IosConfig.activityType (#250)
  // ==========================================================================
  group('IosConfig.activityType (#250)', () {
    // The two enums are declared with different member orderings, so mapping
    // by raw `.index` corrupted the value in flight. `otherNavigation` and
    // `fitness` in particular are swapped between the orderings, which is the
    // clearest regression signal.
    test('toTlConfig maps every activity type by name, not by index', () {
      const cases = <LocationActivityType, TlIosActivityType>{
        LocationActivityType.other: TlIosActivityType.other,
        LocationActivityType.automotiveNavigation: TlIosActivityType.automotive,
        LocationActivityType.otherNavigation: TlIosActivityType.otherNavigation,
        LocationActivityType.fitness: TlIosActivityType.fitness,
        LocationActivityType.airborne: TlIosActivityType.airborne,
      };
      cases.forEach((input, expected) {
        expect(
          IosConfig(activityType: input).toTlConfig().activityType,
          expected,
          reason: '$input must map to $expected',
        );
      });
    });

    test('otherNavigation no longer bridges to fitness (the #250 bug)', () {
      // Regression guard for the exact reported symptom: with index-based
      // mapping, otherNavigation (index 2) became TlIosActivityType.values[2]
      // == fitness.
      const config = IosConfig(
        activityType: LocationActivityType.otherNavigation,
      );
      expect(config.toTlConfig().activityType, TlIosActivityType.otherNavigation);
      expect(
        config.toTlConfig().activityType,
        isNot(TlIosActivityType.fitness),
      );
    });

    test('default activity type is other', () {
      expect(
        const IosConfig().toTlConfig().activityType,
        TlIosActivityType.other,
      );
    });
  });

  group('LocationFilter', () {
    test('defaults are correct', () {
      const filter = LocationFilter();
      expect(filter.useKalmanFilter, false);
      expect(filter.trackingAccuracyThreshold, 100);
    });

    test('round-trip serialization preserves useKalmanFilter', () {
      const filter = LocationFilter(
        useKalmanFilter: true,
        trackingAccuracyThreshold: 150,
      );
      final map = filter.toMap();
      expect(map['useKalmanFilter'], true);

      final restored = LocationFilter.fromMap(map);
      expect(restored.useKalmanFilter, true);
      expect(restored.trackingAccuracyThreshold, 150);
    });

    test('equality and hashCode', () {
      const a = LocationFilter(useKalmanFilter: true);
      const b = LocationFilter(useKalmanFilter: true);
      const c = LocationFilter();
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  // ==========================================================================
  // Location
  // ==========================================================================
  group('Location', () {
    test('toJson can be used by jsonEncode', () {
      final loc = Location.fromMap(const {
        'uuid': 'test-uuid',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': true,
        'odometer': 15.0,
        'coords': {'latitude': 10.0, 'longitude': 20.0, 'accuracy': 5.0},
      });

      // If jsonEncode throws, this test will fail.
      final jsonStr = jsonEncode(loc);
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(decoded['uuid'], 'test-uuid');
      expect(decoded['timestamp'], '2024-01-01T00:00:00Z');
      expect(decoded['is_moving'], true);
      expect(decoded['odometer'], 15.0);
      expect((decoded['coords'] as Map)['latitude'], 10.0);
    });

    test('fromMap with minimal data', () {
      final loc = Location.fromMap(const {
        'uuid': 'abc-123',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': true,
        'odometer': 1500.0,
        'coords': {'latitude': 37.7749, 'longitude': -122.4194},
      });

      expect(loc.uuid, 'abc-123');
      expect(loc.isMoving, true);
      expect(loc.odometer, 1500.0);
      expect(loc.coords.latitude, 37.7749);
      expect(loc.coords.longitude, -122.4194);
    });

    test('round-trip serialization', () {
      final original = Location.fromMap(const {
        'uuid': 'test-uuid',
        'timestamp': '2024-06-15T10:30:00.000Z',
        'is_moving': false,
        'odometer': 2500.5,
        'coords': {
          'latitude': 48.8566,
          'longitude': 2.3522,
          'altitude': 35.0,
          'speed': 1.5,
          'heading': 180.0,
          'accuracy': 5.0,
          'speed_accuracy': 0.5,
          'heading_accuracy': 10.0,
          'altitude_accuracy': 3.0,
          'floor': 2,
        },
        'activity': {'type': 'walking', 'confidence': 75},
        'battery': {'level': 0.85, 'is_charging': true},
        'event': 'motionchange',
        'extras': {'foo': 'bar'},
      });

      final map = original.toMap();
      final restored = Location.fromMap(map);

      expect(restored.uuid, 'test-uuid');
      expect(restored.coords.altitude, 35.0);
      expect(restored.coords.speed, 1.5);
      expect(restored.coords.floor, 2);
      expect(restored.activity.type, ActivityType.walking);
      expect(restored.activity.confidence, ActivityConfidence.high);
      expect(restored.battery.level, 0.85);
      expect(restored.battery.isCharging, true);
      expect(restored.event, 'motionchange');
    });

    test('equality based on uuid', () {
      final a = Location.fromMap(const {
        'uuid': 'same-uuid',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': false,
        'odometer': 0.0,
        'coords': {'latitude': 0.0, 'longitude': 0.0},
      });
      final b = Location.fromMap(const {
        'uuid': 'same-uuid',
        'timestamp': '2024-02-01T00:00:00Z',
        'is_moving': true,
        'odometer': 100.0,
        'coords': {'latitude': 1.0, 'longitude': 1.0},
      });
      expect(a, equals(b));
    });

    test('fromMap supports camelCase keys', () {
      final loc = Location.fromMap(const {
        'uuid': 'camel-test',
        'timestamp': '2024-01-01T00:00:00Z',
        'isMoving': true,
        'odometer': 0.0,
        'coords': {
          'latitude': 0.0,
          'longitude': 0.0,
          'speedAccuracy': 1.5,
          'headingAccuracy': 2.0,
          'altitudeAccuracy': 3.0,
        },
        'battery': {'level': 0.5, 'isCharging': false},
      });
      expect(loc.isMoving, true);
      expect(loc.coords.speedAccuracy, 1.5);
      expect(loc.coords.headingAccuracy, 2.0);
      expect(loc.battery.isCharging, false);
    });

    test('isMock defaults to false', () {
      final loc = Location.fromMap(const {
        'uuid': 'mock-default',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': false,
        'odometer': 0.0,
        'coords': {'latitude': 0.0, 'longitude': 0.0},
      });
      expect(loc.isMock, false);
    });

    test('isMock parsed from mock key', () {
      final loc = Location.fromMap(const {
        'uuid': 'mock-true',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': false,
        'odometer': 0.0,
        'mock': true,
        'coords': {'latitude': 0.0, 'longitude': 0.0},
      });
      expect(loc.isMock, true);
    });

    test('isMock parsed from is_mock key', () {
      final loc = Location.fromMap(const {
        'uuid': 'mock-snake',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': false,
        'odometer': 0.0,
        'is_mock': true,
        'coords': {'latitude': 0.0, 'longitude': 0.0},
      });
      expect(loc.isMock, true);
    });

    test('isMock round-trips through toMap/fromMap', () {
      final original = Location.fromMap(const {
        'uuid': 'mock-rt',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': false,
        'odometer': 0.0,
        'mock': true,
        'coords': {'latitude': 0.0, 'longitude': 0.0},
      });
      expect(original.isMock, true);

      final map = original.toMap();
      expect(map['is_mock'], true);

      final restored = Location.fromMap(map);
      expect(restored.isMock, true);
    });

    test('locationSource defaults to unknown', () {
      final loc = Location.fromMap(const {
        'uuid': 'src-default',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': false,
        'odometer': 0.0,
        'coords': {'latitude': 0.0, 'longitude': 0.0},
      });
      expect(loc.locationSource, 'unknown');
    });

    test('locationSource parsed from map', () {
      final loc = Location.fromMap(const {
        'uuid': 'src-gps',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': false,
        'odometer': 0.0,
        'locationSource': 'gps',
        'coords': {'latitude': 37.0, 'longitude': -122.0},
      });
      expect(loc.locationSource, 'gps');
    });

    test('locationSource parsed from snake_case key', () {
      final loc = Location.fromMap(const {
        'uuid': 'src-wifi',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': false,
        'odometer': 0.0,
        'location_source': 'wifi',
        'coords': {'latitude': 37.0, 'longitude': -122.0},
      });
      expect(loc.locationSource, 'wifi');
    });

    test('locationSource round-trips through toMap/fromMap', () {
      final original = Location.fromMap(const {
        'uuid': 'src-rt',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': false,
        'odometer': 0.0,
        'locationSource': 'cell',
        'coords': {'latitude': 37.0, 'longitude': -122.0},
      });
      expect(original.locationSource, 'cell');

      final map = original.toMap();
      expect(map['locationSource'], 'cell');

      final restored = Location.fromMap(map);
      expect(restored.locationSource, 'cell');
    });

    test('locationSource preserved in copyWithCoords', () {
      final original = Location.fromMap(const {
        'uuid': 'src-copy',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': false,
        'odometer': 0.0,
        'locationSource': 'wifi',
        'coords': {'latitude': 37.0, 'longitude': -122.0},
      });
      final copy = original.copyWithCoords(latitude: 38);
      expect(copy.locationSource, 'wifi');
      expect(copy.coords.latitude, 38.0);
    });

    test('reducedAccuracy defaults to false', () {
      final loc = Location.fromMap(const {
        'uuid': 'ra-default',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': false,
        'odometer': 0.0,
        'coords': {'latitude': 0.0, 'longitude': 0.0},
      });
      expect(loc.reducedAccuracy, false);
    });

    test('reducedAccuracy parsed when true', () {
      final loc = Location.fromMap(const {
        'uuid': 'ra-true',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': false,
        'odometer': 0.0,
        'reducedAccuracy': true,
        'coords': {'latitude': 37.0, 'longitude': -122.0},
      });
      expect(loc.reducedAccuracy, true);
    });

    test('reducedAccuracy parsed from snake_case key', () {
      final loc = Location.fromMap(const {
        'uuid': 'ra-snake',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': false,
        'odometer': 0.0,
        'reduced_accuracy': true,
        'coords': {'latitude': 37.0, 'longitude': -122.0},
      });
      expect(loc.reducedAccuracy, true);
    });

    test('reducedAccuracy round-trips through toMap/fromMap', () {
      final original = Location.fromMap(const {
        'uuid': 'ra-rt',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': false,
        'odometer': 0.0,
        'reducedAccuracy': true,
        'coords': {'latitude': 37.0, 'longitude': -122.0},
      });
      expect(original.reducedAccuracy, true);

      final map = original.toMap();
      expect(map['reducedAccuracy'], true);

      final restored = Location.fromMap(map);
      expect(restored.reducedAccuracy, true);
    });

    test('reducedAccuracy preserved in copyWithCoords', () {
      final original = Location.fromMap(const {
        'uuid': 'ra-copy',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': false,
        'odometer': 0.0,
        'reducedAccuracy': true,
        'coords': {'latitude': 37.0, 'longitude': -122.0},
      });
      final copy = original.copyWithCoords(latitude: 38);
      expect(copy.reducedAccuracy, true);
    });

    test('mockHeuristics defaults to null', () {
      final loc = Location.fromMap(const {
        'uuid': 'test-uuid',
        'timestamp': '2024-01-01T00:00:00.000Z',
        'coords': {'latitude': 37.0, 'longitude': -122.0},
      });
      expect(loc.mockHeuristics, isNull);
    });

    test('mockHeuristics parsed from Android heuristics map', () {
      final loc = Location.fromMap(const {
        'uuid': 'test-uuid',
        'timestamp': '2024-01-01T00:00:00.000Z',
        'coords': {'latitude': 37.0, 'longitude': -122.0},
        'mockHeuristics': {
          'satellites': 0,
          'elapsedRealtimeDriftMs': 15000.0,
          'platformFlagMock': true,
        },
      });
      expect(loc.mockHeuristics, isNotNull);
      expect(loc.mockHeuristics!.satellites, 0);
      expect(loc.mockHeuristics!.elapsedRealtimeDriftMs, 15000.0);
      expect(loc.mockHeuristics!.platformFlagMock, true);
      expect(loc.mockHeuristics!.timestampDriftMs, isNull);
    });

    test('mockHeuristics parsed from iOS heuristics map', () {
      final loc = Location.fromMap(const {
        'uuid': 'test-uuid',
        'timestamp': '2024-01-01T00:00:00.000Z',
        'coords': {'latitude': 37.0, 'longitude': -122.0},
        'mockHeuristics': {
          'timestampDriftMs': 500.0,
          'platformFlagMock': false,
        },
      });
      expect(loc.mockHeuristics, isNotNull);
      expect(loc.mockHeuristics!.timestampDriftMs, 500.0);
      expect(loc.mockHeuristics!.platformFlagMock, false);
      expect(loc.mockHeuristics!.satellites, isNull);
      expect(loc.mockHeuristics!.elapsedRealtimeDriftMs, isNull);
    });

    test('mockHeuristics round-trips through toMap/fromMap', () {
      const original = Location(
        coords: Coords(latitude: 37, longitude: -122),
        timestamp: '2024-01-01T00:00:00.000Z',
        isMoving: false,
        uuid: 'test-uuid',
        odometer: 0,
        isMock: true,
        mockHeuristics: MockHeuristics(
          satellites: 5,
          elapsedRealtimeDriftMs: 200,
          platformFlagMock: false,
        ),
      );
      final map = original.toMap();
      expect(map['mockHeuristics'], isNotNull);

      final restored = Location.fromMap(map);
      expect(restored.mockHeuristics, isNotNull);
      expect(restored.mockHeuristics!.satellites, 5);
      expect(restored.mockHeuristics!.elapsedRealtimeDriftMs, 200.0);
      expect(restored.mockHeuristics!.platformFlagMock, false);
    });

    test('MockHeuristics equality', () {
      const a = MockHeuristics(satellites: 5, platformFlagMock: true);
      const b = MockHeuristics(satellites: 5, platformFlagMock: true);
      const c = MockHeuristics(satellites: 0, platformFlagMock: true);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('MockHeuristics toMap omits null fields', () {
      const h = MockHeuristics(satellites: 10);
      final map = h.toMap();
      expect(map.containsKey('satellites'), isTrue);
      expect(map.containsKey('elapsedRealtimeDriftMs'), isFalse);
      expect(map.containsKey('timestampDriftMs'), isFalse);
      expect(map.containsKey('platformFlagMock'), isFalse);
    });
  });

  // ==========================================================================
  // Coords
  // ==========================================================================
  group('Coords', () {
    test('defaults', () {
      const coords = Coords(latitude: 0, longitude: 0);
      expect(coords.altitude, 0.0);
      expect(coords.speed, 0.0);
      expect(coords.accuracy, 0.0);
      expect(coords.floor, isNull);
    });

    test('equality based on lat/lng', () {
      const a = Coords(latitude: 1, longitude: 2, altitude: 10);
      const b = Coords(latitude: 1, longitude: 2, altitude: 20);
      expect(a, equals(b));
    });
  });

  // ==========================================================================
  // Geofence
  // ==========================================================================
  group('Geofence', () {
    test('fromMap and toMap round-trip', () {
      final geofence = Geofence.fromMap(const {
        'identifier': 'home',
        'latitude': 37.0,
        'longitude': -122.0,
        'radius': 200.0,
        'notifyOnEntry': true,
        'notifyOnExit': false,
        'notifyOnDwell': true,
        'loiteringDelay': 30000,
        'extras': {'label': 'Home Zone'},
      });

      expect(geofence.identifier, 'home');
      expect(geofence.radius, 200.0);
      expect(geofence.notifyOnEntry, true);
      expect(geofence.notifyOnExit, false);
      expect(geofence.notifyOnDwell, true);
      expect(geofence.loiteringDelay, 30000);
      expect(geofence.extras['label'], 'Home Zone');

      final map = geofence.toMap();
      final restored = Geofence.fromMap(map);
      expect(restored.identifier, 'home');
      expect(restored.radius, 200.0);
    });

    test(
      'fromMap parses Pigeon nested dynamic lists for vertices without TypeError',
      () {
        // Reproduce issue #87 where Pigeon returns a List<Object?> of List<Object?>
        final rawVertices = <Object?>[
          <Object?>[37.0, -122.0],
          <Object?>[38.0, -122.0],
          <Object?>[38.0, -123.0],
        ];
        final geofence = Geofence.fromMap({
          'identifier': 'polygon',
          'latitude': 37.0,
          'longitude': -122.0,
          'radius': 0.0,
          'vertices': rawVertices,
        });

        expect(geofence.identifier, 'polygon');
        expect(geofence.vertices.length, 3);
        expect(geofence.vertices[0], [37.0, -122.0]);
        expect(geofence.vertices[2], [38.0, -123.0]);
      },
    );

    test('equality based on identifier', () {
      final a = Geofence.fromMap(const {
        'identifier': 'office',
        'latitude': 37.0,
        'longitude': -122.0,
        'radius': 100.0,
      });
      final b = Geofence.fromMap(const {
        'identifier': 'office',
        'latitude': 38.0,
        'longitude': -123.0,
        'radius': 200.0,
      });
      expect(a, equals(b));
    });
  });

  // ==========================================================================
  // GeofenceEvent
  // ==========================================================================
  group('GeofenceEvent', () {
    test('fromMap parses action as string', () {
      final event = GeofenceEvent.fromMap(const {
        'identifier': 'test-fence',
        'action': 'exit',
        'location': {
          'uuid': 'loc-1',
          'timestamp': '2024-01-01T00:00:00Z',
          'is_moving': false,
          'odometer': 0.0,
          'coords': {'latitude': 0.0, 'longitude': 0.0},
        },
      });
      expect(event.action, GeofenceAction.exit);
      expect(event.identifier, 'test-fence');
    });

    test('fromMap parses action as int', () {
      final event = GeofenceEvent.fromMap(const {
        'identifier': 'test-fence',
        'action': 2,
        'location': {
          'uuid': 'loc-1',
          'timestamp': '2024-01-01T00:00:00Z',
          'is_moving': false,
          'odometer': 0.0,
          'coords': {'latitude': 0.0, 'longitude': 0.0},
        },
      });
      expect(event.action, GeofenceAction.dwell);
    });
  });

  // ==========================================================================
  // State
  // ==========================================================================
  group('State', () {
    test('fromMap creates valid state', () {
      final state = State.fromMap(const {
        'enabled': true,
        'trackingMode': 1,
        'isMoving': true,
        'schedulerEnabled': true,
        'odometer': 5000.0,
        'didLaunchInBackground': false,
        'didDeviceReboot': false,
      });
      expect(state.enabled, true);
      expect(state.trackingMode, TrackingMode.geofences);
      expect(state.isMoving, true);
      expect(state.schedulerEnabled, true);
      expect(state.odometer, 5000.0);
    });

    test('isMoving defaults to false', () {
      final state = State.fromMap(const {'enabled': false, 'trackingMode': 0});
      expect(state.isMoving, false);
    });

    test('isMoving accepts snake_case key', () {
      final state = State.fromMap(const {
        'enabled': true,
        'trackingMode': 0,
        'is_moving': true,
      });
      expect(state.isMoving, true);
    });

    test('toMap round-trip', () {
      final state = State.fromMap(const {
        'enabled': false,
        'trackingMode': 0,
        'isMoving': true,
        'schedulerEnabled': false,
        'odometer': 0.0,
      });
      final map = state.toMap();
      expect(map['enabled'], false);
      expect(map['trackingMode'], 0);
      expect(map['isMoving'], true);

      // Round-trip back
      final restored = State.fromMap(map);
      expect(restored.isMoving, true);
      expect(restored.enabled, false);
    });

    test('fromMap handles missing keys gracefully', () {
      final state = State.fromMap(const {});
      expect(state.enabled, false);
      expect(state.trackingMode, TrackingMode.location);
      expect(state.isMoving, false);
      expect(state.odometer, 0.0);
    });

    test('equality includes all fields', () {
      const a = State(
        enabled: true,
        trackingMode: TrackingMode.location,
        isMoving: true,
        odometer: 100,
      );
      const b = State(
        enabled: true,
        trackingMode: TrackingMode.location,
        odometer: 100,
      );
      expect(a, isNot(equals(b)));
    });

    // Regression test for GitHub issue #26:
    // Config keys must not overwrite state keys when nested under "config".
    test('fromMap: config keys do not overwrite state values (issue #26)', () {
      // Simulates the fixed iOS StateManager.toMap() output where config
      // is properly nested under the "config" key.
      final state = State.fromMap(const {
        'enabled': true,
        'trackingMode': 0,
        'isMoving': true,
        'schedulerEnabled': false,
        'odometer': 1234.5,
        'didLaunchInBackground': false,
        'didDeviceReboot': false,
        'config': {
          // Flattened config contains "enabled" (from audit) and
          // "isMoving" (from motion) — these must NOT leak into state.
          'enabled': false,
          'isMoving': false,
          'distanceFilter': 50.0,
          'stopOnTerminate': true,
        },
      });
      // State values must reflect state, not config.
      expect(state.enabled, true);
      expect(state.isMoving, true);
      expect(state.odometer, 1234.5);
      expect(state.config, isNotNull);
    });

    test(
      'fromMap: flat-merged config would corrupt state (pre-fix behavior)',
      () {
        // Demonstrates the old broken iOS behavior where config was merged flat.
        // If someone accidentally reintroduces flat merging, this fails.
        final brokenMap = <String, Object?>{
          'enabled': true,
          'trackingMode': 0,
          'isMoving': true,
        };
        // Simulate flat-merge of config (the old bug)
        final configEntries = <String, Object?>{
          'enabled': false, // from audit section
          'isMoving': false, // from motion section
        };
        brokenMap.addAll(configEntries);

        final state = State.fromMap(brokenMap);
        // After flat merge, state.enabled would be false — this is the bug.
        expect(state.enabled, false, reason: 'flat merge corrupts enabled');
        expect(state.isMoving, false, reason: 'flat merge corrupts isMoving');
      },
    );
  });

  // ==========================================================================
  // ActivityChangeEvent
  // ==========================================================================
  group('ActivityChangeEvent', () {
    test('fromMap with string values', () {
      final event = ActivityChangeEvent.fromMap(const {
        'activity': 'walking',
        'confidence': 'high',
      });
      expect(event.activity, ActivityType.walking);
      expect(event.confidence, ActivityConfidence.high);
    });

    test('fromMap with int values', () {
      final event = ActivityChangeEvent.fromMap(const {
        'activity': 2,
        'confidence': 80,
      });
      expect(event.activity, ActivityType.running);
      expect(event.confidence, ActivityConfidence.high);
    });

    test('fromMap confidence thresholds', () {
      expect(
        ActivityChangeEvent.fromMap(const {
          'activity': 'still',
          'confidence': 75,
        }).confidence,
        ActivityConfidence.high,
      );
      expect(
        ActivityChangeEvent.fromMap(const {
          'activity': 'still',
          'confidence': 50,
        }).confidence,
        ActivityConfidence.medium,
      );
      expect(
        ActivityChangeEvent.fromMap(const {
          'activity': 'still',
          'confidence': 25,
        }).confidence,
        ActivityConfidence.low,
      );
    });
  });

  // ==========================================================================
  // ProviderChangeEvent
  // ==========================================================================
  group('ProviderChangeEvent', () {
    test('fromMap', () {
      final event = ProviderChangeEvent.fromMap(const {
        'enabled': true,
        'status': 3,
        'gps': true,
        'network': true,
        'accuracyAuthorization': 0,
      });
      expect(event.enabled, true);
      expect(event.status, AuthorizationStatus.always);
      expect(event.gps, true);
      expect(event.accuracyAuthorization, AccuracyAuthorization.full);
    });

    test('mockLocationsDetected defaults to false', () {
      final event = ProviderChangeEvent.fromMap(const {
        'enabled': true,
        'status': 3,
      });
      expect(event.mockLocationsDetected, false);
    });

    test('mockLocationsDetected parsed when true', () {
      final event = ProviderChangeEvent.fromMap(const {
        'enabled': true,
        'status': 3,
        'mockLocationsDetected': true,
      });
      expect(event.mockLocationsDetected, true);
    });

    test('mockLocationsDetected round-trips', () {
      final event = ProviderChangeEvent.fromMap(const {
        'enabled': true,
        'status': 3,
        'mockLocationsDetected': true,
      });
      final map = event.toMap();
      expect(map['mockLocationsDetected'], true);

      final restored = ProviderChangeEvent.fromMap(map);
      expect(restored.mockLocationsDetected, true);
    });

    test('gpsFallback defaults to false', () {
      final event = ProviderChangeEvent.fromMap(const {
        'enabled': true,
        'status': 3,
      });
      expect(event.gpsFallback, false);
    });

    test('gpsFallback parsed when true', () {
      final event = ProviderChangeEvent.fromMap(const {
        'enabled': true,
        'status': 3,
        'gpsFallback': true,
      });
      expect(event.gpsFallback, true);
    });

    test('gpsFallback round-trips', () {
      final event = ProviderChangeEvent.fromMap(const {
        'enabled': true,
        'status': 3,
        'gpsFallback': true,
      });
      final map = event.toMap();
      expect(map['gpsFallback'], true);

      final restored = ProviderChangeEvent.fromMap(map);
      expect(restored.gpsFallback, true);
    });
  });

  // ==========================================================================
  // HttpEvent
  // ==========================================================================
  group('HttpEvent', () {
    test('fromMap and toMap', () {
      final event = HttpEvent.fromMap(const {
        'success': true,
        'status': 200,
        'responseText': '{"ok":true}',
        'isRetry': false,
        'retryCount': 0,
      });
      expect(event.success, true);
      expect(event.status, 200);
      expect(event.responseText, '{"ok":true}');
      expect(event.isRetry, false);
      expect(event.retryCount, 0);

      final map = event.toMap();
      expect(map['success'], true);
      expect(map['status'], 200);
      expect(map['isRetry'], false);
      expect(map['retryCount'], 0);
    });

    test('fromMap with retry metadata', () {
      final event = HttpEvent.fromMap(const {
        'success': false,
        'status': 503,
        'responseText': 'Service Unavailable',
        'isRetry': true,
        'retryCount': 3,
      });
      expect(event.success, false);
      expect(event.status, 503);
      expect(event.isRetry, true);
      expect(event.retryCount, 3);
    });

    test('fromMap defaults for missing retry fields', () {
      final event = HttpEvent.fromMap(const {
        'success': true,
        'status': 200,
        'responseText': 'ok',
      });
      expect(event.isRetry, false);
      expect(event.retryCount, 0);
    });

    test('equality includes retry fields', () {
      const a = HttpEvent(success: true, status: 200);
      const b = HttpEvent(success: true, status: 200, isRetry: true);
      expect(a, isNot(equals(b)));

      const c = HttpEvent(success: true, status: 200, retryCount: 2);
      expect(a, isNot(equals(c)));
    });

    test('equality same values', () {
      const a = HttpEvent(
        success: true,
        status: 200,
        isRetry: true,
        retryCount: 5,
      );
      const b = HttpEvent(
        success: true,
        status: 200,
        responseText: 'different',
        isRetry: true,
        retryCount: 5,
      );
      expect(a, equals(b));
    });

    test('toString includes retryCount', () {
      const event = HttpEvent(success: false, status: 500, retryCount: 3);
      expect(event.toString(), contains('retryCount: 3'));
    });

    test('hashCode differs for different retry values', () {
      const a = HttpEvent(success: true, status: 200);
      const b = HttpEvent(success: true, status: 200, retryCount: 1);
      // Different retry counts should (very likely) have different hashes
      expect(a.hashCode, isNot(equals(b.hashCode)));
    });

    test('toMap round-trip preserves retry metadata', () {
      const original = HttpEvent(
        success: false,
        status: 429,
        responseText: 'Rate limited',
        isRetry: true,
        retryCount: 7,
      );
      final restored = HttpEvent.fromMap(original.toMap());
      expect(restored.success, false);
      expect(restored.status, 429);
      expect(restored.responseText, 'Rate limited');
      expect(restored.isRetry, true);
      expect(restored.retryCount, 7);
    });
  });

  // ==========================================================================
  // ConnectivityChangeEvent
  // ==========================================================================
  group('ConnectivityChangeEvent', () {
    test('fromMap and toMap', () {
      final event = ConnectivityChangeEvent.fromMap(const {'connected': true});
      expect(event.connected, true);

      final map = event.toMap();
      expect(map['connected'], true);
    });
  });

  // ==========================================================================
  // AuthorizationEvent
  // ==========================================================================
  group('AuthorizationEvent', () {
    test('fromMap and toMap', () {
      final event = AuthorizationEvent.fromMap(const {
        'success': false,
        'status': 401,
        'response': 'Unauthorized',
      });
      expect(event.success, false);
      expect(event.status, 401);
      expect(event.response, 'Unauthorized');
    });
  });

  // ==========================================================================
  // Sensors
  // ==========================================================================
  group('Sensors', () {
    test('fromMap', () {
      final sensors = Sensors.fromMap(const {
        'platform': 'android',
        'accelerometer': true,
        'gyroscope': true,
        'magnetometer': false,
        'significantMotion': true,
      });
      expect(sensors.platform, 'android');
      expect(sensors.accelerometer, true);
      expect(sensors.gyroscope, true);
      expect(sensors.magnetometer, false);
      expect(sensors.significantMotion, true);
    });
  });

  // ==========================================================================
  // DeviceInfo
  // ==========================================================================
  group('DeviceInfo', () {
    test('fromMap', () {
      final info = DeviceInfo.fromMap(const {
        'model': 'Pixel 6',
        'manufacturer': 'Google',
        'version': '14',
        'platform': 'android',
        'framework': 'flutter',
      });
      expect(info.model, 'Pixel 6');
      expect(info.manufacturer, 'Google');
      expect(info.platform, 'android');
    });
  });

  // ==========================================================================
  // HeadlessEvent
  // ==========================================================================
  group('HeadlessEvent', () {
    test('fromMap and toMap', () {
      final event = HeadlessEvent.fromMap(const {
        'name': 'location',
        'event': {'uuid': 'abc', 'latitude': 37.0},
      });
      expect(event.name, 'location');
      expect(event.event['uuid'], 'abc');
    });
  });

  // ==========================================================================
  // SQLQuery
  // ==========================================================================
  group('SQLQuery', () {
    test('defaults', () {
      const query = SQLQuery();
      expect(query.limit, -1);
      expect(query.order, LocationOrderDirection.ascending);
      expect(query.start, isNull);
      expect(query.end, isNull);
    });

    test('toMap includes timestamps as milliseconds', () {
      final now = DateTime(2024, 6, 15, 12);
      final query = SQLQuery(
        start: now,
        limit: 100,
        order: LocationOrderDirection.descending,
      );
      final map = query.toMap();
      expect(map['start'], now.millisecondsSinceEpoch);
      expect(map['limit'], 100);
    });

    test('toMap includes both start and end as milliseconds', () {
      final start = DateTime(2024);
      final end = DateTime(2024, 12, 31);
      final query = SQLQuery(start: start, end: end);
      final map = query.toMap();
      expect(map['start'], start.millisecondsSinceEpoch);
      expect(map['end'], end.millisecondsSinceEpoch);
      expect(map['limit'], -1);
      expect(map['order'], LocationOrderDirection.ascending.index);
    });

    test('toMap omits null start and end', () {
      const query = SQLQuery(limit: 50);
      final map = query.toMap();
      expect(map['start'], isNull);
      expect(map['end'], isNull);
      expect(map['limit'], 50);
    });

    test('fromMap round-trips start and end', () {
      final start = DateTime(2024, 3, 15, 8, 30);
      final end = DateTime(2024, 3, 15, 17);
      final original = SQLQuery(
        start: start,
        end: end,
        limit: 200,
        order: LocationOrderDirection.descending,
      );
      final restored = SQLQuery.fromMap(original.toMap());
      expect(restored.start, start);
      expect(restored.end, end);
      expect(restored.limit, 200);
      expect(restored.order, LocationOrderDirection.descending);
    });

    test('fromMap handles null start and end', () {
      final query = SQLQuery.fromMap(const {'limit': 10, 'order': 0});
      expect(query.start, isNull);
      expect(query.end, isNull);
    });

    test('fromMap with only start set', () {
      final start = DateTime(2024, 6);
      final query = SQLQuery.fromMap({
        'start': start.millisecondsSinceEpoch,
        'limit': -1,
        'order': 0,
      });
      expect(query.start, start);
      expect(query.end, isNull);
    });

    test('fromMap with only end set', () {
      final end = DateTime(2024, 6, 30);
      final query = SQLQuery.fromMap({
        'end': end.millisecondsSinceEpoch,
        'limit': -1,
        'order': 0,
      });
      expect(query.start, isNull);
      expect(query.end, end);
    });

    test('toString includes start and end', () {
      final query = SQLQuery(
        start: DateTime(2024),
        end: DateTime(2024, 12, 31),
      );
      final str = query.toString();
      expect(str, contains('start:'));
      expect(str, contains('end:'));
      expect(str, contains('SQLQuery'));
    });

    test('offset defaults to 0 and is serialized', () {
      const query = SQLQuery(limit: 50);
      expect(query.offset, 0);
      final map = query.toMap();
      expect(map['offset'], 0);
    });

    test('offset is preserved through toMap/fromMap round-trip', () {
      const query = SQLQuery(limit: 100, offset: 25);
      expect(query.offset, 25);
      final map = query.toMap();
      expect(map['offset'], 25);
      final restored = SQLQuery.fromMap(map);
      expect(restored.offset, 25);
      expect(restored.limit, 100);
    });

    test('toString includes offset', () {
      const query = SQLQuery(offset: 10);
      expect(query.toString(), contains('offset: 10'));
    });
  });

  // ==========================================================================
  // NotificationPriority enum parsing
  // ==========================================================================
  group('NotificationPriority', () {
    test('ForegroundServiceConfig defaults to defaultPriority', () {
      const config = ForegroundServiceConfig();
      expect(config.notificationPriority, NotificationPriority.defaultPriority);
    });

    test('fromMap parses int 0 as min', () {
      final config = ForegroundServiceConfig.fromMap(const {
        'notificationPriority': 0,
      });
      expect(config.notificationPriority, NotificationPriority.min);
    });

    test('fromMap parses int 1 as low', () {
      final config = ForegroundServiceConfig.fromMap(const {
        'notificationPriority': 1,
      });
      expect(config.notificationPriority, NotificationPriority.low);
    });

    test('fromMap parses int 2 as defaultPriority', () {
      final config = ForegroundServiceConfig.fromMap(const {
        'notificationPriority': 2,
      });
      expect(config.notificationPriority, NotificationPriority.defaultPriority);
    });

    test('fromMap parses int 3 as high', () {
      final config = ForegroundServiceConfig.fromMap(const {
        'notificationPriority': 3,
      });
      expect(config.notificationPriority, NotificationPriority.high);
    });

    test('fromMap parses int 4 as max', () {
      final config = ForegroundServiceConfig.fromMap(const {
        'notificationPriority': 4,
      });
      expect(config.notificationPriority, NotificationPriority.max);
    });

    test('fromMap defaults out-of-range int to defaultPriority', () {
      final config = ForegroundServiceConfig.fromMap(const {
        'notificationPriority': -5,
      });
      expect(config.notificationPriority, NotificationPriority.defaultPriority);
    });

    test('fromMap defaults out-of-range int to defaultPriority (high)', () {
      final config = ForegroundServiceConfig.fromMap(const {
        'notificationPriority': 10,
      });
      expect(config.notificationPriority, NotificationPriority.defaultPriority);
    });

    test('toMap serializes back to int', () {
      const config = ForegroundServiceConfig(
        notificationPriority: NotificationPriority.high,
      );
      final map = config.toMap();
      expect(map['notificationPriority'], 3);
    });

    test('round-trip preserves all priority values', () {
      for (final priority in NotificationPriority.values) {
        final config = ForegroundServiceConfig(notificationPriority: priority);
        final restored = ForegroundServiceConfig.fromMap(config.toMap());
        expect(restored.notificationPriority, priority);
      }
    });
  });

  // ==========================================================================
  // HashAlgorithm enum parsing
  // ==========================================================================
  group('HashAlgorithm', () {
    test('AuditConfig defaults to sha256', () {
      const config = AuditConfig();
      expect(config.hashAlgorithm, HashAlgorithm.sha256);
    });

    test('fromMap parses SHA-256 string', () {
      final config = AuditConfig.fromMap(const {'hashAlgorithm': 'SHA-256'});
      expect(config.hashAlgorithm, HashAlgorithm.sha256);
    });

    test('fromMap parses SHA-384 string', () {
      final config = AuditConfig.fromMap(const {'hashAlgorithm': 'SHA-384'});
      expect(config.hashAlgorithm, HashAlgorithm.sha384);
    });

    test('fromMap parses SHA-512 string', () {
      final config = AuditConfig.fromMap(const {'hashAlgorithm': 'SHA-512'});
      expect(config.hashAlgorithm, HashAlgorithm.sha512);
    });

    test('fromMap defaults unknown string to sha256', () {
      final config = AuditConfig.fromMap(const {'hashAlgorithm': 'MD5'});
      expect(config.hashAlgorithm, HashAlgorithm.sha256);
    });

    test('fromMap defaults missing key to sha256', () {
      final config = AuditConfig.fromMap(const <String, Object?>{});
      expect(config.hashAlgorithm, HashAlgorithm.sha256);
    });

    test('toMap serializes to standard string format', () {
      const config = AuditConfig();
      expect(config.toMap()['hashAlgorithm'], 'SHA-256');

      const config384 = AuditConfig(hashAlgorithm: HashAlgorithm.sha384);
      expect(config384.toMap()['hashAlgorithm'], 'SHA-384');

      const config512 = AuditConfig(hashAlgorithm: HashAlgorithm.sha512);
      expect(config512.toMap()['hashAlgorithm'], 'SHA-512');
    });

    test('round-trip preserves all algorithm values', () {
      for (final algo in HashAlgorithm.values) {
        final config = AuditConfig(hashAlgorithm: algo);
        final restored = AuditConfig.fromMap(config.toMap());
        expect(restored.hashAlgorithm, algo);
      }
    });
  });
}
