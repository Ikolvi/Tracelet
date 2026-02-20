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

/// Safely cast a platform value to `Map<String, Object?>?`.
///
/// iOS platform channels return `Map<Object?, Object?>` which cannot be
/// directly cast to `Map<String, Object?>`. This helper handles both types.
Map<String, Object?>? _safeMap(Object? value) {
  if (value == null) return null;
  if (value is Map<String, Object?>) return value;
  if (value is Map) return Map<String, Object?>.from(value);
  return null;
}

/// Top-level compound configuration for Tracelet.
///
/// Organizes settings into logical sub-configs:
/// - [geo] — Location accuracy, distance filter, intervals, elasticity, filtering
/// - [app] — Lifecycle behavior, heartbeat, scheduling
/// - [http] — Server sync settings
/// - [logger] — Logging level and retention
/// - [motion] — Motion detection sensitivity
/// - [geofence] — Geofence proximity and trigger rules
/// - [persistence] — Database retention, templates, extras
///
/// ```dart
/// final config = Config(
///   geo: GeoConfig(desiredAccuracy: DesiredAccuracy.high, distanceFilter: 10),
///   http: HttpConfig(url: 'https://example.com/locations'),
///   persistence: PersistenceConfig(maxDaysToPersist: 14),
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
    this.persistence = const PersistenceConfig(),
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

  /// Data persistence and database settings.
  final PersistenceConfig persistence;

  /// Creates a [Config] from a flat or nested map.
  ///
  /// Supports both formats:
  /// - **Flat**: `{'desiredAccuracy': 0, 'distanceFilter': 10, ...}`
  /// - **Nested**: `{'geo': {...}, 'app': {...}, ...}`
  factory Config.fromMap(Map<String, Object?> map) {
    // Try nested first, fall back to flat
    final geoMap = _safeMap(map['geo']);
    final appMap = _safeMap(map['app']);
    final httpMap = _safeMap(map['http']);
    final loggerMap = _safeMap(map['logger']);
    final motionMap = _safeMap(map['motion']);
    final geofenceMap = _safeMap(map['geofence']);
    final persistenceMap = _safeMap(map['persistence']);

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
      persistence: persistenceMap != null
          ? PersistenceConfig.fromMap(persistenceMap)
          : PersistenceConfig.fromMap(map),
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
      ...persistence.toMap(),
    };
  }

  @override
  String toString() =>
      'Config(geo: $geo, app: $app, http: $http, logger: $logger, '
      'motion: $motion, geofence: $geofence, persistence: $persistence)';

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
          geofence == other.geofence &&
          persistence == other.persistence;

  @override
  int get hashCode =>
      Object.hash(geo, app, http, logger, motion, geofence, persistence);
}

// ---------------------------------------------------------------------------
// GeoConfig
// ---------------------------------------------------------------------------

/// Location accuracy and sampling settings.
///
/// Controls how the native location provider behaves: accuracy level,
/// minimum distance between updates, timing intervals, elasticity,
/// platform-specific options, and location filtering.
///
/// ```dart
/// GeoConfig(
///   desiredAccuracy: DesiredAccuracy.high,
///   distanceFilter: 10.0,
///   locationUpdateInterval: 1000,
///   filter: LocationFilter(maxImpliedSpeed: 60),
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
    this.disableElasticity = false,
    this.elasticityMultiplier = 1.0,
    this.stopAfterElapsedMinutes = -1,
    this.deferTime = 0,
    this.allowIdenticalLocations = false,
    this.geofenceModeHighAccuracy = false,
    this.maxMonitoredGeofences = -1,
    this.useSignificantChangesOnly = false,
    this.showsBackgroundLocationIndicator = false,
    this.pausesLocationUpdatesAutomatically = false,
    this.locationAuthorizationRequest = 'Always',
    this.disableLocationAuthorizationAlert = false,
    this.enableTimestampMeta = false,
    this.filter,
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

  /// Disable speed-based automatic [distanceFilter] scaling.
  ///
  /// When `false` (default), the plugin dynamically adjusts the distance
  /// filter based on current speed — recording more locations at low speed
  /// and fewer at high speed. Set `true` for a fixed [distanceFilter].
  final bool disableElasticity;

  /// Scale factor for automatic distance-filter elasticity.
  ///
  /// Higher values reduce location recordings at higher speeds. Defaults to `1.0`.
  /// Only effective when [disableElasticity] is `false`.
  final double elasticityMultiplier;

  /// Automatically stop tracking after this many minutes of continuous
  /// operation. Defaults to `-1` (disabled).
  final int stopAfterElapsedMinutes;

  /// `[Android only]` Maximum wait time (ms) for location updates.
  /// Defaults to `0`.
  final int deferTime;

  /// `[Android only]` Allow recording identical consecutive locations.
  /// Defaults to `false`.
  final bool allowIdenticalLocations;

  /// `[Android only]` Enable high-accuracy geofence monitoring during
  /// geofence-only mode ([Tracelet.startGeofences]). Defaults to `false`.
  final bool geofenceModeHighAccuracy;

  /// Maximum number of geofences to monitor at a time, overriding the
  /// platform default (iOS: 20, Android: 100). Defaults to `-1` (use
  /// platform default).
  final int maxMonitoredGeofences;

  /// `[iOS only]` Use significant-change monitoring instead of standard
  /// location updates. Locations are recorded only on major changes
  /// (cell tower / WiFi transition). Saves battery but lower accuracy.
  /// Defaults to `false`.
  final bool useSignificantChangesOnly;

  /// `[iOS only]` Show the blue status bar indicator when tracking in the
  /// background. Defaults to `false`.
  final bool showsBackgroundLocationIndicator;

  /// `[iOS only]` Allow iOS to automatically pause location updates.
  /// Defaults to `false`.
  final bool pausesLocationUpdatesAutomatically;

  /// The location authorization to request: `'Always'` or `'WhenInUse'`.
  /// Defaults to `'Always'`.
  final String locationAuthorizationRequest;

  /// Disable the automatic alert shown when the user has disabled required
  /// location authorization. Defaults to `false`.
  final bool disableLocationAuthorizationAlert;

  /// Append extra timestamp metadata to each location record.
  /// Defaults to `false`.
  final bool enableTimestampMeta;

  /// Location filtering / denoising settings.
  ///
  /// Controls Kalman filtering, speed-jump rejection, and accuracy
  /// thresholds. When `null`, the platform uses default filtering.
  final LocationFilter? filter;

  /// Creates a [GeoConfig] from a map.
  factory GeoConfig.fromMap(Map<String, Object?> map) {
    final filterMap = _safeMap(map['filter']);
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
      disableElasticity:
          _ensureBool(map['disableElasticity'], fallback: false),
      elasticityMultiplier:
          _ensureDouble(map['elasticityMultiplier'], fallback: 1.0),
      stopAfterElapsedMinutes:
          _ensureInt(map['stopAfterElapsedMinutes'], fallback: -1),
      deferTime: _ensureInt(map['deferTime'], fallback: 0),
      allowIdenticalLocations:
          _ensureBool(map['allowIdenticalLocations'], fallback: false),
      geofenceModeHighAccuracy:
          _ensureBool(map['geofenceModeHighAccuracy'], fallback: false),
      maxMonitoredGeofences:
          _ensureInt(map['maxMonitoredGeofences'], fallback: -1),
      useSignificantChangesOnly:
          _ensureBool(map['useSignificantChangesOnly'], fallback: false),
      showsBackgroundLocationIndicator: _ensureBool(
          map['showsBackgroundLocationIndicator'],
          fallback: false),
      pausesLocationUpdatesAutomatically: _ensureBool(
          map['pausesLocationUpdatesAutomatically'],
          fallback: false),
      locationAuthorizationRequest:
          map['locationAuthorizationRequest'] as String? ?? 'Always',
      disableLocationAuthorizationAlert: _ensureBool(
          map['disableLocationAuthorizationAlert'],
          fallback: false),
      enableTimestampMeta:
          _ensureBool(map['enableTimestampMeta'], fallback: false),
      filter:
          filterMap != null ? LocationFilter.fromMap(filterMap) : null,
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
      'disableElasticity': disableElasticity,
      'elasticityMultiplier': elasticityMultiplier,
      'stopAfterElapsedMinutes': stopAfterElapsedMinutes,
      'deferTime': deferTime,
      'allowIdenticalLocations': allowIdenticalLocations,
      'geofenceModeHighAccuracy': geofenceModeHighAccuracy,
      'maxMonitoredGeofences': maxMonitoredGeofences,
      'useSignificantChangesOnly': useSignificantChangesOnly,
      'showsBackgroundLocationIndicator': showsBackgroundLocationIndicator,
      'pausesLocationUpdatesAutomatically': pausesLocationUpdatesAutomatically,
      'locationAuthorizationRequest': locationAuthorizationRequest,
      'disableLocationAuthorizationAlert': disableLocationAuthorizationAlert,
      'enableTimestampMeta': enableTimestampMeta,
      if (filter != null) 'filter': filter!.toMap(),
    };
  }

  @override
  String toString() =>
      'GeoConfig(desiredAccuracy: $desiredAccuracy, '
      'distanceFilter: $distanceFilter, '
      'locationUpdateInterval: $locationUpdateInterval, '
      'disableElasticity: $disableElasticity, '
      'filter: $filter)';

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
          activityType == other.activityType &&
          disableElasticity == other.disableElasticity &&
          elasticityMultiplier == other.elasticityMultiplier &&
          stopAfterElapsedMinutes == other.stopAfterElapsedMinutes &&
          enableTimestampMeta == other.enableTimestampMeta &&
          filter == other.filter;

  @override
  int get hashCode => Object.hash(
        desiredAccuracy,
        distanceFilter,
        locationUpdateInterval,
        fastestLocationUpdateInterval,
        stationaryRadius,
        locationTimeout,
        activityType,
        disableElasticity,
        elasticityMultiplier,
        stopAfterElapsedMinutes,
        enableTimestampMeta,
        filter,
      );
}

// ---------------------------------------------------------------------------
// LocationFilter
// ---------------------------------------------------------------------------

/// Location filtering and denoising configuration.
///
/// Controls how raw GPS samples are processed before being recorded or
/// used for odometer calculations. Helps eliminate noise, GPS spikes,
/// and low-quality readings.
///
/// ```dart
/// LocationFilter(
///   policy: LocationFilterPolicy.adjust,
///   maxImpliedSpeed: 60,
///   odometerAccuracyThreshold: 20,
///   trackingAccuracyThreshold: 100,
/// )
/// ```
@immutable
class LocationFilter {
  /// Creates a new [LocationFilter].
  const LocationFilter({
    this.policy = LocationFilterPolicy.adjust,
    this.maxImpliedSpeed = 0,
    this.odometerAccuracyThreshold = 0,
    this.trackingAccuracyThreshold = 0,
  });

  /// How the filter handles rejected locations.
  ///
  /// - [LocationFilterPolicy.adjust]: Smooth/correct rejected locations.
  /// - [LocationFilterPolicy.ignore]: Silently discard rejected locations.
  /// - [LocationFilterPolicy.discard]: Discard and fire an error event.
  ///
  /// Defaults to [LocationFilterPolicy.adjust].
  final LocationFilterPolicy policy;

  /// Max implied speed (m/s) between consecutive locations.
  ///
  /// Locations that imply traveling faster than this speed are rejected
  /// as GPS spikes. Defaults to `0` (disabled).
  final int maxImpliedSpeed;

  /// Minimum accuracy (in meters) a location must have to be counted
  /// in odometer calculations. Defaults to `0` (accept all).
  final int odometerAccuracyThreshold;

  /// Minimum accuracy (in meters) a location must have to be recorded.
  /// Locations with worse accuracy are filtered. Defaults to `0` (accept all).
  final int trackingAccuracyThreshold;

  /// Creates a [LocationFilter] from a map.
  factory LocationFilter.fromMap(Map<String, Object?> map) {
    return LocationFilter(
      policy: LocationFilterPolicy.values[
          _ensureInt(map['policy'], fallback: 0)
              .clamp(0, LocationFilterPolicy.values.length - 1)],
      maxImpliedSpeed:
          _ensureInt(map['maxImpliedSpeed'], fallback: 0),
      odometerAccuracyThreshold:
          _ensureInt(map['odometerAccuracyThreshold'], fallback: 0),
      trackingAccuracyThreshold:
          _ensureInt(map['trackingAccuracyThreshold'], fallback: 0),
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'policy': policy.index,
      'maxImpliedSpeed': maxImpliedSpeed,
      'odometerAccuracyThreshold': odometerAccuracyThreshold,
      'trackingAccuracyThreshold': trackingAccuracyThreshold,
    };
  }

  @override
  String toString() =>
      'LocationFilter(policy: $policy, maxImpliedSpeed: $maxImpliedSpeed, '
      'odometerAccuracyThreshold: $odometerAccuracyThreshold, '
      'trackingAccuracyThreshold: $trackingAccuracyThreshold)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocationFilter &&
          runtimeType == other.runtimeType &&
          policy == other.policy &&
          maxImpliedSpeed == other.maxImpliedSpeed &&
          odometerAccuracyThreshold == other.odometerAccuracyThreshold &&
          trackingAccuracyThreshold == other.trackingAccuracyThreshold;

  @override
  int get hashCode => Object.hash(
      policy, maxImpliedSpeed, odometerAccuracyThreshold, trackingAccuracyThreshold);
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
    this.scheduleUseAlarmManager = false,
    this.preventSuspend = false,
    this.backgroundPermissionRationale,
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

  /// `[Android only]` Use `AlarmManager` for precise schedule execution.
  ///
  /// By default, schedules use `JobScheduler` / `WorkManager` which may
  /// defer execution. Set `true` for exact-time scheduling. Defaults to `false`.
  final bool scheduleUseAlarmManager;

  /// `[iOS only]` Play a silent audio clip to keep the app alive in the
  /// background, preventing iOS from suspending it.
  ///
  /// Uses minimal battery but prevents iOS from reclaiming resources.
  /// Defaults to `false`.
  final bool preventSuspend;

  /// `[Android only]` Rationale shown when requesting background location
  /// permission (Android 11+).
  ///
  /// When provided, the plugin will show a dialog explaining why background
  /// location is needed before the system permission prompt.
  final PermissionRationale? backgroundPermissionRationale;

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

    final fgMap = _safeMap(map['foregroundService']);
    final rationaleMap = _safeMap(map['backgroundPermissionRationale']);

    return AppConfig(
      stopOnTerminate:
          _ensureBool(map['stopOnTerminate'], fallback: true),
      startOnBoot: _ensureBool(map['startOnBoot'], fallback: false),
      heartbeatInterval:
          _ensureInt(map['heartbeatInterval'], fallback: 60),
      schedule: scheduleList,
      scheduleUseAlarmManager:
          _ensureBool(map['scheduleUseAlarmManager'], fallback: false),
      preventSuspend:
          _ensureBool(map['preventSuspend'], fallback: false),
      backgroundPermissionRationale: rationaleMap != null
          ? PermissionRationale.fromMap(rationaleMap)
          : null,
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
      'scheduleUseAlarmManager': scheduleUseAlarmManager,
      'preventSuspend': preventSuspend,
      if (backgroundPermissionRationale != null)
        'backgroundPermissionRationale':
            backgroundPermissionRationale!.toMap(),
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
          scheduleUseAlarmManager == other.scheduleUseAlarmManager &&
          preventSuspend == other.preventSuspend &&
          foregroundService == other.foregroundService;

  @override
  int get hashCode =>
      Object.hash(stopOnTerminate, startOnBoot, heartbeatInterval,
          scheduleUseAlarmManager, preventSuspend, foregroundService);
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
    this.disableAutoSyncOnCellular = false,
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

  /// If `true`, disable auto-sync when the device is on a cellular connection.
  /// Sync will only occur on Wi-Fi. Defaults to `false`.
  final bool disableAutoSyncOnCellular;

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
      disableAutoSyncOnCellular:
          _ensureBool(map['disableAutoSyncOnCellular'], fallback: false),
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
      'disableAutoSyncOnCellular': disableAutoSyncOnCellular,
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
    this.activityRecognitionInterval = 10000,
    this.minimumActivityRecognitionConfidence = 75,
    this.disableStopDetection = false,
    this.stopDetectionDelay = 0,
    this.stopOnStationary = false,
    this.triggerActivities = '',
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

  /// Interval (in ms) between activity-recognition sampling.
  /// Defaults to `10000` (10 s). Smaller values detect motion changes faster
  /// but use more battery.
  final int activityRecognitionInterval;

  /// Minimum confidence (0–100) a detected activity must have to trigger
  /// a motion-change event. Defaults to `75`.
  final int minimumActivityRecognitionConfidence;

  /// If `true`, disable stop-detection entirely — the plugin will never
  /// automatically transition to the stationary state. Defaults to `false`.
  final bool disableStopDetection;

  /// Extra delay (in minutes) after stop-timeout before engaging stop-detection.
  /// Defaults to `0`.
  final int stopDetectionDelay;

  /// If `true`, automatically call [Tracelet.stop] when the device becomes
  /// stationary (instead of just transitioning to stationary state).
  /// Defaults to `false`.
  final bool stopOnStationary;

  /// Comma-separated activity names that should trigger motion.
  ///
  /// Example: `'on_foot, in_vehicle'`. Empty string (default) means all
  /// activities trigger motion.
  final String triggerActivities;

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
      activityRecognitionInterval:
          _ensureInt(map['activityRecognitionInterval'], fallback: 10000),
      minimumActivityRecognitionConfidence:
          _ensureInt(map['minimumActivityRecognitionConfidence'], fallback: 75),
      disableStopDetection:
          _ensureBool(map['disableStopDetection'], fallback: false),
      stopDetectionDelay:
          _ensureInt(map['stopDetectionDelay'], fallback: 0),
      stopOnStationary:
          _ensureBool(map['stopOnStationary'], fallback: false),
      triggerActivities:
          map['triggerActivities'] as String? ?? '',
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'stopTimeout': stopTimeout,
      'motionTriggerDelay': motionTriggerDelay,
      'disableMotionActivityUpdates': disableMotionActivityUpdates,
      'isMoving': isMoving,
      'activityRecognitionInterval': activityRecognitionInterval,
      'minimumActivityRecognitionConfidence': minimumActivityRecognitionConfidence,
      'disableStopDetection': disableStopDetection,
      'stopDetectionDelay': stopDetectionDelay,
      'stopOnStationary': stopOnStationary,
      'triggerActivities': triggerActivities,
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
          isMoving == other.isMoving &&
          activityRecognitionInterval == other.activityRecognitionInterval &&
          minimumActivityRecognitionConfidence ==
              other.minimumActivityRecognitionConfidence &&
          disableStopDetection == other.disableStopDetection &&
          stopOnStationary == other.stopOnStationary;

  @override
  int get hashCode => Object.hash(
      stopTimeout, motionTriggerDelay, disableMotionActivityUpdates,
      isMoving, activityRecognitionInterval,
      minimumActivityRecognitionConfidence, disableStopDetection,
      stopOnStationary);
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
// PersistenceConfig
// ---------------------------------------------------------------------------

/// Data persistence and database retention settings.
///
/// Controls how recorded locations are stored in the local SQLite database,
/// including retention limits, templates for serialization, and extra data.
///
/// ```dart
/// PersistenceConfig(
///   persistMode: PersistMode.all,
///   maxDaysToPersist: 14,
///   maxRecordsToPersist: 5000,
/// )
/// ```
@immutable
class PersistenceConfig {
  /// Creates a new [PersistenceConfig] with optional overrides.
  const PersistenceConfig({
    this.persistMode = PersistMode.all,
    this.maxDaysToPersist = -1,
    this.maxRecordsToPersist = -1,
    this.locationTemplate,
    this.geofenceTemplate,
    this.disableProviderChangeRecord = false,
    this.extras = const <String, Object?>{},
  });

  /// What types of records to persist to the database.
  ///
  /// - [PersistMode.all]: persist all location and geofence records.
  /// - [PersistMode.location]: persist only location records.
  /// - [PersistMode.geofence]: persist only geofence records.
  /// - [PersistMode.none]: do not persist any records.
  ///
  /// Defaults to [PersistMode.all].
  final PersistMode persistMode;

  /// Maximum number of days to retain records in the database.
  ///
  /// Records older than this are automatically pruned. Defaults to `-1`
  /// (unlimited).
  final int maxDaysToPersist;

  /// Maximum number of records to retain in the database.
  ///
  /// When this limit is exceeded, the oldest records are pruned.
  /// Defaults to `-1` (unlimited).
  final int maxRecordsToPersist;

  /// Custom JSON template for formatting location records.
  ///
  /// Use Mustache-style placeholders: `'{"lat":{{latitude}},"lng":{{longitude}}}'`.
  /// When `null`, the platform default format is used.
  final String? locationTemplate;

  /// Custom JSON template for formatting geofence records.
  ///
  /// When `null`, the platform default format is used.
  final String? geofenceTemplate;

  /// If `true`, do not insert a record when the location provider changes
  /// (e.g., GPS → network). Defaults to `false`.
  final bool disableProviderChangeRecord;

  /// Extra key-value pairs attached to every persisted record.
  final Map<String, Object?> extras;

  /// Creates a [PersistenceConfig] from a map.
  factory PersistenceConfig.fromMap(Map<String, Object?> map) {
    return PersistenceConfig(
      persistMode: PersistMode.values[
          _ensureInt(map['persistMode'], fallback: 0)
              .clamp(0, PersistMode.values.length - 1)],
      maxDaysToPersist:
          _ensureInt(map['maxDaysToPersist'], fallback: -1),
      maxRecordsToPersist:
          _ensureInt(map['maxRecordsToPersist'], fallback: -1),
      locationTemplate: map['locationTemplate'] as String?,
      geofenceTemplate: map['geofenceTemplate'] as String?,
      disableProviderChangeRecord: _ensureBool(
          map['disableProviderChangeRecord'],
          fallback: false),
      extras: _castObjectMap(map['extras']),
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'persistMode': persistMode.index,
      'maxDaysToPersist': maxDaysToPersist,
      'maxRecordsToPersist': maxRecordsToPersist,
      'locationTemplate': locationTemplate,
      'geofenceTemplate': geofenceTemplate,
      'disableProviderChangeRecord': disableProviderChangeRecord,
      'extras': extras,
    };
  }

  @override
  String toString() =>
      'PersistenceConfig(persistMode: $persistMode, '
      'maxDaysToPersist: $maxDaysToPersist, '
      'maxRecordsToPersist: $maxRecordsToPersist)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistenceConfig &&
          runtimeType == other.runtimeType &&
          persistMode == other.persistMode &&
          maxDaysToPersist == other.maxDaysToPersist &&
          maxRecordsToPersist == other.maxRecordsToPersist &&
          locationTemplate == other.locationTemplate &&
          geofenceTemplate == other.geofenceTemplate &&
          disableProviderChangeRecord ==
              other.disableProviderChangeRecord;

  @override
  int get hashCode => Object.hash(persistMode, maxDaysToPersist,
      maxRecordsToPersist, locationTemplate, geofenceTemplate,
      disableProviderChangeRecord);
}

// ---------------------------------------------------------------------------
// PermissionRationale
// ---------------------------------------------------------------------------

/// Rationale dialog configuration for background location permission.
///
/// `[Android 11+ only]` Shown before the system permission dialog when
/// requesting background location access.
///
/// ```dart
/// PermissionRationale(
///   title: 'Background location needed',
///   message: 'This app tracks your position in the background to...',
///   positiveAction: 'Allow',
///   negativeAction: 'Cancel',
/// )
/// ```
@immutable
class PermissionRationale {
  /// Creates a new [PermissionRationale].
  const PermissionRationale({
    required this.title,
    required this.message,
    this.positiveAction = 'Allow',
    this.negativeAction = 'Cancel',
  });

  /// Title of the rationale dialog.
  final String title;

  /// Body text explaining why background location is needed.
  final String message;

  /// Label for the positive button. Defaults to `'Allow'`.
  final String positiveAction;

  /// Label for the negative button. Defaults to `'Cancel'`.
  final String negativeAction;

  /// Creates a [PermissionRationale] from a map.
  factory PermissionRationale.fromMap(Map<String, Object?> map) {
    return PermissionRationale(
      title: map['title'] as String? ?? '',
      message: map['message'] as String? ?? '',
      positiveAction: map['positiveAction'] as String? ?? 'Allow',
      negativeAction: map['negativeAction'] as String? ?? 'Cancel',
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'title': title,
      'message': message,
      'positiveAction': positiveAction,
      'negativeAction': negativeAction,
    };
  }

  @override
  String toString() =>
      'PermissionRationale(title: $title, message: $message)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PermissionRationale &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          message == other.message;

  @override
  int get hashCode => Object.hash(title, message);
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
