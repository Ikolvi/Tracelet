<p align="center">
  <img src="https://raw.githubusercontent.com/Ikolvi/Tracelet/main/assets/tracelet-logo.jpeg" alt="Tracelet" width="200"/>
</p>

# Tracelet

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

> **Production-grade background geolocation for Flutter — fully open-source.**

Battery-conscious motion-detection intelligence, geofencing, SQLite persistence, HTTP sync, and headless Dart execution for iOS & Android.

## Features

- **Background location tracking** — continuous GPS with configurable `distanceFilter` and `desiredAccuracy`
- **Motion-detection intelligence** — accelerometer + activity recognition automatically toggle GPS to save battery
- **Geofencing** — circular geofences with enter/exit/dwell events
- **SQLite persistence** — all locations stored locally, queryable, with configurable retention limits
- **HTTP auto-sync** — batch upload with retry, exponential backoff, offline queue, Wi-Fi-only option
- **Headless execution** — run Dart code in response to background events
- **Scheduling** — time-based tracking windows (e.g., "Mon–Fri 9am–5pm") with optional AlarmManager (Android)
- **Start on boot** — resume after device reboot
- **Dart-controlled permissions** — no native dialogs, full Dart-side customization
- **Foreground service toggle** — run with or without a persistent notification (Android)
- **Debug sounds** — audible feedback during development
- **Elasticity control** — speed-based distance filter scaling with disable/multiplier overrides
- **Location filtering** — reject GPS spikes, low-accuracy readings, and speed jumps via `LocationFilter`
- **Auto-stop** — automatically stop tracking after N minutes via `stopAfterElapsedMinutes`
- **Activity recognition tuning** — confidence thresholds, stop-detection delays, stationary behavior
- **Timestamp metadata** — optional extra timing fields on each location record
- **Geofence high-accuracy mode** — full GPS pipeline in geofence-only mode (Android)
- **Prevent suspend (iOS)** — silent audio keep-alive for continuous background execution

## Quick Start

### 1. Add the dependency

```yaml
dependencies:
  tracelet: ^0.1.0
```

### 2. Platform setup

- [Android Setup Guide](../../help/INSTALL-ANDROID.md)
- [iOS Setup Guide](../../help/INSTALL-IOS.md)

### 3. Use the API

```dart
import 'package:tracelet/tracelet.dart' as tl;

// 1. Subscribe to events
tl.Tracelet.onLocation((tl.Location location) {
  print('${location.coords.latitude}, ${location.coords.longitude}');
});

tl.Tracelet.onMotionChange((tl.Location location) {
  print('Moving: ${location.isMoving}');
});

// 2. Initialize
final state = await tl.Tracelet.ready(tl.Config(
  geo: tl.GeoConfig(
    desiredAccuracy: tl.DesiredAccuracy.high,
    distanceFilter: 10.0,
    filter: tl.LocationFilter(
      trackingAccuracyThreshold: 100,
      maxImpliedSpeed: 80,
    ),
  ),
  app: tl.AppConfig(
    stopOnTerminate: false,
    startOnBoot: true,
  ),
  persistence: tl.PersistenceConfig(
    maxDaysToPersist: 7,
    maxRecordsToPersist: 5000,
  ),
  logger: tl.LoggerConfig(
    debug: true,
    logLevel: tl.LogLevel.verbose,
  ),
));

// 3. Start tracking
await tl.Tracelet.start();
```

---

## Permissions

Tracelet does **not** show any native permission dialogs — only the OS
permission prompt is triggered. Permission flow is fully controlled from Dart,
giving you complete freedom to customize the UI, translations, animations,
and behavior.

### Permission API

| Method | Returns | Description |
|---|---|---|
| `Tracelet.getPermissionStatus()` | `Future<int>` | Read-only check — no dialog triggered |
| `Tracelet.requestPermission()` | `Future<int>` | Triggers OS dialog, returns **actual** result |
| `Tracelet.getNotificationPermissionStatus()` | `Future<int>` | Notification permission status (Android 13+) |
| `Tracelet.requestNotificationPermission()` | `Future<int>` | Request POST_NOTIFICATIONS (Android 13+) |
| `Tracelet.openAppSettings()` | `Future<bool>` | Opens the app's system settings page |
| `Tracelet.openLocationSettings()` | `Future<bool>` | Opens device location settings |
| `Tracelet.openBatterySettings()` | `Future<bool>` | Opens battery optimization settings (Android) |

### Authorization Status Codes

| Code | Enum Value | Meaning |
|------|------------|---------|
| `0` | `notDetermined` | Permission has never been requested |
| `1` | `denied` | User denied, but can ask again (Android only) |
| `2` | `whenInUse` | Foreground location granted |
| `3` | `always` | Background location granted |
| `4` | `deniedForever` | Permanently denied — must open Settings |

### Escalation Logic

`requestPermission()` automatically escalates to the next level:

| Current Status | Action Taken |
|----------------|-------------|
| `notDetermined` / `denied` | Requests **foreground** (When In Use) permission |
| `whenInUse` | Requests **background** (Always) permission |
| `always` / `deniedForever` | Returns immediately — no dialog shown |

### Recommended Permission Flow

```dart
import 'package:tracelet/tracelet.dart' as tl;
import 'package:flutter/material.dart';

Future<void> initializeWithPermissions(BuildContext context) async {
  // 1. Check current status (no dialog)
  final status = await tl.Tracelet.getPermissionStatus();

  // 2. Handle each case
  switch (status) {
    case 0: // notDetermined
    case 1: // denied (can ask again)
      final result = await tl.Tracelet.requestPermission();
      if (result == 4) {
        // Permanently denied — show YOUR dialog
        _showDeniedDialog(context);
        return;
      }
      if (result == 2) {
        // Foreground granted — show rationale then request background
        final upgrade = await _showBackgroundRationale(context);
        if (upgrade) await tl.Tracelet.requestPermission();
      }
      break;

    case 2: // whenInUse — offer background upgrade
      final upgrade = await _showBackgroundRationale(context);
      if (upgrade) await tl.Tracelet.requestPermission();
      break;

    case 4: // deniedForever
      _showDeniedDialog(context);
      return;
  }

  // 3. Now safe to initialize and start
  await tl.Tracelet.ready(tl.Config(/* ... */));
  await tl.Tracelet.start();
}
```

### Dart-Side Permission Dialogs (Example Implementations)

#### Permanently Denied Dialog

Show when `getPermissionStatus()` or `requestPermission()` returns `4` (deniedForever):

```dart
void _showDeniedDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.location_off, color: Colors.red, size: 48),
      title: const Text('Location Permission Required'),
      content: const Text(
        'Location permission has been permanently denied. '
        'Tracelet cannot track your location without it.\n\n'
        'Please open Settings and enable location access '
        'for this app to resume tracking.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Not Now'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(ctx);
            tl.Tracelet.openAppSettings();
          },
          icon: const Icon(Icons.settings),
          label: const Text('Open Settings'),
        ),
      ],
    ),
  );
}
```

#### Background Permission Rationale Dialog

Show **before** requesting background (Always) permission to explain why it's needed:

```dart
Future<bool> _showBackgroundRationale(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.share_location, color: Colors.indigo, size: 48),
      title: const Text('Background Location Access'),
      content: const Text(
        'This app needs background location access to continue '
        'recording your location when the app is not in the foreground.\n\n'
        'On the next screen, select "Allow all the time" to enable '
        'background tracking.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Keep Foreground Only'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.upgrade),
          label: const Text('Change to "Allow all the time"'),
        ),
      ],
    ),
  );
  return result ?? false;
}
```

> **Tip:** You can replace these `AlertDialog` widgets with any Flutter widget —
> bottom sheets, custom pages, Cupertino dialogs, or animated overlays.
> The permission API is UI-agnostic.

### Notification Permission (Android 13+)

Starting with Android 13 (API 33), the `POST_NOTIFICATIONS` runtime permission
is required for the foreground service notification to be visible. Without it,
the service still runs but the notification is hidden — and some OEMs may then
kill the background process.

`getNotificationPermissionStatus()` and `requestNotificationPermission()` return
the same status codes as the location permission API:

| Code | Meaning |
|------|------|
| `0` | Never asked |
| `1` | Denied, can ask again |
| `3` | Granted |
| `4` | Permanently denied |

On Android < 13 and on iOS, both methods always return `3` (granted).

#### Recommended Flow

```dart
// Before starting a foreground service with notification:
if (Platform.isAndroid) {
  final status = await tl.Tracelet.getNotificationPermissionStatus();
  if (status != 3) {
    // Show YOUR rationale dialog first, then:
    final result = await tl.Tracelet.requestNotificationPermission();
    if (result == 4) {
      // Permanently denied — show dialog with "Open Settings" button
      await tl.Tracelet.openAppSettings();
    }
  }
}
```

#### Notification Rationale Dialog (Example)

```dart
Future<bool> _showNotificationRationale(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.notifications_active,
          color: Colors.deepOrange, size: 48),
      title: const Text('Enable Notifications'),
      content: const Text(
        'This app uses a persistent notification to keep background '
        'tracking alive on Android.\n\n'
        'Without notification permission, the foreground service '
        'still runs but the notification will be hidden.\n\n'
        'Allow notifications for the most reliable tracking.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Skip'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.notifications),
          label: const Text('Allow Notifications'),
        ),
      ],
    ),
  );
  return result ?? false;
}
```

---

## Background Tracking

### With Foreground Notification (Recommended)

The foreground service keeps the app alive reliably in the background on Android.
A persistent notification is shown while tracking.

> **Android 13+:** You must request notification permission (`POST_NOTIFICATIONS`)
> before starting the foreground service, otherwise the notification will be
> hidden. See [Notification Permission](#notification-permission-android-13)
> above.

```dart
// 1. Request notification permission (Android 13+)
if (Platform.isAndroid) {
  final notifStatus = await tl.Tracelet.getNotificationPermissionStatus();
  if (notifStatus != 3) {
    await tl.Tracelet.requestNotificationPermission();
  }
}

// 2. Configure and start
await tl.Tracelet.ready(tl.Config(
  app: tl.AppConfig(
    stopOnTerminate: false,
    startOnBoot: true,
    foregroundService: tl.ForegroundServiceConfig(
      notificationTitle: 'My App',
      notificationText: 'Tracking your location',
    ),
  ),
));
await tl.Tracelet.start();
```

### Without Foreground Notification

No notification is shown. Suitable for short-lived tasks like check-ins,
one-shot location fetches, or foreground-only use. The OS may kill the app
in the background at any time.

```dart
await tl.Tracelet.ready(tl.Config(
  app: tl.AppConfig(
    stopOnTerminate: true,
    foregroundService: tl.ForegroundServiceConfig(enabled: false),
  ),
));
await tl.Tracelet.start();
```

### Switching at Runtime

You can switch between modes at runtime using `setConfig()`:

```dart
// Switch to background tracking with notification
await tl.Tracelet.setConfig(tl.Config(
  app: tl.AppConfig(
    stopOnTerminate: false,
    startOnBoot: true,
    foregroundService: tl.ForegroundServiceConfig(
      notificationTitle: 'My App',
      notificationText: 'Background tracking active',
    ),
  ),
));
await tl.Tracelet.start();

// Switch to no-notification mode
await tl.Tracelet.setConfig(tl.Config(
  app: tl.AppConfig(
    stopOnTerminate: true,
    foregroundService: tl.ForegroundServiceConfig(enabled: false),
  ),
));
await tl.Tracelet.start();
```

---

## API Overview

### Lifecycle

| Method | Returns | Description |
|---|---|---|
| `Tracelet.ready(config)` | `State` | Initialize with configuration |
| `Tracelet.start()` | `State` | Start tracking |
| `Tracelet.stop()` | `State` | Stop tracking |
| `Tracelet.startGeofences()` | `State` | Geofence-only mode |
| `Tracelet.getState()` | `State` | Current state |
| `Tracelet.setConfig(config)` | `State` | Update configuration |
| `Tracelet.reset()` | `State` | Reset to defaults |

### Location

| Method | Returns | Description |
|---|---|---|
| `Tracelet.getCurrentPosition()` | `Location` | One-shot position |
| `Tracelet.watchPosition(callback)` | `int` | High-frequency watch |
| `Tracelet.stopWatchPosition(id)` | `bool` | Stop a watch |
| `Tracelet.changePace(isMoving)` | `bool` | Force motion state |
| `Tracelet.getOdometer()` | `double` | Odometer in meters |
| `Tracelet.setOdometer(value)` | `Location` | Reset odometer |

### Geofencing

| Method | Returns | Description |
|---|---|---|
| `Tracelet.addGeofence(geofence)` | `bool` | Add a geofence |
| `Tracelet.addGeofences(list)` | `bool` | Add multiple |
| `Tracelet.removeGeofence(id)` | `bool` | Remove by identifier |
| `Tracelet.removeGeofences()` | `bool` | Remove all |
| `Tracelet.getGeofences()` | `List<Geofence>` | List all |
| `Tracelet.getGeofence(id)` | `Geofence?` | Get one |
| `Tracelet.geofenceExists(id)` | `bool` | Check existence |

### Persistence & Sync

| Method | Returns | Description |
|---|---|---|
| `Tracelet.getLocations()` | `List<Location>` | Stored locations |
| `Tracelet.getCount()` | `int` | Location count |
| `Tracelet.destroyLocations()` | `bool` | Delete all |
| `Tracelet.destroyLocation(uuid)` | `bool` | Delete one |
| `Tracelet.insertLocation(params)` | `String` | Insert custom |
| `Tracelet.sync()` | `List<Location>` | Manual HTTP sync |

### Permissions & Settings

| Method | Returns | Description |
|---|---|---|
| `Tracelet.getPermissionStatus()` | `int` | Current location status (no dialog) |
| `Tracelet.requestPermission()` | `int` | Request location + wait for result |
| `Tracelet.getNotificationPermissionStatus()` | `int` | Notification status (Android 13+) |
| `Tracelet.requestNotificationPermission()` | `int` | Request notification (Android 13+) |
| `Tracelet.openAppSettings()` | `bool` | Open app settings |
| `Tracelet.openLocationSettings()` | `bool` | Open location settings |
| `Tracelet.openBatterySettings()` | `bool` | Open battery optimization (Android) |
| `Tracelet.requestTemporaryFullAccuracy(purpose)` | `int` | Temp full accuracy (iOS 14+) |
| `Tracelet.isPowerSaveMode` | `bool` | Battery saver active? |
| `Tracelet.isIgnoringBatteryOptimizations()` | `bool` | Battery exempt? (Android) |

### Events

| Subscription | Event Type | Fires when |
|---|---|---|
| `Tracelet.onLocation(cb)` | `Location` | Every recorded location |
| `Tracelet.onMotionChange(cb)` | `Location` | Moving ↔ stationary |
| `Tracelet.onActivityChange(cb)` | `ActivityChangeEvent` | Activity changes |
| `Tracelet.onProviderChange(cb)` | `ProviderChangeEvent` | GPS/permission changes |
| `Tracelet.onGeofence(cb)` | `GeofenceEvent` | Geofence transitions |
| `Tracelet.onGeofencesChange(cb)` | `GeofencesChangeEvent` | Monitored set changes |
| `Tracelet.onHeartbeat(cb)` | `HeartbeatEvent` | Heartbeat interval |
| `Tracelet.onHttp(cb)` | `HttpEvent` | HTTP sync result |
| `Tracelet.onSchedule(cb)` | `State` | Schedule start/stop |
| `Tracelet.onConnectivityChange(cb)` | `ConnectivityChangeEvent` | Online/offline |
| `Tracelet.onPowerSaveChange(cb)` | `bool` | Battery saver toggle |
| `Tracelet.onEnabledChange(cb)` | `bool` | Tracking on/off |
| `Tracelet.onNotificationAction(cb)` | `String` | Notification tap (Android) |
| `Tracelet.onAuthorization(cb)` | `AuthorizationEvent` | Auth token refresh |

---

## Configuration

Configuration is organized into logical groups:

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

## Architecture

This is the **app-facing package** in a federated plugin:

| Package | Description |
|---|---|
| **`tracelet`** (this package) | Dart API — the only package apps depend on |
| `tracelet_platform_interface` | Abstract platform interface |
| `tracelet_android` | Kotlin Android implementation |
| `tracelet_ios` | Swift iOS implementation |

## License

Apache 2.0 — see [LICENSE](../../LICENSE) for details.
