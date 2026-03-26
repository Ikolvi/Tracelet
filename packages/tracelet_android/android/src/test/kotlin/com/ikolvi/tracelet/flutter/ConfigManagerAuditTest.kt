package com.ikolvi.tracelet.flutter

import android.content.Context
import android.content.SharedPreferences
import com.ikolvi.tracelet.sdk.ConfigManager
import org.mockito.Mockito
import org.mockito.Mockito.`when`
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Tests for [ConfigManager] audit trail config getters.
 *
 * Verifies defaults, custom values via setConfig, and nested "audit" section
 * flattening.
 */
internal class ConfigManagerAuditTest {

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
    fun auditEnabled_defaultIsFalse() {
        assertEquals(false, createConfig().getAuditEnabled())
    }

    @Test
    fun auditHashAlgorithm_defaultIsSHA256() {
        assertEquals("SHA-256", createConfig().getAuditHashAlgorithm())
    }

    @Test
    fun auditIncludeExtrasInHash_defaultIsFalse() {
        assertEquals(false, createConfig().getAuditIncludeExtrasInHash())
    }

    // ── Custom values via nested "audit" section ────────────────────────────

    @Test
    fun auditEnabled_setToTrue() {
        val config = createConfig(mapOf("audit" to mapOf("enabled" to true)))
        assertEquals(true, config.getAuditEnabled())
    }

    @Test
    fun auditHashAlgorithm_setCustom() {
        val config = createConfig(mapOf("audit" to mapOf("hashAlgorithm" to "SHA-512")))
        assertEquals("SHA-512", config.getAuditHashAlgorithm())
    }

    @Test
    fun auditIncludeExtrasInHash_setToTrue() {
        val config = createConfig(mapOf("audit" to mapOf("includeExtrasInHash" to true)))
        assertEquals(true, config.getAuditIncludeExtrasInHash())
    }

    // ── All audit values set together ──────────────────────────────────────

    @Test
    fun auditConfig_setAllValues() {
        val config = createConfig(mapOf(
            "audit" to mapOf(
                "enabled" to true,
                "hashAlgorithm" to "SHA-256",
                "includeExtrasInHash" to true,
            )
        ))
        assertEquals(true, config.getAuditEnabled())
        assertEquals("SHA-256", config.getAuditHashAlgorithm())
        assertEquals(true, config.getAuditIncludeExtrasInHash())
    }

    // ── Flat keys (not nested under "audit") ───────────────────────────────

    @Test
    fun auditConfig_flatKeysWork() {
        val config = createConfig(mapOf(
            "enabled" to true,
            "includeExtrasInHash" to true,
        ))
        assertEquals(true, config.getAuditEnabled())
        assertEquals(true, config.getAuditIncludeExtrasInHash())
    }

    // ── Reset clears back to defaults ──────────────────────────────────────

    @Test
    fun reset_clearAuditConfigToDefaults() {
        val config = createConfig(mapOf(
            "audit" to mapOf(
                "enabled" to true,
                "includeExtrasInHash" to true,
            )
        ))
        assertEquals(true, config.getAuditEnabled())

        config.reset(null)

        assertEquals(false, config.getAuditEnabled())
        assertEquals(false, config.getAuditIncludeExtrasInHash())
    }
}
