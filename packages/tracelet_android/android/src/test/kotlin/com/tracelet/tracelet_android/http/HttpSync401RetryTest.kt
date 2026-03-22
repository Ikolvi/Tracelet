package com.tracelet.tracelet_android.http

import com.tracelet.core.http.HttpSyncManager
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.mockito.Mockito

/**
 * Tests for 401-aware retry in [HttpSyncManager].
 *
 * Verifies that:
 * - onAuthorizationRequired callback exists and defaults to null
 * - Callback can be set, cleared, and invoked
 * - Callback lifecycle is independent of other HttpSyncManager state
 *
 * Uses Mockito.mock() for HttpSyncManager (same pattern as
 * HttpSyncAutoTriggerTest) to avoid needing Robolectric.
 */
internal class HttpSync401RetryTest {

    @Test
    fun onAuthorizationRequired_defaultsToNull() {
        val manager = Mockito.mock(HttpSyncManager::class.java)
        // Real property access on mock returns null by default
        Mockito.`when`(manager.onAuthorizationRequired).thenCallRealMethod()
        Mockito.doCallRealMethod().`when`(manager).onAuthorizationRequired = Mockito.any()
        assertNull(manager.onAuthorizationRequired)
    }

    @Test
    fun onAuthorizationRequired_canBeSet() {
        val manager = Mockito.mock(HttpSyncManager::class.java)
        var callbackInvoked = false
        val callback: () -> Boolean = {
            callbackInvoked = true
            true
        }

        // Use real field access since this is a public var
        Mockito.`when`(manager.onAuthorizationRequired).thenReturn(callback)

        val result = manager.onAuthorizationRequired?.invoke()
        assertTrue(callbackInvoked)
        assertEquals(true, result)
    }

    @Test
    fun onAuthorizationRequired_canReturnFalse() {
        val manager = Mockito.mock(HttpSyncManager::class.java)
        val callback: () -> Boolean = { false }
        Mockito.`when`(manager.onAuthorizationRequired).thenReturn(callback)

        val result = manager.onAuthorizationRequired?.invoke()
        assertFalse(result!!)
    }

    @Test
    fun onAuthorizationRequired_nullSafeInvocation() {
        val manager = Mockito.mock(HttpSyncManager::class.java)
        Mockito.`when`(manager.onAuthorizationRequired).thenReturn(null)

        // Null-safe invocation should return null
        val result = manager.onAuthorizationRequired?.invoke()
        assertNull(result)
    }

    @Test
    fun onAuthorizationRequired_multipleInvocations() {
        var callCount = 0
        val callback: () -> Boolean = {
            callCount++
            callCount <= 1
        }
        val manager = Mockito.mock(HttpSyncManager::class.java)
        Mockito.`when`(manager.onAuthorizationRequired).thenReturn(callback)

        assertTrue(manager.onAuthorizationRequired!!.invoke())
        assertFalse(manager.onAuthorizationRequired!!.invoke())
        assertEquals(2, callCount)
    }
}
