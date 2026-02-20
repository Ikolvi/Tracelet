import 'package:meta/meta.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

import 'config.dart';

/// The current state of the Tracelet plugin.
///
/// Returned by lifecycle methods like [Tracelet.ready], [Tracelet.start],
/// [Tracelet.stop], and [Tracelet.getState].
@immutable
class State {
  /// Creates a new [State].
  const State({
    required this.enabled,
    required this.trackingMode,
    this.schedulerEnabled = false,
    this.odometer = 0.0,
    this.didLaunchInBackground = false,
    this.didDeviceReboot = false,
    this.config,
  });

  /// Whether tracking is currently active.
  final bool enabled;

  /// The current tracking mode.
  final TrackingMode trackingMode;

  /// Whether the scheduler is active.
  final bool schedulerEnabled;

  /// Current odometer value in meters.
  final double odometer;

  /// Whether the app was launched in the background (e.g. from a boot event
  /// or scheduled task).
  final bool didLaunchInBackground;

  /// Whether the device recently rebooted and tracking was restarted.
  final bool didDeviceReboot;

  /// Snapshot of the current configuration, if available.
  final Config? config;

  /// Creates a [State] from a platform map.
  factory State.fromMap(Map<String, Object?> map) {
    final configMap = _safeMap(map['config']);

    return State(
      enabled: _ensureBool(map['enabled'], fallback: false),
      trackingMode: TrackingMode.values[
          _ensureInt(map['trackingMode'], fallback: 0)
              .clamp(0, TrackingMode.values.length - 1)],
      schedulerEnabled:
          _ensureBool(map['schedulerEnabled'], fallback: false),
      odometer: _ensureDouble(map['odometer'], fallback: 0.0),
      didLaunchInBackground:
          _ensureBool(map['didLaunchInBackground'], fallback: false),
      didDeviceReboot:
          _ensureBool(map['didDeviceReboot'], fallback: false),
      config: configMap != null ? Config.fromMap(configMap) : null,
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'enabled': enabled,
      'trackingMode': trackingMode.index,
      'schedulerEnabled': schedulerEnabled,
      'odometer': odometer,
      'didLaunchInBackground': didLaunchInBackground,
      'didDeviceReboot': didDeviceReboot,
      'config': config?.toMap(),
    };
  }

  @override
  String toString() =>
      'State(enabled: $enabled, trackingMode: $trackingMode, '
      'odometer: ${odometer.toStringAsFixed(1)}m)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is State &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          trackingMode == other.trackingMode &&
          schedulerEnabled == other.schedulerEnabled;

  @override
  int get hashCode => Object.hash(enabled, trackingMode, schedulerEnabled);
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

double _ensureDouble(Object? value, {required double fallback}) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return fallback;
}

Map<String, Object?>? _safeMap(Object? value) {
  if (value == null) return null;
  if (value is Map<String, Object?>) return value;
  if (value is Map) return Map<String, Object?>.from(value);
  return null;
}
