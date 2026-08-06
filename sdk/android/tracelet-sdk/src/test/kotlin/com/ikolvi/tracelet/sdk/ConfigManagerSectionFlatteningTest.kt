package com.ikolvi.tracelet.sdk

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Tests for [ConfigManager.setConfig] section flattening.
 *
 * Regression tests for [Issue #74](https://github.com/Ikolvi/Tracelet/discussions/74):
 * custom Android-specific config (foreground service notification, `deferTime`, etc.)
 * was silently ignored because `"android"`, `"security"`, and `"attestation"` were
 * not listed in `sectionKeys` and therefore never flattened into the top-level
 * config cache.
 *
 * These tests simulate the exact nested map structures produced by
 * `TraceletHostApiImpl.tlConfigToSdkMap()` and verify every typed getter returns
 * the configured value instead of the default.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
internal class ConfigManagerSectionFlatteningTest {

    private lateinit var context: Context
    private lateinit var config: ConfigManager

    @Before
    fun setUp() {
        ConfigManager.resetInstance()
        context = ApplicationProvider.getApplicationContext()
        config = ConfigManager.getInstance(context)
        config.reset(null)
    }

    @After
    fun tearDown() {
        ConfigManager.resetInstance()
    }

    // =========================================================================
    // Issue #74 — Android section flattening
    // =========================================================================

    @Test
    fun androidSection_deferTime_isFlattened() {
        config.setConfig(mapOf(
            "android" to mapOf<String, Any?>(
                "deferTime" to 60000
            )
        ))
        assertEquals(60000, config.getDeferTime())
    }

    @Test
    fun androidSection_locationUpdateInterval_isFlattened() {
        config.setConfig(mapOf(
            "android" to mapOf<String, Any?>(
                "locationUpdateInterval" to 10000L
            )
        ))
        assertEquals(10000L, config.getLocationUpdateInterval())
    }

    @Test
    fun androidSection_fastestLocationUpdateInterval_isFlattened() {
        config.setConfig(mapOf(
            "android" to mapOf<String, Any?>(
                "fastestLocationUpdateInterval" to 5000L
            )
        ))
        assertEquals(5000L, config.getFastestLocationUpdateInterval())
    }

    @Test
    fun androidSection_allowIdenticalLocations_isFlattened() {
        config.setConfig(mapOf(
            "android" to mapOf<String, Any?>(
                "allowIdenticalLocations" to true
            )
        ))
        assertTrue(config.getAllowIdenticalLocations())
    }

    @Test
    fun androidSection_periodicUseForegroundService_isFlattened() {
        config.setConfig(mapOf(
            "android" to mapOf<String, Any?>(
                "periodicUseForegroundService" to true
            )
        ))
        assertTrue(config.getPeriodicUseForegroundService())
    }

    @Test
    fun androidSection_periodicUseExactAlarms_isFlattened() {
        config.setConfig(mapOf(
            "android" to mapOf<String, Any?>(
                "periodicUseExactAlarms" to true
            )
        ))
        assertTrue(config.getPeriodicUseExactAlarms())
    }

    // =========================================================================
    // Issue #74 — Foreground service nested inside android section
    // =========================================================================

    @Test
    fun androidSection_foregroundService_notificationTitle_isFlattenedWithPrefix() {
        config.setConfig(mapOf(
            "android" to mapOf<String, Any?>(
                "foregroundService" to mapOf<String, Any?>(
                    "notificationTitle" to "My Custom Title"
                )
            )
        ))
        assertEquals("My Custom Title", config.getFgNotificationTitle())
    }

    @Test
    fun androidSection_foregroundService_notificationText_isFlattenedWithPrefix() {
        config.setConfig(mapOf(
            "android" to mapOf<String, Any?>(
                "foregroundService" to mapOf<String, Any?>(
                    "notificationText" to "Custom tracking text"
                )
            )
        ))
        assertEquals("Custom tracking text", config.getFgNotificationText())
    }

    @Test
    fun androidSection_foregroundService_channelId_isFlattenedWithPrefix() {
        config.setConfig(mapOf(
            "android" to mapOf<String, Any?>(
                "foregroundService" to mapOf<String, Any?>(
                    "channelId" to "x_background_service"
                )
            )
        ))
        assertEquals("x_background_service", config.getFgChannelId())
    }

    @Test
    fun androidSection_foregroundService_channelName_isFlattenedWithPrefix() {
        config.setConfig(mapOf(
            "android" to mapOf<String, Any?>(
                "foregroundService" to mapOf<String, Any?>(
                    "channelName" to "X Background Service"
                )
            )
        ))
        assertEquals("X Background Service", config.getFgChannelName())
    }

    @Test
    fun androidSection_foregroundService_notificationPriority_isFlattenedWithPrefix() {
        config.setConfig(mapOf(
            "android" to mapOf<String, Any?>(
                "foregroundService" to mapOf<String, Any?>(
                    "notificationPriority" to 3 // HIGH
                )
            )
        ))
        assertEquals(3, config.getFgNotificationPriority())
    }

    @Test
    fun androidSection_foregroundService_enabled_isFlattenedWithPrefix() {
        // Default is true, so set to false to verify flattening
        config.setConfig(mapOf(
            "android" to mapOf<String, Any?>(
                "foregroundService" to mapOf<String, Any?>(
                    "enabled" to false
                )
            )
        ))
        assertFalse(config.isForegroundServiceEnabled())
    }

    @Test
    fun androidSection_foregroundService_notificationOngoing_isFlattenedWithPrefix() {
        // Default is true, set to false
        config.setConfig(mapOf(
            "android" to mapOf<String, Any?>(
                "foregroundService" to mapOf<String, Any?>(
                    "notificationOngoing" to false
                )
            )
        ))
        assertFalse(config.getFgNotificationOngoing())
    }

    @Test
    fun androidSection_foregroundService_notificationColor_isFlattenedWithPrefix() {
        config.setConfig(mapOf(
            "android" to mapOf<String, Any?>(
                "foregroundService" to mapOf<String, Any?>(
                    "notificationColor" to "#FF0000"
                )
            )
        ))
        assertEquals("#FF0000", config.getFgNotificationColor())
    }

    @Test
    fun androidSection_foregroundService_notificationSmallIcon_isFlattenedWithPrefix() {
        config.setConfig(mapOf(
            "android" to mapOf<String, Any?>(
                "foregroundService" to mapOf<String, Any?>(
                    "notificationSmallIcon" to "ic_my_notification"
                )
            )
        ))
        assertEquals("ic_my_notification", config.getFgNotificationSmallIcon())
    }

    @Test
    fun androidSection_foregroundService_notificationLargeIcon_isFlattenedWithPrefix() {
        config.setConfig(mapOf(
            "android" to mapOf<String, Any?>(
                "foregroundService" to mapOf<String, Any?>(
                    "notificationLargeIcon" to "ic_my_large"
                )
            )
        ))
        assertEquals("ic_my_large", config.getFgNotificationLargeIcon())
    }

    @Test
    fun androidSection_foregroundService_actions_isFlattenedWithPrefix() {
        config.setConfig(mapOf(
            "android" to mapOf<String, Any?>(
                "foregroundService" to mapOf<String, Any?>(
                    "actions" to listOf("pause", "resume")
                )
            )
        ))
        assertEquals(listOf("pause", "resume"), config.getFgActions())
    }

    @Test
    fun androidSection_foregroundService_nullValuesSkipped() {
        // null values inside foregroundService should not overwrite existing
        config.setConfig(mapOf(
            "android" to mapOf<String, Any?>(
                "foregroundService" to mapOf<String, Any?>(
                    "notificationTitle" to "First Title"
                )
            )
        ))
        assertEquals("First Title", config.getFgNotificationTitle())

        // Now send null — should preserve existing value
        config.setConfig(mapOf(
            "android" to mapOf<String, Any?>(
                "foregroundService" to mapOf<String, Any?>(
                    "notificationTitle" to null,
                    "notificationText" to "New Text"
                )
            )
        ))
        assertEquals("First Title", config.getFgNotificationTitle())
        assertEquals("New Text", config.getFgNotificationText())
    }

    // =========================================================================
    // Issue #74 — Full pipeline: exact user config from discussion
    // =========================================================================

    @Test
    fun issue74_exactUserConfig_allValuesAccessible() {
        // Simulate the exact map that tlConfigToSdkMap() produces for the
        // user's config in Discussion #74:
        //   AndroidConfig(
        //     locationUpdateInterval: 10000,
        //     deferTime: 60000,
        //     foregroundService: ForegroundServiceConfig(
        //       notificationTitle: 'Title',
        //       notificationText: 'Text',
        //       channelId: 'x_background_service',
        //       channelName: 'X Background Service',
        //       notificationPriority: NotificationPriority.high,
        //     ),
        //   )
        config.setConfig(mapOf(
            "geo" to mapOf<String, Any?>(
                "desiredAccuracy" to 0,
                "distanceFilter" to 10.0
            ),
            "motion" to mapOf<String, Any?>(
                "disableMotionActivityUpdates" to false
            ),
            "app" to mapOf<String, Any?>(
                "stopOnTerminate" to false,
                "startOnBoot" to true
            ),
            "android" to mapOf<String, Any?>(
                "locationUpdateInterval" to 10000L,
                "fastestLocationUpdateInterval" to 5000L,
                "deferTime" to 60000,
                "allowIdenticalLocations" to false,
                "geofenceModeHighAccuracy" to false,
                "periodicUseForegroundService" to false,
                "periodicUseExactAlarms" to false,
                "scheduleUseAlarmManager" to false,
                "foregroundService" to mapOf<String, Any?>(
                    "enabled" to true,
                    "channelId" to "x_background_service",
                    "channelName" to "X Background Service",
                    "notificationTitle" to "Title",
                    "notificationText" to "Text",
                    "notificationColor" to null,
                    "notificationSmallIcon" to null,
                    "notificationLargeIcon" to null,
                    "notificationPriority" to 3,
                    "notificationOngoing" to true,
                    "actions" to emptyList<String>()
                )
            )
        ))

        // Android section values
        assertEquals(10000L, config.getLocationUpdateInterval())
        assertEquals(5000L, config.getFastestLocationUpdateInterval())
        assertEquals(60000, config.getDeferTime())
        assertFalse(config.getAllowIdenticalLocations())

        // Foreground service values
        assertTrue(config.isForegroundServiceEnabled())
        assertEquals("x_background_service", config.getFgChannelId())
        assertEquals("X Background Service", config.getFgChannelName())
        assertEquals("Title", config.getFgNotificationTitle())
        assertEquals("Text", config.getFgNotificationText())
        assertEquals(3, config.getFgNotificationPriority())
        assertTrue(config.getFgNotificationOngoing())
        assertNull(config.getFgNotificationColor())
        assertNull(config.getFgNotificationSmallIcon())
        assertNull(config.getFgNotificationLargeIcon())
        assertEquals(emptyList<String>(), config.getFgActions())

        // Geo and App values also correct
        assertEquals(0, config.getDesiredAccuracy())
        assertEquals(10.0, config.getDistanceFilter(), 0.01)
        assertFalse(config.getStopOnTerminate())
        assertTrue(config.getStartOnBoot())
    }

    // =========================================================================
    // Security section flattening
    // =========================================================================

    @Test
    fun securitySection_encryptDatabase_isFlattened() {
        config.setConfig(mapOf(
            "security" to mapOf<String, Any?>(
                "encryptDatabase" to true
            )
        ))
        assertTrue(config.getEncryptDatabase())
    }

    @Test
    fun securitySection_encryptionKey_isFlattened() {
        config.setConfig(mapOf(
            "security" to mapOf<String, Any?>(
                "encryptDatabase" to true,
                "encryptionKey" to "my-secret-key"
            )
        ))
        assertEquals("my-secret-key", config.getEncryptionKey())
    }

    @Test
    fun securitySection_defaults_whenNotSet() {
        assertFalse(config.getEncryptDatabase())
        assertNull(config.getEncryptionKey())
    }

    // =========================================================================
    // Attestation section special handling
    // =========================================================================

    @Test
    fun attestationSection_enabled_mappedToAttestationEnabled() {
        config.setConfig(mapOf(
            "attestation" to mapOf<String, Any?>(
                "enabled" to true,
                "refreshInterval" to 3600
            )
        ))
        assertTrue(config.getAttestationEnabled())
    }

    @Test
    fun attestationSection_refreshInterval_mappedToAttestationRefreshInterval() {
        config.setConfig(mapOf(
            "attestation" to mapOf<String, Any?>(
                "enabled" to false,
                "refreshInterval" to 1800
            )
        ))
        assertEquals(1800, config.getAttestationRefreshInterval())
    }

    @Test
    fun attestationSection_verificationUrl_mappedToAttestationVerificationUrl() {
        config.setConfig(mapOf(
            "attestation" to mapOf<String, Any?>(
                "enabled" to true,
                "refreshInterval" to 3600,
                "verificationUrl" to "https://verify.example.com/attest"
            )
        ))
        assertEquals(
            "https://verify.example.com/attest",
            config.getAttestationVerificationUrl()
        )
    }

    @Test
    fun attestationSection_defaults_whenNotSet() {
        assertFalse(config.getAttestationEnabled())
        assertEquals(3600, config.getAttestationRefreshInterval())
        assertNull(config.getAttestationVerificationUrl())
    }

    @Test
    fun attestationSection_enabledDoesNotCollideWithAuditEnabled() {
        // Both audit and attestation have an "enabled" key. Verify that
        // attestation's "enabled" maps to "attestationEnabled" and doesn't
        // interfere with audit's "enabled".
        config.setConfig(mapOf(
            "audit" to mapOf<String, Any?>(
                "enabled" to true,
                "hashAlgorithm" to 0
            ),
            "attestation" to mapOf<String, Any?>(
                "enabled" to false,
                "refreshInterval" to 3600
            )
        ))

        // Attestation should be false — its "enabled" mapped to "attestationEnabled"
        assertFalse(config.getAttestationEnabled())
        // Audit should be true — its "enabled" stayed as flat "enabled"
        assertTrue(config.getAuditEnabled())
    }

    // =========================================================================
    // No regression: existing sections still flatten correctly
    // =========================================================================

    @Test
    fun geoSection_stillFlattensCorrectly() {
        config.setConfig(mapOf(
            "geo" to mapOf<String, Any?>(
                "desiredAccuracy" to 2,
                "distanceFilter" to 50.0,
                "stationaryRadius" to 100.0
            )
        ))
        assertEquals(2, config.getDesiredAccuracy())
        assertEquals(50.0, config.getDistanceFilter(), 0.01)
        assertEquals(100.0, config.getStationaryRadius(), 0.01)
    }

    @Test
    fun appSection_stillFlattensCorrectly() {
        config.setConfig(mapOf(
            "app" to mapOf<String, Any?>(
                "stopOnTerminate" to false,
                "startOnBoot" to true,
                "heartbeatInterval" to 120
            )
        ))
        assertFalse(config.getStopOnTerminate())
        assertTrue(config.getStartOnBoot())
        assertEquals(120, config.getHeartbeatInterval())
    }

    @Test
    fun httpSection_stillFlattensCorrectly() {
        config.setConfig(mapOf(
            "http" to mapOf<String, Any?>(
                "url" to "https://api.example.com/locations",
                "autoSync" to true,
                "batchSync" to true,
                "maxBatchSize" to 100
            )
        ))
        assertEquals("https://api.example.com/locations", config.getHttpUrl())
        assertTrue(config.getAutoSync())
        assertTrue(config.getBatchSync())
        assertEquals(100, config.getMaxBatchSize())
    }

    // =========================================================================
    // Partial updates and merge behavior
    // =========================================================================

    @Test
    fun partialUpdate_androidSection_doesNotClobberHttpUrl() {
        config.setConfig(mapOf(
            "http" to mapOf<String, Any?>("url" to "https://api.example.com"),
            "android" to mapOf<String, Any?>(
                "deferTime" to 30000,
                "foregroundService" to mapOf<String, Any?>(
                    "notificationTitle" to "Tracking"
                )
            )
        ))

        assertEquals("https://api.example.com", config.getHttpUrl())
        assertEquals(30000, config.getDeferTime())
        assertEquals("Tracking", config.getFgNotificationTitle())

        // Now do a partial update — only change android
        config.setConfig(mapOf(
            "android" to mapOf<String, Any?>(
                "deferTime" to 90000
            )
        ))

        // HTTP URL must be preserved
        assertEquals("https://api.example.com", config.getHttpUrl())
        // deferTime updated
        assertEquals(90000, config.getDeferTime())
        // foreground service values preserved from prior setConfig
        assertEquals("Tracking", config.getFgNotificationTitle())
    }

    @Test
    fun partialUpdate_securityAfterAndroid_preservesBoth() {
        config.setConfig(mapOf(
            "android" to mapOf<String, Any?>(
                "deferTime" to 60000,
                "foregroundService" to mapOf<String, Any?>(
                    "notificationTitle" to "GPS Active"
                )
            )
        ))
        assertEquals(60000, config.getDeferTime())
        assertEquals("GPS Active", config.getFgNotificationTitle())

        config.setConfig(mapOf(
            "security" to mapOf<String, Any?>(
                "encryptDatabase" to true
            )
        ))

        // Both should be present
        assertEquals(60000, config.getDeferTime())
        assertEquals("GPS Active", config.getFgNotificationTitle())
        assertTrue(config.getEncryptDatabase())
    }

    // =========================================================================
    // Reset with android config
    // =========================================================================

    @Test
    fun reset_withAndroidConfig_flattensCorrectly() {
        config.reset(mapOf(
            "android" to mapOf<String, Any?>(
                "deferTime" to 45000,
                "foregroundService" to mapOf<String, Any?>(
                    "notificationTitle" to "Reset Title"
                )
            )
        ))
        assertEquals(45000, config.getDeferTime())
        assertEquals("Reset Title", config.getFgNotificationTitle())
    }

    @Test
    fun reset_null_restoresDefaults() {
        config.setConfig(mapOf(
            "android" to mapOf<String, Any?>(
                "deferTime" to 60000,
                "foregroundService" to mapOf<String, Any?>(
                    "notificationTitle" to "Custom"
                )
            )
        ))
        assertEquals(60000, config.getDeferTime())

        config.reset(null)

        // Should be back to defaults
        assertEquals(ConfigManager.DEFAULT_DEFER_TIME, config.getDeferTime())
        assertEquals(ConfigManager.DEFAULT_NOTIFICATION_TITLE, config.getFgNotificationTitle())
    }

    // =========================================================================
    // Full config roundtrip (simulating ready() → setConfig())
    // =========================================================================

    @Test
    fun fullConfigRoundtrip_allSectionsIncludingAndroid() {
        // Simulate the full map that tlConfigToSdkMap() builds with ALL sections.
        // This mirrors what happens during a real ready() call.
        val fullConfig = mapOf<String, Any?>(
            "geo" to mapOf<String, Any?>(
                "desiredAccuracy" to 0,
                "distanceFilter" to 10.0,
                "stationaryRadius" to 25.0,
                "locationTimeout" to 60,
                "disableElasticity" to false,
                "elasticityMultiplier" to 3.0,
                "stopAfterElapsedMinutes" to -1,
                "maxMonitoredGeofences" to -1,
                "enableTimestampMeta" to false
            ),
            "app" to mapOf<String, Any?>(
                "stopOnTerminate" to false,
                "startOnBoot" to true,
                "heartbeatInterval" to 60
            ),
            "android" to mapOf<String, Any?>(
                "locationUpdateInterval" to 10000L,
                "fastestLocationUpdateInterval" to 5000L,
                "deferTime" to 60000,
                "allowIdenticalLocations" to false,
                "geofenceModeHighAccuracy" to false,
                "periodicUseForegroundService" to false,
                "periodicUseExactAlarms" to false,
                "scheduleUseAlarmManager" to false,
                "foregroundService" to mapOf<String, Any?>(
                    "enabled" to true,
                    "channelId" to "my_channel",
                    "channelName" to "My Channel",
                    "notificationTitle" to "My App",
                    "notificationText" to "Tracking your location",
                    "notificationColor" to "#00FF00",
                    "notificationSmallIcon" to null,
                    "notificationLargeIcon" to null,
                    "notificationPriority" to 3,
                    "notificationOngoing" to true,
                    "actions" to listOf("stop")
                )
            ),
            "http" to mapOf<String, Any?>(
                "url" to "https://api.example.com/locations",
                "autoSync" to true,
                "batchSync" to false,
                "maxBatchSize" to 250
            ),
            "logger" to mapOf<String, Any?>(
                "logLevel" to 4,
                "logMaxDays" to 3,
                "debug" to true
            ),
            "motion" to mapOf<String, Any?>(
                "stopTimeout" to 5,
                "disableMotionActivityUpdates" to false,
                "isMoving" to false
            ),
            "geofence" to mapOf<String, Any?>(
                "geofenceInitialTriggerEntry" to true,
                "geofenceProximityRadius" to 1000,
                "geofenceInitialTrigger" to true
            ),
            "persistence" to mapOf<String, Any?>(
                "persistMode" to 0,
                "maxDaysToPersist" to -1,
                "maxRecordsToPersist" to -1,
                "disableProviderChangeRecord" to false
            ),
            "audit" to mapOf<String, Any?>(
                "enabled" to false,
                "hashAlgorithm" to 0
            ),
            "privacyZone" to mapOf<String, Any?>(
                "enabled" to false
            ),
            "security" to mapOf<String, Any?>(
                "encryptDatabase" to false
            ),
            "attestation" to mapOf<String, Any?>(
                "enabled" to false,
                "refreshInterval" to 3600
            )
        )

        config.setConfig(fullConfig)

        // Verify Android section
        assertEquals(10000L, config.getLocationUpdateInterval())
        assertEquals(5000L, config.getFastestLocationUpdateInterval())
        assertEquals(60000, config.getDeferTime())
        assertFalse(config.getAllowIdenticalLocations())

        // Verify foreground service
        assertTrue(config.isForegroundServiceEnabled())
        assertEquals("my_channel", config.getFgChannelId())
        assertEquals("My Channel", config.getFgChannelName())
        assertEquals("My App", config.getFgNotificationTitle())
        assertEquals("Tracking your location", config.getFgNotificationText())
        assertEquals("#00FF00", config.getFgNotificationColor())
        assertNull(config.getFgNotificationSmallIcon())
        assertNull(config.getFgNotificationLargeIcon())
        assertEquals(3, config.getFgNotificationPriority())
        assertTrue(config.getFgNotificationOngoing())
        assertEquals(listOf("stop"), config.getFgActions())

        // Verify other sections not broken
        assertEquals("https://api.example.com/locations", config.getHttpUrl())
        assertTrue(config.getAutoSync())
        assertFalse(config.getStopOnTerminate())
        assertTrue(config.getStartOnBoot())
        assertTrue(config.isDebug())

        // Verify security
        assertFalse(config.getEncryptDatabase())

        // Verify attestation
        assertFalse(config.getAttestationEnabled())
        assertEquals(3600, config.getAttestationRefreshInterval())
    }

    // =========================================================================
    // Edge cases
    // =========================================================================

    @Test
    fun emptyAndroidSection_doesNotCrash() {
        config.setConfig(mapOf(
            "android" to mapOf<String, Any?>()
        ))
        // Should return defaults
        assertEquals(ConfigManager.DEFAULT_DEFER_TIME, config.getDeferTime())
        assertEquals(ConfigManager.DEFAULT_LOCATION_UPDATE_INTERVAL, config.getLocationUpdateInterval())
    }

    @Test
    fun androidSectionWithoutForegroundService_doesNotCrash() {
        config.setConfig(mapOf(
            "android" to mapOf<String, Any?>(
                "deferTime" to 30000
            )
        ))
        assertEquals(30000, config.getDeferTime())
        // Foreground service should use defaults
        assertEquals(ConfigManager.DEFAULT_NOTIFICATION_TITLE, config.getFgNotificationTitle())
    }

    @Test
    fun emptyAttestationSection_doesNotCrash() {
        config.setConfig(mapOf(
            "attestation" to mapOf<String, Any?>()
        ))
        assertFalse(config.getAttestationEnabled())
        assertEquals(3600, config.getAttestationRefreshInterval())
    }

    @Test
    fun androidSection_typeCoercion_intTreatedAsLongForLocationUpdateInterval() {
        // Pigeon may pass Int or Long depending on the value range.
        // Verify that getLocationUpdateInterval() (which uses getLong) handles Int.
        config.setConfig(mapOf(
            "android" to mapOf<String, Any?>(
                "locationUpdateInterval" to 10000 // Int, not Long
            )
        ))
        assertEquals(10000L, config.getLocationUpdateInterval())
    }

    @Test
    fun androidSection_typeCoercion_longTreatedAsIntForDeferTime() {
        // Verify that getDeferTime() (which uses getInt) handles Long.
        config.setConfig(mapOf(
            "android" to mapOf<String, Any?>(
                "deferTime" to 60000L // Long, not Int
            )
        ))
        assertEquals(60000, config.getDeferTime())
    }

    // =========================================================================
    // #303 — the location filter sub-map nested inside geo
    // =========================================================================

    @Test
    fun geoSection_filterSubMap_isFlattened() {
        config.setConfig(mapOf(
            "geo" to mapOf<String, Any?>(
                "distanceFilter" to 12.0,
                "filter" to mapOf<String, Any?>(
                    "trackingAccuracyThreshold" to 30,
                    "odometerAccuracyThreshold" to 15,
                    "maxImpliedSpeed" to 25,
                    "rejectMockLocations" to true,
                    "mockDetectionLevel" to 2,
                    "useKalmanFilter" to true
                )
            )
        ))

        assertEquals(30, config.getTrackingAccuracyThreshold())
        assertEquals(15, config.getOdometerAccuracyThreshold())
        assertEquals(25, config.getMaxImpliedSpeed())
        assertTrue(config.getRejectMockLocations())
        assertEquals(2, config.getMockDetectionLevel())
        assertTrue(config.getEnableKalmanFilter())
    }

    /**
     * #303: `LocationFilter.policy` is serialized under `policy` by every
     * transport, but `getFilterPolicy()` — and the processor-rebuild key list in
     * `TraceletSdk.setConfig` — read `filterPolicy`. The value was flattened into
     * the cache under a name nothing asked for, so the policy stayed at ADJUST
     * however it was configured. The rename happens during flattening so both
     * readers see it.
     */
    @Test
    fun geoSection_filterPolicy_isRenamedFromWireName() {
        config.setConfig(mapOf(
            "geo" to mapOf<String, Any?>(
                "filter" to mapOf<String, Any?>("policy" to 2) // DISCARD
            )
        ))

        assertEquals(2, config.getFilterPolicy())
        assertEquals(2, config.getConfig()["filterPolicy"])
        assertNull(config.getConfig()["policy"])
    }

    @Test
    fun geoSection_filter_nullValuesSkipped_existingPreserved() {
        config.setConfig(mapOf(
            "geo" to mapOf<String, Any?>(
                "filter" to mapOf<String, Any?>(
                    "trackingAccuracyThreshold" to 30,
                    "odometerAccuracyThreshold" to 15
                )
            )
        ))
        config.setConfig(mapOf(
            "geo" to mapOf<String, Any?>(
                "filter" to mapOf<String, Any?>(
                    "trackingAccuracyThreshold" to 45,
                    "odometerAccuracyThreshold" to null
                )
            )
        ))

        assertEquals(45, config.getTrackingAccuracyThreshold())
        assertEquals(15, config.getOdometerAccuracyThreshold())
    }

    @Test
    fun attestation_nullValuesSkipped_existingPreserved() {
        config.setConfig(mapOf(
            "attestation" to mapOf<String, Any?>(
                "enabled" to true,
                "refreshInterval" to 1800
            )
        ))
        assertTrue(config.getAttestationEnabled())
        assertEquals(1800, config.getAttestationRefreshInterval())

        // Now set with null enabled — should preserve existing
        config.setConfig(mapOf(
            "attestation" to mapOf<String, Any?>(
                "enabled" to null,
                "refreshInterval" to 900
            )
        ))
        assertTrue(config.getAttestationEnabled()) // preserved from before
        assertEquals(900, config.getAttestationRefreshInterval())
    }
}
