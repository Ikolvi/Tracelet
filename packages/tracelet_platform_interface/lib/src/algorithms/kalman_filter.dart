import 'dart:math' as math;

/// 2D Extended Kalman Filter for GPS coordinate smoothing.
///
/// Uses latitude/longitude in meters (via equirectangular projection) with
/// the device-reported GPS accuracy as measurement noise. Produces smoother
/// tracks, better speed estimates, and eliminates GPS jitter.
///
/// The filter maintains a 4-element state vector: `[x, y, vx, vy]`
/// (position + velocity in local meter coordinates). On each GPS fix,
/// it predicts the next state using elapsed time, then corrects using
/// the measured position weighted by the GPS accuracy.
///
/// **This is a pure Dart implementation** — no native code required. It runs
/// identically on Android, iOS, web, macOS, Linux, and Windows.
///
/// ```dart
/// final kalman = KalmanLocationFilter();
/// final (lat, lng) = kalman.process(
///   latitude: 37.4219983,
///   longitude: -122.084,
///   accuracy: 16.0,
///   timestampMs: DateTime.now().millisecondsSinceEpoch,
/// );
/// ```
class KalmanLocationFilter {
  // State vector: [x, y, vx, vy] in meters from an arbitrary origin.
  double _x = 0; // position x (meters, east)
  double _y = 0; // position y (meters, north)
  double _vx = 0; // velocity x (m/s)
  double _vy = 0; // velocity y (m/s)

  // 4×4 covariance matrix stored as a flat 16-element list.
  //
  // Layout:
  // [P00, P01, P02, P03,
  //  P10, P11, P12, P13,
  //  P20, P21, P22, P23,
  //  P30, P31, P32, P33]
  List<double> _p = List<double>.filled(16, 0);

  /// Process noise in m/s² — models acceleration uncertainty.
  static const double _processNoise = 3.0;

  // Conversion factors.
  double _originLat = 0;
  double _originLng = 0;
  double _metersPerDegreeLat = 111320;
  double _metersPerDegreeLng = 111320;

  int _lastTimestampMs = 0;
  bool _initialized = false;

  /// Whether the filter has been initialized with at least one measurement.
  bool get isInitialized => _initialized;

  /// The current estimated speed in m/s derived from the state vector.
  double get estimatedSpeed => math.sqrt(_vx * _vx + _vy * _vy);

  /// Process a new GPS measurement and return the smoothed coordinates.
  ///
  /// - [latitude]: Raw GPS latitude in degrees.
  /// - [longitude]: Raw GPS longitude in degrees.
  /// - [accuracy]: GPS horizontal accuracy in meters.
  /// - [timestampMs]: Location timestamp in **milliseconds** since epoch.
  ///
  /// Returns a record `(double latitude, double longitude)` of the smoothed
  /// position in degrees.
  ({double latitude, double longitude}) process({
    required double latitude,
    required double longitude,
    required double accuracy,
    required int timestampMs,
  }) {
    final measAccuracy = accuracy.clamp(1.0, double.infinity);

    if (!_initialized) {
      _initialize(latitude, longitude, measAccuracy, timestampMs);
      return (latitude: latitude, longitude: longitude);
    }

    final dt = (timestampMs - _lastTimestampMs) / 1000.0; // seconds
    if (dt <= 0) {
      return _toLatLng();
    }
    _lastTimestampMs = timestampMs;

    // Convert measurement to local meters.
    final mx = (longitude - _originLng) * _metersPerDegreeLng;
    final my = (latitude - _originLat) * _metersPerDegreeLat;

    // Predict step.
    _predict(dt);

    // Update step.
    _update(mx, my, measAccuracy);

    return _toLatLng();
  }

  /// Reset the filter state. Call when tracking restarts.
  void reset() {
    _initialized = false;
    _lastTimestampMs = 0;
    _x = 0;
    _y = 0;
    _vx = 0;
    _vy = 0;
    _p = List<double>.filled(16, 0);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Private implementation
  // ──────────────────────────────────────────────────────────────────────────

  void _initialize(double lat, double lng, double accuracy, int ts) {
    _originLat = lat;
    _originLng = lng;
    _metersPerDegreeLat = 111320;
    _metersPerDegreeLng = 111320 * math.cos(lat * math.pi / 180.0);

    _x = 0;
    _y = 0;
    _vx = 0;
    _vy = 0;
    _lastTimestampMs = ts;
    _initialized = true;

    // Initialize covariance: high uncertainty in position, very high in velocity.
    _p = List<double>.filled(16, 0);
    _p[0] = accuracy * accuracy; // P[0,0] = position x variance
    _p[5] = accuracy * accuracy; // P[1,1] = position y variance
    _p[10] = 100.0; // P[2,2] = velocity x variance
    _p[15] = 100.0; // P[3,3] = velocity y variance
  }

  /// Predict step: state = F × state, P = F × P × Fᵀ + Q
  ///
  /// ```
  /// F = [1, 0, dt, 0]
  ///     [0, 1, 0,  dt]
  ///     [0, 0, 1,  0 ]
  ///     [0, 0, 0,  1 ]
  /// ```
  void _predict(double dt) {
    // State prediction: x += vx*dt, y += vy*dt (constant-velocity model).
    _x += _vx * dt;
    _y += _vy * dt;

    // Process noise covariance Q components.
    final dt2 = dt * dt;
    final dt3 = dt2 * dt / 2.0;
    final dt4 = dt2 * dt2 / 4.0;
    final q = _processNoise * _processNoise;

    // Compute F × P × Fᵀ + Q directly using the constant-velocity structure.
    final p = List<double>.of(_p);
    _p[0] = p[0] + dt * (p[2] + p[8]) + dt2 * p[10] + q * dt4;
    _p[1] = p[1] + dt * (p[3] + p[9]) + dt2 * p[11];
    _p[2] = p[2] + dt * p[10] + q * dt3;
    _p[3] = p[3] + dt * p[11];
    _p[4] = p[4] + dt * (p[6] + p[12]) + dt2 * p[14];
    _p[5] = p[5] + dt * (p[7] + p[13]) + dt2 * p[15] + q * dt4;
    _p[6] = p[6] + dt * p[14];
    _p[7] = p[7] + dt * p[15] + q * dt3;
    _p[8] = p[8] + dt * p[10] + q * dt3;
    _p[9] = p[9] + dt * p[11];
    _p[10] = p[10] + q * dt2;
    _p[11] = p[11];
    _p[12] = p[12] + dt * p[14];
    _p[13] = p[13] + dt * p[15] + q * dt3;
    _p[14] = p[14];
    _p[15] = p[15] + q * dt2;
  }

  /// Update step: correct state using the GPS measurement.
  ///
  /// H = [[1, 0, 0, 0], [0, 1, 0, 0]]  (we observe position only)
  void _update(double mx, double my, double accuracy) {
    final r = accuracy * accuracy; // measurement noise variance

    // Innovation (measurement residual).
    final dx = mx - _x;
    final dy = my - _y;

    // Innovation covariance: S = H × P × Hᵀ + R.
    final s00 = _p[0] + r;
    final s01 = _p[1];
    final s10 = _p[4];
    final s11 = _p[5] + r;

    // Invert 2×2 S matrix.
    final det = s00 * s11 - s01 * s10;
    if (det == 0) return; // singular — skip update
    final invDet = 1.0 / det;
    final si00 = s11 * invDet;
    final si01 = -s01 * invDet;
    final si10 = -s10 * invDet;
    final si11 = s00 * invDet;

    // Kalman gain: K = P × Hᵀ × S⁻¹  (4×2 matrix).
    final k00 = _p[0] * si00 + _p[1] * si10;
    final k01 = _p[0] * si01 + _p[1] * si11;
    final k10 = _p[4] * si00 + _p[5] * si10;
    final k11 = _p[4] * si01 + _p[5] * si11;
    final k20 = _p[8] * si00 + _p[9] * si10;
    final k21 = _p[8] * si01 + _p[9] * si11;
    final k30 = _p[12] * si00 + _p[13] * si10;
    final k31 = _p[12] * si01 + _p[13] * si11;

    // State correction.
    _x += k00 * dx + k01 * dy;
    _y += k10 * dx + k11 * dy;
    _vx += k20 * dx + k21 * dy;
    _vy += k30 * dx + k31 * dy;

    // Covariance correction: P = (I − K × H) × P.
    final p = List<double>.of(_p);
    _p[0] = p[0] - k00 * p[0] - k01 * p[4];
    _p[1] = p[1] - k00 * p[1] - k01 * p[5];
    _p[2] = p[2] - k00 * p[2] - k01 * p[6];
    _p[3] = p[3] - k00 * p[3] - k01 * p[7];
    _p[4] = p[4] - k10 * p[0] - k11 * p[4];
    _p[5] = p[5] - k10 * p[1] - k11 * p[5];
    _p[6] = p[6] - k10 * p[2] - k11 * p[6];
    _p[7] = p[7] - k10 * p[3] - k11 * p[7];
    _p[8] = p[8] - k20 * p[0] - k21 * p[4];
    _p[9] = p[9] - k20 * p[1] - k21 * p[5];
    _p[10] = p[10] - k20 * p[2] - k21 * p[6];
    _p[11] = p[11] - k20 * p[3] - k21 * p[7];
    _p[12] = p[12] - k30 * p[0] - k31 * p[4];
    _p[13] = p[13] - k30 * p[1] - k31 * p[5];
    _p[14] = p[14] - k30 * p[2] - k31 * p[6];
    _p[15] = p[15] - k30 * p[3] - k31 * p[7];
  }

  /// Convert current state back to lat/lng degrees.
  ({double latitude, double longitude}) _toLatLng() {
    return (
      latitude: _originLat + _y / _metersPerDegreeLat,
      longitude: _originLng + _x / _metersPerDegreeLng,
    );
  }
}
