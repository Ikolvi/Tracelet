package com.ikolvi.tracelet.flutter

import android.content.Context
import android.content.SharedPreferences
import com.ikolvi.tracelet.sdk.TraceletSdk
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import org.mockito.Mockito.clearInvocations
import org.mockito.Mockito.mock
import org.mockito.Mockito.never
import org.mockito.Mockito.verify
import org.mockito.Mockito.`when`
import org.mockito.kotlin.any
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Tests that the primary-instance guard in [TraceletAndroidPlugin] prevents
 * secondary FlutterEngine registrations from corrupting the SDK singleton.
 *
 * **Background**: When a plugin that spawns a background Dart isolate
 * (e.g. `FirebaseMessaging.onBackgroundMessage`) creates a temporary
 * FlutterEngine, `GeneratedPluginRegistrant` auto-registers ALL plugins
 * on that engine — including TraceletAndroidPlugin. Without a guard, the
 * secondary instance would:
 * 1. Replace the SDK's event sender with one connected to the wrong isolate
 * 2. Re-initialize all subsystems (LocationEngine, GeofenceManager, etc.)
 * 3. Call `sdk.destroyAll()` on detach — killing the foreground pipeline
 *
 * **Secondary engine discriminator** (Looper heuristic, issue #overlay):
 * When a secondary engine is an **in-process UI engine** (e.g.
 * `flutter_overlay_window` via `FlutterEngineGroup`), it attaches on the
 * main thread. The SDK's EventDispatcher must be re-bound to that engine's
 * messenger so Pigeon FlutterApi messages are delivered correctly.
 * When the secondary engine is a **headless background engine** (Firebase,
 * HeadlessTaskService), it attaches on a background thread and must be
 * fully skipped to preserve the #51 fix.
 *
 * These tests verify all three failure modes plus both discriminator branches.
 */
internal class PluginSecondaryEngineGuardTest {

    private lateinit var mockSdk: TraceletSdk

    @BeforeTest
    fun setUp() {
        // Reset the static primaryInstance before each test
        resetPrimaryInstance()
        // Default: simulate main-thread attach (primary engine behaviour)
        setIsMainThread(true)

        // Inject a mock TraceletSdk into the singleton field so that
        // TraceletSdk.getInstance(context) returns our mock without
        // needing mockStatic (avoids matcher issues).
        mockSdk = mock(TraceletSdk::class.java)
        // onAttachedToEngine logs via sdk.logger; the lazy property is null on a
        // Mockito mock, so stub it to a mock logger to avoid an NPE.
        `when`(mockSdk.logger).thenReturn(mock(com.ikolvi.tracelet.sdk.util.TraceletLogger::class.java))
        val instanceField = TraceletSdk::class.java.getDeclaredField("instance")
        instanceField.isAccessible = true
        instanceField.set(null, mockSdk)
    }

    @AfterTest
    fun tearDown() {
        // Clear the singleton so it doesn't leak between tests
        val instanceField = TraceletSdk::class.java.getDeclaredField("instance")
        instanceField.isAccessible = true
        instanceField.set(null, null)
        resetPrimaryInstance()
        // Restore production Looper check so other test classes are unaffected
        restoreIsMainThread()
    }

    // =========================================================================
    // Tests
    // =========================================================================

    /**
     * Primary (foreground) plugin instance should initialize the SDK
     * and set the event sender.
     */
    @Test
    fun primaryInstance_initializesSDK() {
        val primaryPlugin = TraceletAndroidPlugin()
        val primaryBinding = createMockBinding("primary")

        primaryPlugin.onAttachedToEngine(primaryBinding)

        verify(mockSdk).setEventSender(any())
        verify(mockSdk).initialize()
    }

    /**
     * #358: a headless background engine must not join the event fan-out.
     *
     * `EventDispatcher` decides "can a Flutter engine receive this?" by whether
     * its Pigeon `eventApi` is non-null, and `register()` sets that for any
     * messenger. Registering a headless engine therefore made every subsequent
     * event take the engine branch and post into an isolate with no listener,
     * instead of falling through to `headlessFallback` — the headless task
     * receives events through `dispatchEvent`, a different channel. One
     * transient headless engine (spawned for a sync body, say) silently
     * swallowed every geofence crossing for the rest of the process.
     */
    @Test
    fun headlessSecondaryEngine_doesNotJoinTheEventFanOut() {
        val primaryPlugin = TraceletAndroidPlugin()
        primaryPlugin.onAttachedToEngine(createMockBinding("primary"))
        val afterPrimary = globalDispatcherCount()

        // A headless engine attaches on a background thread.
        setIsMainThread(false)
        TraceletAndroidPlugin().onAttachedToEngine(createMockBinding("headless"))

        assertEquals(
            afterPrimary,
            globalDispatcherCount(),
            "a headless engine must not be added to the fan-out, or it swallows " +
                "events the headless task should have received",
        )
    }

    /**
     * The other half: an in-process *UI* engine (EngineGroup, e.g. an overlay)
     * attaches on the main thread and genuinely can display events, so it must
     * still receive them.
     */
    @Test
    fun uiSecondaryEngine_joinsTheEventFanOut() {
        val primaryPlugin = TraceletAndroidPlugin()
        primaryPlugin.onAttachedToEngine(createMockBinding("primary"))
        val afterPrimary = globalDispatcherCount()

        setIsMainThread(true)
        TraceletAndroidPlugin().onAttachedToEngine(createMockBinding("overlay"))

        assertEquals(
            afterPrimary + 1,
            globalDispatcherCount(),
            "an in-process UI engine must still receive events",
        )
    }

    /**
     * When multiple engines attach, the SDK should only be initialized once
     * (by the first engine).
     */
    @Test
    fun multipleEngines_initializeOnce() {
        val plugin1 = TraceletAndroidPlugin()
        val plugin2 = TraceletAndroidPlugin()

        val binding1 = createMockBinding("engine1")
        val binding2 = createMockBinding("engine2")

        plugin1.onAttachedToEngine(binding1)
        verify(mockSdk).initialize()
        clearInvocations(mockSdk)

        plugin2.onAttachedToEngine(binding2)
        verify(mockSdk, never()).initialize()
    }

    /**
     * When one of multiple engines detaches, the SDK must NOT be destroyed.
     */
    @Test
    fun partialDetach_doesNotDestroySDK() {
        val plugin1 = TraceletAndroidPlugin()
        val plugin2 = TraceletAndroidPlugin()

        val binding1 = createMockBinding("engine1")
        val binding2 = createMockBinding("engine2")

        plugin1.onAttachedToEngine(binding1)
        plugin2.onAttachedToEngine(binding2)
        clearInvocations(mockSdk)

        // Detach one engine
        plugin2.onDetachedFromEngine(binding2)

        // SDK must NOT be destroyed because engine1 is still attached
        verify(mockSdk, never()).destroyAll()
    }

    /**
     * When the last engine detaches, the SDK SHOULD be destroyed.
     */
    @Test
    fun lastDetach_destroysSDK() {
        val plugin1 = TraceletAndroidPlugin()
        val plugin2 = TraceletAndroidPlugin()

        val binding1 = createMockBinding("engine1")
        val binding2 = createMockBinding("engine2")

        plugin1.onAttachedToEngine(binding1)
        plugin2.onAttachedToEngine(binding2)
        clearInvocations(mockSdk)

        // Detach all engines
        plugin1.onDetachedFromEngine(binding1)
        verify(mockSdk, never()).destroyAll()

        plugin2.onDetachedFromEngine(binding2)
        verify(mockSdk).destroyAll()
    }

    /**
     * Full lifecycle: primary attaches → secondary attaches →
     * secondary detaches → primary still works.
     */
    @Test
    fun fullLifecycle_referenceCountingWorks() {
        val primaryPlugin = TraceletAndroidPlugin()
        val secondaryPlugin = TraceletAndroidPlugin()

        val primaryBinding = createMockBinding("primary")
        val secondaryBinding = createMockBinding("secondary")

        // 1. Primary attaches
        primaryPlugin.onAttachedToEngine(primaryBinding)
        verify(mockSdk).setEventSender(any())
        verify(mockSdk).initialize()

        // 2. Secondary attaches
        clearInvocations(mockSdk)
        secondaryPlugin.onAttachedToEngine(secondaryBinding)
        verify(mockSdk, never()).initialize()

        // 3. Secondary detaches
        secondaryPlugin.onDetachedFromEngine(secondaryBinding)
        verify(mockSdk, never()).destroyAll()

        // 4. Primary is still alive — detach it normally
        primaryPlugin.onDetachedFromEngine(primaryBinding)
        verify(mockSdk).destroyAll()
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    private fun createMockBinding(label: String): FlutterPlugin.FlutterPluginBinding {
        val messenger = mock(BinaryMessenger::class.java)
        val context = mock(Context::class.java)
        val headlessPrefs = mock(SharedPreferences::class.java)
        val headlessEditor = mock(SharedPreferences.Editor::class.java)

        `when`(context.applicationContext).thenReturn(context)
        `when`(context.getSharedPreferences(any(), any<Int>())).thenReturn(headlessPrefs)
        `when`(headlessPrefs.edit()).thenReturn(headlessEditor)
        `when`(headlessPrefs.contains(any())).thenReturn(false)
        `when`(headlessPrefs.getLong(any(), any())).thenReturn(-1L)

        val binding = mock(FlutterPlugin.FlutterPluginBinding::class.java)
        `when`(binding.binaryMessenger).thenReturn(messenger)
        `when`(binding.applicationContext).thenReturn(context)

        return binding
    }

    /**
     * Resets the companion object's static fields via reflection.
     */
    private fun resetPrimaryInstance() {
        val field1 = TraceletAndroidPlugin::class.java.getDeclaredField("primaryInstance")
        field1.isAccessible = true
        field1.set(null, null)

        val field2 = TraceletAndroidPlugin::class.java.getDeclaredField("attachedEngineCount")
        field2.isAccessible = true
        val counter = field2.get(null) as java.util.concurrent.atomic.AtomicInteger
        counter.set(0)
    }

    private fun restoreIsMainThread() {
        val field = TraceletAndroidPlugin::class.java.getDeclaredField("isMainThread")
        field.isAccessible = true
        field.set(null, {
            android.os.Looper.myLooper() == android.os.Looper.getMainLooper()
        })
    }

    private fun setIsMainThread(value: Boolean) {
        val field = TraceletAndroidPlugin::class.java.getDeclaredField("isMainThread")
        field.isAccessible = true
        field.set(null, { value })
    }

    /** Number of dispatchers currently in the global event fan-out. */
    private fun globalDispatcherCount(): Int {
        val senderField = TraceletAndroidPlugin::class.java.getDeclaredField("globalEventSender")
        senderField.isAccessible = true
        val sender = senderField.get(null)
        val listField = sender.javaClass.getDeclaredField("dispatchers")
        listField.isAccessible = true
        return (listField.get(sender) as java.util.List<*>).size
    }
}
