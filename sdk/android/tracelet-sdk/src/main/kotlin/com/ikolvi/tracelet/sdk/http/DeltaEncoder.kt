package com.ikolvi.tracelet.sdk.http

import org.json.JSONObject
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.roundToLong

/**
 * Encodes a batch of location maps into delta-compressed format.
 *
 * The first location is emitted as a full reference (`ref: true`).
 * Subsequent locations are encoded as deltas relative to the previous.
 *
 * Achieves 60–80% payload size reduction for high-frequency batch payloads.
 */
internal object DeltaEncoder {

    /**
     * Encode a batch of location maps into delta-compressed format.
     *
     * @param locations Non-empty, timestamp-ordered location maps.
     * @param precision Coordinate decimal places (5 ≈ 1.1m, 6 ≈ 0.11m).
     * @return List of maps ready for JSON serialization.
     */
    fun encode(
        locations: List<Map<String, Any?>>,
        precision: Int = 6
    ): List<Map<String, Any?>> {
        if (locations.isEmpty()) return emptyList()
        if (locations.size == 1) {
            return listOf(HashMap<String, Any?>(locations.first()).apply { put("ref", true) })
        }

        val factor = 10.0.pow(precision).toLong()
        val result = mutableListOf<Map<String, Any?>>()

        // First location: full reference.
        result.add(HashMap<String, Any?>(locations.first()).apply { put("ref", true) })

        var prev = locations.first()
        for (i in 1 until locations.size) {
            val curr = locations[i]
            val delta = encodeDelta(prev, curr, factor)
            result.add(mapOf("d" to delta))
            prev = curr
        }

        return result
    }

    private fun encodeDelta(
        prev: Map<String, Any?>,
        curr: Map<String, Any?>,
        factor: Long
    ): Map<String, Any?> {
        val delta = mutableMapOf<String, Any?>()

        // UUID — always full.
        delta["u"] = curr["uuid"]

        // Δ timestamp (seconds).
        val prevTs = parseTimestamp(prev["timestamp"])
        val currTs = parseTimestamp(curr["timestamp"])
        if (prevTs != null && currTs != null) {
            delta["t"] = ChronoUnit.SECONDS.between(prevTs, currTs)
        }

        // Coordinates.
        val prevCoords = asMap(prev["coords"])
        val currCoords = asMap(curr["coords"])
        if (prevCoords != null && currCoords != null) {
            val prevLat = toDouble(prevCoords["latitude"])
            val currLat = toDouble(currCoords["latitude"])
            delta["la"] = ((currLat - prevLat) * factor).roundToLong()

            val prevLng = toDouble(prevCoords["longitude"])
            val currLng = toDouble(currCoords["longitude"])
            delta["lo"] = ((currLng - prevLng) * factor).roundToLong()

            delta["s"] = round(toDouble(currCoords["speed"]) - toDouble(prevCoords["speed"]), 2)
            delta["h"] = round(
                shortestArc(toDouble(prevCoords["heading"]), toDouble(currCoords["heading"])), 2
            )
            delta["a"] = round(toDouble(currCoords["accuracy"]) - toDouble(prevCoords["accuracy"]), 2)
            delta["al"] = round(toDouble(currCoords["altitude"]) - toDouble(prevCoords["altitude"]), 2)
        }

        // Battery delta.
        val prevBattery = asMap(prev["battery"])
        val currBattery = asMap(curr["battery"])
        if (prevBattery != null && currBattery != null) {
            delta["b"] = round(toDouble(currBattery["level"]) - toDouble(prevBattery["level"]), 4)
        }

        return delta
    }

    private fun parseTimestamp(value: Any?): Instant? {
        if (value is String) {
            return try {
                Instant.from(DateTimeFormatter.ISO_DATE_TIME.parse(value))
            } catch (_: Exception) {
                null
            }
        }
        return null
    }

    @Suppress("UNCHECKED_CAST")
    private fun asMap(value: Any?): Map<String, Any?>? {
        return value as? Map<String, Any?>
    }

    private fun toDouble(value: Any?): Double {
        return when (value) {
            is Double -> value
            is Int -> value.toDouble()
            is Long -> value.toDouble()
            is Float -> value.toDouble()
            is Number -> value.toDouble()
            else -> 0.0
        }
    }

    private fun round(value: Double, places: Int): Double {
        val f = 10.0.pow(places)
        return (value * f).roundToLong() / f
    }

    /** Shortest arc between two headings (0–360°). Returns value in [-180, 180]. */
    private fun shortestArc(from: Double, to: Double): Double {
        var diff = to - from
        while (diff > 180) diff -= 360
        while (diff < -180) diff += 360
        return diff
    }
}
