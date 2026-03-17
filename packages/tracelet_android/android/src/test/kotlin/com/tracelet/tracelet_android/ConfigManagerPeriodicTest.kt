package com.tracelet.tracelet_android

import android.content.Context
import android.content.SharedPreferences
import com.tracelet.core.ConfigManager
import org.mockito.Mockito
import org.mockito.Mockito.`when`
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Tests for [ConfigManager] periodic location getters.
 *
 * Uses mocked SharedPreferences to verify default values and config
 * persistence for the four periodic config options.
 */
internal class ConfigManagerPeriodicTest {

    /**
     * Creates a [ConfigManager] backed by a mocked [Context] whose
     * SharedPreferences works via a fully-mocked in-memory implementation.
     */
    private fun createConfig(initialValues: Map<String, Any?> = emptyMap()): ConfigManager {
        val store = mutableMapOf<String, Any?>()

        val editor = Mockito.mock(SharedPreferences.Editor::class.java)
        `when`(editor.putString(Mockito.anyString(), Mockito.anyString())).thenAnswer {
            store[it.getArgument<String>(0)] = it.getArgument<String>(1)
            editor
        }
        `when`(editor.remove(Mockito.anyString())).thenAnswer {
            store.remove(it.getArgument<String>(0))
            editor
        }
        `when`(editor.clear()).thenAnswer {
            store.clear()
            editor
        }
        `when`(editor.commit()).thenReturn(true)
        // apply() is void — no stub needed, default returns null

        val prefs = Mockito.mock(SharedPreferences::class.java)
        `when`(prefs.edit()).thenReturn(editor)
        `when`(prefs.contains(Mockito.anyString())).thenAnswer {
            store.containsKey(it.getArgument<String>(0))
        }
        `when`(prefs.getString(Mockito.anyString(), Mockito.nullable(String::class.java))).thenAnswer {
            store[it.getArgument<String>(0)] as? String ?: it.getArgument<String?>(1)
        }

        val context = Mockito.mock(Context::class.java)
        `when`(context.getSharedPreferences("com.tracelet.config", Context.MODE_PRIVATE)).thenReturn(prefs)
        `when`(context.applicationContext).thenReturn(context)

        val configManager = ConfigManager(context)

        if (initialValues.isNotEmpty()) {
            configManager.setConfig(initialValues)
        }

        return configManager
    }

    // ── Default values ────────────────────────────────────────────────────

    @Test
    fun periodicLocationInterval_defaultIs900() {
        assertEquals(900, createConfig().getPeriodicLocationInterval())
    }

    @Test
    fun periodicDesiredAccuracy_defaultIs1_medium() {
        assertEquals(1, createConfig().getPeriodicDesiredAccuracy())
    }

    @Test
    fun periodicUseForegroundService_defaultIsFalse() {
        assertEquals(false, createConfig().getPeriodicUseForegroundService())
    }

    @Test
    fun periodicUseExactAlarms_defaultIsFalse() {
        assertEquals(false, createConfig().getPeriodicUseExactAlarms())
    }

    // ── Custom values via setConfig ───────────────────────────────────────

    @Test
    fun periodicLocationInterval_setCustomValue() {
        val config = createConfig(mapOf("geo" to mapOf("periodicLocationInterval" to 1800)))
        assertEquals(1800, config.getPeriodicLocationInterval())
    }

    @Test
    fun periodicDesiredAccuracy_setToHigh() {
        val config = createConfig(mapOf("geo" to mapOf("periodicDesiredAccuracy" to 0)))
        assertEquals(0, config.getPeriodicDesiredAccuracy())
    }

    @Test
    fun periodicDesiredAccuracy_setToLow() {
        val config = createConfig(mapOf("geo" to mapOf("periodicDesiredAccuracy" to 2)))
        assertEquals(2, config.getPeriodicDesiredAccuracy())
    }

    @Test
    fun periodicUseForegroundService_setToTrue() {
        val config = createConfig(mapOf("geo" to mapOf("periodicUseForegroundService" to true)))
        assertEquals(true, config.getPeriodicUseForegroundService())
    }

    @Test
    fun periodicUseExactAlarms_setToTrue() {
        val config = createConfig(mapOf("geo" to mapOf("periodicUseExactAlarms" to true)))
        assertEquals(true, config.getPeriodicUseExactAlarms())
    }

    // ── Multiple periodic values set together ─────────────────────────────

    @Test
    fun periodicConfig_setAllValues() {
        val config = createConfig(mapOf(
            "geo" to mapOf(
                "periodicLocationInterval" to 600,
                "periodicDesiredAccuracy" to 2,
                "periodicUseForegroundService" to true,
                "periodicUseExactAlarms" to true,
            )
        ))
        assertEquals(600, config.getPeriodicLocationInterval())
        assertEquals(2, config.getPeriodicDesiredAccuracy())
        assertEquals(true, config.getPeriodicUseForegroundService())
        assertEquals(true, config.getPeriodicUseExactAlarms())
    }

    // ── Flat keys (not nested under "geo") ────────────────────────────────

    @Test
    fun periodicConfig_flatKeysWork() {
        val config = createConfig(mapOf(
            "periodicLocationInterval" to 300,
            "periodicDesiredAccuracy" to 3,
        ))
        assertEquals(300, config.getPeriodicLocationInterval())
        assertEquals(3, config.getPeriodicDesiredAccuracy())
    }

    // ── Reset clears back to defaults ─────────────────────────────────────

    @Test
    fun reset_clearPeriodicConfigToDefaults() {
        val config = createConfig(mapOf(
            "geo" to mapOf(
                "periodicLocationInterval" to 60,
                "periodicUseForegroundService" to true,
            )
        ))
        assertEquals(60, config.getPeriodicLocationInterval())
        assertEquals(true, config.getPeriodicUseForegroundService())

        config.reset(null)

        assertEquals(900, config.getPeriodicLocationInterval())
        assertEquals(false, config.getPeriodicUseForegroundService())
    }

    // ── setConfig merges, doesn't wipe ────────────────────────────────────

    @Test
    fun setConfig_mergesWithExisting() {
        val config = createConfig(mapOf(
            "geo" to mapOf("periodicLocationInterval" to 1200)
        ))
        config.setConfig(mapOf(
            "geo" to mapOf("periodicUseForegroundService" to true)
        ))

        assertEquals(1200, config.getPeriodicLocationInterval())
        assertEquals(true, config.getPeriodicUseForegroundService())
    }
}
