import 'package:meta/meta.dart';
import 'package:tracelet/src/models/_helpers.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

/// A diagnostic warning detected by [HealthCheck].
///
/// Warnings are automatically computed from the health check data to
/// surface conditions that may degrade tracking quality.
enum HealthWarning {
  /// Location permission is not granted (denied or not determined).
  locationPermissionDenied,

  /// Location permission is permanently denied — the user must manually
  /// enable it in system settings.
  locationPermissionDeniedForever,

  /// Device-level location services are disabled.
  locationServicesDisabled,

  /// The device is in low-power / power-save mode, which may throttle
  /// background activity.
  powerSaveMode,

  /// The device manufacturer is known to aggressively kill background apps.
  aggressiveOem,

  /// The app is NOT exempt from battery optimizations (Android).
  ///
  /// Background tracking may be killed by the OS.
  batteryOptimizationsNotIgnored,

  /// Location accuracy authorization is reduced (iOS 14+).
  ///
  /// The app only receives approximate location (~5 km radius).
  reducedAccuracy,

  /// No accelerometer detected.
  ///
  /// Motion detection relies on the accelerometer. Without it,
  /// stationary/moving transitions cannot be detected automatically.
  noAccelerometer,

  /// No significant-motion sensor detected.
  ///
  /// The significant-motion sensor is used for low-power wake-from-
  /// stationary detection. Without it, the plugin falls back to
  /// periodic wake-ups.
  noSignificantMotion,

  /// Motion / activity recognition permission is denied.
  ///
  /// Activity-classified motion transitions (walking, driving, etc.)
  /// are unavailable. The plugin falls back to accelerometer-only mode.
  motionPermissionDenied,

  /// Mock / spoofed locations have been detected by the provider.
  mockLocationsDetected,

  /// Only "when in use" location permission is granted.
  ///
  /// Background tracking requires "always" authorization and may not
  /// work reliably with only foreground permission.
  locationPermissionOnlyWhenInUse,
}

/// Human-readable descriptions for each [HealthWarning].
extension HealthWarningDescription on HealthWarning {
  /// A short, user-facing description of this warning.
  String get description => switch (this) {
    HealthWarning.locationPermissionDenied =>
      'Location permission is not granted',
    HealthWarning.locationPermissionDeniedForever =>
      'Location permission permanently denied — enable in Settings',
    HealthWarning.locationServicesDisabled =>
      'Device location services are turned off',
    HealthWarning.powerSaveMode =>
      'Power Save mode is ON — may throttle background tracking',
    HealthWarning.aggressiveOem =>
      'Device manufacturer may kill background apps',
    HealthWarning.batteryOptimizationsNotIgnored =>
      'App is not exempt from battery optimizations',
    HealthWarning.reducedAccuracy =>
      'Location accuracy is reduced (~5 km radius)',
    HealthWarning.noAccelerometer =>
      'No accelerometer — motion detection unavailable',
    HealthWarning.noSignificantMotion =>
      'No significant-motion sensor — wake-from-stationary degraded',
    HealthWarning.motionPermissionDenied =>
      'Motion/activity recognition permission denied',
    HealthWarning.mockLocationsDetected => 'Mock/spoofed locations detected',
    HealthWarning.locationPermissionOnlyWhenInUse =>
      'Only "when in use" permission — background tracking may not work',
  };
}

/// A single-call diagnostic snapshot of the plugin's operational health.
///
/// Returned by `Tracelet.getHealth()`. Aggregates tracking state, permissions,
/// provider availability, battery/OEM status, sensor availability, and
/// database metrics into one typed object with computed [warnings].
///
/// ```dart
/// final health = await Tracelet.getHealth();
///
/// if (health.warnings.isNotEmpty) {
///   for (final warning in health.warnings) {
///     print('⚠ $warning');
///   }
/// }
///
/// print('Tracking: ${health.trackingEnabled}');
/// print('Permission: ${health.locationPermission}');
/// print('Pending locations: ${health.locationCount}');
/// ```
@immutable
class HealthCheck {
  /// Creates a new [HealthCheck].
  ///
  /// Prefer using [HealthCheck.fromMaps] to construct from raw platform data.
  const HealthCheck({
    // Tracking state
    required this.trackingEnabled,
    required this.trackingMode,
    required this.timestamp,
    this.isMoving = false,
    this.odometer = 0.0,
    this.schedulerEnabled = false,
    this.didLaunchInBackground = false,
    this.didDeviceReboot = false,
    // Permissions
    this.locationPermission = AuthorizationStatus.notDetermined,
    this.motionPermission = 0,
    this.accuracyAuthorization = AccuracyAuthorization.full,
    // Provider
    this.locationServicesEnabled = false,
    this.gpsEnabled = false,
    this.networkEnabled = false,
    // Battery & power
    this.isPowerSaveMode = false,
    this.isIgnoringBatteryOptimizations = false,
    // OEM
    this.manufacturer = '',
    this.model = '',
    this.isAggressiveOem = false,
    this.aggressionRating = 0,
    // Sensors
    this.hasAccelerometer = false,
    this.hasGyroscope = false,
    this.hasMagnetometer = false,
    this.hasSignificantMotion = false,
    // Database
    this.locationCount = 0,
    // Device
    this.platform = '',
    this.osVersion = '',
    // Diagnostics
    this.mockLocationsDetected = false,
    this.warnings = const <HealthWarning>[],
  });

  // ---------------------------------------------------------------------------
  // Factory
  // ---------------------------------------------------------------------------

  /// Creates a [HealthCheck] by aggregating raw platform maps.
  ///
  /// This is the primary constructor used by `Tracelet.getHealth()`.
  /// It accepts the raw results from multiple platform calls and computes
  /// warnings automatically.
  ///
  /// Parameters:
  /// - [state] — result of `getState()` (State.toMap())
  /// - [provider] — result of `getProviderState()` (ProviderChangeEvent.toMap())
  /// - [settingsHealth] — result of `getSettingsHealth()`
  /// - [sensors] — result of `getSensors()` (Sensors.toMap())
  /// - [deviceInfo] — result of `getDeviceInfo()` (DeviceInfo.toMap())
  /// - [isPowerSave] — result of `isPowerSaveMode()`
  /// - [ignoringBatteryOpt] — result of `isIgnoringBatteryOptimizations()`
  /// - [locationPermissionStatus] — result of `getPermissionStatus()`
  /// - [motionPermissionStatus] — result of `getMotionPermissionStatus()`
  /// - [dbCount] — result of `getCount()`
  factory HealthCheck.fromMaps({
    required Map<String, Object?> state,
    required Map<String, Object?> provider,
    required Map<String, Object?> settingsHealth,
    required Map<String, Object?> sensors,
    required Map<String, Object?> deviceInfo,
    required bool isPowerSave,
    required bool ignoringBatteryOpt,
    required int locationPermissionStatus,
    required int motionPermissionStatus,
    required int dbCount,
  }) {
    // Parse tracking state.
    final enabled = ensureBool(state['enabled'], fallback: false);
    final trackingModeIndex = ensureInt(
      state['trackingMode'],
      fallback: 0,
    ).clamp(0, TrackingMode.values.length - 1);
    final trackingMode = TrackingMode.values[trackingModeIndex];
    final isMoving = ensureBool(
      state['isMoving'] ?? state['is_moving'],
      fallback: false,
    );
    final odometer = ensureDouble(state['odometer'], fallback: 0);
    final schedulerEnabled = ensureBool(
      state['schedulerEnabled'],
      fallback: false,
    );
    final didLaunchInBackground = ensureBool(
      state['didLaunchInBackground'],
      fallback: false,
    );
    final didDeviceReboot = ensureBool(
      state['didDeviceReboot'],
      fallback: false,
    );

    // Parse provider state.
    final locationServicesEnabled = ensureBool(
      provider['enabled'],
      fallback: false,
    );
    final gpsEnabled = ensureBool(provider['gps'], fallback: false);
    final networkEnabled = ensureBool(provider['network'], fallback: false);
    final accuracyAuthIndex = ensureInt(
      provider['accuracyAuthorization'],
      fallback: 0,
    ).clamp(0, AccuracyAuthorization.values.length - 1);
    final accuracyAuth = AccuracyAuthorization.values[accuracyAuthIndex];
    final mockDetected = ensureBool(
      provider['mockLocationsDetected'],
      fallback: false,
    );

    // Parse permission status.
    final locationPermClamp = locationPermissionStatus.clamp(
      0,
      AuthorizationStatus.values.length - 1,
    );
    final locationPerm = AuthorizationStatus.values[locationPermClamp];

    // Parse OEM health.
    final mfr = ensureString(settingsHealth['manufacturer']);
    final mdl = ensureString(settingsHealth['model'] ?? deviceInfo['model']);
    final aggressiveOem = ensureBool(
      settingsHealth['isAggressiveOem'],
      fallback: false,
    );
    final aggressionRating = ensureInt(
      settingsHealth['aggressionRating'],
      fallback: 0,
    );

    // Parse sensors.
    final accel = ensureBool(sensors['accelerometer'], fallback: false);
    final gyro = ensureBool(sensors['gyroscope'], fallback: false);
    final mag = ensureBool(sensors['magnetometer'], fallback: false);
    final sigMotion = ensureBool(sensors['significantMotion'], fallback: false);

    // Parse device info.
    final platformStr = ensureString(
      deviceInfo['platform'] ?? provider['platform'],
    );
    final osVersion = ensureString(deviceInfo['version']);

    // Compute warnings.
    final warnings = _computeWarnings(
      locationPerm: locationPerm,
      locationServicesEnabled: locationServicesEnabled,
      isPowerSave: isPowerSave,
      aggressiveOem: aggressiveOem,
      ignoringBatteryOpt: ignoringBatteryOpt,
      accuracyAuth: accuracyAuth,
      hasAccelerometer: accel,
      hasSignificantMotion: sigMotion,
      motionPermission: motionPermissionStatus,
      mockDetected: mockDetected,
    );

    return HealthCheck(
      trackingEnabled: enabled,
      trackingMode: trackingMode,
      isMoving: isMoving,
      odometer: odometer,
      schedulerEnabled: schedulerEnabled,
      didLaunchInBackground: didLaunchInBackground,
      didDeviceReboot: didDeviceReboot,
      locationPermission: locationPerm,
      motionPermission: motionPermissionStatus,
      accuracyAuthorization: accuracyAuth,
      locationServicesEnabled: locationServicesEnabled,
      gpsEnabled: gpsEnabled,
      networkEnabled: networkEnabled,
      isPowerSaveMode: isPowerSave,
      isIgnoringBatteryOptimizations: ignoringBatteryOpt,
      manufacturer: mfr,
      model: mdl,
      isAggressiveOem: aggressiveOem,
      aggressionRating: aggressionRating,
      hasAccelerometer: accel,
      hasGyroscope: gyro,
      hasMagnetometer: mag,
      hasSignificantMotion: sigMotion,
      locationCount: dbCount,
      platform: platformStr,
      osVersion: osVersion,
      mockLocationsDetected: mockDetected,
      timestamp: DateTime.now().toUtc(),
      warnings: warnings,
    );
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  /// Creates a [HealthCheck] from a serialized map.
  factory HealthCheck.fromMap(Map<String, Object?> map) {
    final warningsList = <HealthWarning>[];
    final rawWarnings = map['warnings'];
    if (rawWarnings is List) {
      for (final w in rawWarnings) {
        final index = ensureInt(w, fallback: -1);
        if (index >= 0 && index < HealthWarning.values.length) {
          warningsList.add(HealthWarning.values[index]);
        }
      }
    }

    final trackingModeIndex = ensureInt(
      map['trackingMode'],
      fallback: 0,
    ).clamp(0, TrackingMode.values.length - 1);

    final locationPermIndex = ensureInt(
      map['locationPermission'],
      fallback: 0,
    ).clamp(0, AuthorizationStatus.values.length - 1);

    final accuracyAuthIndex = ensureInt(
      map['accuracyAuthorization'],
      fallback: 0,
    ).clamp(0, AccuracyAuthorization.values.length - 1);

    return HealthCheck(
      trackingEnabled: ensureBool(map['trackingEnabled'], fallback: false),
      trackingMode: TrackingMode.values[trackingModeIndex],
      isMoving: ensureBool(map['isMoving'], fallback: false),
      odometer: ensureDouble(map['odometer'], fallback: 0),
      schedulerEnabled: ensureBool(map['schedulerEnabled'], fallback: false),
      didLaunchInBackground: ensureBool(
        map['didLaunchInBackground'],
        fallback: false,
      ),
      didDeviceReboot: ensureBool(map['didDeviceReboot'], fallback: false),
      locationPermission: AuthorizationStatus.values[locationPermIndex],
      motionPermission: ensureInt(map['motionPermission'], fallback: 0),
      accuracyAuthorization: AccuracyAuthorization.values[accuracyAuthIndex],
      locationServicesEnabled: ensureBool(
        map['locationServicesEnabled'],
        fallback: false,
      ),
      gpsEnabled: ensureBool(map['gpsEnabled'], fallback: false),
      networkEnabled: ensureBool(map['networkEnabled'], fallback: false),
      isPowerSaveMode: ensureBool(map['isPowerSaveMode'], fallback: false),
      isIgnoringBatteryOptimizations: ensureBool(
        map['isIgnoringBatteryOptimizations'],
        fallback: false,
      ),
      manufacturer: ensureString(map['manufacturer']),
      model: ensureString(map['model']),
      isAggressiveOem: ensureBool(map['isAggressiveOem'], fallback: false),
      aggressionRating: ensureInt(map['aggressionRating'], fallback: 0),
      hasAccelerometer: ensureBool(map['hasAccelerometer'], fallback: false),
      hasGyroscope: ensureBool(map['hasGyroscope'], fallback: false),
      hasMagnetometer: ensureBool(map['hasMagnetometer'], fallback: false),
      hasSignificantMotion: ensureBool(
        map['hasSignificantMotion'],
        fallback: false,
      ),
      locationCount: ensureInt(map['locationCount'], fallback: 0),
      platform: ensureString(map['platform']),
      osVersion: ensureString(map['osVersion']),
      mockLocationsDetected: ensureBool(
        map['mockLocationsDetected'],
        fallback: false,
      ),
      timestamp:
          DateTime.tryParse(ensureString(map['timestamp']))?.toUtc() ??
          DateTime.now().toUtc(),
      warnings: warningsList,
    );
  }

  // ---------------------------------------------------------------------------
  // Tracking State
  // ---------------------------------------------------------------------------

  /// Whether location tracking is currently active.
  final bool trackingEnabled;

  /// The current tracking mode (location or geofences).
  final TrackingMode trackingMode;

  /// Whether the device is currently in a moving state.
  final bool isMoving;

  /// Cumulative distance (in meters) since tracking started.
  final double odometer;

  /// Whether schedule-based tracking is active.
  final bool schedulerEnabled;

  /// Whether the app was launched in the background (boot, scheduled task).
  final bool didLaunchInBackground;

  /// Whether the device recently rebooted and tracking was restarted.
  final bool didDeviceReboot;

  // ---------------------------------------------------------------------------
  // Permissions
  // ---------------------------------------------------------------------------

  /// Current location authorization status.
  final AuthorizationStatus locationPermission;

  /// Motion / activity recognition permission status, as a
  /// [MotionAuthorizationStatus] index.
  ///
  /// - `0` — [MotionAuthorizationStatus.notDetermined]
  /// - `1` — [MotionAuthorizationStatus.granted]
  /// - `2` — [MotionAuthorizationStatus.deniedForever]
  ///
  /// Note this is **not** CoreMotion's `CMAuthorizationStatus` scale, which
  /// orders the cases differently and has a separate `restricted` value. This
  /// doc comment previously described that scale, and callers that decoded the
  /// int accordingly reported a granted permission as "Restricted".
  ///
  /// Prefer [motionAuthorization], which returns the typed value so the
  /// mapping cannot be misread.
  final int motionPermission;

  /// [motionPermission] decoded into its source enum.
  ///
  /// Returns `null` if the value is outside the enum's range, which can happen
  /// when a report is deserialized from a newer or malformed payload.
  MotionAuthorizationStatus? get motionAuthorization =>
      motionPermission >= 0 &&
          motionPermission < MotionAuthorizationStatus.values.length
      ? MotionAuthorizationStatus.values[motionPermission]
      : null;

  /// Accuracy authorization level (iOS 14+).
  ///
  /// On Android, always [AccuracyAuthorization.full].
  final AccuracyAuthorization accuracyAuthorization;

  // ---------------------------------------------------------------------------
  // Provider
  // ---------------------------------------------------------------------------

  /// Whether device-level location services are enabled.
  final bool locationServicesEnabled;

  /// Whether the GPS provider is available (Android only).
  final bool gpsEnabled;

  /// Whether the network location provider is available (Android only).
  final bool networkEnabled;

  // ---------------------------------------------------------------------------
  // Battery & Power
  // ---------------------------------------------------------------------------

  /// Whether the device is in low-power / power-save mode.
  final bool isPowerSaveMode;

  /// Whether the app is exempt from battery optimizations (Android).
  ///
  /// Always `true` on iOS (no equivalent restriction).
  final bool isIgnoringBatteryOptimizations;

  // ---------------------------------------------------------------------------
  // OEM Health
  // ---------------------------------------------------------------------------

  /// Device manufacturer (e.g. `'Samsung'`, `'Apple'`).
  final String manufacturer;

  /// Device model (e.g. `'SM-S911B'`, `'iPhone'`).
  final String model;

  /// Whether this OEM is known to aggressively kill background apps.
  final bool isAggressiveOem;

  /// OEM aggression rating (0–5) per dontkillmyapp.com criteria.
  ///
  /// - `0` — No known issues (Apple, Google Pixel)
  /// - `1–2` — Minor issues
  /// - `3–4` — Significant issues (Samsung, OnePlus)
  /// - `5` — Severe issues (Huawei, Xiaomi)
  final int aggressionRating;

  // ---------------------------------------------------------------------------
  // Sensors
  // ---------------------------------------------------------------------------

  /// Whether the device has an accelerometer.
  final bool hasAccelerometer;

  /// Whether the device has a gyroscope.
  final bool hasGyroscope;

  /// Whether the device has a magnetometer.
  final bool hasMagnetometer;

  /// Whether the device has a significant-motion trigger sensor.
  final bool hasSignificantMotion;

  // ---------------------------------------------------------------------------
  // Database
  // ---------------------------------------------------------------------------

  /// Number of locations currently stored in the database.
  final int locationCount;

  // ---------------------------------------------------------------------------
  // Device
  // ---------------------------------------------------------------------------

  /// Platform identifier (`'android'`, `'ios'`, or `'web'`).
  final String platform;

  /// OS version string (e.g. `'14'`, `'17.4'`).
  final String osVersion;

  // ---------------------------------------------------------------------------
  // Diagnostics
  // ---------------------------------------------------------------------------

  /// Whether mock/spoofed locations have been detected.
  final bool mockLocationsDetected;

  /// When this health check was taken (UTC).
  final DateTime timestamp;

  /// Computed diagnostic warnings.
  ///
  /// Empty when everything is healthy. Each [HealthWarning] identifies a
  /// specific condition that may degrade tracking quality.
  final List<HealthWarning> warnings;

  /// Computes diagnostic warnings from health check data.
  static List<HealthWarning> _computeWarnings({
    required AuthorizationStatus locationPerm,
    required bool locationServicesEnabled,
    required bool isPowerSave,
    required bool aggressiveOem,
    required bool ignoringBatteryOpt,
    required AccuracyAuthorization accuracyAuth,
    required bool hasAccelerometer,
    required bool hasSignificantMotion,
    required int motionPermission,
    required bool mockDetected,
  }) {
    final warnings = <HealthWarning>[];

    // Location permission checks.
    if (locationPerm == AuthorizationStatus.deniedForever) {
      warnings.add(HealthWarning.locationPermissionDeniedForever);
    } else if (locationPerm == AuthorizationStatus.denied ||
        locationPerm == AuthorizationStatus.notDetermined) {
      warnings.add(HealthWarning.locationPermissionDenied);
    } else if (locationPerm == AuthorizationStatus.whenInUse) {
      warnings.add(HealthWarning.locationPermissionOnlyWhenInUse);
    }

    // Location services.
    if (!locationServicesEnabled) {
      warnings.add(HealthWarning.locationServicesDisabled);
    }

    // Power management.
    if (isPowerSave) {
      warnings.add(HealthWarning.powerSaveMode);
    }
    if (aggressiveOem) {
      warnings.add(HealthWarning.aggressiveOem);
    }
    if (!ignoringBatteryOpt) {
      warnings.add(HealthWarning.batteryOptimizationsNotIgnored);
    }

    // Accuracy.
    if (accuracyAuth == AccuracyAuthorization.reduced) {
      warnings.add(HealthWarning.reducedAccuracy);
    }

    // Sensors.
    if (!hasAccelerometer) {
      warnings.add(HealthWarning.noAccelerometer);
    }
    if (!hasSignificantMotion) {
      warnings.add(HealthWarning.noSignificantMotion);
    }

    // Motion permission (2 = denied on both platforms).
    if (motionPermission == 2) {
      warnings.add(HealthWarning.motionPermissionDenied);
    }

    // Mock locations.
    if (mockDetected) {
      warnings.add(HealthWarning.mockLocationsDetected);
    }

    return List<HealthWarning>.unmodifiable(warnings);
  }

  /// Serializes this health check to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      // Tracking state
      'trackingEnabled': trackingEnabled,
      'trackingMode': trackingMode.index,
      'isMoving': isMoving,
      'odometer': odometer,
      'schedulerEnabled': schedulerEnabled,
      'didLaunchInBackground': didLaunchInBackground,
      'didDeviceReboot': didDeviceReboot,
      // Permissions
      'locationPermission': locationPermission.index,
      'motionPermission': motionPermission,
      'accuracyAuthorization': accuracyAuthorization.index,
      // Provider
      'locationServicesEnabled': locationServicesEnabled,
      'gpsEnabled': gpsEnabled,
      'networkEnabled': networkEnabled,
      // Battery & power
      'isPowerSaveMode': isPowerSaveMode,
      'isIgnoringBatteryOptimizations': isIgnoringBatteryOptimizations,
      // OEM
      'manufacturer': manufacturer,
      'model': model,
      'isAggressiveOem': isAggressiveOem,
      'aggressionRating': aggressionRating,
      // Sensors
      'hasAccelerometer': hasAccelerometer,
      'hasGyroscope': hasGyroscope,
      'hasMagnetometer': hasMagnetometer,
      'hasSignificantMotion': hasSignificantMotion,
      // Database
      'locationCount': locationCount,
      // Device
      'platform': platform,
      'osVersion': osVersion,
      // Diagnostics
      'mockLocationsDetected': mockLocationsDetected,
      'timestamp': timestamp.toIso8601String(),
      'warnings': warnings.map((w) => w.index).toList(),
    };
  }

  // ---------------------------------------------------------------------------
  // Convenience
  // ---------------------------------------------------------------------------

  /// Whether the health check has any warnings.
  bool get hasWarnings => warnings.isNotEmpty;

  /// Whether the health check is completely healthy (no warnings).
  bool get isHealthy => warnings.isEmpty;

  /// The number of warnings detected.
  int get warningCount => warnings.length;

  /// Whether the plugin has adequate permissions for background tracking.
  ///
  /// Returns `true` when location permission is [AuthorizationStatus.always]
  /// and location services are enabled.
  bool get hasBackgroundPermission =>
      locationPermission == AuthorizationStatus.always &&
      locationServicesEnabled;

  @override
  String toString() =>
      'HealthCheck('
      'tracking: $trackingEnabled, '
      'mode: ${trackingMode.name}, '
      'permission: ${locationPermission.name}, '
      'locationServices: $locationServicesEnabled, '
      'powerSave: $isPowerSaveMode, '
      'aggressiveOem: $isAggressiveOem, '
      'locations: $locationCount, '
      'warnings: ${warnings.length}'
      ')';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HealthCheck &&
          runtimeType == other.runtimeType &&
          trackingEnabled == other.trackingEnabled &&
          trackingMode == other.trackingMode &&
          isMoving == other.isMoving &&
          odometer == other.odometer &&
          schedulerEnabled == other.schedulerEnabled &&
          locationPermission == other.locationPermission &&
          motionPermission == other.motionPermission &&
          accuracyAuthorization == other.accuracyAuthorization &&
          locationServicesEnabled == other.locationServicesEnabled &&
          gpsEnabled == other.gpsEnabled &&
          networkEnabled == other.networkEnabled &&
          isPowerSaveMode == other.isPowerSaveMode &&
          isIgnoringBatteryOptimizations ==
              other.isIgnoringBatteryOptimizations &&
          manufacturer == other.manufacturer &&
          isAggressiveOem == other.isAggressiveOem &&
          aggressionRating == other.aggressionRating &&
          hasAccelerometer == other.hasAccelerometer &&
          hasSignificantMotion == other.hasSignificantMotion &&
          locationCount == other.locationCount &&
          platform == other.platform &&
          mockLocationsDetected == other.mockLocationsDetected;

  @override
  int get hashCode => Object.hash(
    trackingEnabled,
    trackingMode,
    isMoving,
    locationPermission,
    motionPermission,
    accuracyAuthorization,
    locationServicesEnabled,
    isPowerSaveMode,
    isAggressiveOem,
    aggressionRating,
    hasAccelerometer,
    hasSignificantMotion,
    locationCount,
    platform,
    mockLocationsDetected,
  );
}
