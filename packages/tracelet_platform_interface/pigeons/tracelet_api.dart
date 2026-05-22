// Copyright 2024 Tracelet. All rights reserved.
// Use of this source code is governed by an Apache 2.0 license that can be
// found in the LICENSE file.

// ignore_for_file: avoid_positional_boolean_parameters

import 'package:pigeon/pigeon.dart';

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
enum TlDesiredAccuracy { high, medium, low, veryLow, passive }

enum TlTrackingMode { location, geofences, periodic }

enum TlMotionDetectionMode { accelerometer, speed }

enum TlStationaryTrackingMode { periodic, geofences }

enum TlGeofenceAction { enter, exit, dwell }

enum TlAuthorizationStatus {
  notDetermined,
  restricted,
  denied,
  whenInUse,
  always,
  deniedForever,
}

enum TlMotionAuthorizationStatus {
  notDetermined,
  restricted,
  denied,
  authorized,
  deniedForever,
}

enum TlNotificationAuthorizationStatus {
  notDetermined,
  denied,
  authorized,
  deniedForever,
  provisional,
  ephemeral,
}

enum TlHttpMethod { post, put }

enum TlIosActivityType { other, automotive, fitness, otherNavigation, airborne }

enum TlNotificationPriority { min, low, defaultPriority, high, max }

// =============================================================================
// Configuration Messages
// =============================================================================

class TlGeoConfig {
  TlGeoConfig({
    required this.desiredAccuracy,
    required this.distanceFilter,
    required this.stationaryRadius,
    required this.locationTimeout,
    required this.disableElasticity,
    required this.elasticityMultiplier,
    required this.stopAfterElapsedMinutes,
    required this.maxMonitoredGeofences,
    required this.enableTimestampMeta,
    required this.enableAdaptiveMode,
    required this.periodicLocationInterval,
    required this.periodicDesiredAccuracy,
    required this.enableSparseUpdates,
    required this.sparseDistanceThreshold,
    required this.sparseMaxIdleSeconds,
    required this.enableDeadReckoning,
    required this.deadReckoningActivationDelay,
    required this.deadReckoningMaxDuration,
    required this.batteryBudgetPerHour,
  });

  final TlDesiredAccuracy desiredAccuracy;
  final double distanceFilter;
  final double stationaryRadius;
  final int locationTimeout;
  final bool disableElasticity;
  final double elasticityMultiplier;
  final int stopAfterElapsedMinutes;
  final int maxMonitoredGeofences;
  final bool enableTimestampMeta;
  final bool enableAdaptiveMode;
  final int periodicLocationInterval;
  final TlDesiredAccuracy periodicDesiredAccuracy;
  final bool enableSparseUpdates;
  final double sparseDistanceThreshold;
  final int sparseMaxIdleSeconds;
  final bool enableDeadReckoning;
  final int deadReckoningActivationDelay;
  final int deadReckoningMaxDuration;
  final double batteryBudgetPerHour;
}

class TlAppConfig {
  TlAppConfig({
    required this.stopOnTerminate,
    required this.startOnBoot,
    required this.heartbeatInterval,
    required this.schedule,
    this.remoteConfigUrl,
    this.remoteConfigHeaders,
    required this.remoteConfigTimeout,
    required this.remoteConfigRefreshInterval,
  });

  final bool stopOnTerminate;
  final bool startOnBoot;
  final int heartbeatInterval;
  final List<String?> schedule;
  final String? remoteConfigUrl;
  final Map<String?, String?>? remoteConfigHeaders;
  final int remoteConfigTimeout;
  final int remoteConfigRefreshInterval;
}

class TlForegroundServiceConfig {
  TlForegroundServiceConfig({
    required this.enabled,
    required this.channelId,
    required this.channelName,
    required this.notificationTitle,
    required this.notificationText,
    this.notificationColor,
    this.notificationSmallIcon,
    this.notificationLargeIcon,
    required this.notificationPriority,
    required this.notificationOngoing,
    required this.actions,
  });

  final bool enabled;
  final String channelId;
  final String channelName;
  final String notificationTitle;
  final String notificationText;
  final String? notificationColor;
  final String? notificationSmallIcon;
  final String? notificationLargeIcon;
  final TlNotificationPriority notificationPriority;
  final bool notificationOngoing;
  final List<String?> actions;
}

class TlAndroidConfig {
  TlAndroidConfig({
    required this.locationUpdateInterval,
    required this.fastestLocationUpdateInterval,
    required this.deferTime,
    required this.allowIdenticalLocations,
    required this.geofenceModeHighAccuracy,
    required this.periodicUseForegroundService,
    required this.periodicUseExactAlarms,
    required this.scheduleUseAlarmManager,
    required this.foregroundService,
  });

  final int locationUpdateInterval;
  final int fastestLocationUpdateInterval;
  final int deferTime;
  final bool allowIdenticalLocations;
  final bool geofenceModeHighAccuracy;
  final bool periodicUseForegroundService;
  final bool periodicUseExactAlarms;
  final bool scheduleUseAlarmManager;
  final TlForegroundServiceConfig foregroundService;
}

class TlIosConfig {
  TlIosConfig({
    required this.activityType,
    required this.useSignificantChangesOnly,
    required this.showsBackgroundLocationIndicator,
    required this.pausesLocationUpdatesAutomatically,
    required this.locationAuthorizationRequest,
    required this.disableLocationAuthorizationAlert,
    required this.preventSuspend,
  });

  final TlIosActivityType activityType;
  final bool useSignificantChangesOnly;
  final bool showsBackgroundLocationIndicator;
  final bool pausesLocationUpdatesAutomatically;
  final TlAuthorizationRequest locationAuthorizationRequest;
  final bool disableLocationAuthorizationAlert;
  final bool preventSuspend;
}

enum TlLocationOrderDirection { ascending, descending }

class TlHttpConfig {
  TlHttpConfig({
    this.url,
    required this.method,
    this.headers,
    this.params,
    required this.autoSync,
    required this.batchSync,
    required this.maxBatchSize,
    this.sslPinningFingerprints,
    this.sslPinningCertificates,
    this.httpRootProperty,
    required this.autoSyncThreshold,
    required this.httpTimeout,
    required this.locationsOrderDirection,
    this.extras,
    required this.disableAutoSyncOnCellular,
    required this.maxRetries,
    required this.retryBackoffBase,
    required this.retryBackoffCap,
    required this.enableDeltaCompression,
    required this.deltaCoordinatePrecision,
  });

  final String? url;
  final TlHttpMethod method;
  final Map<String?, String?>? headers;
  final Map<String?, Object?>? params;
  final bool autoSync;
  final bool batchSync;
  final int maxBatchSize;
  final List<String?>? sslPinningFingerprints;
  final List<String?>? sslPinningCertificates;
  final String? httpRootProperty;
  final int autoSyncThreshold;
  final int httpTimeout;
  final TlLocationOrderDirection locationsOrderDirection;
  final Map<String?, Object?>? extras;
  final bool disableAutoSyncOnCellular;
  final int maxRetries;
  final int retryBackoffBase;
  final int retryBackoffCap;
  final bool enableDeltaCompression;
  final int deltaCoordinatePrecision;
}

class TlConfig {
  TlConfig({
    required this.geo,
    required this.app,
    required this.android,
    required this.ios,
    required this.http,
    required this.logger,
    required this.motion,
    required this.geofence,
    required this.persistence,
    required this.audit,
    required this.privacyZone,
    required this.security,
    required this.attestation,
  });

  final TlGeoConfig geo;
  final TlAppConfig app;
  final TlAndroidConfig android;
  final TlIosConfig ios;
  final TlHttpConfig http;
  final TlLoggerConfig logger;
  final TlMotionConfig motion;
  final TlGeofenceConfig geofence;
  final TlPersistenceConfig persistence;
  final TlAuditConfig audit;
  final TlPrivacyZoneConfig privacyZone;
  final TlSecurityConfig security;
  final TlAttestationConfig attestation;
}

class TlLoggerConfig {
  TlLoggerConfig({
    required this.logLevel,
    required this.logMaxDays,
    required this.debug,
  });
  final TlLogLevel logLevel;
  final int logMaxDays;
  final bool debug;
}

enum TlLocationActivityType {
  still,
  walking,
  running,
  onFoot,
  inVehicle,
  onBicycle,
  unknown,
}

class TlMotionConfig {
  TlMotionConfig({
    required this.stopTimeout,
    required this.motionTriggerDelay,
    required this.disableMotionActivityUpdates,
    required this.isMoving,
    required this.activityRecognitionInterval,
    required this.minimumActivityRecognitionConfidence,
    required this.disableStopDetection,
    required this.stopDetectionDelay,
    required this.stopOnStationary,
    this.activityTypes,
    required this.stationaryRadius,
    required this.useSignificantChangesOnly,
    required this.shakeThreshold,
    required this.stillThreshold,
    required this.stillSampleCount,
    required this.motionDetectionMode,
    required this.speedMovingThreshold,
    required this.speedStationaryDelay,
    required this.stationaryTrackingMode,
    required this.stationaryPeriodicInterval,
    required this.stationaryPeriodicAccuracy,
    required this.speedWakeConfirmCount,
  });
  final int stopTimeout;
  final int motionTriggerDelay;
  final bool disableMotionActivityUpdates;
  final bool isMoving;
  final int activityRecognitionInterval;
  final int minimumActivityRecognitionConfidence;
  final bool disableStopDetection;
  final int stopDetectionDelay;
  final bool stopOnStationary;
  final List<TlLocationActivityType?>? activityTypes;
  final double stationaryRadius;
  final bool useSignificantChangesOnly;
  final double shakeThreshold;
  final double stillThreshold;
  final int stillSampleCount;
  final TlMotionDetectionMode motionDetectionMode;
  final double speedMovingThreshold;
  final int speedStationaryDelay;
  final TlStationaryTrackingMode stationaryTrackingMode;
  final int stationaryPeriodicInterval;
  final TlDesiredAccuracy stationaryPeriodicAccuracy;
  final int speedWakeConfirmCount;
}

class TlGeofenceConfig {
  TlGeofenceConfig({
    required this.geofenceModeHighAccuracy,
    required this.geofenceInitialTriggerEntry,
    required this.geofenceProximityRadius,
    required this.geofenceInitialTrigger,
  });
  final bool geofenceModeHighAccuracy;
  final bool geofenceInitialTriggerEntry;
  final int geofenceProximityRadius;
  final bool geofenceInitialTrigger;
}

class TlPersistenceConfig {
  TlPersistenceConfig({
    required this.persistMode,
    required this.maxDaysToPersist,
    required this.maxRecordsToPersist,
    required this.disableProviderChangeRecord,
  });
  final TlPersistMode persistMode;
  final int maxDaysToPersist;
  final int maxRecordsToPersist;
  final bool disableProviderChangeRecord;
}

class TlAuditConfig {
  TlAuditConfig({required this.enabled, required this.hashAlgorithm});
  final bool enabled;
  final TlHashAlgorithm hashAlgorithm;
}

class TlPrivacyZoneConfig {
  TlPrivacyZoneConfig({required this.enabled});
  final bool enabled;
}

class TlSecurityConfig {
  TlSecurityConfig({required this.encryptDatabase});
  final bool encryptDatabase;
}

class TlAttestationConfig {
  TlAttestationConfig({required this.enabled, required this.refreshInterval});
  final bool enabled;
  final int refreshInterval;
}

enum TlLogLevel { off, error, warn, info, debug, verbose }

enum TlPersistMode { all, location, geofence, none }

enum TlHashAlgorithm { sha256 }

enum TlAuthorizationRequest { always, whenInUse }

// =============================================================================
// Data Messages
// =============================================================================

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

class TlBattery {
  TlBattery({required this.level, required this.isCharging});
  final double level;
  final bool isCharging;
}

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

class TlActivity {
  TlActivity({required this.type, required this.confidence});
  final String type;
  final int confidence;
}

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
  final TlTrackingMode trackingMode;
  final bool schedulerEnabled;
  final double odometer;
  final String? lastLocationTimestamp;
}

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

class TlActivityChangeEvent {
  TlActivityChangeEvent({required this.activity, required this.confidence});
  final String activity;
  final int confidence;
}

class TlGeofencesChangeEvent {
  TlGeofencesChangeEvent({this.on, this.off});
  final List<TlGeofence?>? on;
  final List<TlGeofence?>? off;
}

class TlHeartbeatEvent {
  TlHeartbeatEvent({required this.location});
  final TlLocation location;
}

class TlSpeedMotionEvent {
  TlSpeedMotionEvent({
    required this.state,
    required this.previousState,
    required this.trackingMode,
  });

  /// New state: `"moving"`, `"slowing"`, or `"stationary"`.
  final String state;

  /// Previous state before this transition.
  final String previousState;

  /// Underlying tracking mode after the transition: `"continuous"`,
  /// `"periodic"`, or `"geofences"`.
  final String trackingMode;
}

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

class TlConnectivityChangeEvent {
  TlConnectivityChangeEvent({required this.connected});
  final bool connected;
}

// =============================================================================
// Host API
// =============================================================================

@HostApi()
abstract class TraceletHostApi {
  @async
  TlState ready(TlConfig config);

  @async
  TlState start();

  @async
  TlState stop();

  @async
  TlState startGeofences();

  @async
  TlState startPeriodic();

  @async
  TlState getState();

  @async
  TlState setConfig(TlConfig config);

  @async
  TlState reset(TlConfig? config);

  @async
  TlLocation getCurrentPosition(TlCurrentPositionOptions options);

  @async
  TlLocation? getLastKnownLocation(TlCurrentPositionOptions? options);

  @async
  int watchPosition(TlCurrentPositionOptions options);

  @async
  bool stopWatchPosition(int watchId);

  @async
  bool changePace(bool isMoving);

  @async
  double getOdometer();

  @async
  TlLocation setOdometer(double value);

  @async
  bool addGeofence(TlGeofence geofence);

  @async
  bool addGeofences(List<TlGeofence> geofences);

  @async
  bool removeGeofence(String identifier);

  @async
  bool removeGeofences();

  @async
  List<TlGeofence?> getGeofences();

  @async
  TlGeofence? getGeofence(String identifier);

  @async
  bool geofenceExists(String identifier);

  @async
  List<TlLocation?> getLocations(Map<String?, Object?>? query);

  @async
  int getCount(Map<String?, Object?>? query);

  @async
  String insertLocation(Map<String?, Object?> params);

  @async
  bool destroyLocations();

  @async
  int destroySyncedLocations();

  @async
  bool destroyLocation(String uuid);

  @async
  List<TlLocation?> sync();

  @async
  bool setDynamicHeaders(Map<String?, String?> headers);

  @async
  bool setRouteContext(Map<String?, Object?> context);

  @async
  bool clearRouteContext();

  @async
  bool registerHeadlessHeadersCallback(List<int?> callbackIds);

  @async
  bool registerHeadlessSyncBodyBuilder(List<int?> callbackIds);

  @async
  TlAuthorizationStatus getPermissionStatus();

  @async
  TlAuthorizationStatus requestPermission();

  @async
  TlNotificationAuthorizationStatus getNotificationPermissionStatus();

  @async
  TlNotificationAuthorizationStatus requestNotificationPermission();

  @async
  bool canScheduleExactAlarms();

  @async
  bool openExactAlarmSettings();

  @async
  TlMotionAuthorizationStatus getMotionPermissionStatus();

  @async
  TlMotionAuthorizationStatus requestMotionPermission();

  @async
  int requestTemporaryFullAccuracy(String purpose);

  @async
  bool isPowerSaveMode();

  @async
  TlProviderChangeEvent getProviderState();

  @async
  Map<String?, Object?> getDeviceInfo();

  @async
  bool log(String level, String message);

  @async
  bool playSound(String name);

  @async
  bool isIgnoringBatteryOptimizations();

  @async
  bool requestSettings(String action);

  @async
  bool showSettings(String action);

  @async
  TlState startSchedule();

  @async
  TlState stopSchedule();

  @async
  bool registerHeadlessTask(List<int?> callbackIds);

  @async
  int startBackgroundTask();

  @async
  int stopBackgroundTask(int taskId);

  @async
  Map<String?, Object?> getSensors();

  @async
  Map<String?, Object?> getSettingsHealth();

  @async
  bool openOemSettings(String label);

  @async
  String getLog(Map<String?, Object?>? query);

  @async
  bool destroyLog();

  @async
  bool emailLog(String email);

  @async
  Map<String?, Object?> verifyAuditTrail();

  @async
  Map<String?, Object?>? getAuditProof(String uuid);

  @async
  bool addPrivacyZone(Map<String?, Object?> zone);

  @async
  bool addPrivacyZones(List<Map<String?, Object?>?> zones);

  @async
  bool removePrivacyZone(String identifier);

  @async
  bool removePrivacyZones();

  @async
  List<Map<String?, Object?>?> getPrivacyZones();

  @async
  bool isDatabaseEncrypted();

  @async
  bool encryptDatabase();

  @async
  Map<String?, Object?>? getAttestationToken();

  @async
  Map<String?, Object?>? getDeadReckoningState();

  @async
  Map<String?, Object?> getCarbonReport(Map<String?, Object?>? query);
}

// =============================================================================
// Flutter API
// =============================================================================

@FlutterApi()
abstract class TraceletFlutterApi {
  void onHeadlessEvent(Map<String?, Object?> event);

  @async
  Map<String?, String?> onHeadlessHeaders();
}

@FlutterApi()
abstract class TraceletEventApi {
  void onLocation(TlLocation location);
  void onMotionChange(TlLocation location);
  void onMotionModeChange(TlSpeedMotionEvent event);
  void onActivityChange(TlActivityChangeEvent event);
  void onProviderChange(TlProviderChangeEvent event);
  void onGeofence(TlGeofenceEvent event);
  void onGeofencesChange(TlGeofencesChangeEvent event);
  void onHeartbeat(TlHeartbeatEvent event);
  void onHttp(TlHttpEvent event);
  void onSchedule(TlState state);
  void onPowerSaveChange(bool isPowerSaveMode);
  void onConnectivityChange(TlConnectivityChangeEvent event);
  void onEnabledChange(bool enabled);
  void onNotificationAction(String action);
  void onAuthorization(TlAuthorizationEvent event);
  void onWatchPosition(TlLocation location);
}
