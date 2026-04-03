import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet/tracelet.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

/// Tests that verify the location map format contract between native SDKs
/// and the Dart deserialization layer.
///
/// The canonical format produced by the native EventDispatchers uses:
/// - Nested `"coords"` map with camelCase accuracy keys
/// - Nested `"battery"` map with `"is_charging"` (snake_case)
/// - Nested `"activity"` map with `"type"` and `"confidence"`
/// - `"is_moving"` (snake_case) at the top level
/// - `"mock"` key (not `"isMock"` or `"is_mock"`)
void main() {
  // ========================================================================
  // Canonical SDK format → Location.fromMap()
  // ========================================================================
  group('Location.fromMap canonical SDK format', () {
    late Map<String, Object?> canonicalMap;

    setUp(() {
      canonicalMap = <String, Object?>{
        'uuid': 'abc-123',
        'timestamp': '2024-06-15T10:30:00.000Z',
        'is_moving': true,
        'odometer': 1234.5,
        'event': 'motionchange',
        'mock': false,
        'coords': <String, Object?>{
          'latitude': 37.4219983,
          'longitude': -122.084,
          'accuracy': 5.0,
          'speed': 2.5,
          'heading': 180.0,
          'altitude': 100.0,
          'altitudeAccuracy': 3.0,
          'speedAccuracy': 1.5,
          'headingAccuracy': 10.0,
          'floor': 2,
        },
        'battery': <String, Object?>{'level': 0.75, 'is_charging': true},
        'activity': <String, Object?>{'type': 'onFoot', 'confidence': 85},
        'extras': <String, Object?>{'route': 'A1'},
      };
    });

    test('parses nested coords with camelCase accuracy keys', () {
      final loc = Location.fromMap(canonicalMap);
      expect(loc.coords.latitude, 37.4219983);
      expect(loc.coords.longitude, -122.084);
      expect(loc.coords.accuracy, 5.0);
      expect(loc.coords.speed, 2.5);
      expect(loc.coords.heading, 180.0);
      expect(loc.coords.altitude, 100.0);
      expect(loc.coords.altitudeAccuracy, 3.0);
      expect(loc.coords.speedAccuracy, 1.5);
      expect(loc.coords.headingAccuracy, 10.0);
      expect(loc.coords.floor, 2);
    });

    test('parses battery with is_charging snake_case key', () {
      final loc = Location.fromMap(canonicalMap);
      expect(loc.battery.level, 0.75);
      expect(loc.battery.isCharging, isTrue);
    });

    test('parses activity with type and confidence', () {
      final loc = Location.fromMap(canonicalMap);
      expect(loc.activity.type, ActivityType.onFoot);
      expect(loc.activity.confidence, ActivityConfidence.high);
    });

    test('parses is_moving snake_case key', () {
      final loc = Location.fromMap(canonicalMap);
      expect(loc.isMoving, isTrue);
    });

    test('parses mock key (not isMock)', () {
      final loc = Location.fromMap(canonicalMap);
      expect(loc.isMock, isFalse);
    });

    test('parses top-level fields', () {
      final loc = Location.fromMap(canonicalMap);
      expect(loc.uuid, 'abc-123');
      expect(loc.timestamp, '2024-06-15T10:30:00.000Z');
      expect(loc.odometer, 1234.5);
      expect(loc.event, 'motionchange');
      expect(loc.extras, {'route': 'A1'});
    });
  });

  // ========================================================================
  // Legacy / alternative key formats → Location.fromMap()
  // ========================================================================
  group('Location.fromMap legacy key compatibility', () {
    test('accepts isMoving camelCase key', () {
      final map = _minimalMap()..['isMoving'] = true;
      map.remove('is_moving');
      final loc = Location.fromMap(map);
      expect(loc.isMoving, isTrue);
    });

    test('accepts isCharging camelCase in battery', () {
      final map = _minimalMap();
      map['battery'] = <String, Object?>{'level': 0.5, 'isCharging': true};
      final loc = Location.fromMap(map);
      expect(loc.battery.isCharging, isTrue);
    });

    test('accepts snake_case accuracy keys in coords', () {
      final map = _minimalMap();
      map['coords'] = <String, Object?>{
        'latitude': 1.0,
        'longitude': 2.0,
        'accuracy': 5.0,
        'speed': 0.0,
        'heading': 0.0,
        'altitude': 0.0,
        'speed_accuracy': 7.7,
        'heading_accuracy': 8.8,
        'altitude_accuracy': 9.9,
      };
      final loc = Location.fromMap(map);
      expect(loc.coords.speedAccuracy, 7.7);
      expect(loc.coords.headingAccuracy, 8.8);
      expect(loc.coords.altitudeAccuracy, 9.9);
    });

    test('accepts isMock legacy key', () {
      final map = _minimalMap()..['isMock'] = true;
      final loc = Location.fromMap(map);
      expect(loc.isMock, isTrue);
    });

    test('accepts is_mock legacy key', () {
      final map = _minimalMap()..['is_mock'] = true;
      final loc = Location.fromMap(map);
      expect(loc.isMock, isTrue);
    });

    test('falls back to flat coords when nested coords is missing', () {
      final map = <String, Object?>{
        'uuid': 'flat-uuid',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': false,
        'odometer': 0.0,
        'latitude': 10.0,
        'longitude': 20.0,
        'accuracy': 15.0,
        'speed': 1.0,
        'heading': 90.0,
        'altitude': 50.0,
        'speed_accuracy': 2.0,
        'heading_accuracy': 3.0,
        'altitude_accuracy': 4.0,
      };
      final loc = Location.fromMap(map);
      expect(loc.coords.latitude, 10.0);
      expect(loc.coords.longitude, 20.0);
      expect(loc.coords.speedAccuracy, 2.0);
    });
  });

  // ========================================================================
  // Coords.fromMap
  // ========================================================================
  group('Coords.fromMap key conventions', () {
    test('prefers snake_case when both conventions present', () {
      final map = <String, Object?>{
        'latitude': 1.0,
        'longitude': 2.0,
        'accuracy': 5.0,
        'speed': 0.0,
        'heading': 0.0,
        'altitude': 0.0,
        'speed_accuracy': 11.0,
        'speedAccuracy': 22.0,
        'heading_accuracy': 33.0,
        'headingAccuracy': 44.0,
        'altitude_accuracy': 55.0,
        'altitudeAccuracy': 66.0,
      };
      final coords = Coords.fromMap(map);
      // snake_case is checked first in the ?? chain
      expect(coords.speedAccuracy, 11.0);
      expect(coords.headingAccuracy, 33.0);
      expect(coords.altitudeAccuracy, 55.0);
    });

    test('falls back to camelCase when snake_case not present', () {
      final map = <String, Object?>{
        'latitude': 1.0,
        'longitude': 2.0,
        'accuracy': 5.0,
        'speed': 0.0,
        'heading': 0.0,
        'altitude': 0.0,
        'speedAccuracy': 22.0,
        'headingAccuracy': 44.0,
        'altitudeAccuracy': 66.0,
      };
      final coords = Coords.fromMap(map);
      expect(coords.speedAccuracy, 22.0);
      expect(coords.headingAccuracy, 44.0);
      expect(coords.altitudeAccuracy, 66.0);
    });
  });

  // ========================================================================
  // LocationBattery.fromMap
  // ========================================================================
  group('LocationBattery.fromMap key conventions', () {
    test('reads is_charging snake_case', () {
      final b = LocationBattery.fromMap({'level': 0.5, 'is_charging': true});
      expect(b.isCharging, isTrue);
    });

    test('falls back to isCharging camelCase', () {
      final b = LocationBattery.fromMap({'level': 0.5, 'isCharging': true});
      expect(b.isCharging, isTrue);
    });

    test('defaults to false when key is absent', () {
      final b = LocationBattery.fromMap({'level': 0.5});
      expect(b.isCharging, isFalse);
    });
  });

  // ========================================================================
  // LocationActivity.fromMap
  // ========================================================================
  group('LocationActivity.fromMap', () {
    test('parses string type and int confidence', () {
      final a = LocationActivity.fromMap({'type': 'walking', 'confidence': 90});
      expect(a.type, ActivityType.walking);
      expect(a.confidence, ActivityConfidence.high);
    });

    test('parses int type index', () {
      final a = LocationActivity.fromMap({'type': 0, 'confidence': 30});
      expect(a.type, ActivityType.values[0]);
      expect(a.confidence, ActivityConfidence.low);
    });

    test('unknown type string maps to ActivityType.unknown', () {
      final a = LocationActivity.fromMap({'type': 'flying', 'confidence': 50});
      expect(a.type, ActivityType.unknown);
      expect(a.confidence, ActivityConfidence.medium);
    });
  });

  // ========================================================================
  // Location.fromTl (Pigeon path)
  // ========================================================================
  group('Location.fromTl Pigeon path', () {
    test('converts all TlLocation fields correctly', () {
      final tl = TlLocation(
        coords: TlCoords(
          latitude: 48.8566,
          longitude: 2.3522,
          accuracy: 10.0,
          speed: 3.0,
          heading: 270.0,
          altitude: 35.0,
          altitudeAccuracy: 5.0,
          speedAccuracy: 2.0,
          headingAccuracy: 15.0,
          floor: 1,
        ),
        battery: TlBattery(level: 0.9, isCharging: false),
        timestamp: '2024-06-15T12:00:00Z',
        uuid: 'pigeon-uuid',
        isMoving: true,
        odometer: 500.0,
        event: 'location',
        activity: TlActivity(type: 'still', confidence: 95),
        extras: {'key': 'value'},
      );
      final loc = Location.fromTl(tl);

      expect(loc.coords.latitude, 48.8566);
      expect(loc.coords.longitude, 2.3522);
      expect(loc.coords.altitudeAccuracy, 5.0);
      expect(loc.coords.speedAccuracy, 2.0);
      expect(loc.coords.headingAccuracy, 15.0);
      expect(loc.coords.floor, 1);
      expect(loc.battery.level, 0.9);
      expect(loc.battery.isCharging, isFalse);
      expect(loc.timestamp, '2024-06-15T12:00:00Z');
      expect(loc.uuid, 'pigeon-uuid');
      expect(loc.isMoving, isTrue);
      expect(loc.odometer, 500.0);
      expect(loc.event, 'location');
      expect(loc.activity.type, ActivityType.still);
      expect(loc.activity.confidence, ActivityConfidence.high);
      expect(loc.extras, {'key': 'value'});
    });

    test('handles null optional fields', () {
      final tl = TlLocation(
        coords: TlCoords(
          latitude: 0.0,
          longitude: 0.0,
          accuracy: 0.0,
          speed: 0.0,
          heading: 0.0,
          altitude: 0.0,
          altitudeAccuracy: 0.0,
          speedAccuracy: 0.0,
          headingAccuracy: 0.0,
        ),
        battery: TlBattery(level: -1.0, isCharging: false),
        timestamp: '',
        uuid: '',
        isMoving: false,
        odometer: 0.0,
      );
      final loc = Location.fromTl(tl);

      expect(loc.event, isNull);
      expect(loc.activity.type, ActivityType.unknown);
      expect(loc.extras, isEmpty);
    });
  });

  // ========================================================================
  // Round-trip: Location.fromMap(location.toMap())
  // ========================================================================
  group('Location round-trip serialization', () {
    test('toMap() → fromMap() preserves all fields', () {
      final original = Location(
        coords: const Coords(
          latitude: 37.4219983,
          longitude: -122.084,
          accuracy: 5.0,
          speed: 2.5,
          heading: 180.0,
          altitude: 100.0,
          altitudeAccuracy: 3.0,
          speedAccuracy: 1.5,
          headingAccuracy: 10.0,
          floor: 2,
        ),
        timestamp: '2024-06-15T10:30:00.000Z',
        isMoving: true,
        uuid: 'round-trip-uuid',
        odometer: 999.9,
        event: 'heartbeat',
        activity: const LocationActivity(
          type: ActivityType.inVehicle,
          confidence: ActivityConfidence.medium,
        ),
        battery: const LocationBattery(level: 0.42, isCharging: true),
        extras: const <String, Object?>{'foo': 'bar'},
      );

      final map = original.toMap();
      final restored = Location.fromMap(map);

      expect(restored.coords.latitude, original.coords.latitude);
      expect(restored.coords.longitude, original.coords.longitude);
      expect(restored.coords.speedAccuracy, original.coords.speedAccuracy);
      expect(restored.coords.headingAccuracy, original.coords.headingAccuracy);
      expect(
        restored.coords.altitudeAccuracy,
        original.coords.altitudeAccuracy,
      );
      expect(restored.coords.floor, original.coords.floor);
      expect(restored.battery.level, original.battery.level);
      expect(restored.battery.isCharging, original.battery.isCharging);
      expect(restored.isMoving, original.isMoving);
      expect(restored.uuid, original.uuid);
      expect(restored.odometer, original.odometer);
      expect(restored.event, original.event);
      expect(restored.activity.type, original.activity.type);
      expect(restored.extras, original.extras);
    });
  });

  // ========================================================================
  // Simulated DB round-trip (DB uses snake_case for accuracy)
  // ========================================================================
  group('Simulated DB round-trip', () {
    test('iOS DB locationRowToMap format parses correctly', () {
      // Before our fix, iOS DB returned snake_case accuracy keys.
      // After fix, it returns camelCase. Test both are supported.
      final dbMap = <String, Object?>{
        'uuid': 'db-uuid',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': false,
        'odometer': 0.0,
        'coords': <String, Object?>{
          'latitude': 1.0,
          'longitude': 2.0,
          'altitude': 3.0,
          'speed': 4.0,
          'heading': 5.0,
          'accuracy': 6.0,
          'speedAccuracy': 7.0,
          'headingAccuracy': 8.0,
          'altitudeAccuracy': 9.0,
        },
        'battery': <String, Object?>{'level': 0.5, 'is_charging': false},
        'activity': <String, Object?>{'type': 'unknown', 'confidence': -1},
      };
      final loc = Location.fromMap(dbMap);
      expect(loc.coords.speedAccuracy, 7.0);
      expect(loc.coords.headingAccuracy, 8.0);
      expect(loc.coords.altitudeAccuracy, 9.0);
    });

    test('Android DB cursorToLocation format parses correctly (canonical)', () {
      // After fix for #48: Android DB now uses canonical format matching iOS:
      // - is_moving (snake_case), ISO 8601 timestamp
      final dbMap = <String, Object?>{
        'uuid': 'android-db-uuid',
        'timestamp': '2024-06-15T12:30:00.000Z',
        'is_moving': true,
        'odometer': 100.0,
        'event': 'location',
        'coords': <String, Object?>{
          'latitude': 37.0,
          'longitude': -122.0,
          'altitude': 50.0,
          'speed': 1.0,
          'heading': 90.0,
          'accuracy': 10.0,
          'speedAccuracy': 2.0,
          'headingAccuracy': 3.0,
          'altitudeAccuracy': 4.0,
        },
        'battery': <String, Object?>{'level': 0.8, 'is_charging': true},
        'activity': <String, Object?>{'type': 'still', 'confidence': 100},
      };
      final loc = Location.fromMap(dbMap);
      expect(loc.coords.speedAccuracy, 2.0);
      expect(loc.battery.isCharging, isTrue);
      expect(loc.isMoving, isTrue);
      expect(loc.activity.type, ActivityType.still);
      expect(loc.timestamp, '2024-06-15T12:30:00.000Z');
    });

    test('Android DB legacy format still parses (backward compat)', () {
      // Before fix for #48: Android DB used numeric timestamp + isMoving.
      // Verify old data can still be deserialized for backward compatibility.
      final legacyMap = <String, Object?>{
        'uuid': 'android-legacy-uuid',
        'timestamp': 1718451000000,
        'isMoving': true,
        'odometer': 100.0,
        'event': 'location',
        'coords': <String, Object?>{
          'latitude': 37.0,
          'longitude': -122.0,
          'altitude': 50.0,
          'speed': 1.0,
          'heading': 90.0,
          'accuracy': 10.0,
          'speedAccuracy': 2.0,
          'headingAccuracy': 3.0,
          'altitudeAccuracy': 4.0,
        },
        'battery': <String, Object?>{'level': 0.8, 'is_charging': true},
        'activity': <String, Object?>{'type': 'still', 'confidence': 100},
      };
      final loc = Location.fromMap(legacyMap);
      expect(loc.isMoving, isTrue);
      expect(loc.battery.isCharging, isTrue);
      // Numeric timestamp gets stringified by ensureString()
      expect(loc.timestamp, '1718451000000');
    });
  });
}

/// Builds a minimal valid location map with canonical SDK format.
Map<String, Object?> _minimalMap() {
  return <String, Object?>{
    'uuid': 'test-uuid',
    'timestamp': '2024-01-01T00:00:00Z',
    'is_moving': false,
    'odometer': 0.0,
    'coords': <String, Object?>{
      'latitude': 0.0,
      'longitude': 0.0,
      'accuracy': 0.0,
      'speed': 0.0,
      'heading': 0.0,
      'altitude': 0.0,
      'altitudeAccuracy': 0.0,
      'speedAccuracy': 0.0,
      'headingAccuracy': 0.0,
    },
    'battery': <String, Object?>{'level': -1.0, 'is_charging': false},
    'activity': <String, Object?>{'type': 'unknown', 'confidence': -1},
  };
}
