import 'package:meta/meta.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

import '_helpers.dart';

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
    this.mockLocationsDetected = false,
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

  /// Whether mock/spoofed locations have been detected.
  ///
  /// Fires `true` when the first mock location is encountered. On Android
  /// this is derived from `Location.isMock()` / `isFromMockProvider()`. On
  /// iOS 15+ from `CLLocation.sourceInformation?.isSimulatedBySoftware`.
  /// Always `false` on Web and iOS < 15.
  final bool mockLocationsDetected;

  /// Creates a [ProviderChangeEvent] from a platform map.
  factory ProviderChangeEvent.fromMap(Map<String, Object?> map) {
    return ProviderChangeEvent(
      enabled: ensureBool(map['enabled'], fallback: false),
      status:
          AuthorizationStatus.values[ensureInt(
            map['status'],
            fallback: 0,
          ).clamp(0, AuthorizationStatus.values.length - 1)],
      gps: ensureBool(map['gps'], fallback: false),
      network: ensureBool(map['network'], fallback: false),
      accuracyAuthorization:
          AccuracyAuthorization.values[ensureInt(
            map['accuracyAuthorization'],
            fallback: 0,
          ).clamp(0, AccuracyAuthorization.values.length - 1)],
      mockLocationsDetected: ensureBool(
        map['mockLocationsDetected'],
        fallback: false,
      ),
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
      'mockLocationsDetected': mockLocationsDetected,
    };
  }

  @override
  String toString() =>
      'ProviderChangeEvent(enabled: $enabled, status: $status, '
      'accuracy: $accuracyAuthorization, '
      'mockLocationsDetected: $mockLocationsDetected)';

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
