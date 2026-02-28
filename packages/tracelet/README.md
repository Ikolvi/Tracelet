<p align="center">
  <img src="https://raw.githubusercontent.com/Ikolvi/Tracelet/main/assets/logo_anim.webp" alt="Tracelet" width="100%"/>
</p>

# Tracelet

<p align="center">
  <img src="https://raw.githubusercontent.com/Ikolvi/Tracelet/main/assets/tracelet_android_rec.webp" alt="Tracelet Android" width="300"/>
  &nbsp;&nbsp;
  <img src="https://raw.githubusercontent.com/Ikolvi/Tracelet/main/assets/tracelet_ios_rec.webp" alt="Tracelet iOS" width="300"/>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/Ikolvi/Tracelet/main/assets/map_view.png" alt="Tracelet Live Map" width="300"/>
</p>

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

> **Production-grade background geolocation for Flutter — fully open-source.**

Battery-conscious motion-detection intelligence, geofencing, SQLite persistence, HTTP sync, and headless Dart execution for iOS & Android.

## Features

- **Background location tracking** — continuous GPS with configurable `distanceFilter` and `desiredAccuracy`
- **Motion-detection intelligence** — accelerometer + activity recognition automatically toggle GPS to save battery
- **Geofencing** — circular and polygon geofences with enter/exit/dwell events
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
- **Kalman filter** — optional GPS coordinate smoothing via Extended Kalman Filter (`useKalmanFilter: true`)
- **Trip detection** — automatic trip start/stop events with distance, duration, and waypoints
- **Polygon geofences** — define geofences with arbitrary polygon vertices for non-circular regions
- **Auto-stop** — automatically stop tracking after N minutes via `stopAfterElapsedMinutes`
- **Activity recognition tuning** — confidence thresholds, stop-detection delays, stationary behavior
- **Timestamp metadata** — optional extra timing fields on each location record
- **Geofence high-accuracy mode** — full GPS pipeline in geofence-only mode (Android)
- **Prevent suspend (iOS)** — silent audio keep-alive for continuous background execution
- **Shared Dart algorithms** — location filtering, geofence proximity, schedule parsing, and persistence logic run in shared Dart for cross-platform consistency
- **Mock location detection** — detect and reject spoofed GPS with configurable detection levels (basic platform flags + advanced heuristics). [Learn more →](https://github.com/Ikolvi/Tracelet/blob/main/help/MOCK-DETECTION.md)

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
      useKalmanFilter: true, // smooth GPS coordinates
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

### Kalman Filter GPS Smoothing

Enable the Extended Kalman Filter to smooth GPS coordinates, eliminate jitter, and produce cleaner tracks:

```dart
final state = await tl.Tracelet.ready(tl.Config(
  geo: tl.GeoConfig(
    filter: tl.LocationFilter(
      useKalmanFilter: true, // Enable Kalman smoothing
    ),
  ),
));
```

The filter uses a constant-velocity model with GPS accuracy as measurement noise. It runs natively on both Android and iOS for zero-overhead smoothing. See the [Kalman Filter Guide](https://github.com/Ikolvi/Tracelet/blob/main/help/KALMAN-FILTER.md) for details.

### Trip Detection

Subscribe to trip events that fire automatically when the device transitions from moving to stationary. See the [Trip Detection Guide](https://github.com/Ikolvi/Tracelet/blob/main/help/TRIP-DETECTION.md) for full details.

```dart
tl.Tracelet.onTrip((tl.TripEvent trip) {
  print('Trip ended: ${trip.distance}m in ${trip.duration}s');
  print('From: ${trip.startLocation}');
  print('To: ${trip.stopLocation}');
  print('Avg speed: ${trip.averageSpeed} m/s');
  print('Waypoints: ${trip.waypoints.length}');
});
```

### Polygon Geofences

Define geofences with arbitrary polygon vertices instead of circular regions:

```dart
await tl.Tracelet.addGeofence(tl.Geofence(
  identifier: 'campus',
  latitude: 37.422,    // centroid for proximity sorting
  longitude: -122.084,
  radius: 0,           // ignored for polygon geofences
  vertices: [
    [37.423, -122.086],
    [37.424, -122.082],
    [37.421, -122.081],
    [37.420, -122.085],
  ],
));
```

Polygon containment uses the ray-casting algorithm for efficient point-in-polygon checks. Requires `geofenceModeHighAccuracy: true`. See the [Polygon Geofences Guide](https://github.com/Ikolvi/Tracelet/blob/main/help/POLYGON-GEOFENCES.md) for full details.

| Guide | Description |
|---|---|
| [Android Setup](https://github.com/Ikolvi/Tracelet/blob/main/help/INSTALL-ANDROID.md) | Gradle, permissions, and manifest configuration |
| [iOS Setup](https://github.com/Ikolvi/Tracelet/blob/main/help/INSTALL-IOS.md) | Info.plist, capabilities, and entitlements |
| [Permissions](https://github.com/Ikolvi/Tracelet/blob/main/help/PERMISSIONS.md) | Permission flow, status codes, Dart dialog examples |
| [Background Tracking](https://github.com/Ikolvi/Tracelet/blob/main/help/BACKGROUND-TRACKING.md) | Foreground service, silent mode, runtime switching |
| [API Reference](https://github.com/Ikolvi/Tracelet/blob/main/help/API.md) | All methods, events, and return types |
| [Configuration](https://github.com/Ikolvi/Tracelet/blob/main/help/CONFIGURATION.md) | All config groups with property tables |
| [Kalman Filter](https://github.com/Ikolvi/Tracelet/blob/main/help/KALMAN-FILTER.md) | GPS smoothing — how it works, when to use it |
| [Trip Detection](https://github.com/Ikolvi/Tracelet/blob/main/help/TRIP-DETECTION.md) | Automatic trip events — setup, API, edge cases |
| [Polygon Geofences](https://github.com/Ikolvi/Tracelet/blob/main/help/POLYGON-GEOFENCES.md) | Polygon geofences — vertices, ray-casting, examples |
| [Web Support](https://github.com/Ikolvi/Tracelet/blob/main/help/WEB-SUPPORT.md) | Web platform capabilities, limitations, and browser APIs |
| [Mock Detection](https://github.com/Ikolvi/Tracelet/blob/main/help/MOCK-DETECTION.md) | Detect & reject spoofed GPS — detection levels, heuristics, platform details |

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
