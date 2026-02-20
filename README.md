<p align="center">
  <img src="assets/tracelet-logo.jpeg" alt="Tracelet" width="200"/>
</p>

# Tracelet

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![CI](https://ikolvi.com/actions/workflows/ci.yml/badge.svg)](https://ikolvi.com/actions)

> **Production-grade background geolocation for Flutter — fully open-source.**

Battery-conscious motion-detection intelligence, geofencing, SQLite persistence, HTTP sync, and headless Dart execution for iOS & Android.

## Features

- **Motion-detection intelligence** — Uses accelerometer, gyroscope & activity recognition to detect when the device is moving or stationary. Automatically toggles location services to conserve battery.
- **Background location tracking** — Continuous GPS recording with configurable `distanceFilter` and `desiredAccuracy`. Works after app is minimized, killed, or device rebooted.
- **Geofencing** — Add circular geofences with enter/exit/dwell detection. 100 on Android, intelligent nearest-20 rotation on iOS.
- **SQLite persistence** — All locations stored locally in SQLite. Query, count, delete, or sync to your server.
- **HTTP auto-sync** — Configurable batch upload with retry, exponential backoff, and offline queuing.
- **Headless execution** — Run Dart code in response to background events even when the Flutter UI is not running.
- **Start on boot** — Resume tracking automatically after device reboot.
- **Scheduling** — Define time-based schedules (e.g., "Mon–Fri 9AM–5PM").
- **Comprehensive logging** — SQLite-backed log system with email export.
- **Debug sounds** — Audible feedback during development for location, motion, geofence, and HTTP events.

## Architecture

Tracelet uses a **federated plugin architecture** with 4 packages:

| Package | Description |
|---|---|
| [`tracelet`](packages/tracelet/) | App-facing Dart API — the only package you depend on |
| [`tracelet_platform_interface`](packages/tracelet_platform_interface/) | Abstract platform interface + Pigeon definitions |
| [`tracelet_android`](packages/tracelet_android/) | Kotlin Android implementation |
| [`tracelet_ios`](packages/tracelet_ios/) | Swift iOS implementation |

## Quick Start

```yaml
dependencies:
  tracelet: ^1.0.0
```

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
  ),
  app: tl.AppConfig(
    stopOnTerminate: false,
    startOnBoot: true,
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
