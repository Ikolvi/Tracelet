package com.ikolvi.tracelet.sdk.algorithm

/**
 * Auto-adjusts tracking parameters to stay within a battery drain budget.
 *
 * Given a target maximum battery consumption per hour (% points), monitors
 * actual battery drain and steps through a bounded ladder of sampling costs —
 * see the Rust `BatteryBudgetEngine` for the ladder and the evidence bar a
 * window has to clear before it moves.
 *
 * Accuracy levels (ordered by battery cost, index 0 = highest):
 * `high (0) → medium (1) → low (2) → veryLow (3) → passive (4)`
 */
class BatteryBudgetEngine(
    /** Target maximum battery drain per hour (% points). */
    val targetBudgetPerHour: Double,
    initialDistanceFilter: Double = 10.0,
    initialAccuracyIndex: Int = 0,
    initialPeriodicInterval: Int? = null,
) {

    private companion object {
        /**
         * Android reports battery level in whole percent.
         *
         * Finer than iOS's 5 % steps, so a window of the same width resolves a
         * smaller drain — but the principle is the same, and stating it is what
         * stops one reporting step being read as the drain itself (#393).
         */
        const val ANDROID_BATTERY_LEVEL_QUANTUM_PERCENT = 1.0
    }

    private val coreEngine = uniffi.tracelet_core.BatteryBudgetEngine(
        targetBudgetPerHour,
        initialDistanceFilter,
        initialAccuracyIndex,
        initialPeriodicInterval
    ).also { it.setLevelQuantumPercent(ANDROID_BATTERY_LEVEL_QUANTUM_PERCENT) }

    /** Current adjusted distance filter (meters). */
    val distanceFilter: Double
        get() = coreEngine.distanceFilter()

    /** Current adjusted accuracy index (0=high, 4=passive). */
    val accuracyIndex: Int
        get() = coreEngine.accuracyIndex()

    /** Current adjusted periodic interval (null if not periodic). */
    val periodicInterval: Int?
        get() = coreEngine.periodicInterval()

    /** The current throttle rung, 0 (untouched) to 4 (most aggressive). */
    val throttleLevel: Int
        get() = coreEngine.throttleLevel()

    /** Everything the ladder currently imposes. */
    val throttleState: uniffi.tracelet_core.BudgetThrottleState
        get() = coreEngine.throttleState()

    /**
     * Re-reads the app's configured parameters after a `setConfig`, so the
     * overlay is recomputed against what the app now asks for.
     */
    fun updateConfigured(distanceFilter: Double, accuracyIndex: Int, periodicInterval: Int?) {
        coreEngine.setConfigured(distanceFilter, accuracyIndex, periodicInterval)
    }

    /**
     * Process a new battery sample and return an adjustment if needed.
     *
     * Call this periodically (every 5 minutes is recommended).
     *
     * @param batteryLevel 0.0–1.0 (percentage as fraction)
     * @return adjustment event if parameters changed, null otherwise
     */
    fun processSample(batteryLevel: Double, nowMs: Long = System.currentTimeMillis()): BudgetAdjustmentEvent? =
        coreEngine.processSample(batteryLevel, nowMs)?.toHostEvent()

    /**
     * Tell the engine the device is on external power, lifting any throttle.
     *
     * Hosts call this instead of skipping the sample: a charging device has no
     * reason to carry one, and returning early left a throttle picked up during
     * an earlier discharge in force for the rest of the session (#396).
     */
    fun noteCharging(nowMs: Long = System.currentTimeMillis()): BudgetAdjustmentEvent? =
        coreEngine.noteCharging(nowMs)?.toHostEvent()

    /** Reset the engine state. Call when tracking restarts. */
    fun reset() {
        coreEngine.reset()
    }

    private fun uniffi.tracelet_core.BudgetAdjustmentEvent.toHostEvent() = BudgetAdjustmentEvent(
        currentBatteryDrain = currentBatteryDrain,
        targetBudget = targetBudget,
        newDistanceFilter = newDistanceFilter,
        newDesiredAccuracy = newDesiredAccuracy,
        newPeriodicInterval = newPeriodicInterval,
    )
}

/**
 * Event emitted when the battery budget engine adjusts tracking parameters.
 */
data class BudgetAdjustmentEvent(
    /** Estimated current battery drain in %/hr. */
    val currentBatteryDrain: Double,
    /** Configured budget target in %/hr. */
    val targetBudget: Double,
    /** Adjusted distance filter (meters). */
    val newDistanceFilter: Double,
    /** Adjusted desired accuracy level index. */
    val newDesiredAccuracy: Int,
    /** Adjusted periodic interval (null if not in periodic mode). */
    val newPeriodicInterval: Int?,
)
