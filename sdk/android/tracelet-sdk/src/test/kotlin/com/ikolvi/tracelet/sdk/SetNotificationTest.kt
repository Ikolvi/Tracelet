package com.ikolvi.tracelet.sdk

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
class SetNotificationTest {
    private lateinit var sdk: TraceletSdk
    private lateinit var config: ConfigManager

    @Before
    fun setUp() {
        TraceletSdk::class.java.getDeclaredField("instance").apply {
            isAccessible = true
            set(null, null)
        }
        ConfigManager.resetInstance()
        val context = ApplicationProvider.getApplicationContext<Context>()
        sdk = TraceletSdk.getInstance(context)
        config = sdk.configManager
        config.reset(null)
        config.setConfig(mapOf("http" to mapOf("url" to "https://example.test/locations")))
    }

    @Test
    fun `text update changes only notification text and preserves url`() {
        sdk.setNotification(text = "Uploading")

        assertEquals("Uploading", config.getFgNotificationText())
        assertEquals("https://example.test/locations", config.getHttpUrl())
        assertEquals("Tracelet", config.getFgNotificationTitle())
    }

    @Test
    fun `all-null update is a no-op`() {
        val before = config.getConfig()

        sdk.setNotification()

        assertEquals(before, config.getConfig())
    }

    @Test
    fun `showTimer alone persists without inventing startedAt`() {
        sdk.setNotification(showTimer = true)

        assertTrue(config.getFgNotificationShowTimer())
        assertNull(config.getFgNotificationStartedAt())

        sdk.setNotification(showTimer = false)
        assertFalse(config.getFgNotificationShowTimer())
    }
}
