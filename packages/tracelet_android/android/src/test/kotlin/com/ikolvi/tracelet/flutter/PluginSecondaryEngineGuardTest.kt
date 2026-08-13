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
import kotlin.test.assertNotNull

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
        resetGlobalEventSender()
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
        resetGlobalEventSender()
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

        // A headless engine attaches from *inside* the FlutterEngine constructor
        // that HeadlessTaskService wraps in this flag — on the main thread, which
        // is why a thread check misidentified it as a UI engine on a real device.
        setSpawningHeadlessEngine(true)
        try {
            TraceletAndroidPlugin().onAttachedToEngine(createMockBinding("headless"))
        } finally {
            setSpawningHeadlessEngine(false)
        }

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
     * still receive them — once its Dart side has subscribed (#364).
     */
    @Test
    fun uiSecondaryEngine_joinsTheEventFanOut() {
        val primaryPlugin = TraceletAndroidPlugin()
        primaryPlugin.onAttachedToEngine(createMockBinding("primary"))
        val afterPrimary = globalDispatcherCount()

        // No headless spawn in flight — an EngineGroup/overlay engine.
        val overlay = TraceletAndroidPlugin()
        overlay.onAttachedToEngine(createMockBinding("overlay"))
        // Its Dart side accesses an event stream, which makes PigeonTracelet
        // call requestStateFlush() on this engine's HostApi.
        overlay.onDartEventsSubscribed()

        assertEquals(
            afterPrimary + 1,
            globalDispatcherCount(),
            "an in-process UI engine must still receive events",
        )
    }

    /**
     * #364: a FlutterEngine created by *another plugin* must not be treated as
     * an event receiver.
     *
     * `isSpawningHeadlessEngine` only identifies engines Tracelet spawned
     * itself. An engine created by firebase_messaging's background message
     * service (or flutter_local_notifications, background_downloader, …) takes
     * the UI branch, and plugin auto-registration attaches Tracelet to it — but
     * its isolate never calls `Tracelet.onLocation`. Registering it gave the
     * dispatcher a non-null `eventApi`, which `EventDispatcher` reads as "a
     * Flutter engine can receive this", so `fallback()` never routed to
     * `HeadlessTaskService`. After task removal the real UI engine died and
     * that foreign engine kept the whole fan-out to itself: native tracking
     * continued, and Dart saw nothing for the rest of the process.
     */
    @Test
    fun foreignEngineThatNeverSubscribes_doesNotJoinTheEventFanOut() {
        val primaryPlugin = TraceletAndroidPlugin()
        primaryPlugin.onAttachedToEngine(createMockBinding("primary"))
        val afterPrimary = globalDispatcherCount()

        // firebase_messaging's FlutterFirebaseMessagingBackgroundService builds
        // its engine on the main thread and outside any Tracelet headless spawn
        // — indistinguishable from an overlay at attach time.
        TraceletAndroidPlugin().onAttachedToEngine(createMockBinding("fcm"))

        assertEquals(
            afterPrimary,
            globalDispatcherCount(),
            "an engine whose Dart side never subscribed must not join the " +
                "fan-out, or it swallows every event once the UI engine dies",
        )
    }

    /**
     * #364, the delivery half: with the foreign engine held out, the primary
     * detaching on task removal leaves nothing in the fan-out claiming it can
     * deliver — which is what lets events fall through to the headless task
     * instead of being posted into an isolate with no listeners.
     */
    @Test
    fun foreignEngineSurvivingPrimaryDetach_leavesTheFanOutEmpty() {
        val primaryPlugin = TraceletAndroidPlugin()
        val primaryBinding = createMockBinding("primary")
        primaryPlugin.onAttachedToEngine(primaryBinding)
        TraceletAndroidPlugin().onAttachedToEngine(createMockBinding("fcm"))

        // App swiped from recents: the UI engine detaches, the FCM engine lives on.
        primaryPlugin.onDetachedFromEngine(primaryBinding)

        assertEquals(
            0,
            globalDispatcherCount(),
            "the surviving foreign engine must not be left holding the fan-out",
        )
    }

    /**
     * #371, the other half of the state above: an empty fan-out is only safe if
     * something still routes to the headless task.
     *
     * `sdk.setEventSender(globalEventSender)` happens once, at primary attach,
     * and survives task removal — so after the primary detaches every event the
     * still-running native tracking produces is dispatched into this composite.
     * With the members gone, the per-dispatcher `headlessFallback` went with
     * them; the composite needs its own, wired here and outliving the detach.
     */
    @Test
    fun primaryDetachWithASurvivingEngine_leavesAHeadlessRouteOnTheFanOut() {
        val primaryPlugin = TraceletAndroidPlugin()
        val primaryBinding = createMockBinding("primary")
        primaryPlugin.onAttachedToEngine(primaryBinding)
        assertNotNull(
            globalFanOutFallback(),
            "the primary must wire the fan-out's headless fallback at attach",
        )

        TraceletAndroidPlugin().onAttachedToEngine(createMockBinding("fcm"))
        primaryPlugin.onDetachedFromEngine(primaryBinding)

        assertEquals(0, globalDispatcherCount())
        assertNotNull(
            globalFanOutFallback(),
            "with the fan-out empty and the SDK still holding it as the event " +
                "sender, losing this route means events reach nothing at all",
        )
    }

    /**
     * #364 must not re-open #358: an app whose *headless* task subscribes to a
     * stream would otherwise hand the headless engine a live `eventApi` through
     * the same handshake, and swallow the events it was spawned to deliver.
     */
    @Test
    fun headlessEngineThatSubscribes_stillDoesNotJoinTheEventFanOut() {
        val primaryPlugin = TraceletAndroidPlugin()
        primaryPlugin.onAttachedToEngine(createMockBinding("primary"))
        val afterPrimary = globalDispatcherCount()

        val headless = TraceletAndroidPlugin()
        setSpawningHeadlessEngine(true)
        try {
            headless.onAttachedToEngine(createMockBinding("headless"))
        } finally {
            setSpawningHeadlessEngine(false)
        }
        headless.onDartEventsSubscribed()

        assertEquals(
            afterPrimary,
            globalDispatcherCount(),
            "a headless engine must stay out of the fan-out even when its " +
                "isolate subscribes to a stream (#358)",
        )
    }

    /**
     * #364: a secondary engine that detached before subscribing must not be
     * able to join later on a late handshake, holding a messenger whose engine
     * is gone.
     */
    @Test
    fun uiSecondaryEngine_cannotJoinAfterItDetached() {
        val primaryPlugin = TraceletAndroidPlugin()
        primaryPlugin.onAttachedToEngine(createMockBinding("primary"))
        val afterPrimary = globalDispatcherCount()

        val overlay = TraceletAndroidPlugin()
        val overlayBinding = createMockBinding("overlay")
        overlay.onAttachedToEngine(overlayBinding)
        overlay.onDetachedFromEngine(overlayBinding)
        overlay.onDartEventsSubscribed()

        assertEquals(
            afterPrimary,
            globalDispatcherCount(),
            "a detached engine must not join the fan-out",
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

    private fun setSpawningHeadlessEngine(value: Boolean) {
        val cls = Class.forName(
            "com.ikolvi.tracelet.flutter.service.HeadlessTaskService",
        )
        val field = cls.getDeclaredField("isSpawningHeadlessEngine")
        field.isAccessible = true
        field.setBoolean(null, value)
    }

    /** Number of dispatchers currently in the global event fan-out. */
    private fun globalDispatcherCount(): Int = globalDispatchers().size

    /**
     * Empties the static fan-out between tests.
     *
     * `globalEventSender` is a companion-object singleton, so dispatchers added
     * by one test were still there for the next one. Tests that assert a
     * *relative* count survive that; one that asserts the fan-out is empty
     * cannot (#364).
     */
    private fun resetGlobalEventSender() {
        globalDispatchers().clear()
        val sender = globalEventSenderInstance()
        val fallback = sender.javaClass.getDeclaredField("headlessFallback")
        fallback.isAccessible = true
        fallback.set(sender, null)
    }

    /** The fan-out's own headless fallback, or null when none is wired (#371). */
    private fun globalFanOutFallback(): Any? {
        val sender = globalEventSenderInstance()
        val field = sender.javaClass.getDeclaredField("headlessFallback")
        field.isAccessible = true
        return field.get(sender)
    }

    private fun globalEventSenderInstance(): Any {
        val senderField = TraceletAndroidPlugin::class.java.getDeclaredField("globalEventSender")
        senderField.isAccessible = true
        return senderField.get(null)
    }

    private fun globalDispatchers(): MutableList<*> {
        val senderField = TraceletAndroidPlugin::class.java.getDeclaredField("globalEventSender")
        senderField.isAccessible = true
        val sender = senderField.get(null)
        val listField = sender.javaClass.getDeclaredField("dispatchers")
        listField.isAccessible = true
        return listField.get(sender) as MutableList<*>
    }
}
