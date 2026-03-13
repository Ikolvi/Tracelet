import 'geo_utils.dart';

/// Default CO₂ emission factors (gCO₂/km) based on EU EEA 2024 averages.
const Map<String, double> kDefaultEmissionFactors = <String, double>{
  'in_vehicle': 192.0, // EU average new car
  'on_bicycle': 0.0,
  'walking': 0.0,
  'running': 0.0,
  'on_foot': 0.0,
  'bus': 89.0, // EU urban bus average
  'train': 41.0, // EU rail average
  'unknown': 96.0, // half of car as conservative estimate
};

/// Per-trip carbon summary emitted when a trip ends.
class TripCarbonSummary {
  const TripCarbonSummary({
    required this.totalCarbonGrams,
    required this.totalDistanceMeters,
    required this.carbonByMode,
    required this.distanceByMode,
    required this.dominantMode,
  });

  /// Total CO₂ emitted during the trip (grams).
  final double totalCarbonGrams;

  /// Total distance travelled (meters).
  final double totalDistanceMeters;

  /// CO₂ grams broken down by transport mode.
  final Map<String, double> carbonByMode;

  /// Distance in meters broken down by transport mode.
  final Map<String, double> distanceByMode;

  /// The transport mode that covered the most distance.
  final String dominantMode;

  Map<String, Object?> toMap() => <String, Object?>{
    'totalCarbonGrams': totalCarbonGrams,
    'totalDistanceMeters': totalDistanceMeters,
    'carbonByMode': carbonByMode,
    'distanceByMode': distanceByMode,
    'dominantMode': dominantMode,
  };
}

/// Accumulates distance per transport mode during a trip and computes
/// CO₂ emissions using configurable emission factors.
///
/// Feed location updates with the current activity type via
/// [onLocationReceived]. Call [startTrip] when motion begins and
/// [endTrip] when it stops — the latter returns a [TripCarbonSummary].
///
/// ```dart
/// final carbon = CarbonEstimator();
/// carbon.startTrip();
/// carbon.onLocationReceived(37.77, -122.42, 'walking');
/// carbon.onLocationReceived(37.78, -122.43, 'walking');
/// final summary = carbon.endTrip();
/// print('${summary.totalCarbonGrams} g CO₂');
/// ```
class CarbonEstimator {
  /// Create a carbon estimator with optional custom emission factors.
  CarbonEstimator({Map<String, double>? emissionFactors})
    : _factors = emissionFactors ?? kDefaultEmissionFactors;

  final Map<String, double> _factors;

  // Active trip state.
  bool _active = false;
  double? _lastLat;
  double? _lastLng;
  String _currentMode = 'unknown';
  final Map<String, double> _distanceByMode = <String, double>{};

  // Cumulative state (survives across trips until [resetCumulative]).
  double _cumulativeCarbonGrams = 0.0;
  int _cumulativeTrips = 0;
  final Map<String, double> _cumulativeCarbonByMode = <String, double>{};
  final Map<String, double> _cumulativeDistanceByMode = <String, double>{};

  /// Whether a trip is currently being tracked.
  bool get isActive => _active;

  /// Total carbon emitted across all trips (grams).
  double get cumulativeCarbonGrams => _cumulativeCarbonGrams;

  /// Total trips tracked since last [resetCumulative].
  int get cumulativeTrips => _cumulativeTrips;

  /// Begin a new trip. Resets per-trip accumulators.
  void startTrip() {
    _active = true;
    _lastLat = null;
    _lastLng = null;
    _currentMode = 'unknown';
    _distanceByMode.clear();
  }

  /// Update the current transport mode (from activity recognition).
  void setActivity(String activityType) {
    _currentMode = activityType;
  }

  /// Feed a location sample. Distance is accumulated under the current mode.
  void onLocationReceived(double lat, double lng) {
    if (!_active) return;

    if (_lastLat != null && _lastLng != null) {
      final d = GeoUtils.haversine(_lastLat!, _lastLng!, lat, lng);
      _distanceByMode[_currentMode] =
          (_distanceByMode[_currentMode] ?? 0.0) + d;
    }
    _lastLat = lat;
    _lastLng = lng;
  }

  /// End the current trip and return the carbon summary.
  ///
  /// Returns `null` if no trip was active.
  TripCarbonSummary? endTrip() {
    if (!_active) return null;
    _active = false;

    final carbonByMode = <String, double>{};
    double totalCarbon = 0.0;
    double totalDistance = 0.0;

    for (final entry in _distanceByMode.entries) {
      final mode = entry.key;
      final meters = entry.value;
      totalDistance += meters;

      final factor = _factors[mode] ?? _factors['unknown'] ?? 0.0;
      final grams = meters / 1000.0 * factor;
      carbonByMode[mode] = grams;
      totalCarbon += grams;

      // Accumulate into cumulative totals.
      _cumulativeCarbonByMode[mode] =
          (_cumulativeCarbonByMode[mode] ?? 0.0) + grams;
      _cumulativeDistanceByMode[mode] =
          (_cumulativeDistanceByMode[mode] ?? 0.0) + meters;
    }

    _cumulativeCarbonGrams += totalCarbon;
    _cumulativeTrips++;

    // Dominant mode = mode with highest distance.
    String dominantMode = 'unknown';
    double maxDist = 0.0;
    for (final entry in _distanceByMode.entries) {
      if (entry.value > maxDist) {
        maxDist = entry.value;
        dominantMode = entry.key;
      }
    }

    final tripDistanceByMode = Map<String, double>.from(_distanceByMode);

    _distanceByMode.clear();
    _lastLat = null;
    _lastLng = null;

    return TripCarbonSummary(
      totalCarbonGrams: totalCarbon,
      totalDistanceMeters: totalDistance,
      carbonByMode: carbonByMode,
      distanceByMode: tripDistanceByMode,
      dominantMode: dominantMode,
    );
  }

  /// Get a cumulative carbon report across all tracked trips.
  Map<String, Object?> getCumulativeReport() => <String, Object?>{
    'totalCarbonGrams': _cumulativeCarbonGrams,
    'totalTrips': _cumulativeTrips,
    'carbonByMode': Map<String, double>.from(_cumulativeCarbonByMode),
    'distanceByMode': Map<String, double>.from(_cumulativeDistanceByMode),
  };

  /// Reset cumulative counters.
  void resetCumulative() {
    _cumulativeCarbonGrams = 0.0;
    _cumulativeTrips = 0;
    _cumulativeCarbonByMode.clear();
    _cumulativeDistanceByMode.clear();
  }

  /// Reset everything (trip + cumulative).
  void reset() {
    _active = false;
    _lastLat = null;
    _lastLng = null;
    _currentMode = 'unknown';
    _distanceByMode.clear();
    resetCumulative();
  }
}
