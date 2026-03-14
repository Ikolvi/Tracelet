package com.tracelet.core.privacy

import android.content.Context
import com.tracelet.core.ConfigManager
import com.tracelet.core.db.TraceletDatabase
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * **[Enterprise]** Privacy zone manager.
 *
 * Evaluates incoming locations against registered privacy zones and applies
 * the configured action:
 *
 * - **Exclude** (`action = 0`): Location is dropped entirely — not persisted,
 *   not dispatched, not audited.
 * - **Degrade** (`action = 1`): Coordinates are degraded to a configurable
 *   accuracy radius (default 1 000 m) by snapping to a grid. The degraded
 *   location IS persisted and dispatched but with reduced precision.
 * - **Event-only** (`action = 2`): Location is dispatched to Dart listeners
 *   but NOT persisted to the database.
 *
 * ## Distance Calculation
 *
 * Uses the **Haversine formula** for accurate great-circle distance on Earth.
 * This is fast enough for per-location checks (single trig call per zone).
 */
class PrivacyZoneManager(
    private val context: Context,
    private val database: TraceletDatabase,
    private val configManager: ConfigManager,
) {
    companion object {
        /** Earth's mean radius in metres. */
        private const val EARTH_RADIUS_M = 6_371_000.0

        // Action constants (match Dart PrivacyZoneAction enum index)
        const val ACTION_EXCLUDE = 0
        const val ACTION_DEGRADE = 1
        const val ACTION_EVENT_ONLY = 2
    }

    /** Whether privacy zones are enabled in configuration. */
    fun isEnabled(): Boolean = configManager.getPrivacyZoneEnabled()

    // =========================================================================
    // In-memory zone cache
    // =========================================================================

    /** Cached zones — invalidated on add/remove, avoids DB query per location. */
    private var cachedZones: List<Map<String, Any?>>? = null

    /** Returns zones from cache, refreshing from DB only when invalidated. */
    private fun getCachedZones(): List<Map<String, Any?>> {
        return cachedZones ?: database.getPrivacyZones().also { cachedZones = it }
    }

    /** Invalidate the zone cache — forces a DB re-query on next evaluate(). */
    private fun invalidateCache() {
        cachedZones = null
    }

    // =========================================================================
    // Zone CRUD (delegates to database)
    // =========================================================================

    fun addZone(zone: Map<String, Any?>): Boolean {
        val result = database.insertPrivacyZone(zone)
        if (result) invalidateCache()
        return result
    }

    fun addZones(zones: List<Map<String, Any?>>): Boolean {
        zones.forEach { database.insertPrivacyZone(it) }
        invalidateCache()
        return true
    }

    fun removeZone(identifier: String): Boolean {
        val result = database.deletePrivacyZone(identifier)
        if (result) invalidateCache()
        return result
    }

    fun removeAllZones(): Boolean {
        val result = database.deleteAllPrivacyZones()
        invalidateCache()
        return result
    }

    fun getZones(): List<Map<String, Any?>> = getCachedZones()

    // =========================================================================
    // Location evaluation
    // =========================================================================

    /**
     * Result of evaluating a location against all privacy zones.
     *
     * @property action  The action to apply, or `null` if no zone matched.
     * @property zone    The matching zone map, or `null` if no zone matched.
     */
    data class EvaluationResult(
        val action: Int?,
        val zone: Map<String, Any?>?,
    )

    /**
     * Evaluates whether a location at ([latitude], [longitude]) falls inside
     * any registered privacy zone. Returns the matching zone's action, or
     * `null` if no zone contains the point.
     *
     * When multiple zones overlap, the **most restrictive** action wins:
     * exclude > eventOnly > degrade.
     */
    fun evaluate(latitude: Double, longitude: Double): EvaluationResult {
        if (!isEnabled()) return EvaluationResult(null, null)

        val zones = getCachedZones()
        if (zones.isEmpty()) return EvaluationResult(null, null)

        var matchedAction: Int? = null
        var matchedZone: Map<String, Any?>? = null

        for (zone in zones) {
            val zoneLat = (zone["latitude"] as? Number)?.toDouble() ?: continue
            val zoneLng = (zone["longitude"] as? Number)?.toDouble() ?: continue
            val zoneRadius = (zone["radius"] as? Number)?.toDouble() ?: continue

            val distance = haversineDistance(latitude, longitude, zoneLat, zoneLng)
            if (distance <= zoneRadius) {
                val action = (zone["action"] as? Number)?.toInt() ?: ACTION_EXCLUDE
                // Most restrictive wins: exclude(0) > eventOnly(2) > degrade(1)
                if (matchedAction == null || isActionMoreRestrictive(action, matchedAction)) {
                    matchedAction = action
                    matchedZone = zone
                }
            }
        }

        return EvaluationResult(matchedAction, matchedZone)
    }

    /**
     * Applies the privacy zone action to a location map.
     *
     * @return A [ProcessedLocation] describing what to do with the location.
     */
    fun processLocation(location: Map<String, Any?>): ProcessedLocation {
        val lat = (location["latitude"] as? Number)?.toDouble() ?: return ProcessedLocation.passThrough(location)
        val lng = (location["longitude"] as? Number)?.toDouble() ?: return ProcessedLocation.passThrough(location)

        val result = evaluate(lat, lng)
        if (result.action == null) return ProcessedLocation.passThrough(location)

        return when (result.action) {
            ACTION_EXCLUDE -> ProcessedLocation.drop()
            ACTION_EVENT_ONLY -> ProcessedLocation.eventOnly(location)
            ACTION_DEGRADE -> {
                val degradedAccuracy = (result.zone?.get("degradedAccuracyMeters") as? Number)?.toDouble() ?: 1000.0
                val degraded = degradeLocation(location, lat, lng, degradedAccuracy)
                ProcessedLocation.degraded(degraded)
            }
            else -> ProcessedLocation.passThrough(location)
        }
    }

    // =========================================================================
    // Processed location result
    // =========================================================================

    /**
     * Describes how a location should be handled after privacy zone evaluation.
     */
    data class ProcessedLocation(
        val action: Action,
        val location: Map<String, Any?>?,
    ) {
        enum class Action {
            /** No privacy zone matched — pass through normally. */
            PASS_THROUGH,
            /** Location is inside an exclusion zone — drop entirely. */
            DROP,
            /** Location should be dispatched to Dart but NOT persisted. */
            EVENT_ONLY,
            /** Coordinates have been degraded — persist and dispatch the degraded version. */
            DEGRADED,
        }

        companion object {
            fun passThrough(location: Map<String, Any?>) = ProcessedLocation(Action.PASS_THROUGH, location)
            fun drop() = ProcessedLocation(Action.DROP, null)
            fun eventOnly(location: Map<String, Any?>) = ProcessedLocation(Action.EVENT_ONLY, location)
            fun degraded(location: Map<String, Any?>) = ProcessedLocation(Action.DEGRADED, location)
        }
    }

    // =========================================================================
    // Internals
    // =========================================================================

    /**
     * Degrades location precision by snapping coordinates to a grid whose
     * cell size approximates [accuracyMeters].
     *
     * The grid is computed in degrees: `gridSize ≈ accuracyMeters / 111_320`
     * (1° latitude ≈ 111.32 km). Coordinates are rounded to the nearest grid
     * line. The location's accuracy field is set to [accuracyMeters].
     */
    private fun degradeLocation(
        location: Map<String, Any?>,
        lat: Double,
        lng: Double,
        accuracyMeters: Double,
    ): Map<String, Any?> {
        val (snappedLat, snappedLng) = degradeCoordinates(lat, lng, accuracyMeters)

        return location.toMutableMap().apply {
            put("latitude", snappedLat)
            put("longitude", snappedLng)
            put("accuracy", accuracyMeters)
            // Mark as degraded so Dart can inspect
            val coords = get("coords")
            if (coords is MutableMap<*, *>) {
                @Suppress("UNCHECKED_CAST")
                (coords as MutableMap<String, Any?>).apply {
                    put("latitude", snappedLat)
                    put("longitude", snappedLng)
                    put("accuracy", accuracyMeters)
                }
            }
        }
    }

    /**
     * Haversine great-circle distance between two points in metres.
     */
    private fun haversineDistance(
        lat1: Double, lng1: Double,
        lat2: Double, lng2: Double,
    ): Double = haversineDistanceMetres(lat1, lng1, lat2, lng2)
}

// =============================================================================
// Package-level pure functions — extracted for unit testing
// =============================================================================

/** Earth's mean radius in metres. */
private const val EARTH_RADIUS_M = 6_371_000.0

/**
 * Haversine great-circle distance between two points in metres.
 */
internal fun haversineDistanceMetres(
    lat1: Double, lng1: Double,
    lat2: Double, lng2: Double,
): Double {
    val dLat = Math.toRadians(lat2 - lat1)
    val dLng = Math.toRadians(lng2 - lng1)
    val a = sin(dLat / 2) * sin(dLat / 2) +
            cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) *
            sin(dLng / 2) * sin(dLng / 2)
    val c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return EARTH_RADIUS_M * c
}

/**
 * Returns `true` if action [a] is more restrictive than action [b].
 *
 * Priority: exclude(0) > eventOnly(2) > degrade(1).
 */
internal fun isActionMoreRestrictive(a: Int, b: Int): Boolean {
    val priority = mapOf(
        PrivacyZoneManager.ACTION_EXCLUDE to 3,
        PrivacyZoneManager.ACTION_EVENT_ONLY to 2,
        PrivacyZoneManager.ACTION_DEGRADE to 1,
    )
    return (priority[a] ?: 0) > (priority[b] ?: 0)
}

/**
 * Degrades coordinates by snapping to a grid of [accuracyMeters] resolution.
 *
 * Returns a pair of (snappedLat, snappedLng).
 */
internal fun degradeCoordinates(
    lat: Double,
    lng: Double,
    accuracyMeters: Double,
): Pair<Double, Double> {
    val gridDeg = accuracyMeters / 111_320.0
    val snappedLat = Math.round(lat / gridDeg) * gridDeg
    val snappedLng = Math.round(lng / gridDeg) * gridDeg
    return Pair(snappedLat, snappedLng)
}
