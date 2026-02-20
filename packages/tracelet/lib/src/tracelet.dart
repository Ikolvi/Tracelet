import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

import 'models/activity_change_event.dart';
import 'models/authorization_event.dart';
import 'models/config.dart';
import 'models/connectivity_change_event.dart';
import 'models/device_info.dart';
import 'models/geofence.dart';
import 'models/geofence_event.dart';
import 'models/geofences_change_event.dart';
import 'models/headless_event.dart';
import 'models/heartbeat_event.dart';
import 'models/http_event.dart';
import 'models/location.dart';
import 'models/provider_change_event.dart';
import 'models/sensors.dart';
import 'models/sql_query.dart';
import 'models/state.dart';

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
  // Event Channel streams (lazily created singletons)
  // ---------------------------------------------------------------------------

  static final Map<String, EventChannel> _eventChannels =
      <String, EventChannel>{};
  static final Map<String, Stream<Object?>> _eventStreams =
      <String, Stream<Object?>>{};

  static Stream<Object?> _getEventStream(String name) {
    return _eventStreams.putIfAbsent(name, () {
      final channel = _eventChannels.putIfAbsent(
        name,
        () => EventChannel(name),
      );
      return channel.receiveBroadcastStream();
    });
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
    final result = await _platform.ready(config.toMap());
    return State.fromMap(result);
  }

  /// Start location tracking.
  ///
  /// Returns the updated [State] after starting.
  static Future<State> start() async {
    final result = await _platform.start();
    return State.fromMap(result);
  }

  /// Stop location tracking.
  ///
  /// Returns the updated [State] after stopping.
  static Future<State> stop() async {
    final result = await _platform.stop();
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

  /// Get the current plugin [State].
  static Future<State> getState() async {
    final result = await _platform.getState();
    return State.fromMap(result);
  }

  /// Update the plugin configuration.
  ///
  /// Returns the updated [State].
  static Future<State> setConfig(Config config) async {
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
  /// Accepts optional [options] for `desiredAccuracy`, `timeout`, etc.
  ///
  /// ```dart
  /// final loc = await Tracelet.getCurrentPosition(
  ///   desiredAccuracy: DesiredAccuracy.high,
  ///   timeout: 30,
  /// );
  /// ```
  static Future<Location> getCurrentPosition({
    DesiredAccuracy? desiredAccuracy,
    int? timeout,
    int? maximumAge,
    Map<String, Object?>? extras,
  }) async {
    final options = <String, Object?>{
      if (desiredAccuracy != null) 'desiredAccuracy': desiredAccuracy.index,
      if (timeout != null) 'timeout': timeout,
      if (maximumAge != null) 'maximumAge': maximumAge,
      if (extras != null) 'extras': extras,
    };
    final result = await _platform.getCurrentPosition(options);
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

    // Listen to the watchPosition event stream for this watcher
    final stream = _getEventStream(TraceletEvents.watchPosition);
    stream.listen((Object? event) {
      if (event is Map) {
        final map = event.map<String, Object?>(
          (Object? k, Object? v) => MapEntry(k.toString(), v),
        );
        callback(Location.fromMap(map));
      }
    });

    return watchId;
  }

  /// Stop a watch started by [watchPosition].
  static Future<bool> stopWatchPosition(int watchId) {
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
      geofences.map((g) => g.toMap()).toList(),
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
  static Future<int> getCount() {
    return _platform.getCount();
  }

  /// Destroy all stored locations.
  static Future<bool> destroyLocations() {
    return _platform.destroyLocations();
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
  // Utility
  // ---------------------------------------------------------------------------

  /// Whether the device is currently in power-save (battery saver) mode.
  static Future<bool> get isPowerSaveMode => _platform.isPowerSaveMode();

  /// Request location permission from the user.
  ///
  /// Returns the resulting [AuthorizationStatus] as an int.
  static Future<int> requestPermission() {
    return _platform.requestPermission();
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
    // The internal dispatcher that the native side executes as the Dart
    // entry point for the headless isolate.
    final registrationHandle =
        ui.PluginUtilities.getCallbackHandle(_headlessCallbackDispatcher);
    if (registrationHandle == null) {
      throw StateError(
        'Could not look up _headlessCallbackDispatcher handle.',
      );
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
  // Event Subscriptions
  // ---------------------------------------------------------------------------

  /// Subscribe to location events.
  ///
  /// Fires for every recorded location.
  static StreamSubscription<Location> onLocation(
    void Function(Location) callback,
  ) {
    return _getEventStream(TraceletEvents.location)
        .map(_castToMap)
        .map(Location.fromMap)
        .listen(callback);
  }

  /// Subscribe to motion change events.
  ///
  /// Fires when the device transitions between stationary and moving states.
  static StreamSubscription<Location> onMotionChange(
    void Function(Location) callback,
  ) {
    return _getEventStream(TraceletEvents.motionChange)
        .map(_castToMap)
        .map(Location.fromMap)
        .listen(callback);
  }

  /// Subscribe to activity change events.
  ///
  /// Fires when the detected device activity changes (still, walking, etc.).
  static StreamSubscription<ActivityChangeEvent> onActivityChange(
    void Function(ActivityChangeEvent) callback,
  ) {
    return _getEventStream(TraceletEvents.activityChange)
        .map(_castToMap)
        .map(ActivityChangeEvent.fromMap)
        .listen(callback);
  }

  /// Subscribe to provider change events.
  ///
  /// Fires when GPS/network/authorization state changes.
  static StreamSubscription<ProviderChangeEvent> onProviderChange(
    void Function(ProviderChangeEvent) callback,
  ) {
    return _getEventStream(TraceletEvents.providerChange)
        .map(_castToMap)
        .map(ProviderChangeEvent.fromMap)
        .listen(callback);
  }

  /// Subscribe to geofence events.
  ///
  /// Fires on enter, exit, or dwell transitions.
  static StreamSubscription<GeofenceEvent> onGeofence(
    void Function(GeofenceEvent) callback,
  ) {
    return _getEventStream(TraceletEvents.geofence)
        .map(_castToMap)
        .map(GeofenceEvent.fromMap)
        .listen(callback);
  }

  /// Subscribe to geofences change events.
  ///
  /// Fires when the set of actively monitored geofences changes.
  static StreamSubscription<GeofencesChangeEvent> onGeofencesChange(
    void Function(GeofencesChangeEvent) callback,
  ) {
    return _getEventStream(TraceletEvents.geofencesChange)
        .map(_castToMap)
        .map(GeofencesChangeEvent.fromMap)
        .listen(callback);
  }

  /// Subscribe to heartbeat events.
  ///
  /// Fires at the interval configured in [AppConfig.heartbeatInterval].
  static StreamSubscription<HeartbeatEvent> onHeartbeat(
    void Function(HeartbeatEvent) callback,
  ) {
    return _getEventStream(TraceletEvents.heartbeat)
        .map(_castToMap)
        .map(HeartbeatEvent.fromMap)
        .listen(callback);
  }

  /// Subscribe to HTTP sync events.
  ///
  /// Fires after each HTTP request completes (success or failure).
  static StreamSubscription<HttpEvent> onHttp(
    void Function(HttpEvent) callback,
  ) {
    return _getEventStream(TraceletEvents.http)
        .map(_castToMap)
        .map(HttpEvent.fromMap)
        .listen(callback);
  }

  /// Subscribe to schedule events.
  ///
  /// Fires when the scheduler starts or stops a tracking period.
  static StreamSubscription<State> onSchedule(
    void Function(State) callback,
  ) {
    return _getEventStream(TraceletEvents.schedule)
        .map(_castToMap)
        .map(State.fromMap)
        .listen(callback);
  }

  /// Subscribe to power-save mode changes.
  ///
  /// Fires when the device enters or exits battery saver mode.
  static StreamSubscription<bool> onPowerSaveChange(
    void Function(bool) callback,
  ) {
    return _getEventStream(TraceletEvents.powerSaveChange)
        .map((event) {
      if (event is bool) return event;
      if (event is int) return event != 0;
      if (event is Map) {
        final v = event['isPowerSaveMode'] ?? event['enabled'];
        if (v is bool) return v;
        if (v is int) return v != 0;
      }
      return false;
    }).listen(callback);
  }

  /// Subscribe to connectivity change events.
  ///
  /// Fires when the device goes online or offline.
  static StreamSubscription<ConnectivityChangeEvent> onConnectivityChange(
    void Function(ConnectivityChangeEvent) callback,
  ) {
    return _getEventStream(TraceletEvents.connectivityChange)
        .map(_castToMap)
        .map(ConnectivityChangeEvent.fromMap)
        .listen(callback);
  }

  /// Subscribe to enabled-change events.
  ///
  /// Fires when tracking is enabled or disabled.
  static StreamSubscription<bool> onEnabledChange(
    void Function(bool) callback,
  ) {
    return _getEventStream(TraceletEvents.enabledChange)
        .map((event) {
      if (event is bool) return event;
      if (event is int) return event != 0;
      if (event is Map) {
        final v = event['enabled'];
        if (v is bool) return v;
        if (v is int) return v != 0;
      }
      return false;
    }).listen(callback);
  }

  /// Subscribe to notification action events (Android only).
  ///
  /// Fires when the user taps a notification action button.
  static StreamSubscription<String> onNotificationAction(
    void Function(String) callback,
  ) {
    return _getEventStream(TraceletEvents.notificationAction)
        .map((event) {
      if (event is String) return event;
      if (event is Map) return event['action']?.toString() ?? '';
      return '';
    }).listen(callback);
  }

  /// Subscribe to authorization events.
  ///
  /// Fires during OAuth-style token refresh flows.
  static StreamSubscription<AuthorizationEvent> onAuthorization(
    void Function(AuthorizationEvent) callback,
  ) {
    return _getEventStream(TraceletEvents.authorization)
        .map(_castToMap)
        .map(AuthorizationEvent.fromMap)
        .listen(callback);
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Removes all cached event streams, forcing fresh subscriptions on the
  /// next `onXxx()` call.
  ///
  /// Call this when you want to tear down all listeners at once — for
  /// example, in a widget's `dispose()` method or during test cleanup.
  ///
  /// **Note**: This does NOT cancel individual [StreamSubscription]s
  /// returned by `onXxx()` methods — you are still responsible for calling
  /// `.cancel()` on each subscription. This only clears the internal
  /// stream/channel cache so that new subscriptions create fresh platform
  /// channels.
  ///
  /// ```dart
  /// @override
  /// void dispose() {
  ///   _locationSub?.cancel();
  ///   _motionSub?.cancel();
  ///   Tracelet.removeListeners();
  ///   super.dispose();
  /// }
  /// ```
  static void removeListeners() {
    _eventStreams.clear();
    _eventChannels.clear();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static Map<String, Object?> _castToMap(Object? event) {
    if (event is Map) {
      return event.map<String, Object?>(
        (Object? k, Object? v) => MapEntry(k.toString(), v),
      );
    }
    return const <String, Object?>{};
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
              (Object? k, Object? v) => MapEntry(k.toString(), v))
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
