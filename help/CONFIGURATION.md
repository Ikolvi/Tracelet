# Configuration Guide

Configuration in Tracelet 2.x.x is organized into logical, strongly-typed, nested sub-configurations. You can pass a compound `Config` object to `Tracelet.ready()` during initialization, or update individual sub-configurations at runtime using `Tracelet.setConfig()`.

---

## Complete Example

```dart
import 'package:tracelet/tracelet.dart';

final config = Config(
  // 1. Core location tracking and sampling settings
  geo: GeoConfig(
    desiredAccuracy: DesiredAccuracy.high,
    distanceFilter: 10.0,
    stationaryRadius: 25.0,
    locationTimeout: 60,
    disableElasticity: false,
    elasticityMultiplier: 1.0,
    stopAfterElapsedMinutes: -1,
    maxMonitoredGeofences: -1,
    enableTimestampMeta: false,
    enableAdaptiveMode: false,
    periodicLocationInterval: 900,
    periodicDesiredAccuracy: DesiredAccuracy.medium,
    enableSparseUpdates: false,
    sparseDistanceThreshold: 50.0,
    sparseMaxIdleSeconds: 300,
    batteryBudgetPerHour: 0.0,
    enableDeadReckoning: false,
    deadReckoningActivationDelay: 0,
    deadReckoningMaxDuration: 0,
    filter: const LocationFilter(
      trackingAccuracyThreshold: 100,
      maxImpliedSpeed: 80,
      odometerAccuracyThreshold: 50,
      policy: LocationFilterPolicy.adjust,
      rejectMockLocations: true,
      mockDetectionLevel: 1, // basic
      useKalmanFilter: true,
    ),
  ),

  // 2. Application lifecycle and remote scheduling/sync
  app: AppConfig(
    stopOnTerminate: false,
    startOnBoot: true,
    heartbeatInterval: 60,
    schedule: ['1-5 09:00-17:00'], // Active hours Monday-Friday
    remoteConfigUrl: 'https://api.my-server.com/tracelet/config',
    remoteConfigHeaders: {'Authorization': 'Bearer YOUR_TOKEN'},
    remoteConfigTimeout: 60000,
    remoteConfigRefreshInterval: 1440,
  ),

  // 3. Android platform-specific options
  android: AndroidConfig(
    locationUpdateInterval: 1000,
    fastestLocationUpdateInterval: 500,
    deferTime: 0,
    allowIdenticalLocations: false,
    geofenceModeHighAccuracy: false,
    periodicUseForegroundService: false,
    periodicUseExactAlarms: false,
    scheduleUseAlarmManager: false,
    foregroundService: ForegroundServiceConfig(
      enabled: true,
      channelId: 'tracelet_channel',
      channelName: 'Location Tracking',
      notificationTitle: 'Tracking Active',
      notificationText: 'Tracking location in background',
      notificationColor: '#4CAF50',
      notificationPriority: NotificationPriority.defaultPriority,
      notificationOngoing: true,
    ),
  ),

  // 4. iOS platform-specific options
  ios: IosConfig(
    activityType: LocationActivityType.other,
    useSignificantChangesOnly: false,
    showsBackgroundLocationIndicator: true,
    pausesLocationUpdatesAutomatically: false,
    locationAuthorizationRequest: LocationAuthorizationRequest.always,
    disableLocationAuthorizationAlert: false,
    preventSuspend: false,
  ),

  // 5. Server sync and upload settings
  http: HttpConfig(
    url: 'https://api.my-server.com/locations',
    method: HttpMethod.post,
    headers: {'Authorization': 'Bearer YOUR_TOKEN'},
    params: {'device_id': 'unique_device_id'},
    autoSync: true,
    batchSync: true,
    maxBatchSize: 250,
    autoSyncThreshold: 0,
    autoSyncDelay: 10000,
    httpTimeout: 60000,
    locationsOrderDirection: LocationOrderDirection.ascending,
    disableAutoSyncOnCellular: false,
    maxRetries: 3,
    retryBackoffBase: 1,
    retryBackoffCap: 60,
    enableDeltaCompression: false,
    deltaCoordinatePrecision: 5,
  ),

  // 6. Accelerometer-based motion and sleep tuning
  motion: MotionConfig(
    stopTimeout: 5,
    motionTriggerDelay: 0,
    disableMotionActivityUpdates: false,
    isMoving: false,
    activityRecognitionInterval: 1000,
    minimumActivityRecognitionConfidence: 75,
    disableStopDetection: false,
    stopDetectionDelay: 0,
    stopOnStationary: false,
    stationaryRadius: 25.0,
    useSignificantChangesOnly: false,
    shakeThreshold: 2.5,
    stillThreshold: 0.4,
    stillSampleCount: 25,
  ),

  // 7. Core geofencing engine settings
  geofence: GeofenceConfig(
    geofenceModeHighAccuracy: false,
    geofenceInitialTriggerEntry: true,
    geofenceProximityRadius: 1000,
  ),

  // 8. Database retention limits
  persistence: PersistenceConfig(
    maxDaysToPersist: 7,
    maxRecordsToPersist: 5000,
    persistMode: PersistMode.all,
    disableProviderChangeRecord: false,
  ),

  // 9. Logger and console debug options
  logger: LoggerConfig(
    logLevel: LogLevel.info,
    logMaxDays: 3,
    debug: false,
  ),

  // 10. Cryptographic proof and security settings (Enterprise)
  audit: AuditConfig(
    enabled: true,
    hashAlgorithm: HashAlgorithm.sha256,
    includeExtrasInHash: false,
  ),
  privacyZone: PrivacyZoneConfig(
    enabled: true,
  ),
  security: SecurityConfig(
    encryptDatabase: true,
  ),
  attestation: AttestationConfig(
    enabled: true,
    refreshInterval: 3600,
  ),
);
```

---

## 1. GeoConfig

Configures Core Location parameters, accuracy, sampling filter thresholds, battery budgets, and dead reckoning behavior.

| Property | Type | Default | Description |
|---|---|---|---|
| `desiredAccuracy` | `DesiredAccuracy` | `DesiredAccuracy.high` | The desired location accuracy: `high`, `medium`, `low`, `lowest`, or `nav`. |
| `distanceFilter` | `double` | `10.0` | Minimum horizontal movement in meters required before a new location is recorded. |
| `stationaryRadius` | `double` | `25.0` | Radius in meters around the stationary location where the device is considered stationary. |
| `locationTimeout` | `int` | `60` | Timeout in seconds for individual location requests. |
| `disableElasticity` | `bool` | `false` | Disable speed-based distance filter scaling (fixed vs speed-adaptive filters). |
| `elasticityMultiplier` | `double` | `1.0` | Scale factor for adaptive elasticity. Higher value increases filter size faster with speed. |
| `stopAfterElapsedMinutes` | `int` | `-1` | Automatically stop tracking after this many minutes. `-1` to disable. |
| `maxMonitoredGeofences` | `int` | `-1` | Maximum monitored geofences. `-1` falls back to platform default (100 on Android, 20 on iOS). |
| `enableTimestampMeta` | `bool` | `false` | Add extra timing metadata fields to each location payload. |
| `enableAdaptiveMode` | `bool` | `false` | Enable adaptive mode to automatically scale [distanceFilter] based on activity, speed, and battery. |
| `periodicLocationInterval` | `int` | `900` | Interval in seconds between location updates in periodic mode (minimum 60s). |
| `periodicDesiredAccuracy` | `DesiredAccuracy` | `DesiredAccuracy.medium` | The desired accuracy for each periodic location update. |
| `enableSparseUpdates` | `bool` | `false` | Deduplicate location recording at the database layer. Drops locations within [sparseDistanceThreshold]. |
| `sparseDistanceThreshold` | `double` | `50.0` | Minimum horizontal distance in meters between consecutive locations in sparse mode. |
| `sparseMaxIdleSeconds` | `int` | `300` | Force a recorded location update after this many idle seconds even if the device has not moved. |
| `batteryBudgetPerHour` | `double` | `0.0` | Target maximum hourly battery drain percentage (e.g. `2.0` for 2%). `0.0` to disable. |
| `enableDeadReckoning` | `bool` | `false` | Enable inertial sensor fusion positioning during GPS signal loss. |
| `deadReckoningActivationDelay` | `int` | `0` | Seconds without a GPS fix before activating dead reckoning. |
| `deadReckoningMaxDuration` | `int` | `0` | Maximum seconds to execute dead reckoning estimation. `0` for unlimited. |
| `resolveAddress` | `bool` | `false` | Automatically resolve coordinates to a street address using the native OS Geocoder. |
| `filter` | `LocationFilter` | `const LocationFilter()` | Detailed GPS filtering and smoothing options. |

> **Note:** `periodicUseForegroundService` and `periodicUseExactAlarms` are Android-only — configure them under `AndroidConfig`, not `GeoConfig`.

### LocationFilter

Nested under `GeoConfig.filter`. Controls GPS denoising, Extended Kalman Filter smoothing, and spoofing protection.

| Property | Type | Default | Description |
|---|---|---|---|
| `trackingAccuracyThreshold` | `int` | `100` | Reject location fixes with horizontal accuracy worse than this value in meters. |
| `maxImpliedSpeed` | `int` | `80` | Reject locations implying a physical speed greater than this value in m/s. |
| `odometerAccuracyThreshold` | `int` | `50` | Only count location updates with accuracy better than this value toward odometer metrics. |
| `policy` | `LocationFilterPolicy` | `LocationFilterPolicy.adjust` | How to handle rejected fixes: `adjust`, `ignore`, or `discard`. |
| `rejectMockLocations` | `bool` | `false` | Reject locations flagged as fake or spoofed by the host OS. |
| `mockDetectionLevel` | `int` | `1` | Heuristic mock detection sensitivity depth level: `0` (disabled), `1` (basic), `2` (heuristic). |
| `useKalmanFilter` | `bool` | `false` | Enable Extended Kalman Filter (EKF) smoothing to eliminate GPS drift and jitter. |

---

## 2. AppConfig

Controls application-level lifecycle behavior, background execution, and remote configurations.

| Property | Type | Default | Description |
|---|---|---|---|
| `stopOnTerminate` | `bool` | `true` | Stop location tracking immediately when the app process is swiped away or terminated. |
| `startOnBoot` | `bool` | `false` | Resume location tracking automatically when the device boots or restarts (Android). |
| `heartbeatInterval` | `int` | `60` | The interval in seconds between heartbeat ticks. Set to `-1` to disable. |
| `schedule` | `List<String>` | `[]` | Cron-like schedule strings representing active tracking windows (e.g. `['1-5 09:00-17:00']`). |
| `remoteConfigUrl` | `String?` | `null` | Server endpoint to dynamically fetch configuration updates at runtime. |
| `remoteConfigHeaders` | `Map<String, String>?` | `null` | Custom HTTP headers included with the remote configuration fetch request. |
| `remoteConfigTimeout` | `int` | `60000` | Remote configuration request timeout in milliseconds. |
| `remoteConfigRefreshInterval` | `int` | `1440` | Refresh interval in minutes to check for configuration changes. |

---

## 3. AndroidConfig

Android-specific configurations. Ignored on iOS and Web.

| Property | Type | Default | Description |
|---|---|---|---|
| `locationUpdateInterval` | `int` | `1000` | The desired interval (in milliseconds) between location updates. |
| `fastestLocationUpdateInterval` | `int` | `500` | The absolute fastest interval (in milliseconds) the app can handle location updates. |
| `deferTime` | `int` | `0` | Max wait time in milliseconds for location updates before batching/dispatching them. |
| `allowIdenticalLocations` | `bool` | `false` | Allow recording identical consecutive locations (no movement detection check). |
| `geofenceModeHighAccuracy` | `bool` | `false` | Enforce full high-accuracy GPS monitoring during geofence-only tracking mode. |
| `periodicUseForegroundService` | `bool` | `false` | Use a persistent foreground service for periodic mode instead of WorkManager. |
| `periodicUseExactAlarms` | `bool` | `false` | Use AlarmManager exact alarms for periodic updates instead of WorkManager. |
| `scheduleUseAlarmManager` | `bool` | `false` | Use `AlarmManager` exact scheduling to precisely execute schedule events. |
| `foregroundService` | `ForegroundServiceConfig` | — | Configures the notification visible while the background service is running. |

### ForegroundServiceConfig

Nested under `AndroidConfig.foregroundService`. Controls the user-facing foreground service notification.

| Property | Type | Default | Description |
|---|---|---|---|
| `enabled` | `bool` | `true` | Enable or disable the user-visible foreground service notification. |
| `channelId` | `String` | `'tracelet_channel'` | Notification channel ID. |
| `channelName` | `String` | `'Tracelet'` | Human-readable notification channel name. |
| `notificationTitle` | `String` | `'Tracelet'` | Title displayed in the notification. |
| `notificationText` | `String` | `'Tracking location...'` | Content body text displayed in the notification. |
| `notificationColor` | `String?` | `null` | Notification accent color hex string (e.g. `'#4CAF50'`). |
| `notificationSmallIcon` | `String?` | `null` | Custom resource name for the notification's small icon. |
| `notificationLargeIcon` | `String?` | `null` | Custom resource name for the notification's large icon. |
| `notificationStartedAt` | `int?` | `null` | Epoch milliseconds (wall clock) from which the notification counts up. Used only when `notificationShowTimer` is true; future values are clamped to the current time when posted. |
| `notificationShowTimer` | `bool` | `false` | Show a count-up chronometer from `notificationStartedAt`. No timer is shown without a start value. Android advances it without notification reposts. |
| `notificationOnlyAlertOnce` | `bool` | `false` | Alert with sound or vibration only on the first notification post, so later content updates are silent. Android only; not applicable to iOS Live Activities. |
| `notificationPriority` | `NotificationPriority` | `defaultPriority` | Priority level: `min`, `low`, `defaultPriority`, `high`, or `max`. |
| `notificationOngoing` | `bool` | `true` | When true, the notification cannot be cleared by swiping. |
| `actions` | `List<String>` | `[]` | Custom action buttons to display inside the notification. |

---

## 4. IosConfig

iOS-specific configurations. Ignored on Android and Web.

| Property | Type | Default | Description |
|---|---|---|---|
| `activityType` | `LocationActivityType` | `other` | Hint to the system about the activity type: `other`, `automotiveNavigation`, `fitness`, or `airborne`. |
| `useSignificantChangesOnly` | `bool` | `false` | Use significant-change monitoring instead of standard continuous GPS to save battery. |
| `showsBackgroundLocationIndicator` | `bool` | `false` | Show the native blue status bar background indicator when tracking in the background. |
| `pausesLocationUpdatesAutomatically` | `bool` | `false` | Allow iOS Core Location to automatically pause updates when the device stops moving. |
| `locationAuthorizationRequest` | `LocationAuthorizationRequest` | `always` | Authorization level to request: `always` or `whenInUse`. |
| `disableLocationAuthorizationAlert` | `bool` | `false` | Suppress the automatic dialog warning when required permissions are missing. |
| `preventSuspend` | `bool` | `false` | Play an extremely quiet silent audio clip in the background to prevent iOS from suspending the process. |
| `liveActivityConfig` | `LiveActivityConfig?` | `null` | Opt in to an iOS 17+ Live Activity for the tracking indicator. Requires a Widget Extension. |

### LiveActivityConfig

Nested under `IosConfig.liveActivityConfig`. When absent, Tracelet does not create a Live Activity.

| Property | Type | Default | Description |
|---|---|---|---|
| `title` | `String` | required | Static Live Activity title. A change applies when the next activity starts because ActivityKit attributes are immutable while it is running. |
| `body` | `String` | required | Dynamic status text shown by the Live Activity. |
| `startedAt` | `int?` | `null` | Epoch milliseconds (wall clock) from which the Live Activity counts up. Used only when `showTimer` is true; future values are clamped when rendered. |
| `showTimer` | `bool` | `false` | Show a count-up timer from `startedAt`. No timer is shown without a start value, and iOS advances it without SDK updates. |

The bundled `TraceletLiveActivityView` renders the timer automatically. A custom Widget Extension can opt in using `context.state.startedAt` and `context.state.showTimer`; the SDK does not push periodic updates because `Text(timerInterval:countsDown:)` advances on its own.

### Updating the tracking indicator

Use `Tracelet.setNotification` to update only notification or Live Activity content:

```dart
await Tracelet.setNotification(
  text: 'Delivery in progress',
  startedAt: shiftStartedAt.millisecondsSinceEpoch,
  showTimer: true,
);
```

Only non-null arguments are merged into the persisted indicator configuration. This is safer than using `setConfig` for frequent content updates: the targeted payload cannot carry `http.url`, headers, or other unrelated settings that could be overwritten accidentally. An all-null call is a no-op.

On Android, the foreground-service notification is reposted if the service is running; otherwise the values are persisted for its next post. On iOS, the call updates an already configured Live Activity and is a logged no-op when `liveActivityConfig` is absent. On Web it is a no-op. `showTimer: false` disables a stored timer; `startedAt` cannot be cleared through this nullable update API and remains inert while the timer is off.

`Tracelet.updateNotification()` remains available when configuration was changed separately and the current indicator only needs to be reposted. Neither API needs periodic calls to advance the timer.

---

## 5. HttpConfig

Configures the native HTTP Sync engine for local database uploads.

| Property | Type | Default | Description |
|---|---|---|---|
| `url` | `String?` | `null` | Server endpoint URL to upload locations to. |
| `method` | `HttpMethod` | `HttpMethod.post` | The HTTP method to use: `post` or `put`. |
| `headers` | `Map<String, String>?` | `null` | Custom HTTP headers to include with sync requests. |
| `params` | `Map<String, Object?>?` | `null` | Query parameters or additional JSON fields attached to sync payloads. |
| `autoSync` | `bool` | `true` | Sync locations immediately as they are recorded. |
| `batchSync` | `bool` | `false` | Send stored locations in a batch array within a single request. |
| `maxBatchSize` | `int` | `250` | Maximum locations allowed in a single batch request (-1 for unlimited). |
| `autoSyncThreshold` | `int` | `0` | Minimum locations required in the database before auto-sync is triggered. |
| `autoSyncDelay` | `int` | `10000` | Delay in milliseconds to wait before triggering an auto-sync after a location is recorded. |
| `httpTimeout` | `int` | `60000` | Upload request timeout in milliseconds. |
| `locationsOrderDirection` | `LocationOrderDirection` | `ascending` | Sort direction for batch payloads: `ascending` (oldest first) or `descending`. |
| `disableAutoSyncOnCellular` | `bool` | `false` | Restrict sync requests to Wi-Fi networks only. |
| `maxRetries` | `int` | `3` | Maximum retry attempts for transient server failures. |
| `retryBackoffBase` | `int` | `1` | Base delay in seconds for exponential backoff between retries. |
| `retryBackoffCap` | `int` | `60` | Maximum retry backoff delay in seconds (caps exponential growth). |
| `enableDeltaCompression` | `bool` | `false` | Compresses location fields using delta-encoding, reducing payload size by 60–80%. |
| `deltaCoordinatePrecision` | `int` | `5` | Decimal precision for coordinate deltas in delta compression (e.g. `5` ≈ 1.1m, `6` ≈ 0.11m). |

---

## 6. MotionConfig

Granular control over accelerometer activity sensors and stationary state detection.

| Property | Type | Default | Description |
|---|---|---|---|
| `stopTimeout` | `int` | `5` | Minutes of sustained stillness required before the SDK declares the stationary state. |
| `motionTriggerDelay` | `int` | `0` | Delay in milliseconds before starting tracking when movement is triggered. |
| `disableMotionActivityUpdates` | `bool` | `false` | Disable platform activity recognition and use permission-free accelerometer-only detection. |
| `isMoving` | `bool` | `false` | The initial motion state on boot/ready: `true` (moving) or `false` (stationary). |
| `activityRecognitionInterval` | `int` | `1000` | Update interval in milliseconds for activity recognition sensors. |
| `minimumActivityRecognitionConfidence` | `int` | `75` | Minimum confidence score (0-100) required to accept a detected activity. |
| `disableStopDetection` | `bool` | `false` | Prevent the SDK from automatically transitioning back to the stationary state. |
| `stopDetectionDelay` | `int` | `0` | Additional delay in seconds before declaring a stationary state. |
| `stopOnStationary` | `bool` | `false` | Completely shut down the tracking engine when the device becomes stationary. |
| `activityTypes` | `List<LocationActivityType>?` | `null` | List of activity types allowed to trigger moving state. `null` for any moving activity. |
| `stationaryRadius` | `double` | `25.0` | Stationary radius in meters. |
| `useSignificantChangesOnly` | `bool` | `false` | Rely only on significant movement changes (iOS only). |
| `shakeThreshold` | `double` | `2.5` | Acceleration threshold (m/s²) required to trigger stationary → moving state. |
| `stillThreshold` | `double` | `0.4` | Acceleration threshold (m/s²) below which a sample counts as stationary. |
| `stillSampleCount` | `int` | `25` | Consecutive stationary samples required to initiate the `stopTimeout` countdown. |

---

## 7. GeofenceConfig

Proximity-based unlimited geofence engine configuration.

| Property | Type | Default | Description |
|---|---|---|---|
| `geofenceModeHighAccuracy` | `bool` | `false` | Force high-accuracy continuous location tracking during geofencing. |
| `geofenceInitialTriggerEntry` | `bool` | `true` | Immediately trigger an `ENTER` event if the device is already inside the geofence at registration. |
| `geofenceProximityRadius` | `int` | `1000` | Proximity radius in meters. Only geofences within this radius are actively loaded into the OS. |

---

## 8. PersistenceConfig

Configures the local SQLite cache size and data retention rules.

| Property | Type | Default | Description |
|---|---|---|---|
| `maxDaysToPersist` | `int` | `1` | Maximum days to keep location history in the database. `-1` to disable auto-pruning. |
| `maxRecordsToPersist` | `int` | `-1` | Maximum location records to retain in the database. `-1` to disable record caps. |
| `persistMode` | `PersistMode` | `PersistMode.all` | Persistence depth filter: `all` (locations + geofences), `location`, `geofence`, or `none`. |
| `disableProviderChangeRecord` | `bool` | `false` | Skip writing location records when GPS/Wi-Fi positioning toggles occur. |

---

## 9. LoggerConfig

| Property | Type | Default | Description |
|---|---|---|---|
| `logLevel` | `LogLevel` | `LogLevel.info` | Minimum log severity level to capture: `off`, `error`, `warning`, `info`, `debug`, or `verbose`. |
| `logMaxDays` | `int` | `3` | Maximum days to retain log files in the database. |
| `debug` | `bool` | `false` | Enable debug mode. Emits system-level sounds and flashes visual indicators for tracking events. |

---

## 10. Enterprise Security & Attestation Configs

These advanced security configurations are exclusively available to **Tracelet Enterprise** customers.

### SecurityConfig (At-Rest Database Encryption)

| Property | Type | Default | Description |
|---|---|---|---|
| `encryptDatabase` | `bool` | `false` | Enable SQLCipher AES-256 at-rest database encryption. |
| `encryptionKey` | `String?` | `null` | Optional custom encryption key. If `null`, a secure random key is automatically managed. |

### AttestationConfig (Device Attestation)

| Property | Type | Default | Description |
|---|---|---|---|
| `enabled` | `bool` | `false` | Periodically generate a hardware-attested token (Play Integrity on Android, App Attest on iOS). |
| `refreshInterval` | `int` | `3600` | Refresh interval in seconds for the device integrity token. |
| `verificationUrl` | `String?` | `null` | HTTPS endpoint to verify device integrity verdicts before sending sync payloads. |

### AuditConfig (Tamper-Proof Audit Trail)

| Property | Type | Default | Description |
|---|---|---|---|
| `enabled` | `bool` | `false` | Enable blockchain-like SHA-256 hash chaining of location records. |
| `hashAlgorithm` | `HashAlgorithm` | `HashAlgorithm.sha256` | Hash algorithm to use for signature generation. |
| `includeExtrasInHash` | `bool` | `false` | Cryptographically tie the `extras` map to the integrity verification chain. |

### PrivacyZoneConfig (Privacy Protection)

| Property | Type | Default | Description |
|---|---|---|---|
| `enabled` | `bool` | `false` | Evaluate locations against registered privacy zones to obscure, obfuscate, or drop telemetry data. |
