// Copyright 2024 Tracelet. All rights reserved.
// Use of this source code is governed by an Apache 2.0 license that can be
// found in the LICENSE file.

// ignore_for_file: avoid_positional_boolean_parameters

import 'package:pigeon/pigeon.dart';

// =============================================================================
// Pigeon schema for Tracelet Dart↔Native communication.
//
// This file defines the type-safe API contract between Dart and native
// platforms (Android/Kotlin and iOS/Swift). Run pigeon to generate:
//
//   dart run pigeon --input pigeons/tracelet_api.dart
//
// Generated files:
//   - lib/src/generated/tracelet_api.g.dart       (Dart)
//   - android/.../TraceletApi.g.kt                (Kotlin)
//   - ios/.../TraceletApi.g.swift                  (Swift)
//
// MIGRATION PLAN:
// This Pigeon schema replaces the raw MethodChannel-based communication
// in MethodChannelTracelet. Migration steps:
//   1. Define typed messages and host APIs here (this file)
//   2. Generate code with `dart run pigeon`
//   3. Implement TraceletHostApi in Kotlin and Swift
//   4. Replace MethodChannelTracelet with PigeonTracelet
//   5. EventChannels replaced by TraceletEventApi (Pigeon FlutterApi)
//
// Note: TripManager and BatteryBudgetEngine are pure Dart algorithms
// and do NOT need Pigeon definitions — they never cross the native boundary.
// =============================================================================

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/generated/tracelet_api.g.dart',
    dartPackageName: 'tracelet_platform_interface',
    kotlinOut:
        '../tracelet_android/android/src/main/kotlin/com/ikolvi/tracelet/TraceletApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.ikolvi.tracelet'),
    swiftOut:
        '../tracelet_ios/ios/tracelet_ios/Sources/tracelet_ios/TraceletApi.g.swift',
  ),
)
// =============================================================================
// Enums
// =============================================================================
/// Desired accuracy level for location requests.
enum TlDesiredAccuracy { high, medium, low, veryLow, passive }

/// Tracking mode.
enum TlTrackingMode { location, geofences, periodic }

/// Geofence transition action.
enum TlGeofenceAction { enter, exit, dwell }

/// Authorization status for location permissions.
enum TlAuthorizationStatus {
  notDetermined,
  denied,
  whenInUse,
  always,
  deniedForever,
}

/// HTTP method for sync.
enum TlHttpMethod { post, put }

// =============================================================================
// Data Messages — typed replacements for Map<String, Object?>
// =============================================================================

/// Coordinates sub-message within a location.
class TlCoords {
  TlCoords({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.speed,
    required this.heading,
    required this.altitude,
    required this.altitudeAccuracy,
    required this.speedAccuracy,
    required this.headingAccuracy,
    this.ellipsoidalAltitude,
    this.floor,
  });

  final double latitude;
  final double longitude;
  final double accuracy;
  final double speed;
  final double heading;
  final double altitude;
  final double altitudeAccuracy;
  final double speedAccuracy;
  final double headingAccuracy;
  final double? ellipsoidalAltitude;
  final int? floor;
}

/// Battery info sub-message.
class TlBattery {
  TlBattery({required this.level, required this.isCharging});

  final double level;
  final bool isCharging;
}

/// A location fix returned from the native platform.
class TlLocation {
  TlLocation({
    required this.coords,
    required this.battery,
    required this.timestamp,
    required this.uuid,
    required this.isMoving,
    required this.odometer,
    this.event,
    this.activity,
    this.extras,
  });

  final TlCoords coords;
  final TlBattery battery;
  final String timestamp;
  final String uuid;
  final bool isMoving;
  final double odometer;
  final String? event;
  final TlActivity? activity;
  final Map<String?, Object?>? extras;
}

/// Activity classification.
class TlActivity {
  TlActivity({required this.type, required this.confidence});

  final String type;
  final int confidence;
}

/// Plugin state returned by ready/start/stop/getState.
class TlState {
  TlState({
    required this.enabled,
    required this.isMoving,
    required this.trackingMode,
    required this.schedulerEnabled,
    required this.odometer,
    this.lastLocationTimestamp,
  });

  final bool enabled;
  final bool isMoving;
  final int trackingMode;
  final bool schedulerEnabled;
  final double odometer;
  final String? lastLocationTimestamp;
}

/// A geofence definition.
class TlGeofence {
  TlGeofence({
    required this.identifier,
    required this.latitude,
    required this.longitude,
    required this.radius,
    this.notifyOnEntry = true,
    this.notifyOnExit = true,
    this.notifyOnDwell = false,
    this.loiteringDelay = 0,
    this.extras,
    this.vertices,
  });

  final String identifier;
  final double latitude;
  final double longitude;
  final double radius;
  final bool notifyOnEntry;
  final bool notifyOnExit;
  final bool notifyOnDwell;
  final int loiteringDelay;
  final Map<String?, Object?>? extras;
  final List<List<double?>?>? vertices;
}

/// Geofence event fired on transitions.
class TlGeofenceEvent {
  TlGeofenceEvent({
    required this.identifier,
    required this.action,
    required this.location,
    this.extras,
  });

  final String identifier;
  final TlGeofenceAction action;
  final TlLocation location;
  final Map<String?, Object?>? extras;
}

/// HTTP sync event.
class TlHttpEvent {
  TlHttpEvent({
    required this.isSuccess,
    required this.status,
    required this.responseText,
  });

  final bool isSuccess;
  final int status;
  final String responseText;
}

/// Provider change event (GPS/network/authorization state).
class TlProviderChangeEvent {
  TlProviderChangeEvent({
    required this.enabled,
    required this.gps,
    required this.network,
    required this.status,
    this.accuracyAuthorization,
  });

  final bool enabled;
  final bool gps;
  final bool network;
  final int status;
  final int? accuracyAuthorization;
}

/// Options for getCurrentPosition.
class TlCurrentPositionOptions {
  TlCurrentPositionOptions({
    this.desiredAccuracy,
    this.timeout = 30,
    this.maximumAge = 0,
    this.persist = true,
    this.samples = 1,
    this.extras,
  });

  final TlDesiredAccuracy? desiredAccuracy;
  final int timeout;
  final int maximumAge;
  final bool persist;
  final int samples;
  final Map<String?, Object?>? extras;
}

/// Activity change event data.
class TlActivityChangeEvent {
  TlActivityChangeEvent({required this.activity, required this.confidence});

  /// Activity type name (e.g. "still", "walking", "in_vehicle").
  final String activity;

  /// Confidence percentage (0–100).
  final int confidence;
}

/// Change in the set of actively monitored geofences.
class TlGeofencesChangeEvent {
  TlGeofencesChangeEvent({this.on, this.off});

  /// Geofences that were activated (started monitoring).
  final List<TlGeofence>? on;

  /// Geofences that were deactivated (stopped monitoring).
  final List<TlGeofence>? off;
}

/// Heartbeat event data (periodic location check-in).
class TlHeartbeatEvent {
  TlHeartbeatEvent({required this.location});

  final TlLocation location;
}

/// Authorization / token-refresh event data.
class TlAuthorizationEvent {
  TlAuthorizationEvent({
    required this.success,
    required this.status,
    this.response = '',
  });

  final bool success;
  final int status;
  final String response;
}

/// Connectivity change event data.
class TlConnectivityChangeEvent {
  TlConnectivityChangeEvent({required this.connected});

  final bool connected;
}

// =============================================================================
// Host API — Dart calls native (request/response)
//
// These methods replace the raw MethodChannel.invokeMethod calls in
// MethodChannelTracelet. Each method is strongly typed.
// =============================================================================

@HostApi()
abstract class TraceletHostApi {
  // ── Lifecycle ──────────────────────────────────────────────────────────

  /// Initialize the plugin with configuration. Returns current state.
  @async
  TlState ready(Map<String, Object?> config);

  /// Start location tracking. Returns current state.
  @async
  TlState start();

  /// Stop location tracking. Returns current state.
  @async
  TlState stop();

  /// Start geofence-only mode. Returns current state.
  @async
  TlState startGeofences();

  /// Start periodic one-shot mode. Returns current state.
  @async
  TlState startPeriodic();

  /// Get current plugin state.
  @async
  TlState getState();

  /// Update configuration. Returns current state.
  @async
  TlState setConfig(Map<String, Object?> config);

  /// Reset to defaults. Returns current state.
  @async
  TlState reset(Map<String, Object?>? config);

  // ── Location ───────────────────────────────────────────────────────────

  /// Get current position with options.
  @async
  TlLocation getCurrentPosition(TlCurrentPositionOptions options);

  /// Get last known position without triggering a fix.
  @async
  TlLocation? getLastKnownLocation(Map<String, Object?>? options);

  /// Start watching position at an interval. Returns a watch ID.
  @async
  int watchPosition(Map<String, Object?> options);

  /// Stop a position watch by ID.
  @async
  bool stopWatchPosition(int watchId);

  /// Toggle motion state.
  @async
  bool changePace(bool isMoving);

  /// Get odometer value in meters.
  @async
  double getOdometer();

  /// Reset odometer. Returns location at reset point.
  @async
  TlLocation setOdometer(double value);

  // ── Geofencing ─────────────────────────────────────────────────────────

  /// Add a single geofence.
  @async
  bool addGeofence(TlGeofence geofence);

  /// Add multiple geofences.
  @async
  bool addGeofences(List<TlGeofence> geofences);

  /// Remove a geofence by identifier.
  @async
  bool removeGeofence(String identifier);

  /// Remove all geofences.
  @async
  bool removeGeofences();

  /// Get all registered geofences.
  @async
  List<TlGeofence> getGeofences();

  /// Get a single geofence by identifier.
  @async
  TlGeofence? getGeofence(String identifier);

  /// Check if a geofence exists.
  @async
  bool geofenceExists(String identifier);

  // ── Persistence ────────────────────────────────────────────────────────

  /// Get stored locations.
  @async
  List<TlLocation> getLocations(Map<String, Object?>? query);

  /// Get count of stored locations.
  @async
  int getCount(Map<String, Object?>? query);

  /// Delete all stored locations.
  @async
  bool destroyLocations();

  /// Delete only synced locations from the database. Returns count deleted.
  @async
  int destroySyncedLocations();

  /// Delete a single location by UUID.
  @async
  bool destroyLocation(String uuid);

  /// Insert a custom location. Returns UUID.
  @async
  String insertLocation(Map<String, Object?> params);

  // ── HTTP Sync ──────────────────────────────────────────────────────────

  /// Manually trigger HTTP sync. Returns synced locations.
  @async
  List<TlLocation> sync();

  /// Update dynamic HTTP headers.
  @async
  bool setDynamicHeaders(Map<String, String> headers);

  /// Set route context for subsequent locations.
  @async
  bool setRouteContext(Map<String, Object?> context);

  /// Clear route context.
  @async
  bool clearRouteContext();

  // ── Permissions ────────────────────────────────────────────────────────

  /// Get location permission status.
  @async
  TlAuthorizationStatus getPermissionStatus();

  /// Request location permission. Returns result.
  @async
  TlAuthorizationStatus requestPermission();

  /// Get notification permission status (Android 13+).
  @async
  int getNotificationPermissionStatus();

  /// Request notification permission (Android 13+).
  @async
  int requestNotificationPermission();

  /// Check if exact alarms can be scheduled (Android 12+).
  @async
  bool canScheduleExactAlarms();

  /// Open exact alarm settings (Android 12+).
  @async
  bool openExactAlarmSettings();

  /// Get motion/activity recognition permission status.
  @async
  int getMotionPermissionStatus();

  /// Request motion/activity recognition permission.
  @async
  int requestMotionPermission();

  /// Request temporary full accuracy (iOS 14+). Returns accuracy status.
  @async
  int requestTemporaryFullAccuracy(String purpose);

  // ── Utility ────────────────────────────────────────────────────────────

  /// Whether device is in power-save mode.
  @async
  bool isPowerSaveMode();

  /// Get location provider state.
  @async
  TlProviderChangeEvent getProviderState();

  /// Get device info.
  @async
  Map<String, Object?> getDeviceInfo();

  /// Get available sensors.
  @async
  Map<String, Object?> getSensors();

  /// Play a debug sound.
  @async
  bool playSound(String name);

  /// Whether ignoring battery optimizations (Android).
  @async
  bool isIgnoringBatteryOptimizations();

  /// Request a system settings page (e.g., battery optimization).
  @async
  bool requestSettings(String action);

  /// Show a system settings page (e.g., location settings).
  @async
  bool showSettings(String action);

  /// Get OEM settings health information.
  @async
  Map<String, Object?> getSettingsHealth();

  /// Open an OEM-specific settings screen by label.
  @async
  bool openOemSettings(String label);

  // ── Logging ────────────────────────────────────────────────────────────

  /// Get plugin log.
  @async
  String getLog(Map<String, Object?>? query);

  /// Destroy all log entries.
  @async
  bool destroyLog();

  /// Email the log.
  @async
  bool emailLog(String email);

  /// Write a custom log entry.
  @async
  bool log(String level, String message);

  // ── Scheduling ─────────────────────────────────────────────────────────

  /// Start schedule-based tracking.
  @async
  TlState startSchedule();

  /// Stop schedule-based tracking.
  @async
  TlState stopSchedule();

  // ── Background Tasks ───────────────────────────────────────────────────

  /// Start a background task. Returns task ID.
  @async
  int startBackgroundTask();

  /// Complete a background task.
  @async
  int stopBackgroundTask(int taskId);

  // ── Headless ───────────────────────────────────────────────────────────

  /// Register a headless task callback for background event dispatch.
  @async
  bool registerHeadlessTask(List<int> callbackIds);

  /// Register a headless headers callback for background token recovery.
  @async
  bool registerHeadlessHeadersCallback(List<int> callbackIds);

  /// Register a headless sync body builder for background custom payloads.
  @async
  bool registerHeadlessSyncBodyBuilder(List<int> callbackIds);

  // ── Enterprise: Audit Trail ────────────────────────────────────────────

  /// Verify audit trail integrity.
  @async
  Map<String, Object?> verifyAuditTrail();

  /// Get audit proof for a location UUID.
  @async
  Map<String, Object?>? getAuditProof(String uuid);

  // ── Enterprise: Privacy Zones ──────────────────────────────────────────

  /// Add a privacy zone.
  @async
  bool addPrivacyZone(Map<String, Object?> zone);

  /// Add multiple privacy zones.
  @async
  bool addPrivacyZones(List<Map<String, Object?>> zones);

  /// Remove a privacy zone by identifier.
  @async
  bool removePrivacyZone(String identifier);

  /// Remove all privacy zones.
  @async
  bool removePrivacyZones();

  /// Get all privacy zones.
  @async
  List<Map<String, Object?>> getPrivacyZones();

  // ── Enterprise: Encrypted Database ─────────────────────────────────────

  /// Check if database is encrypted.
  @async
  bool isDatabaseEncrypted();

  /// Encrypt the database (one-time migration).
  @async
  bool encryptDatabase();

  // ── Enterprise: Device Attestation ─────────────────────────────────────

  /// Get a device attestation token.
  @async
  Map<String, Object?>? getAttestationToken();

  // ── Enterprise: Carbon Estimator ───────────────────────────────────────

  /// Get carbon emissions report.
  @async
  Map<String, Object?> getCarbonReport(Map<String, Object?>? query);

  // ── Enterprise: Dead Reckoning ─────────────────────────────────────────

  /// Get dead reckoning state.
  @async
  Map<String, Object?>? getDeadReckoningState();
}

// =============================================================================
// Flutter API — Native calls Dart
//
// TraceletFlutterApi: Headless callbacks (background isolate).
// TraceletEventApi:   Streaming events (location, motion, geofence, etc.)
//                     replacing raw EventChannels with type-safe Pigeon calls.
// =============================================================================

@FlutterApi()
abstract class TraceletFlutterApi {
  /// Called by native when a headless event fires.
  void onHeadlessEvent(Map<String, Object?> event);

  /// Called by native to request fresh authorization headers (401 recovery).
  @async
  Map<String, String> onHeadlessHeaders();
}

/// Type-safe event channel replacement.
///
/// Native platforms call these methods to push events to Dart instead of
/// using raw EventChannel/EventSink. Each method maps to one event type.
@FlutterApi()
abstract class TraceletEventApi {
  /// Fired on every recorded location.
  void onLocation(TlLocation location);

  /// Fired when motion state changes (stationary ↔ moving).
  void onMotionChange(TlLocation location);

  /// Fired when detected activity type changes (walking, running, etc.).
  void onActivityChange(TlActivityChangeEvent event);

  /// Fired when location provider state changes (GPS, network, authorization).
  void onProviderChange(TlProviderChangeEvent event);

  /// Fired on geofence transition (enter, exit, dwell).
  void onGeofence(TlGeofenceEvent event);

  /// Fired when monitored geofences change (activated/deactivated list).
  void onGeofencesChange(TlGeofencesChangeEvent event);

  /// Fired at configured heartbeat interval.
  void onHeartbeat(TlHeartbeatEvent event);

  /// Fired on HTTP sync attempt (success or failure).
  void onHttp(TlHttpEvent event);

  /// Fired on schedule start/stop transitions.
  void onSchedule(TlState state);

  /// Fired when device power-save mode toggles.
  void onPowerSaveChange(bool isPowerSaveMode);

  /// Fired when network connectivity changes.
  void onConnectivityChange(TlConnectivityChangeEvent event);

  /// Fired when tracking is enabled or disabled.
  void onEnabledChange(bool enabled);

  /// Fired when user taps a notification action button (Android).
  void onNotificationAction(String action);

  /// Fired on HTTP authorization events (token refresh).
  void onAuthorization(TlAuthorizationEvent event);

  /// Fired for watchPosition updates.
  void onWatchPosition(TlLocation location);
}
