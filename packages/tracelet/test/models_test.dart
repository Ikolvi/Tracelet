import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet/tracelet.dart';

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
      expect(config.geo.periodicUseForegroundService, false);
      expect(config.geo.periodicUseExactAlarms, false);
    });

    test('round-trip serialization preserves all fields', () {
      const config = Config(
        geo: GeoConfig(
          distanceFilter: 50.0,
          stationaryRadius: 30.0,
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
        geofence: GeofenceConfig(
          geofenceInitialTriggerEntry: false,
          geofenceModeKnockOut: true,
        ),
        logger: LoggerConfig(
          logLevel: LogLevel.info,
          logMaxDays: 7,
          debug: true,
        ),
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
      expect(restored.geofence.geofenceModeKnockOut, true);
      expect(restored.logger.logLevel, LogLevel.info);
      expect(restored.logger.logMaxDays, 7);
      expect(restored.logger.debug, true);
    });

    test('equality based on all sub-configs', () {
      const a = Config(geo: GeoConfig(distanceFilter: 10.0));
      const b = Config(geo: GeoConfig(distanceFilter: 10.0));
      const c = Config(geo: GeoConfig(distanceFilter: 20.0));
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('fromMap handles empty map', () {
      final config = Config.fromMap(const {});
      expect(config.geo.distanceFilter, 10.0);
      expect(config.logger.debug, false);
    });

    test('toMap produces nested map (no flat spread collision)', () {
      const config = Config(
        http: HttpConfig(extras: {'apiKey': 'abc'}),
        persistence: PersistenceConfig(extras: {'device': 'test'}),
      );
      final map = config.toMap();

      // Config.toMap() should produce nested keys
      expect(map.containsKey('http'), true);
      expect(map.containsKey('persistence'), true);

      // Each sub-config extras should be independent
      final httpMap = map['http'] as Map<String, Object?>;
      final persistenceMap = map['persistence'] as Map<String, Object?>;
      expect(httpMap['extras'], {'apiKey': 'abc'});
      expect(persistenceMap['extras'], {'device': 'test'});
    });

    test('round-trip preserves both http and persistence extras', () {
      const config = Config(
        http: HttpConfig(extras: {'httpKey': 'httpVal'}),
        persistence: PersistenceConfig(extras: {'dbKey': 'dbVal'}),
      );
      final restored = Config.fromMap(config.toMap());
      expect(restored.http.extras, {'httpKey': 'httpVal'});
      expect(restored.persistence.extras, {'dbKey': 'dbVal'});
    });

    test('round-trip preserves periodic config options', () {
      const config = Config(
        geo: GeoConfig(
          periodicLocationInterval: 1800,
          periodicDesiredAccuracy: DesiredAccuracy.high,
          periodicUseForegroundService: true,
          periodicUseExactAlarms: true,
        ),
      );

      final map = config.toMap();
      final restored = Config.fromMap(map);

      expect(restored.geo.periodicLocationInterval, 1800);
      expect(restored.geo.periodicDesiredAccuracy, DesiredAccuracy.high);
      expect(restored.geo.periodicUseForegroundService, true);
      expect(restored.geo.periodicUseExactAlarms, true);
    });

    test('periodic config defaults are correct in fromMap with empty map', () {
      final config = Config.fromMap(const {});
      expect(config.geo.periodicLocationInterval, 900);
      expect(config.geo.periodicDesiredAccuracy, DesiredAccuracy.medium);
      expect(config.geo.periodicUseForegroundService, false);
      expect(config.geo.periodicUseExactAlarms, false);
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
      const a = HttpConfig(
        url: 'https://a.com',
        method: HttpMethod.post,
        autoSync: true,
        maxBatchSize: 100,
      );
      const b = HttpConfig(
        url: 'https://a.com',
        method: HttpMethod.post,
        autoSync: true,
        maxBatchSize: 200,
      );
      expect(a, isNot(equals(b)));
    });

    test('HttpConfig retry fields have sensible defaults', () {
      const c = HttpConfig();
      expect(c.maxRetries, 10);
      expect(c.retryBackoffBase, 1000);
      expect(c.retryBackoffCap, 300000);
    });

    test('HttpConfig equality includes retry fields', () {
      const a = HttpConfig(url: 'https://a.com', maxRetries: 5);
      const b = HttpConfig(url: 'https://a.com', maxRetries: 10);
      expect(a, isNot(equals(b)));

      const c = HttpConfig(url: 'https://a.com', retryBackoffBase: 500);
      const d = HttpConfig(url: 'https://a.com', retryBackoffBase: 1000);
      expect(c, isNot(equals(d)));

      const e = HttpConfig(url: 'https://a.com', retryBackoffCap: 60000);
      const f = HttpConfig(url: 'https://a.com', retryBackoffCap: 300000);
      expect(e, isNot(equals(f)));
    });

    test('HttpConfig fromMap parses retry fields', () {
      final c = HttpConfig.fromMap(const {
        'url': 'https://example.com',
        'maxRetries': 5,
        'retryBackoffBase': 2000,
        'retryBackoffCap': 120000,
      });
      expect(c.maxRetries, 5);
      expect(c.retryBackoffBase, 2000);
      expect(c.retryBackoffCap, 120000);
    });

    test('HttpConfig toMap includes retry fields', () {
      const c = HttpConfig(
        url: 'https://example.com',
        maxRetries: 3,
        retryBackoffBase: 500,
        retryBackoffCap: 60000,
      );
      final map = c.toMap();
      expect(map['maxRetries'], 3);
      expect(map['retryBackoffBase'], 500);
      expect(map['retryBackoffCap'], 60000);
    });

    test('HttpConfig fromMap uses defaults for missing retry fields', () {
      final c = HttpConfig.fromMap(const {'url': 'https://example.com'});
      expect(c.maxRetries, 10);
      expect(c.retryBackoffBase, 1000);
      expect(c.retryBackoffCap, 300000);
    });

    test('HttpConfig round-trip preserves retry fields', () {
      const original = HttpConfig(
        url: 'https://example.com',
        maxRetries: 7,
        retryBackoffBase: 1500,
        retryBackoffCap: 180000,
      );
      final restored = HttpConfig.fromMap(original.toMap());
      expect(restored.maxRetries, 7);
      expect(restored.retryBackoffBase, 1500);
      expect(restored.retryBackoffCap, 180000);
    });

    test('HttpConfig.toMap serializes method as int index', () {
      const postConfig = HttpConfig(method: HttpMethod.post);
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
      final headers = map['headers'] as Map<String, String>;
      expect(headers['x-api-key'], 'abc123');
      expect(headers['x-account-id'], 'acct');
    });

    test('HttpConfig.fromMap handles missing headers gracefully', () {
      final config = HttpConfig.fromMap(const {});
      expect(config.headers, isEmpty);
    });

    test('HttpConfig maxBatchSize defaults to 250', () {
      const config = HttpConfig();
      expect(config.maxBatchSize, 250);
      final fromMap = HttpConfig.fromMap(const {});
      expect(fromMap.maxBatchSize, 250);
    });

    test('ForegroundServiceConfig equality includes all fields', () {
      const a = ForegroundServiceConfig(
        channelId: 'ch1',
        notificationTitle: 'T',
        notificationText: 'B',
        notificationPriority: NotificationPriority.defaultPriority,
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
      const a = ForegroundServiceConfig(enabled: true);
      const b = ForegroundServiceConfig(enabled: false);
      expect(a, isNot(equals(b)));
    });

    test('ForegroundServiceConfig.enabled from map defaults to true', () {
      final config = ForegroundServiceConfig.fromMap(const {});
      expect(config.enabled, true);
    });

    test('MotionConfig equality includes stopDetectionDelay', () {
      const a = MotionConfig(stopDetectionDelay: 0);
      const b = MotionConfig(stopDetectionDelay: 10);
      expect(a, isNot(equals(b)));
    });

    test('MotionConfig motion sensitivity defaults', () {
      const config = MotionConfig();
      expect(config.shakeThreshold, 2.5);
      expect(config.stillThreshold, 0.4);
      expect(config.stillSampleCount, 25);
    });

    test('MotionConfig motion sensitivity round-trip serialization', () {
      const config = MotionConfig(
        shakeThreshold: 4.0,
        stillThreshold: 0.8,
        stillSampleCount: 50,
      );
      final map = config.toMap();
      expect(map['shakeThreshold'], 4.0);
      expect(map['stillThreshold'], 0.8);
      expect(map['stillSampleCount'], 50);

      final restored = MotionConfig.fromMap(map);
      expect(restored.shakeThreshold, 4.0);
      expect(restored.stillThreshold, 0.8);
      expect(restored.stillSampleCount, 50);
      expect(restored, equals(config));
    });

    test('MotionConfig motion sensitivity affects equality', () {
      const a = MotionConfig(shakeThreshold: 2.5);
      const b = MotionConfig(shakeThreshold: 4.0);
      expect(a, isNot(equals(b)));

      const c = MotionConfig(stillThreshold: 0.4);
      const d = MotionConfig(stillThreshold: 0.8);
      expect(c, isNot(equals(d)));

      const e = MotionConfig(stillSampleCount: 25);
      const f = MotionConfig(stillSampleCount: 50);
      expect(e, isNot(equals(f)));
    });

    test(
      'MotionConfig fromMap with missing sensitivity fields uses defaults',
      () {
        final config = MotionConfig.fromMap(const {'stopTimeout': 10});
        expect(config.stopTimeout, 10);
        expect(config.shakeThreshold, 2.5);
        expect(config.stillThreshold, 0.4);
        expect(config.stillSampleCount, 25);
      },
    );

    test('LocationFilter.rejectMockLocations defaults to false', () {
      const filter = LocationFilter();
      expect(filter.rejectMockLocations, false);
    });

    test('LocationFilter.rejectMockLocations round-trip serialization', () {
      const filter = LocationFilter(rejectMockLocations: true);
      final map = filter.toMap();
      expect(map['rejectMockLocations'], true);

      final restored = LocationFilter.fromMap(map);
      expect(restored.rejectMockLocations, true);
    });

    test('LocationFilter.rejectMockLocations affects equality', () {
      const a = LocationFilter(rejectMockLocations: false);
      const b = LocationFilter(rejectMockLocations: true);
      expect(a, isNot(equals(b)));
    });

    test(
      'LocationFilter.rejectMockLocations from empty map defaults false',
      () {
        final filter = LocationFilter.fromMap(const {});
        expect(filter.rejectMockLocations, false);
      },
    );

    test('LocationFilter.mockDetectionLevel defaults to disabled', () {
      const filter = LocationFilter();
      expect(filter.mockDetectionLevel, MockDetectionLevel.disabled);
    });

    test('LocationFilter.mockDetectionLevel round-trip serialization', () {
      const filter = LocationFilter(
        mockDetectionLevel: MockDetectionLevel.heuristic,
      );
      final map = filter.toMap();
      expect(map['mockDetectionLevel'], 2); // heuristic == index 2
      final restored = LocationFilter.fromMap(map);
      expect(restored.mockDetectionLevel, MockDetectionLevel.heuristic);
    });

    test('LocationFilter.mockDetectionLevel affects equality', () {
      const a = LocationFilter(mockDetectionLevel: MockDetectionLevel.basic);
      const b = LocationFilter(
        mockDetectionLevel: MockDetectionLevel.heuristic,
      );
      expect(a, isNot(equals(b)));
    });

    test(
      'LocationFilter.mockDetectionLevel from empty map defaults disabled',
      () {
        final filter = LocationFilter.fromMap(const {});
        expect(filter.mockDetectionLevel, MockDetectionLevel.disabled);
      },
    );
  });

  // ==========================================================================
  // Location
  // ==========================================================================
  group('Location', () {
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
        coords: Coords(latitude: 37.0, longitude: -122.0),
        timestamp: '2024-01-01T00:00:00.000Z',
        isMoving: false,
        uuid: 'test-uuid',
        odometer: 0,
        isMock: true,
        mockHeuristics: MockHeuristics(
          satellites: 5,
          elapsedRealtimeDriftMs: 200.0,
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
      const coords = Coords(latitude: 0.0, longitude: 0.0);
      expect(coords.altitude, 0.0);
      expect(coords.speed, 0.0);
      expect(coords.accuracy, 0.0);
      expect(coords.floor, isNull);
    });

    test('equality based on lat/lng', () {
      const a = Coords(latitude: 1.0, longitude: 2.0, altitude: 10.0);
      const b = Coords(latitude: 1.0, longitude: 2.0, altitude: 20.0);
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
        odometer: 100.0,
      );
      const b = State(
        enabled: true,
        trackingMode: TrackingMode.location,
        isMoving: false,
        odometer: 100.0,
      );
      expect(a, isNot(equals(b)));
    });
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
      const a = HttpEvent(success: true, status: 200, retryCount: 0);
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
      expect(query.order, LocationOrder.asc);
      expect(query.start, isNull);
      expect(query.end, isNull);
    });

    test('toMap includes timestamps as milliseconds', () {
      final now = DateTime(2024, 6, 15, 12, 0, 0);
      final query = SQLQuery(start: now, limit: 100, order: LocationOrder.desc);
      final map = query.toMap();
      expect(map['start'], now.millisecondsSinceEpoch);
      expect(map['limit'], 100);
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

    test('fromMap parses int -2 as min', () {
      final config = ForegroundServiceConfig.fromMap(const {
        'notificationPriority': -2,
      });
      expect(config.notificationPriority, NotificationPriority.min);
    });

    test('fromMap parses int -1 as low', () {
      final config = ForegroundServiceConfig.fromMap(const {
        'notificationPriority': -1,
      });
      expect(config.notificationPriority, NotificationPriority.low);
    });

    test('fromMap parses int 0 as defaultPriority', () {
      final config = ForegroundServiceConfig.fromMap(const {
        'notificationPriority': 0,
      });
      expect(config.notificationPriority, NotificationPriority.defaultPriority);
    });

    test('fromMap parses int 1 as high', () {
      final config = ForegroundServiceConfig.fromMap(const {
        'notificationPriority': 1,
      });
      expect(config.notificationPriority, NotificationPriority.high);
    });

    test('fromMap parses int 2 as max', () {
      final config = ForegroundServiceConfig.fromMap(const {
        'notificationPriority': 2,
      });
      expect(config.notificationPriority, NotificationPriority.max);
    });

    test('fromMap clamps out-of-range int to min', () {
      final config = ForegroundServiceConfig.fromMap(const {
        'notificationPriority': -5,
      });
      expect(config.notificationPriority, NotificationPriority.min);
    });

    test('fromMap clamps out-of-range int to max', () {
      final config = ForegroundServiceConfig.fromMap(const {
        'notificationPriority': 10,
      });
      expect(config.notificationPriority, NotificationPriority.max);
    });

    test('toMap serializes back to int', () {
      const config = ForegroundServiceConfig(
        notificationPriority: NotificationPriority.high,
      );
      final map = config.toMap();
      expect(map['notificationPriority'], 1);
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
      const config = AuditConfig(hashAlgorithm: HashAlgorithm.sha256);
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

  // ==========================================================================
  // triggerActivities Set<ActivityType> parsing
  // ==========================================================================
  group('triggerActivities', () {
    test('MotionConfig defaults to empty set', () {
      const config = MotionConfig();
      expect(config.triggerActivities, isEmpty);
    });

    test('fromMap parses comma-separated string', () {
      final config = MotionConfig.fromMap(const {
        'triggerActivities': 'on_foot, in_vehicle',
      });
      expect(config.triggerActivities, {
        ActivityType.onFoot,
        ActivityType.inVehicle,
      });
    });

    test('fromMap parses single activity', () {
      final config = MotionConfig.fromMap(const {
        'triggerActivities': 'walking',
      });
      expect(config.triggerActivities, {ActivityType.walking});
    });

    test('fromMap handles all activity types', () {
      final config = MotionConfig.fromMap(const {
        'triggerActivities':
            'still,walking,running,on_foot,in_vehicle,on_bicycle,unknown',
      });
      expect(config.triggerActivities, {
        ActivityType.still,
        ActivityType.walking,
        ActivityType.running,
        ActivityType.onFoot,
        ActivityType.inVehicle,
        ActivityType.onBicycle,
        ActivityType.unknown,
      });
    });

    test('fromMap ignores invalid activity names', () {
      final config = MotionConfig.fromMap(const {
        'triggerActivities': 'walking, flying, running',
      });
      expect(config.triggerActivities, {
        ActivityType.walking,
        ActivityType.running,
      });
    });

    test('fromMap handles empty string', () {
      final config = MotionConfig.fromMap(const {'triggerActivities': ''});
      expect(config.triggerActivities, isEmpty);
    });

    test('fromMap handles missing key', () {
      final config = MotionConfig.fromMap(const <String, Object?>{});
      expect(config.triggerActivities, isEmpty);
    });

    test('toMap serializes to comma-separated snake_case string', () {
      const config = MotionConfig(
        triggerActivities: {ActivityType.onFoot, ActivityType.inVehicle},
      );
      final value = config.toMap()['triggerActivities'] as String;
      expect(value, contains('on_foot'));
      expect(value, contains('in_vehicle'));
    });

    test('toMap serializes empty set to empty string', () {
      const config = MotionConfig();
      expect(config.toMap()['triggerActivities'], '');
    });

    test('round-trip preserves activities through serialization', () {
      const activities = {
        ActivityType.walking,
        ActivityType.running,
        ActivityType.onBicycle,
      };
      const config = MotionConfig(triggerActivities: activities);
      final restored = MotionConfig.fromMap(config.toMap());
      expect(restored.triggerActivities, activities);
    });

    test('case-insensitive parsing', () {
      final config = MotionConfig.fromMap(const {
        'triggerActivities': 'Walking, ON_FOOT, In_Vehicle',
      });
      expect(config.triggerActivities, {
        ActivityType.walking,
        ActivityType.onFoot,
        ActivityType.inVehicle,
      });
    });
  });
}
