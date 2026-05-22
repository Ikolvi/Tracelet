import 'package:meta/meta.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

/// Motion detection strategy.
///
/// - [accelerometer]: default. Uses raw accelerometer (and optional
///   platform Activity Recognition) to detect stationary↔moving transitions.
/// - [speed]: uses GPS speed from each location fix. Immune to the
///   "phone still on moving vehicle" false-stationarity problem. Drives
///   automatic switching between continuous and periodic tracking.
enum MotionDetectionMode {
  /// Legacy accelerometer-driven stop detection.
  ///
  /// All of `shakeThreshold`, `stillThreshold`, `stillSampleCount`,
  /// `stopTimeout`, and the Activity Recognition settings apply.
  accelerometer,

  /// GPS-speed-driven state machine.
  ///
  /// Use for vehicle-tracking scenarios where a phone on a dashboard
  /// reads near-zero accelerometer values at highway speed. The state
  /// machine switches between continuous tracking and low-power periodic
  /// fixes automatically based on [MotionConfig.speedMovingThreshold].
  speed,
}

/// Tracking mode to use when the speed-based state machine enters the
/// stationary state.
enum StationaryTrackingMode {
  /// Schedule one-shot fixes at [MotionConfig.stationaryPeriodicInterval].
  /// GPS radio is off between fixes. Default.
  periodic,

  /// Stop continuous tracking and rely on existing geofence monitoring.
  /// Wake speed is evaluated on any geofence-triggered fix.
  geofences,
}

/// States of the speed-based motion state machine.
///
/// ```
///   MOVING ──(speed < threshold)──▶ SLOWING
///     ▲                                │
///     │                      (delay elapses)
///     │                                ▼
///     └──(speed ≥ threshold)── STATIONARY
/// ```
enum SpeedMotionState {
  /// Normal continuous tracking; speed exceeds threshold.
  moving,

  /// Continuous tracking; speed has dropped below threshold but the
  /// stationary-confirmation countdown has not yet elapsed.
  slowing,

  /// Stationary; tracking has switched to the configured
  /// [StationaryTrackingMode] (periodic one-shot fixes or geofences).
  stationary,
}

/// Underlying tracking mode reported alongside a [SpeedMotionEvent].
enum SpeedMotionTrackingMode {
  /// Full continuous GPS tracking (used in [SpeedMotionState.moving]
  /// and [SpeedMotionState.slowing]).
  continuous,

  /// Periodic one-shot fixes (used in [SpeedMotionState.stationary]
  /// when [StationaryTrackingMode.periodic] is configured).
  periodic,

  /// Geofence-only monitoring (used in [SpeedMotionState.stationary]
  /// when [StationaryTrackingMode.geofences] is configured).
  geofences,
}

/// Event fired when the speed-based motion state machine transitions
/// between states, or when the underlying tracking mode switches.
///
/// Only fires when [MotionDetectionMode.speed] is active. Subscribe via
/// [Tracelet.onMotionModeChange] or [Tracelet.motionModeChangeStream].
@immutable
class SpeedMotionEvent {
  /// Creates a new [SpeedMotionEvent].
  const SpeedMotionEvent({
    required this.state,
    required this.previousState,
    required this.trackingMode,
  });

  /// The new state after this transition.
  final SpeedMotionState state;

  /// The previous state before this transition.
  final SpeedMotionState previousState;

  /// The underlying tracking mode after the transition.
  final SpeedMotionTrackingMode trackingMode;

  /// Creates a [SpeedMotionEvent] from a Pigeon [TlSpeedMotionEvent].
  ///
  /// Used internally by the platform bridge to convert typed Pigeon
  /// messages into the public Dart model.
  factory SpeedMotionEvent.fromTl(TlSpeedMotionEvent event) {
    return SpeedMotionEvent(
      state: _parseState(event.state),
      previousState: _parseState(event.previousState),
      trackingMode: _parseTrackingMode(event.trackingMode),
    );
  }

  /// Creates a [SpeedMotionEvent] from a map (used by headless callbacks
  /// and tests).
  factory SpeedMotionEvent.fromMap(Map<String, Object?> map) {
    return SpeedMotionEvent(
      state: _parseState(map['state']),
      previousState: _parseState(map['previousState']),
      trackingMode: _parseTrackingMode(map['trackingMode']),
    );
  }

  /// Serializes to a map for test round-tripping and headless dispatch.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'state': state.name,
      'previousState': previousState.name,
      'trackingMode': trackingMode.name,
    };
  }

  @override
  String toString() =>
      'SpeedMotionEvent($previousState → $state, trackingMode: $trackingMode)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpeedMotionEvent &&
          runtimeType == other.runtimeType &&
          state == other.state &&
          previousState == other.previousState &&
          trackingMode == other.trackingMode;

  @override
  int get hashCode => Object.hash(state, previousState, trackingMode);

  /// Parses a state value from either a String name or an int index.
  ///
  /// Defaults to [SpeedMotionState.moving] for unrecognized values,
  /// since "moving" is the safest assumption (keeps tracking active).
  static SpeedMotionState _parseState(Object? raw) {
    if (raw is String) {
      return SpeedMotionState.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => SpeedMotionState.moving,
      );
    }
    if (raw is int) {
      return SpeedMotionState.values[raw.clamp(
        0,
        SpeedMotionState.values.length - 1,
      )];
    }
    return SpeedMotionState.moving;
  }

  /// Parses a tracking mode value from either a String name or an int index.
  ///
  /// Defaults to [SpeedMotionTrackingMode.continuous] for unrecognized
  /// values, since continuous tracking is the safest fallback.
  static SpeedMotionTrackingMode _parseTrackingMode(Object? raw) {
    if (raw is String) {
      return SpeedMotionTrackingMode.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => SpeedMotionTrackingMode.continuous,
      );
    }
    if (raw is int) {
      return SpeedMotionTrackingMode.values[raw.clamp(
        0,
        SpeedMotionTrackingMode.values.length - 1,
      )];
    }
    return SpeedMotionTrackingMode.continuous;
  }
}
