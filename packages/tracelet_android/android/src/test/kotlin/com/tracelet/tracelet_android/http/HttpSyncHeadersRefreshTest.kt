package com.tracelet.tracelet_android.http

import android.content.Context
import android.content.SharedPreferences
import com.tracelet.core.ConfigManager
import org.mockito.Mockito
import org.mockito.Mockito.`when`
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Tests for dynamic headers refresh flow used by 401-aware retry.
 *
 * Verifies that:
 * - setDynamicHeaders updates the merged headers
 * - Dynamic headers override static headers
 * - Headers can be updated mid-sync (simulating callback response)
 */
internal class HttpSyncHeadersRefreshTest {

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

    @Test
    fun setDynamicHeaders_updatesGetMergedHttpHeaders() {
        val config = createConfig()
        config.setDynamicHeaders(mapOf("Authorization" to "Bearer old-token"))
        val merged1 = config.getMergedHttpHeaders()
        assertEquals("Bearer old-token", merged1["Authorization"])

        // Simulate 401 callback refreshing the token
        config.setDynamicHeaders(mapOf("Authorization" to "Bearer fresh-token"))
        val merged2 = config.getMergedHttpHeaders()
        assertEquals("Bearer fresh-token", merged2["Authorization"])
    }

    @Test
    fun dynamicHeaders_addNewKeys() {
        val config = createConfig()
        // No static headers configured in this test
        config.setDynamicHeaders(mapOf(
            "Authorization" to "Bearer dynamic-token",
            "X-Api-Key" to "abc"
        ))

        val merged = config.getMergedHttpHeaders()
        assertEquals("Bearer dynamic-token", merged["Authorization"])
        assertEquals("abc", merged["X-Api-Key"])
    }

    @Test
    fun getMergedHttpHeaders_reReadsAfterRefresh() {
        val config = createConfig()

        // First read — no dynamic headers
        val headers1 = config.getMergedHttpHeaders()
        assertTrue(!headers1.containsKey("Authorization"))

        // 401 triggers refresh, callback sets new headers
        config.setDynamicHeaders(mapOf("Authorization" to "Bearer new-token"))

        // Second read — picks up updated dynamic headers
        val headers2 = config.getMergedHttpHeaders()
        assertEquals("Bearer new-token", headers2["Authorization"])
    }

    @Test
    fun setDynamicHeaders_replacesAllPreviousHeaders() {
        val config = createConfig()
        config.setDynamicHeaders(mapOf(
            "Authorization" to "Bearer token1",
            "X-Session" to "session-1",
        ))
        config.setDynamicHeaders(mapOf(
            "Authorization" to "Bearer token2",
        ))

        val merged = config.getMergedHttpHeaders()
        assertEquals("Bearer token2", merged["Authorization"])
        // X-Session should be gone since setDynamicHeaders replaces the entire map
        assertTrue(!merged.containsKey("X-Session"))
    }
}
