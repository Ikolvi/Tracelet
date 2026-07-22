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

enum TlMotionDetectionMode { accelerometer, speed, smart }

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

enum TlLocationFilterPolicy { adjust, ignore, discard }

class TlLocationFilter {
  TlLocationFilter({
    required this.trackingAccuracyThreshold,
    required this.maxImpliedSpeed,
    required this.odometerAccuracyThreshold,
    required this.policy,
    required this.rejectMockLocations,
    required this.mockDetectionLevel,
    required this.useKalmanFilter,
  });

  final int trackingAccuracyThreshold;
  final int maxImpliedSpeed;
  final int odometerAccuracyThreshold;
  final TlLocationFilterPolicy policy;
  final bool rejectMockLocations;
  final int mockDetectionLevel;
  final bool useKalmanFilter;
}

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
    required this.filter,
    required this.resolveAddress,
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
  final TlLocationFilter filter;
  final bool resolveAddress;
}

class TlAppConfig {
  TlAppConfig({
    required this.stopOnTerminate,
    required this.startOnBoot,
    required this.heartbeatInterval,
    required this.schedule,
    required this.remoteConfigTimeout,
    required this.remoteConfigRefreshInterval,
    this.remoteConfigUrl,
    this.remoteConfigHeaders,
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
    required this.notificationPriority,
    required this.notificationOngoing,
    required this.showNotificationOnPauseOnly,
    required this.actions,
    this.notificationColor,
    this.notificationSmallIcon,
    this.notificationLargeIcon,
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
  final bool showNotificationOnPauseOnly;
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
    required this.releaseWakelockWhenStationary,
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

  /// Drops the OEM Wakelock when the device enters a fully stationary state.
  /// Resolves Issue #162.
  final bool releaseWakelockWhenStationary;
}

class TlLiveActivityConfig {
  TlLiveActivityConfig({required this.title, required this.body});
  final String title;
  final String body;
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
    required this.useBackgroundActivitySession,
    this.liveActivityConfig,
  });

  final TlIosActivityType activityType;
  final bool useSignificantChangesOnly;
  final bool showsBackgroundLocationIndicator;
  final bool pausesLocationUpdatesAutomatically;
  final TlAuthorizationRequest locationAuthorizationRequest;
  final bool disableLocationAuthorizationAlert;
  final bool preventSuspend;
  final bool useBackgroundActivitySession;
  final TlLiveActivityConfig? liveActivityConfig;
}

enum TlLocationOrderDirection { ascending, descending }

class TlHttpConfig {
  TlHttpConfig({
    required this.method,
    required this.autoSync,
    required this.batchSync,
    required this.maxBatchSize,
    required this.autoSyncThreshold,
    required this.syncInterval,
    required this.httpTimeout,
    required this.locationsOrderDirection,
    required this.disableAutoSyncOnCellular,
    required this.maxRetries,
    required this.retryBackoffBase,
    required this.retryBackoffCap,
    required this.enableDeltaCompression,
    required this.deltaCoordinatePrecision,
    required this.syncTelematics,
    this.url,
    this.telematicsUrl,
    this.headers,
    this.params,
    this.sslPinningFingerprints,
    this.sslPinningCertificates,
    this.httpRootProperty,
    this.extras,
    this.autoSyncDelay,
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
  final int? autoSyncDelay;
  final int syncInterval;
  final int httpTimeout;
  final TlLocationOrderDirection locationsOrderDirection;
  final Map<String?, Object?>? extras;
  final bool disableAutoSyncOnCellular;
  final int maxRetries;
  final int retryBackoffBase;
  final int retryBackoffCap;
  final bool enableDeltaCompression;
  final int deltaCoordinatePrecision;
  final bool syncTelematics;
  final String? telematicsUrl;
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
    required this.telematics,
    required this.classifier,
    required this.impact,
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
  final TlTelematicsConfig telematics;
  final TlClassifierConfig classifier;
  final TlImpactConfig impact;
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
    this.activityTypes,
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
    required this.geofenceInitialTriggerEntry,
    required this.geofenceProximityRadius,
    required this.geofenceInitialTrigger,
    required this.geofenceModeHighAccuracy,
  });
  final bool geofenceInitialTriggerEntry;
  final int geofenceProximityRadius;
  final bool geofenceInitialTrigger;
  final bool geofenceModeHighAccuracy;
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

/// Driving-behavior (telematics) event detection config. See `TelematicsEngine`.
class TlTelematicsConfig {
  TlTelematicsConfig({
    required this.enableDrivingEvents,
    required this.harshBrakingG,
    required this.harshAccelerationG,
    required this.harshCorneringG,
    required this.speedLimitKmh,
    required this.speedingToleranceKmh,
    required this.speedingMinDurationMs,
    required this.minSpeedForEventsKmh,
    required this.eventDebounceMs,
  });
  final bool enableDrivingEvents;
  final double harshBrakingG;
  final double harshAccelerationG;
  final double harshCorneringG;
  final double speedLimitKmh;
  final double speedingToleranceKmh;
  final int speedingMinDurationMs;
  final double minSpeedForEventsKmh;
  final int eventDebounceMs;
}

/// On-device transport-mode classifier config. See `TransportModeClassifier`.
class TlClassifierConfig {
  TlClassifierConfig({
    required this.enableFusedClassifier,
    required this.fusedClassifierAuthoritative,
    required this.modeSwitchDwellMs,
    required this.minModeConfidence,
  });
  final bool enableFusedClassifier;
  final bool fusedClassifierAuthoritative;
  final int modeSwitchDwellMs;
  final double minModeConfidence;
}

/// Crash & fall detection config. See `ImpactDetector`.
class TlImpactConfig {
  TlImpactConfig({
    required this.enableCrashDetection,
    required this.enableFallDetection,
    required this.crashGThreshold,
    required this.crashMinSpeedKmh,
    required this.fallGThreshold,
    required this.confirmWindowMs,
    required this.minImpactConfidence,
    required this.crashModelThreshold,
    this.crashModelUrl,
    this.crashModelSha256,
    this.crashModelUnlockUrl,
    this.crashModelLicenseKey,
  });
  final bool enableCrashDetection;
  final bool enableFallDetection;
  final double crashGThreshold;
  final double crashMinSpeedKmh;
  final double fallGThreshold;
  final int confirmWindowMs;
  final double minImpactConfidence;
  final String? crashModelUrl;
  final String? crashModelSha256;
  final double crashModelThreshold;
  final String? crashModelUnlockUrl;
  final String? crashModelLicenseKey;
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

class TlAddress {
  TlAddress({
    this.street,
    this.city,
    this.state,
    this.postalCode,
    this.country,
  });
  final String? street;
  final String? city;
  final String? state;
  final String? postalCode;
  final String? country;
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
    this.address,
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
  final TlAddress? address;
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
  final List<Object?>? vertices;
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

enum TlSpeedMotionState { moving, slowing, stationary }

class TlSpeedMotionEvent {
  TlSpeedMotionEvent({
    required this.state,
    required this.previousState,
    required this.trackingMode,
  });

  /// New state: `moving`, `slowing`, or `stationary`.
  final TlSpeedMotionState state;

  /// Previous state before this transition.
  final TlSpeedMotionState previousState;

  /// Underlying tracking mode after the transition: `continuous` (location),
  /// `periodic`, or `geofences`.
  final TlTrackingMode trackingMode;
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

/// A driving-behavior event (harsh brake/accel/cornering/speeding).
class TlDrivingEvent {
  TlDrivingEvent({
    required this.kind,
    required this.severity,
    required this.speed,
    required this.value,
    required this.latitude,
    required this.longitude,
    required this.timestampMs,
  });
  final String kind;
  final double severity;
  final double speed;
  final double value;
  final double latitude;
  final double longitude;
  final int timestampMs;
}

/// A crash/fall impact event (`potential_crash`/`crash`/`potential_fall`/`fall`).
class TlImpactEvent {
  TlImpactEvent({
    required this.kind,
    required this.id,
    required this.confidence,
    required this.peakG,
    required this.speedBefore,
    required this.latitude,
    required this.longitude,
    required this.timestampMs,
    required this.confirmDeadlineMs,
  });
  final String kind;
  final int id;
  final double confidence;
  final double peakG;
  final double speedBefore;
  final double latitude;
  final double longitude;
  final int timestampMs;
  final int confirmDeadlineMs;
}

/// A fused transport-mode change.
class TlModeChangeEvent {
  TlModeChangeEvent({required this.mode, required this.confidence});
  final String mode;
  final double confidence;
}

/// Lifecycle status of the opt-in ML crash model (#183), so apps can show the
/// user that the model is being prepared (e.g. a download spinner).
///
/// [status] is one of: `unlocking`, `downloading`, `decrypting`, `ready`,
/// `failed`, `disabled`. [detail] carries extra context — an error reason on
/// `failed`, or e.g. the tree count on `ready`.
class TlCrashModelStatusEvent {
  TlCrashModelStatusEvent({required this.status, this.detail});
  final String status;
  final String? detail;
}

// =============================================================================
// Host API
// =============================================================================

@HostApi()
abstract class TraceletHostApi {
  void requestStateFlush();

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

  /// Temporarily overrides active OS-provider acquisition options.
  ///
  /// This does not change the persisted Tracelet config or the Rust location
  /// processor. Passing null for both values clears the override and restores
  /// the configured provider options. Supported on iOS and Android; platforms
  /// without live provider updates (e.g. web) return false.
  @async
  bool updateLocationProviderOptions(
    TlDesiredAccuracy? desiredAccuracy,
    double? distanceFilter,
  );

  /// Confirms a pending impact candidate (by [id]) as a real emergency now.
  bool confirmImpact(int id);

  /// Cancels a pending impact candidate (by [id]) — no confirmed event fires.
  bool cancelImpact(int id);

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
  Map<String?, Object?> getForegroundServiceHealth();

  @async
  bool openOemSettings(String label);

  @async
  bool showPowerManager();

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
  List<Object?> getPrivacyZones();

  @async
  bool isDatabaseEncrypted();

  @async
  bool encryptDatabase();

  @async
  Map<String?, Object?>? getAttestationToken();
  @async
  Map<String?, Object?>? getDeadReckoningState();

  @async
  Map<String, Object?> getCarbonReport(Map<String, Object?>? query);

  @async
  bool simulateTelematicsEvent(
    String eventType,
    double severity,
    double latitude,
    double longitude,
  );

  @async
  List<TlTelematicsRecord?> getTelematicsEvents(int limit);

  @async
  bool destroyTelematicsEvents();

  @async
  List<TlLogEntry?> getLogs(int limit);

  @async
  void clearLogs();

  /// Debug-only (#183): synthesizes one high-g accelerometer window and runs it
  /// through the SDK's real crash-detection pipeline — including the loaded ML
  /// crash model — so the model path can be verified without a physical impact.
  /// When [crashLike] is true the synthetic features represent a real crash
  /// (rotation + speed + deceleration); when false a benign bump the model
  /// should reject. Returns the model probability, threshold, and whether a
  /// crash candidate fired. `modelRan` is false when no ML model is loaded.
  @async
  Map<String, Object?> debugRunCrashModelInference(
    double peakG,
    double speedKmh,
    bool crashLike,
  );
}

class TlTelematicsRecord {
  TlTelematicsRecord({
    required this.id,
    required this.eventType,
    required this.severity,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.synced,
  });

  /// The primary key.
  final int id;

  /// The type of telematics event.
  final String eventType;

  /// The severity of the event.
  final double severity;

  /// The latitude.
  final double latitude;

  /// The longitude.
  final double longitude;

  /// The ISO8601 timestamp string.
  final String timestamp;

  /// Whether the event has been synced to the server.
  final bool synced;
}

class TlLogEntry {
  TlLogEntry({
    required this.id,
    required this.level,
    required this.message,
    required this.timestamp,
  });

  /// The primary key.
  final int id;

  /// The log level.
  final String level;

  /// The log message.
  final String message;

  /// The ISO8601 timestamp string.
  final String timestamp;
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
  void onDrivingEvent(TlDrivingEvent event);
  void onImpact(TlImpactEvent event);
  void onModeChange(TlModeChangeEvent event);
  void onCrashModelStatus(TlCrashModelStatusEvent event);
}
