import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

/// Represents a telematics event (e.g. harsh braking, crash) stored in the database.
class TelematicsRecord {
  /// Creates a [TelematicsRecord].
  const TelematicsRecord({
    required this.id,
    required this.eventType,
    required this.severity,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.synced,
    this.speed,
    this.value,
    this.tripId,
  });

  /// Converts from Pigeon [TlTelematicsRecord].
  factory TelematicsRecord.fromTl(TlTelematicsRecord tl) {
    return TelematicsRecord(
      id: tl.id,
      eventType: tl.eventType,
      severity: tl.severity,
      latitude: tl.latitude,
      longitude: tl.longitude,
      timestamp: tl.timestamp,
      synced: tl.synced,
      speed: tl.speed,
      value: tl.value,
      tripId: tl.tripId,
    );
  }

  /// The primary key.
  final int id;

  /// The type of event (e.g. "harsh_braking", "crash").
  final String eventType;

  /// The severity of the event.
  ///
  /// A normalized 0–1 measure of how far past the threshold the event was. For
  /// the physical quantity behind it, see [value].
  final double severity;

  /// Speed at the event in m/s — for an impact, the speed going in.
  ///
  /// `0` for simulated events and for events recorded before the magnitudes
  /// were persisted (#367): the stored column is non-nullable, so an upgraded
  /// install cannot tell an old row from a genuine zero. `null` only when the
  /// native side did not report the field at all.
  final double? speed;

  /// The measured magnitude that triggered the event: g for harsh driving
  /// events and impacts, km/h over the limit for speeding.
  ///
  /// `severity` is the normalized 0–1 flag; this is the physical quantity
  /// behind it. Zero and `null` mean what they do for [speed].
  final double? value;

  /// Event latitude.
  final double latitude;

  /// Event longitude.
  final double longitude;

  /// ISO8601 timestamp string.
  final String timestamp;

  /// Whether it has been synced.
  final bool synced;

  /// The trip this event was recorded during, or `null` if it happened outside
  /// one (#402).
  ///
  /// Stamped when the event was written, not when it is read, so grouping
  /// stored events by trip stays correct for a backlog recorded across several
  /// trips. Matches [TripEvent.tripId] on the summary for the same trip.
  final String? tripId;
}
