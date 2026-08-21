import 'package:meta/meta.dart';

import 'package:tracelet/src/models/_helpers.dart';
import 'package:tracelet/src/models/location.dart';

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
    this.tripId,
    this.startedAt,
    this.endedAt,
  });

  /// Creates a [TripEvent] from a platform map.
  factory TripEvent.fromMap(Map<String, Object?> map) {
    final startMap = safeMap(map['startLocation']) ?? const <String, Object?>{};
    final stopMap = safeMap(map['stopLocation']) ?? const <String, Object?>{};
    final waypointsList = map['waypoints'] as List<Object?>? ?? const [];

    return TripEvent(
      isMoving: ensureBool(map['isMoving'], fallback: false),
      distance: ensureDouble(map['distance'], fallback: 0),
      duration: ensureDouble(map['duration'], fallback: 0),
      startLocation: Location.fromMap(startMap.cast<String, Object?>()),
      stopLocation: Location.fromMap(stopMap.cast<String, Object?>()),
      waypoints: waypointsList
          .whereType<Map<Object?, Object?>>()
          .map((wp) => Location.fromMap(wp.cast<String, Object?>()))
          .toList(),
      tripId: map['tripId'] as String?,
      startedAt: _epochMs(map['startedAt']),
      endedAt: _epochMs(map['endedAt']),
    );
  }

  /// Reads an epoch-milliseconds field written by the native layer, which
  /// sends it as an `int` (or a `BigInt` through the Rust bridge).
  static DateTime? _epochMs(Object? value) {
    final ms = value is int
        ? value
        : value is BigInt
        ? value.toInt()
        : value is num
        ? value.toInt()
        : null;
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

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

  /// The trip's identifier, shared with every location and driving event
  /// recorded during it (#402).
  ///
  /// A UUIDv4 minted by the SDK when the trip started. Treat it as opaque —
  /// it carries no information and does not sort chronologically; order trips
  /// by [startedAt] instead. `null` for trips produced by an SDK version
  /// before trip identity existed.
  final String? tripId;

  /// When the trip started (#402).
  ///
  /// [duration] alone cannot place a trip on a timeline; this and [endedAt]
  /// can. `null` on records from before trip identity existed.
  final DateTime? startedAt;

  /// When the trip ended (#402).
  final DateTime? endedAt;

  /// The average speed (m/s) during the trip.
  double get averageSpeed => duration > 0 ? distance / duration : 0.0;

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'isMoving': isMoving,
      'distance': distance,
      'duration': duration,
      'startLocation': startLocation.toMap(),
      'stopLocation': stopLocation.toMap(),
      'waypoints': waypoints.map((w) => w.toMap()).toList(),
      'tripId': tripId,
      'startedAt': startedAt?.millisecondsSinceEpoch,
      'endedAt': endedAt?.millisecondsSinceEpoch,
    };
  }

  @override
  String toString() =>
      'TripEvent(tripId: $tripId, isMoving: $isMoving, distance: $distance, '
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
          stopLocation == other.stopLocation &&
          tripId == other.tripId &&
          startedAt == other.startedAt &&
          endedAt == other.endedAt;

  @override
  int get hashCode => Object.hash(
    isMoving,
    distance,
    duration,
    startLocation,
    stopLocation,
    tripId,
    startedAt,
    endedAt,
  );
}
