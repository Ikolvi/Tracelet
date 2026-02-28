import 'dart:async';
import 'dart:js_interop';

import 'package:tracelet_platform_interface/tracelet_platform_interface.dart'
    show GeoUtils;
import 'package:web/web.dart' as web;

import 'web_event_dispatcher.dart';
import 'web_geofence_engine.dart';
import 'web_utils.dart';

/// Wraps the browser Geolocation API for Tracelet.
///
/// Provides continuous tracking via `watchPosition`, one-shot fixes via
/// `getCurrentPosition`, and odometer computation. All operations are
/// **foreground-only** — the Web Geolocation API does not function in
/// background tabs or Service Workers.
class WebLocationEngine {
  WebLocationEngine(this._events, this._geofenceEngine);

  final WebEventDispatcher _events;
  final WebGeofenceEngine _geofenceEngine;

  /// Last known location map (cached from most recent fix).
  Map<String, Object?>? _lastLocation;

  /// Current odometer value in meters.
  double _odometer = 0.0;

  /// Whether tracking is currently active.
  bool _isTracking = false;

  /// Whether the device is considered "moving".
  bool _isMoving = false;

  /// Browser watch ID for continuous tracking (from `navigator.geolocation.watchPosition`).
  int? _browserWatchId;

  /// Watch IDs for `watchPosition()` API calls — maps our internal ID → active.
  int _nextWatchId = 1;
  final Map<int, bool> _activeWatches = <int, bool>{};

  /// Heartbeat timer.
  Timer? _heartbeatTimer;

  /// Config values (set via ready/setConfig).
  int _desiredAccuracy = 0; // 0=high
  double _distanceFilter = 10.0;
  double _stationaryRadius = 25.0;
  int _heartbeatInterval = 0; // 0 = disabled
  int _stopTimeout = 5; // minutes

  /// Timer for detecting stop after no movement.
  Timer? _stopTimer;

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------

  void applyConfig(Map<String, Object?> config) {
    final geo = config['geo'];
    if (geo is Map) {
      final geoMap = Map<String, Object?>.from(geo);
      _desiredAccuracy =
          (geoMap['desiredAccuracy'] as int?) ?? _desiredAccuracy;
      _distanceFilter =
          (geoMap['distanceFilter'] as num?)?.toDouble() ?? _distanceFilter;
      _stationaryRadius =
          (geoMap['stationaryRadius'] as num?)?.toDouble() ?? _stationaryRadius;
    }
    final app = config['app'];
    if (app is Map) {
      final appMap = Map<String, Object?>.from(app);
      _heartbeatInterval =
          (appMap['heartbeatInterval'] as int?) ?? _heartbeatInterval;
    }
    final motion = config['motion'];
    if (motion is Map) {
      final motionMap = Map<String, Object?>.from(motion);
      _stopTimeout = (motionMap['stopTimeout'] as int?) ?? _stopTimeout;
    }
  }

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  bool get isTracking => _isTracking;
  bool get isMoving => _isMoving;
  double get odometer => _odometer;
  Map<String, Object?>? get lastLocation => _lastLocation;

  // ---------------------------------------------------------------------------
  // One-shot position
  // ---------------------------------------------------------------------------

  Future<Map<String, Object?>> getCurrentPosition(
    Map<String, Object?> options,
  ) {
    final accuracy = options['desiredAccuracy'] as int? ?? _desiredAccuracy;
    final timeout = options['timeout'] as int? ?? 30;
    final maximumAge = options['maximumAge'] as int? ?? 5000;
    final highAccuracy = accuracy <= 1;

    return _browserGetPosition(
      enableHighAccuracy: highAccuracy,
      timeoutMs: timeout * 1000,
      maximumAgeMs: maximumAge,
    ).catchError((Object error) {
      // Fallback: if high-accuracy request timed out, retry without it.
      // Desktop browsers often lack GPS hardware, so network-only is the
      // only viable provider.
      if (!highAccuracy) throw error;
      _events.log(
        'warn',
        '[Tracelet Web] High-accuracy position timed out, retrying with low accuracy',
      );
      return _browserGetPosition(
        enableHighAccuracy: false,
        timeoutMs: timeout * 1000,
        maximumAgeMs: maximumAge,
      );
    });
  }

  /// Low-level wrapper around the browser Geolocation `getCurrentPosition`.
  Future<Map<String, Object?>> _browserGetPosition({
    required bool enableHighAccuracy,
    required int timeoutMs,
    required int maximumAgeMs,
  }) {
    final completer = Completer<Map<String, Object?>>();

    final posOptions = web.PositionOptions(
      enableHighAccuracy: enableHighAccuracy,
      timeout: timeoutMs,
      maximumAge: maximumAgeMs,
    );

    web.window.navigator.geolocation.getCurrentPosition(
      ((web.GeolocationPosition pos) {
        final locationMap = _positionToMap(pos);
        _updateLastLocation(locationMap);
        completer.complete(locationMap);
      }).toJS,
      ((web.GeolocationPositionError err) {
        completer.completeError(
          StateError('Geolocation error ${err.code}: ${err.message}'),
        );
      }).toJS,
      posOptions,
    );

    return completer.future;
  }

  /// Returns cached last location or empty map.
  Map<String, Object?> getLastKnownLocation() {
    return _lastLocation ?? const <String, Object?>{};
  }

  // ---------------------------------------------------------------------------
  // Continuous tracking (start/stop)
  // ---------------------------------------------------------------------------

  void startTracking() {
    if (_isTracking) return;
    _isTracking = true;
    _isMoving = true;

    _startBrowserWatch();
    _startHeartbeat();
  }

  void stopTracking() {
    if (!_isTracking) return;
    _isTracking = false;
    _isMoving = false;
    _fallbackWatch = false;

    _stopBrowserWatch();
    _stopHeartbeat();
    _stopTimer?.cancel();
    _stopTimer = null;
  }

  // ---------------------------------------------------------------------------
  // watchPosition / stopWatchPosition (user-facing API)
  // ---------------------------------------------------------------------------

  int addWatch(Map<String, Object?> options) {
    final id = _nextWatchId++;
    _activeWatches[id] = true;

    // If not already watching from browser, start.
    if (_browserWatchId == null) {
      _startBrowserWatch();
    }

    return id;
  }

  bool removeWatch(int watchId) {
    final removed = _activeWatches.remove(watchId) != null;

    // If no more watches and not tracking, stop browser watch.
    if (_activeWatches.isEmpty && !_isTracking) {
      _stopBrowserWatch();
    }

    return removed;
  }

  // ---------------------------------------------------------------------------
  // Pace / odometer
  // ---------------------------------------------------------------------------

  bool changePace(bool isMoving) {
    _isMoving = isMoving;
    if (isMoving) {
      _stopTimer?.cancel();
      _stopTimer = null;
    }
    if (_lastLocation != null) {
      _events.emitMotionChange(_lastLocation!);
    }
    return true;
  }

  Map<String, Object?> setOdometer(double value) {
    _odometer = value;
    return _lastLocation ?? _emptyLocation();
  }

  // ---------------------------------------------------------------------------
  // Browser Geolocation watch
  // ---------------------------------------------------------------------------

  void _startBrowserWatch() {
    if (_browserWatchId != null) return;

    // Use generous maximumAge and timeout for continuous tracking.
    // Desktop browsers often rely on network-based location which can be
    // slow; setting maximumAge > 0 allows cached fixes to come through
    // quickly while the browser fetches a fresh one.
    final options = web.PositionOptions(
      enableHighAccuracy: _desiredAccuracy <= 1,
      timeout: 60000,
      maximumAge: 5000,
    );

    _browserWatchId = web.window.navigator.geolocation.watchPosition(
      ((web.GeolocationPosition pos) => _onBrowserPosition(pos)).toJS,
      ((web.GeolocationPositionError err) {
        _onBrowserError(err);
        // If high accuracy timed out, restart watch without it.
        if (err.code == 3 && _desiredAccuracy <= 1 && !_fallbackWatch) {
          _fallbackWatch = true;
          _stopBrowserWatch();
          _startFallbackWatch();
        }
      }).toJS,
      options,
    );
  }

  /// Whether we already fell back to low-accuracy watching.
  bool _fallbackWatch = false;

  void _startFallbackWatch() {
    if (_browserWatchId != null) return;
    _events.log(
      'warn',
      '[Tracelet Web] High-accuracy watch timed out, falling back to low accuracy',
    );
    final options = web.PositionOptions(
      enableHighAccuracy: false,
      timeout: 60000,
      maximumAge: 5000,
    );
    _browserWatchId = web.window.navigator.geolocation.watchPosition(
      ((web.GeolocationPosition pos) => _onBrowserPosition(pos)).toJS,
      ((web.GeolocationPositionError err) => _onBrowserError(err)).toJS,
      options,
    );
  }

  void _stopBrowserWatch() {
    final id = _browserWatchId;
    if (id != null) {
      web.window.navigator.geolocation.clearWatch(id);
      _browserWatchId = null;
    }
  }

  void _onBrowserPosition(web.GeolocationPosition pos) {
    final locationMap = _positionToMap(pos);

    final prevLat = _lastLocation?['coords'] is Map
        ? (_lastLocation!['coords'] as Map)['latitude'] as double?
        : null;
    final prevLon = _lastLocation?['coords'] is Map
        ? (_lastLocation!['coords'] as Map)['longitude'] as double?
        : null;
    final curLat =
        (locationMap['coords'] as Map<String, Object?>)['latitude'] as double;
    final curLon =
        (locationMap['coords'] as Map<String, Object?>)['longitude'] as double;

    double distance = 0;
    if (prevLat != null && prevLon != null) {
      distance = GeoUtils.haversine(prevLat, prevLon, curLat, curLon);
    }

    // Update odometer.
    if (prevLat != null) {
      _odometer += distance;
    }
    locationMap['odometer'] = _odometer;

    _updateLastLocation(locationMap);

    // Motion detection.
    if (!_isMoving && distance > _stationaryRadius) {
      _isMoving = true;
      _events.emitMotionChange(locationMap);
    }

    // Reset stop timer on movement.
    if (_isMoving) {
      _stopTimer?.cancel();
      _stopTimer = Timer(Duration(minutes: _stopTimeout), () {
        if (_isMoving) {
          _isMoving = false;
          if (_lastLocation != null) {
            _events.emitMotionChange(_lastLocation!);
          }
        }
      });
    }

    // Emit location event — no distance filtering here; the shared Dart
    // LocationProcessor in tracelet.dart handles distance, elasticity,
    // accuracy and speed filtering for all platforms.
    if (_isTracking) {
      _events.emitLocation(locationMap);
    }

    // Emit to watchPosition listeners (unfiltered).
    if (_activeWatches.isNotEmpty) {
      _events.emitWatchPosition(locationMap);
    }

    // Check geofences.
    _geofenceEngine.checkGeofences(curLat, curLon, locationMap);
  }

  void _onBrowserError(web.GeolocationPositionError error) {
    // Log but don't crash — browser may temporarily lose GPS.
    _events.log('error', 'Geolocation error ${error.code}: ${error.message}');
  }

  // ---------------------------------------------------------------------------
  // Heartbeat
  // ---------------------------------------------------------------------------

  void _startHeartbeat() {
    _stopHeartbeat();
    if (_heartbeatInterval <= 0) return;

    _heartbeatTimer = Timer.periodic(Duration(seconds: _heartbeatInterval), (
      _,
    ) {
      final loc = _lastLocation ?? _emptyLocation();
      _events.emitHeartbeat(loc);
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _updateLastLocation(Map<String, Object?> location) {
    location['isMoving'] = _isMoving;
    location['odometer'] = _odometer;
    _lastLocation = location;
  }

  Map<String, Object?> _positionToMap(web.GeolocationPosition pos) {
    final coords = pos.coords;
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      pos.timestamp.toInt(),
    ).toIso8601String();

    return <String, Object?>{
      'coords': <String, Object?>{
        'latitude': coords.latitude.toDouble(),
        'longitude': coords.longitude.toDouble(),
        'altitude': coords.altitude?.toDouble(),
        'speed': coords.speed?.toDouble(),
        'heading': coords.heading?.toDouble(),
        'accuracy': coords.accuracy.toDouble(),
        'speedAccuracy': -1.0,
        'headingAccuracy': -1.0,
        'altitudeAccuracy': coords.altitudeAccuracy?.toDouble(),
        'floor': null,
      },
      'timestamp': timestamp,
      'isMoving': _isMoving,
      'uuid': generateUuid(),
      'odometer': _odometer,
      'mock': false, // Web Geolocation API has no mock detection capability.
      'activity': <String, Object?>{'type': 'unknown', 'confidence': 'medium'},
      'battery': <String, Object?>{'level': -1.0, 'isCharging': false},
      'extras': <String, Object?>{},
      'event': null,
    };
  }

  Map<String, Object?> _emptyLocation() {
    return <String, Object?>{
      'coords': <String, Object?>{
        'latitude': 0.0,
        'longitude': 0.0,
        'altitude': null,
        'speed': null,
        'heading': null,
        'accuracy': -1.0,
        'speedAccuracy': -1.0,
        'headingAccuracy': -1.0,
        'altitudeAccuracy': null,
        'floor': null,
      },
      'timestamp': DateTime.now().toIso8601String(),
      'isMoving': false,
      'uuid': generateUuid(),
      'odometer': _odometer,
      'mock': false,
      'activity': <String, Object?>{'type': 'unknown', 'confidence': 'medium'},
      'battery': <String, Object?>{'level': -1.0, 'isCharging': false},
      'extras': <String, Object?>{},
      'event': null,
    };
  }

  /// Release all resources.
  void dispose() {
    stopTracking();
    for (final id in _activeWatches.keys.toList()) {
      removeWatch(id);
    }
  }
}
