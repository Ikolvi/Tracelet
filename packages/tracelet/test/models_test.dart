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
      expect(config.logger.logLevel, LogLevel.off);
      expect(config.motion.stopTimeout, 5);
      expect(config.geofence.geofenceInitialTriggerEntry, true);
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
        motion: MotionConfig(
          stopTimeout: 10,
          isMoving: true,
        ),
        geofence: GeofenceConfig(
          geofenceInitialTriggerEntry: false,
          geofenceModeKnockOut: true,
        ),
        logger: LoggerConfig(logLevel: LogLevel.info, logMaxDays: 7, debug: true),
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
        'coords': {
          'latitude': 37.7749,
          'longitude': -122.4194,
        },
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
        'activity': {
          'type': 'walking',
          'confidence': 75,
        },
        'battery': {
          'level': 0.85,
          'is_charging': true,
        },
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
        'battery': {
          'level': 0.5,
          'isCharging': false,
        },
      });
      expect(loc.isMoving, true);
      expect(loc.coords.speedAccuracy, 1.5);
      expect(loc.coords.headingAccuracy, 2.0);
      expect(loc.battery.isCharging, false);
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
        'schedulerEnabled': true,
        'odometer': 5000.0,
        'didLaunchInBackground': false,
        'didDeviceReboot': false,
      });
      expect(state.enabled, true);
      expect(state.trackingMode, TrackingMode.geofences);
      expect(state.schedulerEnabled, true);
      expect(state.odometer, 5000.0);
    });

    test('toMap round-trip', () {
      final state = State.fromMap(const {
        'enabled': false,
        'trackingMode': 0,
        'schedulerEnabled': false,
        'odometer': 0.0,
      });
      final map = state.toMap();
      expect(map['enabled'], false);
      expect(map['trackingMode'], 0);
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
      });
      expect(event.success, true);
      expect(event.status, 200);
      expect(event.responseText, '{"ok":true}');

      final map = event.toMap();
      expect(map['success'], true);
      expect(map['status'], 200);
    });

    test('equality', () {
      const a = HttpEvent(success: true, status: 200);
      const b = HttpEvent(success: true, status: 200, responseText: 'different');
      expect(a, equals(b));
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
}
