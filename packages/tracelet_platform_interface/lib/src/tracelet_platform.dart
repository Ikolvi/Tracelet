import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'generated/tracelet_api.g.dart';
import 'pigeon_tracelet.dart';

/// The interface that platform implementations of Tracelet must extend.
///
/// Platform implementations should override all methods and provide
/// concrete native implementations. The default implementation is
/// [PigeonTracelet], which uses Pigeon-generated type-safe channels.
abstract class TraceletPlatform extends PlatformInterface {
  /// Constructs a [TraceletPlatform].
  TraceletPlatform() : super(token: _token);

  static final Object _token = Object();

  static TraceletPlatform _instance = PigeonTracelet();

  /// The current platform implementation.
  ///
  /// Defaults to [PigeonTracelet].
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

  /// Start periodic one-shot location tracking mode. Returns [State] map.
  ///
  /// Instead of continuous GPS updates, the engine wakes every
  /// `periodicLocationInterval` seconds, performs a single location fix,
  /// dispatches the result, and immediately turns the provider off.
  Future<Map<String, Object?>> startPeriodic() {
    throw UnimplementedError('startPeriodic() has not been implemented.');
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
  ///
  /// Supported [options] keys:
  /// - `desiredAccuracy` (`int`): Accuracy level index. Defaults to config value.
  /// - `timeout` (`int`): Timeout in seconds. Defaults to `30`.
  /// - `maximumAge` (`int`): Maximum age in ms of a cached location that is
  ///   acceptable to return. Defaults to `0` (always fetch fresh).
  /// - `persist` (`bool`): Whether to persist the location to the database.
  ///   Defaults to `true`.
  /// - `samples` (`int`): Number of location samples to collect and return
  ///   the best one (highest accuracy). Defaults to `1`.
  /// - `extras` (`Map<String, Object?>`): Extra data to attach to the location.
  Future<Map<String, Object?>> getCurrentPosition(
    Map<String, Object?> options,
  ) {
    throw UnimplementedError('getCurrentPosition() has not been implemented.');
  }

  /// Get the last known location without requesting a new fix.
  ///
  /// Returns the last cached location from the platform's location provider,
  /// or `null` (empty map) if no cached location is available. This is a
  /// battery-free operation — it never activates GPS/network providers.
  ///
  /// Supported [options] keys:
  /// - `persist` (`bool`): Whether to persist the location to the database.
  ///   Defaults to `false`.
  /// - `extras` (`Map<String, Object?>`): Extra data to attach to the location.
  Future<Map<String, Object?>> getLastKnownLocation([
    Map<String, Object?>? options,
  ]) {
    throw UnimplementedError(
      'getLastKnownLocation() has not been implemented.',
    );
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
  Future<List<Map<String, Object?>>> getLocations([
    Map<String, Object?>? query,
  ]) {
    throw UnimplementedError('getLocations() has not been implemented.');
  }

  /// Get the count of stored locations.
  ///
  /// Only `start` and `end` keys in [query] affect the result;
  /// `limit`, `offset`, and `order` are ignored for counting.
  Future<int> getCount([Map<String, Object?>? query]) {
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

  /// Update dynamic HTTP headers that are merged with static config headers
  /// at sync time.
  ///
  /// Unlike [HttpConfig.headers] (set once in config), dynamic headers can
  /// be refreshed at any time — ideal for rotating OAuth/JWT tokens.
  Future<bool> setDynamicHeaders(Map<String, String> headers) {
    throw UnimplementedError('setDynamicHeaders() has not been implemented.');
  }

  /// Set the current route context that will be persisted with every
  /// subsequently recorded location.
  ///
  /// Unlike [HttpConfig.extras], route context is captured immutably at
  /// location insert time, not at sync time.
  Future<bool> setRouteContext(Map<String, Object?> context) {
    throw UnimplementedError('setRouteContext() has not been implemented.');
  }

  /// Clear the current route context. Subsequent locations will have
  /// no route context attached.
  Future<bool> clearRouteContext() {
    throw UnimplementedError('clearRouteContext() has not been implemented.');
  }

  /// Register a headless headers callback for background token recovery.
  ///
  /// When the app is terminated and native sync receives a 401 response,
  /// it spawns a headless Dart isolate and invokes this callback to obtain
  /// fresh authorization headers, then retries the failed request once.
  Future<bool> registerHeadlessHeadersCallback(List<int> callbackIds) {
    throw UnimplementedError(
      'registerHeadlessHeadersCallback() has not been implemented.',
    );
  }

  /// Register a headless sync body builder for background custom payloads.
  ///
  /// When the app is terminated and native sync fires, it spawns a headless
  /// Dart isolate and invokes this callback with the location batch, allowing
  /// the app to build a custom HTTP request body even in the background.
  Future<bool> registerHeadlessSyncBodyBuilder(List<int> callbackIds) {
    throw UnimplementedError(
      'registerHeadlessSyncBodyBuilder() has not been implemented.',
    );
  }

  // ---------------------------------------------------------------------------
  // Utility
  // ---------------------------------------------------------------------------

  /// Whether the device is in power-save mode.
  Future<bool> isPowerSaveMode() {
    throw UnimplementedError('isPowerSaveMode() has not been implemented.');
  }

  /// Get current permission status without triggering any dialog.
  ///
  /// Returns a status code matching [AuthorizationStatus]:
  /// - `0` notDetermined — never asked
  /// - `1` denied — denied but can ask again (Android only)
  /// - `2` whenInUse — foreground granted
  /// - `3` always — background granted
  /// - `4` deniedForever — permanently denied, must open Settings
  Future<int> getPermissionStatus() {
    throw UnimplementedError('getPermissionStatus() has not been implemented.');
  }

  /// Request location permission asynchronously.
  ///
  /// Triggers the OS permission dialog and returns the **actual** result
  /// after the user responds. Does **not** show any custom native dialog.
  ///
  /// Escalation: notDetermined → foreground, whenInUse → background.
  /// Terminal states (denied/always) return immediately.
  Future<int> requestPermission() {
    throw UnimplementedError('requestPermission() has not been implemented.');
  }

  /// Get the notification permission status (Android 13+ / API 33+ only).
  ///
  /// Returns:
  /// - `0` notDetermined — never asked
  /// - `1` denied — denied but can ask again
  /// - `3` always (granted)
  /// - `4` deniedForever — permanently denied
  ///
  /// On Android < 13 and on iOS, always returns `3` (granted).
  Future<int> getNotificationPermissionStatus() {
    throw UnimplementedError(
      'getNotificationPermissionStatus() has not been implemented.',
    );
  }

  /// Request notification permission asynchronously (Android 13+ / API 33+).
  ///
  /// Triggers the OS POST_NOTIFICATIONS dialog and returns the actual result
  /// after the user responds.
  ///
  /// On Android < 13 and on iOS, returns `3` (granted) immediately.
  Future<int> requestNotificationPermission() {
    throw UnimplementedError(
      'requestNotificationPermission() has not been implemented.',
    );
  }

  /// Check whether the app can schedule exact alarms (Android 12+ / API 31+).
  ///
  /// Returns `true` if the app has the SCHEDULE_EXACT_ALARM permission
  /// (auto-granted on Android 12, must be enabled in Settings on Android 13+).
  ///
  /// On Android < 12, iOS, and web, always returns `true` (no restriction).
  ///
  /// **When to use:** Before starting periodic mode with intervals under
  /// 15 minutes. If `false`, timing will be approximate.
  Future<bool> canScheduleExactAlarms() {
    throw UnimplementedError(
      'canScheduleExactAlarms() has not been implemented.',
    );
  }

  /// Open the device Settings screen for granting exact alarm permission.
  ///
  /// On Android 12+ (API 31+), opens the "Alarms & reminders" settings
  /// page for this app. The user must manually toggle the permission.
  ///
  /// On Android < 12, iOS, and web, this is a no-op.
  ///
  /// Returns `true` if the settings intent was launched, `false` otherwise.
  Future<bool> openExactAlarmSettings() {
    throw UnimplementedError(
      'openExactAlarmSettings() has not been implemented.',
    );
  }

  /// Get the motion / activity recognition permission status.
  ///
  /// Returns:
  /// - `0` notDetermined — never asked
  /// - `1` denied — denied but can ask again (Android only)
  /// - `3` always (granted)
  /// - `4` deniedForever — permanently denied
  ///
  /// On Android < 10 (API < 29), always returns `3` since no runtime
  /// permission is needed. On iOS, returns the CMMotionActivityManager
  /// authorization status.
  Future<int> getMotionPermissionStatus() {
    throw UnimplementedError(
      'getMotionPermissionStatus() has not been implemented.',
    );
  }

  /// Request motion / activity recognition permission asynchronously.
  ///
  /// On Android 10+ (API 29+), triggers the ACTIVITY_RECOGNITION dialog.
  /// On iOS, triggers the Motion & Fitness permission dialog.
  /// On Android < 10, returns `3` (granted) immediately.
  Future<int> requestMotionPermission() {
    throw UnimplementedError(
      'requestMotionPermission() has not been implemented.',
    );
  }

  /// Request temporary full accuracy (iOS 14+). Returns accuracy status.
  Future<int> requestTemporaryFullAccuracy(String purpose) {
    throw UnimplementedError(
      'requestTemporaryFullAccuracy() has not been implemented.',
    );
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
      'isIgnoringBatteryOptimizations() has not been implemented.',
    );
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
  // OEM Compatibility
  // ---------------------------------------------------------------------------

  /// Get OEM settings health information.
  ///
  /// Returns a map containing:
  /// - `manufacturer` (`String`): Device manufacturer (e.g. "Huawei").
  /// - `model` (`String`): Device model.
  /// - `isAggressiveOem` (`bool`): Whether this OEM aggressively kills
  ///   background apps.
  /// - `aggressionRating` (`int`): Aggression rating 0–5 matching
  ///   dontkillmyapp.com scores.
  /// - `isIgnoringBatteryOptimizations` (`bool`): Whether the app is
  ///   exempt from battery optimizations.
  /// - `autostartAvailable` (`bool`): Whether the OEM autostart settings
  ///   screen is available (Xiaomi/MIUI).
  /// - `oemSettingsScreens` (`List<Map<String, String>>`): Available
  ///   OEM-specific settings screens with `label` and `description` keys.
  ///
  /// On iOS and Web, returns a minimal map with `isAggressiveOem: false`.
  Future<Map<String, Object?>> getSettingsHealth() {
    throw UnimplementedError('getSettingsHealth() has not been implemented.');
  }

  /// Open an OEM-specific settings screen by [label].
  ///
  /// The [label] must match one of the labels returned by
  /// [getSettingsHealth]'s `oemSettingsScreens` list.
  ///
  /// Returns `true` if the screen was opened, `false` if the label
  /// was not found or the intent could not be resolved.
  ///
  /// On iOS and Web, always returns `false`.
  Future<bool> openOemSettings(String label) {
    throw UnimplementedError('openOemSettings() has not been implemented.');
  }

  // ---------------------------------------------------------------------------
  // Background Tasks
  // ---------------------------------------------------------------------------

  /// Start a long-running background task. Returns task ID.
  Future<int> startBackgroundTask() {
    throw UnimplementedError('startBackgroundTask() has not been implemented.');
  }

  /// Signal completion of a background task by [taskId].
  Future<int> stopBackgroundTask(int taskId) {
    throw UnimplementedError('stopBackgroundTask() has not been implemented.');
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
      'registerHeadlessTask() has not been implemented.',
    );
  }

  // ---------------------------------------------------------------------------
  // Audit Trail (Enterprise)
  // ---------------------------------------------------------------------------

  /// Verify the integrity of the tamper-proof location audit trail.
  ///
  /// Walks all records in chain-index order, re-computes each hash, and
  /// compares it to the stored hash. Returns a verification result map.
  Future<Map<String, Object?>> verifyAuditTrail() {
    throw UnimplementedError('verifyAuditTrail() has not been implemented.');
  }

  /// Get the audit proof for a specific location record by [uuid].
  ///
  /// Returns `null` if audit trail is disabled or the record does not exist.
  Future<Map<String, Object?>?> getAuditProof(String uuid) {
    throw UnimplementedError('getAuditProof() has not been implemented.');
  }

  // ---------------------------------------------------------------------------
  // Privacy Zones (Enterprise)
  // ---------------------------------------------------------------------------

  /// Add a single privacy zone. Returns `true` on success.
  Future<bool> addPrivacyZone(Map<String, Object?> zone) {
    throw UnimplementedError('addPrivacyZone() has not been implemented.');
  }

  /// Add multiple privacy zones. Returns `true` on success.
  Future<bool> addPrivacyZones(List<Map<String, Object?>> zones) {
    throw UnimplementedError('addPrivacyZones() has not been implemented.');
  }

  /// Remove a privacy zone by [identifier]. Returns `true` on success.
  Future<bool> removePrivacyZone(String identifier) {
    throw UnimplementedError('removePrivacyZone() has not been implemented.');
  }

  /// Remove all privacy zones. Returns `true` on success.
  Future<bool> removePrivacyZones() {
    throw UnimplementedError('removePrivacyZones() has not been implemented.');
  }

  /// Get all registered privacy zones.
  Future<List<Map<String, Object?>>> getPrivacyZones() {
    throw UnimplementedError('getPrivacyZones() has not been implemented.');
  }

  // ---------------------------------------------------------------------------
  // Encrypted Database (Enterprise)
  // ---------------------------------------------------------------------------

  /// Check if the current database is encrypted.
  ///
  /// Returns `true` if the database is using AES-256 encryption via
  /// SQLCipher, `false` otherwise.
  Future<bool> isDatabaseEncrypted() {
    throw UnimplementedError('isDatabaseEncrypted() has not been implemented.');
  }

  /// Migrate an existing unencrypted database to encrypted (one-time).
  ///
  /// Returns `true` on success. Existing data is preserved. If the
  /// database is already encrypted, returns `true` immediately.
  Future<bool> encryptDatabase() {
    throw UnimplementedError('encryptDatabase() has not been implemented.');
  }

  // ---------------------------------------------------------------------------
  // Device Attestation (Enterprise)
  // ---------------------------------------------------------------------------

  /// Request a fresh attestation token from the platform.
  ///
  /// Returns a map with `token`, `timestamp`, `provider`, and optionally
  /// `verified` fields. Returns `null` on platforms that don't support
  /// attestation (web).
  ///
  /// - **Android**: Uses Google Play Integrity API.
  /// - **iOS**: Uses App Attest (iOS 14+) with DeviceCheck fallback.
  Future<Map<String, Object?>?> getAttestationToken() {
    throw UnimplementedError('getAttestationToken() has not been implemented.');
  }

  // ---------------------------------------------------------------------------
  // Dead Reckoning (Enterprise)
  // ---------------------------------------------------------------------------

  /// Get the current dead reckoning state.
  ///
  /// Returns a map with `active` (bool), `elapsed` (seconds since DR
  /// started), and `estimatedAccuracy` (meters). Returns `null` if dead
  /// reckoning is disabled or GPS signal is available.
  Future<Map<String, Object?>?> getDeadReckoningState() {
    throw UnimplementedError(
      'getDeadReckoningState() has not been implemented.',
    );
  }

  // ---------------------------------------------------------------------------
  // Carbon Estimator (Enterprise)
  // ---------------------------------------------------------------------------

  /// Get cumulative carbon emissions report.
  ///
  /// Returns a map with `totalCarbonGrams`, `carbonByMode`,
  /// `distanceByMode`, and `totalTrips` fields.
  ///
  /// Optionally filter by [query] with `from` and `to` timestamps.
  Future<Map<String, Object?>> getCarbonReport([Map<String, Object?>? query]) {
    throw UnimplementedError('getCarbonReport() has not been implemented.');
  }

  // ---------------------------------------------------------------------------
  // Event Streams
  //
  // Type-safe streams that receive events from the native platform via
  // Pigeon FlutterApi streams (native → Dart via TraceletEventApi).
  // ---------------------------------------------------------------------------

  /// Stream of location events.
  Stream<TlLocation> get locationEvents {
    throw UnimplementedError('locationEvents has not been implemented.');
  }

  /// Stream of motion change events (stationary ↔ moving).
  Stream<TlLocation> get motionChangeEvents {
    throw UnimplementedError('motionChangeEvents has not been implemented.');
  }

  /// Stream of activity change events.
  Stream<TlActivityChangeEvent> get activityChangeEvents {
    throw UnimplementedError('activityChangeEvents has not been implemented.');
  }

  /// Stream of provider change events.
  Stream<TlProviderChangeEvent> get providerChangeEvents {
    throw UnimplementedError('providerChangeEvents has not been implemented.');
  }

  /// Stream of geofence transition events.
  Stream<TlGeofenceEvent> get geofenceEvents {
    throw UnimplementedError('geofenceEvents has not been implemented.');
  }

  /// Stream of geofences change events (monitor set changed).
  Stream<TlGeofencesChangeEvent> get geofencesChangeEvents {
    throw UnimplementedError('geofencesChangeEvents has not been implemented.');
  }

  /// Stream of heartbeat events.
  Stream<TlHeartbeatEvent> get heartbeatEvents {
    throw UnimplementedError('heartbeatEvents has not been implemented.');
  }

  /// Stream of HTTP sync events.
  Stream<TlHttpEvent> get httpEvents {
    throw UnimplementedError('httpEvents has not been implemented.');
  }

  /// Stream of schedule events (start/stop transitions).
  Stream<TlState> get scheduleEvents {
    throw UnimplementedError('scheduleEvents has not been implemented.');
  }

  /// Stream of power-save mode change events.
  Stream<bool> get powerSaveChangeEvents {
    throw UnimplementedError('powerSaveChangeEvents has not been implemented.');
  }

  /// Stream of connectivity change events.
  Stream<TlConnectivityChangeEvent> get connectivityChangeEvents {
    throw UnimplementedError(
      'connectivityChangeEvents has not been implemented.',
    );
  }

  /// Stream of enabled-change events.
  Stream<bool> get enabledChangeEvents {
    throw UnimplementedError('enabledChangeEvents has not been implemented.');
  }

  /// Stream of notification action events (Android).
  Stream<String> get notificationActionEvents {
    throw UnimplementedError(
      'notificationActionEvents has not been implemented.',
    );
  }

  /// Stream of authorization events (token refresh).
  Stream<TlAuthorizationEvent> get authorizationEvents {
    throw UnimplementedError('authorizationEvents has not been implemented.');
  }

  /// Stream of watchPosition events.
  Stream<TlLocation> get watchPositionEvents {
    throw UnimplementedError('watchPositionEvents has not been implemented.');
  }
}
