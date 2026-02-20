import 'package:meta/meta.dart';

/// Event fired when network connectivity changes.
@immutable
class ConnectivityChangeEvent {
  /// Creates a new [ConnectivityChangeEvent].
  const ConnectivityChangeEvent({
    required this.connected,
  });

  /// Whether the device currently has network connectivity.
  final bool connected;

  /// Creates a [ConnectivityChangeEvent] from a platform map.
  factory ConnectivityChangeEvent.fromMap(Map<String, Object?> map) {
    return ConnectivityChangeEvent(
      connected: _ensureBool(map['connected'], fallback: false),
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'connected': connected,
    };
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

bool _ensureBool(Object? value, {required bool fallback}) {
  if (value is bool) return value;
  if (value is int) return value != 0;
  return fallback;
}
