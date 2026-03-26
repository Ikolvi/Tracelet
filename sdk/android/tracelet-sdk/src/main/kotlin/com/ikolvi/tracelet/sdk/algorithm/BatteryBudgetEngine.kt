package com.ikolvi.tracelet.sdk.algorithm

/**
 * Auto-adjusts tracking parameters to stay within a battery drain budget.
 *
 * Given a target maximum battery consumption per hour (% points), monitors
 * actual battery drain and adjusts `distanceFilter`, `desiredAccuracy`, and
 * (for periodic mode) the polling interval.
 *
 * Control loop (called every sampling window):
 * 1. Compute actual drain over the window, normalize to %/hr.
 * 2. Compare to target budget.
 * 3. If draining too fast: increase distanceFilter, degrade accuracy.
 * 4. If under budget: decrease distanceFilter, improve accuracy.
 * 5. Clamp values to sane ranges.
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
    companion object {
        /** Error threshold before adjustments are made (% points/hr). */
        private const val ERROR_THRESHOLD = 0.5

        /** Minimum allowed distance filter (meters). */
        private const val MIN_DISTANCE_FILTER = 10.0

        /** Maximum allowed distance filter (meters). */
        private const val MAX_DISTANCE_FILTER = 5000.0

        /** Throttle factor when draining too fast. */
        private const val THROTTLE_FACTOR = 1.5

        /** Boost factor when under budget. */
        private const val BOOST_FACTOR = 0.8
    }

    /** Current adjusted distance filter (meters). */
    var distanceFilter: Double = initialDistanceFilter
        private set

    /** Current adjusted accuracy index (0=high, 4=passive). */
    var accuracyIndex: Int = initialAccuracyIndex.coerceIn(0, 4)
        private set

    /** Current adjusted periodic interval (null if not periodic). */
    var periodicInterval: Int? = initialPeriodicInterval
        private set

    private var prevBatteryLevel: Double? = null
    private var prevSampleTimeMs: Long? = null

    /**
     * Process a new battery sample and return an adjustment if needed.
     *
     * Call this periodically (every 5 minutes is recommended).
     *
     * @param batteryLevel 0.0–1.0 (percentage as fraction)
     * @return adjustment event if parameters changed, null otherwise
     */
    fun processSample(batteryLevel: Double): BudgetAdjustmentEvent? {
        val nowMs = System.currentTimeMillis()

        if (prevBatteryLevel == null || prevSampleTimeMs == null) {
            prevBatteryLevel = batteryLevel
            prevSampleTimeMs = nowMs
            return null
        }

        val elapsedSec = (nowMs - prevSampleTimeMs!!) / 1000.0
        if (elapsedSec < 60) return null // Too soon for meaningful measurement.

        // Compute actual drain normalized to %/hr.
        val drain = (prevBatteryLevel!! - batteryLevel) * 100.0
        val drainPerHour = drain * (3600.0 / elapsedSec)

        prevBatteryLevel = batteryLevel
        prevSampleTimeMs = nowMs

        // Charging — no adjustment needed.
        if (drainPerHour <= 0) return null

        val error = drainPerHour - targetBudgetPerHour

        if (kotlin.math.abs(error) < ERROR_THRESHOLD) return null

        var adjusted = false

        if (error > 0) {
            // Draining too fast — throttle.
            distanceFilter = (distanceFilter * THROTTLE_FACTOR)
                .coerceIn(MIN_DISTANCE_FILTER, MAX_DISTANCE_FILTER)
            if (accuracyIndex < 4) {
                accuracyIndex++
                adjusted = true
            }
            periodicInterval?.let { interval ->
                periodicInterval = (interval * THROTTLE_FACTOR).toInt()
                    .coerceIn(60, 43200)
            }
            adjusted = true
        } else {
            // Under budget — can improve.
            distanceFilter = (distanceFilter * BOOST_FACTOR)
                .coerceIn(MIN_DISTANCE_FILTER, MAX_DISTANCE_FILTER)
            if (accuracyIndex > 0) {
                accuracyIndex--
                adjusted = true
            }
            periodicInterval?.let { interval ->
                periodicInterval = (interval * BOOST_FACTOR).toInt()
                    .coerceIn(60, 43200)
            }
            adjusted = true
        }

        if (!adjusted) return null

        return BudgetAdjustmentEvent(
            currentBatteryDrain = drainPerHour,
            targetBudget = targetBudgetPerHour,
            newDistanceFilter = distanceFilter,
            newDesiredAccuracy = accuracyIndex,
            newPeriodicInterval = periodicInterval,
        )
    }

    /** Reset the engine state. Call when tracking restarts. */
    fun reset() {
        prevBatteryLevel = null
        prevSampleTimeMs = null
    }
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
