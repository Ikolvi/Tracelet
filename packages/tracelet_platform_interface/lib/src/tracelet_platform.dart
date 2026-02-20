import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'method_channel_tracelet.dart';

/// The interface that platform implementations of Tracelet must extend.
///
/// Platform implementations should override all methods and provide
/// concrete native implementations. The default implementation is
/// [MethodChannelTracelet], which uses MethodChannel for communication.
abstract class TraceletPlatform extends PlatformInterface {
  /// Constructs a [TraceletPlatform].
  TraceletPlatform() : super(token: _token);

  static final Object _token = Object();

  static TraceletPlatform _instance = MethodChannelTracelet();

  /// The current platform implementation.
  ///
  /// Defaults to [MethodChannelTracelet].
  static TraceletPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [TraceletPlatform] when
  /// they register themselves.
  static set instance(TraceletPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// The MethodChannel path used for request/response calls.
  static const String methodChannelName = 'com.tracelet/methods';

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Initialize the plugin with the given [config].
  /// Returns the current [State] as a map.
  Future<Map<String, Object?>> ready(Map<String, Object?> config) {
    throw UnimplementedError('ready() has not been implemented.');
  }

  /// Start location tracking. Returns [State] map.
  Future<Map<String, Object?>> start() {
    throw UnimplementedError('start() has not been implemented.');
  }

  /// Stop location tracking. Returns [State] map.
  Future<Map<String, Object?>> stop() {
    throw UnimplementedError('stop() has not been implemented.');
  }

  /// Start geofence-only tracking mode. Returns [State] map.
  Future<Map<String, Object?>> startGeofences() {
    throw UnimplementedError('startGeofences() has not been implemented.');
  }

  /// Get the current plugin state. Returns [State] map.
  Future<Map<String, Object?>> getState() {
    throw UnimplementedError('getState() has not been implemented.');
  }

  /// Update configuration. Returns [State] map.
  Future<Map<String, Object?>> setConfig(Map<String, Object?> config) {
    throw UnimplementedError('setConfig() has not been implemented.');
  }

  /// Reset to default configuration. Optionally apply [config].
  /// Returns [State] map.
  Future<Map<String, Object?>> reset([Map<String, Object?>? config]) {
    throw UnimplementedError('reset() has not been implemented.');
  }

  // ---------------------------------------------------------------------------
  // Location
  // ---------------------------------------------------------------------------

  /// Get the current position. Returns [Location] map.
  Future<Map<String, Object?>> getCurrentPosition(
      Map<String, Object?> options) {
    throw UnimplementedError('getCurrentPosition() has not been implemented.');
  }

  /// Start watching position at an interval. Returns a watch ID.
  Future<int> watchPosition(Map<String, Object?> options) {
    throw UnimplementedError('watchPosition() has not been implemented.');
  }

  /// Stop a watch started by [watchPosition].
  Future<bool> stopWatchPosition(int watchId) {
    throw UnimplementedError('stopWatchPosition() has not been implemented.');
  }

  /// Toggle motion state. [isMoving] = `true` forces moving mode.
  Future<bool> changePace(bool isMoving) {
    throw UnimplementedError('changePace() has not been implemented.');
  }

  /// Get the current odometer value in meters.
  Future<double> getOdometer() {
    throw UnimplementedError('getOdometer() has not been implemented.');
  }

  /// Set the odometer value. Returns [Location] map at the reset point.
  Future<Map<String, Object?>> setOdometer(double value) {
    throw UnimplementedError('setOdometer() has not been implemented.');
  }

  // ---------------------------------------------------------------------------
  // Geofencing
  // ---------------------------------------------------------------------------

  /// Add a single geofence. Returns `true` on success.
  Future<bool> addGeofence(Map<String, Object?> geofence) {
    throw UnimplementedError('addGeofence() has not been implemented.');
  }

  /// Add multiple geofences. Returns `true` on success.
  Future<bool> addGeofences(List<Map<String, Object?>> geofences) {
    throw UnimplementedError('addGeofences() has not been implemented.');
  }

  /// Remove a geofence by [identifier]. Returns `true` on success.
  Future<bool> removeGeofence(String identifier) {
    throw UnimplementedError('removeGeofence() has not been implemented.');
  }

  /// Remove all geofences. Returns `true` on success.
  Future<bool> removeGeofences() {
    throw UnimplementedError('removeGeofences() has not been implemented.');
  }

  /// Get all registered geofences.
  Future<List<Map<String, Object?>>> getGeofences() {
    throw UnimplementedError('getGeofences() has not been implemented.');
  }

  /// Get a single geofence by [identifier].
  Future<Map<String, Object?>?> getGeofence(String identifier) {
    throw UnimplementedError('getGeofence() has not been implemented.');
  }

  /// Check if a geofence with [identifier] exists.
  Future<bool> geofenceExists(String identifier) {
    throw UnimplementedError('geofenceExists() has not been implemented.');
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  /// Get stored locations. Returns list of [Location] maps.
  Future<List<Map<String, Object?>>> getLocations(
      [Map<String, Object?>? query]) {
    throw UnimplementedError('getLocations() has not been implemented.');
  }

  /// Get the count of stored locations.
  Future<int> getCount() {
    throw UnimplementedError('getCount() has not been implemented.');
  }

  /// Destroy all stored locations.
  Future<bool> destroyLocations() {
    throw UnimplementedError('destroyLocations() has not been implemented.');
  }

  /// Destroy a single location by [uuid].
  Future<bool> destroyLocation(String uuid) {
    throw UnimplementedError('destroyLocation() has not been implemented.');
  }

  /// Insert a custom location into the store. Returns UUID.
  Future<String> insertLocation(Map<String, Object?> params) {
    throw UnimplementedError('insertLocation() has not been implemented.');
  }

  // ---------------------------------------------------------------------------
  // HTTP Sync
  // ---------------------------------------------------------------------------

  /// Manually trigger HTTP sync. Returns synced locations.
  Future<List<Map<String, Object?>>> sync() {
    throw UnimplementedError('sync() has not been implemented.');
  }

  // ---------------------------------------------------------------------------
  // Utility
  // ---------------------------------------------------------------------------

  /// Whether the device is in power-save mode.
  Future<bool> isPowerSaveMode() {
    throw UnimplementedError('isPowerSaveMode() has not been implemented.');
  }

  /// Request location permission. Returns status code.
  Future<int> requestPermission() {
    throw UnimplementedError('requestPermission() has not been implemented.');
  }

  /// Request temporary full accuracy (iOS 14+). Returns accuracy status.
  Future<int> requestTemporaryFullAccuracy(String purpose) {
    throw UnimplementedError(
        'requestTemporaryFullAccuracy() has not been implemented.');
  }

  /// Get the current location provider state.
  Future<Map<String, Object?>> getProviderState() {
    throw UnimplementedError('getProviderState() has not been implemented.');
  }

  /// Get available device sensors info.
  Future<Map<String, Object?>> getSensors() {
    throw UnimplementedError('getSensors() has not been implemented.');
  }

  /// Get device info (model, manufacturer, OS version).
  Future<Map<String, Object?>> getDeviceInfo() {
    throw UnimplementedError('getDeviceInfo() has not been implemented.');
  }

  /// Play a debug sound by name.
  Future<bool> playSound(String name) {
    throw UnimplementedError('playSound() has not been implemented.');
  }

  /// Whether the app is ignoring battery optimizations (Android only).
  Future<bool> isIgnoringBatteryOptimizations() {
    throw UnimplementedError(
        'isIgnoringBatteryOptimizations() has not been implemented.');
  }

  /// Request a system settings page (e.g., battery optimization).
  Future<bool> requestSettings(String action) {
    throw UnimplementedError('requestSettings() has not been implemented.');
  }

  /// Show a system settings page (e.g., location settings).
  Future<bool> showSettings(String action) {
    throw UnimplementedError('showSettings() has not been implemented.');
  }

  // ---------------------------------------------------------------------------
  // Background Tasks
  // ---------------------------------------------------------------------------

  /// Start a long-running background task. Returns task ID.
  Future<int> startBackgroundTask() {
    throw UnimplementedError(
        'startBackgroundTask() has not been implemented.');
  }

  /// Signal completion of a background task by [taskId].
  Future<int> stopBackgroundTask(int taskId) {
    throw UnimplementedError(
        'stopBackgroundTask() has not been implemented.');
  }

  // ---------------------------------------------------------------------------
  // Logging
  // ---------------------------------------------------------------------------

  /// Get the plugin log. Optional [query] for filtering.
  Future<String> getLog([Map<String, Object?>? query]) {
    throw UnimplementedError('getLog() has not been implemented.');
  }

  /// Destroy all log entries.
  Future<bool> destroyLog() {
    throw UnimplementedError('destroyLog() has not been implemented.');
  }

  /// Email the log to [email].
  Future<bool> emailLog(String email) {
    throw UnimplementedError('emailLog() has not been implemented.');
  }

  /// Write a custom log entry at [level] with [message].
  Future<bool> log(String level, String message) {
    throw UnimplementedError('log() has not been implemented.');
  }

  // ---------------------------------------------------------------------------
  // Scheduling
  // ---------------------------------------------------------------------------

  /// Start schedule-based tracking. Returns [State] map.
  Future<Map<String, Object?>> startSchedule() {
    throw UnimplementedError('startSchedule() has not been implemented.');
  }

  /// Stop schedule-based tracking. Returns [State] map.
  Future<Map<String, Object?>> stopSchedule() {
    throw UnimplementedError('stopSchedule() has not been implemented.');
  }

  // ---------------------------------------------------------------------------
  // Headless
  // ---------------------------------------------------------------------------

  /// Register a headless task callback for background event dispatch.
  Future<bool> registerHeadlessTask(List<int> callbackIds) {
    throw UnimplementedError(
        'registerHeadlessTask() has not been implemented.');
  }
}
