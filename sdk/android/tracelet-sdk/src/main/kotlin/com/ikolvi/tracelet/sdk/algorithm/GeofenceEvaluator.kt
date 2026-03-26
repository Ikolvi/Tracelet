package com.ikolvi.tracelet.sdk.algorithm

/**
 * A single geofence state transition detected by [GeofenceEvaluator].
 */
data class GeofenceTransition(
    /** The geofence identifier that triggered. */
    val identifier: String,
    /** `"ENTER"` or `"EXIT"`. */
    val action: String,
    /** Distance in meters from the geofence center (circular only). */
    val distance: Double? = null,
    /** The full geofence data map. */
    val geofence: Map<String, Any?> = emptyMap(),
)

/**
 * High-accuracy geofence proximity evaluator.
 *
 * On each location update, computes the distance from the current position
 * to every registered geofence and fires ENTER/EXIT transitions based on
 * threshold crossings.
 *
 * Supports both **circular** geofences (distance ≤ radius) and **polygon**
 * geofences (ray-casting point-in-polygon via [GeoUtils]).
 *
 * When the registered geofence count exceeds ~50, call [indexGeofences]
 * to build an R-tree spatial index for O(log n) queries.
 */
class GeofenceEvaluator {
    /** Set of geofence identifiers the device is currently inside. */
    private val _insideGeofenceIds = mutableSetOf<String>()

    /** Cached unmodifiable view. */
    private var _cachedInsideView: Set<String>? = null

    /** Spatial index for O(log n) geofence queries. */
    private var rtree: RTree<Map<String, Any?>>? = null

    /** Geofence data indexed by identifier, for EXIT detection on indexed path. */
    private var indexedGeofences: Map<String, Map<String, Any?>>? = null

    /** Read-only view of the geofence identifiers currently marked as "inside". */
    val insideGeofenceIds: Set<String>
        get() {
            if (_cachedInsideView == null) {
                _cachedInsideView = _insideGeofenceIds.toSet()
            }
            return _cachedInsideView!!
        }

    /** Whether a spatial index is currently active. */
    val isIndexed: Boolean get() = rtree != null

    /**
     * Build an R-tree spatial index over [geofences] for O(log n) queries.
     *
     * When the index is present, [evaluateProximity] uses it to narrow
     * candidates before computing exact distances. For ≤ 50 geofences the
     * linear scan is fast enough; the index becomes worthwhile at 100+.
     *
     * Call this whenever the registered geofence list changes. To remove
     * the index, call [clearIndex].
     */
    fun indexGeofences(geofences: List<Map<String, Any?>>) {
        val tree = RTree<Map<String, Any?>>(maxEntries = 8)
        val lookup = mutableMapOf<String, Map<String, Any?>>()

        for (gf in geofences) {
            val id = gf["identifier"] as? String ?: continue
            val lat = toDouble(gf["latitude"]) ?: continue
            val lng = toDouble(gf["longitude"]) ?: continue
            val radius = toDouble(gf["radius"]) ?: 100.0
            tree.insert(lat, lng, radius, gf)
            lookup[id] = gf
        }

        rtree = tree
        indexedGeofences = lookup
    }

    /** Remove the spatial index. [evaluateProximity] will fall back to O(n). */
    fun clearIndex() {
        rtree?.clear()
        rtree = null
        indexedGeofences = null
    }

    /**
     * Evaluate all geofences against the current position.
     *
     * Returns a list of [GeofenceTransition]s that occurred (may be empty).
     *
     * Each geofence map should contain:
     * - `identifier` (String) — unique identifier.
     * - `latitude` (Double) — center latitude (for circular geofences).
     * - `longitude` (Double) — center longitude.
     * - `radius` (Double) — radius in meters (default 100).
     * - `vertices` (List<List<Double>>) — optional polygon vertices.
     *   When present with ≥ 3 vertices, the geofence is treated as a polygon.
     */
    fun evaluateProximity(
        latitude: Double,
        longitude: Double,
        geofences: List<Map<String, Any?>>,
    ): List<GeofenceTransition> {
        val effectiveGeofences = resolveGeofences(latitude, longitude, geofences)
        val transitions = mutableListOf<GeofenceTransition>()

        for (gf in effectiveGeofences) {
            val identifier = gf["identifier"] as? String ?: continue
            val gfLat = toDouble(gf["latitude"])
            val gfLng = toDouble(gf["longitude"])

            // ── Polygon geofence ──────────────────────────────────────
            val rawVertices = gf["vertices"]
            if (rawVertices is List<*> && rawVertices.size >= 3) {
                val vertices = mutableListOf<DoubleArray>()
                var valid = true
                for (v in rawVertices) {
                    if (v is List<*> && v.size >= 2) {
                        val lat = toDouble(v[0])
                        val lng = toDouble(v[1])
                        if (lat != null && lng != null) {
                            vertices.add(doubleArrayOf(lat, lng))
                            continue
                        }
                    }
                    valid = false
                    break
                }

                if (valid && vertices.size >= 3) {
                    val isInside = GeoUtils.isPointInPolygon(
                        latitude, longitude,
                        vertices.map { listOf(it[0], it[1]) },
                    )
                    val wasInside = _insideGeofenceIds.contains(identifier)

                    if (isInside && !wasInside) {
                        _insideGeofenceIds.add(identifier)
                        _cachedInsideView = null
                        transitions.add(
                            GeofenceTransition(
                                identifier = identifier,
                                action = "ENTER",
                                geofence = gf,
                            )
                        )
                    } else if (!isInside && wasInside) {
                        _insideGeofenceIds.remove(identifier)
                        _cachedInsideView = null
                        transitions.add(
                            GeofenceTransition(
                                identifier = identifier,
                                action = "EXIT",
                                geofence = gf,
                            )
                        )
                    }
                    continue // Skip circular check
                }
            }

            // ── Circular geofence ─────────────────────────────────────
            if (gfLat == null || gfLng == null) continue

            val gfRadius = toDouble(gf["radius"]) ?: 100.0
            if (gfRadius <= 0) continue

            val distance = GeoUtils.haversine(latitude, longitude, gfLat, gfLng)
            val wasInside = _insideGeofenceIds.contains(identifier)
            val isInside = distance <= gfRadius

            if (isInside && !wasInside) {
                _insideGeofenceIds.add(identifier)
                _cachedInsideView = null
                transitions.add(
                    GeofenceTransition(
                        identifier = identifier,
                        action = "ENTER",
                        distance = distance,
                        geofence = gf,
                    )
                )
            } else if (!isInside && wasInside) {
                _insideGeofenceIds.remove(identifier)
                _cachedInsideView = null
                transitions.add(
                    GeofenceTransition(
                        identifier = identifier,
                        action = "EXIT",
                        distance = distance,
                        geofence = gf,
                    )
                )
            }
        }

        return transitions
    }

    /** Clear all tracking state. Call when tracking restarts. */
    fun clear() {
        _insideGeofenceIds.clear()
        _cachedInsideView = null
        clearIndex()
    }

    /** Remove a specific geofence from the "inside" set. */
    fun removeGeofence(identifier: String) {
        _insideGeofenceIds.remove(identifier)
        _cachedInsideView = null
    }

    // ─────────────────────────────────────────────────────────────────────
    // Private
    // ─────────────────────────────────────────────────────────────────────

    private fun resolveGeofences(
        lat: Double,
        lng: Double,
        allGeofences: List<Map<String, Any?>>,
    ): List<Map<String, Any?>> {
        val tree = rtree ?: return allGeofences
        val lookup = indexedGeofences ?: return allGeofences

        // Query a generous radius — 50 km covers any practical geofence.
        val searchRadius = 50000.0
        val nearby = tree.queryCircle(lat, lng, searchRadius)

        if (_insideGeofenceIds.isEmpty()) return nearby

        val seen = mutableSetOf<String>()
        val merged = mutableListOf<Map<String, Any?>>()
        for (gf in nearby) {
            val id = gf["identifier"] as? String
            if (id != null) seen.add(id)
            merged.add(gf)
        }
        for (id in _insideGeofenceIds) {
            if (!seen.contains(id)) {
                val gf = lookup[id]
                if (gf != null) merged.add(gf)
            }
        }
        return merged
    }

    companion object {
        private fun toDouble(value: Any?): Double? {
            return when (value) {
                is Double -> value
                is Int -> value.toDouble()
                is Long -> value.toDouble()
                is Float -> value.toDouble()
                is Number -> value.toDouble()
                else -> null
            }
        }
    }
}
