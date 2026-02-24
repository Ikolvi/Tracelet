import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'web_event_dispatcher.dart';

// ignore: unused_import — needed for jsify extension

/// Permissions and connectivity engine for Tracelet web.
///
/// Uses `navigator.permissions` API for querying geolocation permission,
/// `Notification.permission` for notification permission, and
/// `navigator.onLine` + events for connectivity tracking.
class WebPermissionsEngine {
  WebPermissionsEngine(this._events);

  final WebEventDispatcher _events;

  /// Subscription to online/offline events.
  bool _connectivityListening = false;

  /// Start listening for connectivity changes.
  void startConnectivityMonitoring() {
    if (_connectivityListening) return;
    _connectivityListening = true;

    web.window.addEventListener(
      'online',
      _onOnline.toJS,
    );
    web.window.addEventListener(
      'offline',
      _onOffline.toJS,
    );
  }

  void _onOnline(web.Event event) {
    _events.emitConnectivityChange(true);
  }

  void _onOffline(web.Event event) {
    _events.emitConnectivityChange(false);
  }

  /// Stop listening for connectivity changes.
  void stopConnectivityMonitoring() {
    if (!_connectivityListening) return;
    _connectivityListening = false;

    web.window.removeEventListener('online', _onOnline.toJS);
    web.window.removeEventListener('offline', _onOffline.toJS);
  }

  // ---------------------------------------------------------------------------
  // Location permission
  // ---------------------------------------------------------------------------

  /// Query geolocation permission status.
  ///
  /// Returns [AuthorizationStatus] index:
  /// - 0 = notDetermined (prompt)
  /// - 2 = whenInUse (granted — web has no "always" distinction)
  /// - 4 = deniedForever (denied)
  Future<int> getPermissionStatus() async {
    try {
      final descriptor = <String, String>{'name': 'geolocation'}.jsify() as JSObject;
      final status =
          await web.window.navigator.permissions.query(descriptor).toDart;
      return _mapPermissionState(status.state);
    } catch (_) {
      // Permissions API not supported — assume prompt.
      return 0; // notDetermined
    }
  }

  /// Request location permission.
  ///
  /// On web, the browser prompts implicitly when `getCurrentPosition` is
  /// called. We trigger a one-shot position request to force the prompt.
  Future<int> requestPermission() async {
    final completer = Completer<int>();

    web.window.navigator.geolocation.getCurrentPosition(
      (web.GeolocationPosition pos) {
        // Success means granted.
        completer.complete(2); // whenInUse
      }.toJS,
      (web.GeolocationPositionError err) {
        if (err.code == 1) {
          // PERMISSION_DENIED
          completer.complete(4); // deniedForever
        } else {
          // Other error (position unavailable, timeout) — permission might be granted.
          completer.complete(0); // notDetermined
        }
      }.toJS,
      web.PositionOptions(timeout: 10000),
    );

    return completer.future;
  }

  // ---------------------------------------------------------------------------
  // Notification permission
  // ---------------------------------------------------------------------------

  Future<int> getNotificationPermissionStatus() async {
    try {
      final permission = web.Notification.permission;
      switch (permission) {
        case 'granted':
          return 3; // always
        case 'denied':
          return 4; // deniedForever
        default:
          return 0; // notDetermined
      }
    } catch (_) {
      return 3; // Notifications API not available — return granted.
    }
  }

  Future<int> requestNotificationPermission() async {
    try {
      final result = await web.Notification.requestPermission().toDart;
      switch (result) {
        case 'granted':
          return 3; // always
        case 'denied':
          return 4; // deniedForever
        default:
          return 0; // notDetermined
      }
    } catch (_) {
      return 3; // Notifications API not available.
    }
  }

  // ---------------------------------------------------------------------------
  // Motion permission (stub — no web equivalent for most browsers)
  // ---------------------------------------------------------------------------

  Future<int> getMotionPermissionStatus() async => 3; // always (granted)

  Future<int> requestMotionPermission() async => 3; // always (granted)

  // ---------------------------------------------------------------------------
  // Provider state
  // ---------------------------------------------------------------------------

  Future<Map<String, Object?>> getProviderState() async {
    final permStatus = await getPermissionStatus();
    final isOnline = web.window.navigator.onLine;

    return <String, Object?>{
      'enabled': true, // Browser always has geolocation capability
      'status': permStatus,
      'gps': true, // Browser abstracts this
      'network': isOnline,
      'accuracyAuthorization': 0, // full
    };
  }

  // ---------------------------------------------------------------------------
  // Device info
  // ---------------------------------------------------------------------------

  Map<String, Object?> getDeviceInfo() {
    final ua = web.window.navigator.userAgent;
    final platform = web.window.navigator.platform;

    return <String, Object?>{
      'model': _parseBrowserName(ua),
      'manufacturer': 'Web',
      'version': _parseBrowserVersion(ua),
      'platform': platform,
      'framework': 'Flutter Web',
    };
  }

  // ---------------------------------------------------------------------------
  // Sensors
  // ---------------------------------------------------------------------------

  Map<String, Object?> getSensors() {
    return <String, Object?>{
      'platform': 'web',
      'accelerometer': false, // Could detect via Generic Sensor API
      'gyroscope': false,
      'magnetometer': false,
      'significantMotion': false,
    };
  }

  // ---------------------------------------------------------------------------
  // Connectivity
  // ---------------------------------------------------------------------------

  bool get isConnected => web.window.navigator.onLine;

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  int _mapPermissionState(String state) {
    switch (state) {
      case 'granted':
        return 2; // whenInUse
      case 'denied':
        return 4; // deniedForever
      case 'prompt':
      default:
        return 0; // notDetermined
    }
  }

  static String _parseBrowserName(String ua) {
    if (ua.contains('Chrome') && !ua.contains('Edg')) return 'Chrome';
    if (ua.contains('Edg')) return 'Edge';
    if (ua.contains('Firefox')) return 'Firefox';
    if (ua.contains('Safari') && !ua.contains('Chrome')) return 'Safari';
    if (ua.contains('Opera') || ua.contains('OPR')) return 'Opera';
    return 'Unknown Browser';
  }

  static String _parseBrowserVersion(String ua) {
    // Try to extract version from common patterns.
    final patterns = [
      RegExp(r'Chrome/(\d+[\.\d]*)'),
      RegExp(r'Firefox/(\d+[\.\d]*)'),
      RegExp(r'Safari/(\d+[\.\d]*)'),
      RegExp(r'Edg/(\d+[\.\d]*)'),
      RegExp(r'OPR/(\d+[\.\d]*)'),
    ];
    for (final p in patterns) {
      final match = p.firstMatch(ua);
      if (match != null) return match.group(1) ?? '';
    }
    return '';
  }

  void dispose() {
    stopConnectivityMonitoring();
  }
}
