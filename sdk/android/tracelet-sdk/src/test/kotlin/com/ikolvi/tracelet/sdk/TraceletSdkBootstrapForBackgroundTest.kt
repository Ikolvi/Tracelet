package com.ikolvi.tracelet.sdk

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.work.Configuration
import androidx.work.testing.SynchronousExecutor
import androidx.work.testing.WorkManagerTestInitHelper
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.concurrent.CountDownLatch
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * Regression for #264 — the boot/restart crash
 * `UninitializedPropertyAccessException: lateinit property geofenceManager has
 * not been initialized`.
 *
 * `initialize()` wires the `lateinit` subsystems (Rust DB, `geofenceManager`,
 * engines) on a background `tracelet-init` thread. `bootstrapForBackground()`
 * used to kick that off and return immediately, so a cold-boot caller
 * (`LocationService.startBootTracking()`) could read the still-unassigned
 * `geofenceManager` and crash the service before its foreground notification
 * was posted.
 *
 * The contract these tests lock in:
 *  - `bootstrapForBackground()` returns `true` only after init has fully
 *    completed and the managers are actually assigned.
 *  - It returns `false` (so callers defer instead of touching a manager) when
 *    init has not produced a usable DB / `geofenceManager`.
 *
 * These tests operate on isolated [TraceletSdk] instances built via the private
 * constructor, so they never mutate the process-wide singleton that other tests
 * rely on.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class TraceletSdkBootstrapForBackgroundTest {

    private lateinit var context: Context

    @Before
    fun setUp() {
        org.robolectric.shadows.ShadowLog.stream = System.out
        context = ApplicationProvider.getApplicationContext()
        // bootstrapForBackground() → checkSyncProvider()/behaviour engines may
        // touch WorkManager transitively; provide the in-memory test scheduler.
        WorkManagerTestInitHelper.initializeTestWorkManager(
            context,
            Configuration.Builder().setExecutor(SynchronousExecutor()).build(),
        )
    }

    @After
    fun tearDown() {
        ConfigManager.resetInstance()
    }

    /** A fresh, isolated SDK instance that is NOT stored in the singleton, so
     *  manipulating its internal state cannot pollute other test classes. */
    private fun isolatedSdk(): TraceletSdk {
        val ctor = TraceletSdk::class.java.getDeclaredConstructor(Context::class.java)
        ctor.isAccessible = true
        return ctor.newInstance(context.applicationContext) as TraceletSdk
    }

    @Test
    fun `bootstrapForBackground returns true and initializes geofenceManager`() {
        val sdk = isolatedSdk()

        val ok = sdk.bootstrapForBackground(ListenerEventSender())

        assertTrue(
            ok,
            "bootstrapForBackground() must return true once initialization completed",
        )
        // Must be safe to touch now — accessing geofenceManager is the exact
        // operation that crashed on the boot path in #264. It must not throw
        // UninitializedPropertyAccessException.
        assertNotNull(
            sdk.geofenceManager,
            "geofenceManager must be initialized once bootstrapForBackground() returns true",
        )
    }

    @Test
    fun `bootstrapForBackground returns false when init did not assign the managers`() {
        val sdk = isolatedSdk()

        // Force the "init already 'ran' but produced no usable DB/managers"
        // state deterministically, without spawning the real init thread or
        // waiting 15s: mark init started (so initialize() is a no-op) and
        // release the completion latch. rustDatabase stays null and
        // geofenceManager stays unassigned.
        sdk.javaClass.getDeclaredField("initStarted").apply { isAccessible = true }
            .setBoolean(sdk, true)
        (sdk.javaClass.getDeclaredField("initCompleteLatch").apply { isAccessible = true }
            .get(sdk) as CountDownLatch).countDown()

        val ok = sdk.bootstrapForBackground(ListenerEventSender())

        assertFalse(
            ok,
            "bootstrapForBackground() must return false when the Rust DB / " +
                "geofenceManager are not initialized, so boot callers defer " +
                "instead of touching an uninitialized lateinit (#264)",
        )
    }
}
