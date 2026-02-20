import 'package:meta/meta.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

/// Event fired when the location provider state changes.
///
/// Reports whether GPS/network providers are enabled, the authorization
/// status, and accuracy authorization.
@immutable
class ProviderChangeEvent {
  /// Creates a new [ProviderChangeEvent].
  const ProviderChangeEvent({
    required this.enabled,
    required this.status,
    this.gps = false,
    this.network = false,
    this.accuracyAuthorization = AccuracyAuthorization.full,
  });

  /// Whether location services are globally enabled on the device.
  final bool enabled;

  /// The current authorization status.
  final AuthorizationStatus status;

  /// Whether GPS provider is enabled (Android only).
  final bool gps;

  /// Whether network provider is enabled (Android only).
  final bool network;

  /// The accuracy authorization (iOS 14+). On Android, always [AccuracyAuthorization.full].
  final AccuracyAuthorization accuracyAuthorization;

  /// Creates a [ProviderChangeEvent] from a platform map.
  factory ProviderChangeEvent.fromMap(Map<String, Object?> map) {
    return ProviderChangeEvent(
      enabled: _ensureBool(map['enabled'], fallback: false),
      status: AuthorizationStatus.values[
          _ensureInt(map['status'], fallback: 0)
              .clamp(0, AuthorizationStatus.values.length - 1)],
      gps: _ensureBool(map['gps'], fallback: false),
      network: _ensureBool(map['network'], fallback: false),
      accuracyAuthorization: AccuracyAuthorization.values[
          _ensureInt(map['accuracyAuthorization'], fallback: 0)
              .clamp(0, AccuracyAuthorization.values.length - 1)],
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'enabled': enabled,
      'status': status.index,
      'gps': gps,
      'network': network,
      'accuracyAuthorization': accuracyAuthorization.index,
    };
  }

  @override
  String toString() =>
      'ProviderChangeEvent(enabled: $enabled, status: $status, '
      'accuracy: $accuracyAuthorization)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProviderChangeEvent &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          status == other.status;

  @override
  int get hashCode => Object.hash(enabled, status);
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

bool _ensureBool(Object? value, {required bool fallback}) {
  if (value is bool) return value;
  if (value is int) return value != 0;
  return fallback;
}

int _ensureInt(Object? value, {required int fallback}) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  return fallback;
}
