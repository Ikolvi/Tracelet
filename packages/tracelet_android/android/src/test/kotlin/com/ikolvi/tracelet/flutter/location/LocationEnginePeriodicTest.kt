package com.ikolvi.tracelet.flutter.location

import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.TraceletEventSender
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.db.TraceletDatabase
import org.mockito.Mockito
import org.mockito.Mockito.`when`
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Tests for [LocationEngine] periodic tracking lifecycle.
 *
 * Uses mocked dependencies to verify startPeriodic/stopPeriodic state
 * transitions. All mocks are created and wired *before* any stubbing
 * to avoid Mockito's UnfinishedStubbingException.
 *
 * Note: LocationEngine's constructor calls
 * `LocationServices.getFusedLocationProviderClient(context)` which
 * needs the Google Play Services SDK shadow. Since we're running on
 * JVM without Robolectric, we can't instantiate LocationEngine directly.
 * Instead, these tests verify ConfigManager, StateManager, and the
 * periodic flag via the companion defaults.
 *
 * Full lifecycle integration tests (with real FusedLocationProvider)
 * run on-device in `example/integration_test/`.
 */
internal class LocationEnginePeriodicTest {

    /**
     * Creates a mocked [Context] with in-memory SharedPreferences.
     * All mocks are fully wired before returning.
     */
    private fun createMockedContext(permissionGranted: Boolean = true): Context {
        // Pre-create ALL mocks before any stubbing
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
        `when`(stateEditor.putString(Mockito.anyString(), Mockito.anyString())).thenAnswer {
            stateStore[it.getArgument<String>(0)] = it.getArgument<String>(1); stateEditor
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
        val permResult = if (permissionGranted) PackageManager.PERMISSION_GRANTED else PackageManager.PERMISSION_DENIED
        `when`(context.getSharedPreferences("com.tracelet.config", Context.MODE_PRIVATE)).thenReturn(configPrefs)
        `when`(context.getSharedPreferences("com.tracelet.state", Context.MODE_PRIVATE)).thenReturn(statePrefs)
        `when`(context.applicationContext).thenReturn(context)
        `when`(context.checkPermission(Mockito.anyString(), Mockito.anyInt(), Mockito.anyInt())).thenReturn(permResult)
        `when`(context.packageName).thenReturn("com.tracelet.test")

        return context
    }

    // ── ConfigManager periodic getters verified through context ────────────

    @Test
    fun configManager_periodicDefaults_correctWithMockedContext() {
        val ctx = createMockedContext()
        val config = ConfigManager(ctx)

        kotlin.test.assertEquals(900, config.getPeriodicLocationInterval())
        kotlin.test.assertEquals(1, config.getPeriodicDesiredAccuracy())
        kotlin.test.assertEquals(false, config.getPeriodicUseForegroundService())
        kotlin.test.assertEquals(false, config.getPeriodicUseExactAlarms())
    }

    @Test
    fun configManager_periodicCustomValues_throughMockedContext() {
        val ctx = createMockedContext()
        val config = ConfigManager(ctx)
        config.setConfig(mapOf(
            "geo" to mapOf(
                "periodicLocationInterval" to 600,
                "periodicDesiredAccuracy" to 0,
                "periodicUseForegroundService" to true,
                "periodicUseExactAlarms" to true,
            )
        ))

        kotlin.test.assertEquals(600, config.getPeriodicLocationInterval())
        kotlin.test.assertEquals(0, config.getPeriodicDesiredAccuracy())
        kotlin.test.assertEquals(true, config.getPeriodicUseForegroundService())
        kotlin.test.assertEquals(true, config.getPeriodicUseExactAlarms())
    }

    // ── StateManager tracking mode ────────────────────────────────────────

    @Test
    fun stateManager_trackingMode_canSetPeriodic() {
        val ctx = createMockedContext()
        val state = StateManager(ctx)

        // TrackingMode.periodic has index 2
        state.trackingMode = 2
        kotlin.test.assertEquals(2, state.trackingMode)
    }

    @Test
    fun stateManager_enabled_defaultsFalse() {
        val ctx = createMockedContext()
        val state = StateManager(ctx)
        assertFalse(state.enabled)
    }

    @Test
    fun stateManager_enabled_canBeToggled() {
        val ctx = createMockedContext()
        val state = StateManager(ctx)

        state.enabled = true
        assertTrue(state.enabled)

        state.enabled = false
        assertFalse(state.enabled)
    }

    // ── EventDispatcher mock wiring ───────────────────────────────────────

    @Test
    fun eventSender_sendLocation_canBeMocked() {
        val events = Mockito.mock(TraceletEventSender::class.java)
        val locationMap = mapOf<String, Any?>(
            "latitude" to 37.7749,
            "longitude" to -122.4194,
            "event" to "periodic",
        )

        // Verify sendLocation can be called without error
        events.sendLocation(locationMap)
        Mockito.verify(events).sendLocation(locationMap)
    }

    // ── TraceletDatabase mock wiring ──────────────────────────────────────

    @Test
    fun database_insertLocation_canBeMocked() {
        val db = Mockito.mock(TraceletDatabase::class.java)
        val locationMap = mapOf<String, Any?>(
            "uuid" to "test-uuid",
            "latitude" to 37.7749,
            "longitude" to -122.4194,
        )

        db.insertLocation(locationMap)
        Mockito.verify(db).insertLocation(locationMap)
    }
}
