package com.ikolvi.tracelet.sdk.sync

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * #437: auto-sync uploaded one batch per inserted location and dropped any
 * request made while a sync was running, so with `maxBatchSize: 1` the queue
 * could never shrink, and a parked device never caught up.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class AutoSyncDrainerTest {

    /** A queue of rows uploaded `batchSize` at a time. */
    private class FakeQueue(var rows: Int, private val batchSize: Int = 1) {
        var uploads = 0
        var fail = false
        var gate: CompletableDeferred<Unit>? = null

        suspend fun upload(): Int {
            gate?.await()
            uploads++
            if (fail || rows == 0) return 0
            val n = minOf(batchSize, rows)
            rows -= n
            return n
        }
    }

    private fun TestScope.drainer(queue: FakeQueue): AutoSyncDrainer =
        AutoSyncDrainer(
            CoroutineScope(SupervisorJob() + StandardTestDispatcher(testScheduler)),
            Mutex(),
            queue::upload,
        )

    @Test
    fun `one request drains the whole queue, one row per batch`() = runTest {
        val queue = FakeQueue(rows = 7, batchSize = 1)
        val drainer = drainer(queue)

        drainer.request(delayMs = 1_000)
        advanceUntilIdle()

        assertEquals(0, queue.rows)
        assertFalse(drainer.isActive)
    }

    @Test
    fun `a request made during an in-flight upload is not lost`() = runTest {
        val queue = FakeQueue(rows = 1)
        queue.gate = CompletableDeferred()
        val drainer = drainer(queue)

        drainer.request(delayMs = 0)
        testScheduler.advanceTimeBy(1)
        testScheduler.runCurrent()
        assertTrue("upload is in flight", drainer.isActive)

        // Two fixes stored while the request is outstanding.
        queue.rows += 2
        drainer.request(delayMs = 0)
        queue.gate!!.complete(Unit)
        advanceUntilIdle()

        assertEquals(0, queue.rows)
        assertFalse(drainer.isActive)
    }

    @Test
    fun `a failed batch ends the run instead of retrying in a loop`() = runTest {
        val queue = FakeQueue(rows = 5).apply { fail = true }
        val drainer = drainer(queue)

        drainer.request(delayMs = 0)
        advanceUntilIdle()

        assertEquals("one attempt, then wait for the next request", 1, queue.uploads)
        assertEquals(5, queue.rows)
        assertFalse(drainer.isActive)
    }

    @Test
    fun `a backlog longer than one run continues without a new insert`() = runTest {
        val rows = AutoSyncDrainer.MAX_BATCHES_PER_RUN * 2 + 3
        val queue = FakeQueue(rows = rows)
        val drainer = drainer(queue)

        drainer.request(delayMs = 500)
        advanceUntilIdle()

        assertEquals(0, queue.rows)
    }

    @Test
    fun `cancel stops a scheduled drain`() = runTest {
        val queue = FakeQueue(rows = 3)
        val drainer = drainer(queue)

        drainer.request(delayMs = 10_000)
        drainer.cancel()
        advanceUntilIdle()

        assertEquals(0, queue.uploads)
        assertEquals(3, queue.rows)
        assertFalse(drainer.isActive)
    }

    @Test
    fun `a throwing upload is contained and a later request still runs`() = runTest {
        var throwOnce = true
        var rows = 2
        val drainer = AutoSyncDrainer(
            CoroutineScope(SupervisorJob() + StandardTestDispatcher(testScheduler)),
            Mutex(),
            {
                if (throwOnce) {
                    throwOnce = false
                    error("boom")
                }
                if (rows > 0) { rows--; 1 } else 0
            },
        )

        drainer.request(0)
        advanceUntilIdle()
        assertFalse(drainer.isActive)

        drainer.request(0)
        advanceUntilIdle()
        assertEquals(0, rows)
    }
}

class SyncRetryPolicyTest {

    @Test
    fun `backoff doubles from the base and stops at the cap`() {
        assertEquals(500L, SyncRetryPolicy.backoffMs(0, 500, 15_000))
        assertEquals(1_000L, SyncRetryPolicy.backoffMs(1, 500, 15_000))
        assertEquals(8_000L, SyncRetryPolicy.backoffMs(4, 500, 15_000))
        assertEquals(15_000L, SyncRetryPolicy.backoffMs(5, 500, 15_000))
        assertEquals(15_000L, SyncRetryPolicy.backoffMs(60, 500, 15_000))
    }

    @Test
    fun `unset values fall back to sane defaults`() {
        assertEquals(60_000, SyncRetryPolicy.timeoutMs(0))
        assertEquals(30_000, SyncRetryPolicy.timeoutMs(30_000))
        assertEquals(1_000L, SyncRetryPolicy.backoffMs(0, 0, 0))
    }

    @Test
    fun `a read timeout after the body was sent is not retried`() {
        val timeout = java.net.SocketTimeoutException("Read timed out")
        assertFalse(SyncRetryPolicy.mayRetry(timeout, bodyWritten = true))
        assertTrue(SyncRetryPolicy.mayRetry(timeout, bodyWritten = false))
        assertTrue(SyncRetryPolicy.mayRetry(java.io.IOException("reset"), bodyWritten = true))
    }
}
