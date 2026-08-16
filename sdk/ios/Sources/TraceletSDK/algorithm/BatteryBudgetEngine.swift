import Foundation

/// Event emitted when the battery budget engine adjusts tracking parameters.
public struct TraceletBudgetAdjustmentEvent {
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
/// actual battery drain and steps through a bounded ladder of sampling costs —
/// see the Rust `BatteryBudgetEngine` for the ladder itself.
///
/// Accuracy levels (ordered by battery cost, index 0 = highest):
/// `high (0) → medium (1) → low (2) → veryLow (3) → passive (4)`
public class TraceletBatteryBudgetEngine {

    /// iOS reports `UIDevice.batteryLevel` in 5 % steps.
    ///
    /// The engine needs this to know how much of a drain figure is real. Reading
    /// a single step as drain is what produced "60 %/hr" from a device that had
    /// simply crossed 0.25 → 0.20, and throttled a healthy session on it (#393).
    private static let iosBatteryLevelQuantumPercent: Double = 5.0

    private let coreEngine: BatteryBudgetEngine

    /// Target maximum battery drain per hour (% points).
    public var targetBudgetPerHour: Double {
        // the core doesn't expose a getter for target_budget_per_hour directly, but we don't really need it
        // we can store it locally if needed, but it's only used internally
        return _targetBudgetPerHour
    }
    private let _targetBudgetPerHour: Double

    /// Current adjusted distance filter (meters).
    public var distanceFilter: Double { coreEngine.distanceFilter() }

    /// Current adjusted accuracy index (0=high, 4=passive).
    public var accuracyIndex: Int { Int(coreEngine.accuracyIndex()) }

    /// Current adjusted periodic interval (nil if not periodic).
    public var periodicInterval: Int? { coreEngine.periodicInterval().map { Int($0) } }

    public init(
        targetBudgetPerHour: Double,
        initialDistanceFilter: Double = 10.0,
        initialAccuracyIndex: Int = 0,
        initialPeriodicInterval: Int? = nil
    ) {
        self._targetBudgetPerHour = targetBudgetPerHour
        self.coreEngine = BatteryBudgetEngine(
            targetBudgetPerHour: targetBudgetPerHour,
            initialDistanceFilter: initialDistanceFilter,
            initialAccuracyIndex: Int32(initialAccuracyIndex),
            initialPeriodicInterval: initialPeriodicInterval.map { Int32($0) }
        )
        coreEngine.setLevelQuantumPercent(quantum: Self.iosBatteryLevelQuantumPercent)
    }

    /// The current throttle rung, 0 (untouched) to 4 (most aggressive).
    public var throttleLevel: Int { Int(coreEngine.throttleLevel()) }

    /// Everything the ladder currently imposes, for hosts to apply and for the
    /// bug report to show.
    public var throttleState: BudgetThrottleState { coreEngine.throttleState() }

    /// Re-reads the app's configured parameters after a `setConfig`, so the
    /// overlay is recomputed against what the app now asks for.
    public func updateConfigured(
        distanceFilter: Double,
        accuracyIndex: Int,
        periodicInterval: Int?
    ) {
        coreEngine.setConfigured(
            distanceFilter: distanceFilter,
            accuracyIndex: Int32(accuracyIndex),
            periodicInterval: periodicInterval.map { Int32($0) }
        )
    }

    /// Process a new battery sample and return an adjustment if needed.
    ///
    /// Call this periodically (every 5 minutes is recommended).
    ///
    /// - Parameter batteryLevel: 0.0–1.0 (percentage as fraction)
    /// - Returns: adjustment event if parameters changed, nil otherwise
    public func processSample(_ batteryLevel: Double) -> TraceletBudgetAdjustmentEvent? {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        guard let event = coreEngine.processSample(batteryLevel: batteryLevel, nowMs: nowMs) else {
            return nil
        }

        return TraceletBudgetAdjustmentEvent(
            currentBatteryDrain: event.currentBatteryDrain,
            targetBudget: event.targetBudget,
            newDistanceFilter: event.newDistanceFilter,
            newDesiredAccuracy: Int(event.newDesiredAccuracy),
            newPeriodicInterval: event.newPeriodicInterval.map { Int($0) }
        )
    }

    /// Tell the engine the device is on external power, lifting any throttle.
    ///
    /// Hosts call this instead of skipping the sample: a charging device has no
    /// reason to carry one, and simply returning early left a throttle from an
    /// earlier discharge in force for the rest of the session.
    public func noteCharging() -> TraceletBudgetAdjustmentEvent? {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        guard let event = coreEngine.noteCharging(nowMs: nowMs) else { return nil }
        return TraceletBudgetAdjustmentEvent(
            currentBatteryDrain: event.currentBatteryDrain,
            targetBudget: event.targetBudget,
            newDistanceFilter: event.newDistanceFilter,
            newDesiredAccuracy: Int(event.newDesiredAccuracy),
            newPeriodicInterval: event.newPeriodicInterval.map { Int($0) }
        )
    }

    /// Reset the engine state. Call when tracking restarts.
    public func reset() {
        coreEngine.reset()
    }
}
