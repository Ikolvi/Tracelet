# Configuration Guide

Configuration is organized into logical groups. Pass a `Config` object to
`Tracelet.ready()` or update at runtime with `Tracelet.setConfig()`.

---

## Full Example

```dart
Config(
  geo: GeoConfig(                    // Location accuracy & sampling
    desiredAccuracy: DesiredAccuracy.high,
    distanceFilter: 10.0,
    stationaryRadius: 25.0,
    disableElasticity: false,        // Fixed vs speed-adaptive distance filter
    elasticityMultiplier: 1.0,       // Scale factor for adaptive filter
    enableAdaptiveMode: true,        // Auto-adjust distanceFilter (activity + battery + speed)
    enableTimestampMeta: true,       // Extra timing fields on each location
    stopAfterElapsedMinutes: -1,     // Auto-stop after N minutes (-1 = off)
    geofenceModeHighAccuracy: false, // Full GPS in geofence-only mode (Android)
    locationUpdateInterval: 1000,    // Android: desired update interval (ms)
    fastestLocationUpdateInterval: 500, // Android: fastest update interval (ms)
    locationTimeout: 60,             // Timeout for location request (s)
    activityType: LocationActivityType.other, // iOS: activity type hint
    deferTime: 0,                    // Android: defer updates for N ms
    locationAuthorizationRequest: LocationAuthorizationRequest.always, // Authorization level
    disableLocationAuthorizationAlert: false, // Suppress system auth prompt
    // Battery budget:
    batteryBudgetPerHour: 3.0,       // Target max %/hr drain (0 = disabled)
    // Sparse updates:
    enableSparseUpdates: true,       // App-level location deduplication
    sparseDistanceThreshold: 50.0,   // Min meters between recorded locations
    sparseMaxIdleSeconds: 300,       // Force update after N seconds idle
    // Dead reckoning:
    enableDeadReckoning: true,       // IMU navigation during GPS loss
    deadReckoningActivationDelay: 10, // Seconds without GPS before IMU
    deadReckoningMaxDuration: 120,   // Max seconds of dead reckoning
    // Periodic mode options (used with Tracelet.startPeriodic()):
    periodicLocationInterval: 900,           // 15 min between fixes
    periodicDesiredAccuracy: DesiredAccuracy.medium,
    periodicUseForegroundService: false,     // Android: WorkManager (no notification)
    periodicUseExactAlarms: false,           // Android: inexact alarms
    filter: LocationFilter(          // GPS denoising
      trackingAccuracyThreshold: 100,
      maxImpliedSpeed: 80,
      odometerAccuracyThreshold: 50,
      policy: LocationFilterPolicy.adjust,
      useKalmanFilter: true,         // Real-time GPS smoothing
      rejectMockLocations: true,     // Block spoofed GPS
      mockDetectionLevel: MockDetectionLevel.heuristic, // Advanced detection
    ),
  ),
  app: AppConfig(                    // Lifecycle behavior
    stopOnTerminate: false,
    startOnBoot: true,
    heartbeatInterval: 60,
    preventSuspend: false,           // iOS: silent audio keep-alive
    scheduleUseAlarmManager: false,  // Android: exact-time scheduling
    foregroundService: ForegroundServiceConfig(
      notificationTitle: 'My App',   // Android foreground notification
      notificationText: 'Tracking',
      // enabled: false,             // Set false to disable notification
    ),
  ),
  http: HttpConfig(                  // Server sync
    url: 'https://example.com/locations',
    method: HttpMethod.post,
    autoSync: true,
    batchSync: true,
    disableAutoSyncOnCellular: false, // Wi-Fi-only sync
    maxRetries: 10,                  // Retry transient failures
    retryBackoffBase: 1000,          // 1s base delay
    retryBackoffCap: 300000,         // 5 min max backoff
    enableDeltaCompression: true,    // Delta encoding for batch payloads
    deltaCoordinatePrecision: 6,     // Coordinate decimal places (6 ≈ 0.11m)
  ),
  motion: MotionConfig(              // Motion detection
    stopTimeout: 5,
    minimumActivityRecognitionConfidence: 75,
    disableStopDetection: false,
    stopDetectionDelay: 0,
    stopOnStationary: false,
    shakeThreshold: 2.5,             // m/s² — jolt to trigger moving
    stillThreshold: 0.4,             // m/s² — below this counts as still
    stillSampleCount: 25,            // consecutive still samples
  ),
  persistence: PersistenceConfig(    // Database retention
    persistMode: PersistMode.all,    // all | location | geofence | none
    maxDaysToPersist: 7,             // Auto-prune after N days (-1 = unlimited)
    maxRecordsToPersist: 5000,       // Max records (-1 = unlimited)
    disableProviderChangeRecord: false,
  ),
  geofence: GeofenceConfig(          // Geofence behavior
    geofenceProximityRadius: 1000,
    geofenceInitialTriggerEntry: true,
  ),
  logger: LoggerConfig(              // Logging
    debug: true,
    logLevel: LogLevel.verbose,
    logMaxDays: 3,
  ),
)
```

---

## GeoConfig

Location accuracy, sampling, and filtering.

| Property | Type | Default | Description |
|---|---|---|---|
| `desiredAccuracy` | `DesiredAccuracy` | `high` | GPS accuracy level |
| `distanceFilter` | `double` | `10.0` | Minimum meters between updates |
| `stationaryRadius` | `double` | `25.0` | Radius for stationary geofence |
| `disableElasticity` | `bool` | `false` | Disable speed-based distance filter scaling |
| `elasticityMultiplier` | `double` | `1.0` | Scale factor for elastic distance filter |
| `enableTimestampMeta` | `bool` | `false` | Add extra timing fields to each location |
| `stopAfterElapsedMinutes` | `int` | `-1` | Auto-stop after N minutes (-1 = off) |
| `geofenceModeHighAccuracy` | `bool` | `false` | Full GPS in geofence-only mode |
| `maxMonitoredGeofences` | `int` | `-1` | Max simultaneously monitored geofences (-1 = platform default: 100 Android, 20 iOS). Used with proximity-based geofence loading. |
| `useSignificantChangesOnly` | `bool` | `false` | Use significant location changes only |
| `showsBackgroundLocationIndicator` | `bool` | `true` | iOS: show blue status bar indicator |
| `pausesLocationUpdatesAutomatically` | `bool` | `false` | iOS: allow system to pause updates |
| `enableAdaptiveMode` | `bool` | `false` | Enable adaptive sampling — automatically adjusts `distanceFilter` based on activity, battery, and speed ([details](ADAPTIVE-SAMPLING.md)) |
| `locationUpdateInterval` | `int` | `1000` | **Android**: desired update interval in ms |
| `fastestLocationUpdateInterval` | `int` | `500` | **Android**: fastest update interval in ms |
| `locationTimeout` | `int` | `60` | Timeout for individual location request in seconds |
| `activityType` | `LocationActivityType` | `other` | **iOS**: hint for CLLocationManager (`other`, `automotiveNavigation`, `fitness`, `airborne`) |
| `deferTime` | `int` | `0` | **Android**: defer location updates for N ms (batching) |
| `locationAuthorizationRequest` | `LocationAuthorizationRequest` | `always` | Authorization level: `always` or `whenInUse` |
| `disableLocationAuthorizationAlert` | `bool` | `false` | Suppress system authorization prompt |
| **Battery Budget** | | | |
| `batteryBudgetPerHour` | `double` | `0.0` | Target max battery drain %/hr. `0` = disabled. Adjusts distanceFilter, accuracy, and periodic interval automatically ([details](BATTERY-BUDGET.md)) |
| **Sparse Updates** | | | |
| `enableSparseUpdates` | `bool` | `false` | App-level location deduplication — record only when moved beyond threshold ([details](SPARSE-UPDATES.md)) |
| `sparseDistanceThreshold` | `double` | `50.0` | Min meters from last recorded point before recording |
| `sparseMaxIdleSeconds` | `int` | `300` | Force a record after N seconds of no movement (`0` = disabled) |
| **Dead Reckoning** | | | |
| `enableDeadReckoning` | `bool` | `false` | IMU-based inertial navigation when GPS signal lost ([details](DEAD-RECKONING.md)) |
| `deadReckoningActivationDelay` | `int` | `10` | Seconds without GPS before activating IMU |
| `deadReckoningMaxDuration` | `int` | `120` | Max seconds of dead reckoning estimation |
| `filter` | `LocationFilter?` | `null` | GPS denoising configuration |
| **Periodic Mode** | | | |
| `periodicLocationInterval` | `int` | `900` | Seconds between periodic fixes (min 60). WorkManager enforces ≥ 15 min on Android. |
| `periodicDesiredAccuracy` | `DesiredAccuracy` | `medium` | Accuracy level per individual fix |
| `periodicUseForegroundService` | `bool` | `false` | **Android only.** `true` = foreground service + Handler timer (reliable, shows notification). `false` = WorkManager (no notification, ~15-min minimum). |
| `periodicUseExactAlarms` | `bool` | `false` | **Android only.** Use `AlarmManager` exact alarms for precise timing. Falls back to inexact alarms if `SCHEDULE_EXACT_ALARM` is not granted (Android 13+). See [Exact Alarms](BACKGROUND-TRACKING.md#exact-alarms-periodicuseexactalarms-true). |

> **Periodic mode** is activated via `Tracelet.startPeriodic()`. The GPS icon only appears for ~5–10 seconds per fix. See [Background Tracking](BACKGROUND-TRACKING.md#periodic-mode) for usage details.
>
> **iOS:** Periodic mode uses `BGAppRefreshTask` for supplementary wake-ups and `CLServiceSession` (iOS 18+) for authorization preservation. Killed-state auto-resume requires "Always" permission. See [iOS Setup](INSTALL-IOS.md#bgtaskscheduler-permitted-identifiers-required-for-periodic-mode) for required Info.plist keys.

### LocationFilter

| Property | Type | Default | Description |
|---|---|---|---|
| `trackingAccuracyThreshold` | `int` | `0` | Max horizontal accuracy (0 = off) |
| `maxImpliedSpeed` | `int` | `0` | Max implied speed in m/s (0 = off) |
| `odometerAccuracyThreshold` | `int` | `0` | Max accuracy for odometer (0 = off) |
| `policy` | `LocationFilterPolicy` | `adjust` | `adjust`, `ignore`, or `discard` |
| `useKalmanFilter` | `bool` | `false` | Enable Extended Kalman Filter GPS smoothing ([details](KALMAN-FILTER.md)) |
| `rejectMockLocations` | `bool` | `false` | Reject mock/spoofed locations ([details](MOCK-DETECTION.md)) |
| `mockDetectionLevel` | `MockDetectionLevel` | `disabled` | Detection depth: `disabled`, `basic`, or `heuristic` ([details](MOCK-DETECTION.md)) |

---

## AppConfig

App lifecycle, foreground service, and scheduling.

| Property | Type | Default | Description |
|---|---|---|---|
| `stopOnTerminate` | `bool` | `true` | Stop tracking when app is killed |
| `startOnBoot` | `bool` | `false` | Resume tracking after device reboot |
| `heartbeatInterval` | `int` | `-1` | Heartbeat interval in seconds (-1 = off) |
| `preventSuspend` | `bool` | `false` | iOS: silent audio keep-alive |
| `scheduleUseAlarmManager` | `bool` | `false` | Android: use AlarmManager for scheduling |
| `schedule` | `List<String>?` | `null` | Time-based schedule (e.g., `['1-5 09:00-17:00']`) |
| `foregroundService` | `ForegroundServiceConfig` | — | Android notification config |

### ForegroundServiceConfig

| Property | Type | Default | Description |
|---|---|---|---|
| `enabled` | `bool` | `true` | Enable foreground service |
| `channelId` | `String` | `'tracelet_channel'` | Notification channel ID |
| `channelName` | `String` | `'Location Tracking'` | Notification channel name |
| `notificationTitle` | `String` | `'App'` | Notification title |
| `notificationText` | `String` | `'Location tracking active'` | Notification body |
| `notificationSmallIcon` | `String?` | `null` | Custom icon resource name |
| `notificationColor` | `String?` | `null` | Notification accent color (hex string, e.g. `'#FF0000'`) |
| `notificationLargeIcon` | `String?` | `null` | Large notification icon resource name |
| `notificationOngoing` | `bool` | `true` | Make notification non-dismissible |
| `notificationPriority` | `NotificationPriority` | `defaultPriority` | Notification priority (`min`, `low`, `defaultPriority`, `high`, `max`) |
| `actions` | `List<String>` | `[]` | Custom notification action buttons |

---

## HttpConfig

Server sync configuration.

| Property | Type | Default | Description |
|---|---|---|---|
| `url` | `String` | `''` | Server endpoint URL |
| `method` | `HttpMethod` | `post` | HTTP method (`post` or `put`) |
| `autoSync` | `bool` | `true` | Auto-sync on location insert |
| `batchSync` | `bool` | `false` | Send all locations in one request |
| `maxBatchSize` | `int` | `250` | Max locations per batch (-1 = unlimited) |
| `headers` | `Map<String, String>` | `{}` | Custom HTTP headers |
| `params` | `Map<String, String>` | `{}` | Query parameters |
| `extras` | `Map<String, Object?>` | `{}` | Extra data added to each location |
| `autoSyncThreshold` | `int` | `0` | Min locations before auto-sync |
| `disableAutoSyncOnCellular` | `bool` | `false` | Wi-Fi-only auto-sync |
| `httpTimeout` | `int` | `60000` | Request timeout in milliseconds |
| `maxRetries` | `int` | `10` | Max retry attempts for transient failures (5xx, 429, timeout). Set to `0` to disable retries ([details](HTTP-SYNC.md)) |
| `retryBackoffBase` | `int` | `1000` | Base delay in ms for exponential backoff between retries |
| `retryBackoffCap` | `int` | `300000` | Max backoff delay in ms (5 min). Caps exponential growth |
| `httpRootProperty` | `String` | `'location'` | Root JSON key wrapping each location in payloads |
| `locationsOrderDirection` | `LocationOrder` | `asc` | Sort order for synced locations: `asc` (oldest first) or `desc` |
| `enableDeltaCompression` | `bool` | `false` | Delta-encode batch payloads for 60–80% size reduction. Requires `batchSync: true` ([details](DELTA-ENCODING.md)) |
| `deltaCoordinatePrecision` | `int` | `6` | Decimal places for coordinate deltas: `5` ≈ 1.1m, `6` ≈ 0.11m, `7` ≈ 0.011m |
| `authorization` | `Authorization?` | `null` | Token refresh config |

---

## MotionConfig

Motion detection tuning.

| Property | Type | Default | Description |
|---|---|---|---|
| `stopTimeout` | `int` | `5` | Minutes of stillness before declaring stationary |
| `minimumActivityRecognitionConfidence` | `int` | `75` | Min confidence (0–100) |
| `triggerActivities` | `Set<ActivityType>` | `{}` | Activity types that trigger motion |
| `disableStopDetection` | `bool` | `false` | Never declare stationary |
| `stopDetectionDelay` | `int` | `0` | Extra delay (seconds) before stationary |
| `stopOnStationary` | `bool` | `false` | Fully stop tracking when stationary |
| `motionTriggerDelay` | `int` | `0` | Delay (ms) before declaring moving |
| `disableMotionActivityUpdates` | `bool` | `false` | Disable platform activity recognition; falls back to permission-free accelerometer-only motion detection |
| `shakeThreshold` | `double` | `2.5` | Accelerometer magnitude (m/s²) to trigger stationary → moving. Higher = less sensitive |
| `stillThreshold` | `double` | `0.4` | Accelerometer magnitude (m/s²) below which a sample counts as "still". Lower = stricter |
| `stillSampleCount` | `int` | `25` | Consecutive still samples before starting stop-timeout. Higher = needs longer sustained stillness |

### Motion Sensitivity Presets

The 3 accelerometer fields work together. Here are recommended presets:

| Preset | `shakeThreshold` | `stillThreshold` | `stillSampleCount` | Behavior |
|---|---|---|---|---|
| **High** | `1.5` | `0.6` | `15` | Very responsive. Best for walking/exercise apps that need quick transitions. May cause false starts from phone vibration. |
| **Medium** (default) | `2.5` | `0.4` | `25` | Balanced. Good for general-purpose tracking. |
| **Low** | `4.0` | `0.2` | `40` | Conservative. Requires deliberate movement. Best for vehicle-only tracking or when false starts are a problem. |

```dart
// Example: Low sensitivity for vehicle tracking
await Tracelet.setConfig(Config(
  motion: MotionConfig(
    shakeThreshold: 4.0,   // strong jolt required
    stillThreshold: 0.2,   // very still before stop
    stillSampleCount: 40,  // ~8 seconds of stillness
  ),
));
```

> **Note:** Values are in m/s² on both Android and iOS. The iOS implementation
> automatically converts to g-force internally.

---

## PersistenceConfig

Database retention and persistence behavior.

| Property | Type | Default | Description |
|---|---|---|---|
| `persistMode` | `PersistMode` | `all` | `all`, `location`, `geofence`, or `none` |
| `maxDaysToPersist` | `int` | `-1` | Auto-prune after N days (-1 = unlimited) |
| `maxRecordsToPersist` | `int` | `-1` | Max stored records (-1 = unlimited) |
| `disableProviderChangeRecord` | `bool` | `false` | Skip provider change records |
| `allowIdenticalLocations` | `bool` | `false` | Allow locations at the same spot |

---

## GeofenceConfig

Geofence behavior and proximity-based monitoring.

| Property | Type | Default | Description |
|---|---|---|---|
| `geofenceProximityRadius` | `int` | `1000` | Proximity radius in meters. Only geofences within this radius of the device are actively registered with the OS. Enables unlimited geofences by loading/unloading based on proximity. |
| `geofenceInitialTriggerEntry` | `bool` | `true` | Fire enter event if already inside |
| `geofenceModeKnockOut` | `bool` | `false` | Remove geofence after first EXIT trigger |

> **Unlimited Geofences:** iOS limits apps to 20 monitored regions; Android limits to 100.
> Tracelet uses a built-in geospatial proximity query to automatically load and unload
> geofences based on `geofenceProximityRadius`, allowing you to effectively monitor
> **thousands of geofences**. As the device moves, the closest geofences are registered
> with the OS and far-away ones are unregistered. A `geofencesChange` event fires
> whenever geofences are activated or deactivated.

---

## LoggerConfig

Logging behavior.

| Property | Type | Default | Description |
|---|---|---|---|
| `debug` | `bool` | `false` | Enable debug mode (sounds + verbose logging) |
| `logLevel` | `LogLevel` | `off` | `off`, `error`, `warning`, `info`, `debug`, `verbose` |
| `logMaxDays` | `int` | `3` | Auto-prune logs after N days |
