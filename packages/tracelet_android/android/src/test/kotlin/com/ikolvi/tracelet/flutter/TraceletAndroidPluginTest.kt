package com.ikolvi.tracelet.flutter

import android.content.Context
import android.app.Activity
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.flutter.service.HeadlessTaskService
import com.ikolvi.tracelet.sdk.TraceletSdk
import com.ikolvi.tracelet.sdk.model.AuthorizationStatus
import com.ikolvi.tracelet.sdk.util.TraceletPermissionManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.mockito.Mockito.mock
import kotlin.test.assertNotSame
import kotlin.test.assertEquals
import kotlin.test.assertNull
import com.ikolvi.tracelet.sdk.sync.NO_SYNC_BODY_BUILDER_SENTINEL

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class TraceletAndroidPluginTest {

    private lateinit var context: Context

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        // Reset state
        TraceletSdk.getInstance(context).dartSyncInterceptor = null
        HeadlessTaskService.isSpawningHeadlessEngine = false
    }

    @After
    fun tearDown() {
        TraceletSdk.getInstance(context).dartSyncInterceptor = null
        HeadlessTaskService.isSpawningHeadlessEngine = false
        TraceletSdk.getInstance(context).clearPendingPermissionCallback()
    }

    @Test
    fun `plugin attached to headless engine acts as secondary instance`() {
        // Set the flag simulating a headless engine spawning
        HeadlessTaskService.isSpawningHeadlessEngine = true

        val plugin = TraceletAndroidPlugin()
        val mockBinding = mock(FlutterPlugin.FlutterPluginBinding::class.java)
        org.mockito.Mockito.`when`(mockBinding.applicationContext).thenReturn(context)
        org.mockito.Mockito.`when`(mockBinding.binaryMessenger).thenReturn(mock(BinaryMessenger::class.java))

        plugin.onAttachedToEngine(mockBinding)

        // The plugin should NOT overwrite the dartSyncInterceptor
        assertNotSame(
            plugin,
            TraceletSdk.getInstance(context).dartSyncInterceptor,
            "TraceletAndroidPlugin should not overwrite dartSyncInterceptor when spawned by a headless engine"
        )
    }

    @Test
    fun `activity detach completes pending permission reply exactly once`() {
        val plugin = TraceletAndroidPlugin()
        val engineBinding = mock(FlutterPlugin.FlutterPluginBinding::class.java)
        org.mockito.Mockito.`when`(engineBinding.applicationContext).thenReturn(context)
        org.mockito.Mockito.`when`(engineBinding.binaryMessenger)
            .thenReturn(mock(BinaryMessenger::class.java))
        plugin.onAttachedToEngine(engineBinding)

        val activityBinding = mock(ActivityPluginBinding::class.java)
        org.mockito.Mockito.`when`(activityBinding.activity)
            .thenReturn(mock(Activity::class.java))
        plugin.onAttachedToActivity(activityBinding)

        // Reflection seeds SDK state across the plugin-module boundary without
        // widening the production API solely for this regression test.
        val sdk = TraceletSdk.getInstance(context)
        TraceletSdk::class.java
            .getDeclaredField("permissionManager")
            .apply { isAccessible = true }
            .set(sdk, TraceletPermissionManager(context))
        val pendingField = TraceletSdk::class.java
            .getDeclaredField("pendingPermissionCallback")
            .apply { isAccessible = true }
        var completions = 0
        val pending: (AuthorizationStatus) -> Unit = { completions++ }
        pendingField.set(sdk, pending)

        // A repeated lifecycle callback must not complete the same reply twice.
        plugin.onDetachedFromActivity()
        plugin.onDetachedFromActivity()

        assertEquals(1, completions)
        assertNull(pendingField.get(sdk))
    }

    @Test
    fun `requestSyncBody returns sentinel immediately when hasCustomSyncBodyBuilder is false`() {
        TraceletAndroidPlugin.hasCustomSyncBodyBuilder = false
        val plugin = TraceletAndroidPlugin()
        
        // When no custom builder is registered, it should immediately return the sentinel 
        // without waiting for a method channel timeout.
        val result = plugin.requestSyncBody(emptyList())
        
        assertEquals(
            NO_SYNC_BODY_BUILDER_SENTINEL, 
            result,
            "requestSyncBody should return sentinel immediately when hasCustomSyncBodyBuilder is false"
        )
    }
}
