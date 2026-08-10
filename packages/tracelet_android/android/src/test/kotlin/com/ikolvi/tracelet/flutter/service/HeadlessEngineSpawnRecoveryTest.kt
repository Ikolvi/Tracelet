package com.ikolvi.tracelet.flutter.service

import android.content.Context
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowSystemClock
import java.time.Duration
import java.util.concurrent.LinkedBlockingQueue
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Regression tests for #331 — the headless task was intermittently never
 * invoked after task removal, and the failure was completely silent: no engine,
 * no error at any log level, events accumulating in `pendingEvents` forever.
 *
 * These drive the real [HeadlessTaskService]. Under Robolectric a FlutterEngine
 * cannot actually be created, which is what makes the failure handling itself
 * testable: the spawn attempt fails the way a device's would.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class HeadlessEngineSpawnRecoveryTest {

    private lateinit var context: Context

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        HeadlessTaskService.isSpawningHeadlessEngine = false
        // Callbacks registered, exactly as registerHeadlessTask() leaves them.
        context.getSharedPreferences("com.tracelet.headless", Context.MODE_PRIVATE)
            .edit()
            .putLong("registration_callback_id", 42L)
            .putLong("dispatch_callback_id", 43L)
            .apply()
    }

    @Suppress("UNCHECKED_CAST")
    private fun pendingEvents(service: HeadlessTaskService): LinkedBlockingQueue<Map<String, Any?>> {
        val f = HeadlessTaskService::class.java.getDeclaredField("pendingEvents")
        f.isAccessible = true
        return f.get(service) as LinkedBlockingQueue<Map<String, Any?>>
    }

    private fun spawnStage(service: HeadlessTaskService): Any {
        val f = HeadlessTaskService::class.java.getDeclaredField("spawnStage")
        f.isAccessible = true
        return f.get(service)
    }

    /**
     * A spawn that fails must not take the queued events with it. They are the
     * reason the engine was being spawned; the next attempt has to deliver them.
     */
    @Test
    fun `a failed spawn keeps its queued events for the next attempt`() {
        val service = HeadlessTaskService(context)
        assertTrue(service.isRegistered(), "precondition: headless callbacks registered")

        service.dispatchEvent("location", mapOf("i" to 0))
        shadowOf(Looper.getMainLooper()).idle() // the spawn attempt runs and fails

        repeat(9) { i -> service.dispatchEvent("location", mapOf("i" to i + 1)) }
        shadowOf(Looper.getMainLooper()).idle()

        assertEquals(
            10,
            pendingEvents(service).size,
            "every event must survive a failed spawn — destroy() used to clear them",
        )
    }

    /**
     * The reported failure was permanent. After a spawn that never completes,
     * the service must give up on it and be spawnable again rather than treating
     * a half-built engine as proof that one exists.
     */
    @Test
    fun `a stalled spawn is abandoned and retried instead of stranding events`() {
        val service = HeadlessTaskService(context)

        // Post the spawn but never run it — the failing device log shows no
        // main-thread work at all after the swipe.
        service.dispatchEvent("location", mapOf("i" to 0))
        assertEquals(
            HeadlessTaskService.SpawnStage.POSTED,
            spawnStage(service),
            "the spawn is in flight and knows how far it got",
        )

        ShadowSystemClock.advanceBy(
            Duration.ofMillis(HeadlessTaskService.ENGINE_SPAWN_TIMEOUT_MS + 1),
        )

        // The next event notices the stall, reports it, and starts over.
        service.dispatchEvent("location", mapOf("i" to 1))
        assertEquals(
            HeadlessTaskService.SpawnStage.POSTED,
            spawnStage(service),
            "a fresh spawn was started rather than the stalled one being trusted forever",
        )
        assertEquals(
            2,
            pendingEvents(service).size,
            "the retry keeps everything buffered so far",
        )
    }

    /**
     * The queue was unbounded: a continuous config appends one entry every 2 s
     * for as long as the process lives.
     */
    @Test
    fun `the pending queue is capped rather than growing without limit`() {
        val service = HeadlessTaskService(context)

        repeat(HeadlessTaskService.MAX_PENDING_EVENTS + 50) { i ->
            service.dispatchEvent("location", mapOf("i" to i))
        }

        val queue = pendingEvents(service)
        assertEquals(
            HeadlessTaskService.MAX_PENDING_EVENTS,
            queue.size,
            "the queue must stop at its cap",
        )
        @Suppress("UNCHECKED_CAST")
        val oldest = queue.peek()?.get("event") as? Map<String, Any?>
        assertEquals(
            50,
            oldest?.get("i"),
            "eviction is oldest-first, so the freshest events are the ones kept",
        )
    }
}
