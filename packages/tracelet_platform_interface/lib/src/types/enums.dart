/// Desired accuracy levels for location requests.
enum DesiredAccuracy {
  /// Best possible accuracy (GPS). Highest battery usage.
  high,

  /// Approximately 100m accuracy. Medium battery usage.
  medium,

  /// Approximately 1km accuracy. Low battery usage.
  low,

  /// Approximately 3km accuracy. Minimal battery usage.
  veryLow,

  /// No active location gathering; use only passive/cached locations.
  passive,
}

/// Log levels for the Tracelet logger.
enum LogLevel {
  /// Logging disabled.
  off,

  /// Only errors.
  error,

  /// Errors and warnings.
  warning,

  /// Errors, warnings, and informational.
  info,

  /// Errors, warnings, info, and debug.
  debug,

  /// Everything — maximum detail.
  verbose,
}

/// Activity types detected by the motion detection engine.
enum ActivityType {
  /// Device is stationary.
  still,

  /// User is walking.
  walking,

  /// User is running.
  running,

  /// User is on foot (walking or running, not differentiated).
  onFoot,

  /// User is in a vehicle.
  inVehicle,

  /// User is on a bicycle.
  onBicycle,

  /// Activity cannot be determined.
  unknown,
}

/// Confidence level for activity detection.
enum ActivityConfidence {
  /// Low confidence.
  low,

  /// Medium confidence.
  medium,

  /// High confidence.
  high,
}

/// Tracking modes.
enum TrackingMode {
  /// Standard location tracking mode.
  location,

  /// Geofences-only mode (no continuous location tracking).
  geofences,

  /// Periodic one-shot location mode.
  ///
  /// Instead of continuous GPS updates, the engine wakes up every
  /// `GeoConfig.periodicLocationInterval` seconds, performs a single
  /// `getCurrentPosition()` fix, dispatches the result, and immediately
  /// turns the location provider off again.
  ///
  /// This dramatically reduces battery usage and minimises GPS-icon /
  /// blue-arrow visibility to ~5–10 seconds per fix.
  periodic,
}

/// Geofence transition actions.
enum GeofenceAction {
  /// Device entered the geofence.
  enter,

  /// Device exited the geofence.
  exit,

  /// Device is dwelling inside the geofence.
  dwell,
}

/// Authorization status for location permissions.
///
/// Returned by [Tracelet.getLocationAuthorization] and
/// [Tracelet.requestLocationAuthorization]. The raw integer codes
/// exchanged over the platform channel are:
/// `0` notDetermined, `1` denied, `2` whenInUse, `3` always, `4` deniedForever.
enum AuthorizationStatus {
  /// Permission has not been requested.
  notDetermined,

  /// Permission denied by user (can ask again on Android).
  denied,

  /// Authorized for when-in-use (foreground) only.
  whenInUse,

  /// Authorized for always (background) access.
  always,

  /// Permanently denied — user must open Settings manually.
  deniedForever,
}

/// Authorization status for notification permissions.
///
/// Returned by [Tracelet.getNotificationAuthorization] and
/// [Tracelet.requestNotificationAuthorization]. Semantically identical
/// to [AuthorizationStatus] but modelled as a separate type to make
/// call-sites self-documenting and to avoid implicit index aliasing.
///
/// Raw channel values: `0` notDetermined, `1` denied, `3` granted, `4` deniedForever.
/// (`2` is unused for notifications.)
enum NotificationAuthorizationStatus {
  /// Notification permission has not been requested.
  notDetermined,

  /// Denied — the user dismissed the dialog without granting.
  denied,

  /// Granted — notifications are enabled.
  ///
  /// On Android < 13 and on iOS (when authorized), this is always returned.
  granted,

  /// Permanently denied — the user chose "Don't ask again", or the
  /// permission was restricted by device policy. Must open Settings.
  deniedForever,
}

/// Authorization status for motion & fitness / activity recognition
/// permissions.
///
/// Returned by [Tracelet.getMotionAuthorization] and
/// [Tracelet.requestMotionAuthorization].
///
/// Raw channel values: `0` notDetermined, `3` granted, `4` deniedForever.
/// (`1` denied is not used on iOS; Android only uses `0`, `3`, and `4`.)
enum MotionAuthorizationStatus {
  /// Permission has not been requested.
  notDetermined,

  /// Granted — motion/activity recognition is enabled.
  ///
  /// On Android < 10 (API < 29) no runtime permission is required;
  /// this value is always returned in that case.
  granted,

  /// Permanently denied — must open Settings.
  ///
  /// On iOS: CMAuthorizationStatus.denied or .restricted.
  /// On Android: permission denied with "don't ask again".
  deniedForever,
}

/// Temporary full accuracy authorization status (iOS 14+).
///
/// Returned by [Tracelet.requestTemporaryFullAccuracyAuthorization].
/// On Android and iOS < 14, always returns [FullAccuracyStatus.full].
enum FullAccuracyStatus {
  /// Full precision location is authorized.
  full,

  /// Location is returned at reduced (approximate) precision.
  /// The user has not granted temporary full accuracy for the given purpose.
  reduced,
}

/// Accuracy authorization (iOS 14+).
enum AccuracyAuthorization {
  /// Full precision location.
  full,

  /// Reduced (approximate) location.
  reduced,
}

/// HTTP method for sync.
enum HttpMethod {
  /// HTTP POST.
  post,

  /// HTTP PUT.
  put,
}

/// Sort order for location queries.
enum LocationOrderDirection {
  /// Ascending (oldest first).
  ascending,

  /// Descending (newest first).
  descending,
}

/// iOS activity type hints for CLLocationManager.
enum LocationActivityType {
  /// General purpose.
  other,

  /// Navigation in an automobile.
  automotiveNavigation,

  /// Navigation on foot.
  otherNavigation,

  /// Fitness activities (walking, running, cycling).
  fitness,

  /// Navigation in an aircraft.
  airborne,
}

/// Which record types to persist to the local database.
enum PersistMode {
  /// Persist all location and geofence records (default).
  all,

  /// Persist only location records.
  location,

  /// Persist only geofence records.
  geofence,

  /// Do not persist any records. Events are still fired.
  none,
}

/// How the location filter handles rejected locations.
enum LocationFilterPolicy {
  /// Smooth / correct rejected locations before recording them.
  adjust,

  /// Silently discard rejected locations.
  ignore,

  /// Discard rejected locations and emit an error event.
  discard,
}

/// Controls the aggressiveness of mock/spoofed location detection.
///
/// Higher levels apply more checks but may increase false positives
/// (e.g. flagging legitimate external GPS receivers).
enum MockDetectionLevel {
  /// No mock detection. All locations accepted unconditionally.
  /// This is the default behavior.
  disabled,

  /// Platform API flag only.
  ///
  /// - **Android**: `Location.isMock()` / `isFromMockProvider()`.
  /// - **iOS 15+**: `CLLocation.sourceInformation?.isSimulatedBySoftware`.
  /// - **iOS < 15 / Web**: No detection (always passes).
  ///
  /// Catches casual spoofing (Developer Options, Fake GPS apps).
  /// Bypassable on rooted/jailbroken devices.
  basic,

  /// Basic + native-side heuristics.
  ///
  /// Additional checks applied on Android:
  /// - **Satellite count**: Mock locations typically report 0 GPS satellites.
  ///   Real outdoor fixes report 4–30. A satellite count of 0 outdoors is
  ///   flagged as suspicious.
  /// - **Elapsed realtime drift**: Compares `Location.elapsedRealtimeNanos`
  ///   against `SystemClock.elapsedRealtimeNanos()`. Large drift (>10 seconds)
  ///   suggests the location timestamp was not generated by the real GPS
  ///   hardware clock.
  ///
  /// Additional checks applied in Dart (all platforms):
  /// - **Timestamp monotonicity**: Location timestamps must be monotonically
  ///   increasing. A backward jump indicates spoofing or replay.
  ///
  /// May produce false positives in edge cases (cold starts, time zone
  /// changes, NTP corrections).
  heuristic,
}

/// The location authorization level to request from the user.
///
/// On iOS this maps directly to the `CLLocationManager` authorization level:
/// - [always] requests "Always" authorization (background tracking).
/// - [whenInUse] requests "When In Use" authorization only.
///
/// On Android this is used to decide whether to request
/// `ACCESS_BACKGROUND_LOCATION` in addition to `ACCESS_FINE_LOCATION`.
enum LocationAuthorizationRequest {
  /// Request "Always" (background) location authorization.
  ///
  /// This is the default and is required for background tracking.
  always,

  /// Request "When In Use" location authorization only.
  ///
  /// Background tracking will not work with this setting on iOS.
  whenInUse,
}

/// Android notification priority levels for the foreground service.
///
/// Maps to `NotificationCompat.PRIORITY_*` constants and
/// `NotificationManager.IMPORTANCE_*` for the notification channel.
enum NotificationPriority {
  /// Minimum priority. Notification may be completely hidden.
  min,

  /// Low priority.
  low,

  /// Default priority.
  defaultPriority,

  /// High priority. May cause a heads-up notification.
  high,

  /// Maximum priority.
  max,
}

/// Hash algorithms for the audit trail chain.
enum HashAlgorithm {
  /// SHA-256 (default). 256-bit digest.
  sha256,

  /// SHA-384. 384-bit digest.
  sha384,

  /// SHA-512. 512-bit digest.
  sha512,
}
