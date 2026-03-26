package com.ikolvi.tracelet.flutter.http

import com.ikolvi.tracelet.sdk.http.HttpSyncManager
import com.ikolvi.tracelet.sdk.location.PeriodicLocationWorker
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Tests for the HTTP auto-sync trigger wiring.
 *
 * Verifies that:
 * - PeriodicLocationWorker has a static httpSyncManager reference
 * - The reference lifecycle (set/clear/replace) works correctly
 *
 * Full integration tests (LocationEngine → httpSyncManager.onLocationInserted)
 * require a real FusedLocationProvider and run on-device.
 */
internal class HttpSyncAutoTriggerTest {

    // ── PeriodicLocationWorker.httpSyncManager static reference ──────────

    @Test
    fun httpSyncManager_defaultsToNull() {
        PeriodicLocationWorker.httpSyncManager = null
        assertNull(PeriodicLocationWorker.httpSyncManager)
    }

    @Test
    fun httpSyncManager_canBeSetAndRead() {
        val manager = Mockito.mock(HttpSyncManager::class.java)
        try {
            PeriodicLocationWorker.httpSyncManager = manager
            assertEquals(manager, PeriodicLocationWorker.httpSyncManager)
        } finally {
            PeriodicLocationWorker.httpSyncManager = null
        }
    }

    @Test
    fun httpSyncManager_canBeResetToNull() {
        val manager = Mockito.mock(HttpSyncManager::class.java)
        PeriodicLocationWorker.httpSyncManager = manager
        PeriodicLocationWorker.httpSyncManager = null
        assertNull(PeriodicLocationWorker.httpSyncManager)
    }

    @Test
    fun httpSyncManager_multipleAssignments() {
        val m1 = Mockito.mock(HttpSyncManager::class.java)
        val m2 = Mockito.mock(HttpSyncManager::class.java)
        try {
            PeriodicLocationWorker.httpSyncManager = m1
            assertEquals(m1, PeriodicLocationWorker.httpSyncManager)

            PeriodicLocationWorker.httpSyncManager = m2
            assertEquals(m2, PeriodicLocationWorker.httpSyncManager)
        } finally {
            PeriodicLocationWorker.httpSyncManager = null
        }
    }

    @Test
    fun httpSyncManager_independentOfEventDispatcher() {
        val manager = Mockito.mock(HttpSyncManager::class.java)
        try {
            PeriodicLocationWorker.httpSyncManager = manager
            PeriodicLocationWorker.eventSender = null
            // httpSyncManager should remain after clearing eventDispatcher
            assertEquals(manager, PeriodicLocationWorker.httpSyncManager)
        } finally {
            PeriodicLocationWorker.httpSyncManager = null
            PeriodicLocationWorker.eventSender = null
        }
    }
}
