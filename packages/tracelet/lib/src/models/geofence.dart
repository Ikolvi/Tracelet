import 'package:meta/meta.dart';

/// A geofence definition.
///
/// Represents a circular geographic region the plugin monitors for
/// entry, exit, and dwell events.
///
/// ```dart
/// final geofence = Geofence(
///   identifier: 'office',
///   latitude: 37.422,
///   longitude: -122.084,
///   radius: 200.0,
///   notifyOnEntry: true,
///   notifyOnExit: true,
///   notifyOnDwell: true,
///   loiteringDelay: 30000,
/// );
/// await Tracelet.addGeofence(geofence);
/// ```
@immutable
class Geofence {
  /// Creates a new [Geofence].
  const Geofence({
    required this.identifier,
    required this.latitude,
    required this.longitude,
    required this.radius,
    this.notifyOnEntry = true,
    this.notifyOnExit = true,
    this.notifyOnDwell = false,
    this.loiteringDelay = 0,
    this.extras = const <String, Object?>{},
    this.vertices = const <List<double>>[],
  });

  /// Unique identifier for this geofence.
  final String identifier;

  /// Latitude of the center in degrees.
  final double latitude;

  /// Longitude of the center in degrees.
  final double longitude;

  /// Radius in meters.
  final double radius;

  /// Whether to trigger on entry. Defaults to `true`.
  final bool notifyOnEntry;

  /// Whether to trigger on exit. Defaults to `true`.
  final bool notifyOnExit;

  /// Whether to trigger a dwell event after [loiteringDelay]. Defaults to `false`.
  final bool notifyOnDwell;

  /// Time (in milliseconds) the device must loiter inside the geofence before
  /// a dwell event fires. Defaults to `0`.
  final int loiteringDelay;

  /// Arbitrary extra data to attach to this geofence.
  final Map<String, Object?> extras;

  /// Polygon vertices for future polygon geofence support.
  ///
  /// Each vertex is `[latitude, longitude]`. Empty for circular geofences.
  final List<List<double>> vertices;

  /// Creates a [Geofence] from a platform map.
  factory Geofence.fromMap(Map<String, Object?> map) {
    final extrasRaw = map['extras'];
    final verticesRaw = map['vertices'];

    final verticesList = <List<double>>[];
    if (verticesRaw is List) {
      for (final v in verticesRaw) {
        if (v is List) {
          verticesList.add(v.map((e) => _ensureDouble(e, fallback: 0.0)).toList());
        }
      }
    }

    return Geofence(
      identifier: map['identifier'] as String? ?? '',
      latitude: _ensureDouble(map['latitude'], fallback: 0.0),
      longitude: _ensureDouble(map['longitude'], fallback: 0.0),
      radius: _ensureDouble(map['radius'], fallback: 0.0),
      notifyOnEntry:
          _ensureBool(map['notifyOnEntry'], fallback: true),
      notifyOnExit:
          _ensureBool(map['notifyOnExit'], fallback: true),
      notifyOnDwell:
          _ensureBool(map['notifyOnDwell'], fallback: false),
      loiteringDelay:
          _ensureInt(map['loiteringDelay'], fallback: 0),
      extras: extrasRaw is Map
          ? extrasRaw.map<String, Object?>(
              (Object? k, Object? v) => MapEntry(k.toString(), v))
          : const <String, Object?>{},
      vertices: verticesList,
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'identifier': identifier,
      'latitude': latitude,
      'longitude': longitude,
      'radius': radius,
      'notifyOnEntry': notifyOnEntry,
      'notifyOnExit': notifyOnExit,
      'notifyOnDwell': notifyOnDwell,
      'loiteringDelay': loiteringDelay,
      'extras': extras,
      'vertices': vertices,
    };
  }

  @override
  String toString() =>
      'Geofence($identifier, lat: $latitude, lng: $longitude, r: ${radius}m)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Geofence &&
          runtimeType == other.runtimeType &&
          identifier == other.identifier;

  @override
  int get hashCode => identifier.hashCode;
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

bool _ensureBool(Object? value, {required bool fallback}) {
  if (value is bool) return value;
  if (value is int) return value != 0;
  return fallback;
}

int _ensureInt(Object? value, {required int fallback}) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  return fallback;
}

double _ensureDouble(Object? value, {required double fallback}) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return fallback;
}
