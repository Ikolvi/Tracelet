import 'generated/tracelet_api.g.dart';
import 'pigeon_event_receiver.dart';
import 'tracelet_platform.dart';

/// A [TraceletPlatform] implementation backed by Pigeon-generated code.
///
/// All request/response methods delegate to [TraceletHostApi], which routes
/// to the native Kotlin/Swift implementation via Pigeon's type-safe codegen.
///
/// All streaming events are received via [TraceletEventApi] (Pigeon FlutterApi)
/// and exposed as typed [Stream]s through [PigeonEventReceiver].
class PigeonTracelet extends TraceletPlatform {
  PigeonTracelet({TraceletHostApi? api, PigeonEventReceiver? eventReceiver})
    : _api = api ?? TraceletHostApi(),
      _events = eventReceiver ?? PigeonEventReceiver();

  final TraceletHostApi _api;
  final PigeonEventReceiver _events;
  bool _eventsRegistered = false;

  /// Lazily registers [_events] with [TraceletEventApi] on first stream access.
  void _ensureEventsRegistered() {
    if (!_eventsRegistered) {
      _eventsRegistered = true;
      TraceletEventApi.setUp(_events);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Map<String, Object?> _stateToMap(TlState s) => <String, Object?>{
    'enabled': s.enabled,
    'isMoving': s.isMoving,
    'trackingMode': s.trackingMode,
    'schedulerEnabled': s.schedulerEnabled,
    'odometer': s.odometer,
    'lastLocationTimestamp': s.lastLocationTimestamp,
  };

  Map<String, Object?> _locationToMap(TlLocation l) => <String, Object?>{
    'coords': <String, Object?>{
      'latitude': l.coords.latitude,
      'longitude': l.coords.longitude,
      'accuracy': l.coords.accuracy,
      'speed': l.coords.speed,
      'heading': l.coords.heading,
      'altitude': l.coords.altitude,
      'altitudeAccuracy': l.coords.altitudeAccuracy,
      'speedAccuracy': l.coords.speedAccuracy,
      'headingAccuracy': l.coords.headingAccuracy,
      'ellipsoidalAltitude': l.coords.ellipsoidalAltitude,
      'floor': l.coords.floor,
    },
    'battery': <String, Object?>{
      'level': l.battery.level,
      'isCharging': l.battery.isCharging,
    },
    'timestamp': l.timestamp,
    'uuid': l.uuid,
    'isMoving': l.isMoving,
    'odometer': l.odometer,
    'event': l.event,
    'activity': l.activity != null
        ? <String, Object?>{
            'type': l.activity!.type,
            'confidence': l.activity!.confidence,
          }
        : null,
    'extras': l.extras,
  };

  Map<String, Object?> _geofenceToMap(TlGeofence g) => <String, Object?>{
    'identifier': g.identifier,
    'latitude': g.latitude,
    'longitude': g.longitude,
    'radius': g.radius,
    'notifyOnEntry': g.notifyOnEntry,
    'notifyOnExit': g.notifyOnExit,
    'notifyOnDwell': g.notifyOnDwell,
    'loiteringDelay': g.loiteringDelay,
    'extras': g.extras,
    'vertices': g.vertices,
  };

  TlGeofence _mapToGeofence(Map<String, Object?> m) => TlGeofence(
    identifier: m['identifier']! as String,
    latitude: (m['latitude']! as num).toDouble(),
    longitude: (m['longitude']! as num).toDouble(),
    radius: (m['radius']! as num).toDouble(),
    notifyOnEntry: m['notifyOnEntry'] as bool? ?? true,
    notifyOnExit: m['notifyOnExit'] as bool? ?? true,
    notifyOnDwell: m['notifyOnDwell'] as bool? ?? false,
    loiteringDelay: m['loiteringDelay'] as int? ?? 0,
  );

  TlCurrentPositionOptions _mapToOptions(Map<String, Object?> m) =>
      TlCurrentPositionOptions(
        timeout: m['timeout'] as int? ?? 30,
        maximumAge: m['maximumAge'] as int? ?? 0,
        persist: m['persist'] as bool? ?? true,
        samples: m['samples'] as int? ?? 1,
      );

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>> ready(Map<String, Object?> config) async {
    final state = await _api.ready(config);
    return _stateToMap(state);
  }

  @override
  Future<Map<String, Object?>> start() async {
    return _stateToMap(await _api.start());
  }

  @override
  Future<Map<String, Object?>> stop() async {
    return _stateToMap(await _api.stop());
  }

  @override
  Future<Map<String, Object?>> startGeofences() async {
    return _stateToMap(await _api.startGeofences());
  }

  @override
  Future<Map<String, Object?>> startPeriodic() async {
    return _stateToMap(await _api.startPeriodic());
  }

  @override
  Future<Map<String, Object?>> getState() async {
    return _stateToMap(await _api.getState());
  }

  @override
  Future<Map<String, Object?>> setConfig(Map<String, Object?> config) async {
    return _stateToMap(await _api.setConfig(config));
  }

  @override
  Future<Map<String, Object?>> reset([Map<String, Object?>? config]) async {
    return _stateToMap(await _api.reset(config));
  }

  // ---------------------------------------------------------------------------
  // Location
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>> getCurrentPosition(
    Map<String, Object?> options,
  ) async {
    final location = await _api.getCurrentPosition(_mapToOptions(options));
    return _locationToMap(location);
  }

  @override
  Future<Map<String, Object?>> getLastKnownLocation([
    Map<String, Object?>? options,
  ]) async {
    final location = await _api.getLastKnownLocation(options);
    if (location == null) return <String, Object?>{};
    return _locationToMap(location);
  }

  @override
  Future<int> watchPosition(Map<String, Object?> options) =>
      _api.watchPosition(options);

  @override
  Future<bool> stopWatchPosition(int watchId) =>
      _api.stopWatchPosition(watchId);

  @override
  Future<bool> changePace(bool isMoving) => _api.changePace(isMoving);

  @override
  Future<double> getOdometer() => _api.getOdometer();

  @override
  Future<Map<String, Object?>> setOdometer(double value) async {
    return _locationToMap(await _api.setOdometer(value));
  }

  // ---------------------------------------------------------------------------
  // Geofencing
  // ---------------------------------------------------------------------------

  @override
  Future<bool> addGeofence(Map<String, Object?> geofence) =>
      _api.addGeofence(_mapToGeofence(geofence));

  @override
  Future<bool> addGeofences(List<Map<String, Object?>> geofences) =>
      _api.addGeofences(geofences.map(_mapToGeofence).toList());

  @override
  Future<bool> removeGeofence(String identifier) =>
      _api.removeGeofence(identifier);

  @override
  Future<bool> removeGeofences() => _api.removeGeofences();

  @override
  Future<List<Map<String, Object?>>> getGeofences() async {
    final geofences = await _api.getGeofences();
    return geofences.map(_geofenceToMap).toList();
  }

  @override
  Future<Map<String, Object?>?> getGeofence(String identifier) async {
    final g = await _api.getGeofence(identifier);
    return g != null ? _geofenceToMap(g) : null;
  }

  @override
  Future<bool> geofenceExists(String identifier) =>
      _api.geofenceExists(identifier);

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  @override
  Future<List<Map<String, Object?>>> getLocations([
    Map<String, Object?>? query,
  ]) async {
    final locations = await _api.getLocations(query);
    return locations.map(_locationToMap).toList();
  }

  @override
  Future<int> getCount([Map<String, Object?>? query]) => _api.getCount(query);

  @override
  Future<bool> destroyLocations() => _api.destroyLocations();

  @override
  Future<bool> destroyLocation(String uuid) => _api.destroyLocation(uuid);

  @override
  Future<String> insertLocation(Map<String, Object?> params) =>
      _api.insertLocation(params);

  // ---------------------------------------------------------------------------
  // HTTP Sync
  // ---------------------------------------------------------------------------

  @override
  Future<List<Map<String, Object?>>> sync() async {
    final locations = await _api.sync();
    return locations.map(_locationToMap).toList();
  }

  @override
  Future<bool> setDynamicHeaders(Map<String, String> headers) =>
      _api.setDynamicHeaders(headers);

  @override
  Future<bool> setRouteContext(Map<String, Object?> context) =>
      _api.setRouteContext(context);

  @override
  Future<bool> clearRouteContext() => _api.clearRouteContext();

  // ---------------------------------------------------------------------------
  // Permissions
  // ---------------------------------------------------------------------------

  @override
  Future<int> getPermissionStatus() async {
    final status = await _api.getPermissionStatus();
    return status.index;
  }

  @override
  Future<int> requestPermission() async {
    final status = await _api.requestPermission();
    return status.index;
  }

  @override
  Future<int> getNotificationPermissionStatus() =>
      _api.getNotificationPermissionStatus();

  @override
  Future<int> requestNotificationPermission() =>
      _api.requestNotificationPermission();

  @override
  Future<bool> canScheduleExactAlarms() => _api.canScheduleExactAlarms();

  @override
  Future<bool> openExactAlarmSettings() => _api.openExactAlarmSettings();

  @override
  Future<int> getMotionPermissionStatus() => _api.getMotionPermissionStatus();

  @override
  Future<int> requestMotionPermission() => _api.requestMotionPermission();

  @override
  Future<int> requestTemporaryFullAccuracy(String purpose) =>
      _api.requestTemporaryFullAccuracy(purpose);

  // ---------------------------------------------------------------------------
  // Utility
  // ---------------------------------------------------------------------------

  @override
  Future<bool> isPowerSaveMode() => _api.isPowerSaveMode();

  @override
  Future<Map<String, Object?>> getProviderState() async {
    final p = await _api.getProviderState();
    return <String, Object?>{
      'enabled': p.enabled,
      'gps': p.gps,
      'network': p.network,
      'status': p.status,
      'accuracyAuthorization': p.accuracyAuthorization,
    };
  }

  @override
  Future<Map<String, Object?>> getDeviceInfo() => _api.getDeviceInfo();

  @override
  Future<Map<String, Object?>> getSensors() => _api.getSensors();

  @override
  Future<bool> playSound(String name) => _api.playSound(name);

  @override
  Future<bool> isIgnoringBatteryOptimizations() =>
      _api.isIgnoringBatteryOptimizations();

  @override
  Future<bool> requestSettings(String action) => _api.requestSettings(action);

  @override
  Future<bool> showSettings(String action) => _api.showSettings(action);

  @override
  Future<Map<String, Object?>> getSettingsHealth() => _api.getSettingsHealth();

  @override
  Future<bool> openOemSettings(String label) => _api.openOemSettings(label);

  // ---------------------------------------------------------------------------
  // Logging
  // ---------------------------------------------------------------------------

  @override
  Future<String> getLog([Map<String, Object?>? query]) => _api.getLog(query);

  @override
  Future<bool> destroyLog() => _api.destroyLog();

  @override
  Future<bool> emailLog(String email) => _api.emailLog(email);

  @override
  Future<bool> log(String level, String message) => _api.log(level, message);

  // ---------------------------------------------------------------------------
  // Scheduling
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>> startSchedule() async {
    return _stateToMap(await _api.startSchedule());
  }

  @override
  Future<Map<String, Object?>> stopSchedule() async {
    return _stateToMap(await _api.stopSchedule());
  }

  // ---------------------------------------------------------------------------
  // Background Tasks
  // ---------------------------------------------------------------------------

  @override
  Future<int> startBackgroundTask() => _api.startBackgroundTask();

  @override
  Future<int> stopBackgroundTask(int taskId) => _api.stopBackgroundTask(taskId);

  // ---------------------------------------------------------------------------
  // Headless
  // ---------------------------------------------------------------------------

  @override
  Future<bool> registerHeadlessTask(List<int> callbackIds) =>
      _api.registerHeadlessTask(callbackIds);

  @override
  Future<bool> registerHeadlessHeadersCallback(List<int> callbackIds) =>
      _api.registerHeadlessHeadersCallback(callbackIds);

  @override
  Future<bool> registerHeadlessSyncBodyBuilder(List<int> callbackIds) =>
      _api.registerHeadlessSyncBodyBuilder(callbackIds);

  // ---------------------------------------------------------------------------
  // Enterprise: Audit Trail
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>> verifyAuditTrail() => _api.verifyAuditTrail();

  @override
  Future<Map<String, Object?>?> getAuditProof(String uuid) =>
      _api.getAuditProof(uuid);

  // ---------------------------------------------------------------------------
  // Enterprise: Privacy Zones
  // ---------------------------------------------------------------------------

  @override
  Future<bool> addPrivacyZone(Map<String, Object?> zone) =>
      _api.addPrivacyZone(zone);

  @override
  Future<bool> addPrivacyZones(List<Map<String, Object?>> zones) =>
      _api.addPrivacyZones(zones);

  @override
  Future<bool> removePrivacyZone(String identifier) =>
      _api.removePrivacyZone(identifier);

  @override
  Future<bool> removePrivacyZones() => _api.removePrivacyZones();

  @override
  Future<List<Map<String, Object?>>> getPrivacyZones() =>
      _api.getPrivacyZones();

  // ---------------------------------------------------------------------------
  // Enterprise: Encrypted Database
  // ---------------------------------------------------------------------------

  @override
  Future<bool> isDatabaseEncrypted() => _api.isDatabaseEncrypted();

  @override
  Future<bool> encryptDatabase() => _api.encryptDatabase();

  // ---------------------------------------------------------------------------
  // Enterprise: Device Attestation
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>?> getAttestationToken() =>
      _api.getAttestationToken();

  // ---------------------------------------------------------------------------
  // Enterprise: Carbon Estimator
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>> getCarbonReport([Map<String, Object?>? query]) =>
      _api.getCarbonReport(query);

  // ---------------------------------------------------------------------------
  // Enterprise: Dead Reckoning
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>?> getDeadReckoningState() =>
      _api.getDeadReckoningState();

  // ---------------------------------------------------------------------------
  // Event Streams (via PigeonEventReceiver / TraceletEventApi)
  // ---------------------------------------------------------------------------

  @override
  Stream<TlLocation> get locationEvents {
    _ensureEventsRegistered();
    return _events.locationEvents;
  }

  @override
  Stream<TlLocation> get motionChangeEvents {
    _ensureEventsRegistered();
    return _events.motionChangeEvents;
  }

  @override
  Stream<TlActivityChangeEvent> get activityChangeEvents {
    _ensureEventsRegistered();
    return _events.activityChangeEvents;
  }

  @override
  Stream<TlProviderChangeEvent> get providerChangeEvents {
    _ensureEventsRegistered();
    return _events.providerChangeEvents;
  }

  @override
  Stream<TlGeofenceEvent> get geofenceEvents {
    _ensureEventsRegistered();
    return _events.geofenceEvents;
  }

  @override
  Stream<TlGeofencesChangeEvent> get geofencesChangeEvents {
    _ensureEventsRegistered();
    return _events.geofencesChangeEvents;
  }

  @override
  Stream<TlHeartbeatEvent> get heartbeatEvents {
    _ensureEventsRegistered();
    return _events.heartbeatEvents;
  }

  @override
  Stream<TlHttpEvent> get httpEvents {
    _ensureEventsRegistered();
    return _events.httpEvents;
  }

  @override
  Stream<TlState> get scheduleEvents {
    _ensureEventsRegistered();
    return _events.scheduleEvents;
  }

  @override
  Stream<bool> get powerSaveChangeEvents {
    _ensureEventsRegistered();
    return _events.powerSaveChangeEvents;
  }

  @override
  Stream<TlConnectivityChangeEvent> get connectivityChangeEvents {
    _ensureEventsRegistered();
    return _events.connectivityChangeEvents;
  }

  @override
  Stream<bool> get enabledChangeEvents {
    _ensureEventsRegistered();
    return _events.enabledChangeEvents;
  }

  @override
  Stream<String> get notificationActionEvents {
    _ensureEventsRegistered();
    return _events.notificationActionEvents;
  }

  @override
  Stream<TlAuthorizationEvent> get authorizationEvents {
    _ensureEventsRegistered();
    return _events.authorizationEvents;
  }

  @override
  Stream<TlLocation> get watchPositionEvents {
    _ensureEventsRegistered();
    return _events.watchPositionEvents;
  }
}
