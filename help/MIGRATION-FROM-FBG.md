# 🚀 Migration Guide: `flutter_background_geolocation` → Tracelet

Switching from `flutter_background_geolocation` to **Tracelet**? Great choice! Tracelet is a fully open-source (Apache 2.0) alternative with a 1:1 compatible API — plus extras like Kalman filtering, mock detection, privacy zones, and more. No license keys, no proprietary SDKs, full source code.

> 💡 Grab the latest version from [pub.dev/packages/tracelet](https://pub.dev/packages/tracelet). This guide always reflects the current release.

---

## ⚡ 3-Step Speed Run

Seriously, it's this fast.

**Step 1 — Swap the dependency:**

```yaml
# Before
dependencies:
  flutter_background_geolocation: ^5.x.x

# After ✨
dependencies:
  tracelet:    # grab latest from https://pub.dev/packages/tracelet
```

**Step 2 — Update imports:**

```dart
// Before
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;

// After — short & sweet ✅
import 'package:tracelet/tracelet.dart' as tl;
```

**Step 3 — Find & replace the class name:**

```dart
// Before
bg.BackgroundGeolocation.ready(bg.Config(...));

// After
tl.Tracelet.ready(tl.Config(...));
```

**That's literally it.** Every method, every event, every callback — 1:1 compatible. The rest of this guide is just the cheat sheet for the details.

---

## 🏗️ Config: From Flat to Structured

The previous plugin uses a single flat `Config()` with all fields at one level. Tracelet organizes them into logical sections — making large configs much easier to read and maintain.

```dart
// Before — flat config
bg.Config(
  desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
  distanceFilter: 10.0,
  stopOnTerminate: false,
  startOnBoot: true,
  stopTimeout: 5,
  url: 'https://api.example.com/locations',
  batchSync: true,
  autoSync: true,
  headers: {'Authorization': 'Bearer $token'},
  heartbeatInterval: 60,
  notification: bg.Notification(title: 'Tracking', text: 'Active'),
  debug: true,
  logLevel: bg.Config.LOG_LEVEL_VERBOSE,
);

// After — organized by section 🏠
tl.Config(
  geo: tl.GeoConfig(
    desiredAccuracy: tl.DesiredAccuracy.high,   // typed enums!
    distanceFilter: 10.0,
  ),
  app: tl.AppConfig(
    stopOnTerminate: false,
    startOnBoot: true,
    heartbeatInterval: 60,
    foregroundService: tl.ForegroundServiceConfig(
      notificationTitle: 'Tracking',
      notificationText: 'Active',
    ),
  ),
  motion: tl.MotionConfig(
    stopTimeout: 5,
  ),
  http: tl.HttpConfig(
    url: 'https://api.example.com/locations',
    batchSync: true,
    autoSync: true,
    headers: {'Authorization': 'Bearer $token'},
  ),
  logger: tl.LoggerConfig(
    debug: true,
    logLevel: tl.LogLevel.verbose,   // readable enum instead of int constants
  ),
);
```

**The config sections at a glance:**

- **`geo`** → `GeoConfig` — Accuracy, distance filter, elasticity, periodic mode, Kalman filter, mock detection
- **`app`** → `AppConfig` — Lifecycle, heartbeat, schedule, foreground service notification
- **`motion`** → `MotionConfig` — Stop timeout, activity recognition, accelerometer-only mode
- **`http`** → `HttpConfig` — Sync URL, headers, batching, retry backoff, Wi-Fi-only mode
- **`logger`** → `LoggerConfig` — Log level, max days, debug sounds
- **`geofence`** → `GeofenceConfig` — Proximity radius, initial trigger, knock-out mode
- **`persistence`** → `PersistenceConfig` — Persist mode, max days/records, templates
- **`audit`** → `AuditConfig` — 🆕 SHA-256 hash chain — because tamper-proof matters
- **`privacyZone`** → `PrivacyZoneConfig` — 🆕 Privacy zone engine — GDPR's best friend

---

## 🗺️ The Big Config Cheat Sheet

Don't worry, every single field has a 1:1 mapping. Here's your Rosetta Stone.

### Location & Tracking → `GeoConfig`

```
Before                              → Tracelet
─────────────────────────────────────────────────────────────
desiredAccuracy (int: -2…100)       → geo.desiredAccuracy (DesiredAccuracy enum)
                                      .high / .medium / .low / .veryLow / .passive
distanceFilter                      → geo.distanceFilter (default 10m)
locationUpdateInterval              → geo.locationUpdateInterval (Android, 1000ms)
fastestLocationUpdateInterval       → geo.fastestLocationUpdateInterval (Android, 500ms)
stationaryRadius                    → geo.stationaryRadius (default 25m)
locationTimeout                     → geo.locationTimeout (default 60s)
activityType                        → geo.activityType (LocationActivityType enum, iOS)
disableElasticity                   → geo.disableElasticity
elasticityMultiplier                → geo.elasticityMultiplier (default 1.0)
stopAfterElapsedMinutes             → geo.stopAfterElapsedMinutes (-1 = disabled)
deferTime                           → geo.deferTime (Android)
allowIdenticalLocations             → geo.allowIdenticalLocations (Android)
useSignificantChangesOnly           → geo.useSignificantChangesOnly (iOS)
showsBackgroundLocationIndicator    → geo.showsBackgroundLocationIndicator (iOS)
pausesLocationUpdatesAutomatically  → geo.pausesLocationUpdatesAutomatically (iOS)
locationAuthorizationRequest        → geo.locationAuthorizationRequest (default LocationAuthorizationRequest.always)
disableLocationAuthorizationAlert   → geo.disableLocationAuthorizationAlert
enableTimestampMeta                 → geo.enableTimestampMeta
geofenceModeHighAccuracy            → geo.geofenceModeHighAccuracy (Android)
maxMonitoredGeofences               → geo.maxMonitoredGeofences (-1 = platform default)
```

**🆕 Tracelet-exclusive GeoConfig fields:**

- `geo.enableAdaptiveMode` — Adapts distance filter by activity + battery + speed
- `geo.periodicLocationInterval` — Default 900s (15 min)
- `geo.periodicDesiredAccuracy` — Default `.medium`
- `geo.periodicUseForegroundService` — Android only
- `geo.periodicUseExactAlarms` — Android only
- `geo.filter` (`LocationFilter`) — Kalman, mock detection, accuracy thresholds

### 🧹 Location Filter → `LocationFilter` (Tracelet-exclusive!)

- 🆕 **`filter.policy`** — `LocationFilterPolicy.adjust` / `.ignore` / `.discard`
- 🆕 **`filter.useKalmanFilter`** — 4-state Extended Kalman Filter — smooth out GPS noise like a pro
- 🆕 **`filter.mockDetectionLevel`** — `.disabled` / `.basic` / `.heuristic` — catch those spoofed locations
- 🆕 **`filter.rejectMockLocations`** — Auto-reject mock locations
- 🆕 **`filter.maxImpliedSpeed`** — Spike filter — "no, the user did NOT teleport"
- 🆕 **`filter.trackingAccuracyThreshold`** — Min accuracy to accept
- 🆕 **`filter.odometerAccuracyThreshold`** — Min accuracy for odometer updates

### Motion Detection → `MotionConfig`

```
Before                                → Tracelet
─────────────────────────────────────────────────────────────
stopTimeout                            → motion.stopTimeout (default 5 min)
motionTriggerDelay                     → motion.motionTriggerDelay
disableMotionActivityUpdates           → motion.disableMotionActivityUpdates
                                         (set true for accelerometer-only, no permission!)
isMoving                               → motion.isMoving (initial state)
activityRecognitionInterval            → motion.activityRecognitionInterval (10000ms)
minimumActivityRecognitionConfidence   → motion.minimumActivityRecognitionConfidence (75)
disableStopDetection                   → motion.disableStopDetection
stopDetectionDelay                     → motion.stopDetectionDelay
stopOnStationary                       → motion.stopOnStationary
triggerActivities                      → motion.triggerActivities (comma-separated)
```

**🆕 Tracelet-exclusive MotionConfig fields:**

- `motion.shakeThreshold` — Accelerometer-only tuning (default 2.5)
- `motion.stillThreshold` — Accelerometer-only tuning (default 0.4)
- `motion.stillSampleCount` — Accelerometer-only tuning (default 25)

### Application → `AppConfig`

```
Before                   → Tracelet
─────────────────────────────────────────────────────────────
stopOnTerminate          → app.stopOnTerminate (default true)
startOnBoot              → app.startOnBoot (default false)
heartbeatInterval        → app.heartbeatInterval (default 60s)
schedule                 → app.schedule (cron-like expressions)
scheduleUseAlarmManager  → app.scheduleUseAlarmManager (Android)
preventSuspend           → app.preventSuspend (iOS)
notification             → app.foregroundService (see below)
```

### 🔔 Foreground Service Notification (Android)

```
Before (Notification)     → Tracelet (ForegroundServiceConfig)
─────────────────────────────────────────────────────────────
title                     → notificationTitle
text                      → notificationText
color                     → notificationColor
smallIcon                 → notificationSmallIcon
largeIcon                 → notificationLargeIcon
priority                  → notificationPriority
channelName               → channelName
channelId                 → channelId
sticky                    → notificationOngoing
actions                   → actions
enabled                   → enabled
```

### HTTP Sync → `HttpConfig`

```
Before                    → Tracelet
─────────────────────────────────────────────────────────────
url                       → http.url (null = sync disabled)
method                    → http.method (HttpMethod.post / .put)
headers                   → http.headers
httpRootProperty          → http.httpRootProperty (default 'location')
batchSync                 → http.batchSync
maxBatchSize              → http.maxBatchSize
autoSync                  → http.autoSync
autoSyncThreshold         → http.autoSyncThreshold
httpTimeout               → http.httpTimeout (default 60000ms)
params                    → http.params
extras                    → http.extras
locationsOrderDirection   → http.locationsOrderDirection (LocationOrder enum)
```

**🆕 Tracelet-exclusive HttpConfig fields:**

- `http.disableAutoSyncOnCellular` — Wi-Fi-only sync — save that data plan!
- `http.maxRetries` — Default 10, with exponential backoff + jitter
- `http.retryBackoffBase` — Default 1000ms
- `http.retryBackoffCap` — Default 300000ms (5 min)

### Geofencing → `GeofenceConfig`

```
Before                        → Tracelet
─────────────────────────────────────────────────────────────
geofenceProximityRadius       → geofence.geofenceProximityRadius (default 1000m)
geofenceInitialTriggerEntry   → geofence.geofenceInitialTriggerEntry (default true)
```

- 🆕 **`geofence.geofenceModeKnockOut`** — Auto-remove geofence after first EXIT — one and done!

### Persistence → `PersistenceConfig`

```
Before                        → Tracelet
─────────────────────────────────────────────────────────────
persistMode                   → persistence.persistMode (.all / .location / .geofence / .none)
maxDaysToPersist              → persistence.maxDaysToPersist (-1 = forever)
maxRecordsToPersist           → persistence.maxRecordsToPersist (-1 = unlimited)
locationTemplate              → persistence.locationTemplate (Mustache-style)
geofenceTemplate              → persistence.geofenceTemplate (Mustache-style)
disableProviderChangeRecord   → persistence.disableProviderChangeRecord
extras                        → persistence.extras
```

### Logging → `LoggerConfig`

```
Before                 → Tracelet
─────────────────────────────────────────────────────────────
logLevel (int const)   → logger.logLevel (.verbose / .debug / .info / .warning / .error)
logMaxDays             → logger.logMaxDays (default 3)
debug                  → logger.debug (alert sounds — fun at demos, terrifying at 3 AM)
```

### 🔐 Audit Trail → `AuditConfig` (Tracelet-exclusive)

- **`audit.enabled`** — `false` by default. SHA-256 hash chain on every location — tamper = busted
- **`audit.hashAlgorithm`** — `'SHA-256'`
- **`audit.includeExtrasInHash`** — `false` by default

### 🛡️ Privacy Zones → `PrivacyZoneConfig` (Tracelet-exclusive)

- **`privacyZone.enabled`** — `false` by default. Enable privacy zone engine.

### 🎯 Accuracy Constants — Typed Enums!

```
Before (int constants)                    → Tracelet (typed enum)
─────────────────────────────────────────────────────────────
Config.DESIRED_ACCURACY_NAVIGATION        → DesiredAccuracy.high
Config.DESIRED_ACCURACY_HIGH              → DesiredAccuracy.high
Config.DESIRED_ACCURACY_MEDIUM            → DesiredAccuracy.medium
Config.DESIRED_ACCURACY_LOW               → DesiredAccuracy.low
Config.DESIRED_ACCURACY_VERY_LOW          → DesiredAccuracy.veryLow
Config.DESIRED_ACCURACY_LOWEST            → DesiredAccuracy.passive
```

---

## 📡 Events — Same Names, Less Typing

All 14 event streams map 1:1. Just swap the prefix:

```
Before                     → Tracelet                     Callback Type
─────────────────────────────────────────────────────────────────────────
onLocation(cb)             → onLocation(cb)               Location
onMotionChange(cb)         → onMotionChange(cb)           Location
onActivityChange(cb)       → onActivityChange(cb)         ActivityChangeEvent
onProviderChange(cb)       → onProviderChange(cb)         ProviderChangeEvent
onGeofence(cb)             → onGeofence(cb)               GeofenceEvent
onGeofencesChange(cb)      → onGeofencesChange(cb)        GeofencesChangeEvent
onHeartbeat(cb)            → onHeartbeat(cb)              HeartbeatEvent
onHttp(cb)                 → onHttp(cb)                   HttpEvent
onSchedule(cb)             → onSchedule(cb)               State
onPowerSaveChange(cb)      → onPowerSaveChange(cb)        bool
onConnectivityChange(cb)   → onConnectivityChange(cb)     ConnectivityChangeEvent
onEnabledChange(cb)        → onEnabledChange(cb)          bool
onNotificationAction(cb)   → onNotificationAction(cb)     String
onAuthorization(cb)        → onAuthorization(cb)          AuthorizationEvent
N/A                        → 🆕 onTrip(cb)                TripEvent (auto-detected trips!)
removeListeners()          → removeListeners()            Cancels all subscriptions
```

```dart
// Before — so many characters...
bg.BackgroundGeolocation.onLocation((bg.Location location) {
  print('[location] $location');
});

// After — ahh, much better
tl.Tracelet.onLocation((tl.Location location) {
  print('[location] $location');
});
```

---

## 🔧 Methods — The Complete Mapping

### Lifecycle

```
Before                                → Tracelet
─────────────────────────────────────────────────────────────
bg.BackgroundGeolocation.ready(cfg)   → tl.Tracelet.ready(cfg)
bg.BackgroundGeolocation.start()      → tl.Tracelet.start()
bg.BackgroundGeolocation.stop()       → tl.Tracelet.stop()
bg.BackgroundGeolocation.startGeofences()  → tl.Tracelet.startGeofences()
N/A                                   → 🆕 tl.Tracelet.startPeriodic()
bg.BackgroundGeolocation.getState()   → tl.Tracelet.getState()
bg.BackgroundGeolocation.setConfig()  → tl.Tracelet.setConfig()
bg.BackgroundGeolocation.reset()      → tl.Tracelet.reset()
N/A                                   → 🆕 tl.Tracelet.getHealth()
```

### Location

```
Before                     → Tracelet
─────────────────────────────────────────────────────────────
getCurrentPosition(...)    → getCurrentPosition(...)
                             same params: desiredAccuracy, timeout,
                             maximumAge, persist, samples, extras
N/A                        → 🆕 getLastKnownLocation() — zero battery cost!
watchPosition(cb, ...)     → watchPosition(cb, ...) — returns watchId
stopWatchPosition(id)      → stopWatchPosition(id)
changePace(isMoving)       → changePace(isMoving)
getOdometer()              → getOdometer()
setOdometer(value)         → setOdometer(value)
resetOdometer()            → setOdometer(0) — one less method to remember
```

### Geofencing

```
Before              → Tracelet
─────────────────────────────────────────────────────────────
addGeofence(g)      → addGeofence(g)
addGeofences(list)  → addGeofences(list)
removeGeofence(id)  → removeGeofence(id)
removeGeofences()   → removeGeofences()
getGeofences()      → getGeofences()
N/A                 → 🆕 getGeofence(id) — get one without fetching all
N/A                 → 🆕 geofenceExists(id) — quick existence check
```

### Persistence & Sync

```
Before                   → Tracelet
─────────────────────────────────────────────────────────────
getLocations()           → getLocations([SQLQuery?]) — optional filtering!
getCount()               → getCount()
destroyLocations()       → destroyLocations()
destroyLocation(uuid)    → destroyLocation(uuid)
insertLocation(params)   → insertLocation(params) — returns UUID
sync()                   → sync()
```

### Permissions — We've Got Helpers for Days

```
Before               → Tracelet
─────────────────────────────────────────────────────────────
requestPermission()  → requestPermission()
N/A                  → 🆕 getPermissionStatus()
N/A                  → 🆕 hasBackgroundPermission (getter)
N/A                  → 🆕 getNotificationPermissionStatus()
N/A                  → 🆕 requestNotificationPermission()
N/A                  → 🆕 getMotionPermissionStatus()
N/A                  → 🆕 requestMotionPermission()
N/A                  → 🆕 requestTemporaryFullAccuracy(purpose) — iOS 14+
N/A                  → 🆕 canScheduleExactAlarms() — Android 12+
N/A                  → 🆕 openExactAlarmSettings()
N/A                  → 🆕 openAppSettings()
N/A                  → 🆕 openLocationSettings()
N/A                  → 🆕 openBatterySettings()
N/A                  → 🆕 isIgnoringBatteryOptimizations()
```

### Logging

```
Before              → Tracelet
─────────────────────────────────────────────────────────────
getLog()            → getLog([SQLQuery?]) — optional filtering
destroyLog()        → destroyLog()
emailLog(email)     → emailLog(email)
log(level, msg)     → log(level, msg)
```

### Scheduling, Background Tasks & Headless

```
Before                     → Tracelet
─────────────────────────────────────────────────────────────
startSchedule()            → startSchedule()
stopSchedule()             → stopSchedule()
startBackgroundTask()      → startBackgroundTask()
stopBackgroundTask(id)     → stopBackgroundTask(id)
registerHeadlessTask(cb)   → registerHeadlessTask(cb)
```

### Utility

```
Before               → Tracelet
─────────────────────────────────────────────────────────────
getProviderState()   → getProviderState()
getSensors()         → getSensors()
getDeviceInfo()      → getDeviceInfo()
playSound(name)      → playSound(name)
isPowerSaveMode      → isPowerSaveMode
N/A                  → 🆕 getSettingsHealth() — detects OEM battery killers
N/A                  → 🆕 openOemSettings(label) — opens OEM settings page
N/A                  → 🆕 requestSettings(action)
N/A                  → 🆕 showSettings(action)
```

### 🔐 Audit Trail (Tracelet-only — enterprise-grade integrity)

- **`verifyAuditTrail()`** — Verify SHA-256 hash chain — was anything tampered with?
- **`getAuditProof(uuid)`** — Cryptographic proof for a specific location record

### 🛡️ Privacy Zones (Tracelet-only — GDPR says thanks)

- **`addPrivacyZone(zone)`** — Add a zone with action: exclude / degrade / event-only
- **`addPrivacyZones(list)`** — Bulk add
- **`removePrivacyZone(id)`** — Remove by identifier
- **`removePrivacyZones()`** — Remove all
- **`getPrivacyZones()`** — List all zones

---

## 🎁 Tracelet-Exclusive Features

Features you get with Tracelet that aren't available in `flutter_background_geolocation`:

- **Periodic mode** — `Tracelet.startPeriodic()` — GPS fix every N minutes via WorkManager. No foreground service, no notification, no battery drain.
- **Kalman filter** — `geo.filter.useKalmanFilter: true` — 4-state EKF smooths GPS noise. Your tracks look professional, not drunk.
- **Adaptive sampling** — `geo.enableAdaptiveMode: true` — Auto-adjusts distance filter based on activity + battery + speed.
- **Mock detection (3-level)** — `geo.filter.mockDetectionLevel` — Catches GPS spoofing via satellite count, realtime drift, and timestamp analysis.
- **Privacy zones** — `addPrivacyZone()` — Exclude, degrade, or limit tracking in sensitive areas. GDPR compliance built in.
- **Audit trail** — `verifyAuditTrail()` — SHA-256 hash chain. Prove your location data hasn't been tampered with.
- **Health check** — `getHealth()` — One call tells you everything: permissions, GPS, battery, OEM issues, 12 auto-warnings.
- **OEM compatibility** — `getSettingsHealth()` — Detects aggressive battery killers on Huawei, Xiaomi, Samsung, OPPO, and tells users how to fix them.
- **Trip detection** — `onTrip(cb)` — Auto-detects trips with distance, duration, waypoints, and average speed.
- **Polygon geofences** — `Geofence(vertices: [...])` — Not just circles. Draw any shape with ray-casting polygon support.
- **Geofence knock-out** — `geofence.geofenceModeKnockOut` — Geofence auto-removes after first EXIT. Perfect for one-time alerts.
- **Geofence lookup** — `getGeofence(id)` — Query a single geofence without loading all of them.
- **Permission helpers** — `openAppSettings()`, `openBatterySettings()` — Direct deeplinks into system settings.
- **Smart retries** — `http.maxRetries` + backoff — Exponential backoff with jitter. Your server will thank you.
- **Wi-Fi-only sync** — `http.disableAutoSyncOnCellular` — Save mobile data, sync only on Wi-Fi.
- **Accelerometer-only motion** — `motion.shakeThreshold` — Detect motion without Activity Recognition permission. Zero permission popup.
- **Web support** — Experimental. Foreground-only, but full Dart API coverage for web apps.

---

## 🤷 Features Not Yet in Tracelet

A few features from the previous plugin aren't available yet. They're either planned or easily worked around:

- **Server-side geofence sync** — *Planned.* For now, fetch from your API and call `addGeofences()`.
- **`locationTemplate` interpolation** — *Declared, not wired.* Transform in `onLocation` callback or use `http.extras`.
- **JWT auto-refresh** — *Declared, not wired.* Set `http.headers` manually; listen to `onAuthorization`.
- **Demo server** — *Not planned.* Use your own backend — any REST endpoint works.
- **License key activation** — 🎉 Not needed! It's open source.

---

## 🛠️ Step-by-Step Migration

### Step 1: Update `pubspec.yaml`

```yaml
dependencies:
  tracelet:    # see https://pub.dev/packages/tracelet for latest version
```

Delete `flutter_background_geolocation` and any license-key packages. You won't need them anymore!

### Step 2: Android Setup

See [INSTALL-ANDROID.md](https://github.com/Ikolvi/Tracelet/blob/main/help/INSTALL-ANDROID.md). Key differences:

- **No license key** — remove any `BackgroundGeolocation.org` config from `AndroidManifest.xml`
- **Permissions** — auto-merged via Gradle, you don't declare them
- **`minSdkVersion`** — API 21+ (same as before)
- **Kotlin** — all native code is Kotlin

### Step 3: iOS Setup

See [INSTALL-IOS.md](https://github.com/Ikolvi/Tracelet/blob/main/help/INSTALL-IOS.md). Key differences:

- **No license key** — remove previous plugin's plist entries
- **Background modes** — same: Location Updates, Background Fetch, Remote Notifications
- **`Info.plist`** — same usage description keys (`NSLocationAlwaysAndWhenInUseUsageDescription`, etc.)
- **`Podfile`** — remove previous plugin's pod sources

### Step 4: Update Config

Transform your flat `Config()` → compound `Config()`. See the **Config: From Flat to Structured** section above.

### Step 5: Update Event Listeners

Find & replace `bg.BackgroundGeolocation.onXxx` → `tl.Tracelet.onXxx`:

```dart
// Before
bg.BackgroundGeolocation.onLocation((bg.Location location) {
  print('[location] $location');
});

// After
tl.Tracelet.onLocation((tl.Location location) {
  print('[location] $location');
});
```

### Step 6: Update Lifecycle Calls

```dart
// Before
bg.BackgroundGeolocation.ready(config).then((bg.State state) {
  if (!state.enabled) bg.BackgroundGeolocation.start();
});

// After
tl.Tracelet.ready(config).then((tl.State state) {
  if (!state.enabled) tl.Tracelet.start();
});
```

### Step 7: Update Headless Task

```dart
// Before
@pragma('vm:entry-point')
void backgroundGeolocationHeadlessTask(bg.HeadlessEvent event) async {
  switch (event.name) {
    case bg.Event.LOCATION:
      bg.Location location = event.event;
      break;
  }
}

void main() {
  bg.BackgroundGeolocation.registerHeadlessTask(backgroundGeolocationHeadlessTask);
  runApp(MyApp());
}

// After — shorter function name is a bonus 😎
@pragma('vm:entry-point')
void headlessTask(tl.HeadlessEvent event) async {
  switch (event.name) {
    case 'location':
      tl.Location location = event.event as tl.Location;
      break;
  }
}

void main() {
  tl.Tracelet.registerHeadlessTask(headlessTask);
  runApp(MyApp());
}
```

---

## 📦 HTTP Payload: snake_case → camelCase

**Heads up, backend devs!** One thing to update on your server.

**`flutter_background_geolocation` sends this:**

```json
{
  "location": {
    "coords": { "latitude": 37.42, "longitude": -122.08, "accuracy": 12.3 },
    "timestamp": "2026-03-06T10:30:00.000Z",
    "is_moving": true,
    "uuid": "abc-123",
    "odometer": 1234.5,
    "activity": { "type": "walking", "confidence": 85 },
    "battery": { "level": 0.72, "is_charging": false }
  }
}
```

**Tracelet sends this:**

```json
{
  "location": {
    "coords": { "latitude": 37.42, "longitude": -122.08, "accuracy": 12.3 },
    "timestamp": "2026-03-06T10:30:00.000Z",
    "isMoving": true,
    "uuid": "abc-123",
    "odometer": 1234.5,
    "isMock": false,
    "activity": { "type": "walking", "confidence": 85 },
    "battery": { "level": 0.72, "isCharging": false }
  }
}
```

**TL;DR**: `is_moving` → `isMoving`, `is_charging` → `isCharging`, plus a new `isMock` field. Update your JSON parsing and you're golden.

---

## 🚨 Common Gotchas

Don't learn these the hard way — we already did:

- **`Config` is now compound** — Wrap fields in `GeoConfig(...)`, `AppConfig(...)`, `HttpConfig(...)`, etc.
- **`desiredAccuracy: -1` doesn't work** — Use `DesiredAccuracy.high` — typed enums, not magic numbers
- **`logLevel: 5` doesn't work** — Use `LogLevel.verbose`
- **Can't find `resetOdometer()`** — It's `setOdometer(0)` now
- **`notification:` property gone** — It's `foregroundService: ForegroundServiceConfig(...)` inside `AppConfig`
- **Backend can't parse `is_moving`** — It's `isMoving` now (camelCase)
- **Still got license key code?** — Delete it — Tracelet doesn't need one
- **`State` properties look different** — Check the [API Reference](https://github.com/Ikolvi/Tracelet/blob/main/help/API.md)
- **`HeadlessEvent.event` type errors** — Cast it: `event.event as tl.Location`

---

## 📚 More Resources

- [API Reference](https://github.com/Ikolvi/Tracelet/blob/main/help/API.md) — every method, every parameter
- [Configuration Guide](https://github.com/Ikolvi/Tracelet/blob/main/help/CONFIGURATION.md) — deep dive into all config options
- [Background Tracking](https://github.com/Ikolvi/Tracelet/blob/main/help/BACKGROUND-TRACKING.md) — how it survives app kills
- [Android Installation](https://github.com/Ikolvi/Tracelet/blob/main/help/INSTALL-ANDROID.md) — Android-specific setup
- [iOS Installation](https://github.com/Ikolvi/Tracelet/blob/main/help/INSTALL-IOS.md) — iOS-specific setup
- [GitHub Issues](https://github.com/Ikolvi/Tracelet/issues) — stuck? we've got you

---

*Welcome to the open-source side. We have cookies. 🍪*
