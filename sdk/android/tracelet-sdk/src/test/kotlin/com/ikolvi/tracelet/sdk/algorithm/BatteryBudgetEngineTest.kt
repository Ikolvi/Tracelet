package com.ikolvi.tracelet.sdk.algorithm

import org.junit.Before
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Unit tests for [BatteryBudgetEngine].
 */
class BatteryBudgetEngineTest {

    private lateinit var engine: BatteryBudgetEngine

    @Before
    fun setUp() {
        engine = BatteryBudgetEngine(
            targetBudgetPerHour = 5.0,
            initialDistanceFilter = 50.0,
            initialAccuracyIndex = 0,
        )
    }

    @Test
    fun `first sample returns null (baseline)`() {
        val result = engine.processSample(0.85)
        assertNull(result, "First sample should be baseline, no adjustment")
    }

    @Test
    fun `sample too soon returns null`() {
        engine.processSample(0.85)
        // Immediately call again — less than 60s elapsed
        val result = engine.processSample(0.84)
        assertNull(result)
    }

    @Test
    fun `no adjustment when within error threshold`() {
        // 5%/hr target. Error threshold is 0.5%/hr.
        // 0.42% drop in 5 min = 5.04%/hr → error = 0.04%/hr < 0.5 threshold → no adjustment
        val result = simulateSamples(
            startLevel = 0.90,
            endLevel = 0.8958, // (0.90 - 0.8958) * 100 = 0.42%, * (3600/300) = 5.04%/hr
            elapsedMs = 5 * 60 * 1000L,
        )
        assertNull(result, "Should not adjust when drain is within threshold of target")
    }

    @Test
    fun `throttle when draining too fast`() {
        val result = simulateSamples(
            startLevel = 0.90,
            endLevel = 0.85, // 5% drop in 5 min = 60%/hr — way over 5% budget
            elapsedMs = 5 * 60 * 1000L,
        )
        assertNotNull(result)
        assertTrue(result.newDistanceFilter > 50.0, "Should increase distance filter: ${result.newDistanceFilter}")
        assertTrue(result.newDesiredAccuracy > 0, "Should degrade accuracy: ${result.newDesiredAccuracy}")
        assertTrue(result.currentBatteryDrain > engine.targetBudgetPerHour)
    }

    @Test
    fun `boost when under budget`() {
        val result = simulateSamples(
            startLevel = 0.90,
            endLevel = 0.899, // 0.1% in 5 min = 1.2%/hr — well under 5% budget
            elapsedMs = 5 * 60 * 1000L,
        )
        assertNotNull(result)
        assertTrue(result.newDistanceFilter < 50.0, "Should decrease distance filter: ${result.newDistanceFilter}")
    }

    @Test
    fun `charging returns null`() {
        val result = simulateSamples(
            startLevel = 0.80,
            endLevel = 0.85, // Battery went UP (charging)
            elapsedMs = 5 * 60 * 1000L,
        )
        assertNull(result, "Should not adjust while charging")
    }

    @Test
    fun `distance filter clamped to min`() {
        // Create engine with very small distanceFilter
        val smallEngine = BatteryBudgetEngine(
            targetBudgetPerHour = 50.0, // Very high budget
            initialDistanceFilter = 10.0,
            initialAccuracyIndex = 0,
        )
        val result = simulateSamples(
            engine = smallEngine,
            startLevel = 0.999,
            endLevel = 0.998, // Tiny drain → boost
            elapsedMs = 5 * 60 * 1000L,
        )
        if (result != null) {
            assertTrue(result.newDistanceFilter >= 10.0, "Distance filter should not go below 10m")
        }
    }

    @Test
    fun `distance filter clamped to max`() {
        val largeEngine = BatteryBudgetEngine(
            targetBudgetPerHour = 0.01, // Extremely tight budget
            initialDistanceFilter = 4000.0,
            initialAccuracyIndex = 4,
        )
        val result = simulateSamples(
            engine = largeEngine,
            startLevel = 0.90,
            endLevel = 0.80, // 10% drain in 5 min = 120%/hr — massive overshoot
            elapsedMs = 5 * 60 * 1000L,
        )
        if (result != null) {
            assertTrue(result.newDistanceFilter <= 5000.0, "Distance filter should not exceed 5000m")
        }
    }

    @Test
    fun `accuracy index clamped to 0-4`() {
        assertEquals(0, engine.accuracyIndex)
        // Throttle to increase accuracy index
        simulateSamples(
            startLevel = 0.90, endLevel = 0.80, elapsedMs = 5 * 60 * 1000L
        )
        assertTrue(engine.accuracyIndex in 0..4)
    }

    @Test
    fun `reset clears state`() {
        engine.processSample(0.90)
        engine.reset()
        // After reset, next sample should be baseline again
        val result = engine.processSample(0.89)
        assertNull(result, "After reset, first sample should be baseline")
    }

    @Test
    fun `periodic interval adjusted when present`() {
        val periodicEngine = BatteryBudgetEngine(
            targetBudgetPerHour = 5.0,
            initialDistanceFilter = 50.0,
            initialAccuracyIndex = 0,
            initialPeriodicInterval = 900, // 15 min
        )
        val result = simulateSamples(
            engine = periodicEngine,
            startLevel = 0.90,
            endLevel = 0.80, // Big drain → throttle
            elapsedMs = 5 * 60 * 1000L,
        )
        assertNotNull(result)
        assertNotNull(result.newPeriodicInterval)
        assertTrue(result.newPeriodicInterval!! > 900, "Should increase periodic interval")
    }

    @Test
    fun `periodic interval null when not periodic`() {
        val result = simulateSamples(
            startLevel = 0.90,
            endLevel = 0.80,
            elapsedMs = 5 * 60 * 1000L,
        )
        assertNotNull(result)
        assertNull(result.newPeriodicInterval, "Non-periodic engine should have null interval")
    }

    @Test
    fun `budget adjustment event contains correct target`() {
        val result = simulateSamples(
            startLevel = 0.90, endLevel = 0.80, elapsedMs = 5 * 60 * 1000L
        )
        assertNotNull(result)
        assertEquals(5.0, result.targetBudget)
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    /**
     * Simulate two samples with controlled timing via reflection.
     */
    private fun simulateSamples(
        startLevel: Double,
        endLevel: Double,
        elapsedMs: Long,
        engine: BatteryBudgetEngine = this.engine,
    ): BudgetAdjustmentEvent? {
        // First sample (baseline)
        engine.processSample(startLevel)

        // Manipulate prevSampleTimeMs to simulate elapsed time
        val prevTimeField = BatteryBudgetEngine::class.java.getDeclaredField("prevSampleTimeMs")
        prevTimeField.isAccessible = true
        val now = System.currentTimeMillis()
        prevTimeField.set(engine, now - elapsedMs)

        return engine.processSample(endLevel)
    }
}
