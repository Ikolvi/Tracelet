package com.ikolvi.tracelet.flutter

import android.content.Context
import android.content.SharedPreferences
import com.ikolvi.tracelet.sdk.ConfigManager
import org.mockito.Mockito
import org.mockito.Mockito.`when`
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Tests for [ConfigManager] privacy zone config getters.
 *
 * Verifies defaults, custom values via setConfig (nested "privacyZone"
 * section), flat keys, and reset behaviour.
 */
internal class ConfigManagerPrivacyZoneTest {

    /**
     * Creates a [ConfigManager] backed by a mocked SharedPreferences.
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

    // ── Default values ─────────────────────────────────────────────────────

    @Test
    fun privacyZoneEnabled_defaultIsFalse() {
        assertEquals(false, createConfig().getPrivacyZoneEnabled())
    }

    // ── Custom values via nested "privacyZone" section ──────────────────────

    @Test
    fun privacyZoneEnabled_setToTrue_viaNestedSection() {
        val config = createConfig(mapOf(
            "privacyZone" to mapOf("privacyZoneEnabled" to true),
        ))
        assertEquals(true, config.getPrivacyZoneEnabled())
    }

    @Test
    fun privacyZoneEnabled_setToFalse_viaNestedSection() {
        val config = createConfig(mapOf(
            "privacyZone" to mapOf("privacyZoneEnabled" to false),
        ))
        assertEquals(false, config.getPrivacyZoneEnabled())
    }

    // ── Flat key (not nested under "privacyZone") ──────────────────────────

    @Test
    fun privacyZoneEnabled_flatKeyWorks() {
        val config = createConfig(mapOf(
            "privacyZoneEnabled" to true,
        ))
        assertEquals(true, config.getPrivacyZoneEnabled())
    }

    // ── Does not collide with audit "enabled" key ──────────────────────────

    @Test
    fun privacyZoneEnabled_doesNotCollideWithAuditEnabled() {
        val config = createConfig(mapOf(
            "audit" to mapOf("enabled" to true),
            "privacyZone" to mapOf("privacyZoneEnabled" to false),
        ))
        // audit.enabled should be true, privacy zone should be false
        assertEquals(true, config.getAuditEnabled())
        assertEquals(false, config.getPrivacyZoneEnabled())
    }

    @Test
    fun auditEnabled_doesNotAffectPrivacyZone() {
        val config = createConfig(mapOf(
            "audit" to mapOf("enabled" to true),
        ))
        // privacyZoneEnabled should still be default false
        assertEquals(true, config.getAuditEnabled())
        assertEquals(false, config.getPrivacyZoneEnabled())
    }

    @Test
    fun privacyZoneEnabled_doesNotAffectAudit() {
        val config = createConfig(mapOf(
            "privacyZone" to mapOf("privacyZoneEnabled" to true),
        ))
        // audit enabled should still be default false
        assertEquals(false, config.getAuditEnabled())
        assertEquals(true, config.getPrivacyZoneEnabled())
    }

    // ── Reset clears back to defaults ──────────────────────────────────────

    @Test
    fun reset_clearsPrivacyZoneConfigToDefaults() {
        val config = createConfig(mapOf(
            "privacyZone" to mapOf("privacyZoneEnabled" to true),
        ))
        assertEquals(true, config.getPrivacyZoneEnabled())

        config.reset(null)

        assertEquals(false, config.getPrivacyZoneEnabled())
    }

    @Test
    fun reset_clearsPrivacyZoneWithoutAffectingSubsequentSets() {
        val config = createConfig(mapOf(
            "privacyZone" to mapOf("privacyZoneEnabled" to true),
        ))
        assertEquals(true, config.getPrivacyZoneEnabled())

        config.reset(null)
        assertEquals(false, config.getPrivacyZoneEnabled())

        // Setting again should work
        config.setConfig(mapOf("privacyZoneEnabled" to true))
        assertEquals(true, config.getPrivacyZoneEnabled())
    }
}
