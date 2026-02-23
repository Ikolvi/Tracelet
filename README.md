<p align="center">
  <img src="assets/tracelet-logo.jpeg" alt="Tracelet" width="200"/>
</p>

# Tracelet

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![CI](https://github.com/Ikolvi/Tracelet/actions/workflows/ci.yml/badge.svg)](https://github.com/Ikolvi/Tracelet/actions)

> **Production-grade background geolocation for Flutter — fully open-source.**

Battery-conscious motion-detection intelligence, geofencing, SQLite persistence, HTTP sync, and headless Dart execution for iOS & Android.

## Features

- **Motion-detection intelligence** — Uses accelerometer, gyroscope & activity recognition to detect when the device is moving or stationary. Automatically toggles location services to conserve battery.
- **Background location tracking** — Continuous GPS recording with configurable `distanceFilter` and `desiredAccuracy`. Works after app is minimized, killed, or device rebooted.
- **Geofencing** — Add circular geofences with enter/exit/dwell detection. 100 on Android, intelligent nearest-20 rotation on iOS.
- **SQLite persistence** — All locations stored locally in SQLite. Query, count, delete, or sync to your server. Configurable retention (max days/records) and per-type persistence modes.
- **HTTP auto-sync** — Configurable batch upload with retry, exponential backoff, and offline queuing. Wi-Fi-only sync option via `disableAutoSyncOnCellular`.
- **Headless execution** — Run Dart code in response to background events even when the Flutter UI is not running.
- **Start on boot** — Resume tracking automatically after device reboot.
- **Scheduling** — Define time-based schedules (e.g., "Mon–Fri 9AM–5PM"). Use `scheduleUseAlarmManager` on Android for exact-time execution.
- **Comprehensive logging** — SQLite-backed log system with email export.
- **Debug sounds** — Audible feedback during development for location, motion, geofence, and HTTP events.
- **Elasticity control** — Speed-based automatic distance filter scaling, with `disableElasticity` and `elasticityMultiplier` overrides.
- **Location filtering** — Reject GPS spikes and low-accuracy readings with `LocationFilter` (accuracy thresholds, max implied speed, odometer filtering).
- **Auto-stop** — Automatically stop tracking after a configurable number of minutes via `stopAfterElapsedMinutes`.
- **Activity recognition tuning** — Adjust confidence thresholds, stop-detection delays, and stationary behavior.
- **Timestamp metadata** — Optional extra timing fields on each location record via `enableTimestampMeta`.
- **Geofence high-accuracy mode** — Run the full GPS + motion pipeline in geofence-only mode (Android) via `geofenceModeHighAccuracy`.
- **Prevent suspend (iOS)** — Silent audio keep-alive to prevent iOS from suspending the app in the background.
- **Dart-controlled permissions** — No native dialogs. Full Dart-side customization of permission UI, translations, and behavior.
- **Foreground service toggle** — Run with or without a persistent notification (Android).

## Architecture

Tracelet uses a **federated plugin architecture** with 4 packages:

| Package | Description |
|---|---|
| [`tracelet`](packages/tracelet/) | App-facing Dart API — the only package you depend on |
| [`tracelet_platform_interface`](packages/tracelet_platform_interface/) | Abstract platform interface + Pigeon definitions |
| [`tracelet_android`](packages/tracelet_android/) | Kotlin Android implementation |
| [`tracelet_ios`](packages/tracelet_ios/) | Swift iOS implementation |

## Quick Start

```dart
import 'package:tracelet/tracelet.dart' as tl;

// 1. Listen to events
tl.Tracelet.onLocation((tl.Location location) {
  print('[location] $location');
});

tl.Tracelet.onMotionChange((tl.Location location) {
  print('[motionchange] isMoving: ${location.isMoving}');
});

// 2. Configure & ready
final state = await tl.Tracelet.ready(tl.Config(
  geo: tl.GeoConfig(
    desiredAccuracy: tl.DesiredAccuracy.high,
    distanceFilter: 10.0,
    // Reject GPS spikes and low-accuracy readings
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
if (!state.enabled) {
  await tl.Tracelet.start();
}
```

## Permissions

Tracelet does **not** show any native permission dialogs — only the OS prompt
is triggered. All permission UI is controlled from Dart, giving you full
freedom to customize dialogs, translations, and behavior.

| Method | Description |
|---|---|
| `Tracelet.getPermissionStatus()` | Read-only check — no dialog |
| `Tracelet.requestPermission()` | Triggers OS dialog, returns result |
| `Tracelet.getNotificationPermissionStatus()` | Notification status (Android 13+) |
| `Tracelet.requestNotificationPermission()` | Request notification permission (Android 13+) |
| `Tracelet.openAppSettings()` | Opens the app's system settings |
| `Tracelet.openLocationSettings()` | Opens device location settings |
| `Tracelet.openBatterySettings()` | Opens battery optimization (Android) |

**Status codes:** `0` notDetermined · `1` denied · `2` whenInUse · `3` always · `4` deniedForever

### Recommended Flow

```dart
final status = await tl.Tracelet.getPermissionStatus();
if (status == 4) {
  // Permanently denied — show YOUR Dart dialog with "Open Settings" button
  await tl.Tracelet.openAppSettings();
  return;
}
if (status == 0 || status == 1) {
  final result = await tl.Tracelet.requestPermission(); // foreground
  if (result == 2) {
    // Show background rationale dialog, then:
    await tl.Tracelet.requestPermission(); // upgrade to Always
  }
} else if (status == 2) {
  // Already foreground — show rationale, then upgrade
  await tl.Tracelet.requestPermission();
}
```

> See the [package README](packages/tracelet/README.md#permissions) for
> complete dialog implementations (denied dialog, background rationale dialog,
> notification rationale dialog, full escalation flow) with copy-paste Flutter code.

## Background Tracking

### With Foreground Notification (Recommended)

> **Android 13+:** Request notification permission first, otherwise the
> notification is hidden. See
> [Notification Permission](packages/tracelet/README.md#notification-permission-android-13).

> **iOS:** Foreground service config is ignored — iOS uses its own
> background-mode mechanisms (BackgroundTasks, CoreLocation significant
> changes). No notification permission is needed for background location.

```dart
// Android 13+: ensure notification permission
if (Platform.isAndroid) {
  final ns = await tl.Tracelet.getNotificationPermissionStatus();
  if (ns != 3) await tl.Tracelet.requestNotificationPermission();
}

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

```dart
await tl.Tracelet.ready(tl.Config(
  app: tl.AppConfig(
    stopOnTerminate: true,
    foregroundService: tl.ForegroundServiceConfig(enabled: false),
  ),
));
await tl.Tracelet.start();
```

> See the [package README](packages/tracelet/README.md#background-tracking) for
> runtime switching with `setConfig()`.

## Platform Setup

- [Android Setup Guide](help/INSTALL-ANDROID.md)
- [iOS Setup Guide](help/INSTALL-IOS.md)

## Requirements

| Platform | Minimum Version |
|---|---|
| Android | API 26 (Android 8.0 Oreo) |
| iOS | 14.0 |
| Flutter | 3.22+ |
| Dart | 3.4+ |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

Apache 2.0 — see [LICENSE](LICENSE) for details.

All native code is written from scratch. No proprietary SDK dependencies.
