import 'dart:async';
import 'dart:convert' show jsonEncode;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

import 'package:tracelet/src/models/activity_change_event.dart';
import 'package:tracelet/src/models/attestation_config.dart';
import 'package:tracelet/src/models/audit_config.dart';
import 'package:tracelet/src/models/driving_event.dart';
import 'package:tracelet/src/models/audit_proof.dart';
import 'package:tracelet/src/models/authorization_event.dart';
import 'package:tracelet/src/models/compliance_report.dart';
import 'package:tracelet/src/models/config.dart';
import 'package:tracelet/src/models/connectivity_change_event.dart';
import 'package:tracelet/src/models/device_info.dart';
import 'package:tracelet/src/models/geofence.dart';
import 'package:tracelet/src/models/geofence_event.dart';
import 'package:tracelet/src/models/geofences_change_event.dart';
import 'package:tracelet/src/models/headless_event.dart';
import 'package:tracelet/src/models/health_check.dart';
import 'package:tracelet/src/models/heartbeat_event.dart';
import 'package:tracelet/src/models/http_event.dart';
import 'package:tracelet/src/models/location.dart';
import 'package:tracelet/src/models/privacy_zone.dart';
import 'package:tracelet/src/models/privacy_zone_config.dart';
import 'package:tracelet/src/models/provider_change_event.dart';
import 'package:tracelet/src/models/route_context.dart';
import 'package:tracelet/src/models/sensors.dart';
import 'package:tracelet/src/models/sql_query.dart';
import 'package:tracelet/src/models/state.dart';
import 'package:tracelet/src/models/sync_body_context.dart';
import 'package:tracelet/src/models/trip_event.dart';
import 'package:tracelet/src/models/trip_start_event.dart';
import 'package:tracelet/src/models/speed_motion_event.dart';
import 'package:tracelet/src/models/log_entry.dart';
import 'package:tracelet/src/models/telematics_record.dart';

/// Production-grade background geolocation for Flutter.
///
/// The main entry point for the Tracelet plugin. All methods are **static**
/// (singleton pattern). Call [ready] before using any other method.
///
/// ```dart
/// import 'package:tracelet/tracelet.dart' as tl;
///
/// // 1. Subscribe to events
/// tl.Tracelet.onLocation((location) {
///   print('${location.coords.latitude}, ${location.coords.longitude}');
/// });
///
/// // 2. Initialize
/// final state = await tl.Tracelet.ready(tl.Config(
///   geo: tl.GeoConfig(desiredAccuracy: tl.DesiredAccuracy.high),
/// ));
///
/// // 3. Start tracking
/// await tl.Tracelet.start();
/// ```
class Tracelet {
  Tracelet._(); // Prevent instantiation.

  /// The platform implementation delegate.
  static TraceletPlatform get _platform => TraceletPlatform.instance;

  // ---------------------------------------------------------------------------
  // Event streams (via platform Pigeon FlutterApi)
  // ---------------------------------------------------------------------------

  /// Tracks subscriptions created by [watchPosition] so they can be
  /// cancelled by [stopWatchPosition].
  static final Map<int, StreamSubscription<Object?>> _watchSubscriptions =
      <int, StreamSubscription<Object?>>{};

  /// Tracks all subscriptions created by `onXxx()` event methods so
  /// [removeListeners] can cancel them.
  static final List<StreamSubscription<dynamic>> _onSubscriptions =
      <StreamSubscription<dynamic>>[];

  // ---------------------------------------------------------------------------
  // Shared Dart algorithms
  // ---------------------------------------------------------------------------

  /// Trip manager instance for trip detection (runs in Dart, not native).
  static final TripManager _tripManager = TripManager();

  /// StreamController for trip events (computed in Dart, not native).
  static final StreamController<TripEvent> _tripController =
      StreamController<TripEvent>.broadcast();

  /// StreamController for trip *start* events (#402).
  static final StreamController<TripStartEvent> _tripStartController =
      StreamController<TripStartEvent>.broadcast();

  /// Internal subscriptions that drive the TripManager.
  static StreamSubscription<Location>? _tripLocationSub;
  static StreamSubscription<Location>? _tripMotionSub;

  /// Battery budget engine instance (null when disabled).
  static BatteryBudgetEngine? _batteryBudgetEngine;

  /// StreamController for budget adjustment events.
  static final StreamController<BudgetAdjustmentEvent> _budgetController =
      StreamController<BudgetAdjustmentEvent>.broadcast();

  /// Subscription that feeds location battery levels to the budget engine.
  static StreamSubscription<Location>? _budgetLocationSub;

  /// StreamController for remote-config-applied events (Enterprise).
  ///
  /// Emits the merged active [Config] whenever the native layer applies a
  /// remotely-fetched configuration override at runtime.
  static final StreamController<Config> _remoteConfigController =
      StreamController<Config>.broadcast();

  /// Internal subscription that folds native remote-config overrides into
  /// [_currentConfig]. Set up once in [ready]; persists for the app lifetime so
  /// [activeConfig] stays in sync even when the app has no explicit listener.
  static StreamSubscription<Map<String?, Object?>>? _remoteConfigSub;

  /// Cached processed location broadcast stream.
  ///
  /// Filtering and Kalman smoothing are applied ONCE here, then shared
  /// across all `onLocation` subscribers.
  static Stream<Location>? _processedLocationStream;

  // Cached broadcast streams for public stream getters.
  static Stream<Location>? _motionChangeStream;
  static Stream<ActivityChangeEvent>? _activityChangeStream;
  static Stream<ProviderChangeEvent>? _providerChangeStream;
  static Stream<GeofenceEvent>? _geofenceStream;
  static Stream<GeofencesChangeEvent>? _geofencesChangeStream;
  static Stream<HeartbeatEvent>? _heartbeatStream;
  static Stream<HttpEvent>? _httpStream;
  static Stream<State>? _scheduleStream;
  static Stream<ConnectivityChangeEvent>? _connectivityChangeStream;
  static Stream<DrivingEvent>? _drivingEventStream;
  static Stream<ImpactEvent>? _impactStream;
  static Stream<ModeChangeEvent>? _modeChangeStream;
  static Stream<CrashModelStatusEvent>? _crashModelStatusStream;

  /// Whether the Kalman filter is currently enabled for GPS smoothing.
  ///
  /// Returns `true` if [ready] or [setConfig] was called with
  /// `LocationFilter(useKalmanFilter: true)`.
  static bool get isKalmanFilterEnabled =>
      activeConfig.geo.filter.useKalmanFilter;

  /// Initialize or tear down the [BatteryBudgetEngine] based on [config].
  static void _initBatteryBudget(Config config) {
    if (config.geo.batteryBudgetPerHour > 0) {
      _batteryBudgetEngine = BatteryBudgetEngine(
        targetBudgetPerHour: config.geo.batteryBudgetPerHour,
        initialDistanceFilter: config.geo.distanceFilter,
        initialAccuracyIndex: config.geo.desiredAccuracy.index,
        initialPeriodicInterval: config.geo.periodicLocationInterval > 0
            ? config.geo.periodicLocationInterval
            : null,
      );
    } else {
      _batteryBudgetEngine = null;
    }
  }

  /// Folds a native remote-config override map into the Dart-side active config.
  ///
  /// The native layer has already applied [remote] to its own config/engines;
  /// this keeps the Dart mirror ([_currentConfig], and therefore [activeConfig],
  /// diagnostics, and the Dart-side battery-budget engine) in sync, then
  /// notifies [onRemoteConfig] listeners with the merged [Config].
  static void _applyRemoteConfig(Map<String?, Object?> remote) {
    if (remote.isEmpty) return;
    // Pigeon delivers String?/Object? keys with nested Map<Object?, Object?>;
    // normalize to the Map<String, Object?> shape Config.fromMap expects.
    final overrides = _deepCastMap(remote.cast<Object?, Object?>());
    final mergedMap = _deepMergeConfig(_currentConfig.toMap(), overrides);
    final merged = Config.fromMap(mergedMap);
    _currentConfig = merged;
    // Re-init the Dart battery-budget engine and invalidate the processed
    // location stream so both pick up the new settings.
    _initBatteryBudget(merged);
    _processedLocationStream = null;
    if (_remoteConfigController.hasListener) {
      _remoteConfigController.add(merged);
    }
  }

  /// Recursively merges [overrides] onto [base], with nested maps merged
  /// key-by-key (leaf values in [overrides] win). Used to apply a partial
  /// remote-config map (e.g. `{geo: {batteryBudgetPerHour: 1.0}}`) onto the full
  /// current config without dropping unspecified fields.
  static Map<String, Object?> _deepMergeConfig(
    Map<String, Object?> base,
    Map<String, Object?> overrides,
  ) {
    final result = Map<String, Object?>.from(base);
    overrides.forEach((key, value) {
      final existing = result[key];
      if (existing is Map && value is Map) {
        result[key] = _deepMergeConfig(
          Map<String, Object?>.from(existing),
          Map<String, Object?>.from(value),
        );
      } else {
        result[key] = value;
      }
    });
    return result;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------
  static Config _currentConfig = const Config();

  /// Gets the currently active plugin configuration.
  static Config get activeConfig => _currentConfig;

  /// Builds a [State] from a platform result map, backfilling the active
  /// configuration when the native layer omits it.
  ///
  /// Issue #147: the Pigeon `TlState` FFI struct did not carry the active
  /// config, so `State.config` was permanently `null` from `ready()` /
  /// `getState()`. The Dart layer authoritatively tracks the active config in
  /// [_currentConfig], so we populate `state.config` from it whenever the
  /// native map does not already provide one.
  static State _stateFromMap(Map<String, Object?> result) {
    final map = result['config'] == null
        ? <String, Object?>{...result, 'config': _currentConfig.toMap()}
        : result;
    return State.fromMap(map);
  }

  /// Whether [registerHeadlessTask] has been called in this isolate.
  ///
  /// Used by diagnostic tools (e.g. `tracelet_doctor`) to warn when
  /// background tracking is configured but no headless handler is registered.
  static bool _headlessRegistered = false;

  /// Whether a headless background task callback has been registered.
  ///
  /// Returns `true` after [registerHeadlessTask] has been called.
  /// Returns `false` on web (headless isolates not supported).
  static bool get isHeadlessRegistered => _headlessRegistered;

  /// Ensures the Rust core is initialized before calling Rust-backed algorithms.
  static Future<void> _ensureRustLibInitialized() async {
    try {
      // ignore: invalid_use_of_internal_member
      if (!RustLib.instance.initialized) {
        await initializeRustLib();
      }
    } catch (e) {
      if (e is StateError &&
          (e.message.contains('already initialized') ||
              e.message.contains('initialize flutter_rust_bridge twice'))) {
        // Ignored if already initialized concurrently
      } else if (e.toString().contains('Failed to load dynamic library')) {
        // Ignored in tests where the rust dynamic library isn't built
      } else {
        rethrow;
      }
    }
  }

  /// Initialize the plugin and apply the [Config].
  ///
  /// This must be called before [start] to configure the plugin's behavior.
  /// It returns the current [State] of the plugin.
  ///
  /// ```dart
  /// final state = await Tracelet.ready(Config(
  ///   geo: GeoConfig(distanceFilter: 10.0),
  /// ));
  /// print('Enabled: ${state.enabled}');
  /// ```
  static Future<State> ready(Config rawConfig) async {
    await _ensureRustLibInitialized();
    // [ready] establishes the complete baseline, so every field is pinned to
    // its effective value before it crosses the channel. [setConfig] is the
    // partial one and sends only what the caller set; keeping the two apart is
    // what lets an unset field be omitted without the platforms' own defaults
    // having to match Dart's (#321).
    final config = rawConfig.resolved();
    _currentConfig = config;

    // Initialize battery budget engine from config.
    _initBatteryBudget(config);

    // Enterprise remote config is fetched and applied entirely on the native
    // side; the fetch never round-trips through Dart. Subscribe once so that
    // when native applies a remote override at runtime we fold it into
    // [_currentConfig] — otherwise [activeConfig] (and tools like
    // tracelet_doctor, plus the Dart-side battery-budget engine) would keep
    // showing the last locally-set values. Accessing the stream also ensures
    // the Pigeon event channel is registered so the event can arrive.
    _remoteConfigSub ??= _platform.remoteConfigEvents.listen(
      _applyRemoteConfig,
    );

    // Wire trip manager output to the Dart stream controllers.
    _tripManager.onTripStart = (tripData) {
      _tripStartController.add(TripStartEvent.fromMap(tripData));
    };
    _tripManager.onTripEnd = (tripData) {
      _tripController.add(TripEvent.fromMap(tripData));
    };

    _checkSyncProvider(config);

    final result = await _platform.ready(config.toTlConfig());
    return _stateFromMap(result);
  }

  /// Start location tracking.
  ///
  /// Returns the updated [State] after starting.
  static Future<State> start() async {
    await _ensureRustLibInitialized();
    final result = await _platform.start();

    // Start internal trip detection subscriptions.
    _startTripDetection();

    // Start battery budget tracking if enabled.
    _startBatteryBudgetTracking();

    return _stateFromMap(result);
  }

  /// Stop location tracking.
  ///
  /// Returns the updated [State] after stopping.
  static Future<State> stop() async {
    await _ensureRustLibInitialized();
    final result = await _platform.stop();

    // Stop trip detection and reset.
    _stopTripDetection();
    _tripManager.reset();
    _stopBatteryBudgetTracking();
    _batteryBudgetEngine?.reset();

    return _stateFromMap(result);
  }

  /// Request the native service to terminate from a headless isolate.
  ///
  /// Unlike [stop], this uses the headless MethodChannel directly,
  /// so it works from FCM background handlers where Pigeon is unavailable.
  /// Returns whether the native service acknowledged the request.
  /// No [State] is returned since Pigeon is unavailable in headless isolates.
  ///
  /// Android only. On iOS, returns `false` (headless architecture differs).
  static Future<bool> requestTermination() async {
    try {
      const channel = MethodChannel('com.tracelet/methods');
      final result = await channel.invokeMethod<bool>('requestTermination');
      return result ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Start geofence-only tracking mode.
  ///
  /// The plugin will only monitor geofences without continuous location
  /// tracking, saving significant battery.
  static Future<State> startGeofences() async {
    final result = await _platform.startGeofences();
    return _stateFromMap(result);
  }

  /// Start periodic one-shot location tracking mode.
  ///
  /// Instead of continuous GPS updates (which keep the GPS icon permanently
  /// visible), this mode wakes every [GeoConfig.periodicLocationInterval]
  /// seconds, performs a single location fix, dispatches the result, and
  /// immediately turns the location provider off.
  ///
  /// The GPS icon (Android) / blue arrow (iOS) is only visible for ~5–10
  /// seconds per fix instead of permanently.
  ///
  /// Configure via [GeoConfig]:
  /// - `periodicLocationInterval` — seconds between fixes (default: 900 = 15 min)
  /// - `periodicDesiredAccuracy` — accuracy per fix (default: `DesiredAccuracy.medium`)
  /// - `periodicUseForegroundService` — use foreground service on Android (default: `false`)
  /// - `periodicUseExactAlarms` — use exact alarms on Android (default: `false`)
  ///
  /// ```dart
  /// await Tracelet.ready(Config(
  ///   geo: GeoConfig(
  ///     periodicLocationInterval: 1800,
  ///     periodicDesiredAccuracy: DesiredAccuracy.medium,
  ///   ),
  /// ));
  /// await Tracelet.startPeriodic();
  /// ```
  static Future<State> startPeriodic() async {
    final result = await _platform.startPeriodic();
    return _stateFromMap(result);
  }

  /// Get the current plugin [State].
  static Future<State> getState() async {
    final result = await _platform.getState();
    return _stateFromMap(result);
  }

  /// Get a comprehensive diagnostic snapshot of the plugin's operational health.
  ///
  /// Aggregates tracking state, permissions, provider availability, battery/OEM
  /// status, sensor availability, and database metrics into a single typed
  /// [HealthCheck] object with automatically computed [HealthCheck.warnings].
  ///
  /// This replaces the need to call [getState], [getProviderState],
  /// [getSettingsHealth], [isPowerSaveMode], [getSensors], and other
  /// diagnostic methods individually.
  ///
  /// ```dart
  /// final health = await Tracelet.getHealth();
  ///
  /// if (health.isAggressiveOem) {
  ///   // Show OEM battery settings guide
  /// }
  ///
  /// for (final warning in health.warnings) {
  ///   print('Warning: $warning');
  /// }
  /// ```
  static Future<HealthCheck> getHealth() async {
    // Fire all independent platform calls in parallel.
    final results = await Future.wait([
      _platform.getState(), // 0
      _platform.getProviderState(), // 1
      _platform.getSettingsHealth(), // 2
      _platform.getSensors(), // 3
      _platform.getDeviceInfo(), // 4
      _platform.isPowerSaveMode(), // 5
      _platform.isIgnoringBatteryOptimizations(), // 6
      _platform.getLocationAuthorization(), // 7 (AuthorizationStatus)
      _platform.getMotionAuthorization(), // 8 (MotionAuthorizationStatus)
      _platform.getCount(), // 9
    ]);

    return HealthCheck.fromMaps(
      state: Map<String, Object?>.from(results[0] as Map),
      provider: Map<String, Object?>.from(results[1] as Map),
      settingsHealth: Map<String, Object?>.from(results[2] as Map),
      sensors: Map<String, Object?>.from(results[3] as Map),
      deviceInfo: Map<String, Object?>.from(results[4] as Map),
      isPowerSave: results[5] as bool,
      ignoringBatteryOpt: results[6] as bool,
      locationPermissionStatus: (results[7] as AuthorizationStatus).index,
      motionPermissionStatus: (results[8] as MotionAuthorizationStatus).index,
      dbCount: results[9] as int,
    );
  }

  /// Update the plugin configuration.
  ///
  /// This is a **partial update**. Only the fields you actually set are sent;
  /// everything else keeps the value the platform already persisted, in every
  /// section (#320, #321):
  ///
  /// ```dart
  /// // Changes one flag. The notification title and channel from ready(),
  /// // the HTTP URL, distanceFilter, stopOnTerminate — all survive.
  /// await Tracelet.setConfig(const Config(
  ///   android: AndroidConfig(
  ///     foregroundService: ForegroundServiceConfig(
  ///       showNotificationOnPauseOnly: true,
  ///     ),
  ///   ),
  /// ));
  ///
  /// // Changes nothing at all.
  /// await Tracelet.setConfig(const Config());
  /// ```
  ///
  /// Passing a value equal to its default is still an explicit write, so a
  /// flag can always be set back — "unset" means *not provided*, never *equal
  /// to the default*. Use [ready] to establish or replace the full baseline.
  ///
  /// Returns the updated [State].
  static Future<State> setConfig(Config config) async {
    // Mirror the platform's merge across every section, so [activeConfig]
    // keeps reporting the values actually persisted natively instead of the
    // defaults this call left unset (#320, #321).
    final merged = _currentConfig.mergedWith(config);
    _currentConfig = merged;

    // Update battery budget engine from config.
    _initBatteryBudget(merged);
    // Invalidate cached stream pipeline so it rebuilds with new settings (D-M8).
    _processedLocationStream = null;

    _checkSyncProvider(merged);

    // Deliberately sends `config`, not `merged`: the payload must carry only
    // the fields this call actually set, so the platform can leave everything
    // else at its persisted value.
    final s = await _platform.setConfig(config.toTlConfig());
    return _stateFromMap(s);
  }

  /// Refreshes the active on-screen tracking indicator so it reflects the
  /// latest configuration applied via [setConfig], without restarting the
  /// tracking pipeline (#257).
  ///
  /// Content-only configuration changes made through [setConfig] do not rebuild
  /// the indicator currently displayed by the OS. Call this after updating the
  /// relevant config to refresh it in place while background tracking remains
  /// active:
  /// - **Android**: reposts the foreground-service notification from the latest
  ///   [ForegroundServiceConfig] (title, text, icon, color, actions, priority,
  ///   ongoing state). Safe no-op when the foreground service is not running.
  /// - **iOS**: if the developer opted into a Live Activity via
  ///   [LiveActivityConfig] (and added the Widget Extension), refreshes the
  ///   Live Activity from the latest config while a tracking session is active —
  ///   updating the running activity's body in place, or re-presenting it if it
  ///   isn't currently on screen (the activity is bound to the moving
  ///   sub-state, so a transient stop can dismiss it). The title is immutable on
  ///   a running activity. Safe no-op when no Live Activity is configured or
  ///   tracking is stopped.
  /// - **Web**: no-op.
  static Future<void> updateNotification() {
    return _platform.updateNotification();
  }

  /// Verifies if tracelet_sync is installed/registered when HTTP URL is configured.
  /// Displays a developer warning in the console if sync is setup without the sync package.
  static void _checkSyncProvider(Config config) {
    final httpUrl = config.http.url ?? '';
    if (httpUrl.isNotEmpty) {
      scheduleMicrotask(() async {
        try {
          await const MethodChannel('tracelet_sync').invokeMethod('initialize');
        } on MissingPluginException {
          // ignore: avoid_print
          print(
            '⚠️ WARNING [Tracelet]: HTTP sync URL is configured ("$httpUrl"), '
            'but the "tracelet_sync" package is not installed or registered. '
            'Location synchronization will not work without "tracelet_sync". '
            'Please ensure that you have added "tracelet_sync" to your pubspec.yaml '
            'dependencies.',
          );
        } catch (e) {
          // Other exceptions are ignored since they imply the channel is registered.
        }
      });
    }
  }

  /// Reset to default configuration, optionally applying a new [config].
  ///
  /// Like [ready] and unlike [setConfig], this replaces the whole baseline, so
  /// [config] is sent with every field resolved to its effective value (#321).
  ///
  /// Returns the updated [State].
  static Future<State> reset([Config? config]) async {
    final result = await _platform.reset(config?.resolved().toTlConfig());
    return _stateFromMap(result);
  }

  // ---------------------------------------------------------------------------
  // Location
  // ---------------------------------------------------------------------------

  /// Get the current position as a one-shot request.
  ///
  /// This is the primary method for obtaining a single location fix without
  /// starting continuous tracking. It activates the location provider
  /// momentarily, obtains a fix, and returns the result.
  ///
  /// **Parameters:**
  ///
  /// - [desiredAccuracy]: The accuracy level for this request. Because this is
  ///   an explicit one-shot request, it defaults to [DesiredAccuracy.high] —
  ///   it does NOT inherit the (possibly passive) background tracking profile,
  ///   which could otherwise never return a fix. Pass a lower value to trade
  ///   accuracy for battery on this single call.
  /// - [timeout]: Maximum time (in seconds) to wait for a location fix.
  ///   Defaults to `30` seconds.
  /// - [maximumAge]: Maximum age (in milliseconds) of a cached location that
  ///   is acceptable to return. If a cached location exists within this age,
  ///   it is returned immediately without activating the provider.
  ///   Defaults to `0` (always fetch a fresh fix).
  /// - [persist]: Whether to persist the obtained location to the local
  ///   SQLite database. Set to `false` for ephemeral reads (e.g., showing
  ///   current position on a map). Defaults to `true`.
  /// - [samples]: Number of location samples to collect. The sample with the
  ///   best accuracy (lowest `horizontalAccuracy` value) is returned. Useful
  ///   for obtaining a high-quality fix at the cost of slightly more time
  ///   and battery. Defaults to `1`.
  /// - [accuracyTarget]: Optional horizontal-accuracy target in metres. When
  ///   present, native acquisition remains active until a fix reaches the
  ///   target or [timeout] expires; [samples] no longer ends acquisition early.
  /// - [requestId]: Optional caller-owned identifier used to cancel this
  ///   request with [cancelCurrentPosition].
  /// - [extras]: Extra key-value pairs to attach to the returned location.
  ///
  /// **Example — simple one-shot:**
  /// ```dart
  /// final location = await Tracelet.getCurrentPosition();
  /// print('${location.coords.latitude}, ${location.coords.longitude}');
  /// ```
  ///
  /// **Example — high-quality fix without persistence:**
  /// ```dart
  /// final location = await Tracelet.getCurrentPosition(
  ///   desiredAccuracy: DesiredAccuracy.high,
  ///   samples: 3,
  ///   persist: false,
  ///   timeout: 15,
  /// );
  /// ```
  static Future<Location> getCurrentPosition({
    DesiredAccuracy? desiredAccuracy,
    int? timeout,
    int? maximumAge,
    bool? persist,
    int? samples,
    double? accuracyTarget,
    String? requestId,
    Map<String, Object?>? extras,
  }) async {
    final options = TlCurrentPositionOptions(
      desiredAccuracy: TlDesiredAccuracy
          .values[(desiredAccuracy ?? DesiredAccuracy.high).index],
      timeout: timeout ?? 30,
      maximumAge: maximumAge ?? 0,
      persist: persist ?? true,
      samples: samples ?? 1,
      accuracyTarget: accuracyTarget,
      requestId: requestId,
      extras: extras,
    );
    final result = await _platform.getCurrentPosition(options);
    return Location.fromMap(result);
  }

  /// Cancels an active one-shot request identified by [requestId].
  static Future<bool> cancelCurrentPosition(String requestId) =>
      _platform.cancelCurrentPosition(requestId);

  /// Get the last known location without requesting a new fix.
  ///
  /// Returns the most recently cached location from the platform's location
  /// provider. **This method never activates GPS or network providers** — it
  /// is a zero-battery-cost operation.
  ///
  /// Returns `null` if no cached location is available (e.g., the device has
  /// never obtained a location fix, or the cache has been cleared).
  ///
  /// **Parameters:**
  ///
  /// - [persist]: Whether to persist the returned location to the local
  ///   SQLite database. Defaults to `false`.
  /// - [extras]: Extra key-value pairs to attach to the returned location.
  ///
  /// **Use cases:**
  /// - Showing a quick "last seen" position on a map before a fresh fix
  ///   arrives.
  /// - Checking approximate location without incurring any battery cost.
  /// - Pre-filling a location field in a form.
  ///
  /// **Example:**
  /// ```dart
  /// final location = await Tracelet.getLastKnownLocation();
  /// if (location != null) {
  ///   print('Last known: ${location.coords.latitude}');
  /// } else {
  ///   print('No cached location available.');
  /// }
  /// ```
  static Future<Location?> getLastKnownLocation({
    bool persist = false,
    Map<String, Object?>? extras,
  }) async {
    final options = TlCurrentPositionOptions(persist: persist, extras: extras);
    final result = await _platform.getLastKnownLocation(options);
    if (result.isEmpty) return null;
    return Location.fromMap(result);
  }

  /// Start watching position at a high-frequency interval.
  ///
  /// Returns a watch ID that can be used to stop the watch via
  /// [stopWatchPosition]. The [callback] is invoked for each new location.
  static Future<int> watchPosition(
    void Function(Location) callback, {
    int? interval,
    DesiredAccuracy? desiredAccuracy,
    Map<String, Object?>? extras,
  }) async {
    // Note: `interval` has no field on the typed pigeon options and was already
    // dropped by the previous Map conversion, so behavior is unchanged (#206).
    final options = TlCurrentPositionOptions(
      desiredAccuracy: desiredAccuracy != null
          ? TlDesiredAccuracy.values[desiredAccuracy.index]
          : null,
      extras: extras,
    );
    final watchId = await _platform.watchPosition(options);

    // Listen to the watchPosition event stream for this watcher.
    // Store the subscription so stopWatchPosition can cancel it.
    final sub = _platform.watchPositionEvents
        .map(Location.fromTl)
        .listen(callback);

    _watchSubscriptions[watchId] = sub;
    return watchId;
  }

  /// Stop a watch started by [watchPosition].
  ///
  /// Cancels both the native watcher and the Dart stream subscription.
  static Future<bool> stopWatchPosition(int watchId) async {
    await _watchSubscriptions.remove(watchId)?.cancel();
    return _platform.stopWatchPosition(watchId);
  }

  /// Toggle the motion state.
  ///
  /// `isMoving: true` forces the plugin into moving mode (high-frequency
  /// updates). `isMoving: false` forces stationary mode.
  static Future<bool> changePace(bool isMoving) {
    return _platform.changePace(isMoving);
  }

  /// Temporarily overrides the active OS location-provider options.
  ///
  /// This is intended for short-lived acquisition policies such as reducing
  /// GPS power while the device is known to be stationary. It updates the
  /// running provider without calling [stop] or [start]. The persisted [Config],
  /// [activeConfig], and the accepted-point filtering pipeline are unchanged.
  ///
  /// Passing no arguments clears the override and restores the options from
  /// [activeConfig]. The override is also cleared when tracking stops. Returns
  /// `false` when tracking is not active or the platform does not support live
  /// provider updates. Supported on iOS (live `CLLocationManager` property
  /// update) and Android (callback-preserving fused-request re-subscription);
  /// web returns `false`.
  ///
  /// [distanceFilter] must be finite and non-negative. A value of zero requests
  /// all provider updates (`kCLDistanceFilterNone` on iOS).
  ///
  /// ```dart
  /// await Tracelet.updateLocationProviderOptions(
  ///   desiredAccuracy: DesiredAccuracy.medium,
  ///   distanceFilter: 25,
  /// );
  ///
  /// // Restore the configured provider options without restarting tracking.
  /// await Tracelet.updateLocationProviderOptions();
  /// ```
  static Future<bool> updateLocationProviderOptions({
    DesiredAccuracy? desiredAccuracy,
    double? distanceFilter,
  }) {
    if (distanceFilter != null &&
        (!distanceFilter.isFinite || distanceFilter < 0)) {
      throw RangeError.value(
        distanceFilter,
        'distanceFilter',
        'Must be finite and non-negative',
      );
    }

    return _platform.updateLocationProviderOptions(
      desiredAccuracy == null
          ? null
          : TlDesiredAccuracy.values[desiredAccuracy.index],
      distanceFilter,
    );
  }

  /// Confirms a pending impact candidate ([ImpactEvent.id]) as a real
  /// emergency, firing its confirmed `crash`/`fall` event immediately.
  static Future<bool> confirmImpact(int id) {
    return _platform.confirmImpact(id);
  }

  /// Cancels a pending impact candidate ([ImpactEvent.id]) within its
  /// confirmation window — no confirmed event will fire. Call this when the
  /// user dismisses the crash/fall countdown ("I'm fine").
  static Future<bool> cancelImpact(int id) {
    return _platform.cancelImpact(id);
  }

  /// Get the current odometer value in meters.
  static Future<double> getOdometer() {
    return _platform.getOdometer();
  }

  /// Set the odometer value.
  ///
  /// Returns the [Location] at the reset point.
  static Future<Location> setOdometer(double value) async {
    final result = await _platform.setOdometer(value);
    return Location.fromMap(result);
  }

  // ---------------------------------------------------------------------------
  // Geofencing
  // ---------------------------------------------------------------------------

  /// Add a single [Geofence] to the monitoring list.
  static Future<bool> addGeofence(Geofence geofence) {
    return _platform.addGeofence(geofence.toTlGeofence());
  }

  /// Add multiple [Geofence]s at once.
  static Future<bool> addGeofences(List<Geofence> geofences) {
    return _platform.addGeofences(
      geofences.map((g) => g.toTlGeofence()).toList(growable: false),
    );
  }

  /// Remove a geofence by its [identifier].
  static Future<bool> removeGeofence(String identifier) {
    return _platform.removeGeofence(identifier);
  }

  /// Remove all geofences.
  static Future<bool> removeGeofences() {
    return _platform.removeGeofences();
  }

  /// Get all registered geofences.
  static Future<List<Geofence>> getGeofences() async {
    final result = await _platform.getGeofences();
    return result.map(Geofence.fromMap).toList();
  }

  /// Get a single geofence by [identifier], or `null` if not found.
  static Future<Geofence?> getGeofence(String identifier) async {
    final result = await _platform.getGeofence(identifier);
    if (result == null) return null;
    return Geofence.fromMap(result);
  }

  /// Check whether a geofence with the given [identifier] exists.
  static Future<bool> geofenceExists(String identifier) {
    return _platform.geofenceExists(identifier);
  }

  // ---------------------------------------------------------------------------
  // Persistence & Logs & Telematics
  // ---------------------------------------------------------------------------

  /// Get stored logs from the native SQLite database.
  ///
  /// The [limit] controls the maximum number of logs returned.
  static Future<List<LogEntry>> getLogs(int limit) async {
    final result = await _platform.getLogs(limit);
    return result.whereType<TlLogEntry>().map(LogEntry.fromTl).toList();
  }

  /// Delete all stored background logs from the native SQLite database.
  static Future<void> clearLogs() async {
    await _platform.clearLogs();
  }

  /// Get stored telematics events — **most recent first**.
  ///
  /// Returns up to [limit] driving/impact events from the local database,
  /// newest first, whether or not they have already been synced. Enabling
  /// `syncTelematics` therefore no longer empties your own local history
  /// (#313).
  static Future<List<TelematicsRecord>> getTelematicsEvents(int limit) async {
    final result = await _platform.getTelematicsEvents(limit);
    return result
        .whereType<TlTelematicsRecord>()
        .map(TelematicsRecord.fromTl)
        .toList();
  }

  /// Destroy all stored telematics events.
  static Future<bool> destroyTelematicsEvents() {
    return _platform.destroyTelematicsEvents();
  }

  /// Manually insert a telematics event (e.g. for testing with the Doctor UI).
  static Future<bool> simulateTelematicsEvent({
    required String eventType,
    required double severity,
    required double latitude,
    required double longitude,
  }) async {
    return _platform.simulateTelematicsEvent(
      eventType,
      severity,
      latitude,
      longitude,
    );
  }

  /// Debug-only (#183): runs one synthetic high-g window through the **real**
  /// crash-detection pipeline — including the loaded ML crash model — so you can
  /// verify the model path is active without producing a physical impact.
  ///
  /// Crash detection must be enabled (toggle it on and start tracking) for the
  /// pipeline to exist. Returns a map describing the inference:
  /// - `modelRan` (bool): whether the ML model produced a probability (false
  ///   means no model is loaded and only the rule engine ran).
  /// - `proba` (double): the model probability (`-1.0` when no model ran).
  /// - `threshold` (double): the configured crash-probability threshold.
  /// - `peakG` (double): the synthesized window peak.
  /// - `fired` (bool): whether a crash candidate was emitted.
  /// - `kind` (String?): the emitted candidate kind, if any.
  /// - `error` (String?): present when the pipeline could not run.
  static Future<Map<String, Object?>> debugRunCrashModelInference({
    double peakG = 5.0,
    double speedKmh = 60.0,
    bool crashLike = true,
  }) {
    return _platform.debugRunCrashModelInference(peakG, speedKmh, crashLike);
  }

  /// Get stored locations from the local database.
  ///
  /// Optionally pass a [query] to filter by time range and limit.
  static Future<List<Location>> getLocations([SQLQuery? query]) async {
    final result = await _platform.getLocations(query?.toMap());
    return result.map(Location.fromMap).toList();
  }

  /// Get the count of stored locations.
  ///
  /// Optionally pass a [query] to count only locations within a time range.
  /// Only [SQLQuery.start] and [SQLQuery.end] affect the count result;
  /// [SQLQuery.limit], [SQLQuery.offset], and [SQLQuery.order] are ignored.
  static Future<int> getCount([SQLQuery? query]) {
    return _platform.getCount(query?.toMap());
  }

  /// Get the locations still pending synchronization to the backend (#159).
  ///
  /// Tracelet prunes each record from the local store the moment it is confirmed
  /// synced, so every persisted location is by definition still *pending* upload.
  /// This is a convenience wrapper over [getLocations] that makes offline-queue
  /// monitoring explicit: the returned list is exactly the set of locations that
  /// have been captured/stored but not yet delivered (e.g. while offline).
  ///
  /// Optionally pass a [query] to filter by time range and limit.
  static Future<List<Location>> getPendingLocations([SQLQuery? query]) {
    return getLocations(query);
  }

  /// Get the number of locations still pending synchronization (#159).
  ///
  /// Because synced records are pruned immediately, this equals the size of the
  /// offline queue. Useful for surfacing queue depth to end users or for audit
  /// and diagnostics. See [getPendingLocations].
  ///
  /// Only [SQLQuery.start] and [SQLQuery.end] affect the result.
  static Future<int> getPendingLocationCount([SQLQuery? query]) {
    return getCount(query);
  }

  /// Destroy all stored locations.
  static Future<bool> destroyLocations() {
    return _platform.destroyLocations();
  }

  /// Destroy only locations that have been successfully synced to the server.
  ///
  /// Returns the number of synced locations deleted.
  ///
  /// Note: synced locations are also automatically purged after each
  /// successful HTTP sync cycle, so calling this manually is typically
  /// only needed for immediate cleanup.
  static Future<int> destroySyncedLocations() {
    return _platform.destroySyncedLocations();
  }

  /// Destroy a single location by [uuid].
  static Future<bool> destroyLocation(String uuid) {
    return _platform.destroyLocation(uuid);
  }

  /// Insert a custom location into the store.
  ///
  /// Returns the UUID of the inserted location.
  static Future<String> insertLocation(Map<String, Object?> params) {
    final mutableParams = Map<String, Object?>.from(params);
    if (mutableParams.containsKey('timestamp')) {
      final ts = mutableParams['timestamp'];
      DateTime? dt;
      if (ts is DateTime) {
        dt = ts;
      } else if (ts is int) {
        dt = DateTime.fromMillisecondsSinceEpoch(ts);
      } else if (ts is String) {
        dt = DateTime.tryParse(ts);
      }

      if (dt != null) {
        final utcDt = dt.toUtc();
        // Normalize to RFC3339 exact format to ensure SQLite string comparisons work flawlessly against Rust querying limits.
        mutableParams['timestamp'] = utcDt
            .toIso8601String()
            .replaceAll('.000Z', '+00:00')
            .replaceAll('Z', '+00:00');
      }
    }
    return _platform.insertLocation(mutableParams);
  }

  // ---------------------------------------------------------------------------
  // HTTP Sync
  // ---------------------------------------------------------------------------

  /// Manually trigger HTTP synchronization of pending locations.
  ///
  /// Returns the list of locations that were synced.
  static Future<List<Location>> sync() async {
    final result = await _platform.sync();
    return result.map(Location.fromMap).toList();
  }

  // ---------------------------------------------------------------------------
  // Dynamic Headers
  // ---------------------------------------------------------------------------

  /// Callback registered via [setHeadersCallback].
  static Future<Map<String, String>> Function()? _headersCallback;

  /// Update dynamic HTTP headers on the native side.
  ///
  /// Dynamic headers are merged with the static [HttpConfig.headers] at sync
  /// time. Dynamic headers take precedence when keys overlap.
  ///
  /// Call this whenever your auth token is refreshed:
  ///
  /// ```dart
  /// await Tracelet.setDynamicHeaders({
  ///   'Authorization': 'Bearer \$newToken',
  /// });
  /// ```
  static Future<bool> setDynamicHeaders(Map<String, String> headers) {
    return _platform.setDynamicHeaders(headers);
  }

  /// Register a callback that provides fresh HTTP headers on demand.
  ///
  /// When set, Tracelet will invoke this callback before each sync request
  /// (foreground only) to obtain fresh headers. The returned headers are
  /// sent to the native side via [setDynamicHeaders].
  ///
  /// Ideal for OAuth flows where tokens expire and need silent renewal:
  ///
  /// ```dart
  /// Tracelet.setHeadersCallback(() async {
  ///   final token = await authService.getFreshToken();
  ///   return {'Authorization': 'Bearer \$token'};
  /// });
  /// ```
  ///
  /// For background (headless) header recovery, also register
  /// [registerHeadlessHeadersCallback].
  static void setHeadersCallback(
    Future<Map<String, String>> Function()? callback,
  ) {
    _headersCallback = callback;
    if (callback != null) {
      _ensureSyncBodyChannel();
    }
  }

  /// Force a refresh of dynamic headers.
  ///
  /// Invokes the callback registered with [setHeadersCallback] and sends
  /// the resulting headers to the native side. If [force] is `true`,
  /// the refresh runs even if one was recently completed.
  ///
  /// Returns `true` if headers were refreshed, `false` if no callback
  /// is registered.
  static Future<bool> refreshHeaders({bool force = false}) async {
    final callback = _headersCallback;
    if (callback == null) return false;
    final headers = await callback();
    return _platform.setDynamicHeaders(headers);
  }

  // ---------------------------------------------------------------------------
  // Token Refresh (401 recovery)
  // ---------------------------------------------------------------------------

  /// Callback registered via [setTokenRefreshCallback].
  static Future<Map<String, String>> Function()? _tokenRefreshCallback;

  /// Register a callback that refreshes an expired auth token.
  ///
  /// When set, Tracelet's native HTTP sync engine will invoke this callback
  /// on a 401 Unauthorized response. The callback should:
  /// 1. Call your refresh-token API
  /// 2. Persist the new tokens
  /// 3. Return updated HTTP headers (including the new Authorization header)
  ///
  /// The returned headers are pushed to the native side via
  /// [setDynamicHeaders] and the failed request is retried automatically.
  ///
  /// In foreground, the callback runs via MethodChannel. In background
  /// (killed state), it falls back to the headless headers callback
  /// registered via [registerHeadlessHeadersCallback].
  ///
  /// ```dart
  /// Tracelet.setTokenRefreshCallback(() async {
  ///   final newToken = await authService.refreshToken();
  ///   return {
  ///     'Authorization': 'Bearer \$newToken',
  ///     // ... other headers
  ///   };
  /// });
  /// ```
  static void setTokenRefreshCallback(
    Future<Map<String, String>> Function()? callback,
  ) {
    _tokenRefreshCallback = callback;
    if (callback != null) {
      _ensureSyncBodyChannel();
    }
  }

  // ---------------------------------------------------------------------------
  // Route Context
  // ---------------------------------------------------------------------------

  /// Set the route context that will be persisted with every subsequently
  /// recorded location.
  ///
  /// Route context is captured **immutably at insert time** — it travels
  /// with the location row through the sync queue, even if the app changes
  /// context before the batch is drained.
  ///
  /// This is critical for multi-task or multi-driver apps:
  ///
  /// ```dart
  /// await Tracelet.setRouteContext(RouteContext(
  ///   taskId: 'delivery-42',
  ///   driverId: 'driver-7',
  ///   trackingSessionId: uuid.v4(),
  /// ));
  /// ```
  static Future<bool> setRouteContext(RouteContext context) {
    return _platform.setRouteContext(context.toMap());
  }

  /// Clear the current route context.
  ///
  /// Subsequent locations will have no route context attached.
  static Future<bool> clearRouteContext() {
    return _platform.clearRouteContext();
  }

  // ---------------------------------------------------------------------------
  // Custom Sync Body Builder
  // ---------------------------------------------------------------------------

  /// Callback registered via [setSyncBodyBuilder].
  static Future<Map<String, Object?>> Function(SyncBodyContext)?
  _syncBodyBuilder;

  /// Returned from the native `buildSyncBody` call when no custom builder is
  /// registered, so native can distinguish "no builder → use default payload"
  /// from "builder failed → abort the sync". Must match the native sentinels
  /// (`traceletNoSyncBodyBuilderSentinel` / `NO_SYNC_BODY_BUILDER_SENTINEL`).
  static const String _noSyncBodyBuilderSentinel =
      '__tracelet_no_sync_body_builder__';

  /// Whether the native sync body MethodChannel handler has been set up.
  static bool _syncBodyChannelReady = false;

  /// Recursively cast a platform map to `Map<String, Object?>`.
  ///
  /// Platform channels return `Map<Object?, Object?>` which can contain
  /// nested maps (e.g. `extras`). A shallow `Map.from` only casts the
  /// top level, leaving nested maps untyped.

  /// Register a custom sync body builder for foreground sync.
  ///
  /// When set, each sync request will invoke this callback with the batch
  /// of locations about to be sent. The returned map becomes the full HTTP
  /// request body, giving you full control over the JSON structure.
  ///
  /// ```dart
  /// Tracelet.setSyncBodyBuilder((context) async {
  ///   return {
  ///     'deviceId': myDeviceId,
  ///     'taskId': currentTaskId,
  ///     'points': context.locations,
  ///     'sentAt': DateTime.now().toIso8601String(),
  ///   };
  /// });
  /// ```
  ///
  /// Pass `null` to clear the custom builder and revert to the default
  /// JSON structure.
  ///
  /// For background (headless) body building, also register
  /// [registerHeadlessSyncBodyBuilder].
  static Future<void> setSyncBodyBuilder(
    Future<Map<String, Object?>> Function(SyncBodyContext)? builder,
  ) async {
    _syncBodyBuilder = builder;

    if (builder != null) {
      _ensureSyncBodyChannel();
    } else {
      _tearDownSyncBodyChannel();
    }

    // Notify native side whether a foreground builder is registered.
    // This prevents native timeouts and unintended aborts when auto-syncing
    // in the background without a custom builder.
    const channel = MethodChannel('com.tracelet/sync_body');
    try {
      await channel.invokeMethod<void>(
        'setHasCustomSyncBodyBuilder',
        builder != null,
      );
    } on MissingPluginException {
      // Ignore in tests.
    }
  }

  /// Sets up the MethodChannel handler for native → Dart callbacks.
  ///
  /// This channel (`com.tracelet/sync_body`) handles several reverse
  /// invocations from native code:
  /// - `buildSyncBody`: Invokes the custom [setSyncBodyBuilder] callback.
  /// - `requestFreshHeaders`: Invokes the [setHeadersCallback] callback.
  /// - `requestTokenRefresh`: Invokes the [setTokenRefreshCallback] callback.
  static void _ensureSyncBodyChannel() {
    if (_syncBodyChannelReady) return;
    _syncBodyChannelReady = true;

    const channel = MethodChannel('com.tracelet/sync_body');
    channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'buildSyncBody') {
        // No builder registered → return the sentinel so native falls through
        // to the default payload. `null` is reserved for the failure case below
        // so native can tell "no builder" apart from "builder failed" and abort
        // only on the latter (Issue #125).
        if (_syncBodyBuilder == null) return _noSyncBodyBuilderSentinel;
        try {
          // #214: native now sends a {locations, telematics} map; older native
          // builds sent a bare locations List. Accept both so a native/Dart
          // version skew never breaks the builder (it just yields empty telematics).
          final raw = call.arguments;
          final List<dynamic> rawLocations;
          final List<dynamic> rawTelematics;
          if (raw is Map) {
            rawLocations = (raw['locations'] as List<dynamic>?) ?? const [];
            rawTelematics = (raw['telematics'] as List<dynamic>?) ?? const [];
          } else {
            rawLocations = (raw as List<dynamic>?) ?? const []; // legacy shape
            rawTelematics = const [];
          }
          final locations = rawLocations
              .whereType<Map<Object?, Object?>>()
              .map(_deepCastMap)
              .toList();
          final telematics = rawTelematics
              .whereType<Map<Object?, Object?>>()
              .map(_deepCastMap)
              .toList();
          final body = await _syncBodyBuilder!(
            SyncBodyContext(locations: locations, telematics: telematics),
          );
          return jsonEncode(body);
        } catch (e) {
          // A registered builder threw: return null so native aborts the sync
          // instead of posting an error object or the default payload.
          return null;
        }
      }
      if (call.method == 'requestFreshHeaders') {
        final callback = _headersCallback;
        if (callback == null) return false;
        final headers = await callback();
        await _platform.setDynamicHeaders(headers);
        return true;
      }
      if (call.method == 'requestTokenRefresh') {
        final callback = _tokenRefreshCallback;
        if (callback == null) return false;
        final headers = await callback();
        await _platform.setDynamicHeaders(headers);
        return true;
      }
      return null;
    });
  }

  /// Tears down the MethodChannel handler when all callbacks are cleared.
  static void _tearDownSyncBodyChannel() {
    // Keep the channel alive. Unregistering the handler in Dart causes iOS
    // invokeMethod completion blocks to hang/timeout in some Flutter versions
    // rather than returning FlutterMethodNotImplemented immediately.
  }

  /// Send a custom sync body response back to native (headless use).
  ///
  /// Called from a headless sync body callback to return the transformed
  /// body to the native HTTP sync engine. The [body] map is JSON-encoded
  /// and sent via the `com.tracelet/methods` MethodChannel.
  static Future<void> setSyncBodyResponse(Map<String, Object?> body) async {
    const channel = MethodChannel('com.tracelet/methods');
    await channel.invokeMethod<void>('setSyncBodyResponse', jsonEncode(body));
  }

  /// Register a headless sync body builder for background custom payloads.
  ///
  /// The [callback] must be a top-level or static function. It receives a
  /// [HeadlessEvent] with `name == 'syncBodyBuild'` containing the locations
  /// batch, and must return the custom request body.
  ///
  /// ```dart
  /// @pragma('vm:entry-point')
  /// static Future<Map<String, Object?>> myHeadlessSyncBody(
  ///   HeadlessEvent event,
  /// ) async {
  ///   final locations = event.event['locations'] as List;
  ///   return {
  ///     'deviceId': getDeviceId(),
  ///     'points': locations,
  ///   };
  /// }
  /// ```
  static Future<bool> registerHeadlessSyncBodyBuilder(
    void Function(HeadlessEvent) callback,
  ) {
    if (kIsWeb) return Future<bool>.value(false);

    final registrationHandle = ui.PluginUtilities.getCallbackHandle(
      _headlessCallbackDispatcher,
    );
    if (registrationHandle == null) {
      throw StateError('Could not look up _headlessCallbackDispatcher handle.');
    }

    final dispatchHandle = ui.PluginUtilities.getCallbackHandle(callback);
    if (dispatchHandle == null) {
      throw ArgumentError(
        'registerHeadlessSyncBodyBuilder callback must be a top-level or '
        'static function.',
      );
    }

    return _platform.registerHeadlessSyncBodyBuilder(<int>[
      registrationHandle.toRawHandle(),
      dispatchHandle.toRawHandle(),
    ]);
  }

  /// Register a headless headers callback for background token recovery.
  ///
  /// When the app is terminated and native sync receives a 401 response,
  /// the native side spawns a headless Dart isolate, invokes this callback
  /// to obtain fresh authorization headers, and retries the request once.
  ///
  /// The [callback] must be a top-level or static function.
  ///
  /// ```dart
  /// @pragma('vm:entry-point')
  /// static void myHeadlessHeadersCallback(HeadlessEvent event) {
  ///   // Refresh token and update headers
  ///   final token = await secureStorage.read('refreshToken');
  ///   Tracelet.setDynamicHeaders({'Authorization': 'Bearer \$token'});
  /// }
  /// ```
  static Future<bool> registerHeadlessHeadersCallback(
    void Function(HeadlessEvent) callback,
  ) {
    if (kIsWeb) return Future<bool>.value(false);

    final registrationHandle = ui.PluginUtilities.getCallbackHandle(
      _headlessCallbackDispatcher,
    );
    if (registrationHandle == null) {
      throw StateError('Could not look up _headlessCallbackDispatcher handle.');
    }

    final dispatchHandle = ui.PluginUtilities.getCallbackHandle(callback);
    if (dispatchHandle == null) {
      throw ArgumentError(
        'registerHeadlessHeadersCallback callback must be a top-level or '
        'static function.',
      );
    }

    return _platform.registerHeadlessHeadersCallback(<int>[
      registrationHandle.toRawHandle(),
      dispatchHandle.toRawHandle(),
    ]);
  }

  // ---------------------------------------------------------------------------
  // Utility
  // ---------------------------------------------------------------------------

  /// Whether the device is currently in power-save (battery saver) mode.
  static Future<bool> get isPowerSaveMode => _platform.isPowerSaveMode();

  /// Whether the app has background ("Always") location permission.
  ///
  /// Returns `true` when the current [AuthorizationStatus] is
  /// [AuthorizationStatus.always] (status code `3`). Only "Always" permission
  /// allows tracking to continue when the app is terminated, rebooted, or
  /// otherwise in a killed state.
  ///
  /// Use this before calling [start], [startGeofences], or [startPeriodic]
  /// to verify that killed-state tracking will work. If this returns `false`,
  /// prompt the user to upgrade their permission via [requestPermission] or
  /// [openAppSettings].
  ///
  /// ```dart
  /// if (!await Tracelet.hasBackgroundPermission) {
  ///   await Tracelet.requestPermission();
  /// }
  /// ```
  static Future<bool> get hasBackgroundPermission async {
    final status = await getLocationAuthorization();
    return status == AuthorizationStatus.always;
  }

  /// Get the current permission status without triggering any dialog.
  ///
  /// **Deprecated**: prefer [getLocationAuthorization], which returns the
  /// strongly typed [AuthorizationStatus] enum instead of an int. This
  /// method will be removed in 2.0.0.
  ///
  /// Returns the [AuthorizationStatus] index:
  /// Get the current location permission status without triggering a dialog.
  ///
  /// Returns a strongly typed [AuthorizationStatus].
  ///
  /// Use this to decide what UI to show before calling
  /// [requestLocationAuthorization].
  static Future<AuthorizationStatus> getLocationAuthorization() {
    return _platform.getLocationAuthorization();
  }

  /// Request location permission asynchronously.
  ///
  /// Returns a strongly typed [AuthorizationStatus].
  ///
  /// Escalation logic:
  /// - [AuthorizationStatus.notDetermined] → requests foreground (When In
  ///   Use) permission
  /// - [AuthorizationStatus.whenInUse] → requests background (Always)
  ///   permission
  /// - [AuthorizationStatus.denied] / [AuthorizationStatus.deniedForever] /
  ///   [AuthorizationStatus.always] → returns immediately
  static Future<AuthorizationStatus> requestLocationAuthorization() {
    return _platform.requestLocationAuthorization();
  }

  /// Get the notification permission status as a typed [NotificationAuthorizationStatus].
  ///
  /// On Android < 13 and on iOS always returns [NotificationAuthorizationStatus.authorized].
  static Future<NotificationAuthorizationStatus>
  getNotificationAuthorization() {
    return _platform.getNotificationAuthorization();
  }

  /// Request notification permission asynchronously (Android 13+ / API 33+).
  ///
  /// Returns a strongly typed [NotificationAuthorizationStatus].
  static Future<NotificationAuthorizationStatus>
  requestNotificationAuthorization() {
    return _platform.requestNotificationAuthorization();
  }

  /// Check whether the app can schedule exact alarms.
  ///
  /// On Android 12+ (API 31+), returns whether SCHEDULE_EXACT_ALARM is
  /// granted. On Android 12 it is auto-granted; on Android 13+ the user
  /// must enable it in Settings.
  ///
  /// On Android < 12, iOS, and web, always returns `true`.
  ///
  /// **When to use:** Before calling [startPeriodic] with short intervals
  /// (< 15 min). If `false`, periodic timing will be approximate.
  static Future<bool> canScheduleExactAlarms() {
    return _platform.canScheduleExactAlarms();
  }

  /// Open the device Settings screen for exact alarm permission.
  ///
  /// On Android 12+, opens the "Alarms & reminders" settings page for
  /// this app. The user must manually toggle the switch.
  ///
  /// Returns `true` if the settings screen was opened, `false` otherwise.
  /// On iOS and web, this is a no-op that returns `false`.
  static Future<bool> openExactAlarmSettings() {
    return _platform.openExactAlarmSettings();
  }

  /// Get the motion permission status as a typed [MotionAuthorizationStatus].
  ///
  /// On Android < 10 (API < 29), always returns [MotionAuthorizationStatus.authorized].
  static Future<MotionAuthorizationStatus> getMotionAuthorization() {
    return _platform.getMotionAuthorization();
  }

  /// **Important:** Without this permission **and** without the
  /// accelerometer-only fallback (`Config.motion.disableMotionActivityUpdates`),
  /// the plugin cannot detect motion transitions. The device will not fire
  /// `onMotionChange` events unless [changePace] is called manually.
  ///
  /// When `Config.motion.disableMotionActivityUpdates` is `true`, returns
  /// [MotionAuthorizationStatus.authorized] immediately without showing any dialog.
  static Future<MotionAuthorizationStatus> requestMotionAuthorization() {
    return _platform.requestMotionAuthorization();
  }

  /// Request temporary full accuracy (iOS 14+).
  ///
  /// **Deprecated**: prefer [requestTemporaryFullAccuracyAuthorization],
  /// which returns the strongly typed [AuthorizationStatus] enum instead of
  /// an int. This method will be removed in 2.0.0.
  ///
  /// [purpose] must match a key in the app's `Info.plist`
  /// `NSLocationTemporaryUsageDescriptionDictionary`.
  @Deprecated(
    'Use requestTemporaryFullAccuracyAuthorization() — will be removed in 2.0.0',
  )
  static Future<int> requestTemporaryFullAccuracy(String purpose) {
    return _platform.requestTemporaryFullAccuracy(purpose);
  }

  /// Request temporary full accuracy (iOS 14+) returning a typed
  /// [AuthorizationStatus]. Replaces [requestTemporaryFullAccuracy].
  ///
  /// [purpose] must match a key in the app's `Info.plist`
  /// `NSLocationTemporaryUsageDescriptionDictionary`.
  static Future<FullAccuracyStatus> requestTemporaryFullAccuracyAuthorization(
    String purpose,
  ) {
    return _platform.requestTemporaryFullAccuracyAuthorization(purpose);
  }

  /// Get the current location provider state.
  static Future<ProviderChangeEvent> getProviderState() async {
    final result = await _platform.getProviderState();
    return ProviderChangeEvent.fromMap(result);
  }

  /// Get information about available device sensors.
  static Future<Sensors> getSensors() async {
    final result = await _platform.getSensors();
    return Sensors.fromMap(result);
  }

  /// Get information about the device.
  static Future<DeviceInfo> getDeviceInfo() async {
    final result = await _platform.getDeviceInfo();
    return DeviceInfo.fromMap(result);
  }

  /// Play a debug sound effect.
  static Future<bool> playSound(String name) {
    return _platform.playSound(name);
  }

  /// Whether the app is currently ignoring battery optimizations (Android only).
  static Future<bool> isIgnoringBatteryOptimizations() {
    return _platform.isIgnoringBatteryOptimizations();
  }

  /// Request a system settings page (e.g. ignore battery optimization).
  static Future<bool> requestSettings(String action) {
    return _platform.requestSettings(action);
  }

  /// Show a system settings page (e.g. location settings).
  static Future<bool> showSettings(String action) {
    return _platform.showSettings(action);
  }

  /// Open the app's system settings page.
  ///
  /// Useful when permission is permanently denied ([AuthorizationStatus.deniedForever])
  /// and the user must enable it manually.
  static Future<bool> openAppSettings() {
    return _platform.showSettings('app');
  }

  /// Open the device's location settings page.
  static Future<bool> openLocationSettings() {
    return _platform.showSettings('location');
  }

  /// Open battery optimization settings (Android only).
  ///
  /// Prompts the user to exempt the app from battery restrictions.
  static Future<bool> openBatterySettings() {
    return _platform.requestSettings('ignoreOptimizations');
  }

  // ---------------------------------------------------------------------------
  // OEM Compatibility
  // ---------------------------------------------------------------------------

  /// Get OEM settings health information.
  ///
  /// Returns a map describing the device's OEM background-killing behavior,
  /// battery optimization status, and available OEM-specific settings screens.
  ///
  /// Use this to build a "Device Health" UI that guides users through
  /// OEM-specific power management settings. Aggressive manufacturers
  /// (Huawei, Xiaomi, OnePlus, Samsung, Oppo, Vivo) often kill background
  /// apps — this API helps users fix those settings.
  ///
  /// **Returned map keys:**
  /// - `manufacturer` (`String`): Device manufacturer.
  /// - `model` (`String`): Device model.
  /// - `isAggressiveOem` (`bool`): Whether this OEM is known to aggressively
  ///   kill background services.
  /// - `aggressionRating` (`int`): 0–5 severity rating per dontkillmyapp.com.
  /// - `isIgnoringBatteryOptimizations` (`bool`): Whether the app is exempt.
  /// - `autostartAvailable` (`bool`): Whether Xiaomi/MIUI autostart
  ///   settings are available.
  /// - `oemSettingsScreens` (`List<Map<String, String>>`): Available
  ///   OEM-specific settings screens, each with `label` and `description`.
  ///
  /// On iOS and Web, returns a minimal map with `isAggressiveOem: false`.
  ///
  /// ```dart
  /// final health = await Tracelet.getSettingsHealth();
  /// if (health['isAggressiveOem'] == true) {
  ///   final screens = health['oemSettingsScreens'] as List;
  ///   for (final screen in screens) {
  ///     print('${screen['label']}: ${screen['description']}');
  ///   }
  /// }
  /// ```
  static Future<Map<String, Object?>> getSettingsHealth() {
    return _platform.getSettingsHealth();
  }

  /// Get authoritative Android foreground-service health (#255).
  ///
  /// [Tracelet.getState] reports the *desired* tracking state (`enabled`), but
  /// on Android 12+ a foreground-service start can be deferred or rejected by
  /// the OS even while `enabled == true` — so `enabled` alone does not prove
  /// background tracking is actually operational. This exposes the *actual*
  /// native foreground-service state so apps can build accurate tracking-health
  /// indicators, diagnostics, and recovery behavior.
  ///
  /// **Returned map keys:**
  /// - `desiredEnabled` (`bool`): the persisted desired tracking state.
  /// - `foregroundServiceEnabled` (`bool`): whether the active config runs a
  ///   foreground service.
  /// - `serviceRunning` (`bool`): whether the native location service is alive.
  /// - `serviceForeground` (`bool`): whether it is currently promoted to the
  ///   foreground.
  /// - `foregroundNotificationId` (`int?`): the notification id while promoted.
  /// - `lastForegroundPromotionResult` (`String?`): `success`, `deferred`,
  ///   `failed`, or `suppressed` (null before any attempt). `suppressed` means
  ///   the notification is hidden on purpose while the app is on screen
  ///   (`showNotificationOnPauseOnly`) — tracking is running and the service is
  ///   alive, unlike `deferred` and `failed`.
  /// - `lastForegroundPromotionFailureClass` (`String?`): exception class of
  ///   the last failed/deferred promotion.
  /// - `lastForegroundPromotionFailureMessage` (`String?`): its message.
  /// - `lastForegroundTransitionAt` (`int?`): epoch-ms of the last *transition*
  ///   — a promotion that changed the state, not a re-post of a notification
  ///   the service already held (#378).
  /// - `platform` (`String`): `android` or `ios`.
  ///
  /// On iOS the promotion fields are null/`false` — iOS has no foreground
  /// service that can fail after the fact. On Web a minimal disabled map is
  /// returned.
  ///
  /// ```dart
  /// final health = await Tracelet.getForegroundServiceHealth();
  /// if (health['desiredEnabled'] == true &&
  ///     health['serviceForeground'] != true) {
  ///   // Tracking is requested but the foreground service is not running —
  ///   // e.g. promotion was deferred or failed. Surface a warning / recover.
  ///   final reason = health['lastForegroundPromotionResult'];
  ///   debugPrint('Foreground service not active: $reason');
  /// }
  /// ```
  static Future<Map<String, Object?>> getForegroundServiceHealth() {
    return _platform.getForegroundServiceHealth();
  }

  /// The location-filter thresholds **actually in force**, or `null` before a
  /// tracking session has built a location processor (#303).
  ///
  /// This reads back from the native processor, not from [activeConfig].
  /// [activeConfig] is a Dart-side mirror of the last [Config] you passed in,
  /// so it cannot tell you whether a value reached the filter that uses it —
  /// and it cannot show you a transport-mode auto-tune, which changes these
  /// thresholds without any config call at all.
  ///
  /// Two things it surfaces that nothing else can:
  ///
  /// - **Auto-tune state.** While `ClassifierConfig.autoTuneFromTransportMode`
  ///   has a mode committed, these are the *tuned* values, not the ones you
  ///   set. `ModeChangeEvent.appliedTuning` reports the swap at the moment it
  ///   happens; this reports the current state at any time.
  /// - **Whether your configuration took effect.** Prior to #303 most of the
  ///   filter config never reached the processor at runtime, and there was no
  ///   way to observe that from Dart.
  ///
  /// On Web this is always `null` — the browser Geolocation API exposes no
  /// equivalent filter state.
  ///
  /// ```dart
  /// await Tracelet.setConfig(const Config(
  ///   geo: GeoConfig(filter: LocationFilter(trackingAccuracyThreshold: 30)),
  /// ));
  /// final tuning = await Tracelet.getCurrentLocationTuning();
  /// // 30 unless a committed transport mode is currently overriding it.
  /// print(tuning?.trackingAccuracyThreshold);
  /// ```
  static Future<LocationTuning?> getCurrentLocationTuning() async {
    final t = await _platform.getCurrentLocationTuning();
    return t == null ? null : LocationTuning.fromTl(t);
  }

  /// Open an OEM-specific settings screen by [label].
  ///
  /// The [label] must match one of the labels from the `oemSettingsScreens`
  /// list returned by [getSettingsHealth].
  ///
  /// Returns `true` if the settings screen was opened successfully,
  /// `false` if the label was not found or the intent failed to resolve.
  ///
  /// On iOS and Web, always returns `false` (no OEM power management).
  ///
  /// ```dart
  /// final opened = await Tracelet.openOemSettings('Xiaomi Autostart');
  /// if (!opened) {
  ///   print('Settings screen not available on this device.');
  /// }
  /// ```
  static Future<bool> openOemSettings(String label) {
    return _platform.openOemSettings(label);
  }

  /// Launch the OEM-specific power manager / battery optimization screen.
  ///
  /// Iterates through known manufacturer-specific settings intents and
  /// launches the first available one. This is the primary way to direct
  /// users to manually whitelist the app on aggressive OEMs (Vivo, Oppo,
  /// Xiaomi, Huawei, etc.).
  ///
  /// Returns `true` if a screen was launched successfully, `false` if no
  /// known screen was found for this device or the intent failed.
  ///
  /// On iOS and Web, always returns `false`.
  ///
  /// ```dart
  /// final launched = await Tracelet.showPowerManager();
  /// if (launched) {
  ///   print('User is reviewing power settings.');
  /// }
  /// ```
  static Future<bool> showPowerManager() {
    return _platform.showPowerManager();
  }

  // ---------------------------------------------------------------------------
  // Background Tasks
  // ---------------------------------------------------------------------------

  /// Start a long-running background task.
  ///
  /// Call [stopBackgroundTask] when done to prevent the OS from killing the app.
  /// Returns a task ID.
  static Future<int> startBackgroundTask() {
    return _platform.startBackgroundTask();
  }

  /// Stop a background task started by [startBackgroundTask].
  static Future<int> stopBackgroundTask(int taskId) {
    return _platform.stopBackgroundTask(taskId);
  }

  // ---------------------------------------------------------------------------
  // Logging
  // ---------------------------------------------------------------------------

  /// Get the plugin log as a string.
  ///
  /// Optionally pass a [query] to filter by time range and limit.
  static Future<String> getLog([SQLQuery? query]) {
    return _platform.getLog(query?.toMap());
  }

  /// Destroy all log entries.
  static Future<bool> destroyLog() {
    return _platform.destroyLog();
  }

  /// Email the log file to the given [email] address.
  static Future<bool> emailLog(String email) {
    return _platform.emailLog(email);
  }

  /// Write a custom log entry.
  ///
  /// [level] is one of `'error'`, `'warn'`, `'info'`, `'debug'`, `'verbose'`.
  static Future<bool> log(String level, String message) {
    return _platform.log(level, message);
  }

  // ---------------------------------------------------------------------------
  // Scheduling
  // ---------------------------------------------------------------------------

  /// Start the scheduler (uses the `schedule` array in [AppConfig]).
  static Future<State> startSchedule() async {
    final result = await _platform.startSchedule();
    return _stateFromMap(result);
  }

  /// Stop the scheduler.
  static Future<State> stopSchedule() async {
    final result = await _platform.stopSchedule();
    return _stateFromMap(result);
  }

  // ---------------------------------------------------------------------------
  // Headless
  // ---------------------------------------------------------------------------

  /// Register a headless task callback to be invoked in a background isolate.
  ///
  /// The [callback] must be a top-level or static function.
  /// Internally, the callback is converted to a handle via the
  /// `dart:ui` `PluginUtilities.getCallbackHandle()` mechanism.
  ///
  /// Two callback handles are sent to the native side:
  /// 1. **Registration callback** — the internal [_headlessCallbackDispatcher]
  ///    entry point that the native FlutterEngine executes to bootstrap the
  ///    headless Dart isolate.
  /// 2. **Dispatch callback** — the user-supplied [callback] that receives
  ///    each [HeadlessEvent].
  static Future<bool> registerHeadlessTask(
    void Function(HeadlessEvent) callback,
  ) {
    // Headless isolates are not supported on web — bail out early.
    if (kIsWeb) return Future<bool>.value(false);

    // The internal dispatcher that the native side executes as the Dart
    // entry point for the headless isolate.
    final registrationHandle = ui.PluginUtilities.getCallbackHandle(
      _headlessCallbackDispatcher,
    );
    if (registrationHandle == null) {
      throw StateError('Could not look up _headlessCallbackDispatcher handle.');
    }

    // The user's callback that will process each HeadlessEvent.
    final dispatchHandle = ui.PluginUtilities.getCallbackHandle(callback);
    if (dispatchHandle == null) {
      throw ArgumentError(
        'registerHeadlessTask callback must be a top-level or static function.',
      );
    }

    _headlessRegistered = true;
    return _platform.registerHeadlessTask(<int>[
      registrationHandle.toRawHandle(),
      dispatchHandle.toRawHandle(),
    ]);
  }

  // ---------------------------------------------------------------------------
  // Audit Trail (Enterprise)
  // ---------------------------------------------------------------------------

  /// **Enterprise** — Verify the integrity of the tamper-proof audit trail.
  ///
  /// Walks all location records in chain order, re-computes each SHA-256
  /// hash, and compares it to the stored hash. Returns an
  /// [AuditVerification] describing the result.
  ///
  /// If any record has been inserted, deleted, or modified,
  /// [AuditVerification.isValid] will be `false` and
  /// [AuditVerification.brokenAtIndex] / [AuditVerification.brokenAtUuid]
  /// will indicate where the chain was broken.
  ///
  /// ```dart
  /// final result = await Tracelet.verifyAuditTrail();
  /// if (result.isValid) {
  ///   print('Chain intact: ${result.verifiedRecords} records');
  /// } else {
  ///   print('Tampered at index ${result.brokenAtIndex}');
  /// }
  /// ```
  ///
  /// Requires [AuditConfig.enabled] to be `true` in the configuration.
  static Future<AuditVerification> verifyAuditTrail() async {
    final map = await _platform.verifyAuditTrail();
    return AuditVerification.fromMap(map);
  }

  /// **Enterprise** — Get the audit proof for a specific location record.
  ///
  /// Returns the [AuditProof] containing the SHA-256 hash, previous hash,
  /// and chain index for the location identified by [uuid]. Returns `null`
  /// if audit trail is disabled or the record does not exist.
  ///
  /// ```dart
  /// final proof = await Tracelet.getAuditProof(location.uuid);
  /// if (proof != null) {
  ///   print('Hash: ${proof.hash}');
  ///   print('Chain index: ${proof.chainIndex}');
  /// }
  /// ```
  static Future<AuditProof?> getAuditProof(String uuid) async {
    final map = await _platform.getAuditProof(uuid);
    if (map == null) return null;
    return AuditProof.fromMap(map);
  }

  // ---------------------------------------------------------------------------
  // Privacy Zones (Enterprise)
  // ---------------------------------------------------------------------------

  /// **Enterprise** — Add a single [PrivacyZone].
  ///
  /// Privacy zones define geographic areas where location tracking behaviour
  /// changes according to the zone's [PrivacyZoneAction]:
  ///
  /// - [PrivacyZoneAction.exclude] — locations inside the zone are dropped
  ///   entirely (not persisted, not dispatched).
  /// - [PrivacyZoneAction.degrade] — coordinates are degraded to
  ///   [PrivacyZone.degradedAccuracyMeters] precision before persisting
  ///   and dispatching.
  /// - [PrivacyZoneAction.eventOnly] — locations are dispatched to Dart
  ///   listeners but NOT persisted to the database.
  ///
  /// Requires [PrivacyZoneConfig.enabled] to be `true` in the configuration.
  ///
  /// ```dart
  /// await Tracelet.addPrivacyZone(PrivacyZone(
  ///   identifier: 'home',
  ///   latitude: 37.7749,
  ///   longitude: -122.4194,
  ///   radius: 200,
  ///   action: PrivacyZoneAction.exclude,
  /// ));
  /// ```
  static Future<bool> addPrivacyZone(PrivacyZone zone) {
    return _platform.addPrivacyZone(zone.toMap());
  }

  /// **Enterprise** — Add multiple [PrivacyZone]s at once.
  static Future<bool> addPrivacyZones(List<PrivacyZone> zones) {
    return _platform.addPrivacyZones(
      zones.map((z) => z.toMap()).toList(growable: false),
    );
  }

  /// **Enterprise** — Remove a privacy zone by its `identifier`.
  static Future<bool> removePrivacyZone(String identifier) {
    return _platform.removePrivacyZone(identifier);
  }

  /// **Enterprise** — Remove all privacy zones.
  static Future<bool> removePrivacyZones() {
    return _platform.removePrivacyZones();
  }

  /// **Enterprise** — Get all registered privacy zones.
  ///
  /// ```dart
  /// final zones = await Tracelet.getPrivacyZones();
  /// for (final zone in zones) {
  ///   print('${zone.identifier}: ${zone.action}');
  /// }
  /// ```
  static Future<List<PrivacyZone>> getPrivacyZones() async {
    final result = await _platform.getPrivacyZones();
    return result.map(PrivacyZone.fromMap).toList();
  }

  // ---------------------------------------------------------------------------
  // Encrypted Database (Enterprise)
  // ---------------------------------------------------------------------------

  /// **Enterprise** — Check if the database is currently encrypted.
  ///
  /// Returns `true` if the SQLite database is using AES-256 encryption
  /// via SQLCipher.
  ///
  /// ```dart
  /// final encrypted = await Tracelet.isDatabaseEncrypted();
  /// print('Database encrypted: $encrypted');
  /// ```
  static Future<bool> isDatabaseEncrypted() {
    return _platform.isDatabaseEncrypted();
  }

  /// **Enterprise** — Encrypt an existing unencrypted database.
  ///
  /// Performs a one-time migration from unencrypted to AES-256 encrypted
  /// SQLite. All existing data is preserved. Returns `true` on success.
  ///
  /// If the database is already encrypted, returns `true` immediately.
  ///
  /// ```dart
  /// final success = await Tracelet.encryptDatabase();
  /// print('Migration result: $success');
  /// ```
  static Future<bool> encryptDatabase() {
    return _platform.encryptDatabase();
  }

  // ---------------------------------------------------------------------------
  // Device Attestation (Enterprise)
  // ---------------------------------------------------------------------------

  /// **Enterprise** — Request a fresh device attestation token.
  ///
  /// Returns an [AttestationToken] from the platform's hardware-backed
  /// security module, proving the device is genuine and untampered.
  ///
  /// - **Android**: Google Play Integrity API token.
  /// - **iOS**: App Attest assertion.
  /// - **Web**: Returns `null` (not supported).
  ///
  /// ```dart
  /// final token = await Tracelet.getAttestationToken();
  /// if (token != null) {
  ///   print('Provider: ${token.provider}');
  /// }
  /// ```
  static Future<AttestationToken?> getAttestationToken() async {
    final map = await _platform.getAttestationToken();
    if (map == null) return null;
    return AttestationToken.fromMap(map);
  }

  // ---------------------------------------------------------------------------
  // Dead Reckoning (Enterprise)
  // ---------------------------------------------------------------------------

  /// **Enterprise** — Get the current dead reckoning state.
  ///
  /// Returns a map with the DR state when active (`active`, `elapsed`,
  /// `estimatedAccuracy`), or `null` if dead reckoning is disabled or
  /// GPS signal is available.
  ///
  /// ```dart
  /// final state = await Tracelet.getDeadReckoningState();
  /// if (state != null && state['active'] == true) {
  ///   print('DR active for ${state['elapsed']}s');
  /// }
  /// ```
  static Future<Map<String, Object?>?> getDeadReckoningState() {
    return _platform.getDeadReckoningState();
  }

  // ---------------------------------------------------------------------------
  // Carbon Estimator (Enterprise)
  // ---------------------------------------------------------------------------

  /// **Enterprise** — Get cumulative CO₂ emissions report.
  ///
  /// Calculates emissions based on detected transport mode and distance.
  /// Uses EU EEA 2024 average emission factors.
  ///
  /// ```dart
  /// final report = await Tracelet.getCarbonReport();
  /// print('Total: ${report['totalCarbonGrams']}g CO₂');
  /// ```
  static Future<Map<String, Object?>> getCarbonReport([
    Map<String, Object?>? query,
  ]) async {
    final result = await _platform.getCarbonReport(query);
    return result.cast<String, Object?>();
  }

  // ---------------------------------------------------------------------------
  // Compliance Report (Enterprise)
  // ---------------------------------------------------------------------------

  /// **Enterprise** — Generate a GDPR Article 30 / CCPA compliance report.
  ///
  /// Aggregates all location data processing information into a structured
  /// [ComplianceReport]: data inventory, retention policy, privacy measures,
  /// data destinations, audit trail status, and consent status.
  ///
  /// The report can be exported as JSON ([ComplianceReport.toJson]) for
  /// automated compliance tooling, or as Markdown ([ComplianceReport.toMarkdown])
  /// for human review.
  ///
  /// ```dart
  /// final report = await Tracelet.generateComplianceReport();
  /// print(report.toMarkdown());
  /// ```
  static Future<ComplianceReport> generateComplianceReport() async {
    // Gather all data in parallel for efficiency.
    final results = await Future.wait([
      _platform.getState(), // 0
      _platform.getCount(), // 1
      _platform.getLocationAuthorization(), // 2
      _platform.getMotionAuthorization(), // 3
      _platform.getPrivacyZones(), // 4
      _platform.getLocations(<String, Object?>{
        'limit': 1,
        'order': 0,
      }), // 5 oldest
      _platform.getLocations(<String, Object?>{
        'limit': 1,
        'order': 1,
      }), // 6 newest
      _platform.isDatabaseEncrypted(), // 7
    ]);

    final stateMap = Map<String, Object?>.from(results[0] as Map);
    final count = results[1] as int;
    final locationPerm = (results[2] as AuthorizationStatus).index;
    final motionPerm = (results[3] as MotionAuthorizationStatus).index;
    final zones = (results[4] as List)
        .map((z) => Map<String, Object?>.from(z as Map))
        .toList();
    final oldestList = (results[5] as List)
        .map((l) => Map<String, Object?>.from(l as Map))
        .toList();
    final newestList = (results[6] as List)
        .map((l) => Map<String, Object?>.from(l as Map))
        .toList();
    final dbEncrypted = results[7] as bool;

    final state = _stateFromMap(stateMap);

    // Extract timestamps from oldest/newest records.
    // Android sends timestamps as int (millis), iOS sends as String (ISO8601).
    final oldestRaw = oldestList.isNotEmpty
        ? oldestList.first['timestamp']
        : null;
    final newestRaw = newestList.isNotEmpty
        ? newestList.first['timestamp']
        : null;
    final oldestTs = oldestRaw is String
        ? oldestRaw
        : oldestRaw is int
        ? DateTime.fromMillisecondsSinceEpoch(oldestRaw).toIso8601String()
        : null;
    final newestTs = newestRaw is String
        ? newestRaw
        : newestRaw is int
        ? DateTime.fromMillisecondsSinceEpoch(newestRaw).toIso8601String()
        : null;

    return ComplianceReport(
      generatedAt: DateTime.now(),
      totalLocationsStored: count,
      totalLocationsSynced: 0, // Not tracked separately yet
      maxDaysToPersist: activeConfig.persistence.maxDaysToPersist,
      maxRecordsToPersist: activeConfig.persistence.maxRecordsToPersist,
      oldestRecord: oldestTs,
      newestRecord: newestTs,
      databaseEncrypted: dbEncrypted,
      activePrivacyZones: zones.length,
      privacyZoneIdentifiers: zones
          .map((z) => z['identifier'] as String? ?? '')
          .toList(),
      httpSyncUrl: activeConfig.http.url,
      autoSyncEnabled: activeConfig.http.autoSync,
      auditTrailEnabled: activeConfig.audit.enabled,
      locationPermissionStatus: locationPerm,
      motionPermissionStatus: motionPerm,
      sparseUpdatesEnabled: activeConfig.geo.enableSparseUpdates,
      kalmanFilterEnabled: activeConfig.geo.filter.useKalmanFilter,
      deltaCompressionEnabled: activeConfig.http.enableDeltaCompression,
      trackingEnabled: state.enabled,
      trackingMode: state.trackingMode.name,
    );
  }

  // ---------------------------------------------------------------------------
  // Event Subscriptions
  // ---------------------------------------------------------------------------

  /// A broadcast stream of processed location updates.
  ///
  /// Locations are filtered natively by the Rust LocationProcessor.
  /// and smoothed by [KalmanLocationFilter] (if enabled). The stream is shared
  /// across all listeners — stateful transformations are applied once per event.
  ///
  /// ```dart
  /// final sub = Tracelet.locationStream.listen((location) {
  ///   print('${location.coords.latitude}, ${location.coords.longitude}');
  /// });
  /// ```
  ///
  /// For a callback-based alternative, use [onLocation].
  static Stream<Location> get locationStream => _getProcessedLocationStream();

  /// A broadcast stream of motion change events.
  ///
  /// Fires when the device transitions between stationary and moving states.
  static Stream<Location> get motionChangeStream {
    return _motionChangeStream ??= _platform.motionChangeEvents
        .map(Location.fromTl)
        .asBroadcastStream();
  }

  /// A broadcast stream of activity change events.
  ///
  /// Fires when the detected device activity changes (still, walking, etc.).
  static Stream<ActivityChangeEvent> get activityChangeStream {
    return _activityChangeStream ??= _platform.activityChangeEvents.map(
      (e) => ActivityChangeEvent.fromMap({
        'activity': e.activity,
        'confidence': e.confidence,
      }),
    );
  }

  /// A broadcast stream of provider change events.
  ///
  /// Fires when GPS/network/authorization state changes.
  static Stream<ProviderChangeEvent> get providerChangeStream {
    return _providerChangeStream ??= _platform.providerChangeEvents.map(
      (e) => ProviderChangeEvent.fromMap({
        'enabled': e.enabled,
        'gps': e.gps,
        'network': e.network,
        'status': e.status,
        'accuracyAuthorization': e.accuracyAuthorization,
      }),
    );
  }

  /// A broadcast stream of geofence transition events.
  ///
  /// Fires on enter, exit, or dwell transitions.
  static Stream<GeofenceEvent> get geofenceStream {
    return _geofenceStream ??= _platform.geofenceEvents.map(
      (e) => GeofenceEvent.fromMap({
        'identifier': e.identifier,
        'action': e.action.name,
        'location': Location.fromTl(e.location).toMap(),
        'extras': e.extras,
      }),
    );
  }

  /// A broadcast stream of geofences change events.
  ///
  /// Fires when the set of actively monitored geofences changes.
  static Stream<GeofencesChangeEvent> get geofencesChangeStream {
    return _geofencesChangeStream ??= _platform.geofencesChangeEvents.map(
      (e) => GeofencesChangeEvent.fromMap({
        'on': e.on
            ?.whereType<TlGeofence>()
            .map(
              (g) => <String, Object?>{
                'identifier': g.identifier,
                'latitude': g.latitude,
                'longitude': g.longitude,
                'radius': g.radius,
              },
            )
            .toList(),
        'off': e.off
            ?.whereType<TlGeofence>()
            .map(
              (g) => <String, Object?>{
                'identifier': g.identifier,
                'latitude': g.latitude,
                'longitude': g.longitude,
                'radius': g.radius,
              },
            )
            .toList(),
      }),
    );
  }

  /// A broadcast stream of heartbeat events.
  ///
  /// Fires at the interval configured in [AppConfig.heartbeatInterval].
  static Stream<HeartbeatEvent> get heartbeatStream {
    return _heartbeatStream ??= _platform.heartbeatEvents.map(
      (e) => HeartbeatEvent(location: Location.fromTl(e.location)),
    );
  }

  /// A broadcast stream of HTTP sync events.
  ///
  /// Fires after each HTTP request completes (success or failure).
  static Stream<HttpEvent> get httpStream {
    return _httpStream ??= _platform.httpEvents.map(
      (e) => HttpEvent(
        success: e.isSuccess,
        status: e.status,
        responseText: e.responseText,
      ),
    );
  }

  /// A broadcast stream of driving-behavior (telematics) events.
  ///
  /// Fires for `harsh_braking`, `harsh_acceleration`, `harsh_cornering`, and
  /// `speeding` when `TelematicsConfig.enableDrivingEvents` is set.
  static Stream<DrivingEvent> get drivingEventStream {
    return _drivingEventStream ??= _platform.drivingEvents.map(
      DrivingEvent.fromTl,
    );
  }

  /// A broadcast stream of crash/fall impact events.
  ///
  /// Fires `potential_crash`/`crash` (and `potential_fall`/`fall` when enabled)
  /// when `ImpactConfig.enableCrashDetection` is set.
  static Stream<ImpactEvent> get impactStream {
    return _impactStream ??= _platform.impactEvents.map(ImpactEvent.fromTl);
  }

  /// A broadcast stream of fused transport-mode changes.
  ///
  /// Fires when `ClassifierConfig.enableFusedClassifier` is set.
  static Stream<ModeChangeEvent> get modeChangeStream {
    return _modeChangeStream ??= _platform.modeChangeEvents.map(
      ModeChangeEvent.fromTl,
    );
  }

  /// A broadcast stream of opt-in ML crash-model lifecycle status updates.
  ///
  /// Emits `unlocking` → `downloading` → `decrypting` → `ready` as the model is
  /// prepared (or `failed`/`disabled`). Use it to show the user that the crash
  /// model is downloading before crash detection becomes active. Only fires
  /// when `ImpactConfig.useMlModel` (crash model) is configured.
  static Stream<CrashModelStatusEvent> get crashModelStatusStream {
    return _crashModelStatusStream ??= _platform.crashModelStatusEvents.map(
      CrashModelStatusEvent.fromTl,
    );
  }

  /// A broadcast stream of schedule events.
  ///
  /// Fires when the scheduler starts or stops a tracking period.
  static Stream<State> get scheduleStream {
    return _scheduleStream ??= _platform.scheduleEvents.map(
      (s) => State.fromMap({
        'enabled': s.enabled,
        'isMoving': s.isMoving,
        'trackingMode': s.trackingMode,
        'schedulerEnabled': s.schedulerEnabled,
        'odometer': s.odometer,
        'lastLocationTimestamp': s.lastLocationTimestamp,
      }),
    );
  }

  /// A broadcast stream of power-save mode changes.
  ///
  /// Fires when the device enters or exits battery saver mode.
  static Stream<bool> get powerSaveChangeStream =>
      _platform.powerSaveChangeEvents;

  /// A broadcast stream of connectivity change events.
  ///
  /// Fires when the device goes online or offline.
  static Stream<ConnectivityChangeEvent> get connectivityChangeStream {
    return _connectivityChangeStream ??= _platform.connectivityChangeEvents.map(
      (e) => ConnectivityChangeEvent(connected: e.connected),
    );
  }

  /// A broadcast stream of enabled-change events.
  ///
  /// Fires when tracking is enabled or disabled.
  static Stream<bool> get enabledChangeStream => _platform.enabledChangeEvents;

  /// A broadcast stream of notification action events (Android only).
  ///
  /// Fires when the user taps a notification action button.
  static Stream<String> get notificationActionStream =>
      _platform.notificationActionEvents;

  /// Subscribe to location events.
  ///
  /// Fires for every recorded location.
  static StreamSubscription<Location> onLocation(
    void Function(Location) callback,
  ) {
    return _tracked(_getProcessedLocationStream().listen(callback));
  }

  /// Returns a shared broadcast stream of locations.
  ///
  /// The stream is created lazily on first access and cached so that
  /// all subscribers share the same broadcast stream.
  static Stream<Location> _getProcessedLocationStream() {
    return _processedLocationStream ??= _platform.locationEvents
        .map(Location.fromTl)
        .asBroadcastStream();
  }

  /// Subscribe to motion change events.
  ///
  /// Fires when the device transitions between stationary and moving states.
  static StreamSubscription<Location> onMotionChange(
    void Function(Location) callback,
  ) {
    return _tracked(
      _platform.motionChangeEvents.map(Location.fromTl).listen(callback),
    );
  }

  /// Subscribe to speed-based motion mode change events.
  ///
  /// Fires when the tracking engine transitions between moving, slowing,
  /// and stationary states based on GPS speed rather than activity sensors.
  /// Only active when [MotionDetectionMode.speed] is configured.
  static StreamSubscription<SpeedMotionEvent> onSpeedMotionChange(
    void Function(SpeedMotionEvent) callback,
  ) {
    return _tracked(
      _platform.motionModeChangeEvents
          .map(SpeedMotionEvent.fromTl)
          .listen(callback),
    );
  }

  /// Subscribe to activity change events.
  ///
  /// Fires when the detected device activity changes (still, walking, etc.).
  static StreamSubscription<ActivityChangeEvent> onActivityChange(
    void Function(ActivityChangeEvent) callback,
  ) {
    return _tracked(
      _platform.activityChangeEvents
          .map(
            (e) => ActivityChangeEvent.fromMap({
              'activity': e.activity,
              'confidence': e.confidence,
            }),
          )
          .listen(callback),
    );
  }

  /// Subscribe to provider change events.
  ///
  /// Fires when GPS/network/authorization state changes.
  static StreamSubscription<ProviderChangeEvent> onProviderChange(
    void Function(ProviderChangeEvent) callback,
  ) {
    return _tracked(
      _platform.providerChangeEvents
          .map(
            (e) => ProviderChangeEvent.fromMap({
              'enabled': e.enabled,
              'gps': e.gps,
              'network': e.network,
              'status': e.status,
              'accuracyAuthorization': e.accuracyAuthorization,
            }),
          )
          .listen(callback),
    );
  }

  /// Subscribe to geofence events.
  ///
  /// Fires on enter, exit, or dwell transitions.
  static StreamSubscription<GeofenceEvent> onGeofence(
    void Function(GeofenceEvent) callback,
  ) {
    return _tracked(
      _platform.geofenceEvents
          .map(
            (e) => GeofenceEvent.fromMap({
              'identifier': e.identifier,
              'action': e.action.name,
              'location': Location.fromTl(e.location).toMap(),
              'extras': e.extras,
            }),
          )
          .listen(callback),
    );
  }

  /// Subscribe to geofences change events.
  ///
  /// Fires when the set of actively monitored geofences changes.
  static StreamSubscription<GeofencesChangeEvent> onGeofencesChange(
    void Function(GeofencesChangeEvent) callback,
  ) {
    return _tracked(
      _platform.geofencesChangeEvents
          .map(
            (e) => GeofencesChangeEvent.fromMap({
              'on': e.on
                  ?.whereType<TlGeofence>()
                  .map(
                    (g) => <String, Object?>{
                      'identifier': g.identifier,
                      'latitude': g.latitude,
                      'longitude': g.longitude,
                      'radius': g.radius,
                    },
                  )
                  .toList(),
              'off': e.off
                  ?.whereType<TlGeofence>()
                  .map(
                    (g) => <String, Object?>{
                      'identifier': g.identifier,
                      'latitude': g.latitude,
                      'longitude': g.longitude,
                      'radius': g.radius,
                    },
                  )
                  .toList(),
            }),
          )
          .listen(callback),
    );
  }

  /// Subscribe to driving-behavior (telematics) events.
  ///
  /// Requires `TelematicsConfig.enableDrivingEvents`. Fires `harsh_braking`,
  /// `harsh_acceleration`, `harsh_cornering`, and `speeding`.
  static StreamSubscription<DrivingEvent> onDrivingEvent(
    void Function(DrivingEvent) callback,
  ) {
    return _tracked(drivingEventStream.listen(callback));
  }

  /// Subscribe to crash/fall impact events.
  ///
  /// Requires `ImpactConfig.enableCrashDetection` (and/or `enableFallDetection`).
  /// A `potential_*` event can be cancelled within its window via
  /// [cancelImpact], or confirmed early via [confirmImpact].
  static StreamSubscription<ImpactEvent> onImpact(
    void Function(ImpactEvent) callback,
  ) {
    return _tracked(impactStream.listen(callback));
  }

  /// Subscribe to fused transport-mode changes.
  ///
  /// Requires `ClassifierConfig.enableFusedClassifier`.
  static StreamSubscription<ModeChangeEvent> onModeChange(
    void Function(ModeChangeEvent) callback,
  ) {
    return _tracked(modeChangeStream.listen(callback));
  }

  /// Subscribe to heartbeat events.
  ///
  /// Fires at the interval configured in [AppConfig.heartbeatInterval].
  static StreamSubscription<HeartbeatEvent> onHeartbeat(
    void Function(HeartbeatEvent) callback,
  ) {
    return _tracked(
      _platform.heartbeatEvents
          .map((e) => HeartbeatEvent(location: Location.fromTl(e.location)))
          .listen(callback),
    );
  }

  /// Subscribe to HTTP sync events.
  ///
  /// Fires after each HTTP request completes (success or failure).
  static StreamSubscription<HttpEvent> onHttp(
    void Function(HttpEvent) callback,
  ) {
    return _tracked(
      _platform.httpEvents
          .map(
            (e) => HttpEvent(
              success: e.isSuccess,
              status: e.status,
              responseText: e.responseText,
            ),
          )
          .listen(callback),
    );
  }

  /// Subscribe to schedule events.
  ///
  /// Fires when the scheduler starts or stops a tracking period.
  static StreamSubscription<State> onSchedule(void Function(State) callback) {
    return _tracked(
      _platform.scheduleEvents
          .map(
            (s) => State.fromMap({
              'enabled': s.enabled,
              'isMoving': s.isMoving,
              'trackingMode': s.trackingMode,
              'schedulerEnabled': s.schedulerEnabled,
              'odometer': s.odometer,
              'lastLocationTimestamp': s.lastLocationTimestamp,
            }),
          )
          .listen(callback),
    );
  }

  /// Subscribe to power-save mode changes.
  ///
  /// Fires when the device enters or exits battery saver mode.
  static StreamSubscription<bool> onPowerSaveChange(
    void Function(bool) callback,
  ) {
    return _tracked(_platform.powerSaveChangeEvents.listen(callback));
  }

  /// Subscribe to connectivity change events.
  ///
  /// Fires when the device goes online or offline.
  static StreamSubscription<ConnectivityChangeEvent> onConnectivityChange(
    void Function(ConnectivityChangeEvent) callback,
  ) {
    return _tracked(
      _platform.connectivityChangeEvents
          .map((e) => ConnectivityChangeEvent(connected: e.connected))
          .listen(callback),
    );
  }

  /// Subscribe to enabled-change events.
  ///
  /// Fires when tracking is enabled or disabled.
  static StreamSubscription<bool> onEnabledChange(
    void Function(bool) callback,
  ) {
    return _tracked(_platform.enabledChangeEvents.listen(callback));
  }

  /// Subscribe to notification action events (Android only).
  ///
  /// Fires when the user taps a notification action button.
  static StreamSubscription<String> onNotificationAction(
    void Function(String) callback,
  ) {
    return _tracked(_platform.notificationActionEvents.listen(callback));
  }

  /// Subscribe to authorization events.
  ///
  /// Fires during OAuth-style token refresh flows.
  static StreamSubscription<AuthorizationEvent> onAuthorization(
    void Function(AuthorizationEvent) callback,
  ) {
    return _tracked(
      _platform.authorizationEvents
          .map(
            (e) => AuthorizationEvent(
              success: e.success,
              status: e.status,
              response: e.response,
            ),
          )
          .listen(callback),
    );
  }

  /// Subscribe to trip events.
  ///
  /// Fires when a trip ends (device transitions from moving to stationary).
  /// The event includes a full summary: distance, duration, start/stop
  /// locations, and the ordered list of waypoints recorded during the trip.
  ///
  /// ```dart
  /// Tracelet.onTrip((trip) {
  ///   print('Trip ended: ${trip.distance}m in ${trip.duration}s');
  ///   print('Waypoints: ${trip.waypoints.length}');
  /// });
  /// ```
  static StreamSubscription<TripEvent> onTrip(
    void Function(TripEvent) callback,
  ) {
    return _tracked(_tripController.stream.listen(callback));
  }

  /// Subscribe to trip *start* events (#402).
  ///
  /// Fires when a trip begins (device transitions from stationary to moving),
  /// carrying the [TripStartEvent.tripId] that every location and driving
  /// event recorded until the matching [onTrip] will be stamped with.
  ///
  /// Previously a trip only became observable once it had ended, so an app
  /// wanting to group records by trip had to re-derive the boundary from
  /// [onMotionChange] and would drift from the SDK's own trip detection.
  ///
  /// ```dart
  /// Tracelet.onTripStart((trip) {
  ///   print('Trip ${trip.tripId} started at ${trip.startedAt}');
  /// });
  /// ```
  static StreamSubscription<TripStartEvent> onTripStart(
    void Function(TripStartEvent) callback,
  ) {
    return _tracked(_tripStartController.stream.listen(callback));
  }

  /// The active trip's id, or `null` when no trip is running (#402).
  ///
  /// The same value the SDK is stamping onto records as they are written, so
  /// an app can tag its own data with the trip in force right now.
  static String? get currentTripId => _tripManager.currentTripId;

  /// Subscribe to battery budget adjustment events.
  ///
  /// Fires when the battery budget engine adjusts tracking parameters
  /// (distance filter, desired accuracy, periodic interval) to stay
  /// within the configured [GeoConfig.batteryBudgetPerHour] budget.
  ///
  /// Only fires when `batteryBudgetPerHour > 0` in the config.
  ///
  /// ```dart
  /// Tracelet.onBudgetAdjustment((event) {
  ///   print('Drain: ${event.currentBatteryDrain}%/hr');
  ///   print('New distance filter: ${event.newDistanceFilter}m');
  /// });
  /// ```
  static StreamSubscription<BudgetAdjustmentEvent> onBudgetAdjustment(
    void Function(BudgetAdjustmentEvent) callback,
  ) {
    return _tracked(_budgetController.stream.listen(callback));
  }

  /// A broadcast stream of the merged active [Config] each time a remotely
  /// fetched configuration (Enterprise `remoteConfigUrl`) is applied at runtime.
  ///
  /// The native layer fetches and applies remote config on its own; this stream
  /// (and [activeConfig]) reflect the result on the Dart side.
  static Stream<Config> get remoteConfigStream =>
      _remoteConfigController.stream;

  /// Subscribe to remote-config-applied events.
  ///
  /// Fires with the merged active [Config] whenever a remotely fetched
  /// configuration override (Enterprise `remoteConfigUrl`) is applied at
  /// runtime. Use it to react to server-driven config changes; after it fires,
  /// [activeConfig] already reflects the new values.
  ///
  /// ```dart
  /// Tracelet.onRemoteConfig((config) {
  ///   print('Remote budget: ${config.geo.batteryBudgetPerHour}%/hr');
  /// });
  /// ```
  static StreamSubscription<Config> onRemoteConfig(
    void Function(Config) callback,
  ) {
    return _tracked(_remoteConfigController.stream.listen(callback));
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Cancels **all** active subscriptions created by `onXxx()` and
  /// [watchPosition], then clears the internal stream and channel cache.
  ///
  /// Call this when you want to tear down all listeners at once — for
  /// example, in a widget's `dispose()` method or during test cleanup.
  ///
  /// After calling this, new `onXxx()` calls will create fresh platform
  /// channel subscriptions.
  ///
  /// ```dart
  /// @override
  /// void dispose() {
  ///   Tracelet.removeListeners();
  ///   super.dispose();
  /// }
  /// ```
  static void removeListeners() {
    for (final sub in _onSubscriptions) {
      sub.cancel();
    }
    _onSubscriptions.clear();
    for (final sub in _watchSubscriptions.values) {
      sub.cancel();
    }
    _watchSubscriptions.clear();
    _processedLocationStream = null;
    _motionChangeStream = null;
    _activityChangeStream = null;
    _providerChangeStream = null;
    _geofenceStream = null;
    _geofencesChangeStream = null;
    _heartbeatStream = null;
    _httpStream = null;
    _scheduleStream = null;
    _connectivityChangeStream = null;

    // Stop trip detection subscriptions.
    _stopTripDetection();

    // Stop adaptive activity tracking subscription (D-H7).
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Wraps a subscription so [removeListeners] can cancel it later.
  static StreamSubscription<T> _tracked<T>(StreamSubscription<T> sub) {
    _onSubscriptions.add(sub);
    return sub;
  }

  /// Start internal subscriptions that feed the TripManager.
  static void _startTripDetection() {
    _stopTripDetection(); // Ensure clean state.

    // Listen to motion changes to start/end trips.
    _tripMotionSub = _platform.motionChangeEvents.map(Location.fromTl).listen((
      location,
    ) {
      final isMoving = location.isMoving;
      _tripManager.onMotionStateChanged(
        isMoving: isMoving,
        latitude: location.coords.latitude,
        longitude: location.coords.longitude,
        timestamp: location.timestamp,
        // #402: the native layer's id for this trip, which is the one stamped
        // onto the stored records. Without it this manager would mint a second
        // id for the same journey and nothing would join up.
        nativeTripId: location.extras['tripId'] as String?,
      );
    });

    // Listen to location updates to record waypoints.
    // Reuse the processed location stream to avoid duplicate
    // Location.fromMap() deserialization (D-H1).
    _tripLocationSub = _getProcessedLocationStream().listen((location) {
      _tripManager.onLocationReceived(
        latitude: location.coords.latitude,
        longitude: location.coords.longitude,
        timestamp: location.timestamp,
      );
    });
  }

  /// Stop internal subscriptions that feed the TripManager.
  static void _stopTripDetection() {
    _tripLocationSub?.cancel();
    _tripLocationSub = null;
    _tripMotionSub?.cancel();
    _tripMotionSub = null;
  }

  // ---------------------------------------------------------------------------
  // ---------------------------------------------------------------------------
  // Battery Budget — auto-adjust tracking params to stay within budget
  // ---------------------------------------------------------------------------

  /// Start feeding battery levels to the [BatteryBudgetEngine].
  static void _startBatteryBudgetTracking() {
    if (_batteryBudgetEngine == null) return;
    _stopBatteryBudgetTracking();

    _budgetLocationSub = _getProcessedLocationStream().listen((location) {
      final engine = _batteryBudgetEngine;
      if (engine == null) return;

      final batteryLevel = location.battery.level;
      if (batteryLevel < 0) return; // No battery info available.

      final adjustment = engine.processSample(batteryLevel);
      if (adjustment == null) return;

      _budgetController.add(adjustment);
      _applyBudgetAdjustment(adjustment);
    });
  }

  /// Stop the battery budget tracking subscription.
  static void _stopBatteryBudgetTracking() {
    _budgetLocationSub?.cancel();
    _budgetLocationSub = null;
  }

  /// Apply a budget adjustment by sending updated geo config to native.
  static void _applyBudgetAdjustment(BudgetAdjustmentEvent adjustment) {
    final map = _currentConfig.toMap();
    final geoMap = Map<String, Object?>.from(map['geo'] as Map? ?? {});

    geoMap['distanceFilter'] = adjustment.newDistanceFilter;
    geoMap['desiredAccuracy'] = adjustment.newDesiredAccuracy;

    if (adjustment.newPeriodicInterval != null) {
      geoMap['periodicLocationInterval'] = adjustment.newPeriodicInterval;
    }

    map['geo'] = geoMap;
    _currentConfig = Config.fromMap(map);

    // Send to native (fire-and-forget — the native side merges & restarts).
    _platform.setConfig(_currentConfig.toTlConfig());
  }
}

// =============================================================================
// Headless callback dispatcher — entry point for background Dart isolate
// =============================================================================

/// Internal entry point executed by the native FlutterEngine when the app UI
/// is not running (e.g. after device reboot or task removal).
///
/// The native side:
/// 1. Creates a new `FlutterEngine`.
/// 2. Executes this function as the Dart entry point.
/// 3. Sends headless events via the `com.tracelet/headless` MethodChannel.
///
/// This dispatcher looks up the user's dispatch callback from its persisted
/// handle and invokes it for every incoming event.
@pragma('vm:entry-point')
void _headlessCallbackDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.tracelet/headless');

  channel.setMethodCallHandler((MethodCall call) async {
    if (call.method == 'headlessEvent') {
      final raw = call.arguments;
      if (raw is! Map) return;

      final args = raw.map<String, Object?>(
        (Object? k, Object? v) => MapEntry(k.toString(), v),
      );

      // Retrieve the dispatch callback ID sent alongside the event.
      final dispatchId = args['dispatchId'] as int?;
      if (dispatchId == null) return;

      final callbackHandle = ui.CallbackHandle.fromRawHandle(dispatchId);
      final callback = ui.PluginUtilities.getCallbackFromHandle(callbackHandle);
      if (callback == null) return;

      // Build the HeadlessEvent from the nested 'event' payload.
      final eventData = args['event'];
      final eventMap = eventData is Map
          ? eventData.map<String, Object?>(
              (Object? k, Object? v) => MapEntry(k.toString(), v),
            )
          : const <String, Object?>{};

      final name = args['name'] as String? ?? '';

      final headlessEvent = HeadlessEvent(name: name, event: eventMap);

      // Invoke as void Function(HeadlessEvent).
      (callback as void Function(HeadlessEvent))(headlessEvent);
    }
  });

  // Signal to the native side that the isolate is ready.
  channel.invokeMethod<void>('initialized');
}

// =============================================================================
// MethodChannel Data Helpers
// =============================================================================

/// Performs a deep cast of a dynamic map to `Map<String, Object?>`.
///
/// Native `MethodChannel` payloads decode objects dynamically as
/// `Map<Object?, Object?>`. This ensures all nested structures conform to
/// string-keyed maps for reliable JSON encoding or Dart-side access.
Map<String, Object?> _deepCastMap(Map<Object?, Object?> map) {
  return map.map((key, value) => MapEntry(key.toString(), _deepCast(value)));
}

/// Recursively deep casts lists and maps.
Object? _deepCast(Object? value) {
  if (value is Map) {
    return _deepCastMap(value);
  } else if (value is List) {
    return value.map(_deepCast).toList();
  } else {
    return value;
  }
}
