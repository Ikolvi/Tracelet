package com.tracelet.tracelet_android

import android.content.Context
import android.content.SharedPreferences
import com.tracelet.core.ConfigManager
import org.mockito.Mockito
import org.mockito.Mockito.`when`
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Tests for [ConfigManager] sync feature getters:
 * - Dynamic headers (volatile)
 * - Route context (volatile)
 * - SSL pinning config
 * - Merged HTTP headers
 */
internal class ConfigManagerSyncFeaturesTest {

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

    // =========================================================================
    // Dynamic Headers
    // =========================================================================

    @Test
    fun `getDynamicHeaders returns empty map by default`() {
        val config = createConfig()
        assertEquals(emptyMap(), config.getDynamicHeaders())
    }

    @Test
    fun `setDynamicHeaders stores and retrieves headers`() {
        val config = createConfig()
        val headers = mapOf("X-Token" to "abc123", "X-Device" to "dev-1")
        config.setDynamicHeaders(headers)
        assertEquals(headers, config.getDynamicHeaders())
    }

    @Test
    fun `setDynamicHeaders replaces previous headers`() {
        val config = createConfig()
        config.setDynamicHeaders(mapOf("key1" to "val1"))
        config.setDynamicHeaders(mapOf("key2" to "val2"))
        assertEquals(mapOf("key2" to "val2"), config.getDynamicHeaders())
    }

    // =========================================================================
    // Merged HTTP Headers
    // =========================================================================

    @Test
    fun `getMergedHttpHeaders returns static headers when no dynamic headers`() {
        val config = createConfig(mapOf(
            "http" to mapOf("headers" to mapOf("Authorization" to "Bearer tok"))
        ))
        val merged = config.getMergedHttpHeaders()
        assertEquals("Bearer tok", merged["Authorization"])
    }

    @Test
    fun `getMergedHttpHeaders merges static and dynamic headers`() {
        val config = createConfig(mapOf(
            "http" to mapOf("headers" to mapOf("Authorization" to "Bearer tok"))
        ))
        config.setDynamicHeaders(mapOf("X-Custom" to "dyn-value"))
        val merged = config.getMergedHttpHeaders()
        assertEquals("Bearer tok", merged["Authorization"])
        assertEquals("dyn-value", merged["X-Custom"])
    }

    @Test
    fun `getMergedHttpHeaders dynamic headers override static`() {
        val config = createConfig(mapOf(
            "http" to mapOf("headers" to mapOf("Authorization" to "static"))
        ))
        config.setDynamicHeaders(mapOf("Authorization" to "dynamic"))
        val merged = config.getMergedHttpHeaders()
        assertEquals("dynamic", merged["Authorization"])
    }

    // =========================================================================
    // Route Context
    // =========================================================================

    @Test
    fun `getRouteContext returns empty map by default`() {
        val config = createConfig()
        assertEquals(emptyMap(), config.getRouteContext())
    }

    @Test
    fun `setRouteContext stores context`() {
        val config = createConfig()
        val ctx = mapOf<String, Any?>("taskId" to "delivery-42", "driverId" to "driver-7")
        config.setRouteContext(ctx)
        assertEquals(ctx, config.getRouteContext())
    }

    @Test
    fun `clearRouteContext resets to empty map`() {
        val config = createConfig()
        config.setRouteContext(mapOf("taskId" to "task-1"))
        config.clearRouteContext()
        assertEquals(emptyMap(), config.getRouteContext())
    }

    @Test
    fun `setRouteContext replaces previous context`() {
        val config = createConfig()
        config.setRouteContext(mapOf("taskId" to "task-1"))
        config.setRouteContext(mapOf("taskId" to "task-2"))
        assertEquals(mapOf<String, Any?>("taskId" to "task-2"), config.getRouteContext())
    }

    // =========================================================================
    // SSL Pinning Config
    // =========================================================================

    @Test
    fun `getSslPinningCertificates returns empty list by default`() {
        val config = createConfig()
        assertTrue(config.getSslPinningCertificates().isEmpty())
    }

    @Test
    fun `getSslPinningCertificates returns configured certificates`() {
        val config = createConfig(mapOf(
            "http" to mapOf(
                "sslPinningCertificates" to listOf("cert1-base64", "cert2-base64")
            )
        ))
        val certs = config.getSslPinningCertificates()
        assertEquals(2, certs.size)
        assertEquals("cert1-base64", certs[0])
        assertEquals("cert2-base64", certs[1])
    }

    @Test
    fun `getSslPinningFingerprints returns empty list by default`() {
        val config = createConfig()
        assertTrue(config.getSslPinningFingerprints().isEmpty())
    }

    @Test
    fun `getSslPinningFingerprints returns configured fingerprints`() {
        val config = createConfig(mapOf(
            "http" to mapOf(
                "sslPinningFingerprints" to listOf("sha256/AAAA", "sha256/BBBB")
            )
        ))
        val fps = config.getSslPinningFingerprints()
        assertEquals(2, fps.size)
        assertEquals("sha256/AAAA", fps[0])
        assertEquals("sha256/BBBB", fps[1])
    }
}
