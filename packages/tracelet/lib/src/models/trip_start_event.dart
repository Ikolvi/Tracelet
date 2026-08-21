import 'package:meta/meta.dart';

import 'package:tracelet/src/models/_helpers.dart';
import 'package:tracelet/src/models/location.dart';

/// The moment a trip begins (#402).
///
/// Emitted by [Tracelet.onTripStart] when the device transitions from
/// stationary to moving and the SDK opens a new trip. Every location and
/// driving event recorded until the matching `onTrip` carries this [tripId],
/// which makes it the join key between those records and the trip summary.
///
/// Before this event existed a trip only became observable once it was over,
/// so an app that wanted to group records by trip had to re-derive the
/// boundary from motion changes and would drift from the SDK's own detection.
@immutable
class TripStartEvent {
  /// Creates a new [TripStartEvent].
  const TripStartEvent({
    required this.tripId,
    required this.startedAt,
    this.startLocation,
  });

  /// Creates a [TripStartEvent] from a platform map.
  factory TripStartEvent.fromMap(Map<String, Object?> map) {
    final startMap = safeMap(map['startLocation']);
    final startedAtMs = map['startedAt'];
    return TripStartEvent(
      tripId: map['tripId'] as String? ?? '',
      startedAt: DateTime.fromMillisecondsSinceEpoch(
        startedAtMs is int
            ? startedAtMs
            : startedAtMs is BigInt
            ? startedAtMs.toInt()
            : startedAtMs is num
            ? startedAtMs.toInt()
            : DateTime.now().millisecondsSinceEpoch,
      ),
      // A trip can open before any fix has been resolved, in which case the
      // SDK knows the trip began but not where.
      startLocation: startMap == null || startMap.isEmpty
          ? null
          : Location.fromMap(startMap.cast<String, Object?>()),
    );
  }

  /// The trip's identifier — a UUIDv4 minted by the SDK at trip start.
  ///
  /// Treat it as opaque: it carries no information and does not sort
  /// chronologically. Order trips by [startedAt] instead.
  final String tripId;

  /// When the trip started.
  final DateTime startedAt;

  /// Where the trip started, or `null` if no fix was available yet.
  final Location? startLocation;

  /// Serializes to a map.
  Map<String, Object?> toMap() => <String, Object?>{
    'tripId': tripId,
    'startedAt': startedAt.millisecondsSinceEpoch,
    'startLocation': startLocation?.toMap(),
  };

  @override
  String toString() => 'TripStartEvent(tripId: $tripId, startedAt: $startedAt)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TripStartEvent &&
          runtimeType == other.runtimeType &&
          tripId == other.tripId &&
          startedAt == other.startedAt &&
          startLocation == other.startLocation;

  @override
  int get hashCode => Object.hash(tripId, startedAt, startLocation);
}
