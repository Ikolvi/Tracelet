import 'dart:async';

import 'package:tracelet_platform_interface/src/generated/tracelet_api.g.dart';
import 'package:tracelet_platform_interface/src/pigeon_event_receiver.dart';
import 'package:tracelet_platform_interface/src/tracelet_platform.dart';
import 'package:tracelet_platform_interface/src/types/enums.dart';

/// A [TraceletPlatform] implementation backed by Pigeon-generated code.
///
/// All request/response methods delegate to [TraceletHostApi], which routes
/// to the native Kotlin/Swift implementation via Pigeon's type-safe codegen.
///
/// All streaming events are received via [TraceletEventApi] (Pigeon FlutterApi)
/// and exposed as typed [Stream]s through [PigeonEventReceiver].
class PigeonTracelet extends TraceletPlatform {
  /// Creates a [PigeonTracelet] with optional overrides for the HostApi and EventReceiver.
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
      // Best-effort nudge for the native side to re-emit current state. This
      // is intentionally fire-and-forget: event registration above has already
      // succeeded, so a flush failure (e.g. no platform side in headless
      // tests, or a temporarily unreachable channel) must never surface as an
      // *uncaught* async error. Swallowing it here keeps the failure contained
      // so callers awaiting higher-level APIs (like Tracelet.ready) are not
      // taken down by a stray zone error. See issue #262.
      unawaited(_requestStateFlushSafely());
    }
  }

  /// Requests a native state flush while guaranteeing any failure is contained
  /// rather than propagating as an uncaught async error.
  Future<void> _requestStateFlushSafely() async {
    try {
      await _api.requestStateFlush();
    } catch (_) {
      // Ignored: the flush is a non-critical, best-effort re-emit of current
      // state. If the channel is unreachable there is nothing to flush and the
      // caller's awaited path is unaffected.
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Map<String, Object?> _stateToMap(TlState s) => <String, Object?>{
    'enabled': s.enabled,
    'isMoving': s.isMoving,
    'trackingMode': s.trackingMode.index,
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
    'address': l.address != null
        ? <String, Object?>{
            'street': l.address!.street,
            'city': l.address!.city,
            'state': l.address!.state,
            'postalCode': l.address!.postalCode,
            'country': l.address!.country,
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

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>> ready(TlConfig config) async {
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
  Future<Map<String, Object?>> setConfig(TlConfig config) async {
    return _stateToMap(await _api.setConfig(config));
  }

  @override
  Future<Map<String, Object?>> reset([TlConfig? config]) async {
    return _stateToMap(await _api.reset(config));
  }

  @override
  Future<void> updateNotification() => _api.updateNotification();

  // ---------------------------------------------------------------------------
  // Location
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>> getCurrentPosition(
    TlCurrentPositionOptions options,
  ) async {
    final location = await _api.getCurrentPosition(options);
    return _locationToMap(location);
  }

  @override
  Future<bool> cancelCurrentPosition(String requestId) =>
      _api.cancelCurrentPosition(requestId);

  @override
  Future<Map<String, Object?>> getLastKnownLocation([
    TlCurrentPositionOptions? options,
  ]) async {
    final location = await _api.getLastKnownLocation(options);
    if (location == null) return <String, Object?>{};
    return _locationToMap(location);
  }

  @override
  Future<int> watchPosition(TlCurrentPositionOptions options) =>
      _api.watchPosition(options);

  @override
  Future<bool> stopWatchPosition(int watchId) =>
      _api.stopWatchPosition(watchId);

  @override
  Future<bool> changePace(bool isMoving) => _api.changePace(isMoving);

  @override
  Future<bool> updateLocationProviderOptions(
    TlDesiredAccuracy? desiredAccuracy,
    double? distanceFilter,
  ) => _api.updateLocationProviderOptions(desiredAccuracy, distanceFilter);

  @override
  Future<bool> confirmImpact(int id) => _api.confirmImpact(id);

  @override
  Future<bool> cancelImpact(int id) => _api.cancelImpact(id);

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
  Future<bool> addGeofence(TlGeofence geofence) => _api.addGeofence(geofence);

  @override
  Future<bool> addGeofences(List<TlGeofence> geofences) =>
      _api.addGeofences(geofences);

  @override
  Future<bool> removeGeofence(String identifier) =>
      _api.removeGeofence(identifier);

  @override
  Future<bool> removeGeofences() => _api.removeGeofences();

  @override
  Future<List<Map<String, Object?>>> getGeofences() async {
    final geofences = await _api.getGeofences();
    return geofences.whereType<TlGeofence>().map(_geofenceToMap).toList();
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
    final locations = await _api.getLocations(query?.cast<String?, Object?>());
    return locations.whereType<TlLocation>().map(_locationToMap).toList();
  }

  @override
  Future<int> getCount([Map<String, Object?>? query]) => _api.getCount(query);

  @override
  Future<bool> destroyLocations() => _api.destroyLocations();

  @override
  Future<int> destroySyncedLocations() => _api.destroySyncedLocations();

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
    return locations.whereType<TlLocation>().map(_locationToMap).toList();
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
  Future<AuthorizationStatus> getLocationAuthorization() async {
    final status = await _api.getPermissionStatus();
    return AuthorizationStatus.values.firstWhere(
      (e) => e.name == status.name,
      orElse: () => AuthorizationStatus.notDetermined,
    );
  }

  @override
  Future<AuthorizationStatus> requestLocationAuthorization() async {
    final status = await _api.requestPermission();
    return AuthorizationStatus.values.firstWhere(
      (e) => e.name == status.name,
      orElse: () => AuthorizationStatus.notDetermined,
    );
  }

  @override
  Future<NotificationAuthorizationStatus> getNotificationAuthorization() async {
    final status = await _api.getNotificationPermissionStatus();
    if (status == TlNotificationAuthorizationStatus.authorized) {
      return NotificationAuthorizationStatus.granted;
    }
    return NotificationAuthorizationStatus.values.firstWhere(
      (e) => e.name == status.name,
      orElse: () => NotificationAuthorizationStatus.notDetermined,
    );
  }

  @override
  Future<NotificationAuthorizationStatus>
  requestNotificationAuthorization() async {
    final status = await _api.requestNotificationPermission();
    if (status == TlNotificationAuthorizationStatus.authorized) {
      return NotificationAuthorizationStatus.granted;
    }
    return NotificationAuthorizationStatus.values.firstWhere(
      (e) => e.name == status.name,
      orElse: () => NotificationAuthorizationStatus.notDetermined,
    );
  }

  @override
  Future<bool> canScheduleExactAlarms() => _api.canScheduleExactAlarms();

  @override
  Future<bool> openExactAlarmSettings() => _api.openExactAlarmSettings();

  @override
  Future<MotionAuthorizationStatus> getMotionAuthorization() async {
    final status = await _api.getMotionPermissionStatus();
    if (status == TlMotionAuthorizationStatus.authorized) {
      return MotionAuthorizationStatus.granted;
    }
    return MotionAuthorizationStatus.values.firstWhere(
      (e) => e.name == status.name,
      orElse: () => MotionAuthorizationStatus.notDetermined,
    );
  }

  @override
  Future<MotionAuthorizationStatus> requestMotionAuthorization() async {
    final status = await _api.requestMotionPermission();
    if (status == TlMotionAuthorizationStatus.authorized) {
      return MotionAuthorizationStatus.granted;
    }
    return MotionAuthorizationStatus.values.firstWhere(
      (e) => e.name == status.name,
      orElse: () => MotionAuthorizationStatus.notDetermined,
    );
  }

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
  Future<Map<String, Object?>> getDeviceInfo() async {
    final result = await _api.getDeviceInfo();
    return result.cast<String, Object?>();
  }

  @override
  Future<Map<String, Object?>> getSensors() async {
    final result = await _api.getSensors();
    return result.cast<String, Object?>();
  }

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
  Future<Map<String, Object?>> getSettingsHealth() async {
    final result = await _api.getSettingsHealth();
    return result.cast<String, Object?>();
  }

  @override
  Future<Map<String, Object?>> getForegroundServiceHealth() async {
    final result = await _api.getForegroundServiceHealth();
    return result.cast<String, Object?>();
  }

  @override
  Future<TlLocationTuning?> getCurrentLocationTuning() =>
      _api.getCurrentLocationTuning();

  @override
  Future<bool> openOemSettings(String label) => _api.openOemSettings(label);

  @override
  Future<bool> showPowerManager() => _api.showPowerManager();

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
  Future<Map<String, Object?>> verifyAuditTrail() async {
    final result = await _api.verifyAuditTrail();
    return result.cast<String, Object?>();
  }

  @override
  Future<Map<String, Object?>?> getAuditProof(String uuid) async {
    final result = await _api.getAuditProof(uuid);
    return result?.cast<String, Object?>();
  }

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
  Future<List<Map<String, Object?>>> getPrivacyZones() async {
    final result = await _api.getPrivacyZones();
    return result
        .whereType<Map<Object?, Object?>>()
        .map((m) => m.cast<String, Object?>())
        .toList();
  }

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
  Future<Map<String, Object?>?> getAttestationToken() async {
    final result = await _api.getAttestationToken();
    return result?.cast<String, Object?>();
  }

  // ---------------------------------------------------------------------------
  // Enterprise: Carbon Estimator
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>> getCarbonReport([
    Map<String, Object?>? query,
  ]) async {
    final result = await _api.getCarbonReport(query);
    return result.cast<String, Object?>();
  }

  @override
  Future<List<TlTelematicsRecord?>> getTelematicsEvents(int limit) {
    return _api.getTelematicsEvents(limit);
  }

  @override
  Future<bool> destroyTelematicsEvents() async {
    return _api.destroyTelematicsEvents();
  }

  @override
  Future<bool> simulateTelematicsEvent(
    String eventType,
    double severity,
    double latitude,
    double longitude,
  ) async {
    return _api.simulateTelematicsEvent(
      eventType,
      severity,
      latitude,
      longitude,
    );
  }

  @override
  Future<Map<String, Object?>> debugRunCrashModelInference(
    double peakG,
    double speedKmh,
    bool crashLike,
  ) async {
    return _api.debugRunCrashModelInference(peakG, speedKmh, crashLike);
  }

  @override
  Future<List<TlLogEntry?>> getLogs(int limit) {
    return _api.getLogs(limit);
  }

  @override
  Future<void> clearLogs() {
    return _api.clearLogs();
  }

  // ---------------------------------------------------------------------------
  // Enterprise: Dead Reckoning
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>?> getDeadReckoningState() async {
    final result = await _api.getDeadReckoningState();
    return result?.cast<String, Object?>();
  }

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

  @override
  Stream<TlDrivingEvent> get drivingEvents {
    _ensureEventsRegistered();
    return _events.drivingEvents;
  }

  @override
  Stream<TlImpactEvent> get impactEvents {
    _ensureEventsRegistered();
    return _events.impactEvents;
  }

  @override
  Stream<TlModeChangeEvent> get modeChangeEvents {
    _ensureEventsRegistered();
    return _events.modeChangeEvents;
  }

  @override
  Stream<TlCrashModelStatusEvent> get crashModelStatusEvents {
    _ensureEventsRegistered();
    return _events.crashModelStatusEvents;
  }

  @override
  Stream<TlSpeedMotionEvent> get motionModeChangeEvents {
    _ensureEventsRegistered();
    return _events.motionModeChangeEvents;
  }

  @override
  Stream<Map<String?, Object?>> get remoteConfigEvents {
    _ensureEventsRegistered();
    return _events.remoteConfigEvents;
  }
}
