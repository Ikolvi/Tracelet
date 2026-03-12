package com.tracelet.tracelet_android.service

import android.content.Context
import android.content.SharedPreferences
import com.tracelet.tracelet_android.ConfigManager
import com.tracelet.tracelet_android.StateManager
import org.mockito.Mockito
import org.mockito.Mockito.`when`
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Tests for [LocationService] tracking-mode-aware boot recovery logic.
 *
 * Since LocationService is an Android Service that requires a full Android
 * context (foreground notification, wakelocks, etc.), we can't instantiate
 * it directly in JVM-only tests. Instead, we test the decision inputs:
 * - StateManager.trackingMode persistence and round-tripping
 * - ConfigManager periodic strategy flags
 * - The boot-mode static state (bootLocationEngine companion)
 *
 * The actual startBootTracking() execution with real Services/WorkManager
 * requires Robolectric or on-device integration tests.
 */
internal class LocationServiceTest {

    // ─────────────────────────────────────────────────────────────────────
    // Helper: in-memory SharedPreferences mock
    // ─────────────────────────────────────────────────────────────────────

    private data class MockedContext(
        val context: Context,
        val configStore: MutableMap<String, Any?>,
        val stateStore: MutableMap<String, Any?>,
    )

    private fun createMockedContext(): MockedContext {
        val configEditor = Mockito.mock(SharedPreferences.Editor::class.java)
        val configPrefs = Mockito.mock(SharedPreferences::class.java)
        val stateEditor = Mockito.mock(SharedPreferences.Editor::class.java)
        val statePrefs = Mockito.mock(SharedPreferences::class.java)
        val context = Mockito.mock(Context::class.java)

        val configStore = mutableMapOf<String, Any?>()
        val stateStore = mutableMapOf<String, Any?>()

        // Wire config editor
        `when`(configEditor.putString(Mockito.anyString(), Mockito.anyString())).thenAnswer {
            configStore[it.getArgument<String>(0)] = it.getArgument<String>(1); configEditor
        }
        `when`(configEditor.remove(Mockito.anyString())).thenAnswer {
            configStore.remove(it.getArgument<String>(0)); configEditor
        }
        `when`(configEditor.clear()).thenAnswer { configStore.clear(); configEditor }
        `when`(configEditor.commit()).thenReturn(true)

        // Wire config prefs
        `when`(configPrefs.edit()).thenReturn(configEditor)
        `when`(configPrefs.contains(Mockito.anyString())).thenAnswer {
            configStore.containsKey(it.getArgument<String>(0))
        }
        `when`(configPrefs.getString(Mockito.anyString(), Mockito.nullable(String::class.java))).thenAnswer {
            configStore[it.getArgument<String>(0)] as? String ?: it.getArgument<String?>(1)
        }

        // Wire state editor
        `when`(stateEditor.putBoolean(Mockito.anyString(), Mockito.anyBoolean())).thenAnswer {
            stateStore[it.getArgument<String>(0)] = it.getArgument<Boolean>(1); stateEditor
        }
        `when`(stateEditor.putLong(Mockito.anyString(), Mockito.anyLong())).thenAnswer {
            stateStore[it.getArgument<String>(0)] = it.getArgument<Long>(1); stateEditor
        }
        `when`(stateEditor.putInt(Mockito.anyString(), Mockito.anyInt())).thenAnswer {
            stateStore[it.getArgument<String>(0)] = it.getArgument<Int>(1); stateEditor
        }
        `when`(stateEditor.remove(Mockito.anyString())).thenAnswer {
            stateStore.remove(it.getArgument<String>(0)); stateEditor
        }
        `when`(stateEditor.clear()).thenAnswer { stateStore.clear(); stateEditor }
        `when`(stateEditor.commit()).thenReturn(true)

        // Wire state prefs
        `when`(statePrefs.edit()).thenReturn(stateEditor)
        `when`(statePrefs.getBoolean(Mockito.anyString(), Mockito.anyBoolean())).thenAnswer {
            stateStore[it.getArgument<String>(0)] as? Boolean ?: it.getArgument<Boolean>(1)
        }
        `when`(statePrefs.getLong(Mockito.anyString(), Mockito.anyLong())).thenAnswer {
            stateStore[it.getArgument<String>(0)] as? Long ?: it.getArgument<Long>(1)
        }
        `when`(statePrefs.getInt(Mockito.anyString(), Mockito.anyInt())).thenAnswer {
            stateStore[it.getArgument<String>(0)] as? Int ?: it.getArgument<Int>(1)
        }

        // Wire context
        `when`(context.getSharedPreferences("com.tracelet.config", Context.MODE_PRIVATE)).thenReturn(configPrefs)
        `when`(context.getSharedPreferences("com.tracelet.state", Context.MODE_PRIVATE)).thenReturn(statePrefs)
        `when`(context.applicationContext).thenReturn(context)
        `when`(context.packageName).thenReturn("com.tracelet.test")

        return MockedContext(context, configStore, stateStore)
    }

    // ─────────────────────────────────────────────────────────────────────
    // Tests: Boot-mode companion state
    // ─────────────────────────────────────────────────────────────────────

    @Test
    fun bootLocationEngine_isNullByDefault() {
        // No boot tracking has started — companion property should be null
        assertNull(LocationService.bootLocationEngine)
    }

    @Test
    fun stopBootTracking_noOpWhenNotStarted() {
        // stopBootTracking should be safe to call when bootLocationEngine is null.
        // Note: can't call it directly here because destroy() touches Android APIs.
        // Instead verify the companion state that guards it.
        assertNull(LocationService.bootLocationEngine)
        // The guard `bootLocationEngine?.destroy()` is a safe no-op on null.
    }

    @Test
    fun isServiceRunning_falseByDefault() {
        assertEquals(false, LocationService.isServiceRunning())
    }

    // ─────────────────────────────────────────────────────────────────────
    // Tests: Decision inputs for tracking-mode-aware boot recovery
    // ─────────────────────────────────────────────────────────────────────

    @Test
    fun periodicMode_workManagerStrategy_noForegroundService() {
        // When trackingMode=2 and periodicUseForegroundService=false
        // and periodicUseExactAlarms=false (default), the boot recovery
        // should use WorkManager (no foreground service needed)
        val (ctx, _, _) = createMockedContext()
        val state = StateManager(ctx)
        val config = ConfigManager(ctx)

        state.trackingMode = 2
        state.enabled = true

        assertEquals(2, state.trackingMode)
        assertEquals(false, config.getPeriodicUseForegroundService())
        assertEquals(false, config.getPeriodicUseExactAlarms())

        // Decision: trackingMode == 2 && !periodicUseForegroundService
        // → BootReceiver should re-schedule WorkManager, NOT start FG service
        val shouldUseForegroundService = state.trackingMode != 2 ||
            config.getPeriodicUseForegroundService()
        assertEquals(false, shouldUseForegroundService)
    }

    @Test
    fun periodicMode_exactAlarmStrategy_noForegroundService() {
        val (ctx, _, _) = createMockedContext()
        val state = StateManager(ctx)
        val config = ConfigManager(ctx)
        config.setConfig(mapOf(
            "geo" to mapOf("periodicUseExactAlarms" to true)
        ))

        state.trackingMode = 2
        state.enabled = true

        assertEquals(2, state.trackingMode)
        assertEquals(false, config.getPeriodicUseForegroundService())
        assertEquals(true, config.getPeriodicUseExactAlarms())

        // Decision: trackingMode == 2 && !periodicUseForegroundService
        // → BootReceiver should re-schedule exact alarms, NOT start FG service
        val shouldUseForegroundService = state.trackingMode != 2 ||
            config.getPeriodicUseForegroundService()
        assertEquals(false, shouldUseForegroundService)
    }

    @Test
    fun periodicMode_foregroundServiceStrategy_usesForegroundService() {
        val (ctx, _, _) = createMockedContext()
        val state = StateManager(ctx)
        val config = ConfigManager(ctx)
        config.setConfig(mapOf(
            "geo" to mapOf("periodicUseForegroundService" to true)
        ))

        state.trackingMode = 2
        state.enabled = true

        assertEquals(2, state.trackingMode)
        assertEquals(true, config.getPeriodicUseForegroundService())

        // Decision: trackingMode == 2 && periodicUseForegroundService == true
        // → BootReceiver should start FG service, which calls startBootTracking()
        val shouldUseForegroundService = state.trackingMode != 2 ||
            config.getPeriodicUseForegroundService()
        assertEquals(true, shouldUseForegroundService)
    }

    @Test
    fun continuousMode_alwaysUsesForegroundService() {
        val (ctx, _, _) = createMockedContext()
        val state = StateManager(ctx)

        state.trackingMode = 0
        state.enabled = true

        // Decision: trackingMode != 2 → always start FG service
        val shouldUseForegroundService = state.trackingMode != 2 ||
            ConfigManager(ctx).getPeriodicUseForegroundService()
        assertEquals(true, shouldUseForegroundService)
    }

    @Test
    fun geofenceMode_alwaysUsesForegroundService() {
        val (ctx, _, _) = createMockedContext()
        val state = StateManager(ctx)

        state.trackingMode = 1
        state.enabled = true

        val shouldUseForegroundService = state.trackingMode != 2 ||
            ConfigManager(ctx).getPeriodicUseForegroundService()
        assertEquals(true, shouldUseForegroundService)
    }

    // ─────────────────────────────────────────────────────────────────────
    // Tests: startBootTracking decision for periodic strategies
    // ─────────────────────────────────────────────────────────────────────

    @Test
    fun bootTracking_periodicWorkManager_correctDecision() {
        // Simulates the when(trackingMode) branch in startBootTracking()
        val (ctx, _, _) = createMockedContext()
        val state = StateManager(ctx)
        val config = ConfigManager(ctx)

        state.trackingMode = 2

        // Default config: both false → WorkManager strategy
        val strategy = when {
            config.getPeriodicUseForegroundService() -> "foreground-service"
            config.getPeriodicUseExactAlarms() -> "exact-alarms"
            else -> "workmanager"
        }
        assertEquals("workmanager", strategy)
    }

    @Test
    fun bootTracking_periodicExactAlarms_correctDecision() {
        val (ctx, _, _) = createMockedContext()
        val state = StateManager(ctx)
        val config = ConfigManager(ctx)
        config.setConfig(mapOf(
            "geo" to mapOf("periodicUseExactAlarms" to true)
        ))

        state.trackingMode = 2

        val strategy = when {
            config.getPeriodicUseForegroundService() -> "foreground-service"
            config.getPeriodicUseExactAlarms() -> "exact-alarms"
            else -> "workmanager"
        }
        assertEquals("exact-alarms", strategy)
    }

    @Test
    fun bootTracking_periodicForegroundService_correctDecision() {
        val (ctx, _, _) = createMockedContext()
        val state = StateManager(ctx)
        val config = ConfigManager(ctx)
        config.setConfig(mapOf(
            "geo" to mapOf("periodicUseForegroundService" to true)
        ))

        state.trackingMode = 2

        val strategy = when {
            config.getPeriodicUseForegroundService() -> "foreground-service"
            config.getPeriodicUseExactAlarms() -> "exact-alarms"
            else -> "workmanager"
        }
        assertEquals("foreground-service", strategy)
    }

    @Test
    fun bootTracking_continuousMode_noPeriodicBranch() {
        val (ctx, _, _) = createMockedContext()
        val state = StateManager(ctx)

        state.trackingMode = 0

        // For continuous mode, the when(trackingMode) should hit else branch
        val isPeriodic = state.trackingMode == 2
        assertEquals(false, isPeriodic)
    }

    @Test
    fun bootTracking_geofenceMode_noPeriodicBranch() {
        val (ctx, _, _) = createMockedContext()
        val state = StateManager(ctx)

        state.trackingMode = 1

        val isPeriodic = state.trackingMode == 2
        assertEquals(false, isPeriodic)
    }

    // ─────────────────────────────────────────────────────────────────────
    // Tests: onTaskRemoved decision for periodic without FG service
    // ─────────────────────────────────────────────────────────────────────

    @Test
    fun taskRemoval_periodicWithoutFG_shouldStopService() {
        // When task is removed and periodic mode is active without FG service,
        // LocationService should stop itself and let WorkManager continue
        val (ctx, _, _) = createMockedContext()
        val state = StateManager(ctx)
        val config = ConfigManager(ctx)

        state.trackingMode = 2
        state.enabled = true

        val shouldStopService = state.trackingMode == 2 &&
            !config.getPeriodicUseForegroundService()
        assertEquals(true, shouldStopService)
    }

    @Test
    fun taskRemoval_periodicWithFG_shouldKeepService() {
        val (ctx, _, _) = createMockedContext()
        val state = StateManager(ctx)
        val config = ConfigManager(ctx)
        config.setConfig(mapOf(
            "geo" to mapOf("periodicUseForegroundService" to true)
        ))

        state.trackingMode = 2
        state.enabled = true

        val shouldStopService = state.trackingMode == 2 &&
            !config.getPeriodicUseForegroundService()
        assertEquals(false, shouldStopService)
    }

    @Test
    fun taskRemoval_continuousMode_shouldKeepService() {
        val (ctx, _, _) = createMockedContext()
        val state = StateManager(ctx)

        state.trackingMode = 0
        state.enabled = true

        val shouldStopService = state.trackingMode == 2 &&
            !ConfigManager(ctx).getPeriodicUseForegroundService()
        assertEquals(false, shouldStopService)
    }

    // ─────────────────────────────────────────────────────────────────────
    // Tests: destroyAll conditional geofence preservation (#23)
    // ─────────────────────────────────────────────────────────────────────

    @Test
    fun destroyAll_geofenceMode_stopOnTerminateFalse_preservesGeofences() {
        // Issue #23: When stopOnTerminate=false, enabled=true, trackingMode=1
        // the keepGeofencesAlive condition should be true — geofences survive.
        val (ctx, _, _) = createMockedContext()
        val state = StateManager(ctx)
        val config = ConfigManager(ctx)
        config.setConfig(mapOf("stopOnTerminate" to false))

        state.enabled = true
        state.trackingMode = 1

        val keepGeofencesAlive = !config.getStopOnTerminate()
            && state.enabled
            && state.trackingMode == 1
        assertEquals(true, keepGeofencesAlive)
    }

    @Test
    fun destroyAll_geofenceMode_stopOnTerminateTrue_destroysGeofences() {
        // Default stopOnTerminate=true — geofences should be destroyed.
        val (ctx, _, _) = createMockedContext()
        val state = StateManager(ctx)
        val config = ConfigManager(ctx)

        state.enabled = true
        state.trackingMode = 1

        val keepGeofencesAlive = !config.getStopOnTerminate()
            && state.enabled
            && state.trackingMode == 1
        assertEquals(false, keepGeofencesAlive)
    }

    @Test
    fun destroyAll_continuousMode_stopOnTerminateFalse_destroysGeofences() {
        // trackingMode=0 (continuous) — geofences should NOT be preserved
        // even when stopOnTerminate=false.
        val (ctx, _, _) = createMockedContext()
        val state = StateManager(ctx)
        val config = ConfigManager(ctx)
        config.setConfig(mapOf("stopOnTerminate" to false))

        state.enabled = true
        state.trackingMode = 0

        val keepGeofencesAlive = !config.getStopOnTerminate()
            && state.enabled
            && state.trackingMode == 1
        assertEquals(false, keepGeofencesAlive)
    }

    @Test
    fun destroyAll_periodicMode_stopOnTerminateFalse_destroysGeofences() {
        // trackingMode=2 (periodic) — geofences should NOT be preserved.
        val (ctx, _, _) = createMockedContext()
        val state = StateManager(ctx)
        val config = ConfigManager(ctx)
        config.setConfig(mapOf("stopOnTerminate" to false))

        state.enabled = true
        state.trackingMode = 2

        val keepGeofencesAlive = !config.getStopOnTerminate()
            && state.enabled
            && state.trackingMode == 1
        assertEquals(false, keepGeofencesAlive)
    }

    @Test
    fun destroyAll_geofenceMode_disabledTracking_destroysGeofences() {
        // enabled=false — geofences should be destroyed even with
        // stopOnTerminate=false and trackingMode=1.
        val (ctx, _, _) = createMockedContext()
        val state = StateManager(ctx)
        val config = ConfigManager(ctx)
        config.setConfig(mapOf("stopOnTerminate" to false))

        state.enabled = false
        state.trackingMode = 1

        val keepGeofencesAlive = !config.getStopOnTerminate()
            && state.enabled
            && state.trackingMode == 1
        assertEquals(false, keepGeofencesAlive)
    }

    @Test
    fun destroyAll_periodicAndGeofenceProtection_mutuallyExclusive() {
        // Verify periodic and geofence preservation can't both be true
        // simultaneously (they guard different trackingMode values).
        val (ctx, _, _) = createMockedContext()
        val state = StateManager(ctx)
        val config = ConfigManager(ctx)
        config.setConfig(mapOf("stopOnTerminate" to false))

        state.enabled = true
        state.trackingMode = 1

        val keepGeofencesAlive = !config.getStopOnTerminate()
            && state.enabled
            && state.trackingMode == 1
        val keepPeriodicAlive = !config.getStopOnTerminate()
            && state.enabled
            && state.trackingMode == 2

        assertEquals(true, keepGeofencesAlive)
        assertEquals(false, keepPeriodicAlive)
    }

    // ─────────────────────────────────────────────────────────────────────
    // Tests: startBootTracking geofence recovery (#23)
    // ─────────────────────────────────────────────────────────────────────

    @Test
    fun bootTracking_geofenceMode_shouldReRegisterGeofences() {
        // When trackingMode=1, startBootTracking should re-register
        // geofences with Play Services after creating LocationEngine.
        val (ctx, _, _) = createMockedContext()
        val state = StateManager(ctx)

        state.trackingMode = 1

        val shouldRecoverGeofences = state.trackingMode == 1
        assertEquals(true, shouldRecoverGeofences)
    }

    @Test
    fun bootTracking_continuousMode_shouldNotReRegisterGeofences() {
        val (ctx, _, _) = createMockedContext()
        val state = StateManager(ctx)

        state.trackingMode = 0

        val shouldRecoverGeofences = state.trackingMode == 1
        assertEquals(false, shouldRecoverGeofences)
    }

    @Test
    fun bootTracking_periodicMode_shouldNotReRegisterGeofences() {
        val (ctx, _, _) = createMockedContext()
        val state = StateManager(ctx)

        state.trackingMode = 2

        val shouldRecoverGeofences = state.trackingMode == 1
        assertEquals(false, shouldRecoverGeofences)
    }
}
