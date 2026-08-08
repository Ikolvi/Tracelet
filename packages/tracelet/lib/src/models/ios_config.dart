import 'package:meta/meta.dart';
import 'package:tracelet/src/models/_helpers.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

/// Configuration for iOS 17+ Live Activities.
///
/// Both fields are required — a Live Activity is either configured or absent
/// (`IosConfig.liveActivityConfig` is nullable), so there is no partial state
/// to preserve and no `#321` unset-tracking here.
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
///
/// ## Unset fields are not sent (#321)
///
/// `setConfig()` merges into the configuration the platform already persisted,
/// so a field the caller never mentioned must not be transmitted — otherwise it
/// arrives as a value indistinguishable from a deliberate one and overwrites
/// what is stored. This class records *whether* each field was supplied,
/// separately from its value: every property below still returns a
/// non-nullable value with the documented default, but [toMap] and [toTlConfig]
/// emit only the fields that were actually provided.
///
/// This is the iOS half of the same defect fixed for the Android foreground
/// service in #320. The fields it protects are the ones that silently degrade
/// background tracking when reverted — [showsBackgroundLocationIndicator],
/// [preventSuspend] and [useBackgroundActivitySession] — which a partial
/// `setConfig()` previously reset to `false` without any signal.
///
/// Passing a value equal to the default is still an explicit choice and is
/// transmitted. "Unset" means *not provided*, never *equal to the default*.
@immutable
class IosConfig {
  /// Creates a new [IosConfig].
  ///
  /// Every parameter is optional. Omitting one leaves it *unset*: the getter
  /// reports the documented default, and [toMap]/[toTlConfig] skip the field so
  /// `setConfig()` does not overwrite the persisted value (#321).
  const IosConfig({
    LocationActivityType? activityType,
    bool? useSignificantChangesOnly,
    bool? showsBackgroundLocationIndicator,
    bool? pausesLocationUpdatesAutomatically,
    LocationAuthorizationRequest? locationAuthorizationRequest,
    bool? disableLocationAuthorizationAlert,
    bool? preventSuspend,
    bool? useBackgroundActivitySession,
    this.liveActivityConfig,
  }) : _activityType = activityType,
       _useSignificantChangesOnly = useSignificantChangesOnly,
       _showsBackgroundLocationIndicator = showsBackgroundLocationIndicator,
       _pausesLocationUpdatesAutomatically = pausesLocationUpdatesAutomatically,
       _locationAuthorizationRequest = locationAuthorizationRequest,
       _disableLocationAuthorizationAlert = disableLocationAuthorizationAlert,
       _preventSuspend = preventSuspend,
       _useBackgroundActivitySession = useBackgroundActivitySession;

  /// Creates an [IosConfig] from a map.
  ///
  /// A key absent from [map] stays unset, so a `toMap()`/`fromMap()` round trip
  /// preserves which fields were supplied (#321).
  factory IosConfig.fromMap(Map<String, Object?> map) {
    return IosConfig(
      activityType: map.containsKey('activityType')
          ? LocationActivityType.values[ensureInt(
              map['activityType'],
              fallback: 0,
            ).clamp(0, LocationActivityType.values.length - 1)]
          : null,
      useSignificantChangesOnly: map.containsKey('useSignificantChangesOnly')
          ? ensureBool(map['useSignificantChangesOnly'], fallback: false)
          : null,
      showsBackgroundLocationIndicator:
          map.containsKey('showsBackgroundLocationIndicator')
          ? ensureBool(
              map['showsBackgroundLocationIndicator'],
              fallback: false,
            )
          : null,
      pausesLocationUpdatesAutomatically:
          map.containsKey('pausesLocationUpdatesAutomatically')
          ? ensureBool(
              map['pausesLocationUpdatesAutomatically'],
              fallback: false,
            )
          : null,
      locationAuthorizationRequest:
          map.containsKey('locationAuthorizationRequest')
          ? _parseLocationAuthorizationRequest(
              map['locationAuthorizationRequest'],
            )
          : null,
      disableLocationAuthorizationAlert:
          map.containsKey('disableLocationAuthorizationAlert')
          ? ensureBool(
              map['disableLocationAuthorizationAlert'],
              fallback: false,
            )
          : null,
      preventSuspend: map.containsKey('preventSuspend')
          ? ensureBool(map['preventSuspend'], fallback: false)
          : null,
      useBackgroundActivitySession:
          map.containsKey('useBackgroundActivitySession')
          ? ensureBool(map['useBackgroundActivitySession'], fallback: false)
          : null,
      liveActivityConfig: map['liveActivityConfig'] != null
          ? LiveActivityConfig.fromMap(
              (map['liveActivityConfig']! as Map<dynamic, dynamic>)
                  .cast<String, Object?>(),
            )
          : null,
    );
  }

  // Backing fields. `null` means "the caller did not provide this", which is
  // what keeps the field out of the wire payload (#321). The public getters
  // below resolve each one to its documented default.
  final LocationActivityType? _activityType;
  final bool? _useSignificantChangesOnly;
  final bool? _showsBackgroundLocationIndicator;
  final bool? _pausesLocationUpdatesAutomatically;
  final LocationAuthorizationRequest? _locationAuthorizationRequest;
  final bool? _disableLocationAuthorizationAlert;
  final bool? _preventSuspend;
  final bool? _useBackgroundActivitySession;

  /// Hint to the platform about the type of activity being performed.
  /// Defaults to [LocationActivityType.other].
  LocationActivityType get activityType =>
      _activityType ?? LocationActivityType.other;

  /// Use significant-change monitoring instead of standard location updates.
  /// Saves battery but lower accuracy. Defaults to `false`.
  bool get useSignificantChangesOnly => _useSignificantChangesOnly ?? false;

  /// Show the blue status bar indicator when tracking in the background.
  /// Defaults to `false`.
  bool get showsBackgroundLocationIndicator =>
      _showsBackgroundLocationIndicator ?? false;

  /// Allow iOS to automatically pause location updates.
  /// Defaults to `false`.
  bool get pausesLocationUpdatesAutomatically =>
      _pausesLocationUpdatesAutomatically ?? false;

  /// The location authorization level to request.
  /// Defaults to [LocationAuthorizationRequest.always].
  LocationAuthorizationRequest get locationAuthorizationRequest =>
      _locationAuthorizationRequest ?? LocationAuthorizationRequest.always;

  /// Disable the automatic alert shown when the user has disabled required
  /// location authorization. Defaults to `false`.
  bool get disableLocationAuthorizationAlert =>
      _disableLocationAuthorizationAlert ?? false;

  /// Play a silent audio clip to keep the app alive in the background.
  /// Defaults to `false`.
  bool get preventSuspend => _preventSuspend ?? false;

  /// Keeps the app alive in the background using CLBackgroundActivitySession (iOS 17+).
  /// This requires the app to have an active Live Activity or similar session.
  /// Defaults to `false`.
  bool get useBackgroundActivitySession =>
      _useBackgroundActivitySession ?? false;

  /// Configuration to automatically start an ActivityKit Live Activity (iOS 17+).
  /// If provided, Tracelet will use `CLLiveUpdate` for highly battery-optimized location tracking.
  final LiveActivityConfig? liveActivityConfig;

  /// Maps a [LocationActivityType] to its Pigeon [TlIosActivityType] by name.
  ///
  /// The two enums are declared with *different member orderings*, so mapping
  /// by raw `.index` silently sent the wrong value (e.g. `otherNavigation`
  /// arrived as `fitness`). Always map explicitly by name. See issue #250.
  static TlIosActivityType _toTlActivityType(
    LocationActivityType t,
  ) => switch (t) {
    LocationActivityType.other => TlIosActivityType.other,
    LocationActivityType.automotiveNavigation => TlIosActivityType.automotive,
    LocationActivityType.otherNavigation => TlIosActivityType.otherNavigation,
    LocationActivityType.fitness => TlIosActivityType.fitness,
    LocationActivityType.airborne => TlIosActivityType.airborne,
  };

  /// Creates a copy of this [IosConfig] with the given fields replaced.
  ///
  /// A parameter left `null` keeps this config's field *as it is* — including
  /// keeping it unset — rather than resolving it to a default (#321).
  IosConfig copyWith({
    LocationActivityType? activityType,
    bool? useSignificantChangesOnly,
    bool? showsBackgroundLocationIndicator,
    bool? pausesLocationUpdatesAutomatically,
    LocationAuthorizationRequest? locationAuthorizationRequest,
    bool? disableLocationAuthorizationAlert,
    bool? preventSuspend,
    bool? useBackgroundActivitySession,
    LiveActivityConfig? liveActivityConfig,
  }) => IosConfig(
    activityType: activityType ?? _activityType,
    useSignificantChangesOnly:
        useSignificantChangesOnly ?? _useSignificantChangesOnly,
    showsBackgroundLocationIndicator:
        showsBackgroundLocationIndicator ?? _showsBackgroundLocationIndicator,
    pausesLocationUpdatesAutomatically:
        pausesLocationUpdatesAutomatically ??
        _pausesLocationUpdatesAutomatically,
    locationAuthorizationRequest:
        locationAuthorizationRequest ?? _locationAuthorizationRequest,
    disableLocationAuthorizationAlert:
        disableLocationAuthorizationAlert ?? _disableLocationAuthorizationAlert,
    preventSuspend: preventSuspend ?? _preventSuspend,
    useBackgroundActivitySession:
        useBackgroundActivitySession ?? _useBackgroundActivitySession,
    liveActivityConfig: liveActivityConfig ?? this.liveActivityConfig,
  );

  /// Applies every field [other] explicitly supplied on top of this config,
  /// leaving fields [other] left unset as they are here.
  ///
  /// This mirrors what the platform does with the serialized payload, and keeps
  /// `Tracelet.activeConfig` in step with the values actually persisted
  /// natively after a partial `setConfig()` (#321).
  IosConfig mergedWith(IosConfig other) => IosConfig(
    activityType: other._activityType ?? _activityType,
    useSignificantChangesOnly:
        other._useSignificantChangesOnly ?? _useSignificantChangesOnly,
    showsBackgroundLocationIndicator:
        other._showsBackgroundLocationIndicator ??
        _showsBackgroundLocationIndicator,
    pausesLocationUpdatesAutomatically:
        other._pausesLocationUpdatesAutomatically ??
        _pausesLocationUpdatesAutomatically,
    locationAuthorizationRequest:
        other._locationAuthorizationRequest ?? _locationAuthorizationRequest,
    disableLocationAuthorizationAlert:
        other._disableLocationAuthorizationAlert ??
        _disableLocationAuthorizationAlert,
    preventSuspend: other._preventSuspend ?? _preventSuspend,
    useBackgroundActivitySession:
        other._useBackgroundActivitySession ?? _useBackgroundActivitySession,
    liveActivityConfig: other.liveActivityConfig ?? liveActivityConfig,
  );

  /// Returns this config with every field pinned to its effective value.
  ///
  /// Used by `ready()`, which establishes a complete native baseline rather
  /// than a partial update — so the platform's own defaults never have to match
  /// Dart's for correctness (#321).
  IosConfig resolved() => IosConfig(
    activityType: activityType,
    useSignificantChangesOnly: useSignificantChangesOnly,
    showsBackgroundLocationIndicator: showsBackgroundLocationIndicator,
    pausesLocationUpdatesAutomatically: pausesLocationUpdatesAutomatically,
    locationAuthorizationRequest: locationAuthorizationRequest,
    disableLocationAuthorizationAlert: disableLocationAuthorizationAlert,
    preventSuspend: preventSuspend,
    useBackgroundActivitySession: useBackgroundActivitySession,
    liveActivityConfig: liveActivityConfig,
  );

  /// Converts to Pigeon [TlIosConfig].
  ///
  /// Unset fields cross as `null` so the platform can tell them apart from a
  /// supplied value and leave the persisted one alone (#321).
  TlIosConfig toTlConfig() => TlIosConfig(
    activityType: _activityType == null
        ? null
        : _toTlActivityType(_activityType),
    useSignificantChangesOnly: _useSignificantChangesOnly,
    showsBackgroundLocationIndicator: _showsBackgroundLocationIndicator,
    pausesLocationUpdatesAutomatically: _pausesLocationUpdatesAutomatically,
    locationAuthorizationRequest: _locationAuthorizationRequest == null
        ? null
        : (_locationAuthorizationRequest == LocationAuthorizationRequest.always
              ? TlAuthorizationRequest.always
              : TlAuthorizationRequest.whenInUse),
    disableLocationAuthorizationAlert: _disableLocationAuthorizationAlert,
    preventSuspend: _preventSuspend,
    useBackgroundActivitySession: _useBackgroundActivitySession,
    liveActivityConfig: liveActivityConfig?.toTlConfig(),
  );

  /// Serializes to a map, omitting fields that were never supplied (#321).
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (_activityType != null) 'activityType': _activityType.index,
      if (_useSignificantChangesOnly != null)
        'useSignificantChangesOnly': _useSignificantChangesOnly,
      if (_showsBackgroundLocationIndicator != null)
        'showsBackgroundLocationIndicator': _showsBackgroundLocationIndicator,
      if (_pausesLocationUpdatesAutomatically != null)
        'pausesLocationUpdatesAutomatically':
            _pausesLocationUpdatesAutomatically,
      if (_locationAuthorizationRequest != null)
        'locationAuthorizationRequest':
            _locationAuthorizationRequest == LocationAuthorizationRequest.always
            ? 'Always'
            : 'WhenInUse',
      if (_disableLocationAuthorizationAlert != null)
        'disableLocationAuthorizationAlert': _disableLocationAuthorizationAlert,
      if (_preventSuspend != null) 'preventSuspend': _preventSuspend,
      if (_useBackgroundActivitySession != null)
        'useBackgroundActivitySession': _useBackgroundActivitySession,
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

  // Equality compares the backing fields, not the resolved values: an unset
  // field and one explicitly set to its default behave identically but
  // serialise differently, and collapsing them would lose the distinction the
  // fix depends on (#321).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IosConfig &&
          runtimeType == other.runtimeType &&
          _activityType == other._activityType &&
          _useSignificantChangesOnly == other._useSignificantChangesOnly &&
          _showsBackgroundLocationIndicator ==
              other._showsBackgroundLocationIndicator &&
          _pausesLocationUpdatesAutomatically ==
              other._pausesLocationUpdatesAutomatically &&
          _locationAuthorizationRequest ==
              other._locationAuthorizationRequest &&
          _disableLocationAuthorizationAlert ==
              other._disableLocationAuthorizationAlert &&
          _preventSuspend == other._preventSuspend &&
          _useBackgroundActivitySession ==
              other._useBackgroundActivitySession &&
          liveActivityConfig == other.liveActivityConfig;

  @override
  int get hashCode => Object.hash(
    _activityType,
    _useSignificantChangesOnly,
    _showsBackgroundLocationIndicator,
    _pausesLocationUpdatesAutomatically,
    _locationAuthorizationRequest,
    _disableLocationAuthorizationAlert,
    _preventSuspend,
    _useBackgroundActivitySession,
    liveActivityConfig,
  );
}

LocationAuthorizationRequest _parseLocationAuthorizationRequest(Object? value) {
  if (value == 'WhenInUse') return LocationAuthorizationRequest.whenInUse;
  if (value == 'Always') return LocationAuthorizationRequest.always;
  // Fallback to Always for backward compat in background context
  return LocationAuthorizationRequest.always;
}
