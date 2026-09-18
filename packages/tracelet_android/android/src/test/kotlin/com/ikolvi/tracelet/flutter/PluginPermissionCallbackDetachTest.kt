package com.ikolvi.tracelet.flutter

import android.app.Activity
import android.content.Context
import com.ikolvi.tracelet.sdk.TraceletSdk
import com.ikolvi.tracelet.sdk.util.TraceletLogger
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import org.mockito.Mockito.inOrder
import org.mockito.Mockito.mock
import org.mockito.Mockito.never
import org.mockito.Mockito.verify
import org.mockito.Mockito.`when`
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test

/**
 * #415 — the Pigeon reply for `requestPermission` is completed only through
 * `onRequestPermissionsResult`, which reaches the plugin via the listener
 * registered on the `ActivityPluginBinding`. `onDetachedFromActivity` removes
 * that listener. If it fires while the permission dialog is up, the reply has
 * no remaining completion path and the Dart Future never resolves — and the
 * next `requestPermission` short-circuits on the stale pending callback and
 * returns the current status synchronously, which is why "the second call
 * works" was part of the report.
 *
 * The SDK has had `clearPendingPermissionCallback()` for this since `afd6f472`;
 * the 2.0.0 lifecycle rewrite (`b354456c`) stopped calling it.
 *
 * Driven against a mock SDK injected into the singleton, the same way
 * [PluginSecondaryEngineGuardTest] does, so the assertion is about what the
 * plugin asks the SDK to do and in what order.
 */
internal class PluginPermissionCallbackDetachTest {

    private lateinit var mockSdk: TraceletSdk
    private lateinit var plugin: TraceletAndroidPlugin

    @BeforeTest
    fun setUp() {
        mockSdk = mock(TraceletSdk::class.java)
        `when`(mockSdk.logger).thenReturn(mock(TraceletLogger::class.java))
        TraceletSdk::class.java.getDeclaredField("instance").apply {
            isAccessible = true
            set(null, mockSdk)
        }

        plugin = TraceletAndroidPlugin()
        // The lifecycle callbacks reach the SDK through `sdk`, whose getter
        // evaluates `context` first; it is only ever set by onAttachedToEngine,
        // which does far more than these tests need.
        TraceletAndroidPlugin::class.java.getDeclaredField("context").apply {
            isAccessible = true
            set(plugin, mock(Context::class.java))
        }
    }

    @AfterTest
    fun tearDown() {
        TraceletSdk::class.java.getDeclaredField("instance").apply {
            isAccessible = true
            set(null, null)
        }
    }

    private fun attachActivity(): ActivityPluginBinding {
        val binding = mock(ActivityPluginBinding::class.java)
        `when`(binding.activity).thenReturn(mock(Activity::class.java))
        plugin.onAttachedToActivity(binding)
        return binding
    }

    /** The reported path: a full detach completes whatever reply is pending. */
    @Test
    fun detachFromActivity_completesThePendingPermissionReply() {
        attachActivity()

        plugin.onDetachedFromActivity()

        verify(mockSdk).clearPendingPermissionCallback()
    }

    /**
     * Order matters: the status the reply is completed with is resolved
     * through the activity (the rationale check is what tells DENIED from
     * NOT_DETERMINED), so the callback must run before the activity is
     * dropped.
     */
    @Test
    fun detachFromActivity_completesTheReplyBeforeDroppingTheActivity() {
        attachActivity()

        plugin.onDetachedFromActivity()

        inOrder(mockSdk).apply {
            verify(mockSdk).clearPendingPermissionCallback()
            verify(mockSdk).activity = null
        }
    }

    /**
     * A config change detaches and reattaches: the listener is re-added on
     * `onReattachedToActivityForConfigChanges` and the dialog's result still
     * reaches `onRequestPermissionsResult`. Completing the reply here would
     * resolve the Future with the pre-dialog status while the dialog is still
     * up.
     */
    @Test
    fun detachForConfigChanges_leavesThePendingReplyForTheReattach() {
        attachActivity()

        plugin.onDetachedFromActivityForConfigChanges()

        verify(mockSdk, never()).clearPendingPermissionCallback()
    }
}
