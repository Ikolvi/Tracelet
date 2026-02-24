import 'dart:async';

/// Central event dispatcher for Tracelet web.
///
/// Replaces the native EventChannel mechanism. The app-facing `Tracelet`
/// class listens on EventChannels, but on web we register stream controllers
/// directly via the Flutter plugin registrant and emit events here.
///
/// Events are broadcast streams so multiple listeners can subscribe.
class WebEventDispatcher {
  // ---------------------------------------------------------------------------
  // Stream controllers (broadcast)
  // ---------------------------------------------------------------------------

  final StreamController<Map<String, Object?>> _locationController =
      StreamController<Map<String, Object?>>.broadcast();

  final StreamController<Map<String, Object?>> _motionChangeController =
      StreamController<Map<String, Object?>>.broadcast();

  final StreamController<Map<String, Object?>> _activityChangeController =
      StreamController<Map<String, Object?>>.broadcast();

  final StreamController<Map<String, Object?>> _providerChangeController =
      StreamController<Map<String, Object?>>.broadcast();

  final StreamController<Map<String, Object?>> _geofenceController =
      StreamController<Map<String, Object?>>.broadcast();

  final StreamController<Map<String, Object?>> _geofencesChangeController =
      StreamController<Map<String, Object?>>.broadcast();

  final StreamController<Map<String, Object?>> _heartbeatController =
      StreamController<Map<String, Object?>>.broadcast();

  final StreamController<Map<String, Object?>> _httpController =
      StreamController<Map<String, Object?>>.broadcast();

  final StreamController<Map<String, Object?>> _scheduleController =
      StreamController<Map<String, Object?>>.broadcast();

  final StreamController<bool> _powerSaveChangeController =
      StreamController<bool>.broadcast();

  final StreamController<Map<String, Object?>> _connectivityChangeController =
      StreamController<Map<String, Object?>>.broadcast();

  final StreamController<bool> _enabledChangeController =
      StreamController<bool>.broadcast();

  final StreamController<String> _notificationActionController =
      StreamController<String>.broadcast();

  final StreamController<Map<String, Object?>> _authorizationController =
      StreamController<Map<String, Object?>>.broadcast();

  final StreamController<Map<String, Object?>> _watchPositionController =
      StreamController<Map<String, Object?>>.broadcast();

  // ---------------------------------------------------------------------------
  // Public streams
  // ---------------------------------------------------------------------------

  Stream<Map<String, Object?>> get onLocation => _locationController.stream;
  Stream<Map<String, Object?>> get onMotionChange =>
      _motionChangeController.stream;
  Stream<Map<String, Object?>> get onActivityChange =>
      _activityChangeController.stream;
  Stream<Map<String, Object?>> get onProviderChange =>
      _providerChangeController.stream;
  Stream<Map<String, Object?>> get onGeofence => _geofenceController.stream;
  Stream<Map<String, Object?>> get onGeofencesChange =>
      _geofencesChangeController.stream;
  Stream<Map<String, Object?>> get onHeartbeat => _heartbeatController.stream;
  Stream<Map<String, Object?>> get onHttp => _httpController.stream;
  Stream<Map<String, Object?>> get onSchedule => _scheduleController.stream;
  Stream<bool> get onPowerSaveChange => _powerSaveChangeController.stream;
  Stream<Map<String, Object?>> get onConnectivityChange =>
      _connectivityChangeController.stream;
  Stream<bool> get onEnabledChange => _enabledChangeController.stream;
  Stream<String> get onNotificationAction =>
      _notificationActionController.stream;
  Stream<Map<String, Object?>> get onAuthorization =>
      _authorizationController.stream;
  Stream<Map<String, Object?>> get onWatchPosition =>
      _watchPositionController.stream;

  // ---------------------------------------------------------------------------
  // Emit methods
  // ---------------------------------------------------------------------------

  void emitLocation(Map<String, Object?> location) {
    if (!_locationController.isClosed) _locationController.add(location);
  }

  void emitMotionChange(Map<String, Object?> location) {
    if (!_motionChangeController.isClosed) {
      _motionChangeController.add(location);
    }
  }

  void emitActivityChange(Map<String, Object?> event) {
    if (!_activityChangeController.isClosed) {
      _activityChangeController.add(event);
    }
  }

  void emitProviderChange(Map<String, Object?> event) {
    if (!_providerChangeController.isClosed) {
      _providerChangeController.add(event);
    }
  }

  void emitGeofence(Map<String, Object?> event) {
    if (!_geofenceController.isClosed) _geofenceController.add(event);
  }

  void emitGeofencesChange(Map<String, Object?> event) {
    if (!_geofencesChangeController.isClosed) {
      _geofencesChangeController.add(event);
    }
  }

  void emitHeartbeat(Map<String, Object?> location) {
    if (!_heartbeatController.isClosed) {
      _heartbeatController.add(<String, Object?>{'location': location});
    }
  }

  void emitHttp(Map<String, Object?> event) {
    if (!_httpController.isClosed) _httpController.add(event);
  }

  void emitSchedule(Map<String, Object?> state) {
    if (!_scheduleController.isClosed) _scheduleController.add(state);
  }

  void emitConnectivityChange(bool connected) {
    if (!_connectivityChangeController.isClosed) {
      _connectivityChangeController.add(<String, Object?>{
        'connected': connected,
      });
    }
  }

  void emitEnabledChange(bool enabled) {
    if (!_enabledChangeController.isClosed) {
      _enabledChangeController.add(enabled);
    }
  }

  void emitAuthorization(Map<String, Object?> event) {
    if (!_authorizationController.isClosed) _authorizationController.add(event);
  }

  void emitWatchPosition(Map<String, Object?> location) {
    if (!_watchPositionController.isClosed) {
      _watchPositionController.add(location);
    }
  }

  // ---------------------------------------------------------------------------
  // Logging (internal — appended to in-memory log)
  // ---------------------------------------------------------------------------

  final List<String> _logs = <String>[];

  void log(String level, String message) {
    final ts = DateTime.now().toIso8601String();
    _logs.add('[$ts] [$level] $message');
    // Trim to last 10 000 entries.
    if (_logs.length > 10000) {
      _logs.removeRange(0, _logs.length - 10000);
    }
  }

  String getLog() => _logs.join('\n');

  void clearLog() => _logs.clear();

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  void dispose() {
    _locationController.close();
    _motionChangeController.close();
    _activityChangeController.close();
    _providerChangeController.close();
    _geofenceController.close();
    _geofencesChangeController.close();
    _heartbeatController.close();
    _httpController.close();
    _scheduleController.close();
    _powerSaveChangeController.close();
    _connectivityChangeController.close();
    _enabledChangeController.close();
    _notificationActionController.close();
    _authorizationController.close();
    _watchPositionController.close();
  }
}
