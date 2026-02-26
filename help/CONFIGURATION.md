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
    enableTimestampMeta: true,       // Extra timing fields on each location
    stopAfterElapsedMinutes: -1,     // Auto-stop after N minutes (-1 = off)
    geofenceModeHighAccuracy: false, // Full GPS in geofence-only mode (Android)
    filter: LocationFilter(          // GPS denoising
      trackingAccuracyThreshold: 100,
      maxImpliedSpeed: 80,
      odometerAccuracyThreshold: 50,
      policy: LocationFilterPolicy.adjust,
      useKalmanFilter: true,         // Real-time GPS smoothing
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
  ),
  motion: MotionConfig(              // Motion detection
    stopTimeout: 5,
    minimumActivityRecognitionConfidence: 75,
    disableStopDetection: false,
    stopDetectionDelay: 0,
    stopOnStationary: false,
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
| `useSignificantChangesOnly` | `bool` | `false` | Use significant location changes only |
| `showsBackgroundLocationIndicator` | `bool` | `true` | iOS: show blue status bar indicator |
| `pausesLocationUpdatesAutomatically` | `bool` | `false` | iOS: allow system to pause updates |
| `filter` | `LocationFilter?` | `null` | GPS denoising configuration |

### LocationFilter

| Property | Type | Default | Description |
|---|---|---|---|
| `trackingAccuracyThreshold` | `int` | `0` | Max horizontal accuracy (0 = off) |
| `maxImpliedSpeed` | `int` | `0` | Max implied speed in m/s (0 = off) |
| `odometerAccuracyThreshold` | `int` | `0` | Max accuracy for odometer (0 = off) |
| `policy` | `LocationFilterPolicy` | `adjust` | `adjust`, `ignore`, or `discard` |
| `useKalmanFilter` | `bool` | `false` | Enable Extended Kalman Filter GPS smoothing ([details](KALMAN-FILTER.md)) |

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
| `notificationPriority` | `int` | `0` | Notification priority |

---

## HttpConfig

Server sync configuration.

| Property | Type | Default | Description |
|---|---|---|---|
| `url` | `String` | `''` | Server endpoint URL |
| `method` | `HttpMethod` | `post` | HTTP method (`post` or `put`) |
| `autoSync` | `bool` | `true` | Auto-sync on location insert |
| `batchSync` | `bool` | `false` | Send all locations in one request |
| `maxBatchSize` | `int` | `-1` | Max locations per batch (-1 = unlimited) |
| `headers` | `Map<String, String>` | `{}` | Custom HTTP headers |
| `params` | `Map<String, String>` | `{}` | Query parameters |
| `extras` | `Map<String, Object?>` | `{}` | Extra data added to each location |
| `autoSyncThreshold` | `int` | `0` | Min locations before auto-sync |
| `disableAutoSyncOnCellular` | `bool` | `false` | Wi-Fi-only auto-sync |
| `httpTimeout` | `int` | `60000` | Request timeout in milliseconds |
| `authorization` | `Authorization?` | `null` | Token refresh config |

---

## MotionConfig

Motion detection tuning.

| Property | Type | Default | Description |
|---|---|---|---|
| `stopTimeout` | `int` | `5` | Minutes of stillness before declaring stationary |
| `minimumActivityRecognitionConfidence` | `int` | `75` | Min confidence (0–100) |
| `triggerActivities` | `String` | `''` | Comma-separated activity filter |
| `disableStopDetection` | `bool` | `false` | Never declare stationary |
| `stopDetectionDelay` | `int` | `0` | Extra delay (seconds) before stationary |
| `stopOnStationary` | `bool` | `false` | Fully stop tracking when stationary |
| `motionTriggerDelay` | `int` | `0` | Delay (seconds) before declaring moving |
| `disableMotionActivityUpdates` | `bool` | `false` | Disable platform activity recognition; falls back to permission-free accelerometer-only motion detection |

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

Geofence behavior.

| Property | Type | Default | Description |
|---|---|---|---|
| `geofenceProximityRadius` | `int` | `1000` | Activation radius in meters |
| `geofenceInitialTriggerEntry` | `bool` | `true` | Fire enter event if already inside |

---

## LoggerConfig

Logging behavior.

| Property | Type | Default | Description |
|---|---|---|---|
| `debug` | `bool` | `false` | Enable debug mode (sounds + verbose logging) |
| `logLevel` | `LogLevel` | `off` | `off`, `error`, `warning`, `info`, `debug`, `verbose` |
| `logMaxDays` | `int` | `3` | Auto-prune logs after N days |
