import 'package:meta/meta.dart';

import '_helpers.dart';
import 'location.dart';

/// Represents a detected trip (start → stop).
///
/// A trip is auto-detected when the device transitions from stationary to
/// moving and back to stationary. Contains summary statistics: distance,
/// duration, start/end locations, and the route polyline.
///
/// ```dart
/// Tracelet.onTrip((trip) {
///   print('Trip: ${trip.distance}m in ${trip.duration}s');
///   print('From: ${trip.startLocation.coords.latitude}');
///   print('To:   ${trip.stopLocation.coords.latitude}');
/// });
/// ```
@immutable
class TripEvent {
  /// Creates a new [TripEvent].
  const TripEvent({
    required this.isMoving,
    required this.distance,
    required this.duration,
    required this.startLocation,
    required this.stopLocation,
    this.waypoints = const <Location>[],
  });

  /// Whether the device is currently moving (`true` = trip started,
  /// `false` = trip ended).
  final bool isMoving;

  /// Total distance (in meters) covered during this trip.
  final double distance;

  /// Total duration (in seconds) of this trip.
  final double duration;

  /// The location when the trip started.
  final Location startLocation;

  /// The location when the trip stopped (or the latest location if ongoing).
  final Location stopLocation;

  /// Ordered list of intermediate locations recorded during the trip.
  ///
  /// Empty if no tracking locations were recorded between start and stop.
  final List<Location> waypoints;

  /// The average speed (m/s) during the trip.
  double get averageSpeed => duration > 0 ? distance / duration : 0.0;

  /// Creates a [TripEvent] from a platform map.
  factory TripEvent.fromMap(Map<String, Object?> map) {
    final startMap = safeMap(map['startLocation']) ?? const <String, Object?>{};
    final stopMap = safeMap(map['stopLocation']) ?? const <String, Object?>{};
    final waypointsList = map['waypoints'] as List<Object?>? ?? const [];

    return TripEvent(
      isMoving: ensureBool(map['isMoving'], fallback: false),
      distance: ensureDouble(map['distance'], fallback: 0.0),
      duration: ensureDouble(map['duration'], fallback: 0.0),
      startLocation: Location.fromMap(startMap.cast<String, Object?>()),
      stopLocation: Location.fromMap(stopMap.cast<String, Object?>()),
      waypoints: waypointsList
          .whereType<Map<Object?, Object?>>()
          .map((wp) => Location.fromMap((wp).cast<String, Object?>()))
          .toList(),
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'isMoving': isMoving,
      'distance': distance,
      'duration': duration,
      'startLocation': startLocation.toMap(),
      'stopLocation': stopLocation.toMap(),
      'waypoints': waypoints.map((w) => w.toMap()).toList(),
    };
  }

  @override
  String toString() =>
      'TripEvent(isMoving: $isMoving, distance: $distance, '
      'duration: $duration, averageSpeed: $averageSpeed)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TripEvent &&
          runtimeType == other.runtimeType &&
          isMoving == other.isMoving &&
          distance == other.distance &&
          duration == other.duration &&
          startLocation == other.startLocation &&
          stopLocation == other.stopLocation;

  @override
  int get hashCode =>
      Object.hash(isMoving, distance, duration, startLocation, stopLocation);
}
