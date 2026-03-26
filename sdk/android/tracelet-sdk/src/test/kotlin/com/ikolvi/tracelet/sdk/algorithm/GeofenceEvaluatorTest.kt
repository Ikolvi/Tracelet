package com.ikolvi.tracelet.sdk.algorithm

import org.junit.Before
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Unit tests for [GeofenceEvaluator].
 */
class GeofenceEvaluatorTest {

    private lateinit var evaluator: GeofenceEvaluator

    @Before
    fun setUp() {
        evaluator = GeofenceEvaluator()
    }

    // ── Circular geofences ──────────────────────────────────────────────

    @Test
    fun `enter circular geofence`() {
        val geofences = listOf(
            mapOf<String, Any?>("identifier" to "office", "latitude" to 37.422, "longitude" to -122.084, "radius" to 200)
        )

        // Outside (~333m)
        var t = evaluator.evaluateProximity(37.425, -122.084, geofences)
        assertTrue(t.isEmpty())

        // Inside (~55m)
        t = evaluator.evaluateProximity(37.4225, -122.084, geofences)
        assertEquals(1, t.size)
        assertEquals("office", t[0].identifier)
        assertEquals("ENTER", t[0].action)
    }

    @Test
    fun `exit circular geofence`() {
        val geofences = listOf(
            mapOf<String, Any?>("identifier" to "home", "latitude" to 37.7749, "longitude" to -122.4194, "radius" to 100)
        )

        // Enter at center
        evaluator.evaluateProximity(37.7749, -122.4194, geofences)

        // Exit — move far away
        val t = evaluator.evaluateProximity(37.78, -122.42, geofences)
        assertEquals(1, t.size)
        assertEquals("home", t[0].identifier)
        assertEquals("EXIT", t[0].action)
    }

    @Test
    fun `no transition when staying inside`() {
        val geofences = listOf(
            mapOf<String, Any?>("identifier" to "zone", "latitude" to 37.0, "longitude" to -122.0, "radius" to 500)
        )

        // Enter
        evaluator.evaluateProximity(37.0, -122.0, geofences)

        // Stay inside — slight movement
        val t = evaluator.evaluateProximity(37.001, -122.001, geofences)
        assertTrue(t.isEmpty())
    }

    @Test
    fun `no transition when staying outside`() {
        val geofences = listOf(
            mapOf<String, Any?>("identifier" to "zone", "latitude" to 37.0, "longitude" to -122.0, "radius" to 100)
        )

        val t1 = evaluator.evaluateProximity(38.0, -121.0, geofences)
        assertTrue(t1.isEmpty())

        val t2 = evaluator.evaluateProximity(38.001, -121.001, geofences)
        assertTrue(t2.isEmpty())
    }

    @Test
    fun `multiple geofence transitions`() {
        val geofences = listOf(
            mapOf<String, Any?>("identifier" to "a", "latitude" to 37.0, "longitude" to -122.0, "radius" to 500),
            mapOf<String, Any?>("identifier" to "b", "latitude" to 37.0, "longitude" to -122.0, "radius" to 1000),
        )

        // Enter both
        val t = evaluator.evaluateProximity(37.0, -122.0, geofences)
        assertEquals(2, t.size)
        assertTrue(t.any { it.identifier == "a" && it.action == "ENTER" })
        assertTrue(t.any { it.identifier == "b" && it.action == "ENTER" })
    }

    @Test
    fun `transition includes distance for circular`() {
        val geofences = listOf(
            mapOf<String, Any?>("identifier" to "g", "latitude" to 37.0, "longitude" to -122.0, "radius" to 500)
        )
        val t = evaluator.evaluateProximity(37.001, -122.0, geofences)
        assertEquals(1, t.size)
        val dist = t[0].distance
        assertTrue(dist != null && dist > 0 && dist < 500)
    }

    // ── Polygon geofences ───────────────────────────────────────────────

    @Test
    fun `enter polygon geofence`() {
        val geofences = listOf(
            mapOf<String, Any?>(
                "identifier" to "park",
                "latitude" to 37.0,
                "longitude" to -122.0,
                "vertices" to listOf(
                    listOf(36.99, -122.01),
                    listOf(36.99, -121.99),
                    listOf(37.01, -121.99),
                    listOf(37.01, -122.01),
                )
            )
        )

        // Inside polygon
        val t = evaluator.evaluateProximity(37.0, -122.0, geofences)
        assertEquals(1, t.size)
        assertEquals("park", t[0].identifier)
        assertEquals("ENTER", t[0].action)
        // Polygon transitions don't include distance
        assertEquals(null, t[0].distance)
    }

    @Test
    fun `exit polygon geofence`() {
        val geofences = listOf(
            mapOf<String, Any?>(
                "identifier" to "park",
                "latitude" to 37.0,
                "longitude" to -122.0,
                "vertices" to listOf(
                    listOf(36.99, -122.01),
                    listOf(36.99, -121.99),
                    listOf(37.01, -121.99),
                    listOf(37.01, -122.01),
                )
            )
        )

        // Enter
        evaluator.evaluateProximity(37.0, -122.0, geofences)

        // Exit
        val t = evaluator.evaluateProximity(37.05, -122.0, geofences)
        assertEquals(1, t.size)
        assertEquals("park", t[0].identifier)
        assertEquals("EXIT", t[0].action)
    }

    // ── State management ────────────────────────────────────────────────

    @Test
    fun `clear resets all state`() {
        val geofences = listOf(
            mapOf<String, Any?>("identifier" to "g", "latitude" to 37.0, "longitude" to -122.0, "radius" to 500)
        )

        evaluator.evaluateProximity(37.0, -122.0, geofences)
        assertTrue(evaluator.insideGeofenceIds.contains("g"))

        evaluator.clear()
        assertTrue(evaluator.insideGeofenceIds.isEmpty())
    }

    @Test
    fun `removeGeofence removes from inside set`() {
        val geofences = listOf(
            mapOf<String, Any?>("identifier" to "g", "latitude" to 37.0, "longitude" to -122.0, "radius" to 500)
        )

        evaluator.evaluateProximity(37.0, -122.0, geofences)
        assertTrue(evaluator.insideGeofenceIds.contains("g"))

        evaluator.removeGeofence("g")
        assertFalse(evaluator.insideGeofenceIds.contains("g"))
    }

    // ── R-tree indexing ────────────────────────────────────────────────

    @Test
    fun `indexed evaluation produces same results`() {
        val geofences = listOf(
            mapOf<String, Any?>("identifier" to "a", "latitude" to 37.0, "longitude" to -122.0, "radius" to 200),
            mapOf<String, Any?>("identifier" to "b", "latitude" to 38.0, "longitude" to -121.0, "radius" to 200),
        )

        // Build index
        evaluator.indexGeofences(geofences)
        assertTrue(evaluator.isIndexed)

        // Enter nearby geofence
        val t = evaluator.evaluateProximity(37.0, -122.0, geofences)
        assertEquals(1, t.size)
        assertEquals("a", t[0].identifier)
        assertEquals("ENTER", t[0].action)
    }

    @Test
    fun `indexed EXIT detection for inside geofences`() {
        val geofences = listOf(
            mapOf<String, Any?>("identifier" to "x", "latitude" to 37.0, "longitude" to -122.0, "radius" to 200),
        )

        // Enter without index
        evaluator.evaluateProximity(37.0, -122.0, geofences)
        assertTrue(evaluator.insideGeofenceIds.contains("x"))

        // Build index
        evaluator.indexGeofences(geofences)

        // Move far away — should get EXIT even though geofence is far from the 50km search
        val t = evaluator.evaluateProximity(38.0, -121.0, geofences)
        assertEquals(1, t.size)
        assertEquals("x", t[0].identifier)
        assertEquals("EXIT", t[0].action)
    }

    @Test
    fun `clearIndex falls back to linear scan`() {
        val geofences = listOf(
            mapOf<String, Any?>("identifier" to "a", "latitude" to 37.0, "longitude" to -122.0, "radius" to 200),
        )

        evaluator.indexGeofences(geofences)
        evaluator.clearIndex()
        assertFalse(evaluator.isIndexed)

        val t = evaluator.evaluateProximity(37.0, -122.0, geofences)
        assertEquals(1, t.size)
        assertEquals("ENTER", t[0].action)
    }

    // ── Edge cases ──────────────────────────────────────────────────────

    @Test
    fun `skip geofence with missing identifier`() {
        val geofences = listOf(
            mapOf<String, Any?>("latitude" to 37.0, "longitude" to -122.0, "radius" to 500)
        )
        val t = evaluator.evaluateProximity(37.0, -122.0, geofences)
        assertTrue(t.isEmpty())
    }

    @Test
    fun `skip geofence with zero radius`() {
        val geofences = listOf(
            mapOf<String, Any?>("identifier" to "g", "latitude" to 37.0, "longitude" to -122.0, "radius" to 0)
        )
        val t = evaluator.evaluateProximity(37.0, -122.0, geofences)
        assertTrue(t.isEmpty())
    }

    @Test
    fun `default radius 100m when not specified`() {
        val geofences = listOf(
            mapOf<String, Any?>("identifier" to "g", "latitude" to 37.0, "longitude" to -122.0)
        )
        // At center — 0m, default radius 100m, should enter
        val t = evaluator.evaluateProximity(37.0, -122.0, geofences)
        assertEquals(1, t.size)
        assertEquals("ENTER", t[0].action)
    }
}
