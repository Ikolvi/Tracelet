import 'package:meta/meta.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

/// A recorded location from the native platform.
///
/// Contains GPS coordinates, motion state, activity recognition data,
/// battery state, and metadata.
///
/// ```dart
/// Tracelet.onLocation((Location loc) {
///   print('${loc.coords.latitude}, ${loc.coords.longitude}');
///   print('Moving: ${loc.isMoving}');
/// });
/// ```
@immutable
class Location {
  /// Creates a new [Location].
  const Location({
    required this.coords,
    required this.timestamp,
    required this.isMoving,
    required this.uuid,
    required this.odometer,
    this.activity = const LocationActivity(),
    this.battery = const LocationBattery(),
    this.extras = const <String, Object?>{},
    this.event,
  });

  /// Geographic coordinates and accuracy metrics.
  final Coords coords;

  /// ISO 8601 timestamp of when this location was recorded.
  final String timestamp;

  /// Whether the device was in a moving state when this location was recorded.
  final bool isMoving;

  /// Unique identifier for this location record.
  final String uuid;

  /// Distance (in meters) traveled since tracking started.
  final double odometer;

  /// The detected activity at the time of this location.
  final LocationActivity activity;

  /// Battery state at the time of this location.
  final LocationBattery battery;

  /// Arbitrary extra data attached to this location.
  final Map<String, Object?> extras;

  /// The event that triggered this location (e.g. `'motionchange'`,
  /// `'providerchange'`, `'heartbeat'`).
  final String? event;

  /// Creates a [Location] from a platform map.
  factory Location.fromMap(Map<String, Object?> map) {
    final coordsMap = map['coords'] as Map<String, Object?>? ??
        const <String, Object?>{};
    final activityMap = map['activity'] as Map<String, Object?>?;
    final batteryMap = map['battery'] as Map<String, Object?>?;
    final extrasRaw = map['extras'];

    return Location(
      coords: Coords.fromMap(
        coordsMap.isEmpty ? map : coordsMap,
      ),
      timestamp: map['timestamp'] as String? ?? '',
      isMoving: _ensureBool(map['is_moving'] ?? map['isMoving'], fallback: false),
      uuid: map['uuid'] as String? ?? '',
      odometer: _ensureDouble(map['odometer'], fallback: 0.0),
      activity: activityMap != null
          ? LocationActivity.fromMap(activityMap)
          : const LocationActivity(),
      battery: batteryMap != null
          ? LocationBattery.fromMap(batteryMap)
          : const LocationBattery(),
      extras: extrasRaw is Map
          ? extrasRaw.map<String, Object?>(
              (Object? k, Object? v) => MapEntry(k.toString(), v))
          : const <String, Object?>{},
      event: map['event'] as String?,
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'coords': coords.toMap(),
      'timestamp': timestamp,
      'is_moving': isMoving,
      'uuid': uuid,
      'odometer': odometer,
      'activity': activity.toMap(),
      'battery': battery.toMap(),
      'extras': extras,
      'event': event,
    };
  }

  @override
  String toString() =>
      'Location(lat: ${coords.latitude}, lng: ${coords.longitude}, '
      'isMoving: $isMoving, uuid: $uuid)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Location &&
          runtimeType == other.runtimeType &&
          uuid == other.uuid;

  @override
  int get hashCode => uuid.hashCode;
}

// ---------------------------------------------------------------------------
// Coords
// ---------------------------------------------------------------------------

/// Geographic coordinates with accuracy metrics.
@immutable
class Coords {
  /// Creates a new [Coords].
  const Coords({
    required this.latitude,
    required this.longitude,
    this.altitude = 0.0,
    this.speed = 0.0,
    this.heading = 0.0,
    this.accuracy = 0.0,
    this.speedAccuracy = 0.0,
    this.headingAccuracy = 0.0,
    this.altitudeAccuracy = 0.0,
    this.floor,
  });

  /// Latitude in degrees.
  final double latitude;

  /// Longitude in degrees.
  final double longitude;

  /// Altitude in meters above sea level.
  final double altitude;

  /// Speed in meters per second.
  final double speed;

  /// Heading/bearing in degrees (0–360).
  final double heading;

  /// Horizontal accuracy in meters.
  final double accuracy;

  /// Speed accuracy in meters per second (Android only).
  final double speedAccuracy;

  /// Heading accuracy in degrees.
  final double headingAccuracy;

  /// Altitude accuracy in meters.
  final double altitudeAccuracy;

  /// The floor of the building (iOS only).
  final int? floor;

  /// Creates [Coords] from a platform map.
  factory Coords.fromMap(Map<String, Object?> map) {
    return Coords(
      latitude: _ensureDouble(map['latitude'], fallback: 0.0),
      longitude: _ensureDouble(map['longitude'], fallback: 0.0),
      altitude: _ensureDouble(map['altitude'], fallback: 0.0),
      speed: _ensureDouble(map['speed'], fallback: 0.0),
      heading: _ensureDouble(map['heading'], fallback: 0.0),
      accuracy: _ensureDouble(map['accuracy'], fallback: 0.0),
      speedAccuracy: _ensureDouble(
          map['speed_accuracy'] ?? map['speedAccuracy'],
          fallback: 0.0),
      headingAccuracy: _ensureDouble(
          map['heading_accuracy'] ?? map['headingAccuracy'],
          fallback: 0.0),
      altitudeAccuracy: _ensureDouble(
          map['altitude_accuracy'] ?? map['altitudeAccuracy'],
          fallback: 0.0),
      floor: map['floor'] as int?,
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'speed': speed,
      'heading': heading,
      'accuracy': accuracy,
      'speed_accuracy': speedAccuracy,
      'heading_accuracy': headingAccuracy,
      'altitude_accuracy': altitudeAccuracy,
      'floor': floor,
    };
  }

  @override
  String toString() => 'Coords($latitude, $longitude ±${accuracy}m)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Coords &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

// ---------------------------------------------------------------------------
// LocationActivity
// ---------------------------------------------------------------------------

/// Activity recognition data associated with a location.
@immutable
class LocationActivity {
  /// Creates a new [LocationActivity].
  const LocationActivity({
    this.type = ActivityType.unknown,
    this.confidence = ActivityConfidence.low,
  });

  /// The detected activity type.
  final ActivityType type;

  /// The confidence level of the detection.
  final ActivityConfidence confidence;

  /// Creates a [LocationActivity] from a platform map.
  factory LocationActivity.fromMap(Map<String, Object?> map) {
    // Activity type can be sent as string or int
    ActivityType actType = ActivityType.unknown;
    final rawType = map['type'];
    if (rawType is int) {
      actType = ActivityType.values[rawType.clamp(0, ActivityType.values.length - 1)];
    } else if (rawType is String) {
      actType = ActivityType.values.firstWhere(
        (e) => e.name == rawType,
        orElse: () => ActivityType.unknown,
      );
    }

    ActivityConfidence conf = ActivityConfidence.low;
    final rawConf = map['confidence'];
    if (rawConf is int) {
      // Native can send 0-100 confidence → map to enum
      if (rawConf >= 75) {
        conf = ActivityConfidence.high;
      } else if (rawConf >= 50) {
        conf = ActivityConfidence.medium;
      } else {
        conf = ActivityConfidence.low;
      }
    } else if (rawConf is String) {
      conf = ActivityConfidence.values.firstWhere(
        (e) => e.name == rawConf,
        orElse: () => ActivityConfidence.low,
      );
    }

    return LocationActivity(type: actType, confidence: conf);
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'type': type.name,
      'confidence': confidence.name,
    };
  }

  @override
  String toString() => 'LocationActivity($type, $confidence)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocationActivity &&
          type == other.type &&
          confidence == other.confidence;

  @override
  int get hashCode => Object.hash(type, confidence);
}

// ---------------------------------------------------------------------------
// LocationBattery
// ---------------------------------------------------------------------------

/// Battery state associated with a location.
@immutable
class LocationBattery {
  /// Creates a new [LocationBattery].
  const LocationBattery({
    this.level = -1.0,
    this.isCharging = false,
  });

  /// Battery level from `0.0` to `1.0`, or `-1.0` if unknown.
  final double level;

  /// Whether the device is currently charging.
  final bool isCharging;

  /// Creates a [LocationBattery] from a platform map.
  factory LocationBattery.fromMap(Map<String, Object?> map) {
    return LocationBattery(
      level: _ensureDouble(map['level'], fallback: -1.0),
      isCharging: _ensureBool(
          map['is_charging'] ?? map['isCharging'],
          fallback: false),
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'level': level,
      'is_charging': isCharging,
    };
  }

  @override
  String toString() =>
      'LocationBattery(level: ${(level * 100).toStringAsFixed(0)}%, '
      'charging: $isCharging)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocationBattery &&
          level == other.level &&
          isCharging == other.isCharging;

  @override
  int get hashCode => Object.hash(level, isCharging);
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

bool _ensureBool(Object? value, {required bool fallback}) {
  if (value is bool) return value;
  if (value is int) return value != 0;
  return fallback;
}

double _ensureDouble(Object? value, {required double fallback}) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}
