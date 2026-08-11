package com.ikolvi.tracelet.sdk

import android.content.Context
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows
import org.robolectric.annotation.Config

/**
 * #320: a partial `setConfig()` must not overwrite the persisted
 * foreground-service configuration with defaults.
 *
 * `setConfig()` is a merge, and the merge already skipped nulls — but the Dart
 * model declared every field non-nullable with a default, so it never sent one.
 * A `setConfig()` that did not mention `foregroundService` therefore arrived as
 * a complete section of defaults and was written over the stored values, and
 * `persistToPrefs()` made that survive process death. The visible symptom was
 * `showNotificationOnPauseOnly: true` quietly reverting to `false`, so the
 * tracking notification appeared while the app was foregrounded.
 *
 * These tests pin the native half of the contract: an absent or null field
 * leaves the persisted value alone, and an explicitly supplied one overwrites
 * it even when it equals the default.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [30])
class ForegroundServicePartialConfigTest {

    private lateinit var context: Context
    private lateinit var configManager: ConfigManager

    /** The configuration an app applies once, through `ready()`. */
    private fun fullForegroundServiceConfig(): Map<String, Any?> = mapOf(
        "android" to mapOf(
            "foregroundService" to mapOf(
                "notificationTitle" to "📍 Tracelet Demo Active",
                "channelId" to "tracelet_demo_channel",
                "channelName" to "Tracelet Demo Background",
                "showNotificationOnPauseOnly" to true,
                "notificationStartedAt" to 4_294_967_296L,
                "notificationShowTimer" to true,
                "notificationOnlyAlertOnce" to true,
            ),
        ),
    )

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        // Constructed directly rather than via getInstance(): the singleton is
        // a static that outlives Robolectric's per-method Application, so it
        // would keep writing to the previous test's SharedPreferences.
        configManager = ConfigManager(context)
        configManager.reset(null)
    }

    /**
     * The exact reported failure: configure the notification, then make a
     * `setConfig()` call about something else entirely.
     */
    @Test
    fun testPartialSetConfig_OmittingForegroundService_PreservesStoredValues() {
        configManager.setConfig(fullForegroundServiceConfig())
        assertTrue(configManager.getShowNotificationOnPauseOnly())

        configManager.setConfig(mapOf("geo" to mapOf("distanceFilter" to 25.0)))

        assertTrue(
            "showNotificationOnPauseOnly must survive a setConfig() that does not mention it",
            configManager.getShowNotificationOnPauseOnly(),
        )
        assertEquals("📍 Tracelet Demo Active", configManager.getFgNotificationTitle())
        assertEquals("tracelet_demo_channel", configManager.getFgChannelId())
        assertEquals("Tracelet Demo Background", configManager.getFgChannelName())
        assertEquals(4_294_967_296L, configManager.getFgNotificationStartedAt())
        assertTrue(configManager.getFgNotificationShowTimer())
        assertTrue(configManager.getFgNotificationOnlyAlertOnce())
    }

    /**
     * What the fixed Dart layer actually puts on the wire for a `Config()` that
     * does not configure the foreground service: the section is present, but
     * every field in it is null.
     */
    @Test
    fun testAllNullForegroundServiceSection_PreservesStoredValues() {
        configManager.setConfig(fullForegroundServiceConfig())

        configManager.setConfig(
            mapOf(
                "android" to mapOf(
                    "foregroundService" to mapOf(
                        "enabled" to null,
                        "channelId" to null,
                        "channelName" to null,
                        "notificationTitle" to null,
                        "notificationText" to null,
                        "notificationPriority" to null,
                        "notificationOngoing" to null,
                        "showNotificationOnPauseOnly" to null,
                        "notificationStartedAt" to null,
                        "notificationShowTimer" to null,
                        "notificationOnlyAlertOnce" to null,
                        "actions" to null,
                    ),
                ),
            ),
        )

        assertTrue(configManager.getShowNotificationOnPauseOnly())
        assertEquals("📍 Tracelet Demo Active", configManager.getFgNotificationTitle())
        assertEquals("tracelet_demo_channel", configManager.getFgChannelId())
        assertEquals(4_294_967_296L, configManager.getFgNotificationStartedAt())
        assertTrue(configManager.getFgNotificationShowTimer())
        assertTrue(configManager.getFgNotificationOnlyAlertOnce())
    }

    /**
     * The flag has to remain settable back to false. "Unset" means *not
     * supplied*, never *equal to the default* — a fix that dropped
     * default-valued fields would be a worse bug than the one being fixed.
     */
    @Test
    fun testExplicitFalse_OverwritesStoredTrue() {
        configManager.setConfig(fullForegroundServiceConfig())
        assertTrue(configManager.getShowNotificationOnPauseOnly())

        configManager.setConfig(
            mapOf(
                "android" to mapOf(
                    "foregroundService" to mapOf(
                        "showNotificationOnPauseOnly" to false,
                        "notificationOnlyAlertOnce" to false,
                    ),
                ),
            ),
        )

        assertFalse(configManager.getShowNotificationOnPauseOnly())
        assertFalse(configManager.getFgNotificationOnlyAlertOnce())
        // The fields alongside it were not supplied, so they are untouched.
        assertEquals("📍 Tracelet Demo Active", configManager.getFgNotificationTitle())
    }

    /**
     * Nothing configured at all still yields the documented defaults, which are
     * identical to the Dart-side defaults — so omitting an unset field cannot
     * change behaviour on a fresh install.
     */
    @Test
    fun testUnconfiguredForegroundService_FallsBackToDocumentedDefaults() {
        configManager.setConfig(mapOf("geo" to mapOf("distanceFilter" to 10.0)))

        assertTrue(configManager.isForegroundServiceEnabled())
        assertEquals("tracelet_channel", configManager.getFgChannelId())
        assertEquals("Tracelet", configManager.getFgChannelName())
        assertEquals("Tracelet", configManager.getFgNotificationTitle())
        assertEquals(
            "Tracking location in background",
            configManager.getFgNotificationText(),
        )
        assertTrue(configManager.getFgNotificationOngoing())
        assertFalse(configManager.getShowNotificationOnPauseOnly())
        assertNull(configManager.getFgNotificationStartedAt())
        assertFalse(configManager.getFgNotificationShowTimer())
        assertFalse(configManager.getFgNotificationOnlyAlertOnce())
    }

    /** The merged result is persisted, so it has to survive a new instance. */
    @Test
    fun testPreservedValues_SurviveReload() {
        configManager.setConfig(fullForegroundServiceConfig())
        configManager.setConfig(mapOf("app" to mapOf("stopOnTerminate" to false)))

        // persistToPrefs() uses apply(), which defers the disk write; drain it
        // so the new instance reads what was actually written rather than an
        // empty file.
        Shadows.shadowOf(Looper.getMainLooper()).idle()

        val reloaded = ConfigManager(context)

        assertTrue(reloaded.getShowNotificationOnPauseOnly())
        assertEquals(4_294_967_296L, reloaded.getFgNotificationStartedAt())
        assertTrue(reloaded.getFgNotificationShowTimer())
        assertTrue(reloaded.getFgNotificationOnlyAlertOnce())
        assertEquals("📍 Tracelet Demo Active", reloaded.getFgNotificationTitle())
    }

    /** Small Kotlin Int values must be accepted by the epoch-millis getter. */
    @Test
    fun testSmallIntNotificationStartedAt_SurvivesAsLong() {
        configManager.setConfig(
            mapOf(
                "android" to mapOf(
                    "foregroundService" to mapOf("notificationStartedAt" to 1234),
                ),
            ),
        )

        assertEquals(1234L, configManager.getFgNotificationStartedAt())

        Shadows.shadowOf(Looper.getMainLooper()).idle()
        val reloaded = ConfigManager(context)
        assertEquals(1234L, reloaded.getFgNotificationStartedAt())
    }
}
