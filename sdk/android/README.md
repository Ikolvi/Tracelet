# Tracelet Android SDK

[![Maven Central](https://img.shields.io/maven-central/v/com.ikolvi/tracelet-sdk)](https://central.sonatype.com/artifact/com.ikolvi/tracelet-sdk)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

> **Production-grade background geolocation for Android — no Flutter required.**

Battery-conscious motion-detection intelligence, geofencing, SQLite persistence, HTTP sync, and headless execution for pure Kotlin/Java apps.

## Installation

Latest version: [![Maven Central](https://img.shields.io/maven-central/v/com.ikolvi/tracelet-sdk)](https://central.sonatype.com/artifact/com.ikolvi/tracelet-sdk)

### Gradle (Kotlin DSL)

```kotlin
dependencies {
    implementation("com.ikolvi:tracelet-sdk:<latest-version>")
}
```

### Gradle (Groovy)

```groovy
dependencies {
    implementation 'com.ikolvi:tracelet-sdk:<latest-version>'
}
```

> Replace `<latest-version>` with the version shown in the badge above.

### Requirements

| Requirement | Value |
|---|---|
| `minSdk` | **26** (Android 8.0 Oreo) |
| `compileSdk` | **34+** |
| Kotlin | **1.9+** |
| Java | **17** |

## Quick Start

```kotlin
import com.ikolvi.tracelet.sdk.TraceletSdk
import com.ikolvi.tracelet.sdk.TraceletListener
import com.ikolvi.tracelet.sdk.model.*

class MyApp : Application() {
    override fun onCreate() {
        super.onCreate()

        val sdk = TraceletSdk.getInstance(this)

        // 1. Listen to events
        sdk.addListener(object : TraceletListener {
            override fun onLocation(location: Map<String, Any?>) {
                Log.d("Tracelet", "[location] $location")
            }
            override fun onMotionChange(data: Map<String, Any?>) {
                Log.d("Tracelet", "[motionchange] isMoving: ${data["isMoving"]}")
            }
        })

        // 2. Configure & ready
        sdk.ready(TraceletConfig(
            geo = GeoConfig(
                desiredAccuracy = DesiredAccuracy.HIGH,
                distanceFilter = 10.0,
                filter = LocationFilter(
                    trackingAccuracyThreshold = 100,
                    maxImpliedSpeed = 80,
                ),
            ),
            app = AppConfig(
                stopOnTerminate = false,
                startOnBoot = true,
            ),
            persistence = PersistenceConfig(
                maxDaysToPersist = 7,
                maxRecordsToPersist = 5000,
            ),
            logger = LoggerConfig(
                debug = true,
                logLevel = LogLevel.VERBOSE,
            ),
        )) { state ->
            // 3. Start tracking
            if (state["enabled"] == false) {
                sdk.start()
            }
        }
    }
}
```

## Configuration

The SDK uses the same structured config pattern as the Flutter plugin. All settings have sensible defaults — only override what you need.

### TraceletConfig

Top-level compound configuration. Organizes settings into logical groups:

```kotlin
TraceletConfig(
    geo = GeoConfig(...),          // Location accuracy, sampling, filtering
    app = AppConfig(...),          // Lifecycle, scheduling, foreground service
    http = HttpConfig(...),        // Server sync settings
    logger = LoggerConfig(...),    // Logging and debug sounds
    motion = MotionConfig(...),    // Motion detection sensitivity
    geofence = GeofenceConfig(...),// Geofence proximity and triggers
    persistence = PersistenceConfig(...), // Database retention
    audit = AuditConfig(...),      // [Enterprise] Tamper-proof audit trail
    privacyZone = PrivacyZoneConfig(...), // [Enterprise] Privacy zones
    security = SecurityConfig(...),// [Enterprise] Database encryption
    attestation = AttestationConfig(...), // [Enterprise] Device attestation
)
```

### GeoConfig

```kotlin
GeoConfig(
    desiredAccuracy = DesiredAccuracy.HIGH,  // HIGH, MEDIUM, LOW
    distanceFilter = 10.0,                   // meters between updates
    locationUpdateInterval = 1000,           // ms between updates
    stationaryRadius = 25.0,                 // meters to detect movement
    locationTimeout = 60,                    // seconds for fix timeout
    disableElasticity = false,               // speed-based distance scaling
    elasticityMultiplier = 1.0,             // elasticity scale factor
    stopAfterElapsedMinutes = -1,           // auto-stop (-1 = disabled)
    enableAdaptiveMode = false,             // multi-factor distance filter
    enableSparseUpdates = false,            // drop duplicate locations
    sparseDistanceThreshold = 50.0,         // meters for deduplication
    enableDeadReckoning = false,            // IMU fallback on GPS loss
    batteryBudgetPerHour = 0.0,             // auto-tune to battery budget
    filter = LocationFilter(                // GPS denoising
        trackingAccuracyThreshold = 100,    // min accuracy to record
        maxImpliedSpeed = 80,               // reject GPS spikes (m/s)
        useKalmanFilter = true,             // Extended Kalman smoothing
        rejectMockLocations = false,        // drop spoofed locations
        mockDetectionLevel = MockDetectionLevel.DISABLED,
    ),

    // Periodic mode
    periodicLocationInterval = 900,         // seconds (15 min default)
    periodicDesiredAccuracy = DesiredAccuracy.MEDIUM,
    periodicUseForegroundService = false,   // sub-15-min intervals
    periodicUseExactAlarms = false,         // AlarmManager scheduling

    // Android-only
    deferTime = 0,
    allowIdenticalLocations = false,
    geofenceModeHighAccuracy = false,

    // iOS-only (ignored on Android)
    useSignificantChangesOnly = false,
    showsBackgroundLocationIndicator = false,
    pausesLocationUpdatesAutomatically = false,
)
```

### AppConfig

```kotlin
AppConfig(
    stopOnTerminate = false,                // keep tracking after app killed
    startOnBoot = true,                     // restart on device boot
    heartbeatInterval = 60,                 // seconds (-1 to disable)
    schedule = listOf("1-7 09:00-17:00"),   // Mon-Sun 9am-5pm
    scheduleUseAlarmManager = false,        // exact-time scheduling
    foregroundService = ForegroundServiceConfig(
        notificationTitle = "My App",
        notificationText = "Tracking your location",
        notificationColor = "#4CAF50",
        notificationPriority = NotificationPriority.LOW,
        notificationSmallIcon = "drawable/ic_notification",
        actions = listOf("Pause", "Stop"),
    ),
    remoteConfigUrl = "https://api.example.com/config",
)
```

### HttpConfig

```kotlin
HttpConfig(
    url = "https://api.example.com/locations",
    method = HttpMethod.POST,
    headers = mapOf("Authorization" to "Bearer token"),
    batchSync = true,
    maxBatchSize = 100,
    autoSync = true,
    httpTimeout = 60000,
    disableAutoSyncOnCellular = false,      // Wi-Fi only sync
    maxRetries = 10,
    retryBackoffBase = 1000,                // exponential backoff
    retryBackoffCap = 300000,
    enableDeltaCompression = true,          // 60-80% payload reduction
    sslPinningFingerprints = listOf(        // certificate pinning
        "sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
    ),
)
```

### MotionConfig

```kotlin
MotionConfig(
    stopTimeout = 5,                        // minutes to declare stationary
    disableMotionActivityUpdates = false,   // accelerometer-only mode
    activityRecognitionInterval = 10000,    // ms between samples
    minimumActivityRecognitionConfidence = 75,
    stopOnStationary = false,               // auto-stop on stationary
    shakeThreshold = 2.5,                   // m/s² for motion trigger
    stillThreshold = 0.4,                   // m/s² for stillness
    stillSampleCount = 25,                  // samples for stop detection
)
```

### GeofenceConfig

```kotlin
GeofenceConfig(
    geofenceProximityRadius = 1000,         // activation radius (meters)
    geofenceInitialTriggerEntry = true,     // fire ENTER if already inside
    geofenceModeKnockOut = false,           // remove after EXIT
)
```

### PersistenceConfig

```kotlin
PersistenceConfig(
    persistMode = PersistMode.ALL,          // ALL, LOCATION, GEOFENCE, NONE
    maxDaysToPersist = 14,
    maxRecordsToPersist = 5000,
)
```

### LoggerConfig

```kotlin
LoggerConfig(
    logLevel = LogLevel.VERBOSE,            // VERBOSE, DEBUG, INFO, WARN, ERROR
    logMaxDays = 3,
    debug = true,                           // audible debug sounds
)
```

### Enterprise Features

```kotlin
// Tamper-proof location audit trail
AuditConfig(enabled = true, hashAlgorithm = HashAlgorithm.SHA256)

// Geographic privacy zones
PrivacyZoneConfig(enabled = true)

// At-rest SQLite encryption (SQLCipher AES-256)
SecurityConfig(encryptDatabase = true)

// Device attestation (Google Play Integrity)
AttestationConfig(enabled = true, refreshInterval = 3600)
```

## Event Listening

```kotlin
sdk.addListener(object : TraceletListener {
    override fun onLocation(location: Map<String, Any?>) {
        val coords = location["coords"] as? Map<String, Any?>
        val lat = coords?.get("latitude") as? Double
        val lng = coords?.get("longitude") as? Double
    }

    override fun onMotionChange(data: Map<String, Any?>) {
        val isMoving = data["isMoving"] as? Boolean ?: false
    }

    override fun onGeofence(data: Map<String, Any?>) {
        val identifier = data["identifier"] as? String
        val action = data["action"] as? String  // ENTER, EXIT, DWELL
    }

    override fun onHttp(data: Map<String, Any?>) {
        val success = data["success"] as? Boolean ?: false
        val status = data["status"] as? Int
    }

    override fun onActivityChange(data: Map<String, Any?>) {
        val activity = data["activity"] as? String
        val confidence = data["confidence"] as? Int
    }

    override fun onTrip(data: Map<String, Any?>) {
        val distance = data["distance"] as? Double
        val duration = data["duration"] as? Int
    }

    override fun onBudgetAdjustment(data: Map<String, Any?>) {
        val newDistanceFilter = data["distanceFilter"] as? Double
    }
})
```

## Permissions

### AndroidManifest.xml

The SDK's manifest includes required permissions automatically. For background location, add to your app's manifest:

```xml
<!-- Required -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />

<!-- Background tracking -->
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />

<!-- Boot restart -->
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />

<!-- Activity recognition (optional — for motion classification) -->
<uses-permission android:name="android.permission.ACTIVITY_RECOGNITION" />

<!-- Notification (Android 13+) -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

<!-- Exact alarms for periodic mode (optional) -->
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
```

### Runtime Permissions

```kotlin
// Check permission status
val status = sdk.getPermissionStatus()
// 0 = notDetermined, 1 = denied, 2 = whenInUse, 3 = always, 4 = deniedForever

// Request foreground permission
sdk.requestPermission { result ->
    if (result == 2) {
        // Got whenInUse — now request background
        sdk.requestPermission { backgroundResult ->
            // backgroundResult == 3 means "always"
        }
    }
}

// Android 13+ notification permission
val notifStatus = sdk.getNotificationPermissionStatus()
if (notifStatus != 3) {
    sdk.requestNotificationPermission { result -> }
}
```

## Foreground Service

### With Notification (Recommended)

```kotlin
sdk.ready(TraceletConfig(
    app = AppConfig(
        stopOnTerminate = false,
        startOnBoot = true,
        foregroundService = ForegroundServiceConfig(
            notificationTitle = "Fleet Tracker",
            notificationText = "Recording trip",
            notificationColor = "#4CAF50",
            notificationPriority = NotificationPriority.LOW,
        ),
    ),
)) { state -> sdk.start() }
```

### Without Notification

```kotlin
sdk.ready(TraceletConfig(
    app = AppConfig(
        stopOnTerminate = true,
        foregroundService = ForegroundServiceConfig(enabled = false),
    ),
)) { state -> sdk.start() }
```

## Geofencing

### Typed API (Recommended)

```kotlin
import com.ikolvi.tracelet.sdk.model.TraceletGeofence

// Add circular geofence
sdk.addGeofence(TraceletGeofence(
    identifier = "office",
    latitude = 37.4220,
    longitude = -122.0841,
    radius = 200.0,
    notifyOnEntry = true,
    notifyOnExit = true,
    notifyOnDwell = true,
    loiteringDelay = 30000,
))

// Add polygon geofence
sdk.addGeofence(TraceletGeofence(
    identifier = "campus",
    latitude = 0.0,    // Not used for polygon geofences
    longitude = 0.0,
    radius = 0.0,
    vertices = listOf(
        listOf(37.422, -122.084),
        listOf(37.423, -122.084),
        listOf(37.423, -122.083),
        listOf(37.422, -122.083),
    ),
))

// Add multiple geofences at once
sdk.addTypedGeofences(listOf(geofence1, geofence2, geofence3))

// Remove
sdk.removeGeofence("office")
sdk.removeGeofences()
```

### Dictionary API

```kotlin
// Add circular geofence
sdk.addGeofence(mapOf(
    "identifier" to "office",
    "latitude" to 37.4220,
    "longitude" to -122.0841,
    "radius" to 200.0,
    "notifyOnEntry" to true,
    "notifyOnExit" to true,
    "notifyOnDwell" to true,
    "loiteringDelay" to 30000,
))
```

### Privacy Zones

```kotlin
import com.ikolvi.tracelet.sdk.model.TraceletPrivacyZone

// Exclude locations inside the zone entirely
sdk.addPrivacyZone(TraceletPrivacyZone(
    identifier = "home",
    latitude = 37.4220,
    longitude = -122.0841,
    radius = 500.0,
    action = TraceletPrivacyZone.ACTION_EXCLUDE,
))

// Degrade precision inside the zone
sdk.addPrivacyZone(TraceletPrivacyZone(
    identifier = "office",
    latitude = 37.7749,
    longitude = -122.4194,
    radius = 300.0,
    action = TraceletPrivacyZone.ACTION_DEGRADE,
    degradedAccuracyMeters = 500.0,
))

// Event-only: dispatch but don't persist
sdk.addPrivacyZone(TraceletPrivacyZone(
    identifier = "hospital",
    latitude = 37.7631,
    longitude = -122.4576,
    radius = 200.0,
    action = TraceletPrivacyZone.ACTION_EVENT_ONLY,
))

// Add multiple privacy zones at once
sdk.addTypedPrivacyZones(listOf(zone1, zone2, zone3))
```

## HTTP Sync

```kotlin
// Manual sync
sdk.sync()

// Dynamic headers (e.g., rotating auth tokens)
sdk.setDynamicHeaders(mapOf("Authorization" to "Bearer new-token"))
```

## Periodic Mode

One-shot GPS fixes at timed intervals:

```kotlin
sdk.ready(TraceletConfig(
    geo = GeoConfig(
        periodicLocationInterval = 900,     // 15 min
        periodicDesiredAccuracy = DesiredAccuracy.MEDIUM,
        // Sub-15-minute intervals:
        periodicUseForegroundService = true,
        periodicLocationInterval = 300,     // 5 min
    ),
)) { state -> sdk.startPeriodic() }
```

## Tracking Modes

```kotlin
sdk.start()           // Continuous GPS tracking
sdk.startGeofences()  // Geofence-only mode
sdk.startPeriodic()   // One-shot periodic fixes
sdk.stop()            // Stop all tracking
```

## Lifecycle Methods

```kotlin
sdk.getState()               // Current tracking state
sdk.setConfig(configMap)     // Update config at runtime
sdk.reset()                  // Reset to defaults
sdk.getCurrentPosition()     // One-shot location request
sdk.getLastKnownLocation()   // Cached location (no battery cost)
sdk.getOdometer()            // Total distance traveled
sdk.getHealth()              // Diagnostic snapshot
sdk.getLocations()           // Read persisted locations
sdk.getCount()               // Count persisted locations
sdk.destroyLocations()       // Clear database
sdk.sync()                   // Manual HTTP sync
sdk.getLog()                 // Read log entries
sdk.emailLog("dev@co.com")   // Email logs for debugging
```

## Serialization

All config classes support round-trip serialization via `toMap()` and `fromMap()`:

```kotlin
// Serialize to Map (e.g., for persistence or network transfer)
val config = TraceletConfig(
    geo = GeoConfig(desiredAccuracy = DesiredAccuracy.HIGH, distanceFilter = 50.0),
    logger = LoggerConfig(logLevel = LogLevel.DEBUG, debug = true),
)
val map: Map<String, Any?> = config.toMap()

// Deserialize from Map
val restored = TraceletConfig.fromMap(map)

// Sub-configs also support fromMap()
val geoMap = mapOf("desiredAccuracy" to 2, "distanceFilter" to 100.0)
val geo = GeoConfig.fromMap(geoMap)  // Missing keys use defaults
```

This is useful for:
- Persisting config to SharedPreferences or a database
- Loading config from a remote JSON endpoint
- Passing config across process boundaries

## ProGuard / R8

The SDK includes consumer ProGuard rules. No additional configuration needed.

## Capabilities

- Background location tracking with motion detection
- Geofencing (circular + polygon) with unlimited proximity-based loading
- SQLite persistence with optional encryption (SQLCipher AES-256)
- HTTP auto-sync with retry, exponential backoff, delta encoding
- SSL certificate pinning
- Kalman filter GPS smoothing
- Adaptive sampling (speed/activity/battery-aware)
- Battery budget engine
- Trip detection
- Dead reckoning (accelerometer + gyroscope)
- Audit trail (tamper-proof SHA chain)
- Privacy zones
- Device attestation (Google Play Integrity)
- Schedule-based tracking
- Health check API
- Carbon footprint estimator
- GDPR/CCPA compliance reports

## Published Artifact

- **Group**: `com.ikolvi`
- **Artifact**: `tracelet-sdk`
- **Repository**: [Maven Central](https://central.sonatype.com/artifact/com.ikolvi/tracelet-sdk)

## Version History

| Version | Date | Notes |
|---|---|---|
| 0.1.0 | March 2026 | Initial release — full feature parity with Flutter plugin |

## License

Apache 2.0 — see [LICENSE](../../LICENSE) for details.

All native code is written from scratch. No proprietary SDK dependencies.
