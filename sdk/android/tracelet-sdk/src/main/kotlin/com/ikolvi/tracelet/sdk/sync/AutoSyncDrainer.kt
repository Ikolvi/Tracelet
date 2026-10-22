package com.ikolvi.tracelet.sdk.sync

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Drives auto-sync for a sync provider: uploads batch after batch until the
 * queue is empty, and never loses a request (#437).
 *
 * Both providers used to upload exactly one batch per inserted location, and
 * returned early when a job was already running — a job that covered the
 * debounce *and* the HTTP request with all its retries. So a location stored
 * during a request scheduled nothing, and a queue could only shrink by one
 * batch per later insert. With `maxBatchSize: 1` it never shrank at all: the
 * server replayed the route one point per new fix, and a parked device, which
 * inserts nothing, never caught up.
 *
 * A request now sets a flag the running job re-checks before it finishes, so
 * a request made at any moment is served; and each run drains until a batch
 * comes back empty or fails. A failure stops the run without retrying in a
 * loop — the next request tries again, so a down server is not hammered.
 *
 * @param uploadOneBatch uploads the oldest batch and clears it; returns the
 *   number of rows cleared, `0` when the queue is empty or the upload failed.
 */
class AutoSyncDrainer(
    private val scope: CoroutineScope,
    private val mutex: Mutex,
    private val uploadOneBatch: suspend () -> Int,
    private val log: (String) -> Unit = {},
) {
    private val lock = Any()
    private var job: Job? = null
    private var requested = false

    /** Whether a drain is scheduled or running. */
    val isActive: Boolean get() = synchronized(lock) { job != null }

    /**
     * Asks for a drain after [delayMs]. If one is already scheduled or running
     * it picks the request up before finishing, so nothing is dropped.
     */
    fun request(delayMs: Long) {
        synchronized(lock) {
            requested = true
            if (job != null) return
            job = scope.launch { run(delayMs.coerceAtLeast(0)) }
        }
    }

    /** Cancels a scheduled or running drain and forgets pending requests. */
    fun cancel() {
        synchronized(lock) {
            job?.cancel()
            job = null
            requested = false
        }
    }

    private suspend fun run(delayMs: Long) {
        try {
            while (true) {
                delay(delayMs)
                synchronized(lock) { requested = false }
                drain()
                synchronized(lock) {
                    if (!requested) {
                        job = null
                        return
                    }
                }
            }
        } catch (ce: CancellationException) {
            throw ce
        } catch (t: Throwable) {
            // Contained: a throwing iteration must not end auto-sync (#134).
            log("auto-sync drain failed (contained): ${t.message}")
            synchronized(lock) { job = null }
        }
    }

    private suspend fun drain() {
        mutex.withLock {
            var batches = 0
            while (batches < MAX_BATCHES_PER_RUN) {
                currentCoroutineContext().ensureActive()
                if (uploadOneBatch() <= 0) return
                batches++
            }
            // Rows may remain: hand the rest to another run rather than hold
            // the lock (and a background execution window) indefinitely.
            log("auto-sync: $batches batches uploaded, continuing in the next run")
            synchronized(lock) { requested = true }
        }
    }

    companion object {
        /** Batches per run before yielding the lock; the run then continues. */
        const val MAX_BATCHES_PER_RUN = 50
    }
}

/**
 * Timeouts and retry spacing for the custom-body HTTP path, which used fixed
 * 15 s timeouts and a fixed `1 s × attempt` delay whatever the config said
 * (#437).
 */
object SyncRetryPolicy {
    /** `HttpConfig.httpTimeout`, or 60 s when unset. */
    fun timeoutMs(httpTimeout: Int): Int = if (httpTimeout > 0) httpTimeout else 60_000

    /**
     * Exponential backoff from `retryBackoffBase`, capped at `retryBackoffCap`:
     * the same spacing the default (Rust) path already uses.
     */
    fun backoffMs(attempt: Int, base: Int, cap: Int): Long {
        val b = if (base > 0) base.toLong() else 1_000L
        val c = if (cap > 0) cap.toLong() else 60_000L
        val shift = attempt.coerceIn(0, 20)
        return minOf(c, b shl shift)
    }

    /**
     * Whether a failed attempt may be retried. A read timeout once the whole
     * body was sent means the server may already be processing the batch; a
     * retry would deliver it twice, so it is left for the next sync instead.
     */
    fun mayRetry(error: Throwable, bodyWritten: Boolean): Boolean =
        !(bodyWritten && error is java.net.SocketTimeoutException)
}
