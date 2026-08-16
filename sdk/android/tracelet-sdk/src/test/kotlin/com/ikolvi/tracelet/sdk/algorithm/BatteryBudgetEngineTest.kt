package com.ikolvi.tracelet.sdk.algorithm

import org.junit.Before
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Unit tests for [BatteryBudgetEngine].
 *
 * These assert the ladder's contract, which replaced an unbounded multiplier in
 * #393/#396. The tests that stood here before asserted the multiplier's
 * behaviour, and every one of them described the defect rather than the
 * requirement: a single five-minute window was enough to throttle, a configured
 * distance filter was clamped up to 10 m, and accuracy was coarsened on the
 * first over-budget reading. The field failure was a device that had simply
 * crossed one 5 % battery reporting step.
 */
class BatteryBudgetEngineTest {

    private companion object {
        const val MINUTE_MS = 60_000L

        /** Android's own reporting step; the engine is told this at construction. */
        const val QUANTUM = 1.0
    }

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
        assertNull(engine.processSample(0.85, 0), "First sample should be baseline, no adjustment")
    }

    @Test
    fun `sample too soon returns null`() {
        engine.processSample(0.85, 0)
        assertNull(engine.processSample(0.84, 5 * MINUTE_MS))
    }

    /**
     * The field failure, in the form the device produced it: two samples five
     * minutes apart across one reporting step, which the old engine read as a
     * 60 %/hr drain and acted on (#393).
     */
    @Test
    fun `a single reporting step does not throttle`() {
        engine.processSample(0.25, 0)
        assertNull(engine.processSample(0.24, 5 * MINUTE_MS))
        assertEquals(0, engine.throttleLevel, "throttled on one battery reporting step")
    }

    /**
     * A drain has to beat the budget by more than the window can resolve. Over
     * fifteen minutes one 1 % step is 4 %/hr, so a 5 %/hr budget cannot be
     * conclusively exceeded by a reading that close to it.
     */
    @Test
    fun `a drain inside the measurement resolution is inconclusive`() {
        engine.processSample(0.90, 0)
        assertNull(engine.processSample(0.88, 15 * MINUTE_MS))
        assertEquals(0, engine.throttleLevel)
    }

    @Test
    fun `no adjustment when within error threshold`() {
        engine.processSample(0.90, 0)
        // 5.04 %/hr against a 5 %/hr budget, over a window wide enough to
        // resolve it: on budget, so neither direction is conclusive.
        assertNull(engine.processSample(0.874, 60 * MINUTE_MS))
        assertEquals(0, engine.throttleLevel)
    }

    @Test
    fun `sustained heavy drain climbs one rung at a time`() {
        engine.processSample(0.90, 0)
        assertNull(
            engine.processSample(0.75, 30 * MINUTE_MS),
            "one conclusive window is not a dwell",
        )
        assertEquals(0, engine.throttleLevel)

        assertNotNull(engine.processSample(0.60, 60 * MINUTE_MS))
        assertEquals(1, engine.throttleLevel)

        assertNull(engine.processSample(0.45, 90 * MINUTE_MS))
        assertNotNull(engine.processSample(0.30, 120 * MINUTE_MS))
        assertEquals(2, engine.throttleLevel, "one rung per dwell, never two")
    }

    /**
     * The opt-out the old engine destroyed first: `0` meant "record every fix",
     * and `(0 * 1.5).clamp(10, 5000)` turned it into 10 m — permanently, since
     * the recovery path clamped at 10 too (#393).
     */
    @Test
    fun `a configured distance filter of zero is never clamped up`() {
        val zeroEngine = BatteryBudgetEngine(
            targetBudgetPerHour = 5.0,
            initialDistanceFilter = 0.0,
            initialAccuracyIndex = 0,
        )
        assertEquals(0.0, zeroEngine.distanceFilter)
        assertEquals(0.0, zeroEngine.throttleState.distanceFilter)
    }

    @Test
    fun `the ladder never goes below the configured values`() {
        val wideEngine = BatteryBudgetEngine(
            targetBudgetPerHour = 5.0,
            initialDistanceFilter = 250.0,
            initialAccuracyIndex = 2,
        )
        climbOneRung(wideEngine)
        assertEquals(1, wideEngine.throttleLevel)
        assertEquals(
            250.0,
            wideEngine.throttleState.distanceFilter,
            "a configured filter wider than the rung stands",
        )
        assertEquals(
            2,
            wideEngine.throttleState.desiredAccuracy,
            "a configured tier coarser than the rung stands",
        )
    }

    /**
     * Cadence before fidelity. On iOS the tier below `kCLLocationAccuracyBest`
     * is `…HundredMeters` — a hundredfold degradation in one step, and the step
     * the old engine took first. Against a 15 m tracking gate that guaranteed
     * every subsequent fix would be rejected (#396).
     */
    @Test
    fun `accuracy survives the first two rungs`() {
        climbOneRung(engine)
        assertEquals(1, engine.throttleLevel)
        assertEquals(0, engine.throttleState.desiredAccuracy)
        assertEquals(0, engine.throttleState.trackingAccuracyFloor)
        assertTrue(engine.throttleState.cadenceMultiplier > 1.0, "cadence is the first knob")
    }

    /** A coarsened request must relax the gate that judges its fixes. */
    @Test
    fun `a coarsened accuracy tier carries a matching gate floor`() {
        repeat(3) { climbOneRung(engine, offsetMinutes = it * 60L) }
        assertEquals(3, engine.throttleLevel)
        assertTrue(engine.throttleState.desiredAccuracy >= 1)
        assertTrue(
            engine.throttleState.trackingAccuracyFloor >= 100,
            "a 100 m accuracy tier behind a 15 m gate records nothing",
        )
    }

    @Test
    fun `charging lifts the throttle immediately`() {
        climbOneRung(engine)
        assertEquals(1, engine.throttleLevel)

        assertNotNull(engine.noteCharging(61 * MINUTE_MS))
        assertEquals(0, engine.throttleLevel)
        assertNull(
            engine.noteCharging(62 * MINUTE_MS),
            "no event when there was nothing to lift",
        )
    }

    @Test
    fun `accuracy index stays within 0-4`() {
        assertEquals(0, engine.accuracyIndex)
        repeat(6) { climbOneRung(engine, offsetMinutes = it * 60L) }
        assertTrue(engine.accuracyIndex in 0..4)
        assertTrue(engine.throttleLevel <= 4, "the ladder is bounded")
    }

    @Test
    fun `reset clears the measurement baseline`() {
        engine.processSample(0.90, 0)
        engine.reset()
        assertNull(
            engine.processSample(0.75, 30 * MINUTE_MS),
            "after reset, the next sample is a fresh baseline",
        )
    }

    @Test
    fun `periodic interval is stretched when present`() {
        val periodicEngine = BatteryBudgetEngine(
            targetBudgetPerHour = 5.0,
            initialDistanceFilter = 50.0,
            initialAccuracyIndex = 0,
            initialPeriodicInterval = 900,
        )
        val event = climbOneRung(periodicEngine)
        assertNotNull(event)
        assertNotNull(event.newPeriodicInterval)
        assertTrue(event.newPeriodicInterval!! > 900, "should stretch the periodic interval")
    }

    @Test
    fun `periodic interval stays null when not periodic`() {
        val event = climbOneRung(engine)
        assertNotNull(event)
        assertNull(event.newPeriodicInterval, "non-periodic engine should have null interval")
    }

    @Test
    fun `budget adjustment event contains correct target`() {
        val event = climbOneRung(engine)
        assertNotNull(event)
        assertEquals(5.0, event.targetBudget)
    }

    @Test
    fun `the engine reports the resolution behind its own drain figure`() {
        engine.processSample(0.90, 0)
        engine.processSample(0.75, 30 * MINUTE_MS)
        val state = engine.throttleState
        assertEquals(1_800.0, state.lastMeasurementSeconds)
        assertEquals(QUANTUM * 2, state.lastMeasurementResolution, absoluteTolerance = 1e-9)
        assertEquals(30.0, state.lastDrain, absoluteTolerance = 1e-9)
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    /**
     * Two consecutive conclusive over-budget windows — the dwell one rung takes.
     *
     * 30 %/hr over half-hour windows, comfortably past the 2 %/hr such a window
     * can resolve on Android.
     */
    private fun climbOneRung(
        engine: BatteryBudgetEngine,
        offsetMinutes: Long = 0,
    ): BudgetAdjustmentEvent? {
        val base = offsetMinutes * MINUTE_MS
        engine.processSample(0.90, base)
        engine.processSample(0.75, base + 30 * MINUTE_MS)
        return engine.processSample(0.60, base + 60 * MINUTE_MS)
    }
}
