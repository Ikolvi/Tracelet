import Foundation

/// Detected motion activity type.
///
/// Mirrors the Dart `ActivityType` enum.
public enum ActivityType: String {
    case still
    case walking
    case running
    case onFoot
    case inVehicle = "in_vehicle"
    case onBicycle = "on_bicycle"
    case unknown
}

/// Confidence level for activity detection.
///
/// Mirrors the Dart `ActivityConfidence` enum.
public enum ActivityConfidence: String {
    case low
    case medium
    case high
}

/// Contextual data used by ``AdaptiveSamplingEngine`` to compute the
/// optimal distance filter for each location fix.
public struct AdaptiveContext {
    /// Battery level as a fraction (0.0 = empty, 1.0 = full, -1 = unknown).
    public var batteryLevel: Double
    /// Whether the device is currently charging.
    public var isCharging: Bool
    /// The last detected motion activity type.
    public var activityType: ActivityType
    /// The confidence of the detected activity.
    public var activityConfidence: ActivityConfidence
    /// Current speed in m/s (0 or negative if unknown).
    public var speed: Double

    public init(
        batteryLevel: Double = -1.0,
        isCharging: Bool = false,
        activityType: ActivityType = .unknown,
        activityConfidence: ActivityConfidence = .low,
        speed: Double = 0
    ) {
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.activityType = activityType
        self.activityConfidence = activityConfidence
        self.speed = speed
    }
}

/// Which factor was the primary driver of the adaptive calculation.
public enum AdaptiveSource {
    /// Activity-based profile was used.
    case activity
    /// Speed-based elasticity was used (activity unknown or low confidence).
    case speed
    /// Static — no adaptive adjustment was applied.
    case `static`
}

/// Result of an adaptive sampling computation.
public struct AdaptiveSamplingResult {
    /// The computed distance filter in meters.
    public let effectiveDistanceFilter: Double
    /// The original base distance filter from config.
    public let baseDistanceFilter: Double
    /// Multiplier applied based on detected activity.
    public let activityFactor: Double
    /// Multiplier applied based on battery state.
    public let batteryFactor: Double
    /// Multiplier from speed-based elasticity.
    public let speedFactor: Double
    /// Which factor was the primary source of the calculation.
    public let source: AdaptiveSource
}

/// Calculates optimal distance filters based on multi-factor context.
///
/// Replaces simple speed-only elasticity with a holistic approach that
/// considers activity type, battery state, and speed.
///
/// Mirrors the Dart `AdaptiveSamplingEngine` class.
public struct AdaptiveSamplingEngine {

    /// The base distance filter in meters from config.
    public let baseDistanceFilter: Double

    /// Elasticity multiplier for speed-based fallback.
    public let elasticityMultiplier: Double

    public init(baseDistanceFilter: Double, elasticityMultiplier: Double = 1.0) {
        self.baseDistanceFilter = baseDistanceFilter
        self.elasticityMultiplier = elasticityMultiplier
    }

    // MARK: - Activity distance profiles (meters)

    public static let distanceStill: Double = 500.0
    public static let distanceWalking: Double = 50.0
    public static let distanceRunning: Double = 30.0
    public static let distanceBicycle: Double = 25.0
    public static let distanceVehicle: Double = 10.0

    // MARK: - Battery thresholds

    public static let batteryHighThreshold: Double = 0.50
    public static let batteryMediumThreshold: Double = 0.20
    public static let batteryLowThreshold: Double = 0.10

    public static let batteryMediumFactor: Double = 1.5
    public static let batteryLowFactor: Double = 2.5
    public static let batteryCriticalFactor: Double = 5.0

    /// Compute the optimal distance filter for the given context.
    public func compute(_ context: AdaptiveContext) -> AdaptiveSamplingResult {
        var activityFactor: Double = 1.0
        var speedFactor: Double = 1.0
        var source: AdaptiveSource = .static

        // Activity-based distance: use when confidence ≥ medium and type known.
        let useActivity = context.activityType != .unknown &&
            context.activityConfidence != .low

        if useActivity {
            let activityDistance = Self.activityDistance(for: context.activityType)
            activityFactor = activityDistance / baseDistanceFilter
            source = .activity
        } else if context.speed > 0 {
            let mult = max(elasticityMultiplier, 0.1)
            speedFactor = min(max(context.speed / 10.0, 1.0), 10.0) * mult
            source = .speed
        }

        let battFactor = Self.batteryFactor(
            batteryLevel: context.batteryLevel,
            isCharging: context.isCharging
        )

        let effective: Double
        switch source {
        case .activity:
            effective = baseDistanceFilter * activityFactor * battFactor
        case .speed:
            effective = baseDistanceFilter * speedFactor * battFactor
        case .static:
            effective = baseDistanceFilter * battFactor
        }

        return AdaptiveSamplingResult(
            effectiveDistanceFilter: effective,
            baseDistanceFilter: baseDistanceFilter,
            activityFactor: activityFactor,
            batteryFactor: battFactor,
            speedFactor: speedFactor,
            source: source
        )
    }

    /// Returns the distance filter target for a given activity.
    private static func activityDistance(for activity: ActivityType) -> Double {
        switch activity {
        case .still:     return distanceStill
        case .walking,
             .onFoot:    return distanceWalking
        case .running:   return distanceRunning
        case .onBicycle: return distanceBicycle
        case .inVehicle: return distanceVehicle
        case .unknown:   return 10.0 // fallback
        }
    }

    /// Returns the battery scaling factor.
    private static func batteryFactor(
        batteryLevel: Double,
        isCharging: Bool
    ) -> Double {
        if isCharging || batteryLevel < 0 { return 1.0 }
        if batteryLevel < batteryLowThreshold { return batteryCriticalFactor }
        if batteryLevel < batteryMediumThreshold { return batteryLowFactor }
        if batteryLevel < batteryHighThreshold { return batteryMediumFactor }
        return 1.0
    }
}
