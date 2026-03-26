import Foundation

/// Event emitted when the battery budget engine adjusts tracking parameters.
public struct BudgetAdjustmentEvent {
    /// Estimated current battery drain in %/hr.
    public let currentBatteryDrain: Double
    /// Configured budget target in %/hr.
    public let targetBudget: Double
    /// Adjusted distance filter (meters).
    public let newDistanceFilter: Double
    /// Adjusted desired accuracy level index.
    public let newDesiredAccuracy: Int
    /// Adjusted periodic interval (nil if not in periodic mode).
    public let newPeriodicInterval: Int?
}

/// Auto-adjusts tracking parameters to stay within a battery drain budget.
///
/// Given a target maximum battery consumption per hour (% points), monitors
/// actual battery drain and adjusts `distanceFilter`, `desiredAccuracy`, and
/// (for periodic mode) the polling interval.
///
/// Accuracy levels (ordered by battery cost, index 0 = highest):
/// `high (0) → medium (1) → low (2) → veryLow (3) → passive (4)`
public class BatteryBudgetEngine {
    /// Error threshold before adjustments are made (% points/hr).
    private static let errorThreshold = 0.5

    /// Minimum allowed distance filter (meters).
    private static let minDistanceFilter = 10.0

    /// Maximum allowed distance filter (meters).
    private static let maxDistanceFilter = 5000.0

    /// Throttle factor when draining too fast.
    private static let throttleFactor = 1.5

    /// Boost factor when under budget.
    private static let boostFactor = 0.8

    /// Target maximum battery drain per hour (% points).
    public let targetBudgetPerHour: Double

    /// Current adjusted distance filter (meters).
    public private(set) var distanceFilter: Double

    /// Current adjusted accuracy index (0=high, 4=passive).
    public private(set) var accuracyIndex: Int

    /// Current adjusted periodic interval (nil if not periodic).
    public private(set) var periodicInterval: Int?

    private var prevBatteryLevel: Double?
    private var prevSampleTime: Date?

    public init(
        targetBudgetPerHour: Double,
        initialDistanceFilter: Double = 10.0,
        initialAccuracyIndex: Int = 0,
        initialPeriodicInterval: Int? = nil
    ) {
        self.targetBudgetPerHour = targetBudgetPerHour
        self.distanceFilter = initialDistanceFilter
        self.accuracyIndex = min(max(initialAccuracyIndex, 0), 4)
        self.periodicInterval = initialPeriodicInterval
    }

    /// Process a new battery sample and return an adjustment if needed.
    ///
    /// Call this periodically (every 5 minutes is recommended).
    ///
    /// - Parameter batteryLevel: 0.0–1.0 (percentage as fraction)
    /// - Returns: adjustment event if parameters changed, nil otherwise
    public func processSample(_ batteryLevel: Double) -> BudgetAdjustmentEvent? {
        let now = Date()

        guard let prev = prevBatteryLevel, let prevTime = prevSampleTime else {
            prevBatteryLevel = batteryLevel
            prevSampleTime = now
            return nil
        }

        let elapsed = now.timeIntervalSince(prevTime)
        guard elapsed >= 60 else { return nil } // Too soon.

        // Compute actual drain normalized to %/hr.
        let drain = (prev - batteryLevel) * 100.0
        let drainPerHour = drain * (3600.0 / elapsed)

        prevBatteryLevel = batteryLevel
        prevSampleTime = now

        // Charging — no adjustment needed.
        guard drainPerHour > 0 else { return nil }

        let error = drainPerHour - targetBudgetPerHour
        guard abs(error) >= Self.errorThreshold else { return nil }

        var adjusted = false

        if error > 0 {
            // Draining too fast — throttle.
            distanceFilter = min(max(distanceFilter * Self.throttleFactor,
                                     Self.minDistanceFilter), Self.maxDistanceFilter)
            if accuracyIndex < 4 {
                accuracyIndex += 1
                adjusted = true
            }
            if let interval = periodicInterval {
                periodicInterval = min(max(Int(Double(interval) * Self.throttleFactor), 60), 43200)
            }
            adjusted = true
        } else {
            // Under budget — can improve.
            distanceFilter = min(max(distanceFilter * Self.boostFactor,
                                     Self.minDistanceFilter), Self.maxDistanceFilter)
            if accuracyIndex > 0 {
                accuracyIndex -= 1
                adjusted = true
            }
            if let interval = periodicInterval {
                periodicInterval = min(max(Int(Double(interval) * Self.boostFactor), 60), 43200)
            }
            adjusted = true
        }

        guard adjusted else { return nil }

        return BudgetAdjustmentEvent(
            currentBatteryDrain: drainPerHour,
            targetBudget: targetBudgetPerHour,
            newDistanceFilter: distanceFilter,
            newDesiredAccuracy: accuracyIndex,
            newPeriodicInterval: periodicInterval
        )
    }

    /// Reset the engine state. Call when tracking restarts.
    public func reset() {
        prevBatteryLevel = nil
        prevSampleTime = nil
    }
}
