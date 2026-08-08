import 'package:meta/meta.dart';
import 'package:tracelet/src/models/_helpers.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

/// Android-specific configuration settings.
///
/// These settings are ignored on iOS and Web.
@immutable
class AndroidConfig {
  /// Creates a new [AndroidConfig].
  ///
  /// Omitting a parameter leaves it *unset*: the getter reports the documented
  /// default, and [toMap]/[toTlConfig] skip the field so a partial
  /// `setConfig()` does not overwrite the persisted value (#321).
  const AndroidConfig({
    int? locationUpdateInterval,
    int? fastestLocationUpdateInterval,
    int? deferTime,
    bool? allowIdenticalLocations,
    @Deprecated(
      'Use GeofenceConfig.geofenceModeHighAccuracy (cross-platform) instead. '
      'Still honored for now; will be removed in a future major version.',
    )
    bool? geofenceModeHighAccuracy,
    bool? periodicUseForegroundService,
    bool? periodicUseExactAlarms,
    bool? scheduleUseAlarmManager,
    bool? releaseWakelockWhenStationary,
    this.foregroundService = const ForegroundServiceConfig(),
  }) : _locationUpdateInterval = locationUpdateInterval,
       _fastestLocationUpdateInterval = fastestLocationUpdateInterval,
       _deferTime = deferTime,
       _allowIdenticalLocations = allowIdenticalLocations,
       _geofenceModeHighAccuracy = geofenceModeHighAccuracy,
       _periodicUseForegroundService = periodicUseForegroundService,
       _periodicUseExactAlarms = periodicUseExactAlarms,
       _scheduleUseAlarmManager = scheduleUseAlarmManager,
       _releaseWakelockWhenStationary = releaseWakelockWhenStationary;

  /// Creates an [AndroidConfig] from a map.
  factory AndroidConfig.fromMap(Map<String, Object?> map) {
    final fgMap = safeMap(map['foregroundService']);
    return AndroidConfig(
      locationUpdateInterval: map.containsKey('locationUpdateInterval')
          ? ensureInt(map['locationUpdateInterval'], fallback: 1000)
          : null,
      fastestLocationUpdateInterval:
          map.containsKey('fastestLocationUpdateInterval')
          ? ensureInt(map['fastestLocationUpdateInterval'], fallback: 500)
          : null,
      deferTime: map.containsKey('deferTime')
          ? ensureInt(map['deferTime'], fallback: 0)
          : null,
      allowIdenticalLocations: map.containsKey('allowIdenticalLocations')
          ? ensureBool(map['allowIdenticalLocations'], fallback: false)
          : null,
      geofenceModeHighAccuracy: map.containsKey('geofenceModeHighAccuracy')
          ? ensureBool(map['geofenceModeHighAccuracy'], fallback: false)
          : null,
      periodicUseForegroundService:
          map.containsKey('periodicUseForegroundService')
          ? ensureBool(map['periodicUseForegroundService'], fallback: false)
          : null,
      periodicUseExactAlarms: map.containsKey('periodicUseExactAlarms')
          ? ensureBool(map['periodicUseExactAlarms'], fallback: false)
          : null,
      scheduleUseAlarmManager: map.containsKey('scheduleUseAlarmManager')
          ? ensureBool(map['scheduleUseAlarmManager'], fallback: false)
          : null,
      releaseWakelockWhenStationary:
          map.containsKey('releaseWakelockWhenStationary')
          ? ensureBool(map['releaseWakelockWhenStationary'], fallback: false)
          : null,
      foregroundService: fgMap != null
          ? ForegroundServiceConfig.fromMap(fgMap)
          : const ForegroundServiceConfig(),
    );
  }

  /// Creates a copy of this [AndroidConfig] with the given fields replaced with the new values.
  AndroidConfig copyWith({
    int? locationUpdateInterval,
    int? fastestLocationUpdateInterval,
    int? deferTime,
    bool? allowIdenticalLocations,
    @Deprecated(
      'Use GeofenceConfig.geofenceModeHighAccuracy (cross-platform) instead. '
      'Still honored for now; will be removed in a future major version.',
    )
    bool? geofenceModeHighAccuracy,
    bool? periodicUseForegroundService,
    bool? periodicUseExactAlarms,
    bool? scheduleUseAlarmManager,
    bool? releaseWakelockWhenStationary,
    ForegroundServiceConfig? foregroundService,
  }) {
    // A parameter left null keeps this config's field *as it is* — including
    // keeping it unset — rather than resolving it to a default (#321).
    return AndroidConfig(
      locationUpdateInterval: locationUpdateInterval ?? _locationUpdateInterval,
      fastestLocationUpdateInterval:
          fastestLocationUpdateInterval ?? _fastestLocationUpdateInterval,
      deferTime: deferTime ?? _deferTime,
      allowIdenticalLocations:
          allowIdenticalLocations ?? _allowIdenticalLocations,
      geofenceModeHighAccuracy:
          geofenceModeHighAccuracy ?? _geofenceModeHighAccuracy,
      periodicUseForegroundService:
          periodicUseForegroundService ?? _periodicUseForegroundService,
      periodicUseExactAlarms: periodicUseExactAlarms ?? _periodicUseExactAlarms,
      scheduleUseAlarmManager:
          scheduleUseAlarmManager ?? _scheduleUseAlarmManager,
      releaseWakelockWhenStationary:
          releaseWakelockWhenStationary ?? _releaseWakelockWhenStationary,
      foregroundService: foregroundService ?? this.foregroundService,
    );
  }

  /// Applies every field [other] explicitly supplied on top of this config,
  /// leaving fields [other] left unset as they are here (#321).
  AndroidConfig mergedWith(AndroidConfig other) => AndroidConfig(
    locationUpdateInterval:
        other._locationUpdateInterval ?? _locationUpdateInterval,
    fastestLocationUpdateInterval:
        other._fastestLocationUpdateInterval ?? _fastestLocationUpdateInterval,
    deferTime: other._deferTime ?? _deferTime,
    allowIdenticalLocations:
        other._allowIdenticalLocations ?? _allowIdenticalLocations,
    geofenceModeHighAccuracy:
        other._geofenceModeHighAccuracy ?? _geofenceModeHighAccuracy,
    periodicUseForegroundService:
        other._periodicUseForegroundService ?? _periodicUseForegroundService,
    periodicUseExactAlarms:
        other._periodicUseExactAlarms ?? _periodicUseExactAlarms,
    scheduleUseAlarmManager:
        other._scheduleUseAlarmManager ?? _scheduleUseAlarmManager,
    releaseWakelockWhenStationary:
        other._releaseWakelockWhenStationary ?? _releaseWakelockWhenStationary,
    foregroundService: foregroundService.mergedWith(other.foregroundService),
  );

  /// Returns this config with every field pinned to its effective value, for
  /// the complete baseline `ready()` sends (#321).
  AndroidConfig resolved() => AndroidConfig(
    locationUpdateInterval: locationUpdateInterval,
    fastestLocationUpdateInterval: fastestLocationUpdateInterval,
    deferTime: deferTime,
    allowIdenticalLocations: allowIdenticalLocations,
    // ignore: deprecated_member_use_from_same_package
    geofenceModeHighAccuracy: geofenceModeHighAccuracy,
    periodicUseForegroundService: periodicUseForegroundService,
    periodicUseExactAlarms: periodicUseExactAlarms,
    scheduleUseAlarmManager: scheduleUseAlarmManager,
    releaseWakelockWhenStationary: releaseWakelockWhenStationary,
    foregroundService: foregroundService.resolved(),
  );

  // Backing fields. `null` means "the caller did not provide this", which is
  // what keeps the field out of the wire payload (#321). The public getters
  // below resolve each one to its documented default.
  final int? _locationUpdateInterval;
  final int? _fastestLocationUpdateInterval;
  final int? _deferTime;
  final bool? _allowIdenticalLocations;
  final bool? _geofenceModeHighAccuracy;
  final bool? _periodicUseForegroundService;
  final bool? _periodicUseExactAlarms;
  final bool? _scheduleUseAlarmManager;
  final bool? _releaseWakelockWhenStationary;

  /// The desired interval (in milliseconds) between location updates.
  /// Defaults to `1000`.
  int get locationUpdateInterval => _locationUpdateInterval ?? 1000;

  /// The fastest interval (in milliseconds) the app is able to receive
  /// location updates. Defaults to `500`.
  int get fastestLocationUpdateInterval =>
      _fastestLocationUpdateInterval ?? 500;

  /// Maximum wait time (ms) for location updates. Defaults to `0`.
  int get deferTime => _deferTime ?? 0;

  /// Allow recording identical consecutive locations. Defaults to `false`.
  bool get allowIdenticalLocations => _allowIdenticalLocations ?? false;

  /// Enable high-accuracy geofence monitoring during geofence-only mode.
  /// Defaults to `false`.
  ///
  /// Deprecated: use the cross-platform [GeofenceConfig.geofenceModeHighAccuracy]
  /// instead. This Android-only flag is still honored for backward
  /// compatibility — if either it or the GeofenceConfig flag is `true`,
  /// high-accuracy mode is enabled — but it will be removed in a future major
  /// version.
  @Deprecated(
    'Use GeofenceConfig.geofenceModeHighAccuracy (cross-platform) instead. '
    'Still honored for now; will be removed in a future major version.',
  )
  bool get geofenceModeHighAccuracy => _geofenceModeHighAccuracy ?? false;

  /// Whether to use a foreground service for periodic mode.
  /// Defaults to `false` (uses WorkManager).
  bool get periodicUseForegroundService =>
      _periodicUseForegroundService ?? false;

  /// Use exact alarms instead of WorkManager for periodic scheduling.
  /// Requires `SCHEDULE_EXACT_ALARM` permission on API 31+.
  /// Defaults to `false`.
  bool get periodicUseExactAlarms => _periodicUseExactAlarms ?? false;

  /// Use `AlarmManager` for precise schedule execution.
  /// Defaults to `false` (uses WorkManager).
  bool get scheduleUseAlarmManager => _scheduleUseAlarmManager ?? false;

  /// Drops the OEM Wakelock when the device enters a fully stationary state.
  /// Only applies when using `MotionDetectionMode.smart`.
  /// Resolves Issue #162.
  /// Defaults to `false`.
  bool get releaseWakelockWhenStationary =>
      _releaseWakelockWhenStationary ?? false;

  /// Foreground service notification configuration.
  final ForegroundServiceConfig foregroundService;

  /// Converts to Pigeon [TlAndroidConfig].
  ///
  /// Unset fields cross as `null` so the platform leaves the persisted value
  /// alone (#321).
  TlAndroidConfig toTlConfig() => TlAndroidConfig(
    locationUpdateInterval: _locationUpdateInterval,
    fastestLocationUpdateInterval: _fastestLocationUpdateInterval,
    deferTime: _deferTime,
    allowIdenticalLocations: _allowIdenticalLocations,
    geofenceModeHighAccuracy: _geofenceModeHighAccuracy,
    periodicUseForegroundService: _periodicUseForegroundService,
    periodicUseExactAlarms: _periodicUseExactAlarms,
    scheduleUseAlarmManager: _scheduleUseAlarmManager,
    releaseWakelockWhenStationary: _releaseWakelockWhenStationary,
    foregroundService: foregroundService.toTlConfig(),
  );

  /// Serializes to a map, omitting fields that were never supplied (#321).
  Map<String, Object?> toMap() {
    // A nested sub-config is emitted only when it carries something.
    // `filter`/`foregroundService` resolve to a non-null object even when
    // unset, so guarding on the object was dead code and every payload
    // carried an empty `{}`. That contributes nothing to the platform
    // merge, but it makes a partial update that changes nothing look like
    // it touched the section, and it is not a minimal payload (#321).
    final fgMap = foregroundService.toMap();
    return <String, Object?>{
      if (_locationUpdateInterval != null)
        'locationUpdateInterval': _locationUpdateInterval,
      if (_fastestLocationUpdateInterval != null)
        'fastestLocationUpdateInterval': _fastestLocationUpdateInterval,
      if (_deferTime != null) 'deferTime': _deferTime,
      if (_allowIdenticalLocations != null)
        'allowIdenticalLocations': _allowIdenticalLocations,
      if (_geofenceModeHighAccuracy != null)
        'geofenceModeHighAccuracy': _geofenceModeHighAccuracy,
      if (_periodicUseForegroundService != null)
        'periodicUseForegroundService': _periodicUseForegroundService,
      if (_periodicUseExactAlarms != null)
        'periodicUseExactAlarms': _periodicUseExactAlarms,
      if (_scheduleUseAlarmManager != null)
        'scheduleUseAlarmManager': _scheduleUseAlarmManager,
      if (_releaseWakelockWhenStationary != null)
        'releaseWakelockWhenStationary': _releaseWakelockWhenStationary,
      if (fgMap.isNotEmpty) 'foregroundService': fgMap,
    };
  }

  @override
  String toString() =>
      'AndroidConfig(locationUpdateInterval: $locationUpdateInterval, '
      'foregroundService: $foregroundService)';

  // Compares the backing fields so unset stays distinguishable from an
  // explicit default (#321).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AndroidConfig &&
          runtimeType == other.runtimeType &&
          _locationUpdateInterval == other._locationUpdateInterval &&
          _fastestLocationUpdateInterval ==
              other._fastestLocationUpdateInterval &&
          _deferTime == other._deferTime &&
          _allowIdenticalLocations == other._allowIdenticalLocations &&
          _geofenceModeHighAccuracy == other._geofenceModeHighAccuracy &&
          _periodicUseForegroundService ==
              other._periodicUseForegroundService &&
          _periodicUseExactAlarms == other._periodicUseExactAlarms &&
          _scheduleUseAlarmManager == other._scheduleUseAlarmManager &&
          _releaseWakelockWhenStationary ==
              other._releaseWakelockWhenStationary &&
          foregroundService == other.foregroundService;

  @override
  int get hashCode => Object.hash(
    _locationUpdateInterval,
    _fastestLocationUpdateInterval,
    _deferTime,
    _allowIdenticalLocations,
    _geofenceModeHighAccuracy,
    _periodicUseForegroundService,
    _periodicUseExactAlarms,
    _scheduleUseAlarmManager,
    _releaseWakelockWhenStationary,
    foregroundService,
  );
}

/// Configuration for the Android foreground service notification.
///
/// ## Unset fields are not sent (#320)
///
/// `setConfig()` merges into the configuration already persisted by the
/// platform, so a field the caller never mentioned must not be transmitted at
/// all — otherwise it arrives as a value indistinguishable from a deliberate
/// one and overwrites what is stored.
///
/// This class therefore records *whether* each field was supplied, separately
/// from its effective value. Every property below still returns a
/// non-nullable value with the documented default, so reading the config is
/// unchanged; but [toMap] and [toTlConfig] emit only the fields that were
/// actually provided.
///
/// ```dart
/// // Only showNotificationOnPauseOnly is sent; the channel, title and text
/// // configured earlier survive.
/// await Tracelet.setConfig(const Config(
///   android: AndroidConfig(
///     foregroundService: ForegroundServiceConfig(
///       showNotificationOnPauseOnly: true,
///     ),
///   ),
/// ));
/// ```
///
/// Passing a value equal to the default is still an explicit choice and is
/// transmitted — `ForegroundServiceConfig(showNotificationOnPauseOnly: false)`
/// sets the stored value back to `false`. "Unset" means *not provided*, never
/// *equal to the default*; the latter test would make it impossible to restore
/// a default once changed.
///
/// The native defaults match the defaults documented here exactly, so a field
/// left unset on a fresh install behaves as it always did.
@immutable
class ForegroundServiceConfig {
  /// Creates a new [ForegroundServiceConfig].
  ///
  /// Every parameter is optional. Omitting one leaves it *unset*: the getter
  /// reports the documented default, and [toMap]/[toTlConfig] skip the field so
  /// `setConfig()` does not overwrite the persisted value (#320).
  const ForegroundServiceConfig({
    bool? enabled,
    String? channelId,
    String? channelName,
    String? notificationTitle,
    String? notificationText,
    this.notificationColor,
    this.notificationSmallIcon,
    this.notificationLargeIcon,
    NotificationPriority? notificationPriority,
    bool? notificationOngoing,
    bool? showNotificationOnPauseOnly,
    List<String>? actions,
  }) : _enabled = enabled,
       _channelId = channelId,
       _channelName = channelName,
       _notificationTitle = notificationTitle,
       _notificationText = notificationText,
       _notificationPriority = notificationPriority,
       _notificationOngoing = notificationOngoing,
       _showNotificationOnPauseOnly = showNotificationOnPauseOnly,
       _actions = actions;

  /// Creates a [ForegroundServiceConfig] from a map.
  ///
  /// A key that is absent from [map] stays unset, so a `toMap()`/`fromMap()`
  /// round-trip preserves which fields were provided (#320). A key present with
  /// an explicit value is treated as supplied, including when it equals the
  /// default.
  factory ForegroundServiceConfig.fromMap(Map<String, Object?> map) {
    List<String>? actionsList;
    final rawActions = map['actions'];
    if (rawActions is List) {
      actionsList = <String>[
        for (final item in rawActions)
          if (item is String) item,
      ];
    }
    return ForegroundServiceConfig(
      enabled: map.containsKey('enabled')
          ? ensureBool(map['enabled'], fallback: true)
          : null,
      channelId: map['channelId'] as String?,
      channelName: map['channelName'] as String?,
      notificationTitle: map['notificationTitle'] as String?,
      notificationText: map['notificationText'] as String?,
      notificationColor: map['notificationColor'] as String?,
      notificationSmallIcon: map['notificationSmallIcon'] as String?,
      notificationLargeIcon: map['notificationLargeIcon'] as String?,
      notificationPriority: map.containsKey('notificationPriority')
          ? _parseNotificationPriority(map['notificationPriority'])
          : null,
      notificationOngoing: map.containsKey('notificationOngoing')
          ? ensureBool(map['notificationOngoing'], fallback: true)
          : null,
      showNotificationOnPauseOnly:
          map.containsKey('showNotificationOnPauseOnly')
          ? ensureBool(map['showNotificationOnPauseOnly'], fallback: false)
          : null,
      actions: actionsList,
    );
  }

  /// Creates a copy of this [ForegroundServiceConfig] with the given fields replaced with the new values.
  ForegroundServiceConfig copyWith({
    bool? enabled,
    String? channelId,
    String? channelName,
    String? notificationTitle,
    String? notificationText,
    String? notificationColor,
    String? notificationSmallIcon,
    String? notificationLargeIcon,
    NotificationPriority? notificationPriority,
    bool? notificationOngoing,
    bool? showNotificationOnPauseOnly,
    List<String>? actions,
  }) {
    return ForegroundServiceConfig(
      enabled: enabled ?? _enabled,
      channelId: channelId ?? _channelId,
      channelName: channelName ?? _channelName,
      notificationTitle: notificationTitle ?? _notificationTitle,
      notificationText: notificationText ?? _notificationText,
      notificationColor: notificationColor ?? this.notificationColor,
      notificationSmallIcon:
          notificationSmallIcon ?? this.notificationSmallIcon,
      notificationLargeIcon:
          notificationLargeIcon ?? this.notificationLargeIcon,
      notificationPriority: notificationPriority ?? _notificationPriority,
      notificationOngoing: notificationOngoing ?? _notificationOngoing,
      showNotificationOnPauseOnly:
          showNotificationOnPauseOnly ?? _showNotificationOnPauseOnly,
      actions: actions ?? _actions,
    );
  }

  // Backing fields. `null` means "the caller did not provide this", which is
  // what keeps the field out of the wire payload (#320). The public getters
  // below resolve each one to its documented default.
  final bool? _enabled;
  final String? _channelId;
  final String? _channelName;
  final String? _notificationTitle;
  final String? _notificationText;
  final NotificationPriority? _notificationPriority;
  final bool? _notificationOngoing;
  final bool? _showNotificationOnPauseOnly;
  final List<String>? _actions;

  /// Whether the foreground service notification is enabled.
  /// Defaults to `true`.
  bool get enabled => _enabled ?? true;

  /// The unique channel ID for the foreground service notification.
  /// Defaults to `'tracelet_channel'`.
  String get channelId => _channelId ?? 'tracelet_channel';

  /// The user-visible channel name for the foreground service notification.
  /// Defaults to `'Tracelet'`.
  String get channelName => _channelName ?? 'Tracelet';

  /// The notification title shown in the status bar/drawer.
  /// Defaults to `'Tracelet'`.
  String get notificationTitle => _notificationTitle ?? 'Tracelet';

  /// The notification body text.
  /// Defaults to `'Tracking location in background'`.
  String get notificationText =>
      _notificationText ?? 'Tracking location in background';

  /// The hex color code for the notification's accent color (e.g. `'#4CAF50'`).
  /// Defaults to `null`.
  final String? notificationColor;

  /// The resource name for the notification's small icon.
  /// Defaults to `null`.
  final String? notificationSmallIcon;

  /// The resource name for the notification's large icon.
  /// Defaults to `null`.
  final String? notificationLargeIcon;

  /// The notification priority level.
  /// Defaults to [NotificationPriority.defaultPriority].
  NotificationPriority get notificationPriority =>
      _notificationPriority ?? NotificationPriority.defaultPriority;

  /// Whether the notification is persistent and cannot be swiped away by the user.
  /// Defaults to `true`.
  bool get notificationOngoing => _notificationOngoing ?? true;

  /// Whether the notification is only shown when the app is in the background (paused).
  ///
  /// When `true`, the persistent notification is automatically dismissed when the app
  /// enters the foreground and restored when it enters the background.
  ///
  /// Defaults to `false`.
  bool get showNotificationOnPauseOnly => _showNotificationOnPauseOnly ?? false;

  /// Action buttons to display inside the notification drawer (e.g. `['Stop', 'Sync']`).
  /// Defaults to empty list.
  List<String> get actions => _actions ?? const <String>[];

  /// Whether any field of this config was explicitly provided.
  ///
  /// `false` for `const ForegroundServiceConfig()`, which is what a
  /// `setConfig()` that never mentions the foreground service produces. The
  /// caller uses this to drop the section from the payload entirely rather than
  /// sending a map of nulls (#320).
  bool get hasExplicitValues =>
      _enabled != null ||
      _channelId != null ||
      _channelName != null ||
      _notificationTitle != null ||
      _notificationText != null ||
      notificationColor != null ||
      notificationSmallIcon != null ||
      notificationLargeIcon != null ||
      _notificationPriority != null ||
      _notificationOngoing != null ||
      _showNotificationOnPauseOnly != null ||
      _actions != null;

  /// Applies every field [other] explicitly supplied on top of this config,
  /// leaving fields [other] left unset as they are here.
  ///
  /// This mirrors what the platform does with the serialized payload, and is
  /// what keeps `Tracelet.activeConfig` in step with the values actually
  /// persisted natively after a partial `setConfig()` (#320). Without it the
  /// Dart mirror would report a default the platform never stored.
  ForegroundServiceConfig mergedWith(
    ForegroundServiceConfig other,
  ) => ForegroundServiceConfig(
    enabled: other._enabled ?? _enabled,
    channelId: other._channelId ?? _channelId,
    channelName: other._channelName ?? _channelName,
    notificationTitle: other._notificationTitle ?? _notificationTitle,
    notificationText: other._notificationText ?? _notificationText,
    notificationColor: other.notificationColor ?? notificationColor,
    notificationSmallIcon: other.notificationSmallIcon ?? notificationSmallIcon,
    notificationLargeIcon: other.notificationLargeIcon ?? notificationLargeIcon,
    notificationPriority: other._notificationPriority ?? _notificationPriority,
    notificationOngoing: other._notificationOngoing ?? _notificationOngoing,
    showNotificationOnPauseOnly:
        other._showNotificationOnPauseOnly ?? _showNotificationOnPauseOnly,
    actions: other._actions ?? _actions,
  );

  /// Returns this config with every field pinned to its effective value.
  ///
  /// Used by `ready()`, which establishes a complete native baseline rather
  /// than a partial update — so the platform's own defaults never have to match
  /// Dart's for correctness (#321).
  ForegroundServiceConfig resolved() => ForegroundServiceConfig(
    enabled: enabled,
    channelId: channelId,
    channelName: channelName,
    notificationTitle: notificationTitle,
    notificationText: notificationText,
    notificationColor: notificationColor,
    notificationSmallIcon: notificationSmallIcon,
    notificationLargeIcon: notificationLargeIcon,
    notificationPriority: notificationPriority,
    notificationOngoing: notificationOngoing,
    showNotificationOnPauseOnly: showNotificationOnPauseOnly,
    actions: actions,
  );

  /// Converts to Pigeon [TlForegroundServiceConfig].
  ///
  /// Unset fields are carried across as `null` so the platform can tell them
  /// apart from a supplied value and leave the persisted one alone (#320).
  TlForegroundServiceConfig toTlConfig() => TlForegroundServiceConfig(
    enabled: _enabled,
    channelId: _channelId,
    channelName: _channelName,
    notificationTitle: _notificationTitle,
    notificationText: _notificationText,
    notificationColor: notificationColor,
    notificationSmallIcon: notificationSmallIcon,
    notificationLargeIcon: notificationLargeIcon,
    notificationPriority: _notificationPriority == null
        ? null
        : TlNotificationPriority.values[_notificationPriority.index],
    notificationOngoing: _notificationOngoing,
    showNotificationOnPauseOnly: _showNotificationOnPauseOnly,
    actions: _actions,
  );

  /// Serializes to a map, omitting fields that were never provided (#320).
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (_enabled != null) 'enabled': _enabled,
      if (_channelId != null) 'channelId': _channelId,
      if (_channelName != null) 'channelName': _channelName,
      if (_notificationTitle != null) 'notificationTitle': _notificationTitle,
      if (_notificationText != null) 'notificationText': _notificationText,
      if (notificationColor != null) 'notificationColor': notificationColor,
      if (notificationSmallIcon != null)
        'notificationSmallIcon': notificationSmallIcon,
      if (notificationLargeIcon != null)
        'notificationLargeIcon': notificationLargeIcon,
      if (_notificationPriority != null)
        'notificationPriority': _notificationPriority.index,
      if (_notificationOngoing != null)
        'notificationOngoing': _notificationOngoing,
      if (_showNotificationOnPauseOnly != null)
        'showNotificationOnPauseOnly': _showNotificationOnPauseOnly,
      if (_actions != null) 'actions': _actions,
    };
  }

  // Equality compares the backing fields, not the resolved values: an unset
  // field and one explicitly set to its default produce identical behaviour but
  // serialise differently, and treating them as equal would let a copyWith or a
  // cache comparison quietly lose the distinction the fix depends on.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForegroundServiceConfig &&
          runtimeType == other.runtimeType &&
          _enabled == other._enabled &&
          _channelId == other._channelId &&
          _channelName == other._channelName &&
          _notificationTitle == other._notificationTitle &&
          _notificationText == other._notificationText &&
          notificationColor == other.notificationColor &&
          notificationSmallIcon == other.notificationSmallIcon &&
          notificationLargeIcon == other.notificationLargeIcon &&
          _notificationPriority == other._notificationPriority &&
          _notificationOngoing == other._notificationOngoing &&
          _showNotificationOnPauseOnly == other._showNotificationOnPauseOnly &&
          _actionsEqual(_actions, other._actions);

  @override
  int get hashCode => Object.hash(
    _enabled,
    _channelId,
    _channelName,
    _notificationTitle,
    _notificationText,
    notificationColor,
    notificationSmallIcon,
    notificationLargeIcon,
    _notificationPriority,
    _notificationOngoing,
    _showNotificationOnPauseOnly,
    _actions == null ? null : Object.hashAll(_actions),
  );
}

/// Compares two optional action lists by content.
///
/// `null` (unset) and `[]` (explicitly empty) are deliberately not equal — they
/// serialise differently (#320).
bool _actionsEqual(List<String>? a, List<String>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

NotificationPriority _parseNotificationPriority(Object? value) {
  final index = value is int ? value : 2;
  if (index < 0 || index >= NotificationPriority.values.length) {
    return NotificationPriority.defaultPriority;
  }
  return NotificationPriority.values[index];
}
