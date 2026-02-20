import 'package:meta/meta.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

/// Query parameters for reading stored locations or log entries.
///
/// ```dart
/// final locations = await Tracelet.getLocations(SQLQuery(
///   limit: 100,
///   order: LocationOrder.desc,
///   start: DateTime.now().subtract(Duration(hours: 24)),
/// ));
/// ```
@immutable
class SQLQuery {
  /// Creates a new [SQLQuery].
  const SQLQuery({
    this.start,
    this.end,
    this.limit = -1,
    this.order = LocationOrder.asc,
  });

  /// Start of the time range (inclusive). `null` means no lower bound.
  final DateTime? start;

  /// End of the time range (inclusive). `null` means no upper bound.
  final DateTime? end;

  /// Maximum number of records to return. `-1` means no limit.
  final int limit;

  /// Sort order. Defaults to [LocationOrder.asc].
  final LocationOrder order;

  /// Serializes to a map for platform channel transmission.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'start': start?.millisecondsSinceEpoch,
      'end': end?.millisecondsSinceEpoch,
      'limit': limit,
      'order': order.index,
    };
  }

  /// Creates a [SQLQuery] from a map.
  factory SQLQuery.fromMap(Map<String, Object?> map) {
    final startMs = map['start'] as int?;
    final endMs = map['end'] as int?;

    return SQLQuery(
      start: startMs != null
          ? DateTime.fromMillisecondsSinceEpoch(startMs)
          : null,
      end: endMs != null
          ? DateTime.fromMillisecondsSinceEpoch(endMs)
          : null,
      limit: (map['limit'] as int?) ?? -1,
      order: LocationOrder.values[
          ((map['order'] as int?) ?? 0)
              .clamp(0, LocationOrder.values.length - 1)],
    );
  }

  @override
  String toString() =>
      'SQLQuery(start: $start, end: $end, limit: $limit, order: $order)';
}
