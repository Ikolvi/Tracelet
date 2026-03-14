# @ikolvi/tracelet

Production-grade background geolocation for React Native. Battery-conscious motion-detection, geofencing, SQLite persistence, HTTP sync, and headless execution.

> **Apache 2.0** — No commercial license required.

## Features

- **Background location tracking** — continuous, periodic, and geofence-only modes
- **Motion detection** — activity recognition (Android) / CoreMotion (iOS)
- **Geofencing** — circular + polygon geofences with enter/exit/dwell events
- **SQLite persistence** — automatic location storage with query API
- **HTTP sync** — automatic batch upload with retry + manual sync
- **Battery budget** — configurable battery-per-hour target
- **Headless execution** — process background events when app is terminated (Android)
- **Enterprise features** — audit trail, privacy zones, compliance reports, carbon estimation
- **TypeScript-first** — full type safety, no `any` types
- **React hooks** — `useLocation()`, `useTraceletState()`, `useGeofences()`

## Installation

```bash
npm install @ikolvi/tracelet
# or
yarn add @ikolvi/tracelet
```

### iOS

```bash
cd ios && pod install
```

Add to `Info.plist`:
```xml
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>We need your location for tracking</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location for tracking</string>
<key>UIBackgroundModes</key>
<array>
  <string>location</string>
  <string>fetch</string>
</array>
```

### Android

Add to `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
```

## Quick Start

```typescript
import { Tracelet, DesiredAccuracy } from '@ikolvi/tracelet';

// 1. Configure
const state = await Tracelet.ready({
  geo: {
    desiredAccuracy: DesiredAccuracy.high,
    distanceFilter: 10,
  },
  http: {
    url: 'https://api.example.com/locations',
    autoSync: true,
  },
});

// 2. Listen for events
const sub = Tracelet.onLocation((location) => {
  console.log('Location:', location.coords.latitude, location.coords.longitude);
});

// 3. Start tracking
await Tracelet.start();

// 4. Stop tracking
await Tracelet.stop();
sub.remove();
```

## React Hooks

```typescript
import { useLocation, useTraceletState, useGeofences } from '@ikolvi/tracelet';

function LocationView() {
  const location = useLocation();
  const state = useTraceletState();
  const geofences = useGeofences();

  return (
    <View>
      <Text>Enabled: {state?.enabled ? 'YES' : 'NO'}</Text>
      <Text>Lat: {location?.coords.latitude}</Text>
      <Text>Geofences: {geofences.length}</Text>
    </View>
  );
}
```

## Tracking Modes

| Mode | Method | Description |
|------|--------|-------------|
| Continuous | `Tracelet.start()` | Full GPS tracking with motion detection |
| Periodic | `Tracelet.startPeriodic()` | One-shot fixes at intervals |
| Geofence-only | `Tracelet.startGeofences()` | Monitor geofences without continuous GPS |

## API Reference

See full [API documentation](../../help/API.md).

## Events

| Event | Type | Description |
|-------|------|-------------|
| `onLocation` | `Location` | New location received |
| `onMotionChange` | `MotionChangeEvent` | Moving ↔ stationary transition |
| `onActivityChange` | `ActivityChangeEvent` | Activity type changed |
| `onGeofence` | `GeofenceEvent` | Geofence entered/exited/dwelled |
| `onHeartbeat` | `HeartbeatEvent` | Periodic heartbeat with location |
| `onHttp` | `HttpEvent` | HTTP sync completed |
| `onEnabledChange` | `boolean` | Tracking enabled/disabled |
| `onProviderChange` | `ProviderChangeEvent` | GPS provider state changed |
| `onConnectivityChange` | `ConnectivityChangeEvent` | Network connectivity changed |
| `onAuthorization` | `AuthorizationEvent` | Location permission changed |

## Headless Execution (Android)

```typescript
// index.js (app entry — NOT in a component)
import { AppRegistry } from 'react-native';

AppRegistry.registerHeadlessTask(
  'TraceletHeadlessTask',
  () => async (event) => {
    console.log('Background event:', event.name, event.event);
  }
);
```

## Requirements

| Platform | Minimum Version |
|----------|----------------|
| React Native | 0.73+ |
| Android | API 26 (8.0) |
| iOS | 14.0 |
| TypeScript | 5.0+ |

## License

Apache 2.0 — see [LICENSE](../../LICENSE).
