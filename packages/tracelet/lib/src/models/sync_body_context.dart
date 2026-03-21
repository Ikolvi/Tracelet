import 'package:meta/meta.dart';

/// Context passed to a custom sync body builder callback.
///
/// Contains the locations about to be synced. The builder returns a
/// `Map<String, Object?>` that becomes the full HTTP request body,
/// giving integrators full control over the JSON structure.
///
/// ```dart
/// Tracelet.setSyncBodyBuilder((context) {
///   return {
///     'deviceId': myDeviceId,
///     'taskId': currentTaskId,
///     'points': context.locations,
///     'sentAt': DateTime.now().toIso8601String(),
///   };
/// });
/// ```
@immutable
class SyncBodyContext {
  /// Creates a new [SyncBodyContext].
  const SyncBodyContext({required this.locations});

  /// The location maps about to be synced.
  ///
  /// Each map contains the same keys as [Location.toMap()]. The builder
  /// can reshape, filter, or enrich these as needed.
  final List<Map<String, Object?>> locations;

  /// Creates a [SyncBodyContext] from a map.
  factory SyncBodyContext.fromMap(Map<String, Object?> map) {
    final raw = map['locations'];
    final locations = <Map<String, Object?>>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          locations.add(Map<String, Object?>.from(item));
        }
      }
    }
    return SyncBodyContext(locations: locations);
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{'locations': locations};
  }
}
