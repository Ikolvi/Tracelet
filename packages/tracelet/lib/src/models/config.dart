import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:tracelet/src/models/_helpers.dart';
import 'package:tracelet/src/models/android_config.dart';
import 'package:tracelet/src/models/attestation_config.dart';
import 'package:tracelet/src/models/audit_config.dart';
import 'package:tracelet/src/models/driving_config.dart';
import 'package:tracelet/src/models/ios_config.dart';
import 'package:tracelet/src/models/privacy_zone_config.dart';
import 'package:tracelet/src/models/security_config.dart';
import 'package:tracelet/src/models/speed_motion_event.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

export 'android_config.dart';
export 'ios_config.dart';

/// Standard configuration profiles for Tracelet.
enum TraceletProfile {
  /// Turn-by-Turn, precise tracking without adaptive degradation.
  highAccuracy,

  /// Standard tracking balancing battery and accuracy. Uses smart motion detection and adaptive mode.
  balanced,

  /// Background-only, battery-sensitive tracking with sparse updates and cellular/wifi locations.
  lowPower,

  /// Extreme battery saving. Never powers on the GPS hardware itself, but passively
  /// receives locations when other apps (like Google Maps) request them.
  passive,
}

/// Top-level compound configuration for Tracelet.
///
/// Organizes settings into logical sub-configs:
/// - [geo] — Shared location accuracy, distance filter, and sampling
/// - [app] — Shared lifecycle behavior, heartbeat, and scheduling
/// - [android] — **Android-only** tuning (foreground service, alarms, intervals)
/// - [ios] — **iOS-only** tuning (activity types, background sessions, suspend protection)
/// - [http] — Server sync settings
/// - [logger] — Logging level and retention
/// - [motion] — Motion detection sensitivity
/// - [geofence] — Geofence proximity and trigger rules
/// - [persistence] — Database retention
/// - [audit] — Tamper-proof location audit trail (Enterprise)
/// - [privacyZone] — Geographic privacy zone controls (Enterprise)
/// - [security] — At-rest database encryption (Enterprise)
/// - [attestation] — Device integrity attestation (Enterprise)
@immutable
class Config {
  /// Creates a new [Config] with optional sub-configs.
  const Config({
    this.geo = const GeoConfig(),
    this.app = const AppConfig(),
    this.android = const AndroidConfig(),
    this.ios = const IosConfig(),
    this.http = const HttpConfig(),
    this.logger = const LoggerConfig(),
    this.motion = const MotionConfig(),
    this.geofence = const GeofenceConfig(),
    this.persistence = const PersistenceConfig(),
    this.audit = const AuditConfig(),
    this.privacyZone = const PrivacyZoneConfig(),
    this.security = const SecurityConfig(),
    this.attestation = const AttestationConfig(),
    this.telematics = const TelematicsConfig(),
    this.classifier = const ClassifierConfig(),
    this.impact = const ImpactConfig(),
  });

  /// High Accuracy profile tailored for turn-by-turn navigation or precise tracking.
  factory Config.highAccuracy() => _fromProfile(TraceletProfile.highAccuracy);

  /// Balanced profile tailored for standard social/fleet apps, balancing accuracy and battery.
  factory Config.balanced() => _fromProfile(TraceletProfile.balanced);

  /// Low Power profile tailored for background-only coarse tracking to maximize battery life.
  factory Config.lowPower() => _fromProfile(TraceletProfile.lowPower);

  /// Passive profile tailored for extreme battery saving. Never powers on the GPS hardware itself,
  /// but passively receives locations when other apps request them. Most effective on Android.
  factory Config.passive() => _fromProfile(TraceletProfile.passive);

  /// Creates a [Config] from a map. Supports both nested and flat formats.
  factory Config.fromMap(Map<String, Object?> map) {
    final geoMap = safeMap(map['geo']);
    final appMap = safeMap(map['app']);
    final androidMap = safeMap(map['android']);
    final iosMap = safeMap(map['ios']);
    final httpMap = safeMap(map['http']);
    final loggerMap = safeMap(map['logger']);
    final motionMap = safeMap(map['motion']);
    final geofenceMap = safeMap(map['geofence']);
    final persistenceMap = safeMap(map['persistence']);
    final auditMap = safeMap(map['audit']);
    final privacyMap = safeMap(map['privacyZone']);
    final securityMap = safeMap(map['security']);
    final attestMap = safeMap(map['attestation']);

    return Config(
      geo: GeoConfig.fromMap(geoMap ?? map),
      app: AppConfig.fromMap(appMap ?? map),
      android: AndroidConfig.fromMap(androidMap ?? map),
      ios: IosConfig.fromMap(iosMap ?? map),
      http: HttpConfig.fromMap(httpMap ?? map),
      logger: LoggerConfig.fromMap(loggerMap ?? map),
      motion: MotionConfig.fromMap(motionMap ?? map),
      geofence: GeofenceConfig.fromMap(geofenceMap ?? map),
      persistence: PersistenceConfig.fromMap(persistenceMap ?? map),
      audit: AuditConfig.fromMap(auditMap ?? map),
      privacyZone: PrivacyZoneConfig.fromMap(privacyMap ?? map),
      security: SecurityConfig.fromMap(securityMap ?? map),
      attestation: AttestationConfig.fromMap(attestMap ?? map),
      telematics: TelematicsConfig.fromMap(safeMap(map['telematics']) ?? map),
      classifier: ClassifierConfig.fromMap(safeMap(map['classifier']) ?? map),
      impact: ImpactConfig.fromMap(safeMap(map['impact']) ?? map),
    );
  }

  /// Shared location accuracy and sampling settings.
  final GeoConfig geo;

  /// Shared application lifecycle and scheduling settings.
  final AppConfig app;

  /// **Android-specific** tuning and foreground service settings.
  final AndroidConfig android;

  /// **iOS-specific** tuning and background session settings.
  final IosConfig ios;

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

  /// **Enterprise** — Tamper-proof location audit trail settings.
  final AuditConfig audit;

  /// **Enterprise** — Privacy zone controls.
  final PrivacyZoneConfig privacyZone;

  /// **Enterprise** — At-rest database encryption.
  final SecurityConfig security;

  /// **Enterprise** — Device integrity attestation.
  final AttestationConfig attestation;

  /// Driving-behavior (telematics) event detection.
  final TelematicsConfig telematics;

  /// On-device transport-mode classifier.
  final ClassifierConfig classifier;

  /// Crash & fall detection.
  final ImpactConfig impact;

  /// Creates a copy of this [Config] with the given fields replaced with the new values.
  Config copyWith({
    GeoConfig? geo,
    AppConfig? app,
    AndroidConfig? android,
    IosConfig? ios,
    HttpConfig? http,
    LoggerConfig? logger,
    MotionConfig? motion,
    GeofenceConfig? geofence,
    PersistenceConfig? persistence,
    AuditConfig? audit,
    PrivacyZoneConfig? privacyZone,
    SecurityConfig? security,
    AttestationConfig? attestation,
    TelematicsConfig? telematics,
    ClassifierConfig? classifier,
    ImpactConfig? impact,
  }) {
    return Config(
      geo: geo ?? this.geo,
      app: app ?? this.app,
      android: android ?? this.android,
      ios: ios ?? this.ios,
      http: http ?? this.http,
      logger: logger ?? this.logger,
      motion: motion ?? this.motion,
      geofence: geofence ?? this.geofence,
      persistence: persistence ?? this.persistence,
      audit: audit ?? this.audit,
      privacyZone: privacyZone ?? this.privacyZone,
      security: security ?? this.security,
      attestation: attestation ?? this.attestation,
      telematics: telematics ?? this.telematics,
      classifier: classifier ?? this.classifier,
      impact: impact ?? this.impact,
    );
  }

  static const Map<TraceletProfile, String> _profilesJson = {
    TraceletProfile.highAccuracy:
        '{"geo":{"desiredAccuracy":0,"distanceFilter":5.0,"stationaryRadius":25.0,"enableAdaptiveMode":false,"disableElasticity":true,"enableDeadReckoning":true,"filter":{"useKalmanFilter":true,"rejectMockLocations":true}},"motion":{"motionDetectionMode":0,"stationaryTrackingMode":0,"stopTimeout":3},"geofence":{"geofenceModeHighAccuracy":true},"android":{"locationUpdateInterval":1000,"fastestLocationUpdateInterval":500}}',
    TraceletProfile.balanced:
        '{"geo":{"desiredAccuracy":1,"distanceFilter":20.0,"stationaryRadius":50.0,"enableAdaptiveMode":true,"disableElasticity":false,"elasticityMultiplier":1.0,"filter":{"useKalmanFilter":false}},"motion":{"motionDetectionMode":2,"stationaryTrackingMode":1,"stopTimeout":5},"geofence":{"geofenceModeHighAccuracy":false},"android":{"locationUpdateInterval":5000}}',
    TraceletProfile.lowPower:
        '{"geo":{"desiredAccuracy":2,"distanceFilter":50.0,"stationaryRadius":100.0,"enableAdaptiveMode":true,"disableElasticity":false,"elasticityMultiplier":2.0,"enableSparseUpdates":true,"sparseDistanceThreshold":100.0},"motion":{"motionDetectionMode":1,"stationaryTrackingMode":1,"stopTimeout":2},"geofence":{"geofenceModeHighAccuracy":false},"android":{"locationUpdateInterval":10000}}',
    TraceletProfile.passive:
        '{"geo":{"desiredAccuracy":4,"distanceFilter":0.0,"stationaryRadius":500.0,"enableAdaptiveMode":false,"enableSparseUpdates":true,"sparseDistanceThreshold":50.0},"motion":{"motionDetectionMode":1,"stationaryTrackingMode":1,"stopTimeout":2},"geofence":{"geofenceModeHighAccuracy":false},"android":{"locationUpdateInterval":60000}}',
  };

  /// Internal factory to load a profile
  static Config _fromProfile(TraceletProfile profile) {
    final jsonStr = _profilesJson[profile]!;
    final baseMap = json.decode(jsonStr) as Map<String, dynamic>;
    return Config.fromMap(baseMap);
  }

  /// Converts this [Config] to a Pigeon-generated [TlConfig].
  TlConfig toTlConfig() => TlConfig(
    geo: geo.toTlConfig(),
    app: app.toTlConfig(),
    android: android.toTlConfig(),
    ios: ios.toTlConfig(),
    http: http.toTlConfig(),
    logger: logger.toTlConfig(),
    motion: motion.toTlConfig(),
    geofence: geofence.toTlConfig(),
    persistence: persistence.toTlConfig(),
    audit: audit.toTlConfig(),
    privacyZone: privacyZone.toTlConfig(),
    security: security.toTlConfig(),
    attestation: attestation.toTlConfig(),
    telematics: telematics.toTlConfig(),
    classifier: classifier.toTlConfig(),
    impact: impact.toTlConfig(),
  );

  /// Serializes to a nested map suitable for platform channel transmission.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'geo': geo.toMap(),
      'app': app.toMap(),
      'android': android.toMap(),
      'ios': ios.toMap(),
      'http': http.toMap(),
      'logger': logger.toMap(),
      'motion': motion.toMap(),
      'geofence': geofence.toMap(),
      'persistence': persistence.toMap(),
      'audit': audit.toMap(),
      'privacyZone': privacyZone.toMap(),
      'security': security.toMap(),
      'attestation': attestation.toMap(),
      'telematics': telematics.toMap(),
      'classifier': classifier.toMap(),
      'impact': impact.toMap(),
    };
  }

  @override
  String toString() =>
      'Config(geo: $geo, app: $app, android: $android, ios: $ios, http: $http, '
      'logger: $logger, motion: $motion, geofence: $geofence, '
      'persistence: $persistence, audit: $audit, privacyZone: $privacyZone, '
      'security: $security, attestation: $attestation, '
      'telematics: $telematics, classifier: $classifier, impact: $impact)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Config &&
          runtimeType == other.runtimeType &&
          geo == other.geo &&
          app == other.app &&
          android == other.android &&
          ios == other.ios &&
          http == other.http &&
          logger == other.logger &&
          motion == other.motion &&
          geofence == other.geofence &&
          persistence == other.persistence &&
          audit == other.audit &&
          privacyZone == other.privacyZone &&
          security == other.security &&
          attestation == other.attestation &&
          telematics == other.telematics &&
          classifier == other.classifier &&
          impact == other.impact;

  @override
  int get hashCode => Object.hashAll([
    geo,
    app,
    android,
    ios,
    http,
    logger,
    motion,
    geofence,
    persistence,
    audit,
    privacyZone,
    security,
    attestation,
    telematics,
    classifier,
    impact,
  ]);
}

/// GPS filtering and smoothing options.
@immutable
class LocationFilter {
  /// Creates a new [LocationFilter] with optional overrides.
  const LocationFilter({
    this.trackingAccuracyThreshold = 100,
    this.maxImpliedSpeed = 80,
    this.odometerAccuracyThreshold = 50,
    this.policy = LocationFilterPolicy.adjust,
    this.rejectMockLocations = false,
    this.mockDetectionLevel = 1,
    this.useKalmanFilter = false,
  });

  /// Creates a [LocationFilter] from a map.
  factory LocationFilter.fromMap(Map<String, Object?> map) {
    return LocationFilter(
      trackingAccuracyThreshold: ensureInt(
        map['trackingAccuracyThreshold'],
        fallback: 100,
      ),
      maxImpliedSpeed: ensureInt(map['maxImpliedSpeed'], fallback: 80),
      odometerAccuracyThreshold: ensureInt(
        map['odometerAccuracyThreshold'],
        fallback: 50,
      ),
      policy:
          LocationFilterPolicy.values[ensureInt(
            map['policy'],
            fallback: 0,
          ).clamp(0, LocationFilterPolicy.values.length - 1)],
      rejectMockLocations: ensureBool(
        map['rejectMockLocations'],
        fallback: false,
      ),
      mockDetectionLevel: ensureInt(map['mockDetectionLevel'], fallback: 1),
      useKalmanFilter: ensureBool(map['useKalmanFilter'], fallback: false),
    );
  }

  /// Reject locations with accuracy worse than this value (meters).
  final int trackingAccuracyThreshold;

  /// Reject locations that imply a speed greater than this value (m/s).
  final int maxImpliedSpeed;

  /// Only count locations with accuracy better than this value toward odometer.
  final int odometerAccuracyThreshold;

  /// How to handle rejected locations.
  final LocationFilterPolicy policy;

  /// Reject locations flagged as mock by the OS.
  final bool rejectMockLocations;

  /// Sensitivity level for custom mock detection.
  final int mockDetectionLevel;

  /// Whether the Kalman filter is currently enabled for GPS smoothing.
  final bool useKalmanFilter;

  /// Converts to Pigeon [TlLocationFilter].
  TlLocationFilter toTlConfig() => TlLocationFilter(
    trackingAccuracyThreshold: trackingAccuracyThreshold,
    maxImpliedSpeed: maxImpliedSpeed,
    odometerAccuracyThreshold: odometerAccuracyThreshold,
    policy: TlLocationFilterPolicy.values[policy.index],
    rejectMockLocations: rejectMockLocations,
    mockDetectionLevel: mockDetectionLevel,
    useKalmanFilter: useKalmanFilter,
  );

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'trackingAccuracyThreshold': trackingAccuracyThreshold,
      'maxImpliedSpeed': maxImpliedSpeed,
      'odometerAccuracyThreshold': odometerAccuracyThreshold,
      'policy': policy.index,
      'rejectMockLocations': rejectMockLocations,
      'mockDetectionLevel': mockDetectionLevel,
      'useKalmanFilter': useKalmanFilter,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocationFilter &&
          runtimeType == other.runtimeType &&
          trackingAccuracyThreshold == other.trackingAccuracyThreshold &&
          maxImpliedSpeed == other.maxImpliedSpeed &&
          odometerAccuracyThreshold == other.odometerAccuracyThreshold &&
          policy == other.policy &&
          rejectMockLocations == other.rejectMockLocations &&
          mockDetectionLevel == other.mockDetectionLevel &&
          useKalmanFilter == other.useKalmanFilter;

  @override
  int get hashCode => Object.hash(
    trackingAccuracyThreshold,
    maxImpliedSpeed,
    odometerAccuracyThreshold,
    policy,
    rejectMockLocations,
    mockDetectionLevel,
    useKalmanFilter,
  );
}

/// Shared location accuracy and sampling settings.
@immutable
class GeoConfig {
  /// Creates a new [GeoConfig] with optional overrides.
  const GeoConfig({
    this.desiredAccuracy = DesiredAccuracy.high,
    this.distanceFilter = 10.0,
    this.stationaryRadius = 25.0,
    this.locationTimeout = 60,
    this.disableElasticity = false,
    this.elasticityMultiplier = 1.0,
    this.stopAfterElapsedMinutes = -1,
    this.maxMonitoredGeofences = -1,
    this.enableTimestampMeta = false,
    this.enableAdaptiveMode = false,
    this.periodicLocationInterval = 900,
    this.periodicDesiredAccuracy = DesiredAccuracy.medium,
    this.enableSparseUpdates = false,
    this.sparseDistanceThreshold = 50.0,
    this.sparseMaxIdleSeconds = 300,
    this.batteryBudgetPerHour = 0.0,
    this.enableDeadReckoning = false,
    this.deadReckoningActivationDelay = 0,
    this.deadReckoningMaxDuration = 0,
    this.filter = const LocationFilter(),
    this.resolveAddress = false,
  });

  /// Creates a [GeoConfig] from a map.
  factory GeoConfig.fromMap(Map<String, Object?> map) {
    return GeoConfig(
      desiredAccuracy:
          DesiredAccuracy.values[ensureInt(
            map['desiredAccuracy'],
            fallback: 0,
          ).clamp(0, DesiredAccuracy.values.length - 1)],
      distanceFilter: ensureDouble(map['distanceFilter'], fallback: 10),
      stationaryRadius: ensureDouble(map['stationaryRadius'], fallback: 25),
      locationTimeout: ensureInt(map['locationTimeout'], fallback: 60),
      disableElasticity: ensureBool(map['disableElasticity'], fallback: false),
      elasticityMultiplier: ensureDouble(
        map['elasticityMultiplier'],
        fallback: 1,
      ),
      stopAfterElapsedMinutes: ensureInt(
        map['stopAfterElapsedMinutes'],
        fallback: -1,
      ),
      maxMonitoredGeofences: ensureInt(
        map['maxMonitoredGeofences'],
        fallback: -1,
      ),
      enableTimestampMeta: ensureBool(
        map['enableTimestampMeta'],
        fallback: false,
      ),
      enableAdaptiveMode: ensureBool(
        map['enableAdaptiveMode'],
        fallback: false,
      ),
      periodicLocationInterval: ensureInt(
        map['periodicLocationInterval'],
        fallback: 900,
      ),
      periodicDesiredAccuracy:
          DesiredAccuracy.values[ensureInt(
            map['periodicDesiredAccuracy'],
            fallback: 1, // medium
          ).clamp(0, DesiredAccuracy.values.length - 1)],
      enableSparseUpdates: ensureBool(
        map['enableSparseUpdates'],
        fallback: false,
      ),
      sparseDistanceThreshold: ensureDouble(
        map['sparseDistanceThreshold'],
        fallback: 50,
      ),
      sparseMaxIdleSeconds: ensureInt(
        map['sparseMaxIdleSeconds'],
        fallback: 300,
      ),
      batteryBudgetPerHour: ensureDouble(
        map['batteryBudgetPerHour'],
        fallback: 0,
      ),
      enableDeadReckoning: ensureBool(
        map['enableDeadReckoning'],
        fallback: false,
      ),
      deadReckoningActivationDelay: ensureInt(
        map['deadReckoningActivationDelay'],
        fallback: 0,
      ),
      deadReckoningMaxDuration: ensureInt(
        map['deadReckoningMaxDuration'],
        fallback: 0,
      ),
      filter: LocationFilter.fromMap(safeMap(map['filter']) ?? map),
      resolveAddress: ensureBool(map['resolveAddress'], fallback: false),
    );
  }

  /// Creates a copy of this [GeoConfig] with the given fields replaced with the new values.
  GeoConfig copyWith({
    DesiredAccuracy? desiredAccuracy,
    double? distanceFilter,
    double? stationaryRadius,
    int? locationTimeout,
    bool? disableElasticity,
    double? elasticityMultiplier,
    int? stopAfterElapsedMinutes,
    int? maxMonitoredGeofences,
    bool? enableTimestampMeta,
    bool? enableAdaptiveMode,
    int? periodicLocationInterval,
    DesiredAccuracy? periodicDesiredAccuracy,
    bool? enableSparseUpdates,
    double? sparseDistanceThreshold,
    int? sparseMaxIdleSeconds,
    double? batteryBudgetPerHour,
    bool? enableDeadReckoning,
    int? deadReckoningActivationDelay,
    int? deadReckoningMaxDuration,
    LocationFilter? filter,
    bool? resolveAddress,
  }) {
    return GeoConfig(
      desiredAccuracy: desiredAccuracy ?? this.desiredAccuracy,
      distanceFilter: distanceFilter ?? this.distanceFilter,
      stationaryRadius: stationaryRadius ?? this.stationaryRadius,
      locationTimeout: locationTimeout ?? this.locationTimeout,
      disableElasticity: disableElasticity ?? this.disableElasticity,
      elasticityMultiplier: elasticityMultiplier ?? this.elasticityMultiplier,
      stopAfterElapsedMinutes:
          stopAfterElapsedMinutes ?? this.stopAfterElapsedMinutes,
      maxMonitoredGeofences:
          maxMonitoredGeofences ?? this.maxMonitoredGeofences,
      enableTimestampMeta: enableTimestampMeta ?? this.enableTimestampMeta,
      enableAdaptiveMode: enableAdaptiveMode ?? this.enableAdaptiveMode,
      periodicLocationInterval:
          periodicLocationInterval ?? this.periodicLocationInterval,
      periodicDesiredAccuracy:
          periodicDesiredAccuracy ?? this.periodicDesiredAccuracy,
      enableSparseUpdates: enableSparseUpdates ?? this.enableSparseUpdates,
      sparseDistanceThreshold:
          sparseDistanceThreshold ?? this.sparseDistanceThreshold,
      sparseMaxIdleSeconds: sparseMaxIdleSeconds ?? this.sparseMaxIdleSeconds,
      batteryBudgetPerHour: batteryBudgetPerHour ?? this.batteryBudgetPerHour,
      enableDeadReckoning: enableDeadReckoning ?? this.enableDeadReckoning,
      deadReckoningActivationDelay:
          deadReckoningActivationDelay ?? this.deadReckoningActivationDelay,
      deadReckoningMaxDuration:
          deadReckoningMaxDuration ?? this.deadReckoningMaxDuration,
      filter: filter ?? this.filter,
      resolveAddress: resolveAddress ?? this.resolveAddress,
    );
  }

  /// The desired location accuracy.
  /// Defaults to [DesiredAccuracy.high].
  final DesiredAccuracy desiredAccuracy;

  /// The minimum distance (in meters) the device must move horizontally before
  /// a new location update is recorded. Defaults to `10.0`.
  final double distanceFilter;

  /// The radius (in meters) around the stationary location where the device
  /// is considered stationary. Defaults to `25.0`.
  final double stationaryRadius;

  /// The timeout (in seconds) for a location request before giving up.
  /// Defaults to `60`.
  final int locationTimeout;

  /// Disable speed-based distance filter elasticity.
  /// Defaults to `false`.
  final bool disableElasticity;

  /// Scale factor for the speed-based elastic distance filter.
  /// Defaults to `1.0`.
  final double elasticityMultiplier;

  /// Auto-stop tracking after this many minutes have elapsed since start.
  /// `-1` means disabled. Defaults to `-1`.
  final int stopAfterElapsedMinutes;

  /// Maximum simultaneously monitored geofences.
  /// `-1` to fall back to platform defaults (100 on Android, 20 on iOS).
  /// Defaults to `-1`.
  final int maxMonitoredGeofences;

  /// Enable adding extra timestamp metadata to each location payload.
  /// Defaults to `false`.
  final bool enableTimestampMeta;

  /// Enable adaptive sampling mode which automatically scales [distanceFilter]
  /// based on detected activity, speed, and battery levels.
  /// Defaults to `false`.
  final bool enableAdaptiveMode;

  /// The interval (in seconds) between locations in periodic mode.
  /// Minimum is 60s. Defaults to `900`.
  final int periodicLocationInterval;

  /// The desired GPS accuracy level for each periodic update.
  /// Defaults to [DesiredAccuracy.medium].
  final DesiredAccuracy periodicDesiredAccuracy;

  /// Enable sparse updates to deduplicate location recording at the database layer.
  /// Drops locations within [sparseDistanceThreshold] of the last recorded position.
  /// Defaults to `false`.
  final bool enableSparseUpdates;

  /// Minimum horizontal distance (in meters) between locations in sparse mode.
  /// Defaults to `50.0`.
  final double sparseDistanceThreshold;

  /// Force a recorded location update after this many seconds of idle time
  /// even if the device hasn't moved beyond [sparseDistanceThreshold].
  /// Defaults to `300`.
  final int sparseMaxIdleSeconds;

  /// Target maximum battery drain per hour (%).
  /// `0.0` disables battery budget-based parameter scaling.
  /// Defaults to `0.0`.
  final double batteryBudgetPerHour;

  /// Enable dead reckoning inertial sensor fusion for GPS-denied environments.
  /// Defaults to `false`.
  final bool enableDeadReckoning;

  /// Seconds without GPS signal before starting dead reckoning estimation.
  /// Defaults to `0`.
  final int deadReckoningActivationDelay;

  /// Maximum seconds to run dead reckoning positioning.
  /// Defaults to `0` (unlimited).
  final int deadReckoningMaxDuration;

  /// The GPS filtering and smoothing configuration.
  /// Defaults to [LocationFilter].
  final LocationFilter filter;

  /// Automatically resolve coordinates to a street address using the native OS Geocoder.
  /// Defaults to `false` to save network and battery.
  final bool resolveAddress;

  /// Converts to Pigeon [TlGeoConfig].
  TlGeoConfig toTlConfig() => TlGeoConfig(
    desiredAccuracy: TlDesiredAccuracy.values[desiredAccuracy.index],
    distanceFilter: distanceFilter,
    stationaryRadius: stationaryRadius,
    locationTimeout: locationTimeout,
    disableElasticity: disableElasticity,
    elasticityMultiplier: elasticityMultiplier,
    stopAfterElapsedMinutes: stopAfterElapsedMinutes,
    maxMonitoredGeofences: maxMonitoredGeofences,
    enableTimestampMeta: enableTimestampMeta,
    enableAdaptiveMode: enableAdaptiveMode,
    periodicLocationInterval: periodicLocationInterval,
    periodicDesiredAccuracy:
        TlDesiredAccuracy.values[periodicDesiredAccuracy.index],
    enableSparseUpdates: enableSparseUpdates,
    sparseDistanceThreshold: sparseDistanceThreshold,
    sparseMaxIdleSeconds: sparseMaxIdleSeconds,
    batteryBudgetPerHour: batteryBudgetPerHour,
    enableDeadReckoning: enableDeadReckoning,
    deadReckoningActivationDelay: deadReckoningActivationDelay,
    deadReckoningMaxDuration: deadReckoningMaxDuration,
    filter: filter.toTlConfig(),
    resolveAddress: resolveAddress,
  );

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'desiredAccuracy': desiredAccuracy.index,
      'distanceFilter': distanceFilter,
      'stationaryRadius': stationaryRadius,
      'locationTimeout': locationTimeout,
      'disableElasticity': disableElasticity,
      'elasticityMultiplier': elasticityMultiplier,
      'stopAfterElapsedMinutes': stopAfterElapsedMinutes,
      'maxMonitoredGeofences': maxMonitoredGeofences,
      'enableTimestampMeta': enableTimestampMeta,
      'enableAdaptiveMode': enableAdaptiveMode,
      'periodicLocationInterval': periodicLocationInterval,
      'periodicDesiredAccuracy': periodicDesiredAccuracy.index,
      'enableSparseUpdates': enableSparseUpdates,
      'sparseDistanceThreshold': sparseDistanceThreshold,
      'sparseMaxIdleSeconds': sparseMaxIdleSeconds,
      'batteryBudgetPerHour': batteryBudgetPerHour,
      'enableDeadReckoning': enableDeadReckoning,
      'deadReckoningActivationDelay': deadReckoningActivationDelay,
      'deadReckoningMaxDuration': deadReckoningMaxDuration,
      'filter': filter.toMap(),
      'resolveAddress': resolveAddress,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeoConfig &&
          runtimeType == other.runtimeType &&
          desiredAccuracy == other.desiredAccuracy &&
          distanceFilter == other.distanceFilter &&
          stationaryRadius == other.stationaryRadius &&
          locationTimeout == other.locationTimeout &&
          disableElasticity == other.disableElasticity &&
          elasticityMultiplier == other.elasticityMultiplier &&
          stopAfterElapsedMinutes == other.stopAfterElapsedMinutes &&
          maxMonitoredGeofences == other.maxMonitoredGeofences &&
          enableTimestampMeta == other.enableTimestampMeta &&
          enableAdaptiveMode == other.enableAdaptiveMode &&
          periodicLocationInterval == other.periodicLocationInterval &&
          periodicDesiredAccuracy == other.periodicDesiredAccuracy &&
          enableSparseUpdates == other.enableSparseUpdates &&
          sparseDistanceThreshold == other.sparseDistanceThreshold &&
          sparseMaxIdleSeconds == other.sparseMaxIdleSeconds &&
          batteryBudgetPerHour == other.batteryBudgetPerHour &&
          enableDeadReckoning == other.enableDeadReckoning &&
          deadReckoningActivationDelay == other.deadReckoningActivationDelay &&
          deadReckoningMaxDuration == other.deadReckoningMaxDuration &&
          filter == other.filter &&
          resolveAddress == other.resolveAddress;

  @override
  int get hashCode => Object.hashAll([
    desiredAccuracy,
    distanceFilter,
    stationaryRadius,
    locationTimeout,
    disableElasticity,
    elasticityMultiplier,
    stopAfterElapsedMinutes,
    maxMonitoredGeofences,
    enableTimestampMeta,
    enableAdaptiveMode,
    periodicLocationInterval,
    periodicDesiredAccuracy,
    enableSparseUpdates,
    sparseDistanceThreshold,
    sparseMaxIdleSeconds,
    batteryBudgetPerHour,
    enableDeadReckoning,
    deadReckoningActivationDelay,
    deadReckoningMaxDuration,
    filter,
    resolveAddress,
  ]);
}

/// Shared application lifecycle and scheduling settings.
@immutable
class AppConfig {
  /// Creates a new [AppConfig] with optional overrides.
  const AppConfig({
    this.stopOnTerminate = true,
    this.startOnBoot = false,
    this.heartbeatInterval = 60,
    this.schedule = const <String>[],
    this.remoteConfigUrl,
    this.remoteConfigHeaders,
    this.remoteConfigTimeout = 60000,
    this.remoteConfigRefreshInterval = 1440,
  });

  /// Creates an [AppConfig] from a map.
  factory AppConfig.fromMap(Map<String, Object?> map) {
    final rawSchedule = map['schedule'];
    final scheduleList = <String>[];
    if (rawSchedule is List) {
      for (final item in rawSchedule) {
        if (item is String) scheduleList.add(item);
      }
    }
    return AppConfig(
      stopOnTerminate: ensureBool(map['stopOnTerminate'], fallback: true),
      startOnBoot: ensureBool(map['startOnBoot'], fallback: false),
      heartbeatInterval: ensureInt(map['heartbeatInterval'], fallback: 60),
      schedule: scheduleList,
      remoteConfigUrl: map['remoteConfigUrl'] as String?,
      remoteConfigHeaders: (map['remoteConfigHeaders'] as Map?)
          ?.cast<String, String>(),
      remoteConfigTimeout: ensureInt(
        map['remoteConfigTimeout'],
        fallback: 60000,
      ),
      remoteConfigRefreshInterval: ensureInt(
        map['remoteConfigRefreshInterval'],
        fallback: 1440,
      ),
    );
  }

  /// Creates a copy of this [AppConfig] with the given fields replaced with the new values.
  AppConfig copyWith({
    bool? stopOnTerminate,
    bool? startOnBoot,
    int? heartbeatInterval,
    List<String>? schedule,
    String? remoteConfigUrl,
    Map<String, String>? remoteConfigHeaders,
    int? remoteConfigTimeout,
    int? remoteConfigRefreshInterval,
  }) {
    return AppConfig(
      stopOnTerminate: stopOnTerminate ?? this.stopOnTerminate,
      startOnBoot: startOnBoot ?? this.startOnBoot,
      heartbeatInterval: heartbeatInterval ?? this.heartbeatInterval,
      schedule: schedule ?? this.schedule,
      remoteConfigUrl: remoteConfigUrl ?? this.remoteConfigUrl,
      remoteConfigHeaders: remoteConfigHeaders ?? this.remoteConfigHeaders,
      remoteConfigTimeout: remoteConfigTimeout ?? this.remoteConfigTimeout,
      remoteConfigRefreshInterval:
          remoteConfigRefreshInterval ?? this.remoteConfigRefreshInterval,
    );
  }

  /// Whether to stop location tracking when the application is terminated/killed by the user or OS.
  /// Defaults to `true`.
  final bool stopOnTerminate;

  /// Whether to automatically start/resume location tracking after the device reboots.
  /// Defaults to `false`.
  final bool startOnBoot;

  /// The interval (in seconds) between heartbeat events.
  /// Set to `-1` to disable heartbeat monitoring. Defaults to `60`.
  final int heartbeatInterval;

  /// A list of cron-like schedule strings representing active tracking windows.
  /// Defaults to empty list (no schedule constraint).
  final List<String> schedule;

  /// URL of the remote configuration server to fetch settings dynamically at runtime.
  /// Defaults to `null`.
  final String? remoteConfigUrl;

  /// Custom HTTP headers to include with the remote configuration fetch request.
  /// Defaults to `null`.
  final Map<String, String>? remoteConfigHeaders;

  /// Timeout in milliseconds for fetching the remote configuration.
  /// Defaults to `60000` (60 seconds).
  final int remoteConfigTimeout;

  /// How often to refresh/fetch the remote configuration (in minutes).
  /// Defaults to `1440` (24 hours).
  final int remoteConfigRefreshInterval;

  /// Converts to Pigeon [TlAppConfig].
  TlAppConfig toTlConfig() => TlAppConfig(
    stopOnTerminate: stopOnTerminate,
    startOnBoot: startOnBoot,
    heartbeatInterval: heartbeatInterval,
    schedule: schedule,
    remoteConfigUrl: remoteConfigUrl,
    remoteConfigHeaders: remoteConfigHeaders,
    remoteConfigTimeout: remoteConfigTimeout,
    remoteConfigRefreshInterval: remoteConfigRefreshInterval,
  );

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'stopOnTerminate': stopOnTerminate,
      'startOnBoot': startOnBoot,
      'heartbeatInterval': heartbeatInterval,
      'schedule': schedule,
      'remoteConfigUrl': remoteConfigUrl,
      'remoteConfigHeaders': remoteConfigHeaders,
      'remoteConfigTimeout': remoteConfigTimeout,
      'remoteConfigRefreshInterval': remoteConfigRefreshInterval,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppConfig &&
          runtimeType == other.runtimeType &&
          stopOnTerminate == other.stopOnTerminate &&
          startOnBoot == other.startOnBoot &&
          heartbeatInterval == other.heartbeatInterval &&
          schedule == other.schedule &&
          remoteConfigUrl == other.remoteConfigUrl &&
          remoteConfigHeaders == other.remoteConfigHeaders &&
          remoteConfigTimeout == other.remoteConfigTimeout &&
          remoteConfigRefreshInterval == other.remoteConfigRefreshInterval;

  @override
  int get hashCode => Object.hash(
    stopOnTerminate,
    startOnBoot,
    heartbeatInterval,
    schedule,
    remoteConfigUrl,
    remoteConfigHeaders,
    remoteConfigTimeout,
    remoteConfigRefreshInterval,
  );
}

/// HTTP sync settings.
@immutable
class HttpConfig {
  /// Creates a new [HttpConfig] with optional overrides.
  const HttpConfig({
    this.url,
    this.method = HttpMethod.post,
    this.headers,
    this.params,
    this.extras,
    this.httpRootProperty = 'location',
    this.autoSync = true,
    this.batchSync = false,
    this.maxBatchSize = 250,
    this.autoSyncThreshold = 0,
    this.autoSyncDelay = 10000,
    this.syncInterval = 0,
    this.httpTimeout = 60000,
    this.locationsOrderDirection = LocationOrderDirection.ascending,
    this.disableAutoSyncOnCellular = false,
    this.maxRetries = 3,
    this.retryBackoffBase = 1000,
    this.retryBackoffCap = 60000,
    this.enableDeltaCompression = false,
    this.deltaCoordinatePrecision = 5,
    this.sslPinningFingerprints,
    this.sslPinningCertificates,
    this.syncTelematics = false,
    this.telematicsUrl,
  });

  /// Creates an [HttpConfig] from a map.
  factory HttpConfig.fromMap(Map<String, Object?> map) {
    return HttpConfig(
      url: map['url'] as String?,
      method:
          HttpMethod.values[ensureInt(
            map['method'],
            fallback: 0,
          ).clamp(0, HttpMethod.values.length - 1)],
      headers: (map['headers'] as Map?)?.cast<String, String>(),
      params: (map['params'] as Map?)?.cast<String, Object?>(),
      extras: (map['extras'] as Map?)?.cast<String, Object?>(),
      httpRootProperty: map['httpRootProperty'] as String? ?? 'location',
      autoSync: ensureBool(map['autoSync'], fallback: true),
      batchSync: ensureBool(map['batchSync'], fallback: false),
      maxBatchSize: ensureInt(map['maxBatchSize'], fallback: 250),
      autoSyncThreshold: ensureInt(map['autoSyncThreshold'], fallback: 0),
      autoSyncDelay: ensureInt(map['autoSyncDelay'], fallback: 10000),
      syncInterval: ensureInt(map['syncInterval'], fallback: 0),
      httpTimeout: ensureInt(map['httpTimeout'], fallback: 60000),
      locationsOrderDirection:
          LocationOrderDirection.values[ensureInt(
            map['locationsOrderDirection'],
            fallback: 0,
          ).clamp(0, LocationOrderDirection.values.length - 1)],
      disableAutoSyncOnCellular: ensureBool(
        map['disableAutoSyncOnCellular'],
        fallback: false,
      ),
      maxRetries: ensureInt(map['maxRetries'], fallback: 3),
      retryBackoffBase: ensureInt(map['retryBackoffBase'], fallback: 1000),
      retryBackoffCap: ensureInt(map['retryBackoffCap'], fallback: 60000),
      enableDeltaCompression: ensureBool(
        map['enableDeltaCompression'],
        fallback: false,
      ),
      deltaCoordinatePrecision: ensureInt(
        map['deltaCoordinatePrecision'],
        fallback: 5,
      ),
      sslPinningFingerprints: (map['sslPinningFingerprints'] as List?)
          ?.cast<String>(),
      sslPinningCertificates: (map['sslPinningCertificates'] as List?)
          ?.cast<String>(),
      syncTelematics: ensureBool(map['syncTelematics'], fallback: false),
      telematicsUrl: map['telematicsUrl'] as String?,
    );
  }

  /// Creates a copy of this [HttpConfig] with the given fields replaced with the new values.
  HttpConfig copyWith({
    String? url,
    HttpMethod? method,
    Map<String, String>? headers,
    Map<String, Object?>? params,
    Map<String, Object?>? extras,
    String? httpRootProperty,
    bool? autoSync,
    bool? batchSync,
    int? maxBatchSize,
    int? autoSyncThreshold,
    int? autoSyncDelay,
    int? syncInterval,
    int? httpTimeout,
    LocationOrderDirection? locationsOrderDirection,
    bool? disableAutoSyncOnCellular,
    int? maxRetries,
    int? retryBackoffBase,
    int? retryBackoffCap,
    bool? enableDeltaCompression,
    int? deltaCoordinatePrecision,
    List<String>? sslPinningFingerprints,
    List<String>? sslPinningCertificates,
    bool? syncTelematics,
    String? telematicsUrl,
  }) {
    return HttpConfig(
      url: url ?? this.url,
      method: method ?? this.method,
      headers: headers ?? this.headers,
      params: params ?? this.params,
      extras: extras ?? this.extras,
      httpRootProperty: httpRootProperty ?? this.httpRootProperty,
      autoSync: autoSync ?? this.autoSync,
      batchSync: batchSync ?? this.batchSync,
      maxBatchSize: maxBatchSize ?? this.maxBatchSize,
      autoSyncThreshold: autoSyncThreshold ?? this.autoSyncThreshold,
      autoSyncDelay: autoSyncDelay ?? this.autoSyncDelay,
      syncInterval: syncInterval ?? this.syncInterval,
      httpTimeout: httpTimeout ?? this.httpTimeout,
      locationsOrderDirection:
          locationsOrderDirection ?? this.locationsOrderDirection,
      disableAutoSyncOnCellular:
          disableAutoSyncOnCellular ?? this.disableAutoSyncOnCellular,
      maxRetries: maxRetries ?? this.maxRetries,
      retryBackoffBase: retryBackoffBase ?? this.retryBackoffBase,
      retryBackoffCap: retryBackoffCap ?? this.retryBackoffCap,
      enableDeltaCompression:
          enableDeltaCompression ?? this.enableDeltaCompression,
      deltaCoordinatePrecision:
          deltaCoordinatePrecision ?? this.deltaCoordinatePrecision,
      sslPinningFingerprints:
          sslPinningFingerprints ?? this.sslPinningFingerprints,
      sslPinningCertificates:
          sslPinningCertificates ?? this.sslPinningCertificates,
      syncTelematics: syncTelematics ?? this.syncTelematics,
      telematicsUrl: telematicsUrl ?? this.telematicsUrl,
    );
  }

  /// The HTTP server URL to sync locations to.
  /// Defaults to `null`.
  final String? url;

  /// The HTTP method to use for sync requests (POST or PUT).
  /// Defaults to [HttpMethod.post].
  final HttpMethod method;

  /// Custom HTTP headers to include with each sync request.
  /// Defaults to `null`.
  final Map<String, String>? headers;

  /// Custom query parameters or extra JSON fields to send with each sync payload.
  /// Defaults to `null`.
  final Map<String, Object?>? params;

  /// Custom JSON fields to inject at the root of the sync payload.
  /// Defaults to `null`.
  final Map<String, Object?>? extras;

  /// The root JSON property name for the array of locations in the sync payload.
  /// Defaults to `'location'`.
  final String? httpRootProperty;

  /// Whether to auto-sync locations immediately when they are recorded/inserted into the database.
  /// Defaults to `true`.
  final bool autoSync;

  /// Send all locations in a batch array within one request instead of one request per location.
  /// Defaults to `false`.
  final bool batchSync;

  /// The maximum number of records to send in a single batch.
  /// Defaults to `250`.
  final int maxBatchSize;

  /// Minimum number of unsynced locations in the database before auto-sync triggers.
  /// Defaults to `0`.
  final int autoSyncThreshold;

  /// Delay in milliseconds before batching rapid location syncs (debounce time).
  /// Defaults to `10000` (10 seconds).
  final int autoSyncDelay;

  /// Interval, in **seconds**, for the repeating sync timer (interval-based sync).
  ///
  /// When greater than `0`, the SDK periodically flushes any pending locations
  /// to [url] on this cadence, in addition to the debounced auto-sync controlled
  /// by [autoSyncDelay]. This is useful for time-driven flushing of the offline
  /// queue regardless of how many records have accumulated.
  ///
  /// Defaults to `0` (the repeating timer is disabled).
  final int syncInterval;

  /// Request timeout in milliseconds.
  /// Defaults to `60000` (60 seconds).
  final int httpTimeout;

  /// The chronological sort order for synced locations.
  /// Defaults to [LocationOrderDirection.ascending].
  final LocationOrderDirection locationsOrderDirection;

  /// Disable auto-syncing when on a cellular data network (syncs only on Wi-Fi).
  /// Defaults to `false`.
  final bool disableAutoSyncOnCellular;

  /// Maximum retry attempts for transient HTTP failures (e.g. 5xx, 429, timeout).
  /// Defaults to `3`.
  final int maxRetries;

  /// Base delay in seconds for exponential backoff between retries.
  /// Defaults to `1`.
  final int retryBackoffBase;

  /// Maximum backoff delay in seconds (caps exponential growth).
  /// Defaults to `60`.
  final int retryBackoffCap;

  /// Enable delta-encoding compression for batch sync payloads.
  /// Drops duplicate headers and applies delta compression to coordinates, returning 60–80% size reduction.
  /// Defaults to `false`.
  final bool enableDeltaCompression;

  /// Coordinate decimal precision for delta compression (e.g. 5 ≈ 1.1m, 6 ≈ 0.11m).
  /// Defaults to `5`.
  final int deltaCoordinatePrecision;

  /// **Enterprise** — SHA-256 SSL public key pin fingerprints.
  final List<String>? sslPinningFingerprints;

  /// **Enterprise** — Base64 encoded SSL certificates.
  final List<String>? sslPinningCertificates;

  /// Whether to sync telematics events automatically.
  final bool syncTelematics;

  /// The URL to sync telematics events to.
  final String? telematicsUrl;

  /// Converts to Pigeon [TlHttpConfig].
  TlHttpConfig toTlConfig() => TlHttpConfig(
    url: url,
    method: TlHttpMethod.values[method.index],
    headers: headers,
    params: params,
    extras: extras,
    httpRootProperty: httpRootProperty,
    autoSync: autoSync,
    batchSync: batchSync,
    maxBatchSize: maxBatchSize,
    autoSyncThreshold: autoSyncThreshold,
    autoSyncDelay: autoSyncDelay,
    syncInterval: syncInterval,
    httpTimeout: httpTimeout,
    locationsOrderDirection:
        TlLocationOrderDirection.values[locationsOrderDirection.index],
    disableAutoSyncOnCellular: disableAutoSyncOnCellular,
    maxRetries: maxRetries,
    retryBackoffBase: retryBackoffBase,
    retryBackoffCap: retryBackoffCap,
    enableDeltaCompression: enableDeltaCompression,
    deltaCoordinatePrecision: deltaCoordinatePrecision,
    syncTelematics: syncTelematics,
    telematicsUrl: telematicsUrl,
    sslPinningFingerprints: sslPinningFingerprints,
    sslPinningCertificates: sslPinningCertificates,
  );

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'url': url,
      'method': method.index,
      'headers': headers,
      'params': params,
      'extras': extras,
      'httpRootProperty': httpRootProperty,
      'autoSync': autoSync,
      'batchSync': batchSync,
      'maxBatchSize': maxBatchSize,
      'autoSyncThreshold': autoSyncThreshold,
      'autoSyncDelay': autoSyncDelay,
      'syncInterval': syncInterval,
      'httpTimeout': httpTimeout,
      'locationsOrderDirection': locationsOrderDirection.index,
      'disableAutoSyncOnCellular': disableAutoSyncOnCellular,
      'maxRetries': maxRetries,
      'retryBackoffBase': retryBackoffBase,
      'retryBackoffCap': retryBackoffCap,
      'enableDeltaCompression': enableDeltaCompression,
      'deltaCoordinatePrecision': deltaCoordinatePrecision,
      'syncTelematics': syncTelematics,
      'telematicsUrl': telematicsUrl,
      'sslPinningFingerprints': sslPinningFingerprints,
      'sslPinningCertificates': sslPinningCertificates,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HttpConfig &&
          runtimeType == other.runtimeType &&
          url == other.url &&
          method == other.method &&
          headers == other.headers &&
          params == other.params &&
          extras == other.extras &&
          httpRootProperty == other.httpRootProperty &&
          autoSync == other.autoSync &&
          batchSync == other.batchSync &&
          maxBatchSize == other.maxBatchSize &&
          autoSyncThreshold == other.autoSyncThreshold &&
          autoSyncDelay == other.autoSyncDelay &&
          syncInterval == other.syncInterval &&
          httpTimeout == other.httpTimeout &&
          locationsOrderDirection == other.locationsOrderDirection &&
          disableAutoSyncOnCellular == other.disableAutoSyncOnCellular &&
          maxRetries == other.maxRetries &&
          retryBackoffBase == other.retryBackoffBase &&
          retryBackoffCap == other.retryBackoffCap &&
          enableDeltaCompression == other.enableDeltaCompression &&
          deltaCoordinatePrecision == other.deltaCoordinatePrecision &&
          syncTelematics == other.syncTelematics &&
          telematicsUrl == other.telematicsUrl &&
          _listEquals(sslPinningFingerprints, other.sslPinningFingerprints) &&
          _listEquals(sslPinningCertificates, other.sslPinningCertificates);

  @override
  int get hashCode => Object.hashAll([
    url,
    method,
    headers,
    params,
    extras,
    httpRootProperty,
    autoSync,
    batchSync,
    maxBatchSize,
    autoSyncThreshold,
    autoSyncDelay,
    syncInterval,
    httpTimeout,
    locationsOrderDirection,
    disableAutoSyncOnCellular,
    maxRetries,
    retryBackoffBase,
    retryBackoffCap,
    enableDeltaCompression,
    deltaCoordinatePrecision,
    syncTelematics,
    telematicsUrl,
    sslPinningFingerprints,
    sslPinningCertificates,
  ]);
}

// NOTE: Sub-configs like LoggerConfig, MotionConfig, etc. are omitted for brevity
// but would follow the same pattern (fromMap, toMap, and ideally toTlConfig if needed).
// For now, only the core configs are mapped to TlConfig in Pigeon.

@immutable
/// Configuration for the plugin's internal logger.
class LoggerConfig {
  /// Creates a new [LoggerConfig] with optional overrides.
  const LoggerConfig({
    this.logLevel = LogLevel.info,
    this.logMaxDays = 3,
    this.debug = false,
  });

  /// Creates a [LoggerConfig] from a map.
  factory LoggerConfig.fromMap(Map<String, Object?> map) {
    return LoggerConfig(
      logLevel:
          LogLevel.values[ensureInt(
            map['logLevel'],
            fallback: 2,
          ).clamp(0, LogLevel.values.length - 1)],
      logMaxDays: ensureInt(map['logMaxDays'], fallback: 3),
      debug: ensureBool(map['debug'], fallback: false),
    );
  }

  /// Creates a copy of this [LoggerConfig] with the given fields replaced with the new values.
  LoggerConfig copyWith({LogLevel? logLevel, int? logMaxDays, bool? debug}) {
    return LoggerConfig(
      logLevel: logLevel ?? this.logLevel,
      logMaxDays: logMaxDays ?? this.logMaxDays,
      debug: debug ?? this.debug,
    );
  }

  /// The minimum level of logs to capture and persist.
  /// Defaults to [LogLevel.info].
  final LogLevel logLevel;

  /// The maximum number of days to retain logs in the database.
  /// Defaults to `3`.
  final int logMaxDays;

  /// Enable debugging mode (which produces platform-specific tracking sounds
  /// and verbose local logging). Defaults to `false`.
  final bool debug;

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'logLevel': logLevel.index,
      'logMaxDays': logMaxDays,
      'debug': debug,
    };
  }

  /// Converts to Pigeon [TlLoggerConfig].
  TlLoggerConfig toTlConfig() => TlLoggerConfig(
    logLevel: TlLogLevel.values[logLevel.index],
    logMaxDays: logMaxDays,
    debug: debug,
  );

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

@immutable
/// Configuration for motion and activity detection.
class MotionConfig {
  /// Creates a new [MotionConfig] with optional overrides.
  const MotionConfig({
    this.stopTimeout = 5,
    this.motionTriggerDelay = 0,
    this.disableMotionActivityUpdates = false,
    this.isMoving = false,
    this.activityRecognitionInterval = 1000,
    this.minimumActivityRecognitionConfidence = 75,
    this.disableStopDetection = false,
    this.stopDetectionDelay = 0,
    this.stopOnStationary = false,
    this.activityTypes,
    this.stationaryRadius = 25.0,
    this.useSignificantChangesOnly = false,
    double? shakeThreshold,
    double? stillThreshold,
    int? stillSampleCount,
    this.motionDetectionMode = MotionDetectionMode.accelerometer,
    this.speedMovingThreshold = 1.5,
    this.speedStationaryDelay = 180,
    this.stationaryTrackingMode = StationaryTrackingMode.periodic,
    this.stationaryPeriodicInterval = 120,
    this.stationaryPeriodicAccuracy = DesiredAccuracy.high,
    this.speedWakeConfirmCount = 1,
  }) : shakeThreshold = shakeThreshold ?? 2.5,
       stillThreshold = stillThreshold ?? 0.4,
       stillSampleCount = stillSampleCount ?? 25,
       hasExplicitShakeThreshold = shakeThreshold != null,
       hasExplicitStillThreshold = stillThreshold != null,
       hasExplicitStillSampleCount = stillSampleCount != null,
       assert(speedStationaryDelay >= 0, 'speedStationaryDelay must be >= 0'),
       assert(speedWakeConfirmCount >= 1, 'speedWakeConfirmCount must be >= 1'),
       assert(speedMovingThreshold > 0, 'speedMovingThreshold must be > 0');

  /// Creates a [MotionConfig] from a map.
  factory MotionConfig.fromMap(Map<String, Object?> map) {
    // Parse activityTypes from the map if present.
    final rawActivityTypes = map['activityTypes'];
    List<LocationActivityType>? activityTypesList;
    if (rawActivityTypes is List) {
      activityTypesList = <LocationActivityType>[];
      for (final item in rawActivityTypes) {
        final index = item is int ? item : int.tryParse(item.toString());
        if (index != null &&
            index >= 0 &&
            index < LocationActivityType.values.length) {
          activityTypesList.add(LocationActivityType.values[index]);
        }
      }
      if (activityTypesList.isEmpty) activityTypesList = null;
    }
    return MotionConfig(
      stopTimeout: ensureInt(map['stopTimeout'], fallback: 5),
      motionTriggerDelay: ensureInt(map['motionTriggerDelay'], fallback: 0),
      disableMotionActivityUpdates: ensureBool(
        map['disableMotionActivityUpdates'],
        fallback: false,
      ),
      isMoving: ensureBool(map['isMoving'], fallback: false),
      activityRecognitionInterval: ensureInt(
        map['activityRecognitionInterval'],
        fallback: 1000,
      ),
      minimumActivityRecognitionConfidence: ensureInt(
        map['minimumActivityRecognitionConfidence'],
        fallback: 75,
      ),
      disableStopDetection: ensureBool(
        map['disableStopDetection'],
        fallback: false,
      ),
      stopDetectionDelay: ensureInt(map['stopDetectionDelay'], fallback: 0),
      stopOnStationary: ensureBool(map['stopOnStationary'], fallback: false),
      activityTypes: activityTypesList,
      stationaryRadius: ensureDouble(map['stationaryRadius'], fallback: 25),
      useSignificantChangesOnly: ensureBool(
        map['useSignificantChangesOnly'],
        fallback: false,
      ),
      // Absent means "never set", which must stay unset so the platform keeps
      // its own tuned default. Passing the Dart fallback here would silently
      // promote it to an explicit override on the next setConfig round-trip.
      shakeThreshold: map.containsKey('shakeThreshold')
          ? ensureDouble(map['shakeThreshold'], fallback: 2.5)
          : null,
      stillThreshold: map.containsKey('stillThreshold')
          ? ensureDouble(map['stillThreshold'], fallback: 0.4)
          : null,
      stillSampleCount: map.containsKey('stillSampleCount')
          ? ensureInt(map['stillSampleCount'], fallback: 25)
          : null,
      motionDetectionMode: _parseMotionDetectionMode(
        map['motionDetectionMode'],
      ),
      speedMovingThreshold: ensureDouble(
        map['speedMovingThreshold'],
        fallback: 1.5,
      ),
      speedStationaryDelay: ensureInt(
        map['speedStationaryDelay'],
        fallback: 180,
      ),
      stationaryTrackingMode: _parseStationaryTrackingMode(
        map['stationaryTrackingMode'],
      ),
      stationaryPeriodicInterval: ensureInt(
        map['stationaryPeriodicInterval'],
        fallback: 120,
      ),
      stationaryPeriodicAccuracy:
          DesiredAccuracy.values[ensureInt(
            map['stationaryPeriodicAccuracy'],
            fallback: DesiredAccuracy.high.index,
          ).clamp(0, DesiredAccuracy.values.length - 1)],
      speedWakeConfirmCount: ensureInt(
        map['speedWakeConfirmCount'],
        fallback: 1,
      ),
    );
  }

  /// The amount of time (in minutes) the device must be stationary before declaring the stationary state.
  /// Defaults to `5`.
  final int stopTimeout;

  /// The delay (in milliseconds) before starting tracking when motion is triggered.
  /// Defaults to `0`.
  final int motionTriggerDelay;

  /// Disable platform activity recognition and fall back to permission-free accelerometer-only motion detection.
  /// Defaults to `false`.
  final bool disableMotionActivityUpdates;

  /// The current state of motion (moving or stationary).
  /// Defaults to `false` (stationary).
  final bool isMoving;

  /// The interval (in milliseconds) for activity recognition updates.
  /// Defaults to `1000`.
  final int activityRecognitionInterval;

  /// The minimum confidence level (0–100) required to accept a detected activity.
  /// Defaults to `75`.
  final int minimumActivityRecognitionConfidence;

  /// Disable the automatic stationary state transition entirely.
  /// Defaults to `false`.
  final bool disableStopDetection;

  /// The extra delay (in seconds) to add after the stop timeout before stopping location updates.
  /// Defaults to `0`.
  final int stopDetectionDelay;

  /// Stop tracking entirely when a stationary state is declared.
  /// Defaults to `false`.
  final bool stopOnStationary;

  /// The list of specific [LocationActivityType]s that can trigger a transition from stationary to moving.
  /// Defaults to `null` (any moving activity).
  final List<LocationActivityType>? activityTypes;

  /// The radius (in meters) of the stationary geofence.
  /// Defaults to `25.0`.
  final double stationaryRadius;

  /// Whether significant motion changes only should be tracked (iOS only).
  /// Defaults to `false`.
  final bool useSignificantChangesOnly;

  /// The acceleration threshold (in m/s²) to trigger a transition from
  /// stationary to moving.
  ///
  /// Leave this unset to let each platform apply its own tuned default —
  /// `2.5 m/s²` on Android, `0.35 g` on iOS. The two are deliberately different:
  /// Android subtracts gravity from raw, noisier ~5 Hz samples, while iOS reads
  /// clean gravity-subtracted user-acceleration at 10 Hz. Reading this property
  /// reports `2.5` when unset, which is the Android default.
  ///
  /// Setting it sends the value to both platforms; iOS converts m/s² to g by
  /// dividing by 9.81, so `2.5` becomes `0.25 g` there — more sensitive than the
  /// iOS default. Prefer leaving it unset unless you have measured on both.
  final double shakeThreshold;

  /// Whether [shakeThreshold] was set explicitly. When `false` the value is not
  /// sent to the platform, so each platform keeps its own tuned default.
  final bool hasExplicitShakeThreshold;

  /// The acceleration threshold (in m/s²) below which a sample is counted as
  /// still.
  ///
  /// Leave this unset to let each platform apply its own tuned default —
  /// `0.4 m/s²` on Android, `0.15 g` on iOS. Setting it sends the value to both;
  /// iOS divides by 9.81, so `0.4` becomes `0.04 g`, roughly four times stricter
  /// than the iOS default. Reading this property reports `0.4` when unset.
  final double stillThreshold;

  /// Whether [stillThreshold] was set explicitly. When `false` the value is not
  /// sent to the platform, so each platform keeps its own tuned default.
  final bool hasExplicitStillThreshold;

  /// The number of consecutive still samples required to initiate the
  /// [stopTimeout].
  ///
  /// Leave this unset to let each platform target the same ~5 s dwell window
  /// with its own sampling rate — 25 samples at ~5 Hz on Android, 50 at 10 Hz on
  /// iOS. Setting it is taken as a literal sample count on both platforms, so
  /// the dwell duration then differs per platform. Reading this property reports
  /// `25` when unset.
  final int stillSampleCount;

  /// Whether [stillSampleCount] was set explicitly. When `false` the value is
  /// not sent to the platform, so each platform keeps its own tuned default.
  final bool hasExplicitStillSampleCount;

  /// Selects the motion detection strategy.
  ///
  /// - [MotionDetectionMode.accelerometer] (default): the legacy accelerometer-
  ///   driven stop detection. All of `shakeThreshold`, `stillThreshold`,
  ///   `stillSampleCount`, `stopTimeout`, and the Activity Recognition
  ///   settings apply to this mode.
  /// - [MotionDetectionMode.speed]: a GPS-speed-driven state machine. Use
  ///   this for vehicle-tracking scenarios where a phone on a dashboard
  ///   reads near-zero accelerometer values at highway speed. The state
  ///   machine switches the native location engine between continuous
  ///   tracking and low-power periodic fixes automatically. All `speed*`
  ///   and `stationary*` fields below apply to this mode.
  /// - [MotionDetectionMode.smart]: a hybrid mode that evaluates both the
  ///   accelerometer and the GPS speed. Prevents false stops on smooth
  ///   highways by cross-checking speed, and uses Geofences for zero-battery
  ///   monitoring when fully stationary.
  ///
  /// When `speed` is selected, the accelerometer and Activity Recognition
  /// detection paths are disabled entirely.
  final MotionDetectionMode motionDetectionMode;

  /// [Speed mode] Speed (m/s) below which a location fix counts as
  /// "not moving."
  ///
  /// `1.5 m/s` ≈ 5.4 km/h — filters GPS drift while still catching
  /// parking-lot crawl. Defaults to `1.5`.
  final double speedMovingThreshold;

  /// [Speed mode] Seconds of continuous low-speed fixes before the state
  /// machine declares stationary and switches to the
  /// [stationaryTrackingMode].
  ///
  /// Acts as a "red-light buffer" so stops at traffic lights don't trigger
  /// a mode switch. Defaults to `180` (3 minutes).
  final int speedStationaryDelay;

  /// [Speed mode] Tracking mode to enter when stationary.
  ///
  /// - [StationaryTrackingMode.periodic] (default): schedule one-shot
  ///   fixes at [stationaryPeriodicInterval] seconds. GPS radio is off
  ///   between fixes.
  /// - [StationaryTrackingMode.geofences]: stop continuous tracking and
  ///   rely on existing geofence monitoring. Wake speed is evaluated on
  ///   any geofence-triggered fix.
  final StationaryTrackingMode stationaryTrackingMode;

  /// [Speed mode] Interval (in seconds) between periodic fixes while
  /// stationary.
  ///
  /// Defaults to `120` (2 minutes). On Android, sub-15-minute intervals
  /// are driven by an in-process timer on the foreground location service
  /// — no `SCHEDULE_EXACT_ALARM` permission is required.
  final int stationaryPeriodicInterval;

  /// [Speed mode] Desired accuracy for periodic stationary fixes.
  ///
  /// Should be [DesiredAccuracy.high] so that the GPS speed value is
  /// reliable for wake detection. If set to a lower accuracy, consider
  /// raising [speedWakeConfirmCount] to filter phantom speed from
  /// WiFi/cell position jitter. Defaults to [DesiredAccuracy.high].
  final DesiredAccuracy stationaryPeriodicAccuracy;

  /// [Speed mode] Number of consecutive periodic fixes with
  /// `speed >= speedMovingThreshold` required before transitioning back
  /// to continuous tracking.
  ///
  /// `1` (default) gives instant wake and is safe when
  /// [stationaryPeriodicAccuracy] is [DesiredAccuracy.high] because true
  /// GPS speed is jitter-free. Increase to `3+` if you lower the
  /// stationary accuracy.
  final int speedWakeConfirmCount;

  /// Parses [MotionDetectionMode] from a String name or int index.
  static MotionDetectionMode _parseMotionDetectionMode(Object? raw) {
    if (raw is String) {
      return MotionDetectionMode.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => MotionDetectionMode.accelerometer,
      );
    }
    if (raw is int) {
      return MotionDetectionMode.values[raw.clamp(
        0,
        MotionDetectionMode.values.length - 1,
      )];
    }
    return MotionDetectionMode.accelerometer;
  }

  /// Parses [StationaryTrackingMode] from a String name or int index.
  static StationaryTrackingMode _parseStationaryTrackingMode(Object? raw) {
    if (raw is String) {
      return StationaryTrackingMode.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => StationaryTrackingMode.periodic,
      );
    }
    if (raw is int) {
      return StationaryTrackingMode.values[raw.clamp(
        0,
        StationaryTrackingMode.values.length - 1,
      )];
    }
    return StationaryTrackingMode.periodic;
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'stopTimeout': stopTimeout,
      'motionTriggerDelay': motionTriggerDelay,
      'disableMotionActivityUpdates': disableMotionActivityUpdates,
      'isMoving': isMoving,
      'activityRecognitionInterval': activityRecognitionInterval,
      'minimumActivityRecognitionConfidence':
          minimumActivityRecognitionConfidence,
      'disableStopDetection': disableStopDetection,
      'stopDetectionDelay': stopDetectionDelay,
      'stopOnStationary': stopOnStationary,
      if (activityTypes != null)
        'activityTypes': activityTypes!.map((e) => e.index).toList(),
      'stationaryRadius': stationaryRadius,
      'useSignificantChangesOnly': useSignificantChangesOnly,
      // Emitted only when set, so a round-trip through fromMap cannot turn a
      // platform default into an explicit override.
      if (hasExplicitShakeThreshold) 'shakeThreshold': shakeThreshold,
      if (hasExplicitStillThreshold) 'stillThreshold': stillThreshold,
      if (hasExplicitStillSampleCount) 'stillSampleCount': stillSampleCount,
      'motionDetectionMode': motionDetectionMode.index,
      'speedMovingThreshold': speedMovingThreshold,
      'speedStationaryDelay': speedStationaryDelay,
      'stationaryTrackingMode': stationaryTrackingMode.index,
      'stationaryPeriodicInterval': stationaryPeriodicInterval,
      'stationaryPeriodicAccuracy': stationaryPeriodicAccuracy.index,
      'speedWakeConfirmCount': speedWakeConfirmCount,
    };
  }

  /// Converts to Pigeon [TlMotionConfig].
  TlMotionConfig toTlConfig() => TlMotionConfig(
    stopTimeout: stopTimeout,
    motionTriggerDelay: motionTriggerDelay,
    disableMotionActivityUpdates: disableMotionActivityUpdates,
    isMoving: isMoving,
    activityRecognitionInterval: activityRecognitionInterval,
    minimumActivityRecognitionConfidence: minimumActivityRecognitionConfidence,
    disableStopDetection: disableStopDetection,
    stopDetectionDelay: stopDetectionDelay,
    stopOnStationary: stopOnStationary,
    stationaryRadius: stationaryRadius,
    useSignificantChangesOnly: useSignificantChangesOnly,
    // null tells the platform to keep its own tuned default.
    shakeThreshold: hasExplicitShakeThreshold ? shakeThreshold : null,
    stillThreshold: hasExplicitStillThreshold ? stillThreshold : null,
    stillSampleCount: hasExplicitStillSampleCount ? stillSampleCount : null,
    activityTypes: activityTypes
        ?.map((e) => TlLocationActivityType.values[e.index])
        .toList(),
    motionDetectionMode:
        TlMotionDetectionMode.values[motionDetectionMode.index],
    speedMovingThreshold: speedMovingThreshold,
    speedStationaryDelay: speedStationaryDelay,
    stationaryTrackingMode:
        TlStationaryTrackingMode.values[stationaryTrackingMode.index],
    stationaryPeriodicInterval: stationaryPeriodicInterval,
    stationaryPeriodicAccuracy:
        TlDesiredAccuracy.values[stationaryPeriodicAccuracy.index],
    speedWakeConfirmCount: speedWakeConfirmCount,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MotionConfig &&
          runtimeType == other.runtimeType &&
          stopTimeout == other.stopTimeout &&
          motionTriggerDelay == other.motionTriggerDelay &&
          disableMotionActivityUpdates == other.disableMotionActivityUpdates &&
          isMoving == other.isMoving &&
          activityRecognitionInterval == other.activityRecognitionInterval &&
          minimumActivityRecognitionConfidence ==
              other.minimumActivityRecognitionConfidence &&
          disableStopDetection == other.disableStopDetection &&
          stopDetectionDelay == other.stopDetectionDelay &&
          stopOnStationary == other.stopOnStationary &&
          activityTypes == other.activityTypes &&
          stationaryRadius == other.stationaryRadius &&
          useSignificantChangesOnly == other.useSignificantChangesOnly &&
          shakeThreshold == other.shakeThreshold &&
          hasExplicitShakeThreshold == other.hasExplicitShakeThreshold &&
          stillThreshold == other.stillThreshold &&
          hasExplicitStillThreshold == other.hasExplicitStillThreshold &&
          stillSampleCount == other.stillSampleCount &&
          hasExplicitStillSampleCount == other.hasExplicitStillSampleCount &&
          motionDetectionMode == other.motionDetectionMode &&
          speedMovingThreshold == other.speedMovingThreshold &&
          speedStationaryDelay == other.speedStationaryDelay &&
          stationaryTrackingMode == other.stationaryTrackingMode &&
          stationaryPeriodicInterval == other.stationaryPeriodicInterval &&
          stationaryPeriodicAccuracy == other.stationaryPeriodicAccuracy &&
          speedWakeConfirmCount == other.speedWakeConfirmCount;

  @override
  String toString() =>
      'MotionConfig(stopTimeout: $stopTimeout, '
      'disableMotionActivityUpdates: $disableMotionActivityUpdates, '
      'isMoving: $isMoving, '
      'motionDetectionMode: $motionDetectionMode)';

  @override
  int get hashCode => Object.hashAll([
    stopTimeout,
    motionTriggerDelay,
    disableMotionActivityUpdates,
    isMoving,
    activityRecognitionInterval,
    minimumActivityRecognitionConfidence,
    disableStopDetection,
    stopDetectionDelay,
    stopOnStationary,
    activityTypes,
    stationaryRadius,
    useSignificantChangesOnly,
    shakeThreshold,
    hasExplicitShakeThreshold,
    stillThreshold,
    hasExplicitStillThreshold,
    stillSampleCount,
    hasExplicitStillSampleCount,
    motionDetectionMode,
    speedMovingThreshold,
    speedStationaryDelay,
    stationaryTrackingMode,
    stationaryPeriodicInterval,
    stationaryPeriodicAccuracy,
    speedWakeConfirmCount,
  ]);
}

@immutable
/// Configuration for geofencing behavior.
class GeofenceConfig {
  /// Creates a new [GeofenceConfig] with optional overrides.
  const GeofenceConfig({
    this.geofenceInitialTriggerEntry = true,
    this.geofenceInitialTrigger = true,
    this.geofenceProximityRadius = 1000,
    this.geofenceModeHighAccuracy = false,
    this.geofenceExitAccuracyMax = -1,
  });

  /// Creates a [GeofenceConfig] from a map.
  factory GeofenceConfig.fromMap(Map<String, Object?> map) {
    return GeofenceConfig(
      geofenceInitialTriggerEntry: ensureBool(
        map['geofenceInitialTriggerEntry'],
        fallback: true,
      ),
      geofenceInitialTrigger: ensureBool(
        map['geofenceInitialTrigger'],
        fallback: true,
      ),
      geofenceProximityRadius: ensureInt(
        map['geofenceProximityRadius'],
        fallback: 1000,
      ),
      geofenceModeHighAccuracy: ensureBool(
        map['geofenceModeHighAccuracy'],
        fallback: false,
      ),
      geofenceExitAccuracyMax: ensureInt(
        map['geofenceExitAccuracyMax'],
        fallback: -1,
      ),
    );
  }

  /// Fire enter trigger immediately upon registration if device is already inside the geofence.
  /// Defaults to `true`.
  final bool geofenceInitialTriggerEntry;

  /// Enable initial trigger evaluation for geofences on registration.
  /// Defaults to `true`.
  final bool geofenceInitialTrigger;

  /// The radius (in meters) for proximity-based geofence loading.
  /// Only geofences within this distance are actively registered with the OS.
  /// Defaults to `1000`.
  final int geofenceProximityRadius;

  /// High-accuracy geofence mode.
  ///
  /// When `true`, geofence transitions are evaluated in-app from continuous GPS
  /// fixes instead of the OS geofencing service. This makes **tight radii
  /// (e.g. 5–50 m) and EXIT events reliable**, at the cost of higher battery use
  /// and — on iOS — the system "location in use" (blue) status-bar indicator
  /// (continuous GPS forces it; see issue #210).
  ///
  /// When `false` (default), geofencing uses the OS region-monitoring service:
  /// low power, no iOS indicator, but the OS enforces a practical minimum radius
  /// (~100 m) and small/EXIT transitions can be unreliable.
  ///
  /// Cross-platform (iOS + Android). This supersedes the deprecated
  /// [AndroidConfig.geofenceModeHighAccuracy]; if either is `true`, high-accuracy
  /// mode is enabled.
  final bool geofenceModeHighAccuracy;

  /// Tunes the accuracy-aware geofence EXIT gating (high-accuracy mode only).
  ///
  /// In high-accuracy mode a circular geofence only fires EXIT once the whole
  /// GPS error circle clears the fence — `distance - accuracy > radius + buffer`
  /// — so a single high-drift, low-confidence fix can't produce a false EXIT
  /// while a device sits still inside a small geofence (issue #274). The
  /// tradeoff is that a *genuine* departure is delayed by roughly the fix's
  /// horizontal accuracy, which matters most where GPS is chronically poor
  /// (deep indoors, urban canyons).
  ///
  /// This value (in meters) tunes that behavior:
  /// - `-1` (default): full gating — most resistant to drift-induced false
  ///   exits; genuine exits may lag by the current GPS uncertainty.
  /// - `0`: gating disabled — EXIT fires as soon as the reported point clears
  ///   `radius + buffer` (fastest, pre-#274 behavior; drift-prone).
  /// - `N > 0`: clamp — absorb drift up to `N` meters but never delay a genuine
  ///   EXIT by more than ~`N` meters. A good middle ground for small fences in
  ///   mixed GPS conditions (e.g. `20`).
  ///
  /// Has no effect in standard (OS region-monitoring) geofence mode, where the
  /// OS decides EXIT.
  final int geofenceExitAccuracyMax;

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'geofenceInitialTriggerEntry': geofenceInitialTriggerEntry,
      'geofenceInitialTrigger': geofenceInitialTrigger,
      'geofenceProximityRadius': geofenceProximityRadius,
      'geofenceModeHighAccuracy': geofenceModeHighAccuracy,
      'geofenceExitAccuracyMax': geofenceExitAccuracyMax,
    };
  }

  /// Converts to Pigeon [TlGeofenceConfig].
  TlGeofenceConfig toTlConfig() => TlGeofenceConfig(
    geofenceInitialTriggerEntry: geofenceInitialTriggerEntry,
    geofenceProximityRadius: geofenceProximityRadius,
    geofenceInitialTrigger: geofenceInitialTrigger,
    geofenceModeHighAccuracy: geofenceModeHighAccuracy,
    geofenceExitAccuracyMax: geofenceExitAccuracyMax,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeofenceConfig &&
          runtimeType == other.runtimeType &&
          geofenceInitialTriggerEntry == other.geofenceInitialTriggerEntry &&
          geofenceInitialTrigger == other.geofenceInitialTrigger &&
          geofenceProximityRadius == other.geofenceProximityRadius &&
          geofenceModeHighAccuracy == other.geofenceModeHighAccuracy &&
          geofenceExitAccuracyMax == other.geofenceExitAccuracyMax;

  @override
  int get hashCode => Object.hash(
    geofenceInitialTriggerEntry,
    geofenceInitialTrigger,
    geofenceProximityRadius,
    geofenceModeHighAccuracy,
    geofenceExitAccuracyMax,
  );
}

@immutable
/// Configuration for the local SQLite persistence layer.
class PersistenceConfig {
  /// Creates a new [PersistenceConfig] with optional overrides.
  const PersistenceConfig({
    this.maxDaysToPersist = 1,
    this.maxRecordsToPersist = -1,
    this.persistMode = PersistMode.all,
    this.disableProviderChangeRecord = false,
  });

  /// Creates a [PersistenceConfig] from a map.
  factory PersistenceConfig.fromMap(Map<String, Object?> map) {
    return PersistenceConfig(
      maxDaysToPersist: ensureInt(map['maxDaysToPersist'], fallback: 1),
      maxRecordsToPersist: ensureInt(map['maxRecordsToPersist'], fallback: -1),
      persistMode:
          PersistMode.values[ensureInt(
            map['persistMode'],
            fallback: 0,
          ).clamp(0, PersistMode.values.length - 1)],
      disableProviderChangeRecord: ensureBool(
        map['disableProviderChangeRecord'],
        fallback: false,
      ),
    );
  }

  /// The maximum number of days to retain tracked locations and geofence events in the database.
  /// Set to `-1` for unlimited retention. Defaults to `1`.
  final int maxDaysToPersist;

  /// The maximum number of location records to keep in the database.
  /// Set to `-1` for unlimited. Defaults to `-1`.
  final int maxRecordsToPersist;

  /// The tracking data persistence mode.
  /// Defaults to [PersistMode.all].
  final PersistMode persistMode;

  /// Skip writing a database record when location providers change (e.g. GPS disabled/enabled).
  /// Defaults to `false`.
  final bool disableProviderChangeRecord;

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'maxDaysToPersist': maxDaysToPersist,
      'maxRecordsToPersist': maxRecordsToPersist,
      'persistMode': persistMode.index,
      'disableProviderChangeRecord': disableProviderChangeRecord,
    };
  }

  /// Converts to Pigeon [TlPersistenceConfig].
  TlPersistenceConfig toTlConfig() => TlPersistenceConfig(
    persistMode: TlPersistMode.values[persistMode.index],
    maxDaysToPersist: maxDaysToPersist,
    maxRecordsToPersist: maxRecordsToPersist,
    disableProviderChangeRecord: disableProviderChangeRecord,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistenceConfig &&
          runtimeType == other.runtimeType &&
          maxDaysToPersist == other.maxDaysToPersist &&
          maxRecordsToPersist == other.maxRecordsToPersist &&
          persistMode == other.persistMode &&
          disableProviderChangeRecord == other.disableProviderChangeRecord;

  @override
  int get hashCode => Object.hash(
    maxDaysToPersist,
    maxRecordsToPersist,
    persistMode,
    disableProviderChangeRecord,
  );
}

bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (a == null) return b == null;
  if (b == null) return false;
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
