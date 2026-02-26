import 'geo_utils.dart';

/// Tracks trips based on motion state transitions.
///
/// A "trip" starts when the device transitions to moving (`isMoving = true`)
/// and ends when it transitions to stationary (`isMoving = false`).
///
/// Collects:
/// - Start/stop location coordinates
/// - Waypoints (every accepted location during the trip)
/// - Total distance in meters (Haversine)
/// - Duration in seconds
///
/// Dispatches a trip event map when the trip ends via the [onTripEnd] callback.
///
/// **This is a pure Dart implementation** — no native code required. It runs
/// identically on Android, iOS, web, macOS, Linux, and Windows.
///
/// ```dart
/// final trip = TripManager();
/// trip.onTripEnd = (tripData) {
///   print('Trip ended: ${tripData["distance"]}m');
/// };
/// ```
class TripManager {
  /// Callback invoked when a trip ends with the full trip data map.
  ///
  /// The map contains:
  /// - `isMoving` (`bool`): Always `false` when trip ends.
  /// - `distance` (`double`): Total distance in meters.
  /// - `duration` (`double`): Duration in seconds.
  /// - `startLocation` (`Map`): `{latitude, longitude}` of trip start.
  /// - `stopLocation` (`Map`): `{latitude, longitude}` of trip end.
  /// - `waypoints` (`List<Map>`): Each `{latitude, longitude, timestamp}`.
  void Function(Map<String, Object?>)? onTripEnd;

  bool _tripActive = false;
  double? _startLat;
  double? _startLng;
  int _startTimeMs = 0;
  double _totalDistance = 0;
  double? _lastWaypointLat;
  double? _lastWaypointLng;
  final List<Map<String, Object?>> _waypoints = <Map<String, Object?>>[];

  /// Whether a trip is currently active.
  bool get isTripActive => _tripActive;

  /// Called on every motion state change.
  ///
  /// - [isMoving]: Whether the device is now moving.
  /// - [latitude]: Current latitude (if available).
  /// - [longitude]: Current longitude (if available).
  /// - [timestamp]: Current timestamp string or null.
  void onMotionStateChanged({
    required bool isMoving,
    double? latitude,
    double? longitude,
    Object? timestamp,
  }) {
    if (isMoving && !_tripActive) {
      _startTrip(latitude, longitude, timestamp);
    } else if (!isMoving && _tripActive) {
      _endTrip(latitude, longitude, timestamp);
    }
  }

  /// Called on every accepted tracking location to record waypoints.
  ///
  /// - [latitude]: Location latitude.
  /// - [longitude]: Location longitude.
  /// - [timestamp]: Location timestamp (String or int).
  void onLocationReceived({
    required double latitude,
    required double longitude,
    Object? timestamp,
  }) {
    if (!_tripActive) return;

    // Accumulate distance.
    if (_lastWaypointLat != null && _lastWaypointLng != null) {
      _totalDistance += GeoUtils.haversine(
        _lastWaypointLat!,
        _lastWaypointLng!,
        latitude,
        longitude,
      );
    }
    _lastWaypointLat = latitude;
    _lastWaypointLng = longitude;

    // Record waypoint (lightweight: coords + timestamp only).
    _waypoints.add(<String, Object?>{
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp,
    });
  }

  /// Reset the trip manager state.
  void reset() {
    _tripActive = false;
    _startLat = null;
    _startLng = null;
    _lastWaypointLat = null;
    _lastWaypointLng = null;
    _startTimeMs = 0;
    _totalDistance = 0;
    _waypoints.clear();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private
  // ─────────────────────────────────────────────────────────────────────────

  void _startTrip(double? lat, double? lng, Object? timestamp) {
    _tripActive = true;
    _startLat = lat;
    _startLng = lng;
    _lastWaypointLat = lat;
    _lastWaypointLng = lng;
    _startTimeMs = DateTime.now().millisecondsSinceEpoch;
    _totalDistance = 0;
    _waypoints.clear();

    // Record start as first waypoint.
    if (lat != null && lng != null) {
      _waypoints.add(<String, Object?>{
        'latitude': lat,
        'longitude': lng,
        'timestamp': timestamp,
      });
    }
  }

  void _endTrip(double? lat, double? lng, Object? timestamp) {
    _tripActive = false;

    // Add final distance segment.
    if (lat != null &&
        lng != null &&
        _lastWaypointLat != null &&
        _lastWaypointLng != null) {
      _totalDistance += GeoUtils.haversine(
        _lastWaypointLat!,
        _lastWaypointLng!,
        lat,
        lng,
      );
      _waypoints.add(<String, Object?>{
        'latitude': lat,
        'longitude': lng,
        'timestamp': timestamp,
      });
    }

    final durationMs = DateTime.now().millisecondsSinceEpoch - _startTimeMs;
    final durationSeconds = durationMs / 1000.0;

    final startMap = <String, Object?>{
      // ignore: use_null_aware_elements
      if (_startLat != null) 'latitude': _startLat,
      // ignore: use_null_aware_elements
      if (_startLng != null) 'longitude': _startLng,
    };

    final stopMap = <String, Object?>{
      // ignore: use_null_aware_elements
      if (lat != null) 'latitude': lat,
      // ignore: use_null_aware_elements
      if (lng != null) 'longitude': lng,
    };

    final tripData = <String, Object?>{
      'isMoving': false,
      'distance': _totalDistance,
      'duration': durationSeconds,
      'startLocation': startMap,
      'stopLocation': stopMap,
      'waypoints': List<Map<String, Object?>>.of(_waypoints),
    };

    onTripEnd?.call(tripData);

    // Clean up.
    _startLat = null;
    _startLng = null;
    _lastWaypointLat = null;
    _lastWaypointLng = null;
    _startTimeMs = 0;
    _totalDistance = 0;
    _waypoints.clear();
  }
}
