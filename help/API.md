# API Reference

---

## Lifecycle

| Method | Returns | Description |
|---|---|---|
| `Tracelet.ready(config)` | `State` | Initialize with configuration |
| `Tracelet.start()` | `State` | Start tracking |
| `Tracelet.stop()` | `State` | Stop tracking |
| `Tracelet.startGeofences()` | `State` | Geofence-only mode |
| `Tracelet.startPeriodic()` | `State` | Periodic interval mode (GPS-friendly) |
| `Tracelet.getState()` | `State` | Current state |
| `Tracelet.setConfig(config)` | `State` | Update configuration |
| `Tracelet.reset()` | `State` | Reset to defaults |

---

## Location

| Method | Returns | Description |
|---|---|---|
| `Tracelet.getCurrentPosition()` | `Location` | One-shot position |
| `Tracelet.watchPosition(callback)` | `int` | High-frequency watch |
| `Tracelet.stopWatchPosition(id)` | `bool` | Stop a watch |
| `Tracelet.changePace(isMoving)` | `bool` | Force motion state |
| `Tracelet.getOdometer()` | `double` | Odometer in meters |
| `Tracelet.setOdometer(value)` | `Location` | Reset odometer |
| `Tracelet.getLastKnownLocation()` | `Location?` | Cached location without GPS — zero battery cost |

---

## Geofencing

| Method | Returns | Description |
|---|---|---|
| `Tracelet.addGeofence(geofence)` | `bool` | Add a geofence |
| `Tracelet.addGeofences(list)` | `bool` | Add multiple |
| `Tracelet.removeGeofence(id)` | `bool` | Remove by identifier |
| `Tracelet.removeGeofences()` | `bool` | Remove all |
| `Tracelet.getGeofences()` | `List<Geofence>` | List all |
| `Tracelet.getGeofence(id)` | `Geofence?` | Get one |
| `Tracelet.geofenceExists(id)` | `bool` | Check existence |

---

## Privacy Zones

| Method | Returns | Description |
|---|---|---|
| `Tracelet.addPrivacyZone(zone)` | `bool` | Add a privacy zone ([details](PRIVACY-ZONES.md)) |
| `Tracelet.addPrivacyZones(zones)` | `bool` | Add multiple privacy zones |
| `Tracelet.removePrivacyZone(id)` | `bool` | Remove by identifier |
| `Tracelet.removePrivacyZones()` | `bool` | Remove all privacy zones |
| `Tracelet.getPrivacyZones()` | `List<PrivacyZone>` | List all registered zones |

---

## Persistence & Sync

| Method | Returns | Description |
|---|---|---|
| `Tracelet.getLocations()` | `List<Location>` | Stored locations |
| `Tracelet.getCount()` | `int` | Location count |
| `Tracelet.destroyLocations()` | `bool` | Delete all |
| `Tracelet.destroyLocation(uuid)` | `bool` | Delete one |
| `Tracelet.insertLocation(params)` | `String` | Insert custom |
| `Tracelet.sync()` | `List<Location>` | Manual HTTP sync |
| `Tracelet.setDynamicHeaders(headers)` | `bool` | Set dynamic HTTP headers merged at sync time ([details](HTTP-SYNC.md#dynamic-headers)) |
| `Tracelet.setHeadersCallback(callback)` | `void` | Register foreground callback for on-demand header refresh ([details](HTTP-SYNC.md#dynamic-headers)) |
| `Tracelet.refreshHeaders()` | `bool` | Force-invoke the headers callback and send to native |
| `Tracelet.setRouteContext(context)` | `bool` | Attach route context to subsequent locations ([details](HTTP-SYNC.md#route-context)) |
| `Tracelet.clearRouteContext()` | `bool` | Remove route context from subsequent locations |
| `Tracelet.setSyncBodyBuilder(builder)` | `void` | Register custom sync body builder for foreground sync ([details](HTTP-SYNC.md#custom-sync-body-builder)) |
| `Tracelet.registerHeadlessSyncBodyBuilder(cb)` | `bool` | Register headless sync body builder for background sync ([details](HTTP-SYNC.md#custom-sync-body-builder)) |
| `Tracelet.registerHeadlessHeadersCallback(cb)` | `bool` | Register headless headers callback for background token recovery ([details](HTTP-SYNC.md#headless-background-callbacks)) |

---

## Audit Trail

| Method | Returns | Description |
|---|---|---|
| `Tracelet.verifyAuditTrail()` | `AuditVerification` | Verify tamper-proof hash chain integrity ([details](AUDIT-TRAIL.md)) |
| `Tracelet.getAuditProof(uuid)` | `AuditProof?` | Get SHA-256 hash proof for a single location |

---

## Compliance

| Method | Returns | Description |
|---|---|---|
| `Tracelet.generateComplianceReport()` | `ComplianceReport` | Auto-generated GDPR/CCPA compliance report ([details](COMPLIANCE-REPORT.md)) |

---

## Database Encryption

| Method | Returns | Description |
|---|---|---|
| `Tracelet.isDatabaseEncrypted()` | `bool` | Check if database is encrypted at rest ([details](DATABASE-ENCRYPTION.md)) |
| `Tracelet.encryptDatabase()` | `bool` | Encrypt the local database (migration + mark) |

---

## Device Attestation

| Method | Returns | Description |
|---|---|---|
| `Tracelet.getAttestationToken()` | `AttestationToken?` | Get platform attestation token ([details](DEVICE-ATTESTATION.md)) |

---

## Dead Reckoning

| Method | Returns | Description |
|---|---|---|
| `Tracelet.getDeadReckoningState()` | `Map<String, Object?>?` | Query IMU dead reckoning state ([details](DEAD-RECKONING.md)) |

---

## Permissions & Settings

| Method | Returns | Description |
|---|---|---|
| `Tracelet.getPermissionStatus()` | `int` | Current location status (no dialog) |
| `Tracelet.requestPermission()` | `int` | Request location + wait for result |
| `Tracelet.getNotificationPermissionStatus()` | `int` | Notification status (Android 13+) |
| `Tracelet.requestNotificationPermission()` | `int` | Request notification (Android 13+) |
| `Tracelet.getMotionPermissionStatus()` | `int` | Motion/activity recognition status |
| `Tracelet.requestMotionPermission()` | `int` | Request motion permission |
| `Tracelet.openAppSettings()` | `bool` | Open app settings |
| `Tracelet.openLocationSettings()` | `bool` | Open location settings |
| `Tracelet.openBatterySettings()` | `bool` | Open battery optimization (Android) |
| `Tracelet.requestTemporaryFullAccuracy(purpose)` | `int` | Temp full accuracy (iOS 14+) |
| `Tracelet.isPowerSaveMode` | `bool` | Battery saver active? |
| `Tracelet.hasBackgroundPermission` | `bool` | Has "Always" location authorization? |
| `Tracelet.isIgnoringBatteryOptimizations()` | `bool` | Battery exempt? (Android) |
| `Tracelet.canScheduleExactAlarms()` | `bool` | Has `SCHEDULE_EXACT_ALARM` permission? (Android 12+) |
| `Tracelet.openExactAlarmSettings()` | `bool` | Open exact alarms settings page (Android 12+) |
| `Tracelet.getProviderState()` | `ProviderChangeEvent` | Current GPS/network provider state |
| `Tracelet.requestSettings(action)` | `bool` | Open system settings by action string |
| `Tracelet.showSettings(action)` | `bool` | Alias for `requestSettings()` |

---

## Utility

| Method | Returns | Description |
|---|---|---|
| `Tracelet.getSensors()` | `Sensors` | Device sensor availability |
| `Tracelet.getDeviceInfo()` | `DeviceInfo` | Device model, manufacturer, OS |
| `Tracelet.getHealth()` | `HealthCheck` | Single-call diagnostic snapshot ([details](HEALTH-CHECK.md)) |
| `Tracelet.playSound(name)` | `bool` | Play debug sound |
| `Tracelet.getLog()` | `String` | Get log content |
| `Tracelet.destroyLog()` | `bool` | Clear log |
| `Tracelet.emailLog(email)` | `bool` | Email log export |
| `Tracelet.log(level, message)` | `bool` | Write custom log entry |
| `Tracelet.registerHeadlessTask(callback)` | `void` | Register headless Dart callback |
| `Tracelet.getSettingsHealth()` | `Map<String, Object?>` | OEM-specific device settings health ([details](OEM-COMPATIBILITY.md)) |
| `Tracelet.openOemSettings(label)` | `bool` | Open OEM-specific settings page (Android) |
| `Tracelet.startBackgroundTask()` | `int` | Start a long-running background task, returns task ID |
| `Tracelet.stopBackgroundTask(taskId)` | `int` | Stop a background task by ID |
| `Tracelet.startSchedule()` | `State` | Start time-based schedule |
| `Tracelet.stopSchedule()` | `State` | Stop time-based schedule |
| `Tracelet.removeListeners()` | `void` | Cancel all active event subscriptions |

---

## Events

| Subscription | Event Type | Fires when |
|---|---|---|
| `Tracelet.onLocation(cb)` | `Location` | Every recorded location |
| `Tracelet.onMotionChange(cb)` | `Location` | Moving ↔ stationary |
| `Tracelet.onActivityChange(cb)` | `ActivityChangeEvent` | Activity changes |
| `Tracelet.onProviderChange(cb)` | `ProviderChangeEvent` | GPS/permission changes |
| `Tracelet.onGeofence(cb)` | `GeofenceEvent` | Geofence transitions |
| `Tracelet.onGeofencesChange(cb)` | `GeofencesChangeEvent` | Monitored set changes |
| `Tracelet.onHeartbeat(cb)` | `HeartbeatEvent` | Heartbeat interval |
| `Tracelet.onHttp(cb)` | `HttpEvent` | HTTP sync result (includes retry metadata) |
| `Tracelet.onSchedule(cb)` | `State` | Schedule start/stop |
| `Tracelet.onConnectivityChange(cb)` | `ConnectivityChangeEvent` | Online/offline |
| `Tracelet.onPowerSaveChange(cb)` | `bool` | Battery saver toggle |
| `Tracelet.onEnabledChange(cb)` | `bool` | Tracking on/off |
| `Tracelet.onNotificationAction(cb)` | `String` | Notification tap (Android) |
| `Tracelet.onAuthorization(cb)` | `AuthorizationEvent` | Auth token refresh |
| `Tracelet.onTrip(cb)` | `TripEvent` | Trip start/end with waypoints, distance, duration |
| `Tracelet.onBudgetAdjustment(cb)` | `BudgetAdjustmentEvent` | Battery budget engine auto-adjusted tracking params |

---

## Key Event Types

### Location

| Property | Type | Description |
|---|---|---|
| `coords` | `Coords` | Geographic coordinates and accuracy metrics |
| `timestamp` | `String` | ISO 8601 timestamp |
| `isMoving` | `bool` | Whether device was moving |
| `uuid` | `String` | Unique identifier |
| `odometer` | `double` | Distance traveled (meters) |
| `locationSource` | `String` | Fix source: `'gps'`, `'wifi'`, `'cell'`, `'network'`, or `'unknown'` |
| `isMock` | `bool` | Whether location was spoofed |
| `mockHeuristics` | `MockHeuristics?` | Detailed spoofing signals (when heuristic detection enabled) |
| `activity` | `LocationActivity` | Detected activity type + confidence |
| `battery` | `LocationBattery` | Battery level + charging state |
| `event` | `String?` | Trigger event (`'motionchange'`, `'heartbeat'`, `'periodic'`, etc.) |
| `extras` | `Map<String, Object?>` | Arbitrary app data |

#### locationSource

Classifies how each fix was obtained:

| Value | Typical accuracy | Source |
|---|---|---|
| `gps` | ≤ 50m | GPS/GNSS satellite |
| `wifi` | 50–200m | Wi-Fi access point positioning |
| `cell` | > 200m | Cell tower triangulation |
| `network` | varies | Android network provider (Wi-Fi or cell) |
| `unknown` | — | Source could not be determined |

On **Android**, classification uses the provider name from `FusedLocationProviderClient` combined with accuracy. On **iOS**, classification is based on `horizontalAccuracy` alone (iOS does not expose provider names).

### ProviderChangeEvent

| Property | Type | Description |
|---|---|---|
| `enabled` | `bool` | Location services globally enabled |
| `status` | `AuthorizationStatus` | Current authorization status |
| `gps` | `bool` | GPS provider enabled (Android) |
| `network` | `bool` | Network provider enabled (Android) |
| `accuracyAuthorization` | `AccuracyAuthorization` | iOS 14+ precise location auth |
| `mockLocationsDetected` | `bool` | First mock location encountered |
| `gpsFallback` | `bool` | Auto-downgraded to Wi-Fi/cell because GPS is off (Android) |

#### GPS-Off Auto-Fallback (Android)

When GPS hardware is disabled (user toggles GPS off in system settings) and the configured accuracy is `high` (GPS), the engine automatically downgrades to `PRIORITY_BALANCED_POWER_ACCURACY` to receive Wi-Fi/cell tower fixes instead of timing out. When GPS is re-enabled, the original priority is restored automatically.

The `gpsFallback` field in `ProviderChangeEvent` signals this state:
- `true` — engine is using network positioning as fallback
- `false` — engine is using the configured accuracy (normal operation)

### HttpEvent

| Property | Type | Description |
|---|---|---|
| `success` | `bool` | Whether the request succeeded (2xx) |
| `status` | `int` | HTTP status code |
| `responseText` | `String` | Raw response body |
| `isRetry` | `bool` | `true` if this was a retry attempt |
| `retryCount` | `int` | Current retry attempt number (0 = first try) |

> See [HTTP Sync Guide](HTTP-SYNC.md) for retry strategy details.

### HealthCheck

| Property | Type | Description |
|---|---|---|
| `isTracking` | `bool` | Whether tracking is currently active |
| `trackingMode` | `TrackingMode` | Current tracking mode (`location`, `geofences`, or `periodic`) |
| `locationPermission` | `int` | Location permission status |
| `locationServicesEnabled` | `bool` | Location services on/off |
| `isPowerSaveMode` | `bool` | Battery saver active |
| `warnings` | `List<HealthWarning>` | Auto-detected issues |
| `isHealthy` | `bool` | `true` when no warnings |
| `warningCount` | `int` | Number of warnings |
| `hasBackgroundPermission` | `bool` | Has "Always" + services enabled |

> See [Health Check Guide](HEALTH-CHECK.md) for full field list and warning types.

### TripEvent

| Property | Type | Description |
|---|---|---|
| `isMoving` | `bool` | Whether device just started (`true`) or stopped (`false`) moving |
| `distance` | `double` | Total trip distance in meters |
| `duration` | `int` | Trip duration in seconds |
| `startLocation` | `Location` | Location where trip started |
| `stopLocation` | `Location` | Location where trip ended |
| `waypoints` | `List<Location>` | All recorded waypoints during trip |
| `averageSpeed` | `double` | Average speed in m/s |

> See [Trip Detection Guide](TRIP-DETECTION.md) for full usage details.

### BudgetAdjustmentEvent

| Property | Type | Description |
|---|---|---|
| `currentBatteryDrain` | `double` | Measured battery drain (%/hr) |
| `targetBudget` | `double` | Configured target budget (%/hr) |
| `newDistanceFilter` | `double` | Adjusted distance filter in meters |
| `newDesiredAccuracy` | `String` | Adjusted accuracy level name |
| `newPeriodicInterval` | `int?` | Adjusted periodic interval in seconds (null if not periodic mode) |

> See [Battery Budget Guide](BATTERY-BUDGET.md) for target values and tuning.

### ComplianceReport

| Property | Type | Description |
|---|---|---|
| `generatedAt` | `DateTime` | Report generation timestamp |
| `totalLocationsStored` | `int` | Locations in local database |
| `totalLocationsSynced` | `int` | Approximate locations synced to server |
| `oldestRecord` | `String?` | Timestamp of oldest record |
| `newestRecord` | `String?` | Timestamp of newest record |
| `maxDaysToPersist` | `int` | Retention policy — days (-1 = unlimited) |
| `maxRecordsToPersist` | `int` | Retention policy — records (-1 = unlimited) |
| `databaseEncrypted` | `bool` | Database encrypted at rest |
| `activePrivacyZones` | `int` | Number of active privacy zones |
| `privacyZoneIdentifiers` | `List<String>` | Identifiers of all active zones |
| `httpSyncUrl` | `String?` | Server URL (null if disabled) |
| `autoSyncEnabled` | `bool` | Auto-sync on new location |
| `auditTrailEnabled` | `bool` | Hash chain enabled |
| `auditTrailValid` | `bool?` | Chain validation status |
| `locationPermissionStatus` | `int` | Location permission code |
| `motionPermissionStatus` | `int` | Motion permission code |
| `trackingEnabled` | `bool` | Tracking currently active |
| `trackingMode` | `String` | Current mode |

Export methods: `toJson()` → structured JSON, `toMarkdown()` → human-readable report.

> See [Compliance Report Guide](COMPLIANCE-REPORT.md) for GDPR mapping and usage.

### AuditVerification

| Property | Type | Description |
|---|---|---|
| `isValid` | `bool` | Whether the entire hash chain is intact |
| `totalRecords` | `int` | Total records verified |
| `verifiedRecords` | `int` | Number of records successfully verified |
| `brokenAtIndex` | `int?` | Index where chain was broken (null if valid) |
| `brokenAtUuid` | `String?` | UUID of the broken record |
| `error` | `String?` | Error message if verification failed |

### AuditProof

| Property | Type | Description |
|---|---|---|
| `uuid` | `String` | Location record UUID |
| `hash` | `String` | SHA-256 hash of this record |
| `previousHash` | `String` | Hash of preceding record in chain |
| `chainIndex` | `int` | Position in the audit chain |
| `timestamp` | `String` | Record timestamp |

> See [Audit Trail Guide](AUDIT-TRAIL.md) for chain verification details.

### PrivacyZone

| Property | Type | Description |
|---|---|---|
| `identifier` | `String` | Unique zone identifier |
| `latitude` | `double` | Zone center latitude |
| `longitude` | `double` | Zone center longitude |
| `radius` | `double` | Zone radius in meters |
| `action` | `PrivacyZoneAction` | `exclude`, `degrade`, or `eventOnly` |
| `degradedAccuracyMeters` | `double?` | Degraded accuracy when action is `degrade` |

> See [Privacy Zones Guide](PRIVACY-ZONES.md) for zone actions and usage.

### AttestationToken

| Property | Type | Description |
|---|---|---|
| `token` | `String` | Platform-specific attestation token string |
| `timestamp` | `DateTime` | When the token was generated |
| `provider` | `String` | Provider: `play_integrity`, `app_attest`, or `device_check` |
| `verified` | `bool?` | Server verification result (`null` if not yet verified) |

> See [Device Attestation Guide](DEVICE-ATTESTATION.md) for platform details and server verification.

### startPeriodic()

Starts **periodic interval tracking**. Instead of continuously streaming GPS coordinates, the plugin wakes at a configurable interval, takes a single location fix, persists it, dispatches it to your Dart callback, then immediately turns off the GPS radio.

**Result:** The GPS icon (Android) / blue location arrow (iOS) only appears for ~5–10 seconds per fix instead of permanently.

**Android scheduling strategies** (mutually exclusive):

| Strategy | Config | Notification? | Min Interval | Timing Precision |
|---|---|---|---|---|
| WorkManager (default) | Both `false` | No | 15 min | Approximate (system-batched) |
| Exact Alarms | `periodicUseExactAlarms: true` | No | Any | Exact (AlarmManager) |
| Foreground Service | `periodicUseForegroundService: true` | Yes | Any | Exact (Handler timer) |

```dart
// 1. Configure (optional — defaults to 15-min interval, medium accuracy)
await Tracelet.ready(Config(
  geo: GeoConfig(
    periodicLocationInterval: 1800,        // 30 minutes
    periodicDesiredAccuracy: DesiredAccuracy.medium,
    periodicUseForegroundService: false,    // Android: WorkManager (no notification)
    periodicUseExactAlarms: false,          // Android: inexact alarms (battery-friendly)
  ),
));

// 2. Start periodic tracking
final state = await Tracelet.startPeriodic();

// 3. State reflects the new mode
print(state.trackingMode); // TrackingMode.periodic

// 4. Stop with the regular stop()
await Tracelet.stop();
```

> **Exact Alarms:** `periodicUseExactAlarms: true` uses `AlarmManager.setExactAndAllowWhileIdle()` on Android. Requires `SCHEDULE_EXACT_ALARM` permission (granted by default on Android 12–12L, must be manually enabled in Settings on Android 13+). Falls back silently to inexact alarms if not granted.

> See [Background Tracking Guide](BACKGROUND-TRACKING.md#periodic-mode) and [Configuration Guide](CONFIGURATION.md) for full details.

---

## Algorithm Classes

The following classes are exported from `package:tracelet/tracelet.dart` and
available for direct use:

| Class | Purpose | Guide |
|---|---|---|
| `CarbonEstimator` | CO₂ emission tracking per trip/transport mode | [Carbon Estimator](CARBON-ESTIMATOR.md) |
| `BatteryBudgetEngine` | Auto-adjust tracking to stay within battery budget | [Battery Budget](BATTERY-BUDGET.md) |
| `DeltaEncoder` | Location delta compression for HTTP sync | [Delta Encoding](DELTA-ENCODING.md) |
| `KalmanLocationFilter` | GPS coordinate smoothing (Extended Kalman Filter) | [Kalman Filter](KALMAN-FILTER.md) |
| `TripManager` | Trip detection and waypoint collection | [Trip Detection](TRIP-DETECTION.md) |
| `RTree` | R-Tree spatial indexing for geofence proximity queries | — |
| `GeoUtils` | Geographic utilities (Haversine distance, bearing) | — |
| `LocationProcessor` | Distance/accuracy/speed filtering, adaptive sampling | [Adaptive Sampling](ADAPTIVE-SAMPLING.md) |
| `GeofenceEvaluator` | Geofence containment checks (circles + polygons) | [Polygon Geofences](POLYGON-GEOFENCES.md) |
| `ScheduleParser` | Parse and evaluate time-based schedule rules | — |
