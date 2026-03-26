package com.ikolvi.tracelet.sdk.algorithm

import org.junit.Before
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Unit tests for [RTree].
 */
class RTreeTest {

    private lateinit var tree: RTree<String>

    @Before
    fun setUp() {
        tree = RTree(maxEntries = 4)
    }

    @Test
    fun `empty tree returns no results`() {
        assertTrue(tree.isEmpty)
        assertEquals(0, tree.size)
        assertEquals(emptyList(), tree.queryCircle(37.0, -122.0, 1000.0))
    }

    @Test
    fun `insert increments size`() {
        tree.insert(37.0, -122.0, 100.0, "a")
        assertEquals(1, tree.size)
        assertFalse(tree.isEmpty)

        tree.insert(38.0, -121.0, 200.0, "b")
        assertEquals(2, tree.size)
    }

    @Test
    fun `queryCircle finds nearby entry`() {
        tree.insert(37.7749, -122.4194, 100.0, "home")
        tree.insert(40.7128, -74.0060, 500.0, "nyc")

        // Query near San Francisco
        val results = tree.queryCircle(37.7750, -122.4190, 1000.0)
        assertEquals(1, results.size)
        assertEquals("home", results[0])
    }

    @Test
    fun `queryCircle excludes distant entries`() {
        tree.insert(37.7749, -122.4194, 100.0, "sf")
        tree.insert(40.7128, -74.0060, 100.0, "nyc")

        // Query near NYC
        val results = tree.queryCircle(40.7130, -74.0065, 1000.0)
        assertEquals(1, results.size)
        assertEquals("nyc", results[0])
    }

    @Test
    fun `queryCircle returns multiple nearby entries`() {
        tree.insert(37.7749, -122.4194, 100.0, "a")
        tree.insert(37.7750, -122.4195, 100.0, "b")
        tree.insert(37.7748, -122.4193, 100.0, "c")

        val results = tree.queryCircle(37.7749, -122.4194, 500.0)
        assertEquals(3, results.size)
        assertTrue(results.containsAll(listOf("a", "b", "c")))
    }

    @Test
    fun `remove decrements size`() {
        tree.insert(37.0, -122.0, 100.0, "a")
        tree.insert(38.0, -121.0, 200.0, "b")
        assertEquals(2, tree.size)

        assertTrue(tree.remove("a"))
        assertEquals(1, tree.size)

        assertFalse(tree.remove("nonexistent"))
        assertEquals(1, tree.size)
    }

    @Test
    fun `clear empties the tree`() {
        tree.insert(37.0, -122.0, 100.0, "a")
        tree.insert(38.0, -121.0, 200.0, "b")
        tree.clear()
        assertTrue(tree.isEmpty)
        assertEquals(0, tree.size)
    }

    @Test
    fun `queryBBox finds entries within bounds`() {
        tree.insert(37.7749, -122.4194, 100.0, "sf")
        tree.insert(40.7128, -74.0060, 100.0, "nyc")

        // BBox covering SF area
        val results = tree.queryBBox(37.0, -123.0, 38.0, -122.0)
        assertEquals(1, results.size)
        assertEquals("sf", results[0])
    }

    @Test
    fun `handles node splitting with many entries`() {
        // Insert more than maxEntries to trigger splits
        for (i in 0 until 20) {
            tree.insert(37.0 + i * 0.01, -122.0 + i * 0.01, 100.0, "item$i")
        }
        assertEquals(20, tree.size)

        // All items should still be queryable
        val results = tree.queryBBox(36.0, -123.0, 38.0, -121.0)
        assertEquals(20, results.size)
    }

    @Test
    fun `entry radius affects query matching`() {
        // Entry with large radius (5km) centered far away
        tree.insert(37.0, -122.0, 5000.0, "large")
        // Entry with small radius centered nearby
        tree.insert(37.05, -122.0, 10.0, "small")

        // Query from a point 4km from "large" — within its radius
        val results = tree.queryCircle(37.036, -122.0, 100.0)
        assertTrue(results.contains("large"))
    }
}
