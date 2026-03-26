package com.ikolvi.tracelet.sdk.model

import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Unit tests for [TraceletConfig] and all sub-config data classes.
 *
 * Tests cover:
 * - Default values for every config group
 * - `toMap()` serialization produces the correct keys and values
 * - Non-default values round-trip through `toMap()`
 * - Enum `fromValue()` mappings
 */
class TraceletConfigTest {

    // =========================================================================
    // TraceletConfig (top-level)
    // =========================================================================

    @Test
    fun `default TraceletConfig toMap contains all section keys`() {
        val map = TraceletConfig().toMap()
        val expected = listOf(
            "geo", "app", "http", "logger", "motion",
            "geofence", "persistence", "audit", "privacyZone",
            "security", "attestation",
        )
        expected.forEach { key ->
            assertTrue(map.containsKey(key), "Missing key: $key")
        }
        assertEquals(expected.size, map.size)
    }

    // =========================================================================
    // GeoConfig
    // =========================================================================

    @Test
    fun `default GeoConfig toMap`() {
        val map = GeoConfig().toMap()
        assertEquals(DesiredAccuracy.HIGH.value, map["desiredAccuracy"])
        assertEquals(10.0, map["distanceFilter"])
        assertEquals(1000, map["locationUpdateInterval"])
        assertEquals(500, map["fastestLocationUpdateInterval"])
        assertEquals(25.0, map["stationaryRadius"])
        assertEquals(60, map["locationTimeout"])
        assertEquals(LocationActivityType.OTHER.value, map["activityType"])
        assertEquals(false, map["disableElasticity"])
        assertEquals(1.0, map["elasticityMultiplier"])
        assertEquals(-1, map["stopAfterElapsedMinutes"])
        assertEquals(0, map["deferTime"])
        assertEquals(false, map["allowIdenticalLocations"])
        assertEquals(false, map["geofenceModeHighAccuracy"])
        assertEquals(-1, map["maxMonitoredGeofences"])
        assertEquals(false, map["useSignificantChangesOnly"])
        assertEquals(false, map["showsBackgroundLocationIndicator"])
        assertEquals(false, map["pausesLocationUpdatesAutomatically"])
        assertEquals("Always", map["locationAuthorizationRequest"])
        assertEquals(false, map["disableLocationAuthorizationAlert"])
        assertEquals(false, map["enableTimestampMeta"])
        assertEquals(false, map["enableAdaptiveMode"])
        assertEquals(900, map["periodicLocationInterval"])
        assertEquals(DesiredAccuracy.MEDIUM.value, map["periodicDesiredAccuracy"])
        assertEquals(false, map["periodicUseForegroundService"])
        assertEquals(false, map["periodicUseExactAlarms"])
        assertEquals(false, map["enableSparseUpdates"])
        assertEquals(50.0, map["sparseDistanceThreshold"])
        assertEquals(300, map["sparseMaxIdleSeconds"])
        assertEquals(false, map["enableDeadReckoning"])
        assertEquals(10, map["deadReckoningActivationDelay"])
        assertEquals(120, map["deadReckoningMaxDuration"])
        assertEquals(0.0, map["batteryBudgetPerHour"])
        assertTrue(!map.containsKey("filter"), "filter should be absent when null")
    }

    @Test
    fun `GeoConfig with filter includes filter in map`() {
        val config = GeoConfig(
            desiredAccuracy = DesiredAccuracy.LOW,
            distanceFilter = 50.0,
            filter = LocationFilter(
                policy = LocationFilterPolicy.IGNORE,
                maxImpliedSpeed = 200,
                trackingAccuracyThreshold = 100,
                useKalmanFilter = true,
            ),
        )
        val map = config.toMap()
        assertEquals(DesiredAccuracy.LOW.value, map["desiredAccuracy"])
        assertEquals(50.0, map["distanceFilter"])

        @Suppress("UNCHECKED_CAST")
        val filterMap = map["filter"] as Map<String, Any?>
        assertEquals(LocationFilterPolicy.IGNORE.value, filterMap["policy"])
        assertEquals(200, filterMap["maxImpliedSpeed"])
        assertEquals(100, filterMap["trackingAccuracyThreshold"])
        assertEquals(true, filterMap["useKalmanFilter"])
    }

    @Test
    fun `GeoConfig WhenInUse authorization`() {
        val config = GeoConfig(
            locationAuthorizationRequest = LocationAuthorizationRequest.WHEN_IN_USE,
        )
        assertEquals("WhenInUse", config.toMap()["locationAuthorizationRequest"])
    }

    // =========================================================================
    // LocationFilter
    // =========================================================================

    @Test
    fun `default LocationFilter toMap`() {
        val map = LocationFilter().toMap()
        assertEquals(LocationFilterPolicy.ADJUST.value, map["policy"])
        assertEquals(0, map["maxImpliedSpeed"])
        assertEquals(0, map["odometerAccuracyThreshold"])
        assertEquals(0, map["trackingAccuracyThreshold"])
        assertEquals(false, map["useKalmanFilter"])
        assertEquals(false, map["rejectMockLocations"])
        assertEquals(MockDetectionLevel.DISABLED.value, map["mockDetectionLevel"])
    }

    @Test
    fun `LocationFilter custom values`() {
        val filter = LocationFilter(
            policy = LocationFilterPolicy.DISCARD,
            maxImpliedSpeed = 120,
            odometerAccuracyThreshold = 50,
            trackingAccuracyThreshold = 200,
            useKalmanFilter = true,
            rejectMockLocations = true,
            mockDetectionLevel = MockDetectionLevel.HEURISTIC,
        )
        val map = filter.toMap()
        assertEquals(LocationFilterPolicy.DISCARD.value, map["policy"])
        assertEquals(120, map["maxImpliedSpeed"])
        assertEquals(50, map["odometerAccuracyThreshold"])
        assertEquals(200, map["trackingAccuracyThreshold"])
        assertEquals(true, map["useKalmanFilter"])
        assertEquals(true, map["rejectMockLocations"])
        assertEquals(MockDetectionLevel.HEURISTIC.value, map["mockDetectionLevel"])
    }

    // =========================================================================
    // AppConfig
    // =========================================================================

    @Test
    fun `default AppConfig toMap`() {
        val map = AppConfig().toMap()
        assertEquals(true, map["stopOnTerminate"])
        assertEquals(false, map["startOnBoot"])
        assertEquals(60, map["heartbeatInterval"])
        assertEquals(emptyList<String>(), map["schedule"])
        assertEquals(false, map["scheduleUseAlarmManager"])
        assertEquals(false, map["preventSuspend"])
        assertNull(map["remoteConfigUrl"])
        assertEquals(emptyMap<String, String>(), map["remoteConfigHeaders"])
        assertEquals(10000, map["remoteConfigTimeout"])
        assertEquals(0, map["remoteConfigRefreshInterval"])
        assertTrue(map.containsKey("foregroundService"))
    }

    @Test
    fun `AppConfig custom values`() {
        val config = AppConfig(
            stopOnTerminate = false,
            startOnBoot = true,
            heartbeatInterval = 120,
            schedule = listOf("1-7 09:00-17:00"),
            preventSuspend = true,
            remoteConfigUrl = "https://example.com/config",
        )
        val map = config.toMap()
        assertEquals(false, map["stopOnTerminate"])
        assertEquals(true, map["startOnBoot"])
        assertEquals(120, map["heartbeatInterval"])
        assertEquals(listOf("1-7 09:00-17:00"), map["schedule"])
        assertEquals(true, map["preventSuspend"])
        assertEquals("https://example.com/config", map["remoteConfigUrl"])
    }

    // =========================================================================
    // ForegroundServiceConfig
    // =========================================================================

    @Test
    fun `default ForegroundServiceConfig toMap`() {
        val map = ForegroundServiceConfig().toMap()
        assertEquals(true, map["enabled"])
        assertEquals("tracelet_channel", map["channelId"])
        assertEquals("Tracelet", map["channelName"])
        assertEquals("Tracelet", map["notificationTitle"])
        assertEquals("Tracking location in background", map["notificationText"])
        assertNull(map["notificationColor"])
        assertNull(map["notificationSmallIcon"])
        assertNull(map["notificationLargeIcon"])
        assertEquals(NotificationPriority.DEFAULT.value, map["notificationPriority"])
        assertEquals(true, map["notificationOngoing"])
        assertEquals(emptyList<String>(), map["actions"])
    }

    @Test
    fun `ForegroundServiceConfig custom values`() {
        val config = ForegroundServiceConfig(
            notificationTitle = "Fleet",
            notificationText = "Tracking...",
            notificationColor = "#FF0000",
            notificationSmallIcon = "ic_small",
            notificationLargeIcon = "ic_large",
            notificationPriority = NotificationPriority.HIGH,
        )
        val map = config.toMap()
        assertEquals("Fleet", map["notificationTitle"])
        assertEquals("Tracking...", map["notificationText"])
        assertEquals("#FF0000", map["notificationColor"])
        assertEquals("ic_small", map["notificationSmallIcon"])
        assertEquals("ic_large", map["notificationLargeIcon"])
        assertEquals(NotificationPriority.HIGH.value, map["notificationPriority"])
    }

    // =========================================================================
    // HttpConfig
    // =========================================================================

    @Test
    fun `default HttpConfig toMap`() {
        val map = HttpConfig().toMap()
        assertNull(map["url"])
        assertEquals(HttpMethod.POST.value, map["method"])
        assertEquals(emptyMap<String, String>(), map["headers"])
        assertEquals("location", map["httpRootProperty"])
        assertEquals(false, map["batchSync"])
        assertEquals(250, map["maxBatchSize"])
        assertEquals(true, map["autoSync"])
        assertEquals(0, map["autoSyncThreshold"])
        assertEquals(60000, map["httpTimeout"])
        assertEquals(LocationOrder.ASC.value, map["locationsOrderDirection"])
        assertEquals(false, map["disableAutoSyncOnCellular"])
        assertEquals(10, map["maxRetries"])
        assertEquals(1000, map["retryBackoffBase"])
        assertEquals(300000, map["retryBackoffCap"])
        assertEquals(false, map["enableDeltaCompression"])
        assertEquals(6, map["deltaCoordinatePrecision"])
        assertEquals(emptyList<String>(), map["sslPinningCertificates"])
        assertEquals(emptyList<String>(), map["sslPinningFingerprints"])
    }

    @Test
    fun `HttpConfig custom values`() {
        val config = HttpConfig(
            url = "https://api.example.com/locations",
            method = HttpMethod.PUT,
            headers = mapOf("Authorization" to "Bearer token"),
            batchSync = true,
            maxBatchSize = 100,
        )
        val map = config.toMap()
        assertEquals("https://api.example.com/locations", map["url"])
        assertEquals(HttpMethod.PUT.value, map["method"])
        @Suppress("UNCHECKED_CAST")
        val headers = map["headers"] as Map<String, String>
        assertEquals("Bearer token", headers["Authorization"])
        assertEquals(true, map["batchSync"])
        assertEquals(100, map["maxBatchSize"])
    }

    // =========================================================================
    // LoggerConfig
    // =========================================================================

    @Test
    fun `default LoggerConfig toMap`() {
        val map = LoggerConfig().toMap()
        assertEquals(LogLevel.INFO.value, map["logLevel"])
        assertEquals(3, map["logMaxDays"])
        assertEquals(false, map["debug"])
    }

    @Test
    fun `LoggerConfig custom values`() {
        val config = LoggerConfig(
            logLevel = LogLevel.VERBOSE,
            logMaxDays = 7,
            debug = true,
        )
        val map = config.toMap()
        assertEquals(LogLevel.VERBOSE.value, map["logLevel"])
        assertEquals(7, map["logMaxDays"])
        assertEquals(true, map["debug"])
    }

    // =========================================================================
    // MotionConfig
    // =========================================================================

    @Test
    fun `default MotionConfig toMap`() {
        val map = MotionConfig().toMap()
        assertEquals(5, map["stopTimeout"])
        assertEquals(0, map["motionTriggerDelay"])
        assertEquals(false, map["disableMotionActivityUpdates"])
        assertEquals(false, map["isMoving"])
        assertEquals(10000, map["activityRecognitionInterval"])
        assertEquals(75, map["minimumActivityRecognitionConfidence"])
        assertEquals(false, map["disableStopDetection"])
        assertEquals(0, map["stopDetectionDelay"])
        assertEquals(false, map["stopOnStationary"])
        assertEquals(emptyList<String>(), map["triggerActivities"])
        assertEquals(2.5, map["shakeThreshold"])
        assertEquals(0.4, map["stillThreshold"])
        assertEquals(25, map["stillSampleCount"])
    }

    @Test
    fun `MotionConfig with triggerActivities`() {
        val config = MotionConfig(
            stopTimeout = 10,
            triggerActivities = setOf(ActivityType.ON_FOOT, ActivityType.IN_VEHICLE),
            disableMotionActivityUpdates = true,
        )
        val map = config.toMap()
        assertEquals(10, map["stopTimeout"])
        assertEquals(true, map["disableMotionActivityUpdates"])
        @Suppress("UNCHECKED_CAST")
        val activities = map["triggerActivities"] as List<String>
        assertTrue(activities.containsAll(listOf("on_foot", "in_vehicle")))
    }

    // =========================================================================
    // GeofenceConfig
    // =========================================================================

    @Test
    fun `default GeofenceConfig toMap`() {
        val map = GeofenceConfig().toMap()
        assertEquals(1000, map["geofenceProximityRadius"])
        assertEquals(true, map["geofenceInitialTriggerEntry"])
        assertEquals(false, map["geofenceModeKnockOut"])
    }

    @Test
    fun `GeofenceConfig custom values`() {
        val config = GeofenceConfig(
            geofenceProximityRadius = 5000,
            geofenceInitialTriggerEntry = false,
            geofenceModeKnockOut = true,
        )
        val map = config.toMap()
        assertEquals(5000, map["geofenceProximityRadius"])
        assertEquals(false, map["geofenceInitialTriggerEntry"])
        assertEquals(true, map["geofenceModeKnockOut"])
    }

    // =========================================================================
    // PersistenceConfig
    // =========================================================================

    @Test
    fun `default PersistenceConfig toMap`() {
        val map = PersistenceConfig().toMap()
        assertEquals(PersistMode.ALL.value, map["persistMode"])
        assertEquals(-1, map["maxDaysToPersist"])
        assertEquals(-1, map["maxRecordsToPersist"])
        assertNull(map["locationTemplate"])
        assertNull(map["geofenceTemplate"])
        assertEquals(false, map["disableProviderChangeRecord"])
        assertEquals(emptyMap<String, Any?>(), map["persistenceExtras"])
    }

    @Test
    fun `PersistenceConfig custom values`() {
        val config = PersistenceConfig(
            persistMode = PersistMode.LOCATION,
            maxDaysToPersist = 14,
            maxRecordsToPersist = 5000,
            locationTemplate = "{\"lat\":<%= latitude %>,\"lng\":<%= longitude %>}",
        )
        val map = config.toMap()
        assertEquals(PersistMode.LOCATION.value, map["persistMode"])
        assertEquals(14, map["maxDaysToPersist"])
        assertEquals(5000, map["maxRecordsToPersist"])
        assertEquals("{\"lat\":<%= latitude %>,\"lng\":<%= longitude %>}", map["locationTemplate"])
    }

    // =========================================================================
    // AuditConfig
    // =========================================================================

    @Test
    fun `default AuditConfig toMap`() {
        val map = AuditConfig().toMap()
        assertEquals(false, map["enabled"])
        assertEquals(HashAlgorithm.SHA256.value, map["hashAlgorithm"])
    }

    @Test
    fun `AuditConfig enabled with SHA512`() {
        val config = AuditConfig(enabled = true, hashAlgorithm = HashAlgorithm.SHA512)
        val map = config.toMap()
        assertEquals(true, map["enabled"])
        assertEquals(HashAlgorithm.SHA512.value, map["hashAlgorithm"])
    }

    // =========================================================================
    // PrivacyZoneConfig
    // =========================================================================

    @Test
    fun `default PrivacyZoneConfig toMap`() {
        val map = PrivacyZoneConfig().toMap()
        assertEquals(false, map["enabled"])
    }

    // =========================================================================
    // SecurityConfig
    // =========================================================================

    @Test
    fun `default SecurityConfig toMap`() {
        val map = SecurityConfig().toMap()
        assertEquals(false, map["encryptDatabase"])
    }

    @Test
    fun `SecurityConfig enabled`() {
        assertEquals(true, SecurityConfig(encryptDatabase = true).toMap()["encryptDatabase"])
    }

    // =========================================================================
    // AttestationConfig
    // =========================================================================

    @Test
    fun `default AttestationConfig toMap`() {
        val map = AttestationConfig().toMap()
        assertEquals(false, map["enabled"])
        assertEquals(3600, map["refreshInterval"])
    }

    @Test
    fun `AttestationConfig custom`() {
        val config = AttestationConfig(enabled = true, refreshInterval = 7200)
        val map = config.toMap()
        assertEquals(true, map["enabled"])
        assertEquals(7200, map["refreshInterval"])
    }

    // =========================================================================
    // Enum fromValue / companion
    // =========================================================================

    @Test
    fun `DesiredAccuracy fromValue`() {
        assertEquals(DesiredAccuracy.HIGH, DesiredAccuracy.fromValue(0))
        assertEquals(DesiredAccuracy.MEDIUM, DesiredAccuracy.fromValue(1))
        assertEquals(DesiredAccuracy.LOW, DesiredAccuracy.fromValue(2))
        assertEquals(DesiredAccuracy.HIGH, DesiredAccuracy.fromValue(99)) // invalid → default
    }

    @Test
    fun `LogLevel fromValue`() {
        assertEquals(LogLevel.VERBOSE, LogLevel.fromValue(0))
        assertEquals(LogLevel.ERROR, LogLevel.fromValue(4))
        assertEquals(LogLevel.INFO, LogLevel.fromValue(99))
    }

    @Test
    fun `HttpMethod fromValue`() {
        assertEquals(HttpMethod.POST, HttpMethod.fromValue(0))
        assertEquals(HttpMethod.PUT, HttpMethod.fromValue(1))
        assertEquals(HttpMethod.POST, HttpMethod.fromValue(99))
    }

    @Test
    fun `PersistMode fromValue`() {
        assertEquals(PersistMode.ALL, PersistMode.fromValue(0))
        assertEquals(PersistMode.LOCATION, PersistMode.fromValue(1))
        assertEquals(PersistMode.GEOFENCE, PersistMode.fromValue(2))
        assertEquals(PersistMode.NONE, PersistMode.fromValue(3))
        assertEquals(PersistMode.ALL, PersistMode.fromValue(99))
    }

    @Test
    fun `LocationFilterPolicy fromValue`() {
        assertEquals(LocationFilterPolicy.ADJUST, LocationFilterPolicy.fromValue(0))
        assertEquals(LocationFilterPolicy.IGNORE, LocationFilterPolicy.fromValue(1))
        assertEquals(LocationFilterPolicy.DISCARD, LocationFilterPolicy.fromValue(2))
        assertEquals(LocationFilterPolicy.ADJUST, LocationFilterPolicy.fromValue(99))
    }

    @Test
    fun `MockDetectionLevel fromValue`() {
        assertEquals(MockDetectionLevel.DISABLED, MockDetectionLevel.fromValue(0))
        assertEquals(MockDetectionLevel.BASIC, MockDetectionLevel.fromValue(1))
        assertEquals(MockDetectionLevel.HEURISTIC, MockDetectionLevel.fromValue(2))
        assertEquals(MockDetectionLevel.DISABLED, MockDetectionLevel.fromValue(99))
    }

    @Test
    fun `LocationActivityType fromValue`() {
        assertEquals(LocationActivityType.OTHER, LocationActivityType.fromValue(0))
        assertEquals(LocationActivityType.AUTOMOTIVE_NAVIGATION, LocationActivityType.fromValue(1))
        assertEquals(LocationActivityType.FITNESS, LocationActivityType.fromValue(2))
        assertEquals(LocationActivityType.OTHER_NAVIGATION, LocationActivityType.fromValue(3))
        assertEquals(LocationActivityType.AIRBORNE, LocationActivityType.fromValue(4))
        assertEquals(LocationActivityType.OTHER, LocationActivityType.fromValue(99))
    }

    @Test
    fun `NotificationPriority fromValue`() {
        assertEquals(NotificationPriority.MIN, NotificationPriority.fromValue(-2))
        assertEquals(NotificationPriority.LOW, NotificationPriority.fromValue(-1))
        assertEquals(NotificationPriority.DEFAULT, NotificationPriority.fromValue(0))
        assertEquals(NotificationPriority.HIGH, NotificationPriority.fromValue(1))
        assertEquals(NotificationPriority.MAX, NotificationPriority.fromValue(2))
        assertEquals(NotificationPriority.DEFAULT, NotificationPriority.fromValue(99))
    }

    @Test
    fun `LocationOrder fromValue`() {
        assertEquals(LocationOrder.ASC, LocationOrder.fromValue(0))
        assertEquals(LocationOrder.DESC, LocationOrder.fromValue(1))
        assertEquals(LocationOrder.ASC, LocationOrder.fromValue(99))
    }

    @Test
    fun `HashAlgorithm fromValue`() {
        assertEquals(HashAlgorithm.SHA256, HashAlgorithm.fromValue(0))
        assertEquals(HashAlgorithm.SHA512, HashAlgorithm.fromValue(1))
        assertEquals(HashAlgorithm.SHA256, HashAlgorithm.fromValue(99))
    }

    // =========================================================================
    // Full config round-trip
    // =========================================================================

    @Test
    fun `full TraceletConfig with custom values produces correct nested map`() {
        val config = TraceletConfig(
            geo = GeoConfig(
                desiredAccuracy = DesiredAccuracy.LOW,
                distanceFilter = 50.0,
                filter = LocationFilter(useKalmanFilter = true),
            ),
            app = AppConfig(
                stopOnTerminate = false,
                startOnBoot = true,
                foregroundService = ForegroundServiceConfig(
                    notificationTitle = "Test",
                ),
            ),
            http = HttpConfig(
                url = "https://api.example.com/tracks",
                batchSync = true,
            ),
            logger = LoggerConfig(debug = true, logLevel = LogLevel.VERBOSE),
            motion = MotionConfig(stopTimeout = 10),
            geofence = GeofenceConfig(geofenceProximityRadius = 5000),
            persistence = PersistenceConfig(maxDaysToPersist = 7),
            audit = AuditConfig(enabled = true),
            privacyZone = PrivacyZoneConfig(enabled = true),
            security = SecurityConfig(encryptDatabase = true),
            attestation = AttestationConfig(enabled = true, refreshInterval = 1800),
        )

        val map = config.toMap()

        // Verify nested section maps
        @Suppress("UNCHECKED_CAST")
        val geoMap = map["geo"] as Map<String, Any?>
        assertEquals(DesiredAccuracy.LOW.value, geoMap["desiredAccuracy"])
        assertEquals(50.0, geoMap["distanceFilter"])
        assertTrue(geoMap.containsKey("filter"))

        @Suppress("UNCHECKED_CAST")
        val appMap = map["app"] as Map<String, Any?>
        assertEquals(false, appMap["stopOnTerminate"])
        assertEquals(true, appMap["startOnBoot"])

        @Suppress("UNCHECKED_CAST")
        val httpMap = map["http"] as Map<String, Any?>
        assertEquals("https://api.example.com/tracks", httpMap["url"])
        assertEquals(true, httpMap["batchSync"])

        @Suppress("UNCHECKED_CAST")
        val loggerMap = map["logger"] as Map<String, Any?>
        assertEquals(true, loggerMap["debug"])
        assertEquals(LogLevel.VERBOSE.value, loggerMap["logLevel"])

        @Suppress("UNCHECKED_CAST")
        val motionMap = map["motion"] as Map<String, Any?>
        assertEquals(10, motionMap["stopTimeout"])

        @Suppress("UNCHECKED_CAST")
        val geofenceMap = map["geofence"] as Map<String, Any?>
        assertEquals(5000, geofenceMap["geofenceProximityRadius"])

        @Suppress("UNCHECKED_CAST")
        val persistenceMap = map["persistence"] as Map<String, Any?>
        assertEquals(7, persistenceMap["maxDaysToPersist"])

        @Suppress("UNCHECKED_CAST")
        val auditMap = map["audit"] as Map<String, Any?>
        assertEquals(true, auditMap["enabled"])

        @Suppress("UNCHECKED_CAST")
        val privacyMap = map["privacyZone"] as Map<String, Any?>
        assertEquals(true, privacyMap["enabled"])

        @Suppress("UNCHECKED_CAST")
        val securityMap = map["security"] as Map<String, Any?>
        assertEquals(true, securityMap["encryptDatabase"])

        @Suppress("UNCHECKED_CAST")
        val attestMap = map["attestation"] as Map<String, Any?>
        assertEquals(true, attestMap["enabled"])
        assertEquals(1800, attestMap["refreshInterval"])
    }

    // =========================================================================
    // fromMap() round-trip tests
    // =========================================================================

    @Test
    fun `GeoConfig fromMap round-trip preserves all fields`() {
        val original = GeoConfig(
            desiredAccuracy = DesiredAccuracy.LOW,
            distanceFilter = 42.0,
            locationUpdateInterval = 2000,
            fastestLocationUpdateInterval = 1000,
            stationaryRadius = 50.0,
            locationTimeout = 120,
            activityType = LocationActivityType.FITNESS,
            disableElasticity = true,
            elasticityMultiplier = 2.5,
            stopAfterElapsedMinutes = 30,
            deferTime = 5,
            allowIdenticalLocations = true,
            geofenceModeHighAccuracy = true,
            maxMonitoredGeofences = 20,
            useSignificantChangesOnly = true,
            showsBackgroundLocationIndicator = true,
            pausesLocationUpdatesAutomatically = true,
            locationAuthorizationRequest = LocationAuthorizationRequest.WHEN_IN_USE,
            disableLocationAuthorizationAlert = true,
            enableTimestampMeta = true,
            enableAdaptiveMode = true,
            periodicLocationInterval = 300,
            periodicDesiredAccuracy = DesiredAccuracy.LOW,
            periodicUseForegroundService = true,
            periodicUseExactAlarms = true,
            enableSparseUpdates = true,
            sparseDistanceThreshold = 100.0,
            sparseMaxIdleSeconds = 600,
            enableDeadReckoning = true,
            deadReckoningActivationDelay = 20,
            deadReckoningMaxDuration = 240,
            batteryBudgetPerHour = 5.0,
            filter = LocationFilter(
                policy = LocationFilterPolicy.DISCARD,
                maxImpliedSpeed = 120,
                odometerAccuracyThreshold = 50,
                trackingAccuracyThreshold = 200,
                useKalmanFilter = true,
                rejectMockLocations = true,
                mockDetectionLevel = MockDetectionLevel.HEURISTIC,
            ),
        )
        val restored = GeoConfig.fromMap(original.toMap())
        assertEquals(original, restored)
    }

    @Test
    fun `GeoConfig fromMap defaults when map is empty`() {
        val restored = GeoConfig.fromMap(emptyMap())
        assertEquals(GeoConfig(), restored)
    }

    @Test
    fun `LocationFilter fromMap round-trip`() {
        val original = LocationFilter(
            policy = LocationFilterPolicy.IGNORE,
            maxImpliedSpeed = 90,
            odometerAccuracyThreshold = 30,
            trackingAccuracyThreshold = 150,
            useKalmanFilter = true,
            rejectMockLocations = true,
            mockDetectionLevel = MockDetectionLevel.BASIC,
        )
        assertEquals(original, LocationFilter.fromMap(original.toMap()))
    }

    @Test
    fun `AppConfig fromMap round-trip`() {
        val original = AppConfig(
            stopOnTerminate = false,
            startOnBoot = true,
            heartbeatInterval = 120,
            schedule = listOf("1-7 09:00-17:00"),
            scheduleUseAlarmManager = true,
            preventSuspend = true,
            foregroundService = ForegroundServiceConfig(
                notificationTitle = "Test",
                notificationText = "Testing",
                notificationPriority = NotificationPriority.HIGH,
            ),
            remoteConfigUrl = "https://example.com/config",
            remoteConfigHeaders = mapOf("X-Key" to "abc"),
            remoteConfigTimeout = 5000,
            remoteConfigRefreshInterval = 3600,
        )
        assertEquals(original, AppConfig.fromMap(original.toMap()))
    }

    @Test
    fun `ForegroundServiceConfig fromMap round-trip`() {
        val original = ForegroundServiceConfig(
            enabled = false,
            channelId = "custom",
            channelName = "Custom",
            notificationTitle = "Title",
            notificationText = "Text",
            notificationColor = "#FF0000",
            notificationSmallIcon = "ic_small",
            notificationLargeIcon = "ic_large",
            notificationPriority = NotificationPriority.MAX,
            notificationOngoing = false,
            actions = listOf("pause", "stop"),
        )
        assertEquals(original, ForegroundServiceConfig.fromMap(original.toMap()))
    }

    @Test
    fun `HttpConfig fromMap round-trip`() {
        val original = HttpConfig(
            url = "https://api.example.com/locs",
            method = HttpMethod.PUT,
            headers = mapOf("Auth" to "Bearer xyz"),
            httpRootProperty = "data",
            batchSync = true,
            maxBatchSize = 50,
            autoSync = false,
            autoSyncThreshold = 10,
            httpTimeout = 30000,
            locationsOrderDirection = LocationOrder.DESC,
            disableAutoSyncOnCellular = true,
            maxRetries = 5,
            retryBackoffBase = 2000,
            retryBackoffCap = 60000,
            enableDeltaCompression = true,
            deltaCoordinatePrecision = 4,
            sslPinningCertificates = listOf("cert1"),
            sslPinningFingerprints = listOf("fp1"),
        )
        assertEquals(original, HttpConfig.fromMap(original.toMap()))
    }

    @Test
    fun `LoggerConfig fromMap round-trip`() {
        val original = LoggerConfig(
            logLevel = LogLevel.ERROR,
            logMaxDays = 14,
            debug = true,
        )
        assertEquals(original, LoggerConfig.fromMap(original.toMap()))
    }

    @Test
    fun `MotionConfig fromMap round-trip`() {
        val original = MotionConfig(
            stopTimeout = 10,
            motionTriggerDelay = 5,
            disableMotionActivityUpdates = true,
            isMoving = true,
            activityRecognitionInterval = 5000,
            minimumActivityRecognitionConfidence = 50,
            disableStopDetection = true,
            stopDetectionDelay = 3,
            stopOnStationary = true,
            triggerActivities = setOf(ActivityType.IN_VEHICLE, ActivityType.ON_BICYCLE),
            shakeThreshold = 3.0,
            stillThreshold = 0.5,
            stillSampleCount = 30,
        )
        assertEquals(original, MotionConfig.fromMap(original.toMap()))
    }

    @Test
    fun `GeofenceConfig fromMap round-trip`() {
        val original = GeofenceConfig(
            geofenceProximityRadius = 5000,
            geofenceInitialTriggerEntry = false,
            geofenceModeKnockOut = true,
        )
        assertEquals(original, GeofenceConfig.fromMap(original.toMap()))
    }

    @Test
    fun `PersistenceConfig fromMap round-trip`() {
        val original = PersistenceConfig(
            persistMode = PersistMode.GEOFENCE,
            maxDaysToPersist = 14,
            maxRecordsToPersist = 10000,
            locationTemplate = "{\"lat\":<%latitude%>}",
            geofenceTemplate = "{\"id\":\"<%identifier%>\"}",
            disableProviderChangeRecord = true,
        )
        assertEquals(original, PersistenceConfig.fromMap(original.toMap()))
    }

    @Test
    fun `AuditConfig fromMap round-trip`() {
        val original = AuditConfig(enabled = true, hashAlgorithm = HashAlgorithm.SHA512)
        assertEquals(original, AuditConfig.fromMap(original.toMap()))
    }

    @Test
    fun `PrivacyZoneConfig fromMap round-trip`() {
        val original = PrivacyZoneConfig(enabled = true)
        assertEquals(original, PrivacyZoneConfig.fromMap(original.toMap()))
    }

    @Test
    fun `SecurityConfig fromMap round-trip`() {
        val original = SecurityConfig(encryptDatabase = true)
        assertEquals(original, SecurityConfig.fromMap(original.toMap()))
    }

    @Test
    fun `AttestationConfig fromMap round-trip`() {
        val original = AttestationConfig(enabled = true, refreshInterval = 1800)
        assertEquals(original, AttestationConfig.fromMap(original.toMap()))
    }

    @Test
    fun `TraceletConfig fromMap round-trip with all sections`() {
        val original = TraceletConfig(
            geo = GeoConfig(distanceFilter = 42.0, desiredAccuracy = DesiredAccuracy.LOW),
            app = AppConfig(stopOnTerminate = false, startOnBoot = true),
            http = HttpConfig(url = "https://example.com", batchSync = true),
            logger = LoggerConfig(debug = true, logLevel = LogLevel.VERBOSE),
            motion = MotionConfig(stopTimeout = 10),
            geofence = GeofenceConfig(geofenceProximityRadius = 5000),
            persistence = PersistenceConfig(maxDaysToPersist = 7),
            audit = AuditConfig(enabled = true),
            privacyZone = PrivacyZoneConfig(enabled = true),
            security = SecurityConfig(encryptDatabase = true),
            attestation = AttestationConfig(enabled = true, refreshInterval = 1800),
        )
        assertEquals(original, TraceletConfig.fromMap(original.toMap()))
    }

    @Test
    fun `TraceletConfig fromMap defaults when map is empty`() {
        val restored = TraceletConfig.fromMap(emptyMap())
        assertEquals(TraceletConfig(), restored)
    }
}
