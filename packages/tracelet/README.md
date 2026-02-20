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
- **SQLite persistence** — all locations stored locally, queryable
- **HTTP auto-sync** — batch upload with retry, exponential backoff, offline queue
- **Headless execution** — run Dart code in response to background events
- **Scheduling** — time-based tracking windows (e.g., "Mon–Fri 9am–5pm")
- **Start on boot** — resume after device reboot
- **Debug sounds** — audible feedback during development

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
await tl.Tracelet.start();
```

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

## Configuration

Configuration is organized into logical groups:

```dart
Config(
  geo: GeoConfig(                    // Location accuracy & sampling
    desiredAccuracy: DesiredAccuracy.high,
    distanceFilter: 10.0,
    stationaryRadius: 25.0,
  ),
  app: AppConfig(                    // Lifecycle behavior
    stopOnTerminate: false,
    startOnBoot: true,
    heartbeatInterval: 60,
  ),
  http: HttpConfig(                  // Server sync
    url: 'https://example.com/locations',
    method: HttpMethod.post,
    autoSync: true,
    batchSync: true,
  ),
  motion: MotionConfig(              // Motion detection
    stopTimeout: 5,
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
