import 'package:meta/meta.dart';

/// Context passed to a custom sync body builder callback.
///
/// Contains the locations about to be synced, the unsynced telematics/crash
/// events when `syncTelematics` is enabled, and any completed-trip summaries
/// not yet delivered (#401). The builder returns a
/// `Map<String, Object?>` that becomes the full HTTP request body, giving
/// integrators full control over the JSON structure.
///
/// ```dart
/// Tracelet.setSyncBodyBuilder((context) {
///   return {
///     'deviceId': myDeviceId,
///     'taskId': currentTaskId,
///     'points': context.locations,
///     'events': context.telematics, // driving/crash events (#214)
///     'trips': context.trips, // completed-trip summaries (#401)
///     'sentAt': DateTime.now().toIso8601String(),
///   };
/// });
/// ```
@immutable
class SyncBodyContext {
  /// Creates a new [SyncBodyContext].
  const SyncBodyContext({
    required this.locations,
    this.telematics = const <Map<String, Object?>>[],
    this.trips = const <Map<String, Object?>>[],
  });

  /// Creates a [SyncBodyContext] from a map.
  ///
  /// Accepts both shapes for backward compatibility:
  ///  * **Map** — `{locations: [...], telematics: [...]}` (current native bridge).
  ///  * **List** — a bare list of location maps (older native versions). When the
  ///    raw payload is a List it is treated as `locations` with empty telematics,
  ///    so a native/Dart version skew never breaks the custom builder.
  factory SyncBodyContext.fromMap(Map<String, Object?> map) {
    return SyncBodyContext(
      locations: _mapList(map['locations']),
      telematics: _mapList(map['telematics']),
      trips: _mapList(map['trips']),
    );
  }

  /// Builds a [SyncBodyContext] from the raw platform argument, which may be
  /// either the new `{locations, telematics}` map or a legacy bare location list.
  factory SyncBodyContext.fromPlatform(Object? raw) {
    if (raw is Map) {
      return SyncBodyContext.fromMap(Map<String, Object?>.from(raw));
    }
    // Legacy: a bare List of location maps.
    return SyncBodyContext(locations: _mapList(raw));
  }

  static List<Map<String, Object?>> _mapList(Object? raw) {
    final out = <Map<String, Object?>>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) out.add(Map<String, Object?>.from(item));
      }
    }
    return out;
  }

  /// The location maps about to be synced.
  ///
  /// Each map contains the same keys as [Location.toMap()]. The builder
  /// can reshape, filter, or enrich these as needed.
  final List<Map<String, Object?>> locations;

  /// The unsynced telematics / crash-fall events about to be synced (#214).
  ///
  /// Populated only when `HttpConfig.syncTelematics` is enabled; otherwise empty.
  /// Each map carries `id`, `event_type`, `severity`, `latitude`, `longitude`,
  /// `timestamp`, `synced`.
  final List<Map<String, Object?>> telematics;

  /// Completed-trip summaries not yet delivered (#401), in the same shape as
  /// the default payload's `trips` array: `trip_id`, `started_at`, `ended_at`,
  /// `distance` (m), `duration` (s), `average_speed` (m/s), `start_location`,
  /// `stop_location`, `synced`.
  ///
  /// Include them in the body you return: a trip handed to the builder is
  /// marked delivered once the request succeeds, and is not offered again.
  /// Empty when there are none, and from native versions before #401.
  final List<Map<String, Object?>> trips;

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'locations': locations,
      'telematics': telematics,
      'trips': trips,
    };
  }
}
