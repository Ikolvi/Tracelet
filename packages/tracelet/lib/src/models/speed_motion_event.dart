import 'package:meta/meta.dart';
import 'package:tracelet/tracelet.dart' show MotionConfig, Tracelet;
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

/// Motion detection strategy.
///
/// - [accelerometer]: default. Uses raw accelerometer (and optional
///   platform Activity Recognition) to detect stationary↔moving transitions.
/// - [speed]: uses GPS speed from each location fix. Immune to the
///   "phone still on moving vehicle" false-stationarity problem.
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
  /// machine applies [MotionConfig.stationaryTrackingMode] when it detects
  /// that the device is stationary.
  speed,

  /// Hybrid motion detection mode.
  ///
  /// Combines the accelerometer's instant wake-up capabilities with the
  /// GPS-speed state machine to prevent false stops on smooth roads
  /// (e.g. driving on a highway with the phone flat on the dashboard).
  smart,
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

  /// Keep continuous location updates while stationary.
  /// Apply [MotionConfig.stationaryPeriodicAccuracy] if it is coarser than
  /// the normal request, then restore the normal accuracy on movement.
  continuous,
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
  /// [StationaryTrackingMode].
  stationary,
}

/// Underlying tracking mode reported alongside a [SpeedMotionEvent].
enum SpeedMotionTrackingMode {
  /// Continuous location updates, including when [SpeedMotionState.stationary]
  /// with [StationaryTrackingMode.continuous].
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
/// Fires in [MotionDetectionMode.speed] and [MotionDetectionMode.smart].
/// Subscribe via [Tracelet.onMotionModeChange] or
/// [Tracelet.motionModeChangeStream].
@immutable
class SpeedMotionEvent {
  /// Creates a new [SpeedMotionEvent].
  const SpeedMotionEvent({
    required this.state,
    required this.previousState,
    required this.trackingMode,
  });

  /// Creates a [SpeedMotionEvent] from a Pigeon [TlSpeedMotionEvent].
  ///
  /// Used internally by the platform bridge to convert typed Pigeon
  /// messages into the public Dart model.
  factory SpeedMotionEvent.fromTl(TlSpeedMotionEvent event) {
    return SpeedMotionEvent(
      state: _mapStateFromTl(event.state),
      previousState: _mapStateFromTl(event.previousState),
      trackingMode: _mapTrackingModeFromTl(event.trackingMode),
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

  /// The new state after this transition.
  final SpeedMotionState state;

  /// The previous state before this transition.
  final SpeedMotionState previousState;

  /// The underlying tracking mode after the transition.
  final SpeedMotionTrackingMode trackingMode;

  /// Serializes to a map for test round-tripping and headless dispatch.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'state': state.index,
      'previousState': previousState.index,
      'trackingMode': trackingMode.index,
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

  static SpeedMotionState _mapStateFromTl(TlSpeedMotionState tlState) {
    switch (tlState) {
      case TlSpeedMotionState.moving:
        return SpeedMotionState.moving;
      case TlSpeedMotionState.slowing:
        return SpeedMotionState.slowing;
      case TlSpeedMotionState.stationary:
        return SpeedMotionState.stationary;
    }
  }

  static SpeedMotionTrackingMode _mapTrackingModeFromTl(TlTrackingMode tlMode) {
    switch (tlMode) {
      case TlTrackingMode.location:
        return SpeedMotionTrackingMode.continuous;
      case TlTrackingMode.geofences:
        return SpeedMotionTrackingMode.geofences;
      case TlTrackingMode.periodic:
        return SpeedMotionTrackingMode.periodic;
    }
  }

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
