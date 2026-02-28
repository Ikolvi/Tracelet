import 'geo_utils.dart';

/// Result of processing a location through [LocationProcessor].
///
/// When [accepted] is `true`, the location passed all filters and should be
/// delivered to the user. When `false`, the location was rejected and the
/// [reason] and optional [errorMessage] describe why.
class LocationProcessorResult {
  const LocationProcessorResult._({
    required this.accepted,
    this.effectiveSpeed = 0,
    this.odometerDelta = 0,
    this.distance = 0,
    this.reason,
    this.errorMessage,
    this.isError = false,
  });

  /// The location passed all filters.
  factory LocationProcessorResult.accept({
    required double effectiveSpeed,
    required double odometerDelta,
    required double distance,
  }) => LocationProcessorResult._(
    accepted: true,
    effectiveSpeed: effectiveSpeed,
    odometerDelta: odometerDelta,
    distance: distance,
  );

  /// The location was silently filtered (not delivered to the user).
  factory LocationProcessorResult.filtered(String reason) =>
      LocationProcessorResult._(accepted: false, reason: reason);

  /// The location was filtered and an error event should be dispatched.
  factory LocationProcessorResult.error(String reason, String message) =>
      LocationProcessorResult._(
        accepted: false,
        reason: reason,
        errorMessage: message,
        isError: true,
      );

  /// Whether the location was accepted by all filters.
  final bool accepted;

  /// Computed effective speed in m/s (platform speed or distance/time).
  final double effectiveSpeed;

  /// Distance (meters) to add to the odometer for this location.
  final double odometerDelta;

  /// Distance (meters) from the previous accepted location.
  final double distance;

  /// Filter name that rejected the location (e.g. `DISTANCE_FILTER`).
  final String? reason;

  /// Human-readable error message for `discard`-policy rejections.
  final String? errorMessage;

  /// Whether the rejection should dispatch an error event to the user.
  final bool isError;

  @override
  String toString() => accepted
      ? 'LocationProcessorResult.accept(speed=$effectiveSpeed, '
            'odometerDelta=$odometerDelta, distance=$distance)'
      : 'LocationProcessorResult.${isError ? "error" : "filtered"}'
            '(reason=$reason${errorMessage != null ? ', msg=$errorMessage' : ''})';
}

/// Pure-Dart location filtering engine.
///
/// Replaces the filtering logic previously duplicated in native Kotlin
/// (`LocationEngine.onLocationReceived`) and Swift
/// (`LocationEngine.didUpdateLocations`).
///
/// **Filters applied (in order):**
/// 1. **Elasticity** — dynamically scales `distanceFilter` based on speed.
/// 2. **Distance filter** — rejects locations closer than `effectiveDistance`.
/// 3. **Accuracy filter** — rejects locations exceeding
///    `trackingAccuracyThreshold` according to the `filterPolicy`.
/// 4. **Speed filter** — rejects impossible jumps exceeding `maxImpliedSpeed`.
/// 5. **Odometer gating** — only adds distance to the odometer when accuracy
///    is within `odometerAccuracyThreshold`.
///
/// **This is a pure Dart implementation** — no native code required. It runs
/// identically on Android, iOS, web, macOS, Linux, and Windows.
///
/// ```dart
/// final processor = LocationProcessor(distanceFilter: 10);
/// final result = processor.process(
///   latitude: 37.422,
///   longitude: -122.084,
///   accuracy: 16.0,
///   speed: 1.5,
///   timestampMs: DateTime.now().millisecondsSinceEpoch,
/// );
/// if (result.accepted) {
///   print('Accepted, speed=${result.effectiveSpeed}');
/// }
/// ```
class LocationProcessor {
  LocationProcessor({
    this.distanceFilter = 10.0,
    this.disableElasticity = false,
    this.elasticityMultiplier = 1.0,
    this.trackingAccuracyThreshold = 0,
    this.filterPolicy = 0,
    this.maxImpliedSpeed = 0,
    this.odometerAccuracyThreshold = 0,
    this.rejectMockLocations = false,
    this.mockDetectionLevel = 1,
  });

  /// Base distance filter in meters.
  final double distanceFilter;

  /// When `true`, elasticity scaling is disabled and [distanceFilter] is used
  /// as-is regardless of speed.
  final bool disableElasticity;

  /// Multiplier applied to the elasticity-scaled distance.
  /// Values < 1 make the filter more aggressive, > 1 more relaxed.
  final double elasticityMultiplier;

  /// Maximum acceptable GPS accuracy in meters. Locations above this
  /// threshold are handled according to [filterPolicy].
  /// `0` disables the accuracy filter.
  final int trackingAccuracyThreshold;

  /// How to handle locations that exceed [trackingAccuracyThreshold].
  ///
  /// - `0` (adjust): Skip the location but don't fire an error event.
  ///   Only applies when there is a previous location; the very first
  ///   location is always accepted.
  /// - `1` (ignore): Silently drop the location.
  /// - `2` (discard): Drop the location and fire an error event.
  final int filterPolicy;

  /// Maximum plausible speed in m/s. If the implied speed between two
  /// consecutive locations exceeds this, the location is rejected.
  /// `0` disables the speed filter.
  final int maxImpliedSpeed;

  /// Maximum GPS accuracy (meters) for the distance to count towards the
  /// odometer. Locations with lower accuracy still pass through but don't
  /// add to the odometer. `0` disables the threshold (all count).
  final int odometerAccuracyThreshold;

  /// When `true`, locations flagged as mock/spoofed (`isMock == true`) are
  /// automatically rejected. The rejection behavior follows [filterPolicy]:
  /// - `0` / `1`: silent drop.
  /// - `2`: drop and fire an error event.
  final bool rejectMockLocations;

  /// Mock detection level.
  ///
  /// - `0` (disabled): No mock detection.
  /// - `1` (basic): Only platform-flag-based detection.
  /// - `2` (heuristic): Platform flags + native heuristics (satellite count,
  ///   elapsed realtime drift) + Dart-side timestamp monotonicity check.
  final int mockDetectionLevel;

  // ─────────────────────────────────────────────────────────────────────────
  // Internal state
  // ─────────────────────────────────────────────────────────────────────────

  double? _lastLatitude;
  double? _lastLongitude;
  int _lastTimestampMs = 0;

  /// Last computed effective speed in m/s.
  double lastEffectiveSpeed = 0;

  /// Whether [process] has been called at least once and accepted a location.
  bool get hasLastLocation => _lastLatitude != null;

  /// Process a new location and return the filter decision.
  ///
  /// - [latitude], [longitude]: GPS coordinates in degrees.
  /// - [accuracy]: Horizontal accuracy in meters.
  /// - [speed]: Platform-reported speed in m/s. Pass `-1` or `0` if
  ///   unavailable — a fallback speed will be computed from distance/time.
  /// - [timestampMs]: Location timestamp in milliseconds since epoch.
  LocationProcessorResult process({
    required double latitude,
    required double longitude,
    required double accuracy,
    required double speed,
    required int timestampMs,
    bool isMock = false,
  }) {
    // ── Mock location filter ──────────────────────────────────────────────
    if (rejectMockLocations && isMock) {
      if (filterPolicy == 2) {
        return LocationProcessorResult.error(
          'MOCK_LOCATION',
          'Location rejected: flagged as mock/spoofed by the platform',
        );
      }
      return LocationProcessorResult.filtered('MOCK_LOCATION');
    }

    // ── Timestamp monotonicity (heuristic level) ──────────────────────────
    // When mockDetectionLevel >= 2 and we have a previous timestamp, reject
    // locations whose timestamp goes backwards. Real GPS hardware never
    // produces decreasing timestamps; replayed / injected locations can.
    if (mockDetectionLevel >= 2 &&
        rejectMockLocations &&
        _lastTimestampMs > 0 &&
        timestampMs < _lastTimestampMs) {
      if (filterPolicy == 2) {
        return LocationProcessorResult.error(
          'MOCK_LOCATION_TIMESTAMP',
          'Location rejected: timestamp $timestampMs is before previous '
              '$_lastTimestampMs (non-monotonic — possible replay attack)',
        );
      }
      return LocationProcessorResult.filtered('MOCK_LOCATION_TIMESTAMP');
    }

    // ── Distance & speed computation ──────────────────────────────────────
    double distance = 0;
    double timeDelta = 0;

    if (_lastLatitude != null && _lastLongitude != null) {
      distance = GeoUtils.haversine(
        _lastLatitude!,
        _lastLongitude!,
        latitude,
        longitude,
      );
      timeDelta = (timestampMs - _lastTimestampMs) / 1000.0;
    }

    final computedSpeed = (distance > 0 && timeDelta > 0)
        ? distance / timeDelta
        : 0.0;
    final effectiveSpeed = (speed > 0) ? speed : computedSpeed;

    // ── Elasticity: scale distanceFilter by speed ─────────────────────────
    double effectiveDistance = distanceFilter;
    if (!disableElasticity && effectiveSpeed > 0) {
      final multiplier = elasticityMultiplier < 0.1
          ? 0.1
          : elasticityMultiplier;
      final speedFactor = (effectiveSpeed / 10.0).clamp(1.0, 10.0);
      effectiveDistance = distanceFilter * speedFactor * multiplier;
    }

    // ── Distance filter ───────────────────────────────────────────────────
    if (_lastLatitude != null && distance < effectiveDistance) {
      return LocationProcessorResult.filtered('DISTANCE_FILTER');
    }

    // ── Accuracy filter ───────────────────────────────────────────────────
    if (trackingAccuracyThreshold > 0 && accuracy > trackingAccuracyThreshold) {
      switch (filterPolicy) {
        case 2: // discard — fire error event
          return LocationProcessorResult.error(
            'ACCURACY_FILTER',
            'Location accuracy ${accuracy}m exceeds '
                'threshold ${trackingAccuracyThreshold}m',
          );
        case 1: // ignore — silent drop
          return LocationProcessorResult.filtered('ACCURACY_FILTER');
        default: // adjust — skip if we already have a reference location
          if (_lastLatitude != null) {
            return LocationProcessorResult.filtered('ACCURACY_FILTER');
          }
      }
    }

    // ── Speed filter ──────────────────────────────────────────────────────
    if (maxImpliedSpeed > 0 && _lastLatitude != null && timeDelta > 0) {
      final impliedSpeed = distance / timeDelta;
      if (impliedSpeed > maxImpliedSpeed) {
        if (filterPolicy == 2) {
          return LocationProcessorResult.error(
            'SPEED_FILTER',
            'Implied speed ${impliedSpeed.toStringAsFixed(1)}m/s exceeds '
                'max ${maxImpliedSpeed}m/s',
          );
        }
        return LocationProcessorResult.filtered('SPEED_FILTER');
      }
    }

    // ── Odometer gating ───────────────────────────────────────────────────
    double odometerDelta = 0;
    if (odometerAccuracyThreshold <= 0 ||
        accuracy <= odometerAccuracyThreshold) {
      odometerDelta = distance;
    }

    // ── Accept ────────────────────────────────────────────────────────────
    _lastLatitude = latitude;
    _lastLongitude = longitude;
    _lastTimestampMs = timestampMs;
    lastEffectiveSpeed = effectiveSpeed;

    return LocationProcessorResult.accept(
      effectiveSpeed: effectiveSpeed,
      odometerDelta: odometerDelta,
      distance: distance,
    );
  }

  /// Reset all internal state. Call when tracking restarts.
  void reset() {
    _lastLatitude = null;
    _lastLongitude = null;
    _lastTimestampMs = 0;
    lastEffectiveSpeed = 0;
  }

  /// Create a new [LocationProcessor] with updated configuration.
  ///
  /// Preserves internal state (last position, timestamp) so filtering
  /// continuity is maintained across config changes.
  LocationProcessor copyWith({
    double? distanceFilter,
    bool? disableElasticity,
    double? elasticityMultiplier,
    int? trackingAccuracyThreshold,
    int? filterPolicy,
    int? maxImpliedSpeed,
    int? odometerAccuracyThreshold,
    bool? rejectMockLocations,
    int? mockDetectionLevel,
  }) {
    final copy = LocationProcessor(
      distanceFilter: distanceFilter ?? this.distanceFilter,
      disableElasticity: disableElasticity ?? this.disableElasticity,
      elasticityMultiplier: elasticityMultiplier ?? this.elasticityMultiplier,
      trackingAccuracyThreshold:
          trackingAccuracyThreshold ?? this.trackingAccuracyThreshold,
      filterPolicy: filterPolicy ?? this.filterPolicy,
      maxImpliedSpeed: maxImpliedSpeed ?? this.maxImpliedSpeed,
      odometerAccuracyThreshold:
          odometerAccuracyThreshold ?? this.odometerAccuracyThreshold,
      rejectMockLocations: rejectMockLocations ?? this.rejectMockLocations,
      mockDetectionLevel: mockDetectionLevel ?? this.mockDetectionLevel,
    );
    // Preserve internal state.
    copy._lastLatitude = _lastLatitude;
    copy._lastLongitude = _lastLongitude;
    copy._lastTimestampMs = _lastTimestampMs;
    copy.lastEffectiveSpeed = lastEffectiveSpeed;
    return copy;
  }
}
