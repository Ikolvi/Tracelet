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

  /// Applies every field [other] explicitly supplied on top of this config,
  /// section by section, leaving fields [other] left unset as they are here.
  ///
  /// This mirrors what the platform does with the serialized payload, so
  /// `Tracelet.activeConfig` keeps reporting the values actually persisted
  /// natively after a partial `setConfig()` rather than the defaults the call
  /// left unset (#321).
  Config mergedWith(Config other) => Config(
    geo: geo.mergedWith(other.geo),
    app: app.mergedWith(other.app),
    android: android.mergedWith(other.android),
    ios: ios.mergedWith(other.ios),
    http: http.mergedWith(other.http),
    logger: logger.mergedWith(other.logger),
    motion: motion.mergedWith(other.motion),
    geofence: geofence.mergedWith(other.geofence),
    persistence: persistence.mergedWith(other.persistence),
    audit: audit.mergedWith(other.audit),
    privacyZone: privacyZone.mergedWith(other.privacyZone),
    security: security.mergedWith(other.security),
    attestation: attestation.mergedWith(other.attestation),
    telematics: telematics.mergedWith(other.telematics),
    classifier: classifier.mergedWith(other.classifier),
    impact: impact.mergedWith(other.impact),
  );

  /// Returns this config with every field in every section pinned to its
  /// effective value.
  ///
  /// [Tracelet.ready] sends this rather than the sparse form: it establishes a
  /// complete native baseline, so the platforms' own defaults never have to
  /// match Dart's for the omit-unset behaviour to be correct. `setConfig()`
  /// then sends only what the caller actually set (#321).
  Config resolved() => Config(
    geo: geo.resolved(),
    app: app.resolved(),
    android: android.resolved(),
    ios: ios.resolved(),
    http: http.resolved(),
    logger: logger.resolved(),
    motion: motion.resolved(),
    geofence: geofence.resolved(),
    persistence: persistence.resolved(),
    audit: audit.resolved(),
    privacyZone: privacyZone.resolved(),
    security: security.resolved(),
    attestation: attestation.resolved(),
    telematics: telematics.resolved(),
    classifier: classifier.resolved(),
    impact: impact.resolved(),
  );

  /// Serializes to a nested map suitable for platform channel transmission.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (geo != null) 'geo': geo.toMap(),
      if (app != null) 'app': app.toMap(),
      if (android != null) 'android': android.toMap(),
      if (ios != null) 'ios': ios.toMap(),
      if (http != null) 'http': http.toMap(),
      if (logger != null) 'logger': logger.toMap(),
      if (motion != null) 'motion': motion.toMap(),
      if (geofence != null) 'geofence': geofence.toMap(),
      if (persistence != null) 'persistence': persistence.toMap(),
      if (audit != null) 'audit': audit.toMap(),
      if (privacyZone != null) 'privacyZone': privacyZone.toMap(),
      if (security != null) 'security': security.toMap(),
      if (attestation != null) 'attestation': attestation.toMap(),
      if (telematics != null) 'telematics': telematics.toMap(),
      if (classifier != null) 'classifier': classifier.toMap(),
      if (impact != null) 'impact': impact.toMap(),
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
    int? trackingAccuracyThreshold,
    int? maxImpliedSpeed,
    int? odometerAccuracyThreshold,
    LocationFilterPolicy? policy,
    bool? rejectMockLocations,
    int? mockDetectionLevel,
    bool? useKalmanFilter,
  }) : _trackingAccuracyThreshold = trackingAccuracyThreshold,
       _maxImpliedSpeed = maxImpliedSpeed,
       _odometerAccuracyThreshold = odometerAccuracyThreshold,
       _policy = policy,
       _rejectMockLocations = rejectMockLocations,
       _mockDetectionLevel = mockDetectionLevel,
       _useKalmanFilter = useKalmanFilter;

  /// Creates a [LocationFilter] from a map.
  factory LocationFilter.fromMap(Map<String, Object?> map) {
    return LocationFilter(
      trackingAccuracyThreshold: map.containsKey('trackingAccuracyThreshold')
          ? ensureInt(map['trackingAccuracyThreshold'], fallback: 100)
          : null,
      maxImpliedSpeed: map.containsKey('maxImpliedSpeed')
          ? ensureInt(map['maxImpliedSpeed'], fallback: 80)
          : null,
      odometerAccuracyThreshold: map.containsKey('odometerAccuracyThreshold')
          ? ensureInt(map['odometerAccuracyThreshold'], fallback: 50)
          : null,
      policy: map.containsKey('policy')
          ? LocationFilterPolicy.values[ensureInt(
              map['policy'],
              fallback: 0,
            ).clamp(0, LocationFilterPolicy.values.length - 1)]
          : null,
      rejectMockLocations: map.containsKey('rejectMockLocations')
          ? ensureBool(map['rejectMockLocations'], fallback: false)
          : null,
      mockDetectionLevel: map.containsKey('mockDetectionLevel')
          ? ensureInt(map['mockDetectionLevel'], fallback: 1)
          : null,
      useKalmanFilter: map.containsKey('useKalmanFilter')
          ? ensureBool(map['useKalmanFilter'], fallback: false)
          : null,
    );
  }

  // Backing fields. `null` means "the caller did not provide this",
  // which keeps the field out of the wire payload (#321). The getters
  // below resolve each one to its documented default.
  final int? _trackingAccuracyThreshold;
  final int? _maxImpliedSpeed;
  final int? _odometerAccuracyThreshold;
  final LocationFilterPolicy? _policy;
  final bool? _rejectMockLocations;
  final int? _mockDetectionLevel;
  final bool? _useKalmanFilter;

  /// Reject locations with accuracy worse than this value (meters).
  int get trackingAccuracyThreshold => _trackingAccuracyThreshold ?? 100;

  /// Reject locations that imply a speed greater than this value (m/s).
  int get maxImpliedSpeed => _maxImpliedSpeed ?? 80;

  /// Only count locations with accuracy better than this value toward odometer.
  int get odometerAccuracyThreshold => _odometerAccuracyThreshold ?? 50;

  /// How to handle rejected locations.
  LocationFilterPolicy get policy => _policy ?? LocationFilterPolicy.adjust;

  /// Reject locations flagged as mock by the OS.
  bool get rejectMockLocations => _rejectMockLocations ?? false;

  /// Sensitivity level for custom mock detection.
  int get mockDetectionLevel => _mockDetectionLevel ?? 1;

  /// Whether the Kalman filter is currently enabled for GPS smoothing.
  bool get useKalmanFilter => _useKalmanFilter ?? false;

  /// Converts to Pigeon [TlLocationFilter].
  TlLocationFilter toTlConfig() => TlLocationFilter(
    trackingAccuracyThreshold: _trackingAccuracyThreshold,
    maxImpliedSpeed: _maxImpliedSpeed,
    odometerAccuracyThreshold: _odometerAccuracyThreshold,
    policy: _policy == null
        ? null
        : TlLocationFilterPolicy.values[_policy.index],
    rejectMockLocations: _rejectMockLocations,
    mockDetectionLevel: _mockDetectionLevel,
    useKalmanFilter: _useKalmanFilter,
  );

  /// Applies every field [other] explicitly supplied on top of this config,
  /// leaving fields [other] left unset as they are here.
  ///
  /// This mirrors what the platform does with the serialized payload, and
  /// keeps `Tracelet.activeConfig` in step with the values actually persisted
  /// natively after a partial `setConfig()` (#321).
  LocationFilter mergedWith(LocationFilter other) => LocationFilter(
    trackingAccuracyThreshold:
        other._trackingAccuracyThreshold ?? _trackingAccuracyThreshold,
    maxImpliedSpeed: other._maxImpliedSpeed ?? _maxImpliedSpeed,
    odometerAccuracyThreshold:
        other._odometerAccuracyThreshold ?? _odometerAccuracyThreshold,
    policy: other._policy ?? _policy,
    rejectMockLocations: other._rejectMockLocations ?? _rejectMockLocations,
    mockDetectionLevel: other._mockDetectionLevel ?? _mockDetectionLevel,
    useKalmanFilter: other._useKalmanFilter ?? _useKalmanFilter,
  );

  /// Returns this config with every field pinned to its effective value.
  ///
  /// Used by `ready()`, which establishes a complete native baseline rather
  /// than a partial update — so the platform's own defaults never have to
  /// match Dart's for correctness (#321).
  LocationFilter resolved() => LocationFilter(
    trackingAccuracyThreshold: trackingAccuracyThreshold,
    maxImpliedSpeed: maxImpliedSpeed,
    odometerAccuracyThreshold: odometerAccuracyThreshold,
    policy: policy,
    rejectMockLocations: rejectMockLocations,
    mockDetectionLevel: mockDetectionLevel,
    useKalmanFilter: useKalmanFilter,
  );

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (_trackingAccuracyThreshold != null)
        'trackingAccuracyThreshold': _trackingAccuracyThreshold,
      if (_maxImpliedSpeed != null) 'maxImpliedSpeed': _maxImpliedSpeed,
      if (_odometerAccuracyThreshold != null)
        'odometerAccuracyThreshold': _odometerAccuracyThreshold,
      if (_policy != null) 'policy': _policy.index,
      if (_rejectMockLocations != null)
        'rejectMockLocations': _rejectMockLocations,
      if (_mockDetectionLevel != null)
        'mockDetectionLevel': _mockDetectionLevel,
      if (_useKalmanFilter != null) 'useKalmanFilter': _useKalmanFilter,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocationFilter &&
          runtimeType == other.runtimeType &&
          _trackingAccuracyThreshold == other._trackingAccuracyThreshold &&
          _maxImpliedSpeed == other._maxImpliedSpeed &&
          _odometerAccuracyThreshold == other._odometerAccuracyThreshold &&
          _policy == other._policy &&
          _rejectMockLocations == other._rejectMockLocations &&
          _mockDetectionLevel == other._mockDetectionLevel &&
          _useKalmanFilter == other._useKalmanFilter;

  @override
  int get hashCode => Object.hash(
    _trackingAccuracyThreshold,
    _maxImpliedSpeed,
    _odometerAccuracyThreshold,
    _policy,
    _rejectMockLocations,
    _mockDetectionLevel,
    _useKalmanFilter,
  );
}

/// Shared location accuracy and sampling settings.
@immutable
class GeoConfig {
  /// Creates a new [GeoConfig] with optional overrides.
  const GeoConfig({
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
  }) : _desiredAccuracy = desiredAccuracy,
       _distanceFilter = distanceFilter,
       _stationaryRadius = stationaryRadius,
       _locationTimeout = locationTimeout,
       _disableElasticity = disableElasticity,
       _elasticityMultiplier = elasticityMultiplier,
       _stopAfterElapsedMinutes = stopAfterElapsedMinutes,
       _maxMonitoredGeofences = maxMonitoredGeofences,
       _enableTimestampMeta = enableTimestampMeta,
       _enableAdaptiveMode = enableAdaptiveMode,
       _periodicLocationInterval = periodicLocationInterval,
       _periodicDesiredAccuracy = periodicDesiredAccuracy,
       _enableSparseUpdates = enableSparseUpdates,
       _sparseDistanceThreshold = sparseDistanceThreshold,
       _sparseMaxIdleSeconds = sparseMaxIdleSeconds,
       _batteryBudgetPerHour = batteryBudgetPerHour,
       _enableDeadReckoning = enableDeadReckoning,
       _deadReckoningActivationDelay = deadReckoningActivationDelay,
       _deadReckoningMaxDuration = deadReckoningMaxDuration,
       _filter = filter,
       _resolveAddress = resolveAddress;

  /// Creates a [GeoConfig] from a map.
  factory GeoConfig.fromMap(Map<String, Object?> map) {
    return GeoConfig(
      desiredAccuracy: map.containsKey('desiredAccuracy')
          ? DesiredAccuracy.values[ensureInt(
              map['desiredAccuracy'],
              fallback: 0,
            ).clamp(0, DesiredAccuracy.values.length - 1)]
          : null,
      distanceFilter: map.containsKey('distanceFilter')
          ? ensureDouble(map['distanceFilter'], fallback: 10)
          : null,
      stationaryRadius: map.containsKey('stationaryRadius')
          ? ensureDouble(map['stationaryRadius'], fallback: 25)
          : null,
      locationTimeout: map.containsKey('locationTimeout')
          ? ensureInt(map['locationTimeout'], fallback: 60)
          : null,
      disableElasticity: map.containsKey('disableElasticity')
          ? ensureBool(map['disableElasticity'], fallback: false)
          : null,
      elasticityMultiplier: map.containsKey('elasticityMultiplier')
          ? ensureDouble(map['elasticityMultiplier'], fallback: 1)
          : null,
      stopAfterElapsedMinutes: map.containsKey('stopAfterElapsedMinutes')
          ? ensureInt(map['stopAfterElapsedMinutes'], fallback: -1)
          : null,
      maxMonitoredGeofences: map.containsKey('maxMonitoredGeofences')
          ? ensureInt(map['maxMonitoredGeofences'], fallback: -1)
          : null,
      enableTimestampMeta: map.containsKey('enableTimestampMeta')
          ? ensureBool(map['enableTimestampMeta'], fallback: false)
          : null,
      enableAdaptiveMode: map.containsKey('enableAdaptiveMode')
          ? ensureBool(map['enableAdaptiveMode'], fallback: false)
          : null,
      periodicLocationInterval: map.containsKey('periodicLocationInterval')
          ? ensureInt(map['periodicLocationInterval'], fallback: 900)
          : null,
      periodicDesiredAccuracy: map.containsKey('periodicDesiredAccuracy')
          ? DesiredAccuracy.values[ensureInt(
              map['periodicDesiredAccuracy'],
              fallback: 1, // medium
            ).clamp(0, DesiredAccuracy.values.length - 1)]
          : null,
      enableSparseUpdates: map.containsKey('enableSparseUpdates')
          ? ensureBool(map['enableSparseUpdates'], fallback: false)
          : null,
      sparseDistanceThreshold: map.containsKey('sparseDistanceThreshold')
          ? ensureDouble(map['sparseDistanceThreshold'], fallback: 50)
          : null,
      sparseMaxIdleSeconds: map.containsKey('sparseMaxIdleSeconds')
          ? ensureInt(map['sparseMaxIdleSeconds'], fallback: 300)
          : null,
      batteryBudgetPerHour: map.containsKey('batteryBudgetPerHour')
          ? ensureDouble(map['batteryBudgetPerHour'], fallback: 0)
          : null,
      enableDeadReckoning: map.containsKey('enableDeadReckoning')
          ? ensureBool(map['enableDeadReckoning'], fallback: false)
          : null,
      deadReckoningActivationDelay:
          map.containsKey('deadReckoningActivationDelay')
          ? ensureInt(map['deadReckoningActivationDelay'], fallback: 0)
          : null,
      deadReckoningMaxDuration: map.containsKey('deadReckoningMaxDuration')
          ? ensureInt(map['deadReckoningMaxDuration'], fallback: 0)
          : null,
      filter: map.containsKey('filter')
          ? LocationFilter.fromMap(safeMap(map['filter']) ?? map)
          : null,
      resolveAddress: map.containsKey('resolveAddress')
          ? ensureBool(map['resolveAddress'], fallback: false)
          : null,
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
      desiredAccuracy: desiredAccuracy ?? _desiredAccuracy,
      distanceFilter: distanceFilter ?? _distanceFilter,
      stationaryRadius: stationaryRadius ?? _stationaryRadius,
      locationTimeout: locationTimeout ?? _locationTimeout,
      disableElasticity: disableElasticity ?? _disableElasticity,
      elasticityMultiplier: elasticityMultiplier ?? _elasticityMultiplier,
      stopAfterElapsedMinutes:
          stopAfterElapsedMinutes ?? this.stopAfterElapsedMinutes,
      maxMonitoredGeofences:
          maxMonitoredGeofences ?? this.maxMonitoredGeofences,
      enableTimestampMeta: enableTimestampMeta ?? _enableTimestampMeta,
      enableAdaptiveMode: enableAdaptiveMode ?? _enableAdaptiveMode,
      periodicLocationInterval:
          periodicLocationInterval ?? this.periodicLocationInterval,
      periodicDesiredAccuracy:
          periodicDesiredAccuracy ?? this.periodicDesiredAccuracy,
      enableSparseUpdates: enableSparseUpdates ?? _enableSparseUpdates,
      sparseDistanceThreshold:
          sparseDistanceThreshold ?? this.sparseDistanceThreshold,
      sparseMaxIdleSeconds: sparseMaxIdleSeconds ?? _sparseMaxIdleSeconds,
      batteryBudgetPerHour: batteryBudgetPerHour ?? _batteryBudgetPerHour,
      enableDeadReckoning: enableDeadReckoning ?? _enableDeadReckoning,
      deadReckoningActivationDelay:
          deadReckoningActivationDelay ?? this.deadReckoningActivationDelay,
      deadReckoningMaxDuration:
          deadReckoningMaxDuration ?? this.deadReckoningMaxDuration,
      filter: filter ?? _filter,
      resolveAddress: resolveAddress ?? _resolveAddress,
    );
  }

  // Backing fields. `null` means "the caller did not provide this",
  // which keeps the field out of the wire payload (#321). The getters
  // below resolve each one to its documented default.
  final DesiredAccuracy? _desiredAccuracy;
  final double? _distanceFilter;
  final double? _stationaryRadius;
  final int? _locationTimeout;
  final bool? _disableElasticity;
  final double? _elasticityMultiplier;
  final int? _stopAfterElapsedMinutes;
  final int? _maxMonitoredGeofences;
  final bool? _enableTimestampMeta;
  final bool? _enableAdaptiveMode;
  final int? _periodicLocationInterval;
  final DesiredAccuracy? _periodicDesiredAccuracy;
  final bool? _enableSparseUpdates;
  final double? _sparseDistanceThreshold;
  final int? _sparseMaxIdleSeconds;
  final double? _batteryBudgetPerHour;
  final bool? _enableDeadReckoning;
  final int? _deadReckoningActivationDelay;
  final int? _deadReckoningMaxDuration;
  final LocationFilter? _filter;
  final bool? _resolveAddress;

  /// The desired location accuracy.
  /// Defaults to [DesiredAccuracy.high].
  DesiredAccuracy get desiredAccuracy =>
      _desiredAccuracy ?? DesiredAccuracy.high;

  /// The minimum distance (in meters) the device must move horizontally before
  /// a new location update is recorded. Defaults to `10.0`.
  double get distanceFilter => _distanceFilter ?? 10.0;

  /// The radius (in meters) around the stationary location where the device
  /// is considered stationary. Defaults to `25.0`.
  double get stationaryRadius => _stationaryRadius ?? 25.0;

  /// The timeout (in seconds) for a location request before giving up.
  /// Defaults to `60`.
  int get locationTimeout => _locationTimeout ?? 60;

  /// Disable speed-based distance filter elasticity.
  /// Defaults to `false`.
  bool get disableElasticity => _disableElasticity ?? false;

  /// Scale factor for the speed-based elastic distance filter.
  /// Defaults to `1.0`.
  double get elasticityMultiplier => _elasticityMultiplier ?? 1.0;

  /// Auto-stop tracking after this many minutes have elapsed since start.
  /// `-1` means disabled. Defaults to `-1`.
  int get stopAfterElapsedMinutes => _stopAfterElapsedMinutes ?? -1;

  /// Maximum simultaneously monitored geofences.
  /// `-1` to fall back to platform defaults (100 on Android, 20 on iOS).
  /// Defaults to `-1`.
  int get maxMonitoredGeofences => _maxMonitoredGeofences ?? -1;

  /// Enable adding extra timestamp metadata to each location payload.
  /// Defaults to `false`.
  bool get enableTimestampMeta => _enableTimestampMeta ?? false;

  /// Enable adaptive sampling mode which automatically scales [distanceFilter]
  /// based on detected activity, speed, and battery levels.
  /// Defaults to `false`.
  bool get enableAdaptiveMode => _enableAdaptiveMode ?? false;

  /// The interval (in seconds) between locations in periodic mode.
  /// Minimum is 60s. Defaults to `900`.
  int get periodicLocationInterval => _periodicLocationInterval ?? 900;

  /// The desired GPS accuracy level for each periodic update.
  /// Defaults to [DesiredAccuracy.medium].
  DesiredAccuracy get periodicDesiredAccuracy =>
      _periodicDesiredAccuracy ?? DesiredAccuracy.medium;

  /// Enable sparse updates to deduplicate location recording at the database layer.
  /// Drops locations within [sparseDistanceThreshold] of the last recorded position.
  /// Defaults to `false`.
  bool get enableSparseUpdates => _enableSparseUpdates ?? false;

  /// Minimum horizontal distance (in meters) between locations in sparse mode.
  /// Defaults to `50.0`.
  double get sparseDistanceThreshold => _sparseDistanceThreshold ?? 50.0;

  /// Force a recorded location update after this many seconds of idle time
  /// even if the device hasn't moved beyond [sparseDistanceThreshold].
  /// Defaults to `300`.
  int get sparseMaxIdleSeconds => _sparseMaxIdleSeconds ?? 300;

  /// Target maximum battery drain per hour (%).
  /// `0.0` disables battery budget-based parameter scaling.
  /// Defaults to `0.0`.
  double get batteryBudgetPerHour => _batteryBudgetPerHour ?? 0.0;

  /// Enable dead reckoning inertial sensor fusion for GPS-denied environments.
  /// Defaults to `false`.
  bool get enableDeadReckoning => _enableDeadReckoning ?? false;

  /// Seconds without GPS signal before starting dead reckoning estimation.
  /// Defaults to `0`.
  int get deadReckoningActivationDelay => _deadReckoningActivationDelay ?? 0;

  /// Maximum seconds to run dead reckoning positioning.
  /// Defaults to `0` (unlimited).
  int get deadReckoningMaxDuration => _deadReckoningMaxDuration ?? 0;

  /// The GPS filtering and smoothing configuration.
  /// Defaults to [LocationFilter].
  LocationFilter get filter => _filter ?? const LocationFilter();

  /// Automatically resolve coordinates to a street address using the native OS Geocoder.
  /// Defaults to `false` to save network and battery.
  bool get resolveAddress => _resolveAddress ?? false;

  /// Converts to Pigeon [TlGeoConfig].
  TlGeoConfig toTlConfig() => TlGeoConfig(
    desiredAccuracy: _desiredAccuracy == null
        ? null
        : TlDesiredAccuracy.values[_desiredAccuracy.index],
    distanceFilter: _distanceFilter,
    stationaryRadius: _stationaryRadius,
    locationTimeout: _locationTimeout,
    disableElasticity: _disableElasticity,
    elasticityMultiplier: _elasticityMultiplier,
    stopAfterElapsedMinutes: _stopAfterElapsedMinutes,
    maxMonitoredGeofences: _maxMonitoredGeofences,
    enableTimestampMeta: _enableTimestampMeta,
    enableAdaptiveMode: _enableAdaptiveMode,
    periodicLocationInterval: _periodicLocationInterval,
    periodicDesiredAccuracy: _periodicDesiredAccuracy == null
        ? null
        : TlDesiredAccuracy.values[_periodicDesiredAccuracy.index],
    enableSparseUpdates: _enableSparseUpdates,
    sparseDistanceThreshold: _sparseDistanceThreshold,
    sparseMaxIdleSeconds: _sparseMaxIdleSeconds,
    batteryBudgetPerHour: _batteryBudgetPerHour,
    enableDeadReckoning: _enableDeadReckoning,
    deadReckoningActivationDelay: _deadReckoningActivationDelay,
    deadReckoningMaxDuration: _deadReckoningMaxDuration,
    filter: _filter?.toTlConfig(),
    resolveAddress: _resolveAddress,
  );

  /// Applies every field [other] explicitly supplied on top of this config,
  /// leaving fields [other] left unset as they are here.
  ///
  /// This mirrors what the platform does with the serialized payload, and
  /// keeps `Tracelet.activeConfig` in step with the values actually persisted
  /// natively after a partial `setConfig()` (#321).
  GeoConfig mergedWith(GeoConfig other) => GeoConfig(
    desiredAccuracy: other._desiredAccuracy ?? _desiredAccuracy,
    distanceFilter: other._distanceFilter ?? _distanceFilter,
    stationaryRadius: other._stationaryRadius ?? _stationaryRadius,
    locationTimeout: other._locationTimeout ?? _locationTimeout,
    disableElasticity: other._disableElasticity ?? _disableElasticity,
    elasticityMultiplier: other._elasticityMultiplier ?? _elasticityMultiplier,
    stopAfterElapsedMinutes:
        other._stopAfterElapsedMinutes ?? _stopAfterElapsedMinutes,
    maxMonitoredGeofences:
        other._maxMonitoredGeofences ?? _maxMonitoredGeofences,
    enableTimestampMeta: other._enableTimestampMeta ?? _enableTimestampMeta,
    enableAdaptiveMode: other._enableAdaptiveMode ?? _enableAdaptiveMode,
    periodicLocationInterval:
        other._periodicLocationInterval ?? _periodicLocationInterval,
    periodicDesiredAccuracy:
        other._periodicDesiredAccuracy ?? _periodicDesiredAccuracy,
    enableSparseUpdates: other._enableSparseUpdates ?? _enableSparseUpdates,
    sparseDistanceThreshold:
        other._sparseDistanceThreshold ?? _sparseDistanceThreshold,
    sparseMaxIdleSeconds: other._sparseMaxIdleSeconds ?? _sparseMaxIdleSeconds,
    batteryBudgetPerHour: other._batteryBudgetPerHour ?? _batteryBudgetPerHour,
    enableDeadReckoning: other._enableDeadReckoning ?? _enableDeadReckoning,
    deadReckoningActivationDelay:
        other._deadReckoningActivationDelay ?? _deadReckoningActivationDelay,
    deadReckoningMaxDuration:
        other._deadReckoningMaxDuration ?? _deadReckoningMaxDuration,
    filter: _filter == null
        ? other._filter
        : (other._filter == null ? _filter : _filter.mergedWith(other._filter)),
    resolveAddress: other._resolveAddress ?? _resolveAddress,
  );

  /// Returns this config with every field pinned to its effective value.
  ///
  /// Used by `ready()`, which establishes a complete native baseline rather
  /// than a partial update — so the platform's own defaults never have to
  /// match Dart's for correctness (#321).
  GeoConfig resolved() => GeoConfig(
    desiredAccuracy: desiredAccuracy,
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
    periodicDesiredAccuracy: periodicDesiredAccuracy,
    enableSparseUpdates: enableSparseUpdates,
    sparseDistanceThreshold: sparseDistanceThreshold,
    sparseMaxIdleSeconds: sparseMaxIdleSeconds,
    batteryBudgetPerHour: batteryBudgetPerHour,
    enableDeadReckoning: enableDeadReckoning,
    deadReckoningActivationDelay: deadReckoningActivationDelay,
    deadReckoningMaxDuration: deadReckoningMaxDuration,
    filter: (_filter ?? const LocationFilter()).resolved(),
    resolveAddress: resolveAddress,
  );

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    // A nested sub-config is emitted only when it carries something.
    // `filter`/`foregroundService` resolve to a non-null object even when
    // unset, so guarding on the object was dead code and every payload
    // carried an empty `{}`. That contributes nothing to the platform
    // merge, but it makes a partial update that changes nothing look like
    // it touched the section, and it is not a minimal payload (#321).
    final filterMap = filter.toMap();
    return <String, Object?>{
      if (_desiredAccuracy != null) 'desiredAccuracy': _desiredAccuracy.index,
      if (_distanceFilter != null) 'distanceFilter': _distanceFilter,
      if (_stationaryRadius != null) 'stationaryRadius': _stationaryRadius,
      if (_locationTimeout != null) 'locationTimeout': _locationTimeout,
      if (_disableElasticity != null) 'disableElasticity': _disableElasticity,
      if (_elasticityMultiplier != null)
        'elasticityMultiplier': _elasticityMultiplier,
      if (_stopAfterElapsedMinutes != null)
        'stopAfterElapsedMinutes': _stopAfterElapsedMinutes,
      if (_maxMonitoredGeofences != null)
        'maxMonitoredGeofences': _maxMonitoredGeofences,
      if (_enableTimestampMeta != null)
        'enableTimestampMeta': _enableTimestampMeta,
      if (_enableAdaptiveMode != null)
        'enableAdaptiveMode': _enableAdaptiveMode,
      if (_periodicLocationInterval != null)
        'periodicLocationInterval': _periodicLocationInterval,
      if (_periodicDesiredAccuracy != null)
        'periodicDesiredAccuracy': _periodicDesiredAccuracy.index,
      if (_enableSparseUpdates != null)
        'enableSparseUpdates': _enableSparseUpdates,
      if (_sparseDistanceThreshold != null)
        'sparseDistanceThreshold': _sparseDistanceThreshold,
      if (_sparseMaxIdleSeconds != null)
        'sparseMaxIdleSeconds': _sparseMaxIdleSeconds,
      if (_batteryBudgetPerHour != null)
        'batteryBudgetPerHour': _batteryBudgetPerHour,
      if (_enableDeadReckoning != null)
        'enableDeadReckoning': _enableDeadReckoning,
      if (_deadReckoningActivationDelay != null)
        'deadReckoningActivationDelay': _deadReckoningActivationDelay,
      if (_deadReckoningMaxDuration != null)
        'deadReckoningMaxDuration': _deadReckoningMaxDuration,
      if (filterMap.isNotEmpty) 'filter': filterMap,
      if (_resolveAddress != null) 'resolveAddress': _resolveAddress,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeoConfig &&
          runtimeType == other.runtimeType &&
          _desiredAccuracy == other._desiredAccuracy &&
          _distanceFilter == other._distanceFilter &&
          _stationaryRadius == other._stationaryRadius &&
          _locationTimeout == other._locationTimeout &&
          _disableElasticity == other._disableElasticity &&
          _elasticityMultiplier == other._elasticityMultiplier &&
          _stopAfterElapsedMinutes == other._stopAfterElapsedMinutes &&
          _maxMonitoredGeofences == other._maxMonitoredGeofences &&
          _enableTimestampMeta == other._enableTimestampMeta &&
          _enableAdaptiveMode == other._enableAdaptiveMode &&
          _periodicLocationInterval == other._periodicLocationInterval &&
          _periodicDesiredAccuracy == other._periodicDesiredAccuracy &&
          _enableSparseUpdates == other._enableSparseUpdates &&
          _sparseDistanceThreshold == other._sparseDistanceThreshold &&
          _sparseMaxIdleSeconds == other._sparseMaxIdleSeconds &&
          _batteryBudgetPerHour == other._batteryBudgetPerHour &&
          _enableDeadReckoning == other._enableDeadReckoning &&
          _deadReckoningActivationDelay ==
              other._deadReckoningActivationDelay &&
          _deadReckoningMaxDuration == other._deadReckoningMaxDuration &&
          _filter == other._filter &&
          _resolveAddress == other._resolveAddress;

  @override
  int get hashCode => Object.hashAll([
    _desiredAccuracy,
    _distanceFilter,
    _stationaryRadius,
    _locationTimeout,
    _disableElasticity,
    _elasticityMultiplier,
    _stopAfterElapsedMinutes,
    _maxMonitoredGeofences,
    _enableTimestampMeta,
    _enableAdaptiveMode,
    _periodicLocationInterval,
    _periodicDesiredAccuracy,
    _enableSparseUpdates,
    _sparseDistanceThreshold,
    _sparseMaxIdleSeconds,
    _batteryBudgetPerHour,
    _enableDeadReckoning,
    _deadReckoningActivationDelay,
    _deadReckoningMaxDuration,
    _filter,
    _resolveAddress,
  ]);
}

/// Shared application lifecycle and scheduling settings.
@immutable
class AppConfig {
  /// Creates a new [AppConfig] with optional overrides.
  const AppConfig({
    bool? stopOnTerminate,
    bool? startOnBoot,
    int? heartbeatInterval,
    List<String>? schedule,
    this.remoteConfigUrl,
    this.remoteConfigHeaders,
    int? remoteConfigTimeout,
    int? remoteConfigRefreshInterval,
  }) : _stopOnTerminate = stopOnTerminate,
       _startOnBoot = startOnBoot,
       _heartbeatInterval = heartbeatInterval,
       _schedule = schedule,
       _remoteConfigTimeout = remoteConfigTimeout,
       _remoteConfigRefreshInterval = remoteConfigRefreshInterval;

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
      stopOnTerminate: map.containsKey('stopOnTerminate')
          ? ensureBool(map['stopOnTerminate'], fallback: true)
          : null,
      startOnBoot: map.containsKey('startOnBoot')
          ? ensureBool(map['startOnBoot'], fallback: false)
          : null,
      heartbeatInterval: map.containsKey('heartbeatInterval')
          ? ensureInt(map['heartbeatInterval'], fallback: 60)
          : null,
      schedule: rawSchedule is List ? scheduleList : null,
      remoteConfigUrl: map['remoteConfigUrl'] as String?,
      remoteConfigHeaders: (map['remoteConfigHeaders'] as Map?)
          ?.cast<String, String>(),
      remoteConfigTimeout: map.containsKey('remoteConfigTimeout')
          ? ensureInt(map['remoteConfigTimeout'], fallback: 60000)
          : null,
      remoteConfigRefreshInterval:
          map.containsKey('remoteConfigRefreshInterval')
          ? ensureInt(map['remoteConfigRefreshInterval'], fallback: 1440)
          : null,
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
      stopOnTerminate: stopOnTerminate ?? _stopOnTerminate,
      startOnBoot: startOnBoot ?? _startOnBoot,
      heartbeatInterval: heartbeatInterval ?? _heartbeatInterval,
      schedule: schedule ?? _schedule,
      remoteConfigUrl: remoteConfigUrl ?? this.remoteConfigUrl,
      remoteConfigHeaders: remoteConfigHeaders ?? this.remoteConfigHeaders,
      remoteConfigTimeout: remoteConfigTimeout ?? _remoteConfigTimeout,
      remoteConfigRefreshInterval:
          remoteConfigRefreshInterval ?? this.remoteConfigRefreshInterval,
    );
  }

  // Backing fields. `null` means "the caller did not provide this",
  // which keeps the field out of the wire payload (#321). The getters
  // below resolve each one to its documented default.
  final bool? _stopOnTerminate;
  final bool? _startOnBoot;
  final int? _heartbeatInterval;
  final List<String>? _schedule;
  final int? _remoteConfigTimeout;
  final int? _remoteConfigRefreshInterval;

  /// Whether to stop location tracking when the application is terminated/killed by the user or OS.
  /// Defaults to `true`.
  bool get stopOnTerminate => _stopOnTerminate ?? true;

  /// Whether to automatically start/resume location tracking after the device reboots.
  /// Defaults to `false`.
  bool get startOnBoot => _startOnBoot ?? false;

  /// The interval (in seconds) between heartbeat events.
  /// Set to `-1` to disable heartbeat monitoring. Defaults to `60`.
  int get heartbeatInterval => _heartbeatInterval ?? 60;

  /// A list of cron-like schedule strings representing active tracking windows.
  /// Defaults to empty list (no schedule constraint).
  List<String> get schedule => _schedule ?? const <String>[];

  /// URL of the remote configuration server to fetch settings dynamically at runtime.
  /// Defaults to `null`.
  final String? remoteConfigUrl;

  /// Custom HTTP headers to include with the remote configuration fetch request.
  /// Defaults to `null`.
  final Map<String, String>? remoteConfigHeaders;

  /// Timeout in milliseconds for fetching the remote configuration.
  /// Defaults to `60000` (60 seconds).
  int get remoteConfigTimeout => _remoteConfigTimeout ?? 60000;

  /// How often to refresh/fetch the remote configuration (in minutes).
  /// Defaults to `1440` (24 hours).
  int get remoteConfigRefreshInterval => _remoteConfigRefreshInterval ?? 1440;

  /// Converts to Pigeon [TlAppConfig].
  TlAppConfig toTlConfig() => TlAppConfig(
    stopOnTerminate: _stopOnTerminate,
    startOnBoot: _startOnBoot,
    heartbeatInterval: _heartbeatInterval,
    schedule: _schedule,
    remoteConfigUrl: remoteConfigUrl,
    remoteConfigHeaders: remoteConfigHeaders,
    remoteConfigTimeout: _remoteConfigTimeout,
    remoteConfigRefreshInterval: _remoteConfigRefreshInterval,
  );

  /// Applies every field [other] explicitly supplied on top of this config,
  /// leaving fields [other] left unset as they are here.
  ///
  /// This mirrors what the platform does with the serialized payload, and
  /// keeps `Tracelet.activeConfig` in step with the values actually persisted
  /// natively after a partial `setConfig()` (#321).
  AppConfig mergedWith(AppConfig other) => AppConfig(
    stopOnTerminate: other._stopOnTerminate ?? _stopOnTerminate,
    startOnBoot: other._startOnBoot ?? _startOnBoot,
    heartbeatInterval: other._heartbeatInterval ?? _heartbeatInterval,
    schedule: other._schedule ?? _schedule,
    remoteConfigUrl: other.remoteConfigUrl ?? remoteConfigUrl,
    remoteConfigHeaders: other.remoteConfigHeaders ?? remoteConfigHeaders,
    remoteConfigTimeout: other._remoteConfigTimeout ?? _remoteConfigTimeout,
    remoteConfigRefreshInterval:
        other._remoteConfigRefreshInterval ?? _remoteConfigRefreshInterval,
  );

  /// Returns this config with every field pinned to its effective value.
  ///
  /// Used by `ready()`, which establishes a complete native baseline rather
  /// than a partial update — so the platform's own defaults never have to
  /// match Dart's for correctness (#321).
  AppConfig resolved() => AppConfig(
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
      if (_stopOnTerminate != null) 'stopOnTerminate': _stopOnTerminate,
      if (_startOnBoot != null) 'startOnBoot': _startOnBoot,
      if (_heartbeatInterval != null) 'heartbeatInterval': _heartbeatInterval,
      if (_schedule != null) 'schedule': _schedule,
      if (remoteConfigUrl != null) 'remoteConfigUrl': remoteConfigUrl,
      if (remoteConfigHeaders != null)
        'remoteConfigHeaders': remoteConfigHeaders,
      if (_remoteConfigTimeout != null)
        'remoteConfigTimeout': _remoteConfigTimeout,
      if (_remoteConfigRefreshInterval != null)
        'remoteConfigRefreshInterval': _remoteConfigRefreshInterval,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppConfig &&
          runtimeType == other.runtimeType &&
          _stopOnTerminate == other._stopOnTerminate &&
          _startOnBoot == other._startOnBoot &&
          _heartbeatInterval == other._heartbeatInterval &&
          _schedule == other._schedule &&
          remoteConfigUrl == other.remoteConfigUrl &&
          remoteConfigHeaders == other.remoteConfigHeaders &&
          _remoteConfigTimeout == other._remoteConfigTimeout &&
          _remoteConfigRefreshInterval == other._remoteConfigRefreshInterval;

  @override
  int get hashCode => Object.hash(
    _stopOnTerminate,
    _startOnBoot,
    _heartbeatInterval,
    _schedule,
    remoteConfigUrl,
    remoteConfigHeaders,
    _remoteConfigTimeout,
    _remoteConfigRefreshInterval,
  );
}

/// HTTP sync settings.
@immutable
class HttpConfig {
  /// Creates a new [HttpConfig] with optional overrides.
  const HttpConfig({
    this.url,
    HttpMethod? method,
    this.headers,
    this.params,
    this.extras,
    this.httpRootProperty,
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
    this.sslPinningFingerprints,
    this.sslPinningCertificates,
    bool? syncTelematics,
    this.telematicsUrl,
  }) : _method = method,
       _autoSync = autoSync,
       _batchSync = batchSync,
       _maxBatchSize = maxBatchSize,
       _autoSyncThreshold = autoSyncThreshold,
       _autoSyncDelay = autoSyncDelay,
       _syncInterval = syncInterval,
       _httpTimeout = httpTimeout,
       _locationsOrderDirection = locationsOrderDirection,
       _disableAutoSyncOnCellular = disableAutoSyncOnCellular,
       _maxRetries = maxRetries,
       _retryBackoffBase = retryBackoffBase,
       _retryBackoffCap = retryBackoffCap,
       _enableDeltaCompression = enableDeltaCompression,
       _deltaCoordinatePrecision = deltaCoordinatePrecision,
       _syncTelematics = syncTelematics;

  /// Creates an [HttpConfig] from a map.
  factory HttpConfig.fromMap(Map<String, Object?> map) {
    return HttpConfig(
      url: map['url'] as String?,
      method: map.containsKey('method')
          ? HttpMethod.values[ensureInt(
              map['method'],
              fallback: 0,
            ).clamp(0, HttpMethod.values.length - 1)]
          : null,
      headers: (map['headers'] as Map?)?.cast<String, String>(),
      params: (map['params'] as Map?)?.cast<String, Object?>(),
      extras: (map['extras'] as Map?)?.cast<String, Object?>(),
      httpRootProperty: map['httpRootProperty'] as String?,
      autoSync: map.containsKey('autoSync')
          ? ensureBool(map['autoSync'], fallback: true)
          : null,
      batchSync: map.containsKey('batchSync')
          ? ensureBool(map['batchSync'], fallback: false)
          : null,
      maxBatchSize: map.containsKey('maxBatchSize')
          ? ensureInt(map['maxBatchSize'], fallback: 250)
          : null,
      autoSyncThreshold: map.containsKey('autoSyncThreshold')
          ? ensureInt(map['autoSyncThreshold'], fallback: 0)
          : null,
      autoSyncDelay: map.containsKey('autoSyncDelay')
          ? ensureInt(map['autoSyncDelay'], fallback: 10000)
          : null,
      syncInterval: map.containsKey('syncInterval')
          ? ensureInt(map['syncInterval'], fallback: 0)
          : null,
      httpTimeout: map.containsKey('httpTimeout')
          ? ensureInt(map['httpTimeout'], fallback: 60000)
          : null,
      locationsOrderDirection: map.containsKey('locationsOrderDirection')
          ? LocationOrderDirection.values[ensureInt(
              map['locationsOrderDirection'],
              fallback: 0,
            ).clamp(0, LocationOrderDirection.values.length - 1)]
          : null,
      disableAutoSyncOnCellular: map.containsKey('disableAutoSyncOnCellular')
          ? ensureBool(map['disableAutoSyncOnCellular'], fallback: false)
          : null,
      maxRetries: map.containsKey('maxRetries')
          ? ensureInt(map['maxRetries'], fallback: 3)
          : null,
      retryBackoffBase: map.containsKey('retryBackoffBase')
          ? ensureInt(map['retryBackoffBase'], fallback: 1000)
          : null,
      retryBackoffCap: map.containsKey('retryBackoffCap')
          ? ensureInt(map['retryBackoffCap'], fallback: 60000)
          : null,
      enableDeltaCompression: map.containsKey('enableDeltaCompression')
          ? ensureBool(map['enableDeltaCompression'], fallback: false)
          : null,
      deltaCoordinatePrecision: map.containsKey('deltaCoordinatePrecision')
          ? ensureInt(map['deltaCoordinatePrecision'], fallback: 5)
          : null,
      sslPinningFingerprints: (map['sslPinningFingerprints'] as List?)
          ?.cast<String>(),
      sslPinningCertificates: (map['sslPinningCertificates'] as List?)
          ?.cast<String>(),
      syncTelematics: map.containsKey('syncTelematics')
          ? ensureBool(map['syncTelematics'], fallback: false)
          : null,
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
      method: method ?? _method,
      headers: headers ?? this.headers,
      params: params ?? this.params,
      extras: extras ?? this.extras,
      httpRootProperty: httpRootProperty ?? this.httpRootProperty,
      autoSync: autoSync ?? _autoSync,
      batchSync: batchSync ?? _batchSync,
      maxBatchSize: maxBatchSize ?? _maxBatchSize,
      autoSyncThreshold: autoSyncThreshold ?? _autoSyncThreshold,
      autoSyncDelay: autoSyncDelay ?? _autoSyncDelay,
      syncInterval: syncInterval ?? _syncInterval,
      httpTimeout: httpTimeout ?? _httpTimeout,
      locationsOrderDirection:
          locationsOrderDirection ?? this.locationsOrderDirection,
      disableAutoSyncOnCellular:
          disableAutoSyncOnCellular ?? this.disableAutoSyncOnCellular,
      maxRetries: maxRetries ?? _maxRetries,
      retryBackoffBase: retryBackoffBase ?? _retryBackoffBase,
      retryBackoffCap: retryBackoffCap ?? _retryBackoffCap,
      enableDeltaCompression:
          enableDeltaCompression ?? this.enableDeltaCompression,
      deltaCoordinatePrecision:
          deltaCoordinatePrecision ?? this.deltaCoordinatePrecision,
      sslPinningFingerprints:
          sslPinningFingerprints ?? this.sslPinningFingerprints,
      sslPinningCertificates:
          sslPinningCertificates ?? this.sslPinningCertificates,
      syncTelematics: syncTelematics ?? _syncTelematics,
      telematicsUrl: telematicsUrl ?? this.telematicsUrl,
    );
  }

  /// The HTTP server URL to sync locations to.
  /// Defaults to `null`.
  final String? url;

  // Backing fields. `null` means "the caller did not provide this",
  // which keeps the field out of the wire payload (#321). The getters
  // below resolve each one to its documented default.
  final HttpMethod? _method;
  final bool? _autoSync;
  final bool? _batchSync;
  final int? _maxBatchSize;
  final int? _autoSyncThreshold;
  final int? _autoSyncDelay;
  final int? _syncInterval;
  final int? _httpTimeout;
  final LocationOrderDirection? _locationsOrderDirection;
  final bool? _disableAutoSyncOnCellular;
  final int? _maxRetries;
  final int? _retryBackoffBase;
  final int? _retryBackoffCap;
  final bool? _enableDeltaCompression;
  final int? _deltaCoordinatePrecision;
  final bool? _syncTelematics;

  /// The HTTP method to use for sync requests (POST or PUT).
  /// Defaults to [HttpMethod.post].
  HttpMethod get method => _method ?? HttpMethod.post;

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
  /// Root JSON property for the sync payload. Defaults to `'location'`
  /// when unset; the default is applied natively rather than eagerly here,
  /// so a partial setConfig() does not overwrite a configured value (#321).
  final String? httpRootProperty;

  /// Whether to auto-sync locations immediately when they are recorded/inserted into the database.
  /// Defaults to `true`.
  bool get autoSync => _autoSync ?? true;

  /// Send all locations in a batch array within one request instead of one request per location.
  /// Defaults to `false`.
  bool get batchSync => _batchSync ?? false;

  /// The maximum number of records to send in a single batch.
  /// Defaults to `250`.
  int get maxBatchSize => _maxBatchSize ?? 250;

  /// Minimum number of unsynced locations in the database before auto-sync triggers.
  /// Defaults to `0`.
  int get autoSyncThreshold => _autoSyncThreshold ?? 0;

  /// Delay in milliseconds before batching rapid location syncs (debounce time).
  /// Defaults to `10000` (10 seconds).
  int get autoSyncDelay => _autoSyncDelay ?? 10000;

  /// Interval, in **seconds**, for the repeating sync timer (interval-based sync).
  ///
  /// When greater than `0`, the SDK periodically flushes any pending locations
  /// to [url] on this cadence, in addition to the debounced auto-sync controlled
  /// by [autoSyncDelay]. This is useful for time-driven flushing of the offline
  /// queue regardless of how many records have accumulated.
  ///
  /// Defaults to `0` (the repeating timer is disabled).
  int get syncInterval => _syncInterval ?? 0;

  /// Request timeout in milliseconds.
  /// Defaults to `60000` (60 seconds).
  int get httpTimeout => _httpTimeout ?? 60000;

  /// The chronological sort order for synced locations.
  /// Defaults to [LocationOrderDirection.ascending].
  LocationOrderDirection get locationsOrderDirection =>
      _locationsOrderDirection ?? LocationOrderDirection.ascending;

  /// Disable auto-syncing when on a cellular data network (syncs only on Wi-Fi).
  /// Defaults to `false`.
  bool get disableAutoSyncOnCellular => _disableAutoSyncOnCellular ?? false;

  /// Maximum retry attempts for transient HTTP failures (e.g. 5xx, 429, timeout).
  /// Defaults to `3`.
  int get maxRetries => _maxRetries ?? 3;

  /// Base delay in seconds for exponential backoff between retries.
  /// Defaults to `1`.
  int get retryBackoffBase => _retryBackoffBase ?? 1000;

  /// Maximum backoff delay in seconds (caps exponential growth).
  /// Defaults to `60`.
  int get retryBackoffCap => _retryBackoffCap ?? 60000;

  /// Enable delta-encoding compression for batch sync payloads.
  /// Drops duplicate headers and applies delta compression to coordinates, returning 60–80% size reduction.
  /// Defaults to `false`.
  bool get enableDeltaCompression => _enableDeltaCompression ?? false;

  /// Coordinate decimal precision for delta compression (e.g. 5 ≈ 1.1m, 6 ≈ 0.11m).
  /// Defaults to `5`.
  int get deltaCoordinatePrecision => _deltaCoordinatePrecision ?? 5;

  /// **Enterprise** — SHA-256 SSL public key pin fingerprints.
  final List<String>? sslPinningFingerprints;

  /// **Enterprise** — Base64 encoded SSL certificates.
  final List<String>? sslPinningCertificates;

  /// Whether to sync telematics events automatically.
  bool get syncTelematics => _syncTelematics ?? false;

  /// The URL to sync telematics events to.
  final String? telematicsUrl;

  /// Converts to Pigeon [TlHttpConfig].
  TlHttpConfig toTlConfig() => TlHttpConfig(
    url: url,
    method: _method == null ? null : TlHttpMethod.values[_method.index],
    headers: headers,
    params: params,
    extras: extras,
    httpRootProperty: httpRootProperty,
    autoSync: _autoSync,
    batchSync: _batchSync,
    maxBatchSize: _maxBatchSize,
    autoSyncThreshold: _autoSyncThreshold,
    autoSyncDelay: _autoSyncDelay,
    syncInterval: _syncInterval,
    httpTimeout: _httpTimeout,
    locationsOrderDirection: _locationsOrderDirection == null
        ? null
        : TlLocationOrderDirection.values[_locationsOrderDirection.index],
    disableAutoSyncOnCellular: _disableAutoSyncOnCellular,
    maxRetries: _maxRetries,
    retryBackoffBase: _retryBackoffBase,
    retryBackoffCap: _retryBackoffCap,
    enableDeltaCompression: _enableDeltaCompression,
    deltaCoordinatePrecision: _deltaCoordinatePrecision,
    syncTelematics: _syncTelematics,
    telematicsUrl: telematicsUrl,
    sslPinningFingerprints: sslPinningFingerprints,
    sslPinningCertificates: sslPinningCertificates,
  );

  /// Applies every field [other] explicitly supplied on top of this config,
  /// leaving fields [other] left unset as they are here.
  ///
  /// This mirrors what the platform does with the serialized payload, and
  /// keeps `Tracelet.activeConfig` in step with the values actually persisted
  /// natively after a partial `setConfig()` (#321).
  HttpConfig mergedWith(HttpConfig other) => HttpConfig(
    url: other.url ?? url,
    method: other._method ?? _method,
    headers: other.headers ?? headers,
    params: other.params ?? params,
    extras: other.extras ?? extras,
    httpRootProperty: other.httpRootProperty ?? httpRootProperty,
    autoSync: other._autoSync ?? _autoSync,
    batchSync: other._batchSync ?? _batchSync,
    maxBatchSize: other._maxBatchSize ?? _maxBatchSize,
    autoSyncThreshold: other._autoSyncThreshold ?? _autoSyncThreshold,
    autoSyncDelay: other._autoSyncDelay ?? _autoSyncDelay,
    syncInterval: other._syncInterval ?? _syncInterval,
    httpTimeout: other._httpTimeout ?? _httpTimeout,
    locationsOrderDirection:
        other._locationsOrderDirection ?? _locationsOrderDirection,
    disableAutoSyncOnCellular:
        other._disableAutoSyncOnCellular ?? _disableAutoSyncOnCellular,
    maxRetries: other._maxRetries ?? _maxRetries,
    retryBackoffBase: other._retryBackoffBase ?? _retryBackoffBase,
    retryBackoffCap: other._retryBackoffCap ?? _retryBackoffCap,
    enableDeltaCompression:
        other._enableDeltaCompression ?? _enableDeltaCompression,
    deltaCoordinatePrecision:
        other._deltaCoordinatePrecision ?? _deltaCoordinatePrecision,
    sslPinningFingerprints:
        other.sslPinningFingerprints ?? sslPinningFingerprints,
    sslPinningCertificates:
        other.sslPinningCertificates ?? sslPinningCertificates,
    syncTelematics: other._syncTelematics ?? _syncTelematics,
    telematicsUrl: other.telematicsUrl ?? telematicsUrl,
  );

  /// Returns this config with every field pinned to its effective value.
  ///
  /// Used by `ready()`, which establishes a complete native baseline rather
  /// than a partial update — so the platform's own defaults never have to
  /// match Dart's for correctness (#321).
  HttpConfig resolved() => HttpConfig(
    url: url,
    method: method,
    headers: headers,
    params: params,
    extras: extras,
    httpRootProperty: httpRootProperty ?? 'location',
    autoSync: autoSync,
    batchSync: batchSync,
    maxBatchSize: maxBatchSize,
    autoSyncThreshold: autoSyncThreshold,
    autoSyncDelay: autoSyncDelay,
    syncInterval: syncInterval,
    httpTimeout: httpTimeout,
    locationsOrderDirection: locationsOrderDirection,
    disableAutoSyncOnCellular: disableAutoSyncOnCellular,
    maxRetries: maxRetries,
    retryBackoffBase: retryBackoffBase,
    retryBackoffCap: retryBackoffCap,
    enableDeltaCompression: enableDeltaCompression,
    deltaCoordinatePrecision: deltaCoordinatePrecision,
    sslPinningFingerprints: sslPinningFingerprints,
    sslPinningCertificates: sslPinningCertificates,
    syncTelematics: syncTelematics,
    telematicsUrl: telematicsUrl,
  );

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (url != null) 'url': url,
      if (_method != null) 'method': _method.index,
      if (headers != null) 'headers': headers,
      if (params != null) 'params': params,
      if (extras != null) 'extras': extras,
      if (httpRootProperty != null) 'httpRootProperty': httpRootProperty,
      if (_autoSync != null) 'autoSync': _autoSync,
      if (_batchSync != null) 'batchSync': _batchSync,
      if (_maxBatchSize != null) 'maxBatchSize': _maxBatchSize,
      if (_autoSyncThreshold != null) 'autoSyncThreshold': _autoSyncThreshold,
      if (_autoSyncDelay != null) 'autoSyncDelay': _autoSyncDelay,
      if (_syncInterval != null) 'syncInterval': _syncInterval,
      if (_httpTimeout != null) 'httpTimeout': _httpTimeout,
      if (_locationsOrderDirection != null)
        'locationsOrderDirection': _locationsOrderDirection.index,
      if (_disableAutoSyncOnCellular != null)
        'disableAutoSyncOnCellular': _disableAutoSyncOnCellular,
      if (_maxRetries != null) 'maxRetries': _maxRetries,
      if (_retryBackoffBase != null) 'retryBackoffBase': _retryBackoffBase,
      if (_retryBackoffCap != null) 'retryBackoffCap': _retryBackoffCap,
      if (_enableDeltaCompression != null)
        'enableDeltaCompression': _enableDeltaCompression,
      if (_deltaCoordinatePrecision != null)
        'deltaCoordinatePrecision': _deltaCoordinatePrecision,
      if (_syncTelematics != null) 'syncTelematics': _syncTelematics,
      if (telematicsUrl != null) 'telematicsUrl': telematicsUrl,
      if (sslPinningFingerprints != null)
        'sslPinningFingerprints': sslPinningFingerprints,
      if (sslPinningCertificates != null)
        'sslPinningCertificates': sslPinningCertificates,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HttpConfig &&
          runtimeType == other.runtimeType &&
          url == other.url &&
          _method == other._method &&
          headers == other.headers &&
          params == other.params &&
          extras == other.extras &&
          httpRootProperty == other.httpRootProperty &&
          _autoSync == other._autoSync &&
          _batchSync == other._batchSync &&
          _maxBatchSize == other._maxBatchSize &&
          _autoSyncThreshold == other._autoSyncThreshold &&
          _autoSyncDelay == other._autoSyncDelay &&
          _syncInterval == other._syncInterval &&
          _httpTimeout == other._httpTimeout &&
          _locationsOrderDirection == other._locationsOrderDirection &&
          _disableAutoSyncOnCellular == other._disableAutoSyncOnCellular &&
          _maxRetries == other._maxRetries &&
          _retryBackoffBase == other._retryBackoffBase &&
          _retryBackoffCap == other._retryBackoffCap &&
          _enableDeltaCompression == other._enableDeltaCompression &&
          _deltaCoordinatePrecision == other._deltaCoordinatePrecision &&
          _syncTelematics == other._syncTelematics &&
          telematicsUrl == other.telematicsUrl &&
          _listEquals(sslPinningFingerprints, other.sslPinningFingerprints) &&
          _listEquals(sslPinningCertificates, other.sslPinningCertificates);

  @override
  int get hashCode => Object.hashAll([
    url,
    _method,
    headers,
    params,
    extras,
    httpRootProperty,
    _autoSync,
    _batchSync,
    _maxBatchSize,
    _autoSyncThreshold,
    _autoSyncDelay,
    _syncInterval,
    _httpTimeout,
    _locationsOrderDirection,
    _disableAutoSyncOnCellular,
    _maxRetries,
    _retryBackoffBase,
    _retryBackoffCap,
    _enableDeltaCompression,
    _deltaCoordinatePrecision,
    _syncTelematics,
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
  const LoggerConfig({LogLevel? logLevel, int? logMaxDays, bool? debug})
    : _logLevel = logLevel,
      _logMaxDays = logMaxDays,
      _debug = debug;

  /// Creates a [LoggerConfig] from a map.
  factory LoggerConfig.fromMap(Map<String, Object?> map) {
    return LoggerConfig(
      logLevel: map.containsKey('logLevel')
          ? LogLevel.values[ensureInt(
              map['logLevel'],
              fallback: 2,
            ).clamp(0, LogLevel.values.length - 1)]
          : null,
      logMaxDays: map.containsKey('logMaxDays')
          ? ensureInt(map['logMaxDays'], fallback: 3)
          : null,
      debug: map.containsKey('debug')
          ? ensureBool(map['debug'], fallback: false)
          : null,
    );
  }

  /// Creates a copy of this [LoggerConfig] with the given fields replaced with the new values.
  LoggerConfig copyWith({LogLevel? logLevel, int? logMaxDays, bool? debug}) {
    return LoggerConfig(
      logLevel: logLevel ?? _logLevel,
      logMaxDays: logMaxDays ?? _logMaxDays,
      debug: debug ?? _debug,
    );
  }

  // Backing fields. `null` means "the caller did not provide this",
  // which keeps the field out of the wire payload (#321). The getters
  // below resolve each one to its documented default.
  final LogLevel? _logLevel;
  final int? _logMaxDays;
  final bool? _debug;

  /// The minimum level of logs to capture and persist.
  /// Defaults to [LogLevel.info].
  LogLevel get logLevel => _logLevel ?? LogLevel.info;

  /// The maximum number of days to retain logs in the database.
  /// Defaults to `3`.
  int get logMaxDays => _logMaxDays ?? 3;

  /// Enable debugging mode (which produces platform-specific tracking sounds
  /// and verbose local logging). Defaults to `false`.
  bool get debug => _debug ?? false;

  /// Applies every field [other] explicitly supplied on top of this config,
  /// leaving fields [other] left unset as they are here.
  ///
  /// This mirrors what the platform does with the serialized payload, and
  /// keeps `Tracelet.activeConfig` in step with the values actually persisted
  /// natively after a partial `setConfig()` (#321).
  LoggerConfig mergedWith(LoggerConfig other) => LoggerConfig(
    logLevel: other._logLevel ?? _logLevel,
    logMaxDays: other._logMaxDays ?? _logMaxDays,
    debug: other._debug ?? _debug,
  );

  /// Returns this config with every field pinned to its effective value.
  ///
  /// Used by `ready()`, which establishes a complete native baseline rather
  /// than a partial update — so the platform's own defaults never have to
  /// match Dart's for correctness (#321).
  LoggerConfig resolved() =>
      LoggerConfig(logLevel: logLevel, logMaxDays: logMaxDays, debug: debug);

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (_logLevel != null) 'logLevel': _logLevel.index,
      if (_logMaxDays != null) 'logMaxDays': _logMaxDays,
      if (_debug != null) 'debug': _debug,
    };
  }

  /// Converts to Pigeon [TlLoggerConfig].
  TlLoggerConfig toTlConfig() => TlLoggerConfig(
    logLevel: _logLevel == null ? null : TlLogLevel.values[_logLevel.index],
    logMaxDays: _logMaxDays,
    debug: _debug,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoggerConfig &&
          runtimeType == other.runtimeType &&
          _logLevel == other._logLevel &&
          _logMaxDays == other._logMaxDays &&
          _debug == other._debug;

  @override
  int get hashCode => Object.hash(_logLevel, _logMaxDays, _debug);
}

@immutable
/// Configuration for motion and activity detection.
class MotionConfig {
  /// Creates a new [MotionConfig] with optional overrides.
  const MotionConfig({
    int? stopTimeout,
    int? motionTriggerDelay,
    bool? disableMotionActivityUpdates,
    bool? isMoving,
    int? activityRecognitionInterval,
    int? minimumActivityRecognitionConfidence,
    bool? disableStopDetection,
    int? stopDetectionDelay,
    bool? stopOnStationary,
    this.activityTypes,
    double? stationaryRadius,
    bool? useSignificantChangesOnly,
    double? shakeThreshold,
    double? stillThreshold,
    int? stillSampleCount,
    MotionDetectionMode? motionDetectionMode,
    double? speedMovingThreshold,
    int? speedStationaryDelay,
    StationaryTrackingMode? stationaryTrackingMode,
    int? stationaryPeriodicInterval,
    DesiredAccuracy? stationaryPeriodicAccuracy,
    int? speedWakeConfirmCount,
  }) : _stopTimeout = stopTimeout,
       _motionTriggerDelay = motionTriggerDelay,
       _disableMotionActivityUpdates = disableMotionActivityUpdates,
       _isMoving = isMoving,
       _activityRecognitionInterval = activityRecognitionInterval,
       _minimumActivityRecognitionConfidence =
           minimumActivityRecognitionConfidence,
       _disableStopDetection = disableStopDetection,
       _stopDetectionDelay = stopDetectionDelay,
       _stopOnStationary = stopOnStationary,
       _stationaryRadius = stationaryRadius,
       _useSignificantChangesOnly = useSignificantChangesOnly,
       _shakeThreshold = shakeThreshold,
       _stillThreshold = stillThreshold,
       _stillSampleCount = stillSampleCount,
       _motionDetectionMode = motionDetectionMode,
       _speedMovingThreshold = speedMovingThreshold,
       _speedStationaryDelay = speedStationaryDelay,
       _stationaryTrackingMode = stationaryTrackingMode,
       _stationaryPeriodicInterval = stationaryPeriodicInterval,
       _stationaryPeriodicAccuracy = stationaryPeriodicAccuracy,
       _speedWakeConfirmCount = speedWakeConfirmCount,
       // The bounds constrain only values the caller actually supplied — an
       // unset field carries no value to validate (#321).
       assert(
         speedStationaryDelay == null || speedStationaryDelay >= 0,
         'speedStationaryDelay must be >= 0',
       ),
       assert(
         speedWakeConfirmCount == null || speedWakeConfirmCount >= 1,
         'speedWakeConfirmCount must be >= 1',
       ),
       assert(
         speedMovingThreshold == null || speedMovingThreshold > 0,
         'speedMovingThreshold must be > 0',
       );

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
      stopTimeout: map.containsKey('stopTimeout')
          ? ensureInt(map['stopTimeout'], fallback: 5)
          : null,
      motionTriggerDelay: map.containsKey('motionTriggerDelay')
          ? ensureInt(map['motionTriggerDelay'], fallback: 0)
          : null,
      disableMotionActivityUpdates:
          map.containsKey('disableMotionActivityUpdates')
          ? ensureBool(map['disableMotionActivityUpdates'], fallback: false)
          : null,
      isMoving: map.containsKey('isMoving')
          ? ensureBool(map['isMoving'], fallback: false)
          : null,
      activityRecognitionInterval:
          map.containsKey('activityRecognitionInterval')
          ? ensureInt(map['activityRecognitionInterval'], fallback: 1000)
          : null,
      minimumActivityRecognitionConfidence:
          map.containsKey('minimumActivityRecognitionConfidence')
          ? ensureInt(map['minimumActivityRecognitionConfidence'], fallback: 75)
          : null,
      disableStopDetection: map.containsKey('disableStopDetection')
          ? ensureBool(map['disableStopDetection'], fallback: false)
          : null,
      stopDetectionDelay: map.containsKey('stopDetectionDelay')
          ? ensureInt(map['stopDetectionDelay'], fallback: 0)
          : null,
      stopOnStationary: map.containsKey('stopOnStationary')
          ? ensureBool(map['stopOnStationary'], fallback: false)
          : null,
      activityTypes: activityTypesList,
      stationaryRadius: map.containsKey('stationaryRadius')
          ? ensureDouble(map['stationaryRadius'], fallback: 25)
          : null,
      useSignificantChangesOnly: map.containsKey('useSignificantChangesOnly')
          ? ensureBool(map['useSignificantChangesOnly'], fallback: false)
          : null,
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
      motionDetectionMode: map.containsKey('motionDetectionMode')
          ? _parseMotionDetectionMode(map['motionDetectionMode'])
          : null,
      speedMovingThreshold: map.containsKey('speedMovingThreshold')
          ? ensureDouble(map['speedMovingThreshold'], fallback: 1.5)
          : null,
      speedStationaryDelay: map.containsKey('speedStationaryDelay')
          ? ensureInt(map['speedStationaryDelay'], fallback: 180)
          : null,
      stationaryTrackingMode: map.containsKey('stationaryTrackingMode')
          ? _parseStationaryTrackingMode(map['stationaryTrackingMode'])
          : null,
      stationaryPeriodicInterval: map.containsKey('stationaryPeriodicInterval')
          ? ensureInt(map['stationaryPeriodicInterval'], fallback: 120)
          : null,
      stationaryPeriodicAccuracy: map.containsKey('stationaryPeriodicAccuracy')
          ? DesiredAccuracy.values[ensureInt(
              map['stationaryPeriodicAccuracy'],
              fallback: DesiredAccuracy.high.index,
            ).clamp(0, DesiredAccuracy.values.length - 1)]
          : null,
      speedWakeConfirmCount: map.containsKey('speedWakeConfirmCount')
          ? ensureInt(map['speedWakeConfirmCount'], fallback: 1)
          : null,
    );
  }

  // Backing fields. `null` means "the caller did not provide this",
  // which keeps the field out of the wire payload (#321). The getters
  // below resolve each one to its documented default.
  final int? _stopTimeout;
  final int? _motionTriggerDelay;
  final bool? _disableMotionActivityUpdates;
  final bool? _isMoving;
  final int? _activityRecognitionInterval;
  final int? _minimumActivityRecognitionConfidence;
  final bool? _disableStopDetection;
  final int? _stopDetectionDelay;
  final bool? _stopOnStationary;
  final double? _stationaryRadius;
  final bool? _useSignificantChangesOnly;
  final MotionDetectionMode? _motionDetectionMode;
  final double? _speedMovingThreshold;
  final int? _speedStationaryDelay;
  final StationaryTrackingMode? _stationaryTrackingMode;
  final int? _stationaryPeriodicInterval;
  final DesiredAccuracy? _stationaryPeriodicAccuracy;
  final int? _speedWakeConfirmCount;
  final double? _shakeThreshold;
  final double? _stillThreshold;
  final int? _stillSampleCount;

  /// The amount of time (in minutes) the device must be stationary before declaring the stationary state.
  /// Defaults to `5`.
  int get stopTimeout => _stopTimeout ?? 5;

  /// The delay (in milliseconds) before starting tracking when motion is triggered.
  /// Defaults to `0`.
  int get motionTriggerDelay => _motionTriggerDelay ?? 0;

  /// Disable platform activity recognition and fall back to permission-free accelerometer-only motion detection.
  /// Defaults to `false`.
  bool get disableMotionActivityUpdates =>
      _disableMotionActivityUpdates ?? false;

  /// The current state of motion (moving or stationary).
  /// Defaults to `false` (stationary).
  bool get isMoving => _isMoving ?? false;

  /// The interval (in milliseconds) for activity recognition updates.
  /// Defaults to `1000`.
  int get activityRecognitionInterval => _activityRecognitionInterval ?? 1000;

  /// The minimum confidence level (0–100) required to accept a detected activity.
  /// Defaults to `75`.
  int get minimumActivityRecognitionConfidence =>
      _minimumActivityRecognitionConfidence ?? 75;

  /// Disable the automatic stationary state transition entirely.
  /// Defaults to `false`.
  bool get disableStopDetection => _disableStopDetection ?? false;

  /// The extra delay (in seconds) to add after the stop timeout before stopping location updates.
  /// Defaults to `0`.
  int get stopDetectionDelay => _stopDetectionDelay ?? 0;

  /// Stop tracking entirely when a stationary state is declared.
  /// Defaults to `false`.
  bool get stopOnStationary => _stopOnStationary ?? false;

  /// The list of specific [LocationActivityType]s that can trigger a transition from stationary to moving.
  /// Defaults to `null` (any moving activity).
  final List<LocationActivityType>? activityTypes;

  /// The radius (in meters) of the stationary geofence.
  /// Defaults to `25.0`.
  double get stationaryRadius => _stationaryRadius ?? 25.0;

  /// Whether significant motion changes only should be tracked (iOS only).
  /// Defaults to `false`.
  bool get useSignificantChangesOnly => _useSignificantChangesOnly ?? false;

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
  double get shakeThreshold => _shakeThreshold ?? 2.5;

  /// Whether [shakeThreshold] was set explicitly. When `false` the value is not
  /// sent to the platform, so each platform keeps its own tuned default.
  bool get hasExplicitShakeThreshold => _shakeThreshold != null;

  /// The acceleration threshold (in m/s²) below which a sample is counted as
  /// still.
  ///
  /// Leave this unset to let each platform apply its own tuned default —
  /// `0.4 m/s²` on Android, `0.15 g` on iOS. Setting it sends the value to both;
  /// iOS divides by 9.81, so `0.4` becomes `0.04 g`, roughly four times stricter
  /// than the iOS default. Reading this property reports `0.4` when unset.
  double get stillThreshold => _stillThreshold ?? 0.4;

  /// Whether [stillThreshold] was set explicitly. When `false` the value is not
  /// sent to the platform, so each platform keeps its own tuned default.
  bool get hasExplicitStillThreshold => _stillThreshold != null;

  /// The number of consecutive still samples required to initiate the
  /// [stopTimeout].
  ///
  /// Leave this unset to let each platform target the same ~5 s dwell window
  /// with its own sampling rate — 25 samples at ~5 Hz on Android, 50 at 10 Hz on
  /// iOS. Setting it is taken as a literal sample count on both platforms, so
  /// the dwell duration then differs per platform. Reading this property reports
  /// `25` when unset.
  int get stillSampleCount => _stillSampleCount ?? 25;

  /// Whether [stillSampleCount] was set explicitly. When `false` the value is
  /// not sent to the platform, so each platform keeps its own tuned default.
  bool get hasExplicitStillSampleCount => _stillSampleCount != null;

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
  MotionDetectionMode get motionDetectionMode =>
      _motionDetectionMode ?? MotionDetectionMode.accelerometer;

  /// [Speed mode] Speed (m/s) below which a location fix counts as
  /// "not moving."
  ///
  /// `1.5 m/s` ≈ 5.4 km/h — filters GPS drift while still catching
  /// parking-lot crawl. Defaults to `1.5`.
  double get speedMovingThreshold => _speedMovingThreshold ?? 1.5;

  /// [Speed mode] Seconds of continuous low-speed fixes before the state
  /// machine declares stationary and switches to the
  /// [stationaryTrackingMode].
  ///
  /// Acts as a "red-light buffer" so stops at traffic lights don't trigger
  /// a mode switch. Defaults to `180` (3 minutes).
  int get speedStationaryDelay => _speedStationaryDelay ?? 180;

  /// [Speed mode] Tracking mode to enter when stationary.
  ///
  /// - [StationaryTrackingMode.periodic] (default): schedule one-shot
  ///   fixes at [stationaryPeriodicInterval] seconds. GPS radio is off
  ///   between fixes.
  /// - [StationaryTrackingMode.geofences]: stop continuous tracking and
  ///   rely on existing geofence monitoring. Wake speed is evaluated on
  ///   any geofence-triggered fix.
  StationaryTrackingMode get stationaryTrackingMode =>
      _stationaryTrackingMode ?? StationaryTrackingMode.periodic;

  /// [Speed mode] Interval (in seconds) between periodic fixes while
  /// stationary.
  ///
  /// Defaults to `120` (2 minutes). On Android, sub-15-minute intervals
  /// are driven by an in-process timer on the foreground location service
  /// — no `SCHEDULE_EXACT_ALARM` permission is required.
  int get stationaryPeriodicInterval => _stationaryPeriodicInterval ?? 120;

  /// [Speed mode] Desired accuracy for periodic stationary fixes.
  ///
  /// Should be [DesiredAccuracy.high] so that the GPS speed value is
  /// reliable for wake detection. If set to a lower accuracy, consider
  /// raising [speedWakeConfirmCount] to filter phantom speed from
  /// WiFi/cell position jitter. Defaults to [DesiredAccuracy.high].
  DesiredAccuracy get stationaryPeriodicAccuracy =>
      _stationaryPeriodicAccuracy ?? DesiredAccuracy.high;

  /// [Speed mode] Number of consecutive periodic fixes with
  /// `speed >= speedMovingThreshold` required before transitioning back
  /// to continuous tracking.
  ///
  /// `1` (default) gives instant wake and is safe when
  /// [stationaryPeriodicAccuracy] is [DesiredAccuracy.high] because true
  /// GPS speed is jitter-free. Increase to `3+` if you lower the
  /// stationary accuracy.
  int get speedWakeConfirmCount => _speedWakeConfirmCount ?? 1;

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

  /// Applies every field [other] explicitly supplied on top of this config,
  /// leaving fields [other] left unset as they are here.
  ///
  /// This mirrors what the platform does with the serialized payload, and
  /// keeps `Tracelet.activeConfig` in step with the values actually persisted
  /// natively after a partial `setConfig()` (#321).
  MotionConfig mergedWith(MotionConfig other) => MotionConfig(
    stopTimeout: other._stopTimeout ?? _stopTimeout,
    motionTriggerDelay: other._motionTriggerDelay ?? _motionTriggerDelay,
    disableMotionActivityUpdates:
        other._disableMotionActivityUpdates ?? _disableMotionActivityUpdates,
    isMoving: other._isMoving ?? _isMoving,
    activityRecognitionInterval:
        other._activityRecognitionInterval ?? _activityRecognitionInterval,
    minimumActivityRecognitionConfidence:
        other._minimumActivityRecognitionConfidence ??
        _minimumActivityRecognitionConfidence,
    disableStopDetection: other._disableStopDetection ?? _disableStopDetection,
    stopDetectionDelay: other._stopDetectionDelay ?? _stopDetectionDelay,
    stopOnStationary: other._stopOnStationary ?? _stopOnStationary,
    activityTypes: other.activityTypes ?? activityTypes,
    stationaryRadius: other._stationaryRadius ?? _stationaryRadius,
    useSignificantChangesOnly:
        other._useSignificantChangesOnly ?? _useSignificantChangesOnly,
    shakeThreshold: other._shakeThreshold ?? _shakeThreshold,
    stillThreshold: other._stillThreshold ?? _stillThreshold,
    stillSampleCount: other._stillSampleCount ?? _stillSampleCount,
    motionDetectionMode: other._motionDetectionMode ?? _motionDetectionMode,
    speedMovingThreshold: other._speedMovingThreshold ?? _speedMovingThreshold,
    speedStationaryDelay: other._speedStationaryDelay ?? _speedStationaryDelay,
    stationaryTrackingMode:
        other._stationaryTrackingMode ?? _stationaryTrackingMode,
    stationaryPeriodicInterval:
        other._stationaryPeriodicInterval ?? _stationaryPeriodicInterval,
    stationaryPeriodicAccuracy:
        other._stationaryPeriodicAccuracy ?? _stationaryPeriodicAccuracy,
    speedWakeConfirmCount:
        other._speedWakeConfirmCount ?? _speedWakeConfirmCount,
  );

  /// Returns this config with every field pinned to its effective value.
  ///
  /// Used by `ready()`, which establishes a complete native baseline rather
  /// than a partial update — so the platform's own defaults never have to
  /// match Dart's for correctness (#321).
  MotionConfig resolved() => MotionConfig(
    stopTimeout: stopTimeout,
    motionTriggerDelay: motionTriggerDelay,
    disableMotionActivityUpdates: disableMotionActivityUpdates,
    isMoving: isMoving,
    activityRecognitionInterval: activityRecognitionInterval,
    minimumActivityRecognitionConfidence: minimumActivityRecognitionConfidence,
    disableStopDetection: disableStopDetection,
    stopDetectionDelay: stopDetectionDelay,
    stopOnStationary: stopOnStationary,
    activityTypes: activityTypes,
    stationaryRadius: stationaryRadius,
    useSignificantChangesOnly: useSignificantChangesOnly,
    shakeThreshold: shakeThreshold,
    stillThreshold: stillThreshold,
    stillSampleCount: stillSampleCount,
    motionDetectionMode: motionDetectionMode,
    speedMovingThreshold: speedMovingThreshold,
    speedStationaryDelay: speedStationaryDelay,
    stationaryTrackingMode: stationaryTrackingMode,
    stationaryPeriodicInterval: stationaryPeriodicInterval,
    stationaryPeriodicAccuracy: stationaryPeriodicAccuracy,
    speedWakeConfirmCount: speedWakeConfirmCount,
  );

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (_stopTimeout != null) 'stopTimeout': _stopTimeout,
      if (_motionTriggerDelay != null)
        'motionTriggerDelay': _motionTriggerDelay,
      if (_disableMotionActivityUpdates != null)
        'disableMotionActivityUpdates': _disableMotionActivityUpdates,
      if (_isMoving != null) 'isMoving': _isMoving,
      if (_activityRecognitionInterval != null)
        'activityRecognitionInterval': _activityRecognitionInterval,
      if (_minimumActivityRecognitionConfidence != null)
        'minimumActivityRecognitionConfidence':
            _minimumActivityRecognitionConfidence,
      if (_disableStopDetection != null)
        'disableStopDetection': _disableStopDetection,
      if (_stopDetectionDelay != null)
        'stopDetectionDelay': _stopDetectionDelay,
      if (_stopOnStationary != null) 'stopOnStationary': _stopOnStationary,
      if (activityTypes != null)
        'activityTypes': activityTypes!.map((e) => e.index).toList(),
      if (_stationaryRadius != null) 'stationaryRadius': _stationaryRadius,
      if (_useSignificantChangesOnly != null)
        'useSignificantChangesOnly': _useSignificantChangesOnly,
      // Emitted only when set, so a round-trip through fromMap cannot turn a
      // platform default into an explicit override.
      if (hasExplicitShakeThreshold) 'shakeThreshold': shakeThreshold,
      if (hasExplicitStillThreshold) 'stillThreshold': stillThreshold,
      if (hasExplicitStillSampleCount) 'stillSampleCount': stillSampleCount,
      if (_motionDetectionMode != null)
        'motionDetectionMode': _motionDetectionMode.index,
      if (_speedMovingThreshold != null)
        'speedMovingThreshold': _speedMovingThreshold,
      if (_speedStationaryDelay != null)
        'speedStationaryDelay': _speedStationaryDelay,
      if (_stationaryTrackingMode != null)
        'stationaryTrackingMode': _stationaryTrackingMode.index,
      if (_stationaryPeriodicInterval != null)
        'stationaryPeriodicInterval': _stationaryPeriodicInterval,
      if (_stationaryPeriodicAccuracy != null)
        'stationaryPeriodicAccuracy': _stationaryPeriodicAccuracy.index,
      if (_speedWakeConfirmCount != null)
        'speedWakeConfirmCount': _speedWakeConfirmCount,
    };
  }

  /// Converts to Pigeon [TlMotionConfig].
  TlMotionConfig toTlConfig() => TlMotionConfig(
    stopTimeout: _stopTimeout,
    motionTriggerDelay: _motionTriggerDelay,
    disableMotionActivityUpdates: _disableMotionActivityUpdates,
    isMoving: _isMoving,
    activityRecognitionInterval: _activityRecognitionInterval,
    minimumActivityRecognitionConfidence: _minimumActivityRecognitionConfidence,
    disableStopDetection: _disableStopDetection,
    stopDetectionDelay: _stopDetectionDelay,
    stopOnStationary: _stopOnStationary,
    stationaryRadius: _stationaryRadius,
    useSignificantChangesOnly: _useSignificantChangesOnly,
    // null tells the platform to keep its own tuned default.
    shakeThreshold: hasExplicitShakeThreshold ? shakeThreshold : null,
    stillThreshold: hasExplicitStillThreshold ? stillThreshold : null,
    stillSampleCount: hasExplicitStillSampleCount ? stillSampleCount : null,
    activityTypes: activityTypes
        ?.map((e) => TlLocationActivityType.values[e.index])
        .toList(),
    motionDetectionMode: _motionDetectionMode == null
        ? null
        : TlMotionDetectionMode.values[_motionDetectionMode.index],
    speedMovingThreshold: _speedMovingThreshold,
    speedStationaryDelay: _speedStationaryDelay,
    stationaryTrackingMode: _stationaryTrackingMode == null
        ? null
        : TlStationaryTrackingMode.values[_stationaryTrackingMode.index],
    stationaryPeriodicInterval: _stationaryPeriodicInterval,
    stationaryPeriodicAccuracy: _stationaryPeriodicAccuracy == null
        ? null
        : TlDesiredAccuracy.values[_stationaryPeriodicAccuracy.index],
    speedWakeConfirmCount: _speedWakeConfirmCount,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MotionConfig &&
          runtimeType == other.runtimeType &&
          _stopTimeout == other._stopTimeout &&
          _motionTriggerDelay == other._motionTriggerDelay &&
          _disableMotionActivityUpdates ==
              other._disableMotionActivityUpdates &&
          _isMoving == other._isMoving &&
          _activityRecognitionInterval == other._activityRecognitionInterval &&
          minimumActivityRecognitionConfidence ==
              other.minimumActivityRecognitionConfidence &&
          _disableStopDetection == other._disableStopDetection &&
          _stopDetectionDelay == other._stopDetectionDelay &&
          _stopOnStationary == other._stopOnStationary &&
          activityTypes == other.activityTypes &&
          _stationaryRadius == other._stationaryRadius &&
          _useSignificantChangesOnly == other._useSignificantChangesOnly &&
          shakeThreshold == other.shakeThreshold &&
          hasExplicitShakeThreshold == other.hasExplicitShakeThreshold &&
          stillThreshold == other.stillThreshold &&
          hasExplicitStillThreshold == other.hasExplicitStillThreshold &&
          stillSampleCount == other.stillSampleCount &&
          hasExplicitStillSampleCount == other.hasExplicitStillSampleCount &&
          _motionDetectionMode == other._motionDetectionMode &&
          _speedMovingThreshold == other._speedMovingThreshold &&
          _speedStationaryDelay == other._speedStationaryDelay &&
          _stationaryTrackingMode == other._stationaryTrackingMode &&
          _stationaryPeriodicInterval == other._stationaryPeriodicInterval &&
          _stationaryPeriodicAccuracy == other._stationaryPeriodicAccuracy &&
          _speedWakeConfirmCount == other._speedWakeConfirmCount;

  @override
  String toString() =>
      'MotionConfig(stopTimeout: $stopTimeout, '
      'disableMotionActivityUpdates: $disableMotionActivityUpdates, '
      'isMoving: $isMoving, '
      'motionDetectionMode: $motionDetectionMode)';

  @override
  int get hashCode => Object.hashAll([
    _stopTimeout,
    _motionTriggerDelay,
    _disableMotionActivityUpdates,
    _isMoving,
    _activityRecognitionInterval,
    _minimumActivityRecognitionConfidence,
    _disableStopDetection,
    _stopDetectionDelay,
    _stopOnStationary,
    activityTypes,
    _stationaryRadius,
    _useSignificantChangesOnly,
    shakeThreshold,
    hasExplicitShakeThreshold,
    stillThreshold,
    hasExplicitStillThreshold,
    stillSampleCount,
    hasExplicitStillSampleCount,
    _motionDetectionMode,
    _speedMovingThreshold,
    _speedStationaryDelay,
    _stationaryTrackingMode,
    _stationaryPeriodicInterval,
    _stationaryPeriodicAccuracy,
    _speedWakeConfirmCount,
  ]);
}

@immutable
/// Configuration for geofencing behavior.
class GeofenceConfig {
  /// Creates a new [GeofenceConfig] with optional overrides.
  const GeofenceConfig({
    bool? geofenceInitialTriggerEntry,
    bool? geofenceInitialTrigger,
    int? geofenceProximityRadius,
    bool? geofenceModeHighAccuracy,
    int? geofenceExitAccuracyMax,
  }) : _geofenceInitialTriggerEntry = geofenceInitialTriggerEntry,
       _geofenceInitialTrigger = geofenceInitialTrigger,
       _geofenceProximityRadius = geofenceProximityRadius,
       _geofenceModeHighAccuracy = geofenceModeHighAccuracy,
       _geofenceExitAccuracyMax = geofenceExitAccuracyMax;

  /// Creates a [GeofenceConfig] from a map.
  factory GeofenceConfig.fromMap(Map<String, Object?> map) {
    return GeofenceConfig(
      geofenceInitialTriggerEntry:
          map.containsKey('geofenceInitialTriggerEntry')
          ? ensureBool(map['geofenceInitialTriggerEntry'], fallback: true)
          : null,
      geofenceInitialTrigger: map.containsKey('geofenceInitialTrigger')
          ? ensureBool(map['geofenceInitialTrigger'], fallback: true)
          : null,
      geofenceProximityRadius: map.containsKey('geofenceProximityRadius')
          ? ensureInt(map['geofenceProximityRadius'], fallback: 1000)
          : null,
      geofenceModeHighAccuracy: map.containsKey('geofenceModeHighAccuracy')
          ? ensureBool(map['geofenceModeHighAccuracy'], fallback: false)
          : null,
      geofenceExitAccuracyMax: map.containsKey('geofenceExitAccuracyMax')
          ? ensureInt(map['geofenceExitAccuracyMax'], fallback: -1)
          : null,
    );
  }

  // Backing fields. `null` means "the caller did not provide this",
  // which keeps the field out of the wire payload (#321). The getters
  // below resolve each one to its documented default.
  final bool? _geofenceInitialTriggerEntry;
  final bool? _geofenceInitialTrigger;
  final int? _geofenceProximityRadius;
  final bool? _geofenceModeHighAccuracy;
  final int? _geofenceExitAccuracyMax;

  /// Fire enter trigger immediately upon registration if device is already inside the geofence.
  /// Defaults to `true`.
  bool get geofenceInitialTriggerEntry => _geofenceInitialTriggerEntry ?? true;

  /// Enable initial trigger evaluation for geofences on registration.
  /// Defaults to `true`.
  bool get geofenceInitialTrigger => _geofenceInitialTrigger ?? true;

  /// The radius (in meters) for proximity-based geofence loading.
  /// Only geofences within this distance are actively registered with the OS.
  /// Defaults to `1000`.
  int get geofenceProximityRadius => _geofenceProximityRadius ?? 1000;

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
  bool get geofenceModeHighAccuracy => _geofenceModeHighAccuracy ?? false;

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
  int get geofenceExitAccuracyMax => _geofenceExitAccuracyMax ?? -1;

  /// Applies every field [other] explicitly supplied on top of this config,
  /// leaving fields [other] left unset as they are here.
  ///
  /// This mirrors what the platform does with the serialized payload, and
  /// keeps `Tracelet.activeConfig` in step with the values actually persisted
  /// natively after a partial `setConfig()` (#321).
  GeofenceConfig mergedWith(GeofenceConfig other) => GeofenceConfig(
    geofenceInitialTriggerEntry:
        other._geofenceInitialTriggerEntry ?? _geofenceInitialTriggerEntry,
    geofenceInitialTrigger:
        other._geofenceInitialTrigger ?? _geofenceInitialTrigger,
    geofenceProximityRadius:
        other._geofenceProximityRadius ?? _geofenceProximityRadius,
    geofenceModeHighAccuracy:
        other._geofenceModeHighAccuracy ?? _geofenceModeHighAccuracy,
    geofenceExitAccuracyMax:
        other._geofenceExitAccuracyMax ?? _geofenceExitAccuracyMax,
  );

  /// Returns this config with every field pinned to its effective value.
  ///
  /// Used by `ready()`, which establishes a complete native baseline rather
  /// than a partial update — so the platform's own defaults never have to
  /// match Dart's for correctness (#321).
  GeofenceConfig resolved() => GeofenceConfig(
    geofenceInitialTriggerEntry: geofenceInitialTriggerEntry,
    geofenceInitialTrigger: geofenceInitialTrigger,
    geofenceProximityRadius: geofenceProximityRadius,
    geofenceModeHighAccuracy: geofenceModeHighAccuracy,
    geofenceExitAccuracyMax: geofenceExitAccuracyMax,
  );

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (_geofenceInitialTriggerEntry != null)
        'geofenceInitialTriggerEntry': _geofenceInitialTriggerEntry,
      if (_geofenceInitialTrigger != null)
        'geofenceInitialTrigger': _geofenceInitialTrigger,
      if (_geofenceProximityRadius != null)
        'geofenceProximityRadius': _geofenceProximityRadius,
      if (_geofenceModeHighAccuracy != null)
        'geofenceModeHighAccuracy': _geofenceModeHighAccuracy,
      if (_geofenceExitAccuracyMax != null)
        'geofenceExitAccuracyMax': _geofenceExitAccuracyMax,
    };
  }

  /// Converts to Pigeon [TlGeofenceConfig].
  TlGeofenceConfig toTlConfig() => TlGeofenceConfig(
    geofenceInitialTriggerEntry: _geofenceInitialTriggerEntry,
    geofenceProximityRadius: _geofenceProximityRadius,
    geofenceInitialTrigger: _geofenceInitialTrigger,
    geofenceModeHighAccuracy: _geofenceModeHighAccuracy,
    geofenceExitAccuracyMax: _geofenceExitAccuracyMax,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeofenceConfig &&
          runtimeType == other.runtimeType &&
          _geofenceInitialTriggerEntry == other._geofenceInitialTriggerEntry &&
          _geofenceInitialTrigger == other._geofenceInitialTrigger &&
          _geofenceProximityRadius == other._geofenceProximityRadius &&
          _geofenceModeHighAccuracy == other._geofenceModeHighAccuracy &&
          _geofenceExitAccuracyMax == other._geofenceExitAccuracyMax;

  @override
  int get hashCode => Object.hash(
    _geofenceInitialTriggerEntry,
    _geofenceInitialTrigger,
    _geofenceProximityRadius,
    _geofenceModeHighAccuracy,
    _geofenceExitAccuracyMax,
  );
}

@immutable
/// Configuration for the local SQLite persistence layer.
class PersistenceConfig {
  /// Creates a new [PersistenceConfig] with optional overrides.
  const PersistenceConfig({
    int? maxDaysToPersist,
    int? maxRecordsToPersist,
    PersistMode? persistMode,
    bool? disableProviderChangeRecord,
  }) : _maxDaysToPersist = maxDaysToPersist,
       _maxRecordsToPersist = maxRecordsToPersist,
       _persistMode = persistMode,
       _disableProviderChangeRecord = disableProviderChangeRecord;

  /// Creates a [PersistenceConfig] from a map.
  factory PersistenceConfig.fromMap(Map<String, Object?> map) {
    return PersistenceConfig(
      maxDaysToPersist: map.containsKey('maxDaysToPersist')
          ? ensureInt(map['maxDaysToPersist'], fallback: 1)
          : null,
      maxRecordsToPersist: map.containsKey('maxRecordsToPersist')
          ? ensureInt(map['maxRecordsToPersist'], fallback: -1)
          : null,
      persistMode: map.containsKey('persistMode')
          ? PersistMode.values[ensureInt(
              map['persistMode'],
              fallback: 0,
            ).clamp(0, PersistMode.values.length - 1)]
          : null,
      disableProviderChangeRecord:
          map.containsKey('disableProviderChangeRecord')
          ? ensureBool(map['disableProviderChangeRecord'], fallback: false)
          : null,
    );
  }

  // Backing fields. `null` means "the caller did not provide this",
  // which keeps the field out of the wire payload (#321). The getters
  // below resolve each one to its documented default.
  final int? _maxDaysToPersist;
  final int? _maxRecordsToPersist;
  final PersistMode? _persistMode;
  final bool? _disableProviderChangeRecord;

  /// The maximum number of days to retain tracked locations and geofence events in the database.
  /// Set to `-1` for unlimited retention. Defaults to `1`.
  int get maxDaysToPersist => _maxDaysToPersist ?? 1;

  /// The maximum number of location records to keep in the database.
  /// Set to `-1` for unlimited. Defaults to `-1`.
  int get maxRecordsToPersist => _maxRecordsToPersist ?? -1;

  /// The tracking data persistence mode.
  /// Defaults to [PersistMode.all].
  PersistMode get persistMode => _persistMode ?? PersistMode.all;

  /// Skip writing a database record when location providers change (e.g. GPS disabled/enabled).
  /// Defaults to `false`.
  bool get disableProviderChangeRecord => _disableProviderChangeRecord ?? false;

  /// Applies every field [other] explicitly supplied on top of this config,
  /// leaving fields [other] left unset as they are here.
  ///
  /// This mirrors what the platform does with the serialized payload, and
  /// keeps `Tracelet.activeConfig` in step with the values actually persisted
  /// natively after a partial `setConfig()` (#321).
  PersistenceConfig mergedWith(PersistenceConfig other) => PersistenceConfig(
    maxDaysToPersist: other._maxDaysToPersist ?? _maxDaysToPersist,
    maxRecordsToPersist: other._maxRecordsToPersist ?? _maxRecordsToPersist,
    persistMode: other._persistMode ?? _persistMode,
    disableProviderChangeRecord:
        other._disableProviderChangeRecord ?? _disableProviderChangeRecord,
  );

  /// Returns this config with every field pinned to its effective value.
  ///
  /// Used by `ready()`, which establishes a complete native baseline rather
  /// than a partial update — so the platform's own defaults never have to
  /// match Dart's for correctness (#321).
  PersistenceConfig resolved() => PersistenceConfig(
    maxDaysToPersist: maxDaysToPersist,
    maxRecordsToPersist: maxRecordsToPersist,
    persistMode: persistMode,
    disableProviderChangeRecord: disableProviderChangeRecord,
  );

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (_maxDaysToPersist != null) 'maxDaysToPersist': _maxDaysToPersist,
      if (_maxRecordsToPersist != null)
        'maxRecordsToPersist': _maxRecordsToPersist,
      if (_persistMode != null) 'persistMode': _persistMode.index,
      if (_disableProviderChangeRecord != null)
        'disableProviderChangeRecord': _disableProviderChangeRecord,
    };
  }

  /// Converts to Pigeon [TlPersistenceConfig].
  TlPersistenceConfig toTlConfig() => TlPersistenceConfig(
    persistMode: _persistMode == null
        ? null
        : TlPersistMode.values[_persistMode.index],
    maxDaysToPersist: _maxDaysToPersist,
    maxRecordsToPersist: _maxRecordsToPersist,
    disableProviderChangeRecord: _disableProviderChangeRecord,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistenceConfig &&
          runtimeType == other.runtimeType &&
          _maxDaysToPersist == other._maxDaysToPersist &&
          _maxRecordsToPersist == other._maxRecordsToPersist &&
          _persistMode == other._persistMode &&
          _disableProviderChangeRecord == other._disableProviderChangeRecord;

  @override
  int get hashCode => Object.hash(
    _maxDaysToPersist,
    _maxRecordsToPersist,
    _persistMode,
    _disableProviderChangeRecord,
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
