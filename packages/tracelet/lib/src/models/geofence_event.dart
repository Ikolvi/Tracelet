import 'package:meta/meta.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

import 'location.dart';

/// Event fired when a geofence transition occurs.
///
/// Contains the geofence identifier, the transition action (enter/exit/dwell),
/// and the location at the time of the event.
@immutable
class GeofenceEvent {
  /// Creates a new [GeofenceEvent].
  const GeofenceEvent({
    required this.identifier,
    required this.action,
    required this.location,
    this.extras = const <String, Object?>{},
  });

  /// The identifier of the geofence.
  final String identifier;

  /// The transition action.
  final GeofenceAction action;

  /// The location at the time of the event.
  final Location location;

  /// Extra data from the geofence definition.
  final Map<String, Object?> extras;

  /// Creates a [GeofenceEvent] from a platform map.
  factory GeofenceEvent.fromMap(Map<String, Object?> map) {
    final actionRaw = map['action'];
    GeofenceAction action = GeofenceAction.enter;
    if (actionRaw is int) {
      action = GeofenceAction.values[
          actionRaw.clamp(0, GeofenceAction.values.length - 1)];
    } else if (actionRaw is String) {
      action = GeofenceAction.values.firstWhere(
        (e) => e.name == actionRaw.toLowerCase(),
        orElse: () => GeofenceAction.enter,
      );
    }

    final locationMap = map['location'] as Map<String, Object?>? ??
        const <String, Object?>{};
    final extrasRaw = map['extras'];

    return GeofenceEvent(
      identifier: map['identifier'] as String? ?? '',
      action: action,
      location: Location.fromMap(locationMap),
      extras: extrasRaw is Map
          ? extrasRaw.map<String, Object?>(
              (Object? k, Object? v) => MapEntry(k.toString(), v))
          : const <String, Object?>{},
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'identifier': identifier,
      'action': action.name,
      'location': location.toMap(),
      'extras': extras,
    };
  }

  @override
  String toString() =>
      'GeofenceEvent($identifier, action: $action)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeofenceEvent &&
          runtimeType == other.runtimeType &&
          identifier == other.identifier &&
          action == other.action;

  @override
  int get hashCode => Object.hash(identifier, action);
}
