import Foundation

/// Result of processing a location through ``LocationProcessor``.
public struct LocationProcessorResult {
    /// Whether the location was accepted by all filters.
    public let accepted: Bool
    /// Computed effective speed in m/s.
    public let effectiveSpeed: Double
    /// Distance (meters) to add to the odometer for this location.
    public let odometerDelta: Double
    /// Distance (meters) from the previous accepted location.
    public let distance: Double
    /// Filter name that rejected the location (e.g. `DISTANCE_FILTER`).
    public let reason: String?
    /// Human-readable error message for `discard`-policy rejections.
    public let errorMessage: String?
    /// Whether the rejection should dispatch an error event to the user.
    public let isError: Bool

    /// The location passed all filters.
    public static func accept(
        effectiveSpeed: Double,
        odometerDelta: Double,
        distance: Double
    ) -> LocationProcessorResult {
        LocationProcessorResult(
            accepted: true,
            effectiveSpeed: effectiveSpeed,
            odometerDelta: odometerDelta,
            distance: distance,
            reason: nil,
            errorMessage: nil,
            isError: false
        )
    }

    /// The location was silently filtered.
    public static func filtered(_ reason: String) -> LocationProcessorResult {
        LocationProcessorResult(
            accepted: false,
            effectiveSpeed: 0,
            odometerDelta: 0,
            distance: 0,
            reason: reason,
            errorMessage: nil,
            isError: false
        )
    }

    /// The location was filtered and an error event should be dispatched.
    public static func error(
        _ reason: String,
        _ message: String
    ) -> LocationProcessorResult {
        LocationProcessorResult(
            accepted: false,
            effectiveSpeed: 0,
            odometerDelta: 0,
            distance: 0,
            reason: reason,
            errorMessage: message,
            isError: true
        )
    }
}

/// Pure-Swift location filtering engine.
///
/// Applies (in order): elasticity, distance filter, accuracy filter,
/// speed filter, odometer gating, and sparse deduplication.
///
/// Mirrors the Dart `LocationProcessor` class.
public final class LocationProcessor {

    /// Base distance filter in meters.
    public let distanceFilter: Double
    /// When `true`, elasticity scaling is disabled.
    public let disableElasticity: Bool
    /// Multiplier applied to the elasticity-scaled distance.
    public let elasticityMultiplier: Double
    /// When `true`, the adaptive sampling engine is used instead of
    /// simple speed-based elasticity.
    public let enableAdaptiveMode: Bool
    /// Maximum acceptable GPS accuracy in meters. 0 disables.
    public let trackingAccuracyThreshold: Int
    /// How to handle locations exceeding accuracy threshold.
    /// 0 = adjust, 1 = ignore, 2 = discard.
    public let filterPolicy: Int
    /// Maximum plausible speed in m/s. 0 disables.
    public let maxImpliedSpeed: Int
    /// Maximum GPS accuracy for odometer counting. 0 disables.
    public let odometerAccuracyThreshold: Int
    /// When `true`, mock locations are rejected.
    public let rejectMockLocations: Bool
    /// Mock detection level: 0 = disabled, 1 = basic, 2 = heuristic.
    public let mockDetectionLevel: Int
    /// Enable sparse updates (intelligent deduplication).
    public let enableSparseUpdates: Bool
    /// Minimum distance (meters) for sparse recording.
    public let sparseDistanceThreshold: Double
    /// Maximum idle seconds before forcing a sparse recording. 0 disables.
    public let sparseMaxIdleSeconds: Int

    // Internal state
    private var lastLatitude: Double?
    private var lastLongitude: Double?
    private var lastTimestampMs: Int = 0
    private var sparseLastLat: Double?
    private var sparseLastLng: Double?
    private var sparseLastTimestampMs: Int = 0

    /// Last computed effective speed in m/s.
    public var lastEffectiveSpeed: Double = 0

    /// Whether `process` has accepted at least one location.
    public var hasLastLocation: Bool { lastLatitude != nil }

    /// Cached adaptive sampling engine.
    private lazy var adaptiveEngine = AdaptiveSamplingEngine(
        baseDistanceFilter: distanceFilter,
        elasticityMultiplier: elasticityMultiplier
    )

    public init(
        distanceFilter: Double = 10.0,
        disableElasticity: Bool = false,
        elasticityMultiplier: Double = 1.0,
        enableAdaptiveMode: Bool = false,
        trackingAccuracyThreshold: Int = 0,
        filterPolicy: Int = 0,
        maxImpliedSpeed: Int = 0,
        odometerAccuracyThreshold: Int = 0,
        rejectMockLocations: Bool = false,
        mockDetectionLevel: Int = 1,
        enableSparseUpdates: Bool = false,
        sparseDistanceThreshold: Double = 50.0,
        sparseMaxIdleSeconds: Int = 300
    ) {
        self.distanceFilter = distanceFilter
        self.disableElasticity = disableElasticity
        self.elasticityMultiplier = elasticityMultiplier
        self.enableAdaptiveMode = enableAdaptiveMode
        self.trackingAccuracyThreshold = trackingAccuracyThreshold
        self.filterPolicy = filterPolicy
        self.maxImpliedSpeed = maxImpliedSpeed
        self.odometerAccuracyThreshold = odometerAccuracyThreshold
        self.rejectMockLocations = rejectMockLocations
        self.mockDetectionLevel = mockDetectionLevel
        self.enableSparseUpdates = enableSparseUpdates
        self.sparseDistanceThreshold = sparseDistanceThreshold
        self.sparseMaxIdleSeconds = sparseMaxIdleSeconds
    }

    /// Process a new location and return the filter decision.
    ///
    /// - Parameters:
    ///   - latitude: GPS latitude in degrees.
    ///   - longitude: GPS longitude in degrees.
    ///   - accuracy: Horizontal accuracy in meters.
    ///   - speed: Platform-reported speed in m/s (-1 or 0 if unavailable).
    ///   - timestampMs: Location timestamp in milliseconds since epoch.
    ///   - isMock: Whether the platform flagged this as a mock location.
    ///   - adaptiveContext: Optional context for adaptive sampling.
    public func process(
        latitude: Double,
        longitude: Double,
        accuracy: Double,
        speed: Double,
        timestampMs: Int,
        isMock: Bool = false,
        adaptiveContext: AdaptiveContext? = nil
    ) -> LocationProcessorResult {
        // ── Mock location filter ──
        if rejectMockLocations && isMock {
            if filterPolicy == 2 {
                return .error(
                    "MOCK_LOCATION",
                    "Location rejected: flagged as mock/spoofed by the platform"
                )
            }
            return .filtered("MOCK_LOCATION")
        }

        // ── Timestamp monotonicity (heuristic level) ──
        if mockDetectionLevel >= 2 && rejectMockLocations &&
            lastTimestampMs > 0 && timestampMs < lastTimestampMs {
            if filterPolicy == 2 {
                return .error(
                    "MOCK_LOCATION_TIMESTAMP",
                    "Location rejected: timestamp \(timestampMs) is before " +
                    "previous \(lastTimestampMs) (non-monotonic)"
                )
            }
            return .filtered("MOCK_LOCATION_TIMESTAMP")
        }

        // ── Distance & speed computation ──
        var distance: Double = 0
        var timeDelta: Double = 0

        if let prevLat = lastLatitude, let prevLng = lastLongitude {
            distance = GeoUtils.haversine(prevLat, prevLng, latitude, longitude)
            timeDelta = Double(timestampMs - lastTimestampMs) / 1000.0
        }

        let computedSpeed = (distance > 0 && timeDelta > 0)
            ? distance / timeDelta : 0.0
        let effectiveSpeed = (speed > 0) ? speed : computedSpeed

        // ── Elasticity / Adaptive: scale distanceFilter ──
        var effectiveDistance = distanceFilter
        if enableAdaptiveMode {
            var ctx = adaptiveContext ?? AdaptiveContext(speed: effectiveSpeed)
            if ctx.speed <= 0 { ctx.speed = effectiveSpeed }
            let result = adaptiveEngine.compute(ctx)
            effectiveDistance = result.effectiveDistanceFilter
        } else if !disableElasticity && effectiveSpeed > 0 {
            let multiplier = max(elasticityMultiplier, 0.1)
            let speedFactor = min(max(effectiveSpeed / 10.0, 1.0), 10.0)
            effectiveDistance = distanceFilter * speedFactor * multiplier
        }

        // ── Distance filter ──
        if lastLatitude != nil && distance < effectiveDistance {
            return .filtered("DISTANCE_FILTER")
        }

        // ── Accuracy filter ──
        if trackingAccuracyThreshold > 0 &&
            accuracy > Double(trackingAccuracyThreshold) {
            switch filterPolicy {
            case 2:
                return .error(
                    "ACCURACY_FILTER",
                    "Location accuracy \(accuracy)m exceeds " +
                    "threshold \(trackingAccuracyThreshold)m"
                )
            case 1:
                return .filtered("ACCURACY_FILTER")
            default:
                if lastLatitude != nil {
                    return .filtered("ACCURACY_FILTER")
                }
            }
        }

        // ── Speed filter ──
        if maxImpliedSpeed > 0 && lastLatitude != nil && timeDelta > 0 {
            let impliedSpeed = distance / timeDelta
            if impliedSpeed > Double(maxImpliedSpeed) {
                if filterPolicy == 2 {
                    return .error(
                        "SPEED_FILTER",
                        "Implied speed \(String(format: "%.1f", impliedSpeed))m/s " +
                        "exceeds max \(maxImpliedSpeed)m/s"
                    )
                }
                return .filtered("SPEED_FILTER")
            }
        }

        // ── Odometer gating ──
        var odometerDelta: Double = 0
        if odometerAccuracyThreshold <= 0 ||
            accuracy <= Double(odometerAccuracyThreshold) {
            odometerDelta = distance
        }

        // ── Sparse deduplication ──
        if enableSparseUpdates {
            if let sLat = sparseLastLat, let sLng = sparseLastLng {
                let sparseDist = GeoUtils.haversine(
                    sLat, sLng, latitude, longitude
                )
                let sparseElapsed = Double(timestampMs - sparseLastTimestampMs) / 1000.0

                let withinDistance = sparseDist < sparseDistanceThreshold
                let withinTime = sparseMaxIdleSeconds == 0 ||
                    sparseElapsed < Double(sparseMaxIdleSeconds)

                if withinDistance && withinTime {
                    lastLatitude = latitude
                    lastLongitude = longitude
                    lastTimestampMs = timestampMs
                    lastEffectiveSpeed = effectiveSpeed
                    return .filtered("SPARSE_FILTER")
                }
            }
            sparseLastLat = latitude
            sparseLastLng = longitude
            sparseLastTimestampMs = timestampMs
        }

        // ── Accept ──
        lastLatitude = latitude
        lastLongitude = longitude
        lastTimestampMs = timestampMs
        lastEffectiveSpeed = effectiveSpeed

        return .accept(
            effectiveSpeed: effectiveSpeed,
            odometerDelta: odometerDelta,
            distance: distance
        )
    }

    /// Reset all internal state. Call when tracking restarts.
    public func reset() {
        lastLatitude = nil
        lastLongitude = nil
        lastTimestampMs = 0
        lastEffectiveSpeed = 0
        sparseLastLat = nil
        sparseLastLng = nil
        sparseLastTimestampMs = 0
    }
}
