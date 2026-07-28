package com.ikolvi.tracelet.sdk

import android.Manifest
import android.content.Context
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Regression for the remote-config battery-budget bug.
 *
 * `batteryBudgetPerHour` used to be read only at [TraceletSdk.ready], so a value
 * that arrived afterwards — e.g. a remote-config push of
 * `{"geo":{"batteryBudgetPerHour":1.0}}` applied at runtime via [setConfig] —
 * was written into the config cache but never acted on: the battery-budget
 * engine stayed exactly as `ready()` had left it (only a cold restart, which
 * applies the cached remote config before `ready()` builds the engine, made it
 * appear to work).
 *
 * These tests drive the exact runtime path the remote-config fetch uses
 * ([setConfig]) and assert the engine is (re)built / torn down accordingly.
 * Every `ready()`/`setConfig()` passes `batteryBudgetPerHour` explicitly so the
 * assertions are immune to any value persisted by a previous run.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class BatteryBudgetRemoteConfigTest {

    private lateinit var context: Context
    private lateinit var sdk: TraceletSdk

    @Before
    fun setUp() {
        org.robolectric.shadows.ShadowLog.stream = System.out
        context = ApplicationProvider.getApplicationContext()

        androidx.work.testing.WorkManagerTestInitHelper.initializeTestWorkManager(
            context,
            androidx.work.Configuration.Builder()
                .setExecutor(androidx.work.testing.SynchronousExecutor())
                .build(),
        )

        val shadowApp = shadowOf(context as android.app.Application)
        shadowApp.grantPermissions(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
            Manifest.permission.ACCESS_BACKGROUND_LOCATION,
            Manifest.permission.ACTIVITY_RECOGNITION,
        )

        sdk = TraceletSdk.getInstance(context)
        // initialize() requires an event sender to be registered first.
        sdk.setEventSender(ListenerEventSender())
        sdk.initialize()
    }

    @After
    fun tearDown() {
        try { sdk.stop() } catch (_: Exception) {}
        idle()
        ConfigManager.resetInstance()
    }

    private fun idle() = shadowOf(Looper.getMainLooper()).idle()

    private fun geo(budget: Any): Map<String, Any?> =
        mapOf("geo" to mapOf("batteryBudgetPerHour" to budget))

    private fun ready(config: Map<String, Any?>) {
        var done = false
        sdk.ready(
            config + mapOf(
                "foregroundService" to false,
                "stopOnStationary" to false,
                "isMoving" to true,
            ),
        ) { done = true }
        idle()
        assertTrue(done, "ready() callback should fire")
    }

    /**
     * The reported scenario: `ready()` starts with the budget OFF (mirroring
     * `Config.balanced()` used by the remote-config example card), then the
     * budget arrives at runtime via `setConfig()`. The engine MUST become
     * active — before the fix it stayed null until a cold restart.
     */
    @Test
    fun `runtime setConfig enables battery budget`() {
        ready(geo(0.0))
        assertFalse(
            sdk.isBatteryBudgetEngineActive,
            "battery budget must be off when ready() had batteryBudgetPerHour=0",
        )

        sdk.setConfig(geo(1.0))
        idle()

        assertTrue(
            sdk.isBatteryBudgetEngineActive,
            "runtime setConfig({geo:{batteryBudgetPerHour:1.0}}) must (re)build the engine",
        )
    }

    /** Same, but while tracking is active — the real remote-config timing. */
    @Test
    fun `runtime setConfig enables battery budget while tracking`() {
        ready(geo(0.0))
        sdk.start()
        idle()
        assertFalse(sdk.isBatteryBudgetEngineActive)

        sdk.setConfig(geo(1.0))
        idle()

        assertTrue(
            sdk.isBatteryBudgetEngineActive,
            "an active tracking session must pick up a remote batteryBudgetPerHour",
        )
    }

    /**
     * An integer-encoded value (`1` rather than `1.0`) must be honoured too —
     * JSON from a remote endpoint frequently drops the decimal point.
     */
    @Test
    fun `runtime setConfig enables battery budget with integer-encoded value`() {
        ready(geo(0.0))

        sdk.setConfig(geo(1))
        idle()

        assertTrue(
            sdk.isBatteryBudgetEngineActive,
            "integer-encoded batteryBudgetPerHour (1) must build the engine",
        )
    }

    /**
     * The inverse: a runtime config of `0` must tear the engine down, so remote
     * config can disable the budget as well as enable it.
     */
    @Test
    fun `runtime setConfig disables battery budget`() {
        ready(geo(2.0))
        assertTrue(
            sdk.isBatteryBudgetEngineActive,
            "battery budget must be on when ready() supplied batteryBudgetPerHour=2",
        )

        sdk.setConfig(geo(0.0))
        idle()

        assertFalse(
            sdk.isBatteryBudgetEngineActive,
            "runtime setConfig with batteryBudgetPerHour=0 must disable the engine",
        )
    }
}
