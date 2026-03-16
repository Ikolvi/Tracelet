import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

import 'web_event_dispatcher.dart';
import 'web_geofence_engine.dart';
import 'web_http_engine.dart';
import 'web_location_engine.dart';
import 'web_permissions_engine.dart';
import 'web_storage_engine.dart';

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
  late final WebLocationEngine _locationEngine = WebLocationEngine(
    _events,
    _geofenceEngine,
  );
  late final WebStorageEngine _storage = WebStorageEngine();
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
  Future<Map<String, Object?>> ready(Map<String, Object?> config) async {
    _config = Map<String, Object?>.from(config);
    _locationEngine.applyConfig(config);
    _storage.applyConfig(config);
    _httpEngine.applyConfig(config);
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
  Future<Map<String, Object?>> setConfig(Map<String, Object?> config) async {
    _config = Map<String, Object?>.from(config);
    _locationEngine.applyConfig(config);
    _storage.applyConfig(config);
    _httpEngine.applyConfig(config);
    return _buildState();
  }

  @override
  Future<Map<String, Object?>> reset([Map<String, Object?>? config]) async {
    await stop();
    await _storage.destroyLocations();
    await _storage.destroyLog();
    _geofenceEngine.removeGeofences();
    _config = config ?? <String, Object?>{};
    if (config != null) {
      _locationEngine.applyConfig(config);
      _storage.applyConfig(config);
      _httpEngine.applyConfig(config);
    }
    return _buildState();
  }

  // ---------------------------------------------------------------------------
  // Location
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>> getCurrentPosition(
    Map<String, Object?> options,
  ) async {
    final location = await _locationEngine.getCurrentPosition(options);
    final persist = options['persist'] as bool? ?? true;
    if (persist) {
      await _storage.persistLocation(location);
      _httpEngine.onLocationInserted();
    }
    return location;
  }

  @override
  Future<Map<String, Object?>> getLastKnownLocation([
    Map<String, Object?>? options,
  ]) async {
    return _locationEngine.getLastKnownLocation();
  }

  @override
  Future<int> watchPosition(Map<String, Object?> options) async {
    return _locationEngine.addWatch(options);
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
  Future<bool> addGeofence(Map<String, Object?> geofence) async {
    return _geofenceEngine.addGeofence(geofence);
  }

  @override
  Future<bool> addGeofences(List<Map<String, Object?>> geofences) async {
    return _geofenceEngine.addGeofences(geofences);
  }

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

  // ---------------------------------------------------------------------------
  // Utility
  // ---------------------------------------------------------------------------

  @override
  Future<bool> isPowerSaveMode() async => false;

  @override
  Future<int> getPermissionStatus() {
    return _permissions.getPermissionStatus();
  }

  @override
  Future<int> requestPermission() {
    return _permissions.requestPermission();
  }

  @override
  Future<int> getNotificationPermissionStatus() {
    return _permissions.getNotificationPermissionStatus();
  }

  @override
  Future<int> requestNotificationPermission() {
    return _permissions.requestNotificationPermission();
  }

  @override
  Future<bool> canScheduleExactAlarms() async => true; // no restriction on web

  @override
  Future<bool> openExactAlarmSettings() async => false; // no-op on web

  @override
  Future<int> getMotionPermissionStatus() async => 3; // always granted

  @override
  Future<int> requestMotionPermission() async => 3; // always granted

  @override
  Future<int> requestTemporaryFullAccuracy(String purpose) async {
    return 0; // full — browser always provides full accuracy
  }

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
  // [Enterprise] Audit Trail (not supported on web)
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>> verifyAuditTrail() async {
    return <String, Object?>{
      'is_valid': true,
      'total_records': 0,
      'verified_records': 0,
    };
  }

  @override
  Future<Map<String, Object?>?> getAuditProof(String uuid) async {
    return null;
  }

  // ---------------------------------------------------------------------------
  // [Enterprise] Privacy Zones (not supported on web)
  // ---------------------------------------------------------------------------

  @override
  Future<bool> addPrivacyZone(Map<String, Object?> zone) async => false;

  @override
  Future<bool> addPrivacyZones(List<Map<String, Object?>> zones) async => false;

  @override
  Future<bool> removePrivacyZone(String identifier) async => false;

  @override
  Future<bool> removePrivacyZones() async => false;

  @override
  Future<List<Map<String, Object?>>> getPrivacyZones() async => [];

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

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
