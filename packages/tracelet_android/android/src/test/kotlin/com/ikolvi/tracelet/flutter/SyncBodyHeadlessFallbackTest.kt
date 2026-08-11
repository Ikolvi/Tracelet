package com.ikolvi.tracelet.flutter

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.flutter.service.HeadlessTaskService
import com.ikolvi.tracelet.sdk.TraceletSdk
import com.ikolvi.tracelet.sdk.sync.NO_SYNC_BODY_BUILDER_SENTINEL
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.mockito.Mockito.`when`
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Regression tests for #340 — the same app posted its own sync body on Android
 * and the SDK default on iOS.
 *
 * `hasCustomSyncBodyBuilder` only ever reflects the **foreground** isolate. A
 * process whose Dart never ran the app code that calls `setSyncBodyBuilder` —
 * a background relaunch, or an app opened but not yet through its own init —
 * reads `false` there even when `registerHeadlessSyncBodyBuilder` is registered
 * and perfectly usable. That branch returned the sentinel before the
 * headless routing further down could be reached, so the device posted the
 * default payload with a custom builder sitting available in preferences.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SyncBodyHeadlessFallbackTest {

    private lateinit var context: Context
    private lateinit var mockSdk: TraceletSdk

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        resetPluginStatics()
        HeadlessTaskService.isSpawningHeadlessEngine = false
        TraceletAndroidPlugin.hasCustomSyncBodyBuilder = false

        // A mock SDK singleton: attaching as the primary instance otherwise
        // runs the real initialize(), which needs the native core.
        mockSdk = mock(TraceletSdk::class.java)
        `when`(mockSdk.logger).thenReturn(mock(com.ikolvi.tracelet.sdk.util.TraceletLogger::class.java))
        sdkInstanceField().set(null, mockSdk)
    }

    @After
    fun tearDown() {
        sdkInstanceField().set(null, null)
        resetPluginStatics()
        TraceletAndroidPlugin.hasCustomSyncBodyBuilder = false
    }

    private fun sdkInstanceField() =
        TraceletSdk::class.java.getDeclaredField("instance").apply { isAccessible = true }

    private fun resetPluginStatics() {
        TraceletAndroidPlugin::class.java.getDeclaredField("primaryInstance")
            .apply { isAccessible = true }
            .set(null, null)
        val counter = TraceletAndroidPlugin::class.java.getDeclaredField("attachedEngineCount")
            .apply { isAccessible = true }
            .get(null) as java.util.concurrent.atomic.AtomicInteger
        counter.set(0)
    }

    private fun registerHeadlessSyncBodyBuilder() {
        context.getSharedPreferences("com.tracelet.headless", Context.MODE_PRIVATE)
            .edit()
            .putLong("headlessSyncBody_registrationId", 7L)
            .putLong("headlessSyncBody_dispatchId", 8L)
            .apply()
    }

    private fun attachedPlugin(): TraceletAndroidPlugin {
        val binding = mock(FlutterPlugin.FlutterPluginBinding::class.java)
        `when`(binding.applicationContext).thenReturn(context)
        `when`(binding.binaryMessenger).thenReturn(mock(BinaryMessenger::class.java))
        return TraceletAndroidPlugin().also { it.onAttachedToEngine(binding) }
    }

    @Test
    fun `the headless sync-body registration is readable without touching the SDK`() {
        val service = HeadlessTaskService(context)
        assertFalse(
            service.isSyncBodyBuilderRegistered(),
            "nothing registered yet",
        )

        registerHeadlessSyncBodyBuilder()
        assertTrue(
            service.isSyncBodyBuilderRegistered(),
            "both callback ids are persisted, so the builder is reachable",
        )
    }

    /**
     * The #125 guarantee: with nothing registered anywhere, the sentinel comes
     * back immediately rather than after a channel timeout, so the sync posts
     * the default payload instead of aborting.
     */
    @Test
    fun `no builder anywhere still returns the sentinel immediately`() {
        val plugin = attachedPlugin()

        assertEquals(
            NO_SYNC_BODY_BUILDER_SENTINEL,
            plugin.requestSyncBody(emptyList()),
            "no foreground builder and no headless builder — nothing to route to",
        )
    }

    /**
     * #340: a registered headless builder must be consulted before the default
     * payload is posted. Before the fix this returned the sentinel in
     * microseconds; now the call reaches the headless service and waits there
     * for the Dart response, which no engine can deliver in a unit test.
     */
    @Test
    fun `a registered headless builder is consulted when the foreground one is absent`() {
        registerHeadlessSyncBodyBuilder()
        val plugin = attachedPlugin()

        val returned = AtomicReference<String?>(null)
        val done = java.util.concurrent.CountDownLatch(1)
        // Off the test thread: the headless path blocks on its response latch,
        // and requestCustomSyncBody refuses to run on the main thread at all.
        val caller = Thread {
            try {
                returned.set(plugin.requestSyncBody(emptyList()))
            } catch (_: InterruptedException) {
                // Expected when the test releases it below.
            } finally {
                done.countDown()
            }
        }
        caller.isDaemon = true
        caller.start()

        val finished = done.await(1, TimeUnit.SECONDS)
        caller.interrupt()

        assertFalse(
            finished,
            "requestSyncBody returned ${returned.get()} straight away — it took the " +
                "default-payload branch instead of the registered headless builder",
        )
    }
}
