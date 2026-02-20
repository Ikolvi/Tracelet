import 'package:meta/meta.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

/// Helper to safely extract a [bool] from a map value.
///
/// Handles int-to-bool coercion (iOS returns 0/1 for bools).
bool _ensureBool(Object? value, {required bool fallback}) {
  if (value is bool) return value;
  if (value is int) return value != 0;
  return fallback;
}

/// Helper to safely extract an [int] from a map value.
int _ensureInt(Object? value, {required int fallback}) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

/// Helper to safely extract a [double] from a map value.
double _ensureDouble(Object? value, {required double fallback}) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

/// Top-level compound configuration for Tracelet.
///
/// Organizes settings into logical sub-configs:
/// - [geo] — Location accuracy, distance filter, intervals
/// - [app] — Lifecycle behavior, heartbeat, scheduling
/// - [http] — Server sync settings
/// - [logger] — Logging level and retention
/// - [motion] — Motion detection sensitivity
/// - [geofence] — Geofence proximity and trigger rules
///
/// ```dart
/// final config = Config(
///   geo: GeoConfig(desiredAccuracy: DesiredAccuracy.high, distanceFilter: 10),
///   http: HttpConfig(url: 'https://example.com/locations'),
/// );
/// ```
@immutable
class Config {
  /// Creates a new [Config] with optional sub-configs.
  ///
  /// All sub-configs default to their respective defaults when omitted.
  const Config({
    this.geo = const GeoConfig(),
    this.app = const AppConfig(),
    this.http = const HttpConfig(),
    this.logger = const LoggerConfig(),
    this.motion = const MotionConfig(),
    this.geofence = const GeofenceConfig(),
  });

  /// Location accuracy and sampling settings.
  final GeoConfig geo;

  /// Application lifecycle and scheduling settings.
  final AppConfig app;

  /// HTTP sync settings.
  final HttpConfig http;

  /// Logger settings.
  final LoggerConfig logger;

  /// Motion detection settings.
  final MotionConfig motion;

  /// Geofencing settings.
  final GeofenceConfig geofence;

  /// Creates a [Config] from a flat or nested map.
  ///
  /// Supports both formats:
  /// - **Flat**: `{'desiredAccuracy': 0, 'distanceFilter': 10, ...}`
  /// - **Nested**: `{'geo': {...}, 'app': {...}, ...}`
  factory Config.fromMap(Map<String, Object?> map) {
    // Try nested first, fall back to flat
    final geoMap = map['geo'] as Map<String, Object?>?;
    final appMap = map['app'] as Map<String, Object?>?;
    final httpMap = map['http'] as Map<String, Object?>?;
    final loggerMap = map['logger'] as Map<String, Object?>?;
    final motionMap = map['motion'] as Map<String, Object?>?;
    final geofenceMap = map['geofence'] as Map<String, Object?>?;

    return Config(
      geo: geoMap != null ? GeoConfig.fromMap(geoMap) : GeoConfig.fromMap(map),
      app: appMap != null ? AppConfig.fromMap(appMap) : AppConfig.fromMap(map),
      http:
          httpMap != null ? HttpConfig.fromMap(httpMap) : HttpConfig.fromMap(map),
      logger: loggerMap != null
          ? LoggerConfig.fromMap(loggerMap)
          : LoggerConfig.fromMap(map),
      motion: motionMap != null
          ? MotionConfig.fromMap(motionMap)
          : MotionConfig.fromMap(map),
      geofence: geofenceMap != null
          ? GeofenceConfig.fromMap(geofenceMap)
          : GeofenceConfig.fromMap(map),
    );
  }

  /// Serializes to a flat map suitable for platform channel transmission.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      ...geo.toMap(),
      ...app.toMap(),
      ...http.toMap(),
      ...logger.toMap(),
      ...motion.toMap(),
      ...geofence.toMap(),
    };
  }

  @override
  String toString() =>
      'Config(geo: $geo, app: $app, http: $http, logger: $logger, '
      'motion: $motion, geofence: $geofence)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Config &&
          runtimeType == other.runtimeType &&
          geo == other.geo &&
          app == other.app &&
          http == other.http &&
          logger == other.logger &&
          motion == other.motion &&
          geofence == other.geofence;

  @override
  int get hashCode => Object.hash(geo, app, http, logger, motion, geofence);
}

// ---------------------------------------------------------------------------
// GeoConfig
// ---------------------------------------------------------------------------

/// Location accuracy and sampling settings.
///
/// Controls how the native location provider behaves: accuracy level,
/// minimum distance between updates, and timing intervals.
///
/// ```dart
/// GeoConfig(
///   desiredAccuracy: DesiredAccuracy.high,
///   distanceFilter: 10.0,
///   locationUpdateInterval: 1000,
/// )
/// ```
@immutable
class GeoConfig {
  /// Creates a new [GeoConfig] with optional overrides.
  const GeoConfig({
    this.desiredAccuracy = DesiredAccuracy.high,
    this.distanceFilter = 10.0,
    this.locationUpdateInterval = 1000,
    this.fastestLocationUpdateInterval = 500,
    this.stationaryRadius = 25.0,
    this.locationTimeout = 60,
    this.activityType = LocationActivityType.other,
  });

  /// The accuracy level to request from the platform.
  ///
  /// Higher accuracy = more battery usage. Defaults to [DesiredAccuracy.high].
  final DesiredAccuracy desiredAccuracy;

  /// Minimum distance (in meters) the device must move before a new location
  /// is recorded. Defaults to `10.0`.
  final double distanceFilter;

  /// The desired interval (in milliseconds) between location updates.
  ///
  /// Android only — iOS ignores this. Defaults to `1000`.
  final int locationUpdateInterval;

  /// The fastest interval (in milliseconds) the app is able to receive
  /// location updates. Android only. Defaults to `500`.
  final int fastestLocationUpdateInterval;

  /// The radius (in meters) around the last known position used to
  /// determine when the device has moved. Defaults to `25.0`.
  final double stationaryRadius;

  /// Timeout (in seconds) for obtaining a location fix. If no fix is
  /// obtained within this duration, an error event may fire. Defaults to `60`.
  final int locationTimeout;

  /// Hint to the platform about the type of activity being performed.
  ///
  /// iOS only — Android ignores this. Defaults to [LocationActivityType.other].
  final LocationActivityType activityType;

  /// Creates a [GeoConfig] from a map.
  factory GeoConfig.fromMap(Map<String, Object?> map) {
    return GeoConfig(
      desiredAccuracy: DesiredAccuracy.values[
          _ensureInt(map['desiredAccuracy'], fallback: 0)
              .clamp(0, DesiredAccuracy.values.length - 1)],
      distanceFilter:
          _ensureDouble(map['distanceFilter'], fallback: 10.0),
      locationUpdateInterval:
          _ensureInt(map['locationUpdateInterval'], fallback: 1000),
      fastestLocationUpdateInterval:
          _ensureInt(map['fastestLocationUpdateInterval'], fallback: 500),
      stationaryRadius:
          _ensureDouble(map['stationaryRadius'], fallback: 25.0),
      locationTimeout: _ensureInt(map['locationTimeout'], fallback: 60),
      activityType: LocationActivityType.values[
          _ensureInt(map['activityType'], fallback: 0)
              .clamp(0, LocationActivityType.values.length - 1)],
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'desiredAccuracy': desiredAccuracy.index,
      'distanceFilter': distanceFilter,
      'locationUpdateInterval': locationUpdateInterval,
      'fastestLocationUpdateInterval': fastestLocationUpdateInterval,
      'stationaryRadius': stationaryRadius,
      'locationTimeout': locationTimeout,
      'activityType': activityType.index,
    };
  }

  @override
  String toString() =>
      'GeoConfig(desiredAccuracy: $desiredAccuracy, '
      'distanceFilter: $distanceFilter, '
      'locationUpdateInterval: $locationUpdateInterval)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeoConfig &&
          runtimeType == other.runtimeType &&
          desiredAccuracy == other.desiredAccuracy &&
          distanceFilter == other.distanceFilter &&
          locationUpdateInterval == other.locationUpdateInterval &&
          fastestLocationUpdateInterval ==
              other.fastestLocationUpdateInterval &&
          stationaryRadius == other.stationaryRadius &&
          locationTimeout == other.locationTimeout &&
          activityType == other.activityType;

  @override
  int get hashCode => Object.hash(
        desiredAccuracy,
        distanceFilter,
        locationUpdateInterval,
        fastestLocationUpdateInterval,
        stationaryRadius,
        locationTimeout,
        activityType,
      );
}

// ---------------------------------------------------------------------------
// AppConfig
// ---------------------------------------------------------------------------

/// Application lifecycle and behavior settings.
///
/// Controls plugin behavior on app termination, device boot, heartbeat
/// interval, scheduling, and the Android foreground notification.
@immutable
class AppConfig {
  /// Creates a new [AppConfig] with optional overrides.
  const AppConfig({
    this.stopOnTerminate = true,
    this.startOnBoot = false,
    this.heartbeatInterval = 60,
    this.schedule = const <String>[],
    this.foregroundService = const ForegroundServiceConfig(),
  });

  /// Whether to stop tracking when the app is terminated. Defaults to `true`.
  final bool stopOnTerminate;

  /// Whether to restart tracking after device boot. Defaults to `false`.
  ///
  /// Requires `stopOnTerminate: false` to be effective.
  final bool startOnBoot;

  /// Interval (in seconds) for the heartbeat event. Defaults to `60`.
  ///
  /// Set to `-1` to disable heartbeat.
  final int heartbeatInterval;

  /// Scheduled tracking windows. Each string is a cron-like expression.
  ///
  /// Example: `['1-7 09:00-17:00']` (Mon–Sun, 9am–5pm).
  final List<String> schedule;

  /// Android foreground service notification configuration.
  final ForegroundServiceConfig foregroundService;

  /// Creates an [AppConfig] from a map.
  factory AppConfig.fromMap(Map<String, Object?> map) {
    final rawSchedule = map['schedule'];
    final scheduleList = <String>[];
    if (rawSchedule is List) {
      for (final item in rawSchedule) {
        if (item is String) scheduleList.add(item);
      }
    }

    final fgMap = map['foregroundService'] as Map<String, Object?>?;

    return AppConfig(
      stopOnTerminate:
          _ensureBool(map['stopOnTerminate'], fallback: true),
      startOnBoot: _ensureBool(map['startOnBoot'], fallback: false),
      heartbeatInterval:
          _ensureInt(map['heartbeatInterval'], fallback: 60),
      schedule: scheduleList,
      foregroundService: fgMap != null
          ? ForegroundServiceConfig.fromMap(fgMap)
          : const ForegroundServiceConfig(),
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'stopOnTerminate': stopOnTerminate,
      'startOnBoot': startOnBoot,
      'heartbeatInterval': heartbeatInterval,
      'schedule': schedule,
      'foregroundService': foregroundService.toMap(),
    };
  }

  @override
  String toString() =>
      'AppConfig(stopOnTerminate: $stopOnTerminate, '
      'startOnBoot: $startOnBoot, '
      'heartbeatInterval: $heartbeatInterval)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppConfig &&
          runtimeType == other.runtimeType &&
          stopOnTerminate == other.stopOnTerminate &&
          startOnBoot == other.startOnBoot &&
          heartbeatInterval == other.heartbeatInterval &&
          foregroundService == other.foregroundService;

  @override
  int get hashCode =>
      Object.hash(stopOnTerminate, startOnBoot, heartbeatInterval, foregroundService);
}

// ---------------------------------------------------------------------------
// ForegroundServiceConfig
// ---------------------------------------------------------------------------

/// Configuration for the Android foreground service notification.
@immutable
class ForegroundServiceConfig {
  /// Creates a new [ForegroundServiceConfig].
  const ForegroundServiceConfig({
    this.channelId = 'tracelet_channel',
    this.channelName = 'Tracelet',
    this.notificationTitle = 'Tracelet',
    this.notificationText = 'Tracking location in background',
    this.notificationColor,
    this.notificationSmallIcon,
    this.notificationLargeIcon,
    this.notificationPriority = 0,
    this.notificationOngoing = true,
    this.actions = const <String>[],
  });

  /// The Android notification channel ID.
  final String channelId;

  /// The Android notification channel name.
  final String channelName;

  /// Title text of the foreground notification.
  final String notificationTitle;

  /// Body text of the foreground notification.
  final String notificationText;

  /// ARGB color of the notification (e.g. `'#FF0000'`).
  final String? notificationColor;

  /// Resource name of the small icon (e.g. `'drawable/ic_notification'`).
  final String? notificationSmallIcon;

  /// Resource name of the large icon.
  final String? notificationLargeIcon;

  /// Notification priority (`-2` to `2`). Defaults to `0`.
  final int notificationPriority;

  /// Whether the notification is ongoing (cannot be swiped away). Defaults to `true`.
  final bool notificationOngoing;

  /// Action button labels shown on the notification.
  final List<String> actions;

  /// Creates a [ForegroundServiceConfig] from a map.
  factory ForegroundServiceConfig.fromMap(Map<String, Object?> map) {
    final rawActions = map['actions'];
    final actionsList = <String>[];
    if (rawActions is List) {
      for (final item in rawActions) {
        if (item is String) actionsList.add(item);
      }
    }
    return ForegroundServiceConfig(
      channelId: map['channelId'] as String? ?? 'tracelet_channel',
      channelName: map['channelName'] as String? ?? 'Tracelet',
      notificationTitle:
          map['notificationTitle'] as String? ?? 'Tracelet',
      notificationText: map['notificationText'] as String? ??
          'Tracking location in background',
      notificationColor: map['notificationColor'] as String?,
      notificationSmallIcon: map['notificationSmallIcon'] as String?,
      notificationLargeIcon: map['notificationLargeIcon'] as String?,
      notificationPriority:
          _ensureInt(map['notificationPriority'], fallback: 0),
      notificationOngoing:
          _ensureBool(map['notificationOngoing'], fallback: true),
      actions: actionsList,
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'channelId': channelId,
      'channelName': channelName,
      'notificationTitle': notificationTitle,
      'notificationText': notificationText,
      'notificationColor': notificationColor,
      'notificationSmallIcon': notificationSmallIcon,
      'notificationLargeIcon': notificationLargeIcon,
      'notificationPriority': notificationPriority,
      'notificationOngoing': notificationOngoing,
      'actions': actions,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForegroundServiceConfig &&
          runtimeType == other.runtimeType &&
          channelId == other.channelId &&
          notificationTitle == other.notificationTitle &&
          notificationText == other.notificationText;

  @override
  int get hashCode =>
      Object.hash(channelId, notificationTitle, notificationText);
}

// ---------------------------------------------------------------------------
// HttpConfig
// ---------------------------------------------------------------------------

/// HTTP synchronization settings.
///
/// When [url] is configured, Tracelet will automatically POST/PUT recorded
/// locations to your server.
@immutable
class HttpConfig {
  /// Creates a new [HttpConfig] with optional overrides.
  const HttpConfig({
    this.url,
    this.method = HttpMethod.post,
    this.headers = const <String, String>{},
    this.httpRootProperty = 'location',
    this.batchSync = false,
    this.maxBatchSize = 250,
    this.autoSync = true,
    this.autoSyncThreshold = 0,
    this.httpTimeout = 60000,
    this.params = const <String, Object?>{},
    this.locationsOrderDirection = LocationOrder.asc,
    this.extras = const <String, Object?>{},
  });

  /// The server URL to sync locations to. `null` disables HTTP sync.
  final String? url;

  /// HTTP method. Defaults to [HttpMethod.post].
  final HttpMethod method;

  /// Extra HTTP headers to include with each request.
  final Map<String, String> headers;

  /// Root JSON property name wrapping each location. Defaults to `'location'`.
  final String httpRootProperty;

  /// If `true`, sync all pending locations in a single request as a JSON
  /// array. Defaults to `false` (one request per location).
  final bool batchSync;

  /// Maximum number of locations per batch when [batchSync] is `true`.
  /// Defaults to `250`.
  final int maxBatchSize;

  /// Whether to auto-sync immediately when a new location is recorded.
  /// Defaults to `true`.
  final bool autoSync;

  /// Minimum number of unsent locations before triggering auto-sync.
  /// Defaults to `0` (sync immediately).
  final int autoSyncThreshold;

  /// HTTP request timeout in milliseconds. Defaults to `60000` (60s).
  final int httpTimeout;

  /// Extra static parameters merged into each request body.
  final Map<String, Object?> params;

  /// Sort order when reading locations from the database for sync.
  /// Defaults to [LocationOrder.asc].
  final LocationOrder locationsOrderDirection;

  /// Extra key-value pairs attached to every location record.
  final Map<String, Object?> extras;

  /// Creates an [HttpConfig] from a map.
  factory HttpConfig.fromMap(Map<String, Object?> map) {
    return HttpConfig(
      url: map['url'] as String?,
      method: HttpMethod
          .values[_ensureInt(map['method'], fallback: 0)
              .clamp(0, HttpMethod.values.length - 1)],
      headers: _castStringMap(map['headers']),
      httpRootProperty:
          map['httpRootProperty'] as String? ?? 'location',
      batchSync: _ensureBool(map['batchSync'], fallback: false),
      maxBatchSize: _ensureInt(map['maxBatchSize'], fallback: 250),
      autoSync: _ensureBool(map['autoSync'], fallback: true),
      autoSyncThreshold:
          _ensureInt(map['autoSyncThreshold'], fallback: 0),
      httpTimeout: _ensureInt(map['httpTimeout'], fallback: 60000),
      params: _castObjectMap(map['params']),
      locationsOrderDirection: LocationOrder
          .values[_ensureInt(map['locationsOrderDirection'], fallback: 0)
              .clamp(0, LocationOrder.values.length - 1)],
      extras: _castObjectMap(map['extras']),
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'url': url,
      'method': method.index,
      'headers': headers,
      'httpRootProperty': httpRootProperty,
      'batchSync': batchSync,
      'maxBatchSize': maxBatchSize,
      'autoSync': autoSync,
      'autoSyncThreshold': autoSyncThreshold,
      'httpTimeout': httpTimeout,
      'params': params,
      'locationsOrderDirection': locationsOrderDirection.index,
      'extras': extras,
    };
  }

  @override
  String toString() =>
      'HttpConfig(url: $url, method: $method, autoSync: $autoSync)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HttpConfig &&
          runtimeType == other.runtimeType &&
          url == other.url &&
          method == other.method &&
          autoSync == other.autoSync;

  @override
  int get hashCode => Object.hash(url, method, autoSync);
}

// ---------------------------------------------------------------------------
// LoggerConfig
// ---------------------------------------------------------------------------

/// Logging and debug settings.
@immutable
class LoggerConfig {
  /// Creates a new [LoggerConfig] with optional overrides.
  const LoggerConfig({
    this.logLevel = LogLevel.off,
    this.logMaxDays = 3,
    this.debug = false,
  });

  /// The log verbosity level. Defaults to [LogLevel.off].
  final LogLevel logLevel;

  /// Maximum number of days to retain log entries. Defaults to `3`.
  final int logMaxDays;

  /// If `true`, play debug sound effects on location events. Defaults to `false`.
  final bool debug;

  /// Creates a [LoggerConfig] from a map.
  factory LoggerConfig.fromMap(Map<String, Object?> map) {
    return LoggerConfig(
      logLevel: LogLevel
          .values[_ensureInt(map['logLevel'], fallback: 0)
              .clamp(0, LogLevel.values.length - 1)],
      logMaxDays: _ensureInt(map['logMaxDays'], fallback: 3),
      debug: _ensureBool(map['debug'], fallback: false),
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'logLevel': logLevel.index,
      'logMaxDays': logMaxDays,
      'debug': debug,
    };
  }

  @override
  String toString() =>
      'LoggerConfig(logLevel: $logLevel, logMaxDays: $logMaxDays, '
      'debug: $debug)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoggerConfig &&
          runtimeType == other.runtimeType &&
          logLevel == other.logLevel &&
          logMaxDays == other.logMaxDays &&
          debug == other.debug;

  @override
  int get hashCode => Object.hash(logLevel, logMaxDays, debug);
}

// ---------------------------------------------------------------------------
// MotionConfig
// ---------------------------------------------------------------------------

/// Motion detection settings.
///
/// Controls how aggressively the plugin transitions between stationary
/// and moving states.
@immutable
class MotionConfig {
  /// Creates a new [MotionConfig] with optional overrides.
  const MotionConfig({
    this.stopTimeout = 5,
    this.motionTriggerDelay = 0,
    this.disableMotionActivityUpdates = false,
    this.isMoving = false,
  });

  /// Minutes of non-movement before transitioning to stationary state.
  /// Defaults to `5`.
  final int stopTimeout;

  /// Delay (in milliseconds) after motion is detected before starting
  /// location tracking. Defaults to `0`.
  final int motionTriggerDelay;

  /// If `true`, disable the hardware motion activity detection (accelerometer /
  /// activity recognition). Defaults to `false`.
  final bool disableMotionActivityUpdates;

  /// Initial motion state. If `true`, begin in moving mode. Defaults to `false`.
  final bool isMoving;

  /// Creates a [MotionConfig] from a map.
  factory MotionConfig.fromMap(Map<String, Object?> map) {
    return MotionConfig(
      stopTimeout: _ensureInt(map['stopTimeout'], fallback: 5),
      motionTriggerDelay:
          _ensureInt(map['motionTriggerDelay'], fallback: 0),
      disableMotionActivityUpdates: _ensureBool(
          map['disableMotionActivityUpdates'],
          fallback: false),
      isMoving: _ensureBool(map['isMoving'], fallback: false),
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'stopTimeout': stopTimeout,
      'motionTriggerDelay': motionTriggerDelay,
      'disableMotionActivityUpdates': disableMotionActivityUpdates,
      'isMoving': isMoving,
    };
  }

  @override
  String toString() =>
      'MotionConfig(stopTimeout: $stopTimeout, '
      'disableMotionActivityUpdates: $disableMotionActivityUpdates, '
      'isMoving: $isMoving)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MotionConfig &&
          runtimeType == other.runtimeType &&
          stopTimeout == other.stopTimeout &&
          motionTriggerDelay == other.motionTriggerDelay &&
          disableMotionActivityUpdates ==
              other.disableMotionActivityUpdates &&
          isMoving == other.isMoving;

  @override
  int get hashCode => Object.hash(
      stopTimeout, motionTriggerDelay, disableMotionActivityUpdates, isMoving);
}

// ---------------------------------------------------------------------------
// GeofenceConfig
// ---------------------------------------------------------------------------

/// Geofencing settings.
@immutable
class GeofenceConfig {
  /// Creates a new [GeofenceConfig] with optional overrides.
  const GeofenceConfig({
    this.geofenceProximityRadius = 1000,
    this.geofenceInitialTriggerEntry = true,
    this.geofenceModeKnockOut = false,
  });

  /// The radius (in meters) used to activate geofences near the device's
  /// current position. Larger values consume more battery as more geofences
  /// are actively monitored. Defaults to `1000`.
  final int geofenceProximityRadius;

  /// If `true`, immediately fire an ENTER event for geofences the device is
  /// already inside when monitoring starts. Defaults to `true`.
  final bool geofenceInitialTriggerEntry;

  /// If `true`, a geofence that fires an EXIT event is automatically removed.
  /// Defaults to `false`.
  final bool geofenceModeKnockOut;

  /// Creates a [GeofenceConfig] from a map.
  factory GeofenceConfig.fromMap(Map<String, Object?> map) {
    return GeofenceConfig(
      geofenceProximityRadius:
          _ensureInt(map['geofenceProximityRadius'], fallback: 1000),
      geofenceInitialTriggerEntry: _ensureBool(
          map['geofenceInitialTriggerEntry'],
          fallback: true),
      geofenceModeKnockOut:
          _ensureBool(map['geofenceModeKnockOut'], fallback: false),
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'geofenceProximityRadius': geofenceProximityRadius,
      'geofenceInitialTriggerEntry': geofenceInitialTriggerEntry,
      'geofenceModeKnockOut': geofenceModeKnockOut,
    };
  }

  @override
  String toString() =>
      'GeofenceConfig(proximityRadius: $geofenceProximityRadius, '
      'initialTriggerEntry: $geofenceInitialTriggerEntry, '
      'knockOut: $geofenceModeKnockOut)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeofenceConfig &&
          runtimeType == other.runtimeType &&
          geofenceProximityRadius == other.geofenceProximityRadius &&
          geofenceInitialTriggerEntry ==
              other.geofenceInitialTriggerEntry &&
          geofenceModeKnockOut == other.geofenceModeKnockOut;

  @override
  int get hashCode => Object.hash(
      geofenceProximityRadius, geofenceInitialTriggerEntry, geofenceModeKnockOut);
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

Map<String, String> _castStringMap(Object? value) {
  if (value is Map) {
    return value.map<String, String>(
      (Object? k, Object? v) => MapEntry(k.toString(), v.toString()),
    );
  }
  return const <String, String>{};
}

Map<String, Object?> _castObjectMap(Object? value) {
  if (value is Map) {
    return value.map<String, Object?>(
      (Object? k, Object? v) => MapEntry(k.toString(), v),
    );
  }
  return const <String, Object?>{};
}
