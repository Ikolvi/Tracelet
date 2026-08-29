import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

import 'package:tracelet_web/src/web_carbon_engine.dart';
import 'package:tracelet_web/src/web_event_dispatcher.dart';
import 'package:tracelet_web/src/web_geofence_engine.dart';
import 'package:tracelet_web/src/web_http_engine.dart';
import 'package:tracelet_web/src/web_location_engine.dart';
import 'package:tracelet_web/src/web_permissions_engine.dart';
import 'package:tracelet_web/src/web_privacy_engine.dart';
import 'package:tracelet_web/src/web_storage_engine.dart';

/// Web implementation of [TraceletPlatform].
///
/// Registers itself via `registerWith` during Flutter web plugin discovery.
/// Uses browser APIs (Geolocation, fetch, navigator.permissions,
/// navigator.onLine) for a foreground-only location tracking experience.
///
/// **Key limitation:** No background tracking. The Web Geolocation API does
/// not function in background tabs or Service Workers.
class TraceletWebPlugin extends TraceletPlatform {
  TraceletWebPlugin._();

  static TraceletWebPlugin? _instance;

  /// Registers this class as the default platform implementation.
  static void registerWith(Registrar registrar) {
    _instance ??= TraceletWebPlugin._();
    TraceletPlatform.instance = _instance!;

    // Register EventChannel-compatible stream handlers so the app-facing
    // Tracelet class (which listens on EventChannels) works on web.
    _instance!._registerEventChannels(registrar);
  }

  // ---------------------------------------------------------------------------
  // Engines
  // ---------------------------------------------------------------------------

  late final WebEventDispatcher _events = WebEventDispatcher();
  late final WebGeofenceEngine _geofenceEngine = WebGeofenceEngine(_events);
  late final WebPrivacyEngine _privacyEngine = WebPrivacyEngine();
  late final WebLocationEngine _locationEngine = WebLocationEngine(
    _events,
    _geofenceEngine,
    _privacyEngine,
  );
  late final WebStorageEngine _storage = WebStorageEngine();
  late final WebCarbonEngine _carbonEngine = WebCarbonEngine(_storage);
  late final WebHttpEngine _httpEngine = WebHttpEngine(_events, _storage);
  late final WebPermissionsEngine _permissions = WebPermissionsEngine(_events);

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  bool _isReady = false;
  bool _enabled = false;
  int _trackingMode = 0; // 0=location, 1=geofences
  bool _schedulerEnabled = false;
  Map<String, Object?> _config = <String, Object?>{};

  /// Timer for schedule-based tracking.
  Timer? _scheduleTimer;

  Map<String, Object?> _buildState() {
    return <String, Object?>{
      'enabled': _enabled,
      'trackingMode': _trackingMode,
      'isMoving': _locationEngine.isMoving,
      'schedulerEnabled': _schedulerEnabled,
      'odometer': _locationEngine.odometer,
      'didLaunchInBackground': false,
      'didDeviceReboot': false,
      'config': _config,
    };
  }

  // ---------------------------------------------------------------------------
  // Event channel registration
  // ---------------------------------------------------------------------------

  void _registerEventChannels(Registrar registrar) {
    // We have to bridge our internal broadcast streams to Flutter EventChannels
    // so the app-facing Tracelet class can listen as normal.
    _registerStreamHandler(
      registrar,
      TraceletEvents.location,
      _events.onLocation,
    );
    _registerStreamHandler(
      registrar,
      TraceletEvents.motionChange,
      _events.onMotionChange,
    );
    _registerStreamHandler(
      registrar,
      TraceletEvents.activityChange,
      _events.onActivityChange,
    );
    _registerStreamHandler(
      registrar,
      TraceletEvents.providerChange,
      _events.onProviderChange,
    );
    _registerStreamHandler(
      registrar,
      TraceletEvents.geofence,
      _events.onGeofence,
    );
    _registerStreamHandler(
      registrar,
      TraceletEvents.geofencesChange,
      _events.onGeofencesChange,
    );
    _registerStreamHandler(
      registrar,
      TraceletEvents.heartbeat,
      _events.onHeartbeat,
    );
    _registerStreamHandler(registrar, TraceletEvents.http, _events.onHttp);
    _registerStreamHandler(
      registrar,
      TraceletEvents.schedule,
      _events.onSchedule,
    );
    _registerStreamHandler(
      registrar,
      TraceletEvents.connectivityChange,
      _events.onConnectivityChange,
    );
    _registerStreamHandler(
      registrar,
      TraceletEvents.authorization,
      _events.onAuthorization,
    );
    _registerStreamHandler(
      registrar,
      TraceletEvents.watchPosition,
      _events.onWatchPosition,
    );

    // Bool streams need special handling.
    _registerBoolStreamHandler(
      registrar,
      TraceletEvents.powerSaveChange,
      _events.onPowerSaveChange,
    );
    _registerBoolStreamHandler(
      registrar,
      TraceletEvents.enabledChange,
      _events.onEnabledChange,
    );

    // String stream.
    _registerStringStreamHandler(
      registrar,
      TraceletEvents.notificationAction,
      _events.onNotificationAction,
    );
  }

  void _registerStreamHandler(
    Registrar registrar,
    String channelName,
    Stream<Map<String, Object?>> stream,
  ) {
    final channel = PluginEventChannel<Object?>(
      channelName,
      const StandardMethodCodec(),
      registrar,
    );
    channel.setController(_bridgedController<Object?>(stream.cast<Object?>()));
  }

  void _registerBoolStreamHandler(
    Registrar registrar,
    String channelName,
    Stream<bool> stream,
  ) {
    final channel = PluginEventChannel<Object?>(
      channelName,
      const StandardMethodCodec(),
      registrar,
    );
    channel.setController(_bridgedController<Object?>(stream.cast<Object?>()));
  }

  void _registerStringStreamHandler(
    Registrar registrar,
    String channelName,
    Stream<String> stream,
  ) {
    final channel = PluginEventChannel<Object?>(
      channelName,
      const StandardMethodCodec(),
      registrar,
    );
    channel.setController(_bridgedController<Object?>(stream.cast<Object?>()));
  }

  // ===========================================================================
  // TraceletPlatform method overrides
  // ===========================================================================

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>> ready(TlConfig config) async {
    final map = _tlConfigToMap(config);
    _config = map;
    _locationEngine.applyConfig(map);
    _storage.applyConfig(map);
    _httpEngine.applyConfig(map);
    _permissions.startConnectivityMonitoring();
    _isReady = true;
    _events.log('info', '[Tracelet Web] ready()');
    return _buildState();
  }

  @override
  Future<Map<String, Object?>> start() async {
    _assertReady();
    _enabled = true;
    _trackingMode = 0; // location
    _locationEngine.startTracking();
    _events.emitEnabledChange(true);
    _events.log('info', '[Tracelet Web] start()');
    return _buildState();
  }

  @override
  Future<Map<String, Object?>> stop() async {
    _enabled = false;
    _locationEngine.stopTracking();
    _events.emitEnabledChange(false);
    _events.log('info', '[Tracelet Web] stop()');
    return _buildState();
  }

  @override
  Future<Map<String, Object?>> startGeofences() async {
    _assertReady();
    _enabled = true;
    _trackingMode = 1; // geofences
    // Start location tracking at reduced frequency for geofence checks.
    _locationEngine.startTracking();
    _events.emitEnabledChange(true);
    _events.log('info', '[Tracelet Web] startGeofences()');
    return _buildState();
  }

  @override
  Future<Map<String, Object?>> startPeriodic() async {
    _assertReady();
    _enabled = true;
    _trackingMode = 2; // periodic
    // On web, periodic mode uses the same watchPosition mechanism but with
    // reduced accuracy. True periodic wake-ups are not possible in a browser.
    _locationEngine.startTracking();
    _events.emitEnabledChange(true);
    _events.log('info', '[Tracelet Web] startPeriodic()');
    return _buildState();
  }

  @override
  Future<Map<String, Object?>> getState() async {
    return _buildState();
  }

  @override
  Future<Map<String, Object?>> getForegroundServiceHealth() async {
    // Web has no foreground service (#255). Report the desired enabled state
    // and null/false promotion fields so cross-platform callers get a stable
    // shape without a runtime UnimplementedError.
    final state = _buildState();
    return <String, Object?>{
      'desiredEnabled': state['enabled'] ?? false,
      'foregroundServiceEnabled': false,
      'serviceRunning': state['enabled'] ?? false,
      'serviceForeground': false,
      'foregroundNotificationId': null,
      'lastForegroundPromotionResult': null,
      'lastForegroundPromotionFailureClass': null,
      'lastForegroundPromotionFailureMessage': null,
      'lastForegroundTransitionAt': null,
      'platform': 'web',
    };
  }

  /// Web has no native location processor, so there is no live tuning to
  /// report — the browser Geolocation API exposes no equivalent filter state
  /// (#303).
  @override
  Future<TlLocationTuning?> getCurrentLocationTuning() async => null;

  @override
  Future<Map<String, Object?>> setConfig(TlConfig config) async {
    final map = _tlConfigToMap(config);
    _config = map;
    _locationEngine.applyConfig(map);
    _storage.applyConfig(map);
    _httpEngine.applyConfig(map);
    return _buildState();
  }

  @override
  Future<Map<String, Object?>> reset([TlConfig? config]) async {
    await stop();
    await _storage.destroyLocations();
    await _storage.destroyLog();
    _geofenceEngine.removeGeofences();
    final map = config != null ? _tlConfigToMap(config) : <String, Object?>{};
    _config = map;
    if (config != null) {
      _locationEngine.applyConfig(map);
      _storage.applyConfig(map);
      _httpEngine.applyConfig(map);
    }
    return _buildState();
  }

  @override
  Future<void> updateNotification() async {
    // Web has no foreground-service notification to refresh (#257): no-op.
  }

  // ---------------------------------------------------------------------------
  // Location
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>> getCurrentPosition(
    TlCurrentPositionOptions options,
  ) async {
    final location = await _locationEngine.getCurrentPosition(
      _optionsToMap(options),
    );
    if (options.persist) {
      await _storage.persistLocation(location);
      _httpEngine.onLocationInserted();
    }
    return location;
  }

  @override
  Future<bool> cancelCurrentPosition(String requestId) async => false;

  @override
  Future<Map<String, Object?>> getLastKnownLocation([
    TlCurrentPositionOptions? options,
  ]) async {
    return _locationEngine.getLastKnownLocation();
  }

  @override
  Future<int> watchPosition(TlCurrentPositionOptions options) async {
    return _locationEngine.addWatch(_optionsToMap(options));
  }

  @override
  Future<bool> stopWatchPosition(int watchId) async {
    return _locationEngine.removeWatch(watchId);
  }

  @override
  Future<bool> changePace(bool isMoving) async {
    return _locationEngine.changePace(isMoving);
  }

  @override
  Future<bool> updateLocationProviderOptions(
    TlDesiredAccuracy? desiredAccuracy,
    double? distanceFilter,
  ) async {
    // The Web Geolocation API cannot change accuracy or filtering on an
    // active watch — live provider updates are unsupported here.
    return false;
  }

  @override
  Future<double> getOdometer() async {
    return _locationEngine.odometer;
  }

  @override
  Future<Map<String, Object?>> setOdometer(double value) async {
    return _locationEngine.setOdometer(value);
  }

  // ---------------------------------------------------------------------------
  // Geofencing
  // ---------------------------------------------------------------------------

  @override
  Future<bool> addGeofence(TlGeofence geofence) async {
    return _geofenceEngine.addGeofence(_geofenceToMap(geofence));
  }

  @override
  Future<bool> addGeofences(List<TlGeofence> geofences) async {
    return _geofenceEngine.addGeofences(geofences.map(_geofenceToMap).toList());
  }

  // Typed Pigeon inputs → the Map shape the web engines consume (#206).
  Map<String, Object?> _optionsToMap(
    TlCurrentPositionOptions o,
  ) => <String, Object?>{
    if (o.desiredAccuracy != null) 'desiredAccuracy': o.desiredAccuracy!.index,
    'timeout': o.timeout,
    'maximumAge': o.maximumAge,
    'persist': o.persist,
    'samples': o.samples,
    if (o.accuracyTarget != null) 'accuracyTarget': o.accuracyTarget,
    if (o.requestId != null) 'requestId': o.requestId,
    if (o.extras != null) 'extras': o.extras,
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
    if (g.extras != null) 'extras': g.extras,
    if (g.vertices != null) 'vertices': g.vertices,
  };

  @override
  Future<bool> removeGeofence(String identifier) async {
    return _geofenceEngine.removeGeofence(identifier);
  }

  @override
  Future<bool> removeGeofences() async {
    return _geofenceEngine.removeGeofences();
  }

  @override
  Future<List<Map<String, Object?>>> getGeofences() async {
    return _geofenceEngine.getGeofences();
  }

  @override
  Future<Map<String, Object?>?> getGeofence(String identifier) async {
    return _geofenceEngine.getGeofence(identifier);
  }

  @override
  Future<bool> geofenceExists(String identifier) async {
    return _geofenceEngine.geofenceExists(identifier);
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  @override
  Future<List<Map<String, Object?>>> getLocations([
    Map<String, Object?>? query,
  ]) {
    return _storage.getLocations(query);
  }

  @override
  Future<int> getCount([Map<String, Object?>? query]) {
    return _storage.getCount(query);
  }

  @override
  Future<bool> destroyLocations() {
    return _storage.destroyLocations();
  }

  @override
  Future<int> destroySyncedLocations() {
    return _storage.destroySyncedLocations();
  }

  @override
  Future<bool> destroyLocation(String uuid) {
    return _storage.destroyLocation(uuid);
  }

  @override
  Future<String> insertLocation(Map<String, Object?> params) async {
    final uuid = await _storage.insertLocation(params);
    _httpEngine.onLocationInserted();
    return uuid;
  }

  // ---------------------------------------------------------------------------
  // HTTP Sync
  // ---------------------------------------------------------------------------

  @override
  Future<List<Map<String, Object?>>> sync() {
    return _httpEngine.sync();
  }

  @override
  Future<bool> setDynamicHeaders(Map<String, String> headers) async {
    _httpEngine.setDynamicHeaders(headers);
    return true;
  }

  @override
  Future<bool> setRouteContext(Map<String, Object?> context) async {
    _httpEngine.setRouteContext(context);
    return true;
  }

  @override
  Future<bool> clearRouteContext() async {
    _httpEngine.clearRouteContext();
    return true;
  }

  @override
  Future<bool> registerHeadlessHeadersCallback(List<int> callbackIds) async {
    _events.log(
      'warning',
      '[Tracelet Web] registerHeadlessHeadersCallback() is not supported on web',
    );
    return false;
  }

  @override
  Future<bool> registerHeadlessSyncBodyBuilder(List<int> callbackIds) async {
    _events.log(
      'warning',
      '[Tracelet Web] registerHeadlessSyncBodyBuilder() is not supported on web',
    );
    return false;
  }

  // ---------------------------------------------------------------------------
  // Utility
  // ---------------------------------------------------------------------------

  @override
  Future<bool> isPowerSaveMode() async => false;

  @override
  Future<AuthorizationStatus> getLocationAuthorization() async {
    final status = await _permissions.getPermissionStatus();
    if (status == 2) return AuthorizationStatus.whenInUse;
    if (status == 4) return AuthorizationStatus.deniedForever;
    return AuthorizationStatus.notDetermined;
  }

  @override
  Future<AuthorizationStatus> requestLocationAuthorization() async {
    final status = await _permissions.requestPermission();
    if (status == 2) return AuthorizationStatus.whenInUse;
    if (status == 4) return AuthorizationStatus.deniedForever;
    return AuthorizationStatus.notDetermined;
  }

  @override
  Future<NotificationAuthorizationStatus> getNotificationAuthorization() async {
    final status = await _permissions.getNotificationPermissionStatus();
    if (status == 3) return NotificationAuthorizationStatus.granted;
    if (status == 4) return NotificationAuthorizationStatus.deniedForever;
    return NotificationAuthorizationStatus.notDetermined;
  }

  @override
  Future<NotificationAuthorizationStatus>
  requestNotificationAuthorization() async {
    final status = await _permissions.requestNotificationPermission();
    if (status == 3) return NotificationAuthorizationStatus.granted;
    if (status == 4) return NotificationAuthorizationStatus.deniedForever;
    return NotificationAuthorizationStatus.notDetermined;
  }

  @override
  Future<bool> canScheduleExactAlarms() async => true; // no restriction on web

  @override
  Future<bool> openExactAlarmSettings() async => false; // no-op on web

  @override
  Future<MotionAuthorizationStatus> getMotionAuthorization() async =>
      MotionAuthorizationStatus.granted; // always granted

  @override
  Future<MotionAuthorizationStatus> requestMotionAuthorization() async =>
      MotionAuthorizationStatus.granted; // always granted

  @Deprecated(
    'Use requestTemporaryFullAccuracyAuthorization() which returns FullAccuracyStatus.',
  )
  @override
  Future<int> requestTemporaryFullAccuracy(String purpose) async {
    return 0; // full — browser always provides full accuracy
  }

  @override
  Future<FullAccuracyStatus> requestTemporaryFullAccuracyAuthorization(
    String purpose,
  ) async => FullAccuracyStatus.full; // browsers always provide full accuracy

  @override
  Future<Map<String, Object?>> getProviderState() {
    return _permissions.getProviderState();
  }

  @override
  Future<Map<String, Object?>> getSensors() async {
    return _permissions.getSensors();
  }

  @override
  Future<Map<String, Object?>> getDeviceInfo() async {
    return _permissions.getDeviceInfo();
  }

  @override
  Future<bool> playSound(String name) async {
    // Could use AudioContext but not critical for web.
    _events.log('debug', '[Tracelet Web] playSound("$name") — no-op on web');
    return false;
  }

  @override
  Future<bool> isIgnoringBatteryOptimizations() async => true;

  @override
  Future<bool> requestSettings(String action) async => false;

  @override
  Future<bool> showSettings(String action) async => false;

  // ---------------------------------------------------------------------------
  // OEM Compatibility (no OEM power management on web)
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>> getSettingsHealth() async {
    return <String, Object?>{
      'manufacturer': 'Web',
      'model': 'Browser',
      'isAggressiveOem': false,
      'aggressionRating': 0,
      'isIgnoringBatteryOptimizations': true,
      'autostartAvailable': false,
      'oemSettingsScreens': <Map<String, String>>[],
    };
  }

  @override
  Future<bool> openOemSettings(String label) async => false;

  @override
  Future<bool> showPowerManager() async => false;

  // ---------------------------------------------------------------------------
  // Background Tasks (stubs — no background execution on web)
  // ---------------------------------------------------------------------------

  @override
  Future<int> startBackgroundTask() async => 0;

  @override
  Future<int> stopBackgroundTask(int taskId) async => taskId;

  // ---------------------------------------------------------------------------
  // Logging
  // ---------------------------------------------------------------------------

  @override
  Future<String> getLog([Map<String, Object?>? query]) {
    return _storage.getLog(query);
  }

  @override
  Future<bool> destroyLog() {
    return _storage.destroyLog();
  }

  @override
  Future<void> clearLogs() async {
    await _storage.destroyLog();
  }

  @override
  Future<bool> emailLog(String email) async {
    // Could open mailto: link but impractical. Log a warning.
    _events.log('warning', '[Tracelet Web] emailLog() is not supported on web');
    return false;
  }

  @override
  Future<bool> log(String level, String message) {
    return _storage.log(level, message);
  }

  // ---------------------------------------------------------------------------
  // Telematics & Custom Sync
  // ---------------------------------------------------------------------------

  @override
  Future<void> connectCustomSync(String url, String jwt) async {
    _events.log(
      'warning',
      '[Tracelet Web] connectCustomSync() is not supported on web',
    );
  }

  @override
  Future<List<TlTelematicsRecord?>> getTelematicsEvents(int limit) async {
    return <TlTelematicsRecord?>[];
  }

  @override
  Future<bool> destroyTelematicsEvents() async {
    return true;
  }

  @override
  Future<bool> simulateTelematicsEvent(
    String eventType,
    double severity,
    double latitude,
    double longitude,
  ) async {
    _events.log(
      'warning',
      '[Tracelet Web] simulateTelematicsEvent() is not supported on web',
    );
    return false;
  }

  @override
  Future<Map<String, Object?>> debugRunCrashModelInference(
    double peakG,
    double speedKmh,
    bool crashLike,
  ) async {
    _events.log(
      'warning',
      '[Tracelet Web] debugRunCrashModelInference() is not supported on web',
    );
    return {'modelRan': false, 'fired': false, 'error': 'unsupported on web'};
  }

  // ---------------------------------------------------------------------------
  // Scheduling (foreground-only timers)
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>> startSchedule() async {
    _schedulerEnabled = true;
    // Simple foreground scheduler — just start/stop tracking on interval.
    // Real schedule parsing would be more sophisticated.
    _events.emitSchedule(_buildState());
    return _buildState();
  }

  @override
  Future<Map<String, Object?>> stopSchedule() async {
    _schedulerEnabled = false;
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    _events.emitSchedule(_buildState());
    return _buildState();
  }

  // ---------------------------------------------------------------------------
  // Headless (not supported on web)
  // ---------------------------------------------------------------------------

  @override
  Future<bool> registerHeadlessTask(List<int> callbackIds) async {
    _events.log(
      'warning',
      '[Tracelet Web] registerHeadlessTask() is not supported on web',
    );
    return false;
  }

  // ---------------------------------------------------------------------------
  // [Enterprise] Audit Trail
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>> verifyAuditTrail() async {
    return _storage.verifyAuditTrail();
  }

  @override
  Future<Map<String, Object?>?> getAuditProof(String uuid) async {
    return _storage.getAuditProof(uuid);
  }

  // ---------------------------------------------------------------------------
  // [Enterprise] Privacy Zones
  // ---------------------------------------------------------------------------

  @override
  Future<bool> addPrivacyZone(Map<String, Object?> zone) async {
    return _privacyEngine.addPrivacyZone(zone);
  }

  @override
  Future<bool> addPrivacyZones(List<Map<String, Object?>> zones) async {
    return _privacyEngine.addPrivacyZones(zones);
  }

  @override
  Future<bool> removePrivacyZone(String identifier) async {
    return _privacyEngine.removePrivacyZone(identifier);
  }

  @override
  Future<bool> removePrivacyZones() async {
    return _privacyEngine.removePrivacyZones();
  }

  @override
  Future<List<Map<String, Object?>>> getPrivacyZones() async {
    return _privacyEngine.getPrivacyZones();
  }

  // ---------------------------------------------------------------------------
  // [Enterprise] Encrypted Database (no-op on web — in-memory storage)
  // ---------------------------------------------------------------------------

  @override
  Future<bool> isDatabaseEncrypted() async => false;

  @override
  Future<bool> encryptDatabase() async => false;

  // ---------------------------------------------------------------------------
  // [Enterprise] Device Attestation (not supported on web)
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>?> getAttestationToken() async => null;

  // ---------------------------------------------------------------------------
  // [Enterprise] Dead Reckoning (not supported on web)
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>?> getDeadReckoningState() async => null;

  // ---------------------------------------------------------------------------
  // [Enterprise] Carbon Estimator
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>> getCarbonReport([
    Map<String, Object?>? query,
  ]) async {
    return _carbonEngine.getCarbonReport(query);
  }

  // ---------------------------------------------------------------------------
  // Driving & Safety (Crash / Fall Detection — not supported on web)
  // ---------------------------------------------------------------------------

  @override
  Future<bool> confirmImpact(int id) async {
    _events.log(
      'warning',
      '[Tracelet Web] confirmImpact() is not supported on web',
    );
    return false;
  }

  @override
  Future<bool> cancelImpact(int id) async {
    _events.log(
      'warning',
      '[Tracelet Web] cancelImpact() is not supported on web',
    );
    return false;
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  Map<String, Object?> _tlConfigToMap(TlConfig c) {
    return {
      'geo': {
        'desiredAccuracy': c.geo.desiredAccuracy?.index,
        'distanceFilter': c.geo.distanceFilter,
        'stationaryRadius': c.geo.stationaryRadius,
        'locationTimeout': c.geo.locationTimeout,
        'disableElasticity': c.geo.disableElasticity,
        'elasticityMultiplier': c.geo.elasticityMultiplier,
        'stopAfterElapsedMinutes': c.geo.stopAfterElapsedMinutes,
        'maxMonitoredGeofences': c.geo.maxMonitoredGeofences,
        'enableTimestampMeta': c.geo.enableTimestampMeta,
        'enableAdaptiveMode': c.geo.enableAdaptiveMode,
        'periodicLocationInterval': c.geo.periodicLocationInterval,
        'periodicDesiredAccuracy': c.geo.periodicDesiredAccuracy?.index,
        'enableSparseUpdates': c.geo.enableSparseUpdates,
        'sparseDistanceThreshold': c.geo.sparseDistanceThreshold,
        'sparseMaxIdleSeconds': c.geo.sparseMaxIdleSeconds,
        'enableDeadReckoning': c.geo.enableDeadReckoning,
        'deadReckoningActivationDelay': c.geo.deadReckoningActivationDelay,
        'deadReckoningMaxDuration': c.geo.deadReckoningMaxDuration,
        'batteryBudgetPerHour': c.geo.batteryBudgetPerHour,
      },
      'app': {
        'stopOnTerminate': c.app.stopOnTerminate,
        'startOnBoot': c.app.startOnBoot,
        'heartbeatInterval': c.app.heartbeatInterval,
        'schedule': c.app.schedule,
        'remoteConfigUrl': c.app.remoteConfigUrl,
        'remoteConfigHeaders': c.app.remoteConfigHeaders,
        'remoteConfigTimeout': c.app.remoteConfigTimeout,
        'remoteConfigRefreshInterval': c.app.remoteConfigRefreshInterval,
      },
      'http': {
        'url': c.http.url,
        'method': c.http.method?.index,
        'headers': c.http.headers,
        'params': c.http.params,
        'autoSync': c.http.autoSync,
        'batchSync': c.http.batchSync,
        'maxBatchSize': c.http.maxBatchSize,
        'autoSyncThreshold': c.http.autoSyncThreshold,
        'httpTimeout': c.http.httpTimeout,
        'locationsOrderDirection': c.http.locationsOrderDirection?.index,
        'disableAutoSyncOnCellular': c.http.disableAutoSyncOnCellular,
        'maxRetries': c.http.maxRetries,
        'retryBackoffBase': c.http.retryBackoffBase,
        'retryBackoffCap': c.http.retryBackoffCap,
        'enableDeltaCompression': c.http.enableDeltaCompression,
        'deltaCoordinatePrecision': c.http.deltaCoordinatePrecision,
      },
      'logger': {
        'logLevel': c.logger.logLevel?.index,
        'logMaxDays': c.logger.logMaxDays,
        'debug': c.logger.debug,
      },
      'motion': {
        'stopTimeout': c.motion.stopTimeout,
        'motionTriggerDelay': c.motion.motionTriggerDelay,
        'disableMotionActivityUpdates': c.motion.disableMotionActivityUpdates,
        'isMoving': c.motion.isMoving,
        'activityRecognitionInterval': c.motion.activityRecognitionInterval,
        'minimumActivityRecognitionConfidence':
            c.motion.minimumActivityRecognitionConfidence,
        'disableStopDetection': c.motion.disableStopDetection,
        'stopDetectionDelay': c.motion.stopDetectionDelay,
        'stopOnStationary': c.motion.stopOnStationary,
        'stationaryRadius': c.motion.stationaryRadius,
        'useSignificantChangesOnly': c.motion.useSignificantChangesOnly,
      },
      'geofence': {
        // #305: read the cross-platform GeofenceConfig flag, OR'd with the
        // deprecated Android-only one for backward compatibility — matching
        // both Pigeon host implementations. Web previously read ONLY the
        // deprecated flag, so setting the documented cross-platform one had no
        // effect here.
        'geofenceModeHighAccuracy':
            (c.geofence.geofenceModeHighAccuracy ?? false) ||
            (c.android.geofenceModeHighAccuracy ?? false),
        'geofenceInitialTriggerEntry': c.geofence.geofenceInitialTriggerEntry,
        'geofenceProximityRadius': c.geofence.geofenceProximityRadius,
        'geofenceInitialTrigger': c.geofence.geofenceInitialTrigger,
        'geofenceExitAccuracyMax': c.geofence.geofenceExitAccuracyMax,
      },
      'persistence': {
        'persistMode': c.persistence.persistMode?.index,
        'maxDaysToPersist': c.persistence.maxDaysToPersist,
        'maxRecordsToPersist': c.persistence.maxRecordsToPersist,
        'disableProviderChangeRecord':
            c.persistence.disableProviderChangeRecord,
      },
      'audit': {
        'enabled': c.audit.enabled,
        'hashAlgorithm': c.audit.hashAlgorithm?.index,
      },
      'privacyZone': {'enabled': c.privacyZone.enabled},
      'security': {'encryptDatabase': c.security.encryptDatabase},
      'attestation': {
        'enabled': c.attestation.enabled,
        'refreshInterval': c.attestation.refreshInterval,
      },
    };
  }

  // ---------------------------------------------------------------------------
  // Event Streams (typed — TraceletPlatform overrides)
  //
  // The WebEventDispatcher emits raw Map<String, Object?> events through its
  // broadcast stream controllers. These getters convert them into the typed
  // Tl* objects expected by the shared Tracelet class in tracelet.dart.
  // ---------------------------------------------------------------------------

  /// Convert a raw location map from WebLocationEngine into a [TlLocation].
  TlLocation _mapToTlLocation(Map<String, Object?> m) {
    final coordsRaw = m['coords'];
    final coords = coordsRaw is Map
        ? Map<String, Object?>.from(coordsRaw)
        : <String, Object?>{};
    final batteryRaw = m['battery'];
    final battery = batteryRaw is Map
        ? Map<String, Object?>.from(batteryRaw)
        : <String, Object?>{};
    final activityRaw = m['activity'];
    final activityMap = activityRaw is Map
        ? Map<String, Object?>.from(activityRaw)
        : null;

    return TlLocation(
      coords: TlCoords(
        latitude: (coords['latitude'] as num?)?.toDouble() ?? 0.0,
        longitude: (coords['longitude'] as num?)?.toDouble() ?? 0.0,
        accuracy: (coords['accuracy'] as num?)?.toDouble() ?? -1.0,
        speed: (coords['speed'] as num?)?.toDouble() ?? -1.0,
        heading: (coords['heading'] as num?)?.toDouble() ?? -1.0,
        altitude: (coords['altitude'] as num?)?.toDouble() ?? 0.0,
        altitudeAccuracy:
            (coords['altitudeAccuracy'] as num?)?.toDouble() ?? -1.0,
        speedAccuracy: (coords['speedAccuracy'] as num?)?.toDouble() ?? -1.0,
        headingAccuracy:
            (coords['headingAccuracy'] as num?)?.toDouble() ?? -1.0,
        ellipsoidalAltitude: (coords['ellipsoidalAltitude'] as num?)
            ?.toDouble(),
        floor: coords['floor'] as int?,
      ),
      battery: TlBattery(
        level: (battery['level'] as num?)?.toDouble() ?? -1.0,
        isCharging: battery['isCharging'] as bool? ?? false,
      ),
      timestamp: m['timestamp'] as String? ?? DateTime.now().toIso8601String(),
      uuid: m['uuid'] as String? ?? '',
      isMoving: m['isMoving'] as bool? ?? false,
      odometer: (m['odometer'] as num?)?.toDouble() ?? 0.0,
      event: m['event'] as String?,
      activity: activityMap != null
          ? TlActivity(
              type: activityMap['type'] as String? ?? 'unknown',
              confidence: activityMap['confidence'] is int
                  ? activityMap['confidence']! as int
                  : 50,
            )
          : null,
    );
  }

  @override
  Stream<TlLocation> get locationEvents =>
      _events.onLocation.map(_mapToTlLocation);

  @override
  Stream<TlLocation> get motionChangeEvents =>
      _events.onMotionChange.map(_mapToTlLocation);

  @override
  Stream<TlLocation> get watchPositionEvents =>
      _events.onWatchPosition.map(_mapToTlLocation);

  @override
  Stream<TlActivityChangeEvent> get activityChangeEvents =>
      _events.onActivityChange.map((m) {
        return TlActivityChangeEvent(
          activity: m['activity'] as String? ?? 'unknown',
          confidence: m['confidence'] as int? ?? 50,
        );
      });

  @override
  Stream<TlProviderChangeEvent> get providerChangeEvents =>
      _events.onProviderChange.map((m) {
        return TlProviderChangeEvent(
          enabled: m['enabled'] as bool? ?? true,
          gps: m['gps'] as bool? ?? true,
          network: m['network'] as bool? ?? true,
          status: m['status'] as int? ?? 2,
          accuracyAuthorization: m['accuracyAuthorization'] as int?,
        );
      });

  @override
  Stream<TlGeofenceEvent> get geofenceEvents => _events.onGeofence.map((m) {
    final locationRaw = m['location'];
    final locationMap = locationRaw is Map
        ? Map<String, Object?>.from(locationRaw)
        : <String, Object?>{};
    return TlGeofenceEvent(
      identifier: m['identifier'] as String? ?? '',
      action: TlGeofenceAction
          .values[m['action'] as int? ?? TlGeofenceAction.enter.index],
      location: _mapToTlLocation(locationMap),
    );
  });

  @override
  Stream<TlGeofencesChangeEvent> get geofencesChangeEvents =>
      // The web geofence engine doesn't emit geofencesChange events; return empty.
      const Stream.empty();

  @override
  Stream<TlHeartbeatEvent> get heartbeatEvents => _events.onHeartbeat.map((m) {
    final locationRaw = m['location'];
    final locationMap = locationRaw is Map
        ? Map<String, Object?>.from(locationRaw)
        : m; // heartbeat emits location directly
    return TlHeartbeatEvent(location: _mapToTlLocation(locationMap));
  });

  @override
  Stream<TlHttpEvent> get httpEvents => _events.onHttp.map((m) {
    return TlHttpEvent(
      isSuccess: m['isSuccess'] as bool? ?? false,
      status: m['status'] as int? ?? 0,
      responseText: m['responseText'] as String? ?? '',
    );
  });

  @override
  Stream<TlState> get scheduleEvents => _events.onSchedule.map((m) {
    return TlState(
      enabled: m['enabled'] as bool? ?? false,
      isMoving: m['isMoving'] as bool? ?? false,
      trackingMode: TlTrackingMode
          .values[m['trackingMode'] as int? ?? TlTrackingMode.location.index],
      schedulerEnabled: m['schedulerEnabled'] as bool? ?? false,
      odometer: (m['odometer'] as num?)?.toDouble() ?? 0.0,
      lastLocationTimestamp: m['lastLocationTimestamp'] as String?,
    );
  });

  @override
  Stream<bool> get powerSaveChangeEvents => _events.onPowerSaveChange;

  @override
  Stream<TlConnectivityChangeEvent> get connectivityChangeEvents =>
      _events.onConnectivityChange.map((m) {
        return TlConnectivityChangeEvent(
          connected: m['connected'] as bool? ?? true,
        );
      });

  @override
  Stream<bool> get enabledChangeEvents => _events.onEnabledChange;

  @override
  Stream<String> get notificationActionEvents => _events.onNotificationAction;

  @override
  Stream<TlAuthorizationEvent> get authorizationEvents =>
      _events.onAuthorization.map((m) {
        return TlAuthorizationEvent(
          success: m['success'] as bool? ?? false,
          status: m['status'] as int? ?? 0,
          response: m['response'] as String? ?? '',
        );
      });

  @override
  Stream<TlSpeedMotionEvent> get motionModeChangeEvents =>
      // Speed motion events are emitted via WebLocationEngine via a separate
      // dedicated controller added to WebEventDispatcher in a future iteration.
      // For now return empty — the speed motion state is tracked internally.
      const Stream.empty();

  @override
  Stream<TlImpactEvent> get impactEvents => const Stream.empty();

  @override
  Stream<TlCrashModelStatusEvent> get crashModelStatusEvents =>
      // The ML crash model is a native-only feature; never fires on web.
      const Stream.empty();

  @override
  Stream<Map<String?, Object?>> get remoteConfigEvents =>
      // Remote config is a native-only (Enterprise) feature; never fires on web.
      const Stream.empty();

  void _assertReady() {
    if (!_isReady) {
      throw StateError(
        'Tracelet.ready() must be called before start(). '
        'Call ready(Config) first.',
      );
    }
  }
}

// =============================================================================
// Helper: bridges a broadcast stream to a StreamController for EventChannel
// =============================================================================

StreamController<T> _bridgedController<T>(Stream<T> source) {
  late StreamController<T> controller;
  StreamSubscription<T>? subscription;
  controller = StreamController<T>(
    onListen: () {
      subscription = source.listen(
        (T data) => controller.add(data),
        onError: (Object error, StackTrace stackTrace) =>
            controller.addError(error, stackTrace),
      );
    },
    onCancel: () {
      subscription?.cancel();
      subscription = null;
    },
  );
  return controller;
}
