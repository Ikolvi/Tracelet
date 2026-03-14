# React Native Installation Guide

## Requirements

- React Native **0.73+** (New Architecture / TurboModules)
- iOS **14.0+**
- Android **API 26+** (Android 8.0 Oreo)

## Install

```bash
npm install @tracelet/react-native
# or
yarn add @tracelet/react-native
```

## iOS Setup

### 1. Install Pods

```bash
cd ios && pod install
```

### 2. Enable Background Modes

In Xcode, select your target → **Signing & Capabilities** → **+ Capability** → **Background Modes**. Enable:

- **Location updates**
- **Background fetch**
- **Background processing** (for periodic mode)

### 3. Info.plist Keys

Add these to `ios/YourApp/Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location for tracking.</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>We need background location for continuous tracking.</string>

<key>NSMotionUsageDescription</key>
<string>Used for activity detection (walking, driving, etc.).</string>

<!-- Required for periodic mode (BGAppRefreshTask) -->
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
  <string>com.tracelet.periodicRefresh</string>
</array>
```

### 4. Temporary Full Accuracy (iOS 14+)

If you use `requestTemporaryFullAccuracy()`, add to `Info.plist`:

```xml
<key>NSLocationTemporaryUsageDescriptionDictionary</key>
<dict>
  <key>navigation</key>
  <string>Temporary full accuracy for turn-by-turn navigation.</string>
</dict>
```

---

## Android Setup

### 1. Permissions

Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<!-- Required -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />

<!-- Background location (API 29+) -->
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />

<!-- Activity recognition (motion detection) -->
<uses-permission android:name="android.permission.ACTIVITY_RECOGNITION" />

<!-- Foreground service (required for background tracking) -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />

<!-- Boot restart -->
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />

<!-- Notification permission (API 33+) -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

<!-- Exact alarms for periodic mode (optional) -->
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
```

### 2. Headless Task (Background JS Execution)

Register the headless task in your app's entry point (`index.js`):

```js
import { AppRegistry } from 'react-native';
import App from './src/App';

// Register headless task for background events
AppRegistry.registerHeadlessTask('TraceletHeadlessTask', () => async (event) => {
  console.log('[Tracelet Headless]', event.name, event.event);
  // Process background events here (e.g., sync to your server)
});

AppRegistry.registerComponent('YourApp', () => App);
```

### 3. ProGuard / R8

If minification is enabled, add to `android/app/proguard-rules.pro`:

```
-keep class com.tracelet.** { *; }
```

---

## Quick Start

```typescript
import { Tracelet, DesiredAccuracy } from '@tracelet/react-native';

// 1. Configure
const state = await Tracelet.ready({
  geo: {
    desiredAccuracy: DesiredAccuracy.high,
    distanceFilter: 10,
  },
  app: {
    stopOnTerminate: false,
    startOnBoot: true,
  },
});

// 2. Subscribe to events
const sub = Tracelet.onLocation((location) => {
  console.log('Location:', location.coords.latitude, location.coords.longitude);
});

// 3. Request permission & start
await Tracelet.requestPermission();
await Tracelet.start();

// 4. Stop when done
await Tracelet.stop();
sub.remove();
```

## Tracking Modes

| Mode | Method | Use Case |
|------|--------|----------|
| **Location** | `start()` | Continuous GPS tracking with motion detection |
| **Geofences** | `startGeofences()` | Monitor geofence enter/exit/dwell only |
| **Periodic** | `startPeriodic()` | Battery-saver: GPS fix every N seconds |

## Event Reference

| Event | Callback Type | Description |
|-------|--------------|-------------|
| `onLocation` | `(location: Location) => void` | New location recorded |
| `onMotionChange` | `(event: MotionChangeEvent) => void` | Moving ↔ stationary |
| `onActivityChange` | `(event: ActivityChangeEvent) => void` | walking/driving/still |
| `onGeofence` | `(event: GeofenceEvent) => void` | Geofence transition |
| `onHeartbeat` | `(event: HeartbeatEvent) => void` | Periodic check-in |
| `onHttp` | `(event: HttpEvent) => void` | HTTP sync result |
| `onProviderChange` | `(event: ProviderChangeEvent) => void` | GPS on/off |
| `onEnabledChange` | `(enabled: boolean) => void` | Tracking started/stopped |
| `onConnectivityChange` | `(event: ConnectivityChangeEvent) => void` | Network state |

## Troubleshooting

### iOS: App killed in background

Ensure **all three** background modes are enabled (Location updates, Background fetch, Background processing). If using `preventSuspend`, verify the silent audio background mode isn't restricted by the user.

### Android: No locations after app swipe-kill

1. Check that `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_LOCATION` permissions are declared
2. Ensure `stopOnTerminate: false` is set in config
3. On OEM ROMs (Xiaomi, Samsung, Huawei), manually disable battery optimization for your app

### Android: Periodic mode not firing

- If interval < 15 minutes, exact alarms are used (`SCHEDULE_EXACT_ALARM` required on API 31+)
- Check `canScheduleExactAlarms()` and guide users to grant permission if needed
