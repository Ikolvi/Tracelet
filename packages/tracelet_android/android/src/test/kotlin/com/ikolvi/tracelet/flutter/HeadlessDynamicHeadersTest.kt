package com.ikolvi.tracelet.flutter

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.TraceletHostApi
import com.ikolvi.tracelet.flutter.service.HeadlessTaskService
import com.ikolvi.tracelet.sdk.TraceletSdk
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.mockito.kotlin.whenever
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import uniffi.tracelet_core.EngineState
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Dynamic headers in a process the service started in the background, where
 * `bootstrapForBackground()` initializes the SDK and `ready()` never runs.
 *
 * The headless headers callback's `Tracelet.setDynamicHeaders()` reaches the
 * Pigeon host API. It must apply the headers to both stores native sync reads
 * (ConfigManager and the live Rust engine state), and complete the header
 * refresh of the [HeadlessTaskService] that spawned the isolate — not some
 * other instance — so the 401 retry in the same sync cycle uses them.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class HeadlessDynamicHeadersTest {

    private lateinit var context: Context
    private lateinit var sdk: TraceletSdk
    private lateinit var executor: ExecutorService
    private var engineState: EngineState? = null

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        sdk = TraceletSdk.getInstance(context)
        executor = Executors.newCachedThreadPool()
        setSdkField("isReady", false)
        setSdkField("rustEngineState", null)
        sdk.configManager.setDynamicHeaders(emptyMap())
        HeadlessTaskService.isSpawningHeadlessEngine = false
        HeadlessTaskService.spawningService = null
    }

    @After
    fun tearDown() {
        executor.shutdownNow()
        setSdkField("isReady", false)
        setSdkField("rustEngineState", null)
        engineState?.close()
        sdk.configManager.setDynamicHeaders(emptyMap())
        HeadlessTaskService.isSpawningHeadlessEngine = false
        HeadlessTaskService.spawningService = null
    }

    // -------------------------------------------------------------------------
    // Applying headers
    // -------------------------------------------------------------------------

    @Test
    fun `background-initialized SDK applies headers to ConfigManager and Rust state without ready()`() {
        val state = bootstrapCold()

        val reply = setDynamicHeaders(newHostApi(), BEARER_FRESH)

        assertEquals(true, reply)
        assertEquals("Bearer fresh", sdk.configManager.getMergedHttpHeaders()["Authorization"])
        assertEquals("Bearer fresh", state.getConfig().http.headers["Authorization"])
    }

    @Test
    fun `uninitialized SDK applies nothing and reports false`() {
        val reply = setDynamicHeaders(newHostApi(), BEARER_FRESH)

        assertEquals(false, reply)
        assertTrue(sdk.configManager.getDynamicHeaders().isEmpty())
    }

    @Test
    fun `ready SDK keeps the existing path`() {
        val state = bootstrapCold()
        setSdkField("isReady", true)

        val reply = setDynamicHeaders(newHostApi(), BEARER_FRESH)

        assertEquals(true, reply)
        assertEquals("Bearer fresh", sdk.configManager.getMergedHttpHeaders()["Authorization"])
        assertEquals("Bearer fresh", state.getConfig().http.headers["Authorization"])
    }

    // -------------------------------------------------------------------------
    // Completing the waiting refresh
    // -------------------------------------------------------------------------

    @Test
    fun `Pigeon header update completes the refresh of the service that spawned the engine`() {
        val state = bootstrapCold()
        val owner = registeredService()
        val other = registeredService()
        val messenger = attachHeadlessEngine(owner)

        val ownerWait = waitForRefresh(owner, 5_000L, HeadlessTaskService.HEADERS_REASON_TOKEN_REFRESH)
        val otherWait = waitForRefresh(other, 300L, HeadlessTaskService.HEADERS_REASON_TOKEN_REFRESH)

        val reply = messenger.setDynamicHeaders(BEARER_FRESH)

        assertEquals(true, reply)
        assertTrue(ownerWait.get(2, TimeUnit.SECONDS), "owner's refresh should complete")
        assertFalse(otherWait.get(2, TimeUnit.SECONDS), "another service's refresh must not be woken")
        // What the 401 retry reads once requestTokenRefresh() returns true.
        assertEquals("Bearer fresh", state.getConfig().http.headers["Authorization"])
    }

    @Test
    fun `refresh times out when the headers could not be applied`() {
        // No Rust core: nothing would read the headers, so nothing may report success.
        val owner = registeredService()
        val messenger = attachHeadlessEngine(owner)
        val wait = waitForRefresh(owner, 500L, HeadlessTaskService.HEADERS_REASON_TOKEN_REFRESH)

        val reply = messenger.setDynamicHeaders(BEARER_FRESH)

        assertEquals(false, reply)
        assertFalse(wait.get(2, TimeUnit.SECONDS))
    }

    @Test
    fun `a reply that arrives after the timeout does not complete a later refresh`() {
        bootstrapCold()
        val owner = registeredService()
        val messenger = attachHeadlessEngine(owner)

        assertFalse(waitForRefresh(owner, 200L, null).get(2, TimeUnit.SECONDS))
        // The late reply is still applied — the headers are fresh — but there is
        // no waiter left for it to complete.
        assertEquals(true, messenger.setDynamicHeaders(BEARER_FRESH))

        assertFalse(waitForRefresh(owner, 300L, null).get(2, TimeUnit.SECONDS))
    }

    @Test
    fun `headersRefresh event carries the reason`() {
        val owner = registeredService()

        val wait = waitForRefresh(owner, 200L, HeadlessTaskService.HEADERS_REASON_FRESH_HEADERS)
        wait.get(2, TimeUnit.SECONDS)

        val event = pendingEvents(owner).single { it["name"] == "headersRefresh" }
        assertEquals(mapOf("reason" to "freshHeaders"), event["event"])
    }

    @Test
    fun `headersRefresh event without a reason keeps the empty payload`() {
        val owner = registeredService()

        owner.requestHeadersRefreshOffMain(200L)

        val event = pendingEvents(owner).single { it["name"] == "headersRefresh" }
        assertEquals(emptyMap<String, Any?>(), event["event"])
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    /** A cold SDK after `bootstrapForBackground()`: Rust core up, `ready()` never called. */
    private fun bootstrapCold(): EngineState {
        val state = EngineState()
        engineState = state
        setSdkField("rustEngineState", state)
        setSdkField("isReady", false)
        return state
    }

    private fun setSdkField(name: String, value: Any?) {
        TraceletSdk::class.java.getDeclaredField(name).apply {
            isAccessible = true
            set(sdk, value)
        }
    }

    private fun newHostApi() = TraceletHostApiImpl(context, mock(HeadlessTaskService::class.java))

    private fun setDynamicHeaders(api: TraceletHostApiImpl, headers: Map<String, String>): Boolean? {
        var reply: Result<Boolean>? = null
        api.setDynamicHeaders(HashMap<String?, String?>(headers)) { reply = it }
        return reply!!.getOrThrow()
    }

    /** A service with a headless headers callback registered, as the app does. */
    private fun registeredService(): HeadlessTaskService =
        HeadlessTaskService(context).apply {
            registerCallbacks(HeadlessTaskService.CallbackType.HEADERS, 1L, 2L)
        }

    /**
     * Attaches the plugin to a headless engine the way `ensureEngine()` does:
     * inside the `FlutterEngine` constructor, with [owner] spawning it.
     */
    private fun attachHeadlessEngine(owner: HeadlessTaskService): CapturingMessenger {
        val messenger = CapturingMessenger()
        val binding = mock(FlutterPlugin.FlutterPluginBinding::class.java)
        whenever(binding.applicationContext).thenReturn(context)
        whenever(binding.binaryMessenger).thenReturn(messenger)
        HeadlessTaskService.isSpawningHeadlessEngine = true
        HeadlessTaskService.spawningService = owner
        try {
            TraceletAndroidPlugin().onAttachedToEngine(binding)
        } finally {
            HeadlessTaskService.isSpawningHeadlessEngine = false
            HeadlessTaskService.spawningService = null
        }
        return messenger
    }

    /**
     * Starts [HeadlessTaskService.requestHeadersRefresh] on a sync thread (it
     * refuses the main thread) and returns once its latch is armed, so a reply
     * sent afterwards cannot race ahead of the waiter.
     */
    private fun waitForRefresh(
        service: HeadlessTaskService,
        timeoutMs: Long,
        reason: String?,
    ): Future<Boolean> {
        val started = CountDownLatch(1)
        val future = executor.submit<Boolean> {
            started.countDown()
            service.requestHeadersRefresh(timeoutMs, reason)
        }
        started.await(2, TimeUnit.SECONDS)
        val deadline = System.currentTimeMillis() + 2_000L
        while (latchOf(service) == null && !future.isDone && System.currentTimeMillis() < deadline) {
            Thread.sleep(5)
        }
        return future
    }

    private fun HeadlessTaskService.requestHeadersRefreshOffMain(timeoutMs: Long): Boolean =
        executor.submit<Boolean> { requestHeadersRefresh(timeoutMs) }.get(2, TimeUnit.SECONDS)

    private fun latchOf(service: HeadlessTaskService): Any? =
        HeadlessTaskService::class.java.getDeclaredField("headersRefreshLatch").run {
            isAccessible = true
            get(service)
        }

    @Suppress("UNCHECKED_CAST")
    private fun pendingEvents(service: HeadlessTaskService): List<Map<String, Any?>> =
        HeadlessTaskService::class.java.getDeclaredField("pendingEvents").run {
            isAccessible = true
            (get(service) as Collection<Map<String, Any?>>).toList()
        }

    /** Records the handlers Pigeon registers so a test can deliver a real message. */
    private class CapturingMessenger : BinaryMessenger {
        private val handlers = mutableMapOf<String, BinaryMessenger.BinaryMessageHandler?>()

        override fun send(channel: String, message: ByteBuffer?) {}

        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {}

        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
            handlers[channel] = handler
        }

        /** Sends `TraceletHostApi.setDynamicHeaders` as the Dart platform does. */
        fun setDynamicHeaders(headers: Map<String, String>): Boolean? {
            val handler = handlers[SET_DYNAMIC_HEADERS_CHANNEL]
                ?: error("TraceletHostApi is not registered on this engine")
            val message = TraceletHostApi.codec.encodeMessage(listOf(headers))!!
            message.rewind()
            var reply: List<*>? = null
            handler.onMessage(message) { bytes ->
                bytes!!.rewind()
                reply = TraceletHostApi.codec.decodeMessage(bytes) as List<*>
            }
            return reply!!.single() as Boolean?
        }
    }

    private companion object {
        const val SET_DYNAMIC_HEADERS_CHANNEL =
            "dev.flutter.pigeon.tracelet_platform_interface.TraceletHostApi.setDynamicHeaders"
        val BEARER_FRESH = mapOf("Authorization" to "Bearer fresh")
    }
}
