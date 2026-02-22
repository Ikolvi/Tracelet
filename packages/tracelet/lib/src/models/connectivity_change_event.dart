import 'package:meta/meta.dart';

import '_helpers.dart';

/// Event fired when network connectivity changes.
@immutable
class ConnectivityChangeEvent {
  /// Creates a new [ConnectivityChangeEvent].
  const ConnectivityChangeEvent({required this.connected});

  /// Whether the device currently has network connectivity.
  final bool connected;

  /// Creates a [ConnectivityChangeEvent] from a platform map.
  factory ConnectivityChangeEvent.fromMap(Map<String, Object?> map) {
    return ConnectivityChangeEvent(
      connected: ensureBool(map['connected'], fallback: false),
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{'connected': connected};
  }

  @override
  String toString() => 'ConnectivityChangeEvent(connected: $connected)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectivityChangeEvent &&
          runtimeType == other.runtimeType &&
          connected == other.connected;

  @override
  int get hashCode => connected.hashCode;
}
