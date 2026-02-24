<p align="center">
  <img src="https://raw.githubusercontent.com/Ikolvi/Tracelet/main/assets/logo_anim.webp" alt="Tracelet" width="100%"/>
</p>

# Tracelet

<p align="center">
  <img src="https://raw.githubusercontent.com/Ikolvi/Tracelet/main/assets/tracelet_android_rec.webp" alt="Tracelet Android" width="300"/>
  &nbsp;&nbsp;
  <img src="https://raw.githubusercontent.com/Ikolvi/Tracelet/main/assets/tracelet_ios_rec.webp" alt="Tracelet iOS" width="300"/>
</p>

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

## Documentation

| Guide | Description |
|---|---|
| [Android Setup](https://github.com/Ikolvi/Tracelet/blob/main/help/INSTALL-ANDROID.md) | Gradle, permissions, and manifest configuration |
| [iOS Setup](https://github.com/Ikolvi/Tracelet/blob/main/help/INSTALL-IOS.md) | Info.plist, capabilities, and entitlements |
| [Permissions](https://github.com/Ikolvi/Tracelet/blob/main/help/PERMISSIONS.md) | Permission flow, status codes, Dart dialog examples |
| [Background Tracking](https://github.com/Ikolvi/Tracelet/blob/main/help/BACKGROUND-TRACKING.md) | Foreground service, silent mode, runtime switching |
| [API Reference](https://github.com/Ikolvi/Tracelet/blob/main/help/API.md) | All methods, events, and return types |
| [Configuration](https://github.com/Ikolvi/Tracelet/blob/main/help/CONFIGURATION.md) | All config groups with property tables |
| [Web Support](https://github.com/Ikolvi/Tracelet/blob/main/help/WEB-SUPPORT.md) | Web platform capabilities, limitations, and browser APIs |

## Architecture

This is the **app-facing package** in a federated plugin:

| Package | Description |
|---|---|
| **`tracelet`** (this package) | Dart API — the only package apps depend on |
| `tracelet_platform_interface` | Abstract platform interface |
| `tracelet_android` | Kotlin Android implementation |
| `tracelet_ios` | Swift iOS implementation |
| `tracelet_web` | Web implementation (experimental) |

## Support

If you find Tracelet useful, consider buying me a coffee:

<p align="center">
  <a href="https://buymeacoffee.com/kiranbjm">
    <img src="https://raw.githubusercontent.com/Ikolvi/Tracelet/main/assets/buy_me_a_coffee.png" alt="Buy Me a Coffee" width="200"/>
  </a>
</p>

<p align="center">
  <a href="https://buymeacoffee.com/kiranbjm">buymeacoffee.com/kiranbjm</a>
</p>

## License

Apache 2.0 — see [LICENSE](../../LICENSE) for details.
