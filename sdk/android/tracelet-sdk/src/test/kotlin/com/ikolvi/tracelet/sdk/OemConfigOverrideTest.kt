package com.ikolvi.tracelet.sdk

import android.content.Context
import android.os.Build
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.util.ReflectionHelpers

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [30])
class OemConfigOverrideTest {

    private lateinit var context: Context
    private lateinit var configManager: ConfigManager

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        configManager = ConfigManager.getInstance(context)
        // Reset config before each test
        configManager.reset(null)
    }

    @After
    fun tearDown() {
        // Reset back to normal to avoid polluting other tests
        ReflectionHelpers.setStaticField(Build::class.java, "MANUFACTURER", "unknown")
    }

    /**
     * #243: the foreground-service flags are authoritative. Aggressive OEMs no
     * longer silently force the service (and its notification) back on — the
     * SDK logs a reliability warning at start()/startPeriodic() instead.
     * Geofence high-accuracy mode keeps its OEM override (no notification
     * involved; plain geofences are unreliable on these devices).
     */
    @Test
    fun testRestrictedOem_ExplicitForegroundDisable_IsHonored() {
        ReflectionHelpers.setStaticField(Build::class.java, "MANUFACTURER", "Xiaomi")

        configManager.setConfig(mapOf(
            "android" to mapOf(
                "foregroundService" to mapOf("enabled" to false),
                "periodicUseForegroundService" to false,
            )
        ))

        assertFalse(configManager.isForegroundServiceEnabled())
        assertFalse(configManager.getPeriodicUseForegroundService())
    }

    @Test
    fun testRestrictedOem_Defaults_AreNotForced() {
        ReflectionHelpers.setStaticField(Build::class.java, "MANUFACTURER", "OPPO")

        // Defaults apply as-is: FG service defaults to true on its own merits,
        // periodic mode defaults to the WorkManager (no-service) strategy.
        assertTrue(configManager.isForegroundServiceEnabled())
        assertFalse(configManager.getPeriodicUseForegroundService())
        // Geofence high-accuracy override is intentionally kept for OEMs.
        assertTrue(configManager.getGeofenceModeHighAccuracy())
    }

    @Test
    fun testStandardOem_Google_ReturnsConfiguredValue() {
        ReflectionHelpers.setStaticField(Build::class.java, "MANUFACTURER", "Google")

        // Should return defaults (true for FG, false for geofence mode)
        assertTrue(configManager.isForegroundServiceEnabled()) // Default is true
        assertFalse(configManager.getGeofenceModeHighAccuracy()) // Default is false
        assertFalse(configManager.getPeriodicUseForegroundService()) // Default is false

        // Change config to false/true
        configManager.setConfig(mapOf(
            "android" to mapOf(
                "foregroundService" to mapOf("enabled" to false),
                "periodicUseForegroundService" to true,
                "geofenceModeHighAccuracy" to true
            )
        ))

        assertFalse(configManager.isForegroundServiceEnabled())
        assertTrue(configManager.getGeofenceModeHighAccuracy())
        assertTrue(configManager.getPeriodicUseForegroundService())
    }

    @Test
    fun testRestrictedOem_DoesNotOverrideShowNotificationOnPauseOnly() {
        ReflectionHelpers.setStaticField(Build::class.java, "MANUFACTURER", "vivo")

        // Default is false
        assertFalse(configManager.getShowNotificationOnPauseOnly())

        // Change config to true
        configManager.setConfig(mapOf(
            "android" to mapOf("foregroundService" to mapOf("showNotificationOnPauseOnly" to true))
        ))

        // Should be true now, untouched by the OEM override
        assertTrue(configManager.getShowNotificationOnPauseOnly())
    }
}
