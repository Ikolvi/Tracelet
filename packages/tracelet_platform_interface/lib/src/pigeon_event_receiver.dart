import 'dart:async';

import 'generated/tracelet_api.g.dart';

/// Implements [TraceletEventApi] and routes each Pigeon callback into a
/// broadcast [StreamController].
///
/// This replaces the raw EventChannel infrastructure. Native platforms
/// call the generated FlutterApi methods (e.g. `onLocation(TlLocation)`)
/// and this class forwards them into typed Dart streams.
class PigeonEventReceiver implements TraceletEventApi {
  // ---------------------------------------------------------------------------
  // Stream controllers (all broadcast so multiple listeners are supported)
  // ---------------------------------------------------------------------------

  final _locationCtrl = StreamController<TlLocation>.broadcast();
  final _motionChangeCtrl = StreamController<TlLocation>.broadcast();
  /// Controller for speed-mode state machine transitions.
  final _motionModeChangeCtrl = StreamController<TlSpeedMotionEvent>.broadcast();
  final _activityChangeCtrl =
      StreamController<TlActivityChangeEvent>.broadcast();
  final _providerChangeCtrl =
      StreamController<TlProviderChangeEvent>.broadcast();
  final _geofenceCtrl = StreamController<TlGeofenceEvent>.broadcast();
  final _geofencesChangeCtrl =
      StreamController<TlGeofencesChangeEvent>.broadcast();
  final _heartbeatCtrl = StreamController<TlHeartbeatEvent>.broadcast();
  final _httpCtrl = StreamController<TlHttpEvent>.broadcast();
  final _scheduleCtrl = StreamController<TlState>.broadcast();
  final _powerSaveChangeCtrl = StreamController<bool>.broadcast();
  final _connectivityChangeCtrl =
      StreamController<TlConnectivityChangeEvent>.broadcast();
  final _enabledChangeCtrl = StreamController<bool>.broadcast();
  final _notificationActionCtrl = StreamController<String>.broadcast();
  final _authorizationCtrl = StreamController<TlAuthorizationEvent>.broadcast();
  final _watchPositionCtrl = StreamController<TlLocation>.broadcast();

  // ---------------------------------------------------------------------------
  // Public streams
  // ---------------------------------------------------------------------------

  Stream<TlLocation> get locationEvents => _locationCtrl.stream;
  Stream<TlLocation> get motionChangeEvents => _motionChangeCtrl.stream;

  /// Fires each time the speed-based motion state machine transitions
  /// between `moving`, `slowing`, and `stationary` states.
  ///
  /// Only active when [TlMotionDetectionMode.speed] is configured.
  Stream<TlSpeedMotionEvent> get motionModeChangeEvents =>
      _motionModeChangeCtrl.stream;

  Stream<TlActivityChangeEvent> get activityChangeEvents =>
      _activityChangeCtrl.stream;
  Stream<TlProviderChangeEvent> get providerChangeEvents =>
      _providerChangeCtrl.stream;
  Stream<TlGeofenceEvent> get geofenceEvents => _geofenceCtrl.stream;
  Stream<TlGeofencesChangeEvent> get geofencesChangeEvents =>
      _geofencesChangeCtrl.stream;
  Stream<TlHeartbeatEvent> get heartbeatEvents => _heartbeatCtrl.stream;
  Stream<TlHttpEvent> get httpEvents => _httpCtrl.stream;
  Stream<TlState> get scheduleEvents => _scheduleCtrl.stream;
  Stream<bool> get powerSaveChangeEvents => _powerSaveChangeCtrl.stream;
  Stream<TlConnectivityChangeEvent> get connectivityChangeEvents =>
      _connectivityChangeCtrl.stream;
  Stream<bool> get enabledChangeEvents => _enabledChangeCtrl.stream;
  Stream<String> get notificationActionEvents => _notificationActionCtrl.stream;
  Stream<TlAuthorizationEvent> get authorizationEvents =>
      _authorizationCtrl.stream;
  Stream<TlLocation> get watchPositionEvents => _watchPositionCtrl.stream;

  // ---------------------------------------------------------------------------
  // TraceletEventApi implementation (called by native via Pigeon)
  // ---------------------------------------------------------------------------

  @override
  void onLocation(TlLocation location) => _locationCtrl.add(location);

  @override
  void onMotionChange(TlLocation location) => _motionChangeCtrl.add(location);

  @override
  void onActivityChange(TlActivityChangeEvent event) =>
      _activityChangeCtrl.add(event);

  @override
  void onProviderChange(TlProviderChangeEvent event) =>
      _providerChangeCtrl.add(event);

  @override
  void onGeofence(TlGeofenceEvent event) => _geofenceCtrl.add(event);

  @override
  void onGeofencesChange(TlGeofencesChangeEvent event) =>
      _geofencesChangeCtrl.add(event);

  @override
  void onHeartbeat(TlHeartbeatEvent event) => _heartbeatCtrl.add(event);

  @override
  void onHttp(TlHttpEvent event) => _httpCtrl.add(event);

  @override
  void onSchedule(TlState state) => _scheduleCtrl.add(state);

  @override
  void onPowerSaveChange(bool isPowerSaveMode) =>
      _powerSaveChangeCtrl.add(isPowerSaveMode);

  @override
  void onConnectivityChange(TlConnectivityChangeEvent event) =>
      _connectivityChangeCtrl.add(event);

  @override
  void onEnabledChange(bool enabled) => _enabledChangeCtrl.add(enabled);

  @override
  void onNotificationAction(String action) =>
      _notificationActionCtrl.add(action);

  @override
  void onAuthorization(TlAuthorizationEvent event) =>
      _authorizationCtrl.add(event);

  @override
  void onWatchPosition(TlLocation location) => _watchPositionCtrl.add(location);

  /// Called by native when the speed-based motion state machine transitions.
  ///
  /// Forwards the typed [TlSpeedMotionEvent] (state, previousState,
  /// trackingMode) to [motionModeChangeEvents] subscribers.
  @override
  void onMotionModeChange(TlSpeedMotionEvent event) =>
      _motionModeChangeCtrl.add(event);

  /// Closes all stream controllers. Call on plugin detach.
  void dispose() {
    _locationCtrl.close();
    _motionChangeCtrl.close();
    _activityChangeCtrl.close();
    _providerChangeCtrl.close();
    _geofenceCtrl.close();
    _geofencesChangeCtrl.close();
    _heartbeatCtrl.close();
    _httpCtrl.close();
    _scheduleCtrl.close();
    _powerSaveChangeCtrl.close();
    _connectivityChangeCtrl.close();
    _enabledChangeCtrl.close();
    _notificationActionCtrl.close();
    _authorizationCtrl.close();
    _watchPositionCtrl.close();
    _motionModeChangeCtrl.close();
  }
}
