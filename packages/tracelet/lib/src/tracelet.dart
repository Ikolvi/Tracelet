import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

import 'models/activity_change_event.dart';
import 'models/attestation_config.dart';
import 'models/audit_config.dart';
import 'models/audit_proof.dart';
import 'models/authorization_event.dart';
import 'models/compliance_report.dart';
import 'models/config.dart';
import 'models/connectivity_change_event.dart';
import 'models/device_info.dart';
import 'models/geofence.dart';
import 'models/geofence_event.dart';
import 'models/geofences_change_event.dart';
import 'models/headless_event.dart';
import 'models/health_check.dart';
import 'models/heartbeat_event.dart';
import 'models/http_event.dart';
import 'models/location.dart';
import 'models/privacy_zone.dart';
import 'models/privacy_zone_config.dart';
import 'models/provider_change_event.dart';
import 'models/route_context.dart';
import 'models/sensors.dart';
import 'models/sql_query.dart';
import 'models/state.dart';
import 'models/sync_body_context.dart';
import 'models/trip_event.dart';

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

  /// Kalman filter instance for GPS smoothing (runs in Dart, not native).
  static final KalmanLocationFilter _kalmanFilter = KalmanLocationFilter();

  /// Trip manager instance for trip detection (runs in Dart, not native).
  static final TripManager _tripManager = TripManager();

  /// StreamController for trip events (computed in Dart, not native).
  static final StreamController<TripEvent> _tripController =
      StreamController<TripEvent>.broadcast();

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

  /// Whether the Kalman filter is enabled (set from config).
  static bool _useKalmanFilter = false;

  /// Whether adaptive sampling mode is enabled (set from config).
  static bool _enableAdaptiveMode = false;

  /// Last known activity type for adaptive sampling.
  static ActivityType _lastActivityType = ActivityType.unknown;

  /// Last known activity confidence for adaptive sampling.
  static ActivityConfidence _lastActivityConfidence = ActivityConfidence.low;

  /// Last known battery level (0.0–1.0) for adaptive sampling.
  static double _lastBatteryLevel = -1.0;

  /// Last known charging state for adaptive sampling.
  static bool _lastIsCharging = false;

  /// Subscription that feeds activity changes to adaptive sampling state.
  static StreamSubscription<ActivityChangeEvent>? _adaptiveActivitySub;

  /// Location processor for distance/accuracy/speed filtering
  /// (runs in Dart, not native).
  static LocationProcessor? _locationProcessor;

  /// Geofence evaluator for high-accuracy proximity checks
  /// (runs in Dart, not native).
  static final GeofenceEvaluator _geofenceEvaluator = GeofenceEvaluator();

  /// Cached processed location broadcast stream.
  ///
  /// Filtering and Kalman smoothing are applied ONCE here, then shared
  /// across all `onLocation` subscribers. Without this, each listener
  /// would independently call `_filterLocation` on the same stateful
  /// [LocationProcessor], causing the second listener to see distance=0
  /// and incorrectly filter the location.
  static Stream<Location>? _processedLocationStream;

  /// Whether the Kalman filter is currently enabled for GPS smoothing.
  ///
  /// Returns `true` if [ready] or [setConfig] was called with
  /// `LocationFilter(useKalmanFilter: true)`.
  static bool get isKalmanFilterEnabled => _useKalmanFilter;

  /// Create a [LocationProcessor] from the geo settings in [config].
  static LocationProcessor _processorFromConfig(Config config) {
    return LocationProcessor(
      distanceFilter: config.geo.distanceFilter,
      disableElasticity: config.geo.disableElasticity,
      elasticityMultiplier: config.geo.elasticityMultiplier,
      enableAdaptiveMode: config.geo.enableAdaptiveMode,
      trackingAccuracyThreshold:
          config.geo.filter?.trackingAccuracyThreshold ?? 0,
      filterPolicy: config.geo.filter?.policy.index ?? 0,
      maxImpliedSpeed: config.geo.filter?.maxImpliedSpeed ?? 0,
      odometerAccuracyThreshold:
          config.geo.filter?.odometerAccuracyThreshold ?? 0,
      rejectMockLocations: config.geo.filter?.rejectMockLocations ?? false,
      mockDetectionLevel: config.geo.filter?.mockDetectionLevel.index ?? 1,
      enableSparseUpdates: config.geo.enableSparseUpdates,
      sparseDistanceThreshold: config.geo.sparseDistanceThreshold,
      sparseMaxIdleSeconds: config.geo.sparseMaxIdleSeconds,
    );
  }

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

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Initialize the plugin with the given [config].
  ///
  /// **Must be called before any other method.** Returns the current [State].
  ///
  /// ```dart
  /// final state = await Tracelet.ready(Config(
  ///   geo: GeoConfig(distanceFilter: 10),
  /// ));
  /// print('Enabled: ${state.enabled}');
  /// ```
  static Future<State> ready(Config config) async {
    // Capture Kalman filter setting from config.
    _useKalmanFilter = config.geo.filter?.useKalmanFilter ?? false;
    _kalmanFilter.reset();

    // Capture adaptive sampling setting from config.
    _enableAdaptiveMode = config.geo.enableAdaptiveMode;

    // Initialize location processor from config.
    _locationProcessor = _processorFromConfig(config);
    _geofenceEvaluator.clear();

    // Initialize battery budget engine from config.
    _initBatteryBudget(config);

    // Wire trip manager output to the Dart stream controller.
    _tripManager.onTripEnd = (tripData) {
      _tripController.add(TripEvent.fromMap(tripData));
    };

    final result = await _platform.ready(config.toMap());
    return State.fromMap(result);
  }

  /// Start location tracking.
  ///
  /// Returns the updated [State] after starting.
  static Future<State> start() async {
    final result = await _platform.start();

    // Start internal trip detection subscriptions.
    _startTripDetection();

    // Start adaptive sampling activity tracking if enabled.
    _startAdaptiveActivityTracking();

    // Start battery budget tracking if enabled.
    _startBatteryBudgetTracking();

    return State.fromMap(result);
  }

  /// Stop location tracking.
  ///
  /// Returns the updated [State] after stopping.
  static Future<State> stop() async {
    final result = await _platform.stop();

    // Stop trip detection and reset.
    _stopTripDetection();
    _tripManager.reset();
    _kalmanFilter.reset();
    _locationProcessor?.reset();
    _geofenceEvaluator.clear();
    _stopAdaptiveActivityTracking();
    _stopBatteryBudgetTracking();
    _batteryBudgetEngine?.reset();

    return State.fromMap(result);
  }

  /// Start geofence-only tracking mode.
  ///
  /// The plugin will only monitor geofences without continuous location
  /// tracking, saving significant battery.
  static Future<State> startGeofences() async {
    final result = await _platform.startGeofences();
    return State.fromMap(result);
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
    return State.fromMap(result);
  }

  /// Get the current plugin [State].
  static Future<State> getState() async {
    final result = await _platform.getState();
    return State.fromMap(result);
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
      _platform.getPermissionStatus(), // 7
      _platform.getMotionPermissionStatus(), // 8
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
      locationPermissionStatus: results[7] as int,
      motionPermissionStatus: results[8] as int,
      dbCount: results[9] as int,
    );
  }

  /// Update the plugin configuration.
  ///
  /// Returns the updated [State].
  static Future<State> setConfig(Config config) async {
    // Update Kalman filter setting.
    _useKalmanFilter = config.geo.filter?.useKalmanFilter ?? false;

    // Update adaptive sampling setting.
    _enableAdaptiveMode = config.geo.enableAdaptiveMode;

    // Update location processor, preserving internal state.
    final newProcessor = _processorFromConfig(config);
    _locationProcessor?.transferStateTo(newProcessor);
    _locationProcessor = newProcessor;

    // Update battery budget engine from config.
    _initBatteryBudget(config);

    // Invalidate cached stream pipeline so it rebuilds with new settings (D-M8).
    _processedLocationStream = null;

    final result = await _platform.setConfig(config.toMap());
    return State.fromMap(result);
  }

  /// Reset to default configuration, optionally applying a new [config].
  ///
  /// Returns the updated [State].
  static Future<State> reset([Config? config]) async {
    final result = await _platform.reset(config?.toMap());
    return State.fromMap(result);
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
  /// - [desiredAccuracy]: The accuracy level for this request. Overrides the
  ///   configured accuracy. Defaults to the value in [GeoConfig].
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
    Map<String, Object?>? extras,
  }) async {
    final options = <String, Object?>{
      if (desiredAccuracy != null) 'desiredAccuracy': desiredAccuracy.index,
      if (timeout != null) 'timeout': timeout,
      if (maximumAge != null) 'maximumAge': maximumAge,
      if (persist != null) 'persist': persist,
      if (samples != null) 'samples': samples,
      if (extras != null) 'extras': extras,
    };
    final result = await _platform.getCurrentPosition(options);
    return Location.fromMap(result);
  }

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
    final options = <String, Object?>{
      'persist': persist,
      if (extras != null) 'extras': extras,
    };
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
    final options = <String, Object?>{
      if (interval != null) 'interval': interval,
      if (desiredAccuracy != null) 'desiredAccuracy': desiredAccuracy.index,
      if (extras != null) 'extras': extras,
    };
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
    return _platform.addGeofence(geofence.toMap());
  }

  /// Add multiple [Geofence]s at once.
  static Future<bool> addGeofences(List<Geofence> geofences) {
    return _platform.addGeofences(
      geofences.map((g) => g.toMap()).toList(growable: false),
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
  // Persistence
  // ---------------------------------------------------------------------------

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
    return _platform.insertLocation(params);
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
  // ignore: unused_field
  _syncBodyBuilder;

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
  static void setSyncBodyBuilder(
    Future<Map<String, Object?>> Function(SyncBodyContext)? builder,
  ) {
    _syncBodyBuilder = builder;
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
    final status = await _platform.getPermissionStatus();
    return status == AuthorizationStatus.always.index;
  }

  /// Get the current permission status without triggering any dialog.
  ///
  /// Returns the [AuthorizationStatus] index:
  /// - `0` notDetermined — never asked
  /// - `1` denied — denied but can ask again (Android only)
  /// - `2` whenInUse — foreground granted
  /// - `3` always — background granted
  /// - `4` deniedForever — permanently denied, open Settings to change
  ///
  /// Use this to decide what UI to show before calling [requestPermission].
  static Future<int> getPermissionStatus() {
    return _platform.getPermissionStatus();
  }

  /// Request location permission asynchronously.
  ///
  /// Triggers the native OS permission dialog (no custom native dialogs) and
  /// returns the **actual** [AuthorizationStatus] after the user responds.
  ///
  /// Escalation logic:
  /// - `notDetermined` → requests foreground (When In Use) permission
  /// - `whenInUse` → requests background (Always) permission
  /// - `denied` / `deniedForever` / `always` → returns immediately
  ///
  /// For denied/deniedForever cases, show your own Dart dialog and use
  /// [openAppSettings] to let the user fix permissions manually.
  static Future<int> requestPermission() {
    return _platform.requestPermission();
  }

  /// Get the notification permission status (Android 13+ / API 33+ only).
  ///
  /// Returns a status code:
  /// - `0` notDetermined — never asked
  /// - `1` denied — denied but can ask again
  /// - `3` always (granted)
  /// - `4` deniedForever — permanently denied, must open Settings
  ///
  /// On Android < 13 and on iOS, always returns `3` (granted) since no
  /// runtime notification permission is needed.
  ///
  /// On Android 13+, the POST_NOTIFICATIONS permission is required for
  /// the foreground service notification to be visible. Without it, the
  /// service still runs but the notification is hidden.
  static Future<int> getNotificationPermissionStatus() {
    return _platform.getNotificationPermissionStatus();
  }

  /// Request notification permission asynchronously (Android 13+ / API 33+).
  ///
  /// Triggers the OS POST_NOTIFICATIONS dialog and returns the **actual**
  /// status after the user responds.
  ///
  /// On Android < 13 and on iOS, returns `3` (granted) immediately.
  ///
  /// **Important:** On Android 13+, call this before starting a foreground
  /// service with a notification. Without this permission, the notification
  /// will not be visible (though the service still runs).
  static Future<int> requestNotificationPermission() {
    return _platform.requestNotificationPermission();
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

  /// Get the motion / activity recognition permission status.
  ///
  /// Returns an `AuthorizationStatus` code:
  /// - `0` notDetermined — never asked
  /// - `1` denied — denied but can ask again (Android only)
  /// - `3` always (granted)
  /// - `4` deniedForever — permanently denied, must open Settings
  ///
  /// On Android < 10 (API < 29), always returns `3` since the
  /// ACTIVITY_RECOGNITION runtime permission is not needed.
  /// On iOS, returns the CMMotionActivityManager authorization status.
  ///
  /// **When to use:** Call before [start] to check if the device can detect
  /// motion transitions (walking, driving, stationary).
  ///
  /// **Note:** When `Config.motion.disableMotionActivityUpdates` is `true`,
  /// this always returns `3` (granted) because the accelerometer-only
  /// fallback mode does not require any permission.
  static Future<int> getMotionPermissionStatus() {
    return _platform.getMotionPermissionStatus();
  }

  /// Request motion / activity recognition permission asynchronously.
  ///
  /// On Android 10+ (API 29+), triggers the ACTIVITY_RECOGNITION dialog.
  /// On iOS, triggers the Motion & Fitness permission dialog.
  /// On Android < 10, returns `3` (granted) immediately.
  ///
  /// Returns the actual status after the user responds.
  ///
  /// **Important:** Without this permission **and** without the
  /// accelerometer-only fallback (`Config.motion.disableMotionActivityUpdates`),
  /// the plugin cannot detect motion transitions. The device will not fire
  /// `onMotionChange` events unless [changePace] is called manually.
  ///
  /// When `Config.motion.disableMotionActivityUpdates` is `true`, returns `3`
  /// immediately without showing any dialog.
  static Future<int> requestMotionPermission() {
    return _platform.requestMotionPermission();
  }

  /// Request temporary full accuracy (iOS 14+).
  ///
  /// [purpose] must match a key in the app's `Info.plist`
  /// `NSLocationTemporaryUsageDescriptionDictionary`.
  static Future<int> requestTemporaryFullAccuracy(String purpose) {
    return _platform.requestTemporaryFullAccuracy(purpose);
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
    return State.fromMap(result);
  }

  /// Stop the scheduler.
  static Future<State> stopSchedule() async {
    final result = await _platform.stopSchedule();
    return State.fromMap(result);
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
  ]) {
    return _platform.getCarbonReport(query);
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
      _platform.getPermissionStatus(), // 2
      _platform.getMotionPermissionStatus(), // 3
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
    final locationPerm = results[2] as int;
    final motionPerm = results[3] as int;
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

    final state = State.fromMap(stateMap);

    // Extract config values from the raw state map for compliance data.
    final rawConfig = stateMap['config'];
    final configMap = rawConfig is Map
        ? Map<String, Object?>.from(rawConfig)
        : null;
    final rawGeo = configMap?['geo'];
    final geoMap = rawGeo is Map ? Map<String, Object?>.from(rawGeo) : null;
    final rawHttp = configMap?['http'];
    final httpMap = rawHttp is Map ? Map<String, Object?>.from(rawHttp) : null;
    final rawAudit = configMap?['audit'];
    final auditMap = rawAudit is Map
        ? Map<String, Object?>.from(rawAudit)
        : null;
    final rawPersist = configMap?['persistence'];
    final persistMap = rawPersist is Map
        ? Map<String, Object?>.from(rawPersist)
        : null;

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
      maxDaysToPersist: persistMap?['maxDaysToPersist'] as int? ?? -1,
      maxRecordsToPersist: persistMap?['maxRecordsToPersist'] as int? ?? -1,
      oldestRecord: oldestTs,
      newestRecord: newestTs,
      databaseEncrypted: dbEncrypted,
      activePrivacyZones: zones.length,
      privacyZoneIdentifiers: zones
          .map((z) => z['identifier'] as String? ?? '')
          .toList(),
      httpSyncUrl: httpMap?['url'] as String?,
      autoSyncEnabled: httpMap?['autoSync'] as bool? ?? true,
      auditTrailEnabled: auditMap?['enabled'] as bool? ?? false,
      auditTrailValid: null, // Not verified until explicitly called
      locationPermissionStatus: locationPerm,
      motionPermissionStatus: motionPerm,
      sparseUpdatesEnabled: geoMap?['enableSparseUpdates'] as bool? ?? false,
      kalmanFilterEnabled: _useKalmanFilter,
      deltaCompressionEnabled:
          httpMap?['enableDeltaCompression'] as bool? ?? false,
      trackingEnabled: state.enabled,
      trackingMode: state.trackingMode.name,
    );
  }

  // ---------------------------------------------------------------------------
  // Event Subscriptions
  // ---------------------------------------------------------------------------

  /// A broadcast stream of processed location updates.
  ///
  /// Locations are filtered by [LocationProcessor] (distance, accuracy, speed)
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

  /// Subscribe to location events.
  ///
  /// Fires for every recorded location.
  static StreamSubscription<Location> onLocation(
    void Function(Location) callback,
  ) {
    return _tracked(_getProcessedLocationStream().listen(callback));
  }

  /// Returns a shared broadcast stream of locations that have been filtered
  /// by [LocationProcessor] and smoothed by [KalmanLocationFilter].
  ///
  /// The stream is created lazily on first access and cached so that
  /// stateful transformations (distance filter state, Kalman state) are
  /// applied exactly once per event regardless of subscriber count.
  static Stream<Location> _getProcessedLocationStream() {
    return _processedLocationStream ??= _platform.locationEvents
        .map(Location.fromTl)
        .where(_shouldAcceptLocation)
        .map(_applyKalmanFilter)
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
                  ?.map(
                    (g) => <String, Object?>{
                      'identifier': g.identifier,
                      'latitude': g.latitude,
                      'longitude': g.longitude,
                      'radius': g.radius,
                    },
                  )
                  .toList(),
              'off': e.off
                  ?.map(
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

    // Stop trip detection subscriptions.
    _stopTripDetection();

    // Stop adaptive activity tracking subscription (D-H7).
    _stopAdaptiveActivityTracking();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Wraps a subscription so [removeListeners] can cancel it later.
  static StreamSubscription<T> _tracked<T>(StreamSubscription<T> sub) {
    _onSubscriptions.add(sub);
    return sub;
  }

  /// Returns `true` if the location passes all filters (distance, accuracy,
  /// speed, adaptive sampling). Side-effect: updates adaptive state.
  ///
  /// Used with `Stream.where()` to avoid the list allocation overhead of
  /// `Stream.expand()`.
  static bool _shouldAcceptLocation(Location location) {
    // Periodic locations bypass all filters.
    if (location.event == 'periodic') return true;

    final processor = _locationProcessor;
    if (processor == null) return true;

    final ts = DateTime.tryParse(location.timestamp);
    if (ts == null) return true;

    AdaptiveContext? adaptiveCtx;
    if (_enableAdaptiveMode) {
      final locActivity = location.activity.type;
      final activityType = locActivity != ActivityType.unknown
          ? locActivity
          : _lastActivityType;
      final activityConf = locActivity != ActivityType.unknown
          ? location.activity.confidence
          : _lastActivityConfidence;

      final batteryLevel = location.battery.level >= 0
          ? location.battery.level
          : _lastBatteryLevel;
      final isCharging = location.battery.isCharging || _lastIsCharging;

      _lastBatteryLevel = batteryLevel;
      _lastIsCharging = isCharging;

      adaptiveCtx = AdaptiveContext(
        batteryLevel: batteryLevel,
        isCharging: isCharging,
        activityType: activityType,
        activityConfidence: activityConf,
        speed: location.coords.speed,
      );
    }

    return processor
        .process(
          latitude: location.coords.latitude,
          longitude: location.coords.longitude,
          accuracy: location.coords.accuracy,
          speed: location.coords.speed,
          timestampMs: ts.millisecondsSinceEpoch,
          isMock: location.isMock,
          adaptiveContext: adaptiveCtx,
        )
        .accepted;
  }

  /// Apply Kalman filter to a [Location] if enabled.
  static Location _applyKalmanFilter(Location location) {
    if (!_useKalmanFilter) return location;

    // Parse timestamp safely — skip filtering if timestamp is invalid.
    final ts = DateTime.tryParse(location.timestamp);
    if (ts == null) return location;

    final result = _kalmanFilter.process(
      latitude: location.coords.latitude,
      longitude: location.coords.longitude,
      accuracy: location.coords.accuracy,
      timestampMs: ts.millisecondsSinceEpoch,
    );

    // Return a new Location with smoothed coordinates but original metadata.
    return location.copyWithCoords(
      latitude: result.latitude,
      longitude: result.longitude,
    );
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
  // Adaptive Sampling — activity & battery tracking
  // ---------------------------------------------------------------------------

  /// Start listening to activity change events so the adaptive sampling
  /// engine always has fresh motion context.
  static void _startAdaptiveActivityTracking() {
    if (!_enableAdaptiveMode) return;
    _stopAdaptiveActivityTracking();

    _adaptiveActivitySub = _platform.activityChangeEvents
        .map(
          (e) => ActivityChangeEvent.fromMap({
            'activity': e.activity,
            'confidence': e.confidence,
          }),
        )
        .listen((event) {
          _lastActivityType = event.activity;
          _lastActivityConfidence = event.confidence;
        });
  }

  /// Stop the adaptive activity tracking subscription.
  static void _stopAdaptiveActivityTracking() {
    _adaptiveActivitySub?.cancel();
    _adaptiveActivitySub = null;
    // Reset adaptive state to defaults.
    _lastActivityType = ActivityType.unknown;
    _lastActivityConfidence = ActivityConfidence.low;
    _lastBatteryLevel = -1.0;
    _lastIsCharging = false;
  }

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
    final geoUpdate = <String, Object?>{
      'distanceFilter': adjustment.newDistanceFilter,
      'desiredAccuracy': adjustment.newDesiredAccuracy,
    };
    if (adjustment.newPeriodicInterval != null) {
      geoUpdate['periodicLocationInterval'] = adjustment.newPeriodicInterval;
    }

    // Update the Dart-side location processor to match.
    final processor = _locationProcessor;
    if (processor != null) {
      final updated = LocationProcessor(
        distanceFilter: adjustment.newDistanceFilter,
        disableElasticity: processor.disableElasticity,
        elasticityMultiplier: processor.elasticityMultiplier,
        enableAdaptiveMode: processor.enableAdaptiveMode,
        trackingAccuracyThreshold: processor.trackingAccuracyThreshold,
        filterPolicy: processor.filterPolicy,
        maxImpliedSpeed: processor.maxImpliedSpeed,
        odometerAccuracyThreshold: processor.odometerAccuracyThreshold,
        rejectMockLocations: processor.rejectMockLocations,
        mockDetectionLevel: processor.mockDetectionLevel,
        enableSparseUpdates: processor.enableSparseUpdates,
        sparseDistanceThreshold: processor.sparseDistanceThreshold,
        sparseMaxIdleSeconds: processor.sparseMaxIdleSeconds,
      );
      processor.transferStateTo(updated);
      _locationProcessor = updated;
    }

    // Send to native (fire-and-forget — the native side merges & restarts).
    _platform.setConfig(<String, Object?>{'geo': geoUpdate});
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
  channel.invokeMethod<void>('initialized', null);
}
