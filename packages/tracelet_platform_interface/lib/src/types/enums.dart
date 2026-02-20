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
enum AuthorizationStatus {
  /// Permission has not been requested.
  notDetermined,

  /// Permission denied by user.
  denied,

  /// Authorized for when-in-use only.
  whenInUse,

  /// Authorized for always (background) access.
  always,

  /// Permanently denied (user chose "Don't ask again").
  deniedForever,
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
enum LocationOrder {
  /// Ascending (oldest first).
  asc,

  /// Descending (newest first).
  desc,
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
