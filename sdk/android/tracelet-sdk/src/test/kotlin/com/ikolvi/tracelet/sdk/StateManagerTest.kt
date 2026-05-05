package com.ikolvi.tracelet.sdk

import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import com.ikolvi.tracelet.sdk.model.TrackingMode
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

@RunWith(RobolectricTestRunner::class)
class StateManagerTest {

    @Test
    fun `default state is disabled`() {
        val context = RuntimeEnvironment.getApplication()
        val state = StateManager(context)
        assertFalse(state.enabled)
        assertFalse(state.isMoving)
        assertFalse(state.schedulerEnabled)
        assertEquals(TrackingMode.CONTINUOUS, state.trackingMode)
        assertEquals(0.0, state.odometer)
    }

    @Test
    fun `enabled state persists`() {
        val context = RuntimeEnvironment.getApplication()
        val state = StateManager(context)
        state.enabled = true
        assertTrue(state.enabled)
    }

    @Test
    fun `tracking mode persists`() {
        val context = RuntimeEnvironment.getApplication()
        val state = StateManager(context)
        state.trackingMode = TrackingMode.PERIODIC
        assertEquals(TrackingMode.PERIODIC, state.trackingMode)
    }

    @Test
    fun `odometer accumulates`() {
        val context = RuntimeEnvironment.getApplication()
        val state = StateManager(context)
        state.odometer = 0.0
        state.addOdometer(100.0)
        state.addOdometer(50.5)
        assertEquals(150.5, state.odometer, 0.001)
    }

    @Test
    fun `toMap includes all fields`() {
        val context = RuntimeEnvironment.getApplication()
        val state = StateManager(context)
        state.enabled = true
        state.trackingMode = TrackingMode.GEOFENCES
        state.isMoving = true
        state.odometer = 42.0

        val map = state.toMap()
        assertEquals(true, map["enabled"])
        assertEquals(1, map["trackingMode"])
        assertEquals(true, map["isMoving"])
        assertEquals(42.0, map["odometer"])
    }

    @Test
    fun `reset clears all state`() {
        val context = RuntimeEnvironment.getApplication()
        val state = StateManager(context)
        state.enabled = true
        state.isMoving = true
        state.odometer = 100.0

        state.reset()

        assertFalse(state.enabled)
        assertFalse(state.isMoving)
        assertEquals(0.0, state.odometer)
    }
}
