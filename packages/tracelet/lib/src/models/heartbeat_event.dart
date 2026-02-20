import 'package:meta/meta.dart';

import 'location.dart';

Map<String, Object?>? _safeMap(Object? value) {
  if (value == null) return null;
  if (value is Map<String, Object?>) return value;
  if (value is Map) return Map<String, Object?>.from(value);
  return null;
}

/// Event fired on each heartbeat interval.
///
/// Contains the latest known location (which may be stale if the device
/// is stationary and not actively receiving GPS fixes).
@immutable
class HeartbeatEvent {
  /// Creates a new [HeartbeatEvent].
  const HeartbeatEvent({
    required this.location,
  });

  /// The latest location at the time of the heartbeat.
  final Location location;

  /// Creates a [HeartbeatEvent] from a platform map.
  factory HeartbeatEvent.fromMap(Map<String, Object?> map) {
    final locationMap = _safeMap(map['location']) ?? const <String, Object?>{};

    return HeartbeatEvent(
      location: Location.fromMap(locationMap),
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'location': location.toMap(),
    };
  }

  @override
  String toString() => 'HeartbeatEvent(location: $location)';
}
