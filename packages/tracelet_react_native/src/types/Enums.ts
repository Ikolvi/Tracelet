// Desired accuracy levels for location requests.
export enum DesiredAccuracy {
  high = 0,
  medium = 1,
  low = 2,
  veryLow = 3,
  passive = 4,
}

// Log levels for the Tracelet logger.
export enum LogLevel {
  off = 0,
  error = 1,
  warning = 2,
  info = 3,
  debug = 4,
  verbose = 5,
}

// Activity types detected by the motion detection engine.
export enum ActivityType {
  still = 'still',
  walking = 'walking',
  running = 'running',
  onFoot = 'on_foot',
  inVehicle = 'in_vehicle',
  onBicycle = 'on_bicycle',
  unknown = 'unknown',
}

// Confidence level for activity detection.
export enum ActivityConfidence {
  low = 0,
  medium = 1,
  high = 2,
}

// Tracking modes.
export enum TrackingMode {
  location = 0,
  geofences = 1,
  periodic = 2,
}

// Geofence transition actions.
export enum GeofenceAction {
  enter = 'ENTER',
  exit = 'EXIT',
  dwell = 'DWELL',
}

// Authorization status for location permissions.
export enum AuthorizationStatus {
  notDetermined = 0,
  denied = 1,
  whenInUse = 2,
  always = 3,
  deniedForever = 4,
}

// Accuracy authorization (iOS 14+).
export enum AccuracyAuthorization {
  full = 0,
  reduced = 1,
}

// HTTP method for sync.
export enum HttpMethod {
  post = 0,
  put = 1,
}

// Sort order for location queries.
export enum LocationOrder {
  asc = 'ASC',
  desc = 'DESC',
}

// iOS activity type hints for CLLocationManager.
export enum LocationActivityType {
  other = 0,
  automotiveNavigation = 1,
  otherNavigation = 2,
  fitness = 3,
  airborne = 4,
}

// Persist mode.
export enum PersistMode {
  all = 2,
  location = 0,
  geofence = 1,
  none = -1,
}

// Location filter policy.
export enum LocationFilterPolicy {
  adjust = 0,
  ignore = 1,
  discard = 2,
}

// Mock detection level.
export enum MockDetectionLevel {
  disabled = 0,
  basic = 1,
  heuristic = 2,
}

// Location authorization request.
export enum LocationAuthorizationRequest {
  always = 'Always',
  whenInUse = 'WhenInUse',
}

// Android notification priority.
export enum NotificationPriority {
  min = -2,
  low = -1,
  defaultPriority = 0,
  high = 1,
  max = 2,
}

// Hash algorithms for audit trail.
export enum HashAlgorithm {
  sha256 = 'SHA-256',
  sha384 = 'SHA-384',
  sha512 = 'SHA-512',
}
