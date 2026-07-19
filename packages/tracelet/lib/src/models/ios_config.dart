import 'package:meta/meta.dart';
import 'package:tracelet/src/models/_helpers.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

/// Configuration for iOS 17+ Live Activities.
@immutable
class LiveActivityConfig {
  /// Creates a new [LiveActivityConfig].
  const LiveActivityConfig({required this.title, required this.body});

  /// Creates a [LiveActivityConfig] from a map.
  factory LiveActivityConfig.fromMap(Map<String, Object?> map) {
    return LiveActivityConfig(
      title: map['title'] as String? ?? 'Tracking Location',
      body:
          map['body'] as String? ??
          'Your location is being updated in the background.',
    );
  }

  /// The static title of the Live Activity.
  final String title;

  /// The dynamic status text.
  final String body;

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{'title': title, 'body': body};
  }

  /// Converts to Pigeon [TlLiveActivityConfig].
  TlLiveActivityConfig toTlConfig() =>
      TlLiveActivityConfig(title: title, body: body);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveActivityConfig &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          body == other.body;

  @override
  int get hashCode => Object.hash(title, body);
}

/// iOS-specific configuration settings.
///
/// These settings are ignored on Android and Web.
@immutable
class IosConfig {
  /// Creates a new [IosConfig] with optional overrides.
  const IosConfig({
    this.activityType = LocationActivityType.other,
    this.useSignificantChangesOnly = false,
    this.showsBackgroundLocationIndicator = false,
    this.pausesLocationUpdatesAutomatically = false,
    this.locationAuthorizationRequest = LocationAuthorizationRequest.always,
    this.disableLocationAuthorizationAlert = false,
    this.preventSuspend = false,
    this.useBackgroundActivitySession = false,
    this.liveActivityConfig,
  });

  /// Creates an [IosConfig] from a map.
  factory IosConfig.fromMap(Map<String, Object?> map) {
    return IosConfig(
      activityType:
          LocationActivityType.values[ensureInt(
            map['activityType'],
            fallback: 0,
          ).clamp(0, LocationActivityType.values.length - 1)],
      useSignificantChangesOnly: ensureBool(
        map['useSignificantChangesOnly'],
        fallback: false,
      ),
      showsBackgroundLocationIndicator: ensureBool(
        map['showsBackgroundLocationIndicator'],
        fallback: false,
      ),
      pausesLocationUpdatesAutomatically: ensureBool(
        map['pausesLocationUpdatesAutomatically'],
        fallback: false,
      ),
      locationAuthorizationRequest: _parseLocationAuthorizationRequest(
        map['locationAuthorizationRequest'],
      ),
      disableLocationAuthorizationAlert: ensureBool(
        map['disableLocationAuthorizationAlert'],
        fallback: false,
      ),
      preventSuspend: ensureBool(map['preventSuspend'], fallback: false),
      useBackgroundActivitySession: ensureBool(
        map['useBackgroundActivitySession'],
        fallback: false,
      ),
      liveActivityConfig: map['liveActivityConfig'] != null
          ? LiveActivityConfig.fromMap(
              (map['liveActivityConfig']! as Map<dynamic, dynamic>)
                  .cast<String, Object?>(),
            )
          : null,
    );
  }

  /// Hint to the platform about the type of activity being performed.
  /// Defaults to [LocationActivityType.other].
  final LocationActivityType activityType;

  /// Use significant-change monitoring instead of standard location updates.
  /// Saves battery but lower accuracy. Defaults to `false`.
  final bool useSignificantChangesOnly;

  /// Show the blue status bar indicator when tracking in the background.
  /// Defaults to `false`.
  final bool showsBackgroundLocationIndicator;

  /// Allow iOS to automatically pause location updates.
  /// Defaults to `false`.
  final bool pausesLocationUpdatesAutomatically;

  /// The location authorization level to request.
  /// Defaults to [LocationAuthorizationRequest.always].
  final LocationAuthorizationRequest locationAuthorizationRequest;

  /// Disable the automatic alert shown when the user has disabled required
  /// location authorization. Defaults to `false`.
  final bool disableLocationAuthorizationAlert;

  /// Play a silent audio clip to keep the app alive in the background.
  /// Defaults to `false`.
  final bool preventSuspend;

  /// Keeps the app alive in the background using CLBackgroundActivitySession (iOS 17+).
  /// This requires the app to have an active Live Activity or similar session.
  /// Defaults to `false`.
  final bool useBackgroundActivitySession;

  /// Configuration to automatically start an ActivityKit Live Activity (iOS 17+).
  /// If provided, Tracelet will use `CLLiveUpdate` for highly battery-optimized location tracking.
  final LiveActivityConfig? liveActivityConfig;

  /// Maps a [LocationActivityType] to its Pigeon [TlIosActivityType] by name.
  ///
  /// The two enums are declared with *different member orderings*, so mapping
  /// by raw `.index` silently sent the wrong value (e.g. `otherNavigation`
  /// arrived as `fitness`). Always map explicitly by name. See issue #250.
  static TlIosActivityType _toTlActivityType(LocationActivityType t) =>
      switch (t) {
        LocationActivityType.other => TlIosActivityType.other,
        LocationActivityType.automotiveNavigation =>
          TlIosActivityType.automotive,
        LocationActivityType.otherNavigation => TlIosActivityType.otherNavigation,
        LocationActivityType.fitness => TlIosActivityType.fitness,
        LocationActivityType.airborne => TlIosActivityType.airborne,
      };

  /// Converts to Pigeon [TlIosConfig].
  TlIosConfig toTlConfig() => TlIosConfig(
    activityType: _toTlActivityType(activityType),
    useSignificantChangesOnly: useSignificantChangesOnly,
    showsBackgroundLocationIndicator: showsBackgroundLocationIndicator,
    pausesLocationUpdatesAutomatically: pausesLocationUpdatesAutomatically,
    locationAuthorizationRequest:
        locationAuthorizationRequest == LocationAuthorizationRequest.always
        ? TlAuthorizationRequest.always
        : TlAuthorizationRequest.whenInUse,
    disableLocationAuthorizationAlert: disableLocationAuthorizationAlert,
    preventSuspend: preventSuspend,
    useBackgroundActivitySession: useBackgroundActivitySession,
    liveActivityConfig: liveActivityConfig?.toTlConfig(),
  );

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'activityType': activityType.index,
      'useSignificantChangesOnly': useSignificantChangesOnly,
      'showsBackgroundLocationIndicator': showsBackgroundLocationIndicator,
      'pausesLocationUpdatesAutomatically': pausesLocationUpdatesAutomatically,
      'locationAuthorizationRequest':
          locationAuthorizationRequest == LocationAuthorizationRequest.always
          ? 'Always'
          : 'WhenInUse',
      'disableLocationAuthorizationAlert': disableLocationAuthorizationAlert,
      'preventSuspend': preventSuspend,
      'useBackgroundActivitySession': useBackgroundActivitySession,
      if (liveActivityConfig != null)
        'liveActivityConfig': liveActivityConfig!.toMap(),
    };
  }

  @override
  String toString() =>
      'IosConfig(activityType: $activityType, '
      'preventSuspend: $preventSuspend, '
      'useBackgroundActivitySession: $useBackgroundActivitySession, '
      'liveActivityConfig: $liveActivityConfig)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IosConfig &&
          runtimeType == other.runtimeType &&
          activityType == other.activityType &&
          useSignificantChangesOnly == other.useSignificantChangesOnly &&
          showsBackgroundLocationIndicator ==
              other.showsBackgroundLocationIndicator &&
          pausesLocationUpdatesAutomatically ==
              other.pausesLocationUpdatesAutomatically &&
          locationAuthorizationRequest == other.locationAuthorizationRequest &&
          disableLocationAuthorizationAlert ==
              other.disableLocationAuthorizationAlert &&
          preventSuspend == other.preventSuspend &&
          useBackgroundActivitySession == other.useBackgroundActivitySession &&
          liveActivityConfig == other.liveActivityConfig;

  @override
  int get hashCode => Object.hash(
    activityType,
    useSignificantChangesOnly,
    showsBackgroundLocationIndicator,
    pausesLocationUpdatesAutomatically,
    locationAuthorizationRequest,
    disableLocationAuthorizationAlert,
    preventSuspend,
    useBackgroundActivitySession,
    liveActivityConfig,
  );
}

LocationAuthorizationRequest _parseLocationAuthorizationRequest(Object? value) {
  if (value == 'WhenInUse') return LocationAuthorizationRequest.whenInUse;
  if (value == 'Always') return LocationAuthorizationRequest.always;
  // Fallback to Always for backward compat in background context
  return LocationAuthorizationRequest.always;
}
