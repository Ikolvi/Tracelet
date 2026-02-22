import 'package:meta/meta.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

import '_helpers.dart';
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
    this.isMoving = false,
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

  /// Whether the device is currently in a moving state.
  ///
  /// This reflects the motion-detection engine's current assessment. When
  /// `true`, the plugin is recording locations at the configured moving rate.
  /// When `false`, the plugin is in stationary mode using the geofence-based
  /// exit trigger.
  final bool isMoving;

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
    final configMap = safeMap(map['config']);

    return State(
      enabled: ensureBool(map['enabled'], fallback: false),
      trackingMode: TrackingMode.values[
          ensureInt(map['trackingMode'], fallback: 0)
              .clamp(0, TrackingMode.values.length - 1)],
      isMoving:
          ensureBool(map['isMoving'] ?? map['is_moving'], fallback: false),
      schedulerEnabled:
          ensureBool(map['schedulerEnabled'], fallback: false),
      odometer: ensureDouble(map['odometer'], fallback: 0.0),
      didLaunchInBackground:
          ensureBool(map['didLaunchInBackground'], fallback: false),
      didDeviceReboot:
          ensureBool(map['didDeviceReboot'], fallback: false),
      config: configMap != null ? Config.fromMap(configMap) : null,
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'enabled': enabled,
      'trackingMode': trackingMode.index,
      'isMoving': isMoving,
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
      'isMoving: $isMoving, odometer: ${odometer.toStringAsFixed(1)}m)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is State &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          trackingMode == other.trackingMode &&
          isMoving == other.isMoving &&
          schedulerEnabled == other.schedulerEnabled &&
          odometer == other.odometer &&
          didLaunchInBackground == other.didLaunchInBackground &&
          didDeviceReboot == other.didDeviceReboot &&
          config == other.config;

  @override
  int get hashCode => Object.hash(enabled, trackingMode, isMoving,
      schedulerEnabled, odometer, didLaunchInBackground, didDeviceReboot);
}
