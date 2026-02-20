/// EventChannel path constants for Tracelet.
///
/// These are shared between Dart and native platform implementations.
/// Both Android (Kotlin) and iOS (Swift) must register handlers at these paths.
class TraceletEvents {
  TraceletEvents._();

  /// Base path for all event channels.
  static const String basePath = 'com.tracelet/events';

  /// Fired on every recorded location.
  static const String location = '$basePath/location';

  /// Fired when motion state changes (stationary ↔ moving).
  static const String motionChange = '$basePath/motionchange';

  /// Fired when detected activity type changes (walking, running, etc.).
  static const String activityChange = '$basePath/activitychange';

  /// Fired when location provider state changes (GPS, network, authorization).
  static const String providerChange = '$basePath/providerchange';

  /// Fired on geofence transition (enter, exit, dwell).
  static const String geofence = '$basePath/geofence';

  /// Fired when monitored geofences change (activated/deactivated list).
  static const String geofencesChange = '$basePath/geofenceschange';

  /// Fired at configured heartbeat interval.
  static const String heartbeat = '$basePath/heartbeat';

  /// Fired on HTTP sync attempt (success or failure).
  static const String http = '$basePath/http';

  /// Fired on schedule start/stop transitions.
  static const String schedule = '$basePath/schedule';

  /// Fired when device power-save mode toggles.
  static const String powerSaveChange = '$basePath/powersavechange';

  /// Fired when network connectivity changes.
  static const String connectivityChange = '$basePath/connectivitychange';

  /// Fired when tracking is enabled or disabled.
  static const String enabledChange = '$basePath/enabledchange';

  /// Fired when user taps a notification action button (Android).
  static const String notificationAction = '$basePath/notificationaction';

  /// Fired on HTTP authorization events.
  static const String authorization = '$basePath/authorization';

  /// Fired for watchPosition updates (multiplexed by watchId).
  static const String watchPosition = '$basePath/watchposition';

  /// All event channel paths.
  static const List<String> all = [
    location,
    motionChange,
    activityChange,
    providerChange,
    geofence,
    geofencesChange,
    heartbeat,
    http,
    schedule,
    powerSaveChange,
    connectivityChange,
    enabledChange,
    notificationAction,
    authorization,
    watchPosition,
  ];
}
