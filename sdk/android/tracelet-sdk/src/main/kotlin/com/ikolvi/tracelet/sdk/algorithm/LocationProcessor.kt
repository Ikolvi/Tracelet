package com.ikolvi.tracelet.sdk.algorithm

/**
 * Result of processing a location through [LocationProcessor].
 */
data class LocationProcessorResult private constructor(
    /** Whether the location was accepted by all filters. */
    val accepted: Boolean,
    /** Computed effective speed in m/s. */
    val effectiveSpeed: Double = 0.0,
    /** Distance (meters) to add to the odometer for this location. */
    val odometerDelta: Double = 0.0,
    /** Distance (meters) from the previous accepted location. */
    val distance: Double = 0.0,
    /** Filter name that rejected the location (e.g. `DISTANCE_FILTER`). */
    val reason: String? = null,
    /** Human-readable error message for `discard`-policy rejections. */
    val errorMessage: String? = null,
    /** Whether the rejection should dispatch an error event to the user. */
    val isError: Boolean = false
) {
    companion object {
        /** The location passed all filters. */
        fun accept(
            effectiveSpeed: Double,
            odometerDelta: Double,
            distance: Double
        ) = LocationProcessorResult(
            accepted = true,
            effectiveSpeed = effectiveSpeed,
            odometerDelta = odometerDelta,
            distance = distance
        )

        /** The location was silently filtered. */
        fun filtered(reason: String) = LocationProcessorResult(
            accepted = false,
            reason = reason
        )

        /** The location was filtered and an error event should be dispatched. */
        fun error(reason: String, message: String) = LocationProcessorResult(
            accepted = false,
            reason = reason,
            errorMessage = message,
            isError = true
        )
    }
}

/**
 * Pure-Kotlin location filtering engine.
 *
 * Applies (in order): elasticity, distance filter, accuracy filter,
 * speed filter, odometer gating, and sparse deduplication.
 *
 * Mirrors the Dart `LocationProcessor` class.
 */
class LocationProcessor(
    /** Base distance filter in meters. */
    val distanceFilter: Double = 10.0,
    /** When `true`, elasticity scaling is disabled. */
    val disableElasticity: Boolean = false,
    /** Multiplier applied to the elasticity-scaled distance. */
    val elasticityMultiplier: Double = 1.0,
    /** When `true`, the adaptive sampling engine is used. */
    val enableAdaptiveMode: Boolean = false,
    /** Maximum acceptable GPS accuracy in meters. 0 disables. */
    val trackingAccuracyThreshold: Int = 0,
    /** How to handle locations exceeding accuracy threshold (0=adjust, 1=ignore, 2=discard). */
    val filterPolicy: Int = 0,
    /** Maximum plausible speed in m/s. 0 disables. */
    val maxImpliedSpeed: Int = 0,
    /** Maximum GPS accuracy for odometer counting. 0 disables. */
    val odometerAccuracyThreshold: Int = 0,
    /** When `true`, mock locations are rejected. */
    val rejectMockLocations: Boolean = false,
    /** Mock detection level: 0 = disabled, 1 = basic, 2 = heuristic. */
    val mockDetectionLevel: Int = 1,
    /** Enable sparse updates (intelligent deduplication). */
    val enableSparseUpdates: Boolean = false,
    /** Minimum distance (meters) for sparse recording. */
    val sparseDistanceThreshold: Double = 50.0,
    /** Maximum idle seconds before forcing a sparse recording. 0 disables. */
    val sparseMaxIdleSeconds: Int = 300
) {

    // Internal state
    private var lastLatitude: Double? = null
    private var lastLongitude: Double? = null
    private var lastTimestampMs: Long = 0
    private var sparseLastLat: Double? = null
    private var sparseLastLng: Double? = null
    private var sparseLastTimestampMs: Long = 0

    /** Last computed effective speed in m/s. */
    var lastEffectiveSpeed: Double = 0.0

    /** Whether `process` has accepted at least one location. */
    val hasLastLocation: Boolean get() = lastLatitude != null

    private val adaptiveEngine by lazy {
        AdaptiveSamplingEngine(
            baseDistanceFilter = distanceFilter,
            elasticityMultiplier = elasticityMultiplier
        )
    }

    /**
     * Process a new location and return the filter decision.
     */
    fun process(
        latitude: Double,
        longitude: Double,
        accuracy: Double,
        speed: Double,
        timestampMs: Long,
        isMock: Boolean = false,
        adaptiveContext: AdaptiveContext? = null
    ): LocationProcessorResult {
        // Mock location filter
        if (rejectMockLocations && isMock) {
            return if (filterPolicy == 2) {
                LocationProcessorResult.error(
                    "MOCK_LOCATION",
                    "Location rejected: flagged as mock/spoofed by the platform"
                )
            } else LocationProcessorResult.filtered("MOCK_LOCATION")
        }

        // Timestamp monotonicity (heuristic level)
        if (mockDetectionLevel >= 2 && rejectMockLocations &&
            lastTimestampMs > 0 && timestampMs < lastTimestampMs
        ) {
            return if (filterPolicy == 2) {
                LocationProcessorResult.error(
                    "MOCK_LOCATION_TIMESTAMP",
                    "Location rejected: timestamp $timestampMs is before " +
                        "previous $lastTimestampMs (non-monotonic)"
                )
            } else LocationProcessorResult.filtered("MOCK_LOCATION_TIMESTAMP")
        }

        // Distance & speed computation
        var distance = 0.0
        var timeDelta = 0.0

        val prevLat = lastLatitude
        val prevLng = lastLongitude
        if (prevLat != null && prevLng != null) {
            distance = GeoUtils.haversine(prevLat, prevLng, latitude, longitude)
            timeDelta = (timestampMs - lastTimestampMs) / 1000.0
        }

        val computedSpeed = if (distance > 0 && timeDelta > 0) distance / timeDelta else 0.0
        val effectiveSpeed = if (speed > 0) speed else computedSpeed

        // Elasticity / Adaptive: scale distanceFilter
        var effectiveDistance = distanceFilter
        if (enableAdaptiveMode) {
            val ctx = adaptiveContext?.let {
                if (it.speed <= 0) it.copy(speed = effectiveSpeed) else it
            } ?: AdaptiveContext(speed = effectiveSpeed)
            effectiveDistance = adaptiveEngine.compute(ctx).effectiveDistanceFilter
        } else if (!disableElasticity && effectiveSpeed > 0) {
            val multiplier = elasticityMultiplier.coerceAtLeast(0.1)
            val speedFactor = (effectiveSpeed / 10.0).coerceIn(1.0, 10.0)
            effectiveDistance = distanceFilter * speedFactor * multiplier
        }

        // Distance filter
        if (lastLatitude != null && distance < effectiveDistance) {
            return LocationProcessorResult.filtered("DISTANCE_FILTER")
        }

        // Accuracy filter
        if (trackingAccuracyThreshold > 0 && accuracy > trackingAccuracyThreshold) {
            when (filterPolicy) {
                2 -> return LocationProcessorResult.error(
                    "ACCURACY_FILTER",
                    "Location accuracy ${accuracy}m exceeds threshold ${trackingAccuracyThreshold}m"
                )
                1 -> return LocationProcessorResult.filtered("ACCURACY_FILTER")
                else -> if (lastLatitude != null) {
                    return LocationProcessorResult.filtered("ACCURACY_FILTER")
                }
            }
        }

        // Speed filter
        if (maxImpliedSpeed > 0 && lastLatitude != null && timeDelta > 0) {
            val impliedSpeed = distance / timeDelta
            if (impliedSpeed > maxImpliedSpeed) {
                return if (filterPolicy == 2) {
                    LocationProcessorResult.error(
                        "SPEED_FILTER",
                        "Implied speed ${"%.1f".format(impliedSpeed)}m/s exceeds max ${maxImpliedSpeed}m/s"
                    )
                } else LocationProcessorResult.filtered("SPEED_FILTER")
            }
        }

        // Odometer gating
        val odometerDelta = if (odometerAccuracyThreshold <= 0 ||
            accuracy <= odometerAccuracyThreshold
        ) distance else 0.0

        // Sparse deduplication
        if (enableSparseUpdates) {
            val sLat = sparseLastLat
            val sLng = sparseLastLng
            if (sLat != null && sLng != null) {
                val sparseDist = GeoUtils.haversine(sLat, sLng, latitude, longitude)
                val sparseElapsed = (timestampMs - sparseLastTimestampMs) / 1000.0

                val withinDistance = sparseDist < sparseDistanceThreshold
                val withinTime = sparseMaxIdleSeconds == 0 ||
                    sparseElapsed < sparseMaxIdleSeconds

                if (withinDistance && withinTime) {
                    lastLatitude = latitude
                    lastLongitude = longitude
                    lastTimestampMs = timestampMs
                    lastEffectiveSpeed = effectiveSpeed
                    return LocationProcessorResult.filtered("SPARSE_FILTER")
                }
            }
            sparseLastLat = latitude
            sparseLastLng = longitude
            sparseLastTimestampMs = timestampMs
        }

        // Accept
        lastLatitude = latitude
        lastLongitude = longitude
        lastTimestampMs = timestampMs
        lastEffectiveSpeed = effectiveSpeed

        return LocationProcessorResult.accept(
            effectiveSpeed = effectiveSpeed,
            odometerDelta = odometerDelta,
            distance = distance
        )
    }

    /** Reset all internal state. Call when tracking restarts. */
    fun reset() {
        lastLatitude = null
        lastLongitude = null
        lastTimestampMs = 0
        lastEffectiveSpeed = 0.0
        sparseLastLat = null
        sparseLastLng = null
        sparseLastTimestampMs = 0
    }
}
