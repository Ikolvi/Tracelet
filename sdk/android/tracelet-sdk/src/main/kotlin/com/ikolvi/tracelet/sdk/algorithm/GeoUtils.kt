package com.ikolvi.tracelet.sdk.algorithm

import kotlin.math.PI
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Pure-Kotlin geospatial utility functions.
 *
 * Mirrors the Dart `GeoUtils` class — ray-casting point-in-polygon and
 * Haversine distance.
 */
object GeoUtils {

    private const val DEG2RAD = PI / 180.0

    /**
     * Ray-casting point-in-polygon algorithm.
     *
     * Determines if the point ([lat], [lng]) is inside the polygon defined
     * by [vertices]. Each vertex is `[latitude, longitude]`.
     *
     * @return `true` if the point is inside the polygon.
     */
    fun isPointInPolygon(
        lat: Double,
        lng: Double,
        vertices: List<List<Double>>
    ): Boolean {
        val n = vertices.size
        if (n < 3) return false
        var inside = false
        var j = n - 1

        for (i in 0 until n) {
            val vi = vertices[i]
            if (vi.size < 2) return false
            val yi = vi[0] // lat
            val xi = vi[1] // lng
            val vj = vertices[j]
            if (vj.size < 2) return false
            val yj = vj[0]
            val xj = vj[1]

            if ((yi > lat) != (yj > lat) &&
                lng < (xj - xi) * (lat - yi) / (yj - yi) + xi
            ) {
                inside = !inside
            }
            j = i
        }
        return inside
    }

    /**
     * Haversine distance between two lat/lng points, in meters.
     */
    fun haversine(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val r = 6371000.0
        val dLat = (lat2 - lat1) * DEG2RAD
        val dLon = (lon2 - lon1) * DEG2RAD
        val sinDLat = sin(dLat * 0.5)
        val sinDLon = sin(dLon * 0.5)
        val a = sinDLat * sinDLat +
            cos(lat1 * DEG2RAD) * cos(lat2 * DEG2RAD) *
            sinDLon * sinDLon
        return r * 2.0 * asin(sqrt(a.coerceIn(0.0, 1.0)))
    }
}
