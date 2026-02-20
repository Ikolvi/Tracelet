import 'package:meta/meta.dart';

import 'geofence.dart';

/// Event fired when the set of active geofences changes.
///
/// Contains the newly activated (`on`) and deactivated (`off`) geofences.
/// This typically fires when the device moves and the nearest-N geofences
/// are rotated in/out of the platform monitor.
@immutable
class GeofencesChangeEvent {
  /// Creates a new [GeofencesChangeEvent].
  const GeofencesChangeEvent({
    this.on = const <Geofence>[],
    this.off = const <Geofence>[],
  });

  /// Geofences that were activated (started monitoring).
  final List<Geofence> on;

  /// Geofences that were deactivated (stopped monitoring).
  final List<Geofence> off;

  /// Creates a [GeofencesChangeEvent] from a platform map.
  factory GeofencesChangeEvent.fromMap(Map<String, Object?> map) {
    final onRaw = map['on'];
    final offRaw = map['off'];

    return GeofencesChangeEvent(
      on: _parseGeofenceList(onRaw),
      off: _parseGeofenceList(offRaw),
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'on': on.map((g) => g.toMap()).toList(),
      'off': off.map((g) => g.toMap()).toList(),
    };
  }

  @override
  String toString() =>
      'GeofencesChangeEvent(on: ${on.length}, off: ${off.length})';
}

List<Geofence> _parseGeofenceList(Object? raw) {
  if (raw is! List) return const <Geofence>[];
  return raw
      .whereType<Map<String, Object?>>()
      .map(Geofence.fromMap)
      .toList();
}
