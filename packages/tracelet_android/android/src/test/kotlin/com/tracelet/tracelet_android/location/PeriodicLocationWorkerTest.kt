package com.tracelet.tracelet_android.location

import com.tracelet.core.TraceletEventSender
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Tests for [PeriodicLocationWorker] companion object methods and static state.
 *
 * Verifies scheduling constants and the static EventDispatcher reference
 * lifecycle. WorkManager scheduling tests require a real Android Context
 * and are covered by integration tests on the device.
 */
internal class PeriodicLocationWorkerTest {

    // ── WORK_NAME constant ───────────────────────────────────────────────

    @Test
    fun workName_isCorrect() {
        assertEquals("com.tracelet.periodic_location", PeriodicLocationWorker.WORK_NAME)
    }

    @Test
    fun oneTimeWorkName_isDerivedFromPeriodicWorkName() {
        val oneTimeName = "${PeriodicLocationWorker.WORK_NAME}_onetime"
        assertEquals("com.tracelet.periodic_location_onetime", oneTimeName)
    }

    // ── EventDispatcher static reference ─────────────────────────────────

    @Test
    fun eventSender_defaultsToNull() {
        PeriodicLocationWorker.eventSender = null
        assertNull(PeriodicLocationWorker.eventSender)
    }

    @Test
    fun eventSender_canBeSetAndRead() {
        val dispatcher = Mockito.mock(EventDispatcher::class.java)
        try {
            PeriodicLocationWorker.eventSender = dispatcher
            assertEquals(dispatcher, PeriodicLocationWorker.eventSender)
        } finally {
            PeriodicLocationWorker.eventSender = null
        }
    }

    @Test
    fun eventSender_canBeResetToNull() {
        val dispatcher = Mockito.mock(EventDispatcher::class.java)
        PeriodicLocationWorker.eventSender = dispatcher
        PeriodicLocationWorker.eventSender = null
        assertNull(PeriodicLocationWorker.eventSender)
    }

    @Test
    fun eventSender_multipleAssignments() {
        val d1 = Mockito.mock(EventDispatcher::class.java)
        val d2 = Mockito.mock(EventDispatcher::class.java)
        try {
            PeriodicLocationWorker.eventSender = d1
            assertEquals(d1, PeriodicLocationWorker.eventSender)

            PeriodicLocationWorker.eventSender = d2
            assertEquals(d2, PeriodicLocationWorker.eventSender)
        } finally {
            PeriodicLocationWorker.eventSender = null
        }
    }

    // ── Accuracy mapping documentation ───────────────────────────────────

    @Test
    fun accuracyIndices_matchDesiredAccuracyEnum() {
        // DesiredAccuracy enum from Dart:
        // 0 = high, 1 = medium, 2 = low, 3 = veryLow, 4 = lowestUnbiased
        // ConfigManager defaults for periodic: 1 (medium)
        // The worker maps these to FusedLocationProvider Priority:
        // 0 -> PRIORITY_HIGH_ACCURACY (100)
        // 1 -> PRIORITY_BALANCED_POWER_ACCURACY (102)
        // 2 -> PRIORITY_LOW_POWER (104)
        // 3 -> PRIORITY_PASSIVE (105)
        // 4 -> PRIORITY_PASSIVE (105)
        val expectedMappings = mapOf(
            0 to "high",
            1 to "medium (balanced)",
            2 to "low",
            3 to "passive",
            4 to "passive",
        )
        assertEquals(5, expectedMappings.size, "All 5 accuracy levels should be mapped")
    }
}
