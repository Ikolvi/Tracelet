package com.ikolvi.tracelet.sdk.algorithm

/**
 * Detected motion activity type.
 *
 * Mirrors the Dart `ActivityType` enum.
 */
enum class ActivityType(val value: String) {
    STILL("still"),
    WALKING("walking"),
    RUNNING("running"),
    ON_FOOT("on_foot"),
    IN_VEHICLE("in_vehicle"),
    ON_BICYCLE("on_bicycle"),
    UNKNOWN("unknown");

    companion object {
        fun fromString(value: String): ActivityType =
            entries.find { it.value == value } ?: UNKNOWN
    }
}

/**
 * Confidence level for activity detection.
 *
 * Mirrors the Dart `ActivityConfidence` enum.
 */
enum class ActivityConfidence {
    LOW, MEDIUM, HIGH
}

/**
 * Contextual data used by [AdaptiveSamplingEngine] to compute the
 * optimal distance filter for each location fix.
 */
data class AdaptiveContext(
    /** Battery level as a fraction (0.0 = empty, 1.0 = full, -1 = unknown). */
    val batteryLevel: Double = -1.0,
    /** Whether the device is currently charging. */
    val isCharging: Boolean = false,
    /** The last detected motion activity type. */
    val activityType: ActivityType = ActivityType.UNKNOWN,
    /** The confidence of the detected activity. */
    val activityConfidence: ActivityConfidence = ActivityConfidence.LOW,
    /** Current speed in m/s (0 or negative if unknown). */
    val speed: Double = 0.0
)

/**
 * Which factor was the primary driver of the adaptive calculation.
 */
enum class AdaptiveSource {
    /** Activity-based profile was used. */
    ACTIVITY,
    /** Speed-based elasticity was used (activity unknown or low confidence). */
    SPEED,
    /** Static — no adaptive adjustment was applied. */
    STATIC
}

/**
 * Result of an adaptive sampling computation.
 */
data class AdaptiveSamplingResult(
    /** The computed distance filter in meters. */
    val effectiveDistanceFilter: Double,
    /** The original base distance filter from config. */
    val baseDistanceFilter: Double,
    /** Multiplier applied based on detected activity. */
    val activityFactor: Double,
    /** Multiplier applied based on battery state. */
    val batteryFactor: Double,
    /** Multiplier from speed-based elasticity. */
    val speedFactor: Double,
    /** Which factor was the primary source of the calculation. */
    val source: AdaptiveSource
)

/**
 * Calculates optimal distance filters based on multi-factor context.
 *
 * Replaces simple speed-only elasticity with a holistic approach that
 * considers activity type, battery state, and speed.
 *
 * Mirrors the Dart `AdaptiveSamplingEngine` class.
 */
class AdaptiveSamplingEngine(
    /** The base distance filter in meters from config. */
    val baseDistanceFilter: Double,
    /** Elasticity multiplier for speed-based fallback. */
    val elasticityMultiplier: Double = 1.0
) {

    /**
     * Compute the optimal distance filter for the given [context].
     */
    fun compute(context: AdaptiveContext): AdaptiveSamplingResult {
        var activityFactor = 1.0
        var speedFactor = 1.0
        var source = AdaptiveSource.STATIC

        val useActivity = context.activityType != ActivityType.UNKNOWN &&
            context.activityConfidence != ActivityConfidence.LOW

        if (useActivity) {
            val activityDistance = activityDistance(context.activityType)
            activityFactor = activityDistance / baseDistanceFilter
            source = AdaptiveSource.ACTIVITY
        } else if (context.speed > 0) {
            val mult = elasticityMultiplier.coerceAtLeast(0.1)
            speedFactor = (context.speed / 10.0).coerceIn(1.0, 10.0) * mult
            source = AdaptiveSource.SPEED
        }

        val battFactor = batteryFactor(context.batteryLevel, context.isCharging)

        val effective = when (source) {
            AdaptiveSource.ACTIVITY -> baseDistanceFilter * activityFactor * battFactor
            AdaptiveSource.SPEED -> baseDistanceFilter * speedFactor * battFactor
            AdaptiveSource.STATIC -> baseDistanceFilter * battFactor
        }

        return AdaptiveSamplingResult(
            effectiveDistanceFilter = effective,
            baseDistanceFilter = baseDistanceFilter,
            activityFactor = activityFactor,
            batteryFactor = battFactor,
            speedFactor = speedFactor,
            source = source
        )
    }

    companion object {
        // Activity distance profiles (meters)
        const val DISTANCE_STILL = 500.0
        const val DISTANCE_WALKING = 50.0
        const val DISTANCE_RUNNING = 30.0
        const val DISTANCE_BICYCLE = 25.0
        const val DISTANCE_VEHICLE = 10.0

        // Battery thresholds
        const val BATTERY_HIGH_THRESHOLD = 0.50
        const val BATTERY_MEDIUM_THRESHOLD = 0.20
        const val BATTERY_LOW_THRESHOLD = 0.10

        const val BATTERY_MEDIUM_FACTOR = 1.5
        const val BATTERY_LOW_FACTOR = 2.5
        const val BATTERY_CRITICAL_FACTOR = 5.0

        private fun activityDistance(activity: ActivityType): Double = when (activity) {
            ActivityType.STILL -> DISTANCE_STILL
            ActivityType.WALKING, ActivityType.ON_FOOT -> DISTANCE_WALKING
            ActivityType.RUNNING -> DISTANCE_RUNNING
            ActivityType.ON_BICYCLE -> DISTANCE_BICYCLE
            ActivityType.IN_VEHICLE -> DISTANCE_VEHICLE
            ActivityType.UNKNOWN -> 10.0
        }

        private fun batteryFactor(batteryLevel: Double, isCharging: Boolean): Double {
            if (isCharging || batteryLevel < 0) return 1.0
            if (batteryLevel < BATTERY_LOW_THRESHOLD) return BATTERY_CRITICAL_FACTOR
            if (batteryLevel < BATTERY_MEDIUM_THRESHOLD) return BATTERY_LOW_FACTOR
            if (batteryLevel < BATTERY_HIGH_THRESHOLD) return BATTERY_MEDIUM_FACTOR
            return 1.0
        }
    }
}
