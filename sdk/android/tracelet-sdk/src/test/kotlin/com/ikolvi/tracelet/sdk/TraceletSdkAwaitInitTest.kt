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
import kotlin.test.assertTrue

/**
 * Regression coverage for the boot/broadcast init race (regression from #260,
 * partially fixed in #264, completed in #270).
 *
 * `initialize()` wires the `lateinit` subsystems (Rust DB, `geofenceManager`,
 * engines) on a background `tracelet-init` thread and returns immediately.
 * Every synchronous entry point that dereferences those managers right after
 * calling `initialize()` — `ready()`, `bootstrapForBackground()`, and the
 * native boot / broadcast paths (`GeofenceBroadcastReceiver`,
 * `CrashConfirmReceiver`) — must first funnel through [TraceletSdk.awaitInit]
 * and bail when it returns `false`, instead of touching a not-yet-assigned
 * lateinit and crashing with `UninitializedPropertyAccessException`.
 *
 * These tests lock in the [TraceletSdk.awaitInit] contract:
 *  - returns `true` only once init has fully completed without failure, so the
 *    subsystems are safe to touch;
 *  - returns `false` when init recorded a failure, so callers defer instead of
 *    dereferencing a half-wired lateinit.
 *
 * They run on isolated [TraceletSdk] instances built via the private
 * constructor so they never mutate the process-wide singleton.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class TraceletSdkAwaitInitTest {

    private lateinit var context: Context

    @Before
    fun setUp() {
        org.robolectric.shadows.ShadowLog.stream = System.out
        context = ApplicationProvider.getApplicationContext()
        // awaitInit() → callers may transitively touch WorkManager; provide the
        // in-memory test scheduler so those paths do not blow up.
        WorkManagerTestInitHelper.initializeTestWorkManager(
            context,
            Configuration.Builder().setExecutor(SynchronousExecutor()).build(),
        )
    }

    @After
    fun tearDown() {
        ConfigManager.resetInstance()
    }

    /** A fresh, isolated SDK instance that is NOT stored in the singleton. */
    private fun isolatedSdk(): TraceletSdk {
        val ctor = TraceletSdk::class.java.getDeclaredConstructor(Context::class.java)
        ctor.isAccessible = true
        return ctor.newInstance(context.applicationContext) as TraceletSdk
    }

    private fun setPrivateField(sdk: TraceletSdk, name: String, value: Any?) {
        sdk.javaClass.getDeclaredField(name).apply { isAccessible = true }.set(sdk, value)
    }

    private fun countDownInitLatch(sdk: TraceletSdk) {
        (sdk.javaClass.getDeclaredField("initCompleteLatch").apply { isAccessible = true }
            .get(sdk) as CountDownLatch).countDown()
    }

    @Test
    fun `awaitInit returns true once initialization completed`() {
        val sdk = isolatedSdk()

        // bootstrapForBackground() runs the real init to completion (proven by
        // TraceletSdkBootstrapForBackgroundTest). After it returns true, the
        // completion latch is released with no recorded failure, so awaitInit()
        // must report the subsystems are safe to touch.
        assertTrue(
            sdk.bootstrapForBackground(ListenerEventSender()),
            "precondition: bootstrapForBackground() should complete init",
        )

        assertTrue(
            sdk.awaitInit(),
            "awaitInit() must return true once initialize() has completed without failure",
        )
    }

    @Test
    fun `awaitInit returns false when initialization failed`() {
        val sdk = isolatedSdk()

        // Deterministically model "init ran but threw": mark init started (so
        // initialize() stays a no-op and no real thread spawns), record a
        // failure, and release the latch. awaitInit() must surface the failure
        // rather than blocking for the 30s timeout or falsely reporting success.
        setPrivateField(sdk, "initStarted", true)
        setPrivateField(sdk, "initializationFailure", IllegalStateException("boom"))
        countDownInitLatch(sdk)

        assertFalse(
            sdk.awaitInit(),
            "awaitInit() must return false when initialize() recorded a failure, " +
                "so boot / broadcast callers defer instead of dereferencing an " +
                "unassigned lateinit",
        )
    }
}
