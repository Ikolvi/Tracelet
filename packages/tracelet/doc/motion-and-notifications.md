# Advanced Features & Setup Guide (Version 2.1.0+)

This guide provides extensive documentation and examples for the advanced capabilities introduced in Tracelet 2.1.0, including Speed-Based Motion Detection, Smart Foreground Notification Visibility, and Kalman Filter smoothing.

## Table of Contents
1. [Speed-Based Motion Detection](#1-speed-based-motion-detection)
2. [Smart Foreground Notification Visibility](#2-smart-foreground-notification-visibility)
3. [Kalman Filter Integration](#3-kalman-filter-integration)

---

## 1. Speed-Based Motion Detection

By default, Tracelet uses the device's pedometer / accelerometer (Activity Recognition) to determine if the device is moving (`stationary` vs `moving`). However, in scenarios where the device is mounted to a vehicle or when the accelerometer doesn't accurately reflect movement, **Speed-Based Motion Detection** is the ideal solution.

When enabled, the motion engine continuously monitors speed changes through GPS and applies sophisticated algorithms to transition the device between states without relying on the accelerometer. 

### How It Works
The speed-based engine introduces an intermediate `slowing` state:
- **`stationary`**: Device is below the `speedMovingThreshold`.
- **`moving`**: Device exceeds the `speedMovingThreshold`.
- **`slowing`**: Device was moving but speed has dropped below the threshold. If it remains below the threshold for `speedStationaryDelay` seconds, it transitions to `stationary`. 

### Common Scenarios & Setup Examples

#### Scenario A: Vehicle / Fleet Tracking
When tracking cars or trucks, you want to ignore small movements and only trigger "moving" when driving. You also want to wait before declaring a vehicle "stationary" to account for traffic lights.

```dart
final config = TlConfig(
  motion: MotionConfig(
    // Enable speed-based detection instead of accelerometer
    motionDetectionMode: MotionDetectionMode.speed,
    
    // Consider moving only when speed exceeds ~5.6 mph (2.5 m/s)
    speedMovingThreshold: 2.5,
    
    // Wait 5 minutes (300 seconds) of zero/low speed before entering stationary mode. 
    // This prevents the tracker from sleeping at long red lights.
    speedStationaryDelay: 300,
    
    // When stationary, use geofences to wake up again when the vehicle moves
    stationaryTrackingMode: StationaryTrackingMode.geofences,
    
    // Require 2 consecutive readings confirming "stationary" speeds to avoid GPS jitter
    speedWakeConfirmCount: 2,
  ),
  location: LocationConfig(
    distanceFilter: 50.0, // Update every 50 meters
    desiredAccuracy: DesiredAccuracy.high,
  ),
);

await Tracelet.instance.setConfig(config);
await Tracelet.instance.start();
```

#### Scenario B: Maritime / Boat Tracking
Boats drift and bob on the water, which can trick the accelerometer or cause low-speed GPS jitter.

```dart
final config = TlConfig(
  motion: MotionConfig(
    motionDetectionMode: MotionDetectionMode.speed,
    // Higher threshold to ignore drifting at anchor
    speedMovingThreshold: 1.5, 
    // Wait 10 minutes before turning off GPS
    speedStationaryDelay: 600, 
    // Wake up periodically rather than relying on geofences in open water
    stationaryTrackingMode: StationaryTrackingMode.periodic,
    stationaryPeriodicInterval: 900, // Wake up every 15 mins while anchored
  ),
);
```

> **Note**: When `motionDetectionMode: MotionDetectionMode.speed` is active, Tracelet automatically disables the OS-level distance filter while moving, ensuring consistent speed calculations.

---

## 2. Smart Foreground Notification Visibility

Android 14 introduced strict constraints regarding when Foreground Services (FGS) can be launched from the background. By default, Tracelet must display a persistent notification while tracking. However, showing this notification can be annoying to users when tracking isn't actively occurring.

The **Smart Foreground Notification Visibility** feature allows you to only show the persistent notification when the app enters the background or when a specific state is reached, while seamlessly keeping the FGS alive.

### How It Works
If `showNotificationOnPauseOnly` is enabled, the SDK starts the Foreground Service and then hides the notification while the user is actively using the app, revealing it again when the app goes into the background.

Hiding it means **demoting the service**: Android has no such thing as a foreground service without a notification, so `stopForeground()` is what takes it down. The service keeps running and tracking is unaffected — but while it is demoted the process holds no foreground service, which is the state Android kills when the user swipes the app out of recents. See the constraint below.

### Common Scenarios & Setup Examples

#### Scenario C: Stealthy User Experience
You want to track locations in the background but want to avoid cluttering the user's notification tray while they have the app open.

```dart
final config = TlConfig(
  foregroundService: ForegroundServiceConfig(
    enabled: true,
    notificationTitle: "Active Tracking",
    notificationText: "Tracking your route...",
    
    // The Magic Flag: The notification will disappear when the app is in focus
    // and reappear when the app is swiped to the background.
    showNotificationOnPauseOnly: true,
  ),
);
```

> **Warning**: Disabling `showNotificationOnPauseOnly` (setting it to `false`) means the notification is always visible while tracking is enabled. On Android 14+, attempting to start an FGS without immediate notification visibility from a background state may result in exceptions if not handled properly by this smart logic.

### Constraint: it is ignored under `stopOnTerminate: false` (#378)

The two settings ask for incompatible things, and the survival promise wins.

While the notification is hidden the process holds no foreground service, and `ActivityManager` chooses which processes to kill on task removal from exactly that fact — before the SDK's `onTaskRemoved` handler runs, so nothing the SDK does at removal time can undo it. A swipe from recents in the few hundred milliseconds between the app leaving the screen and the notification coming back therefore killed the process outright: no headless task, no events, no logs, nothing that `stopOnTerminate: false` exists to guarantee. The window was measured at 285 ms on a Pixel Fold and 700–1500 ms on the reporting user's Android 15 device.

So when `stopOnTerminate: false` is set, `showNotificationOnPauseOnly` is not applied and the notification stays visible. It is not silent — the SDK writes one line to the always-on lifecycle log channel, readable via `Tracelet.getLogs()`:

```text
notification: showNotificationOnPauseOnly ignored because stopOnTerminate=false — …
```

`Tracelet.getForegroundServiceHealth()` reports the same thing from the other side: when the notification *is* legitimately hidden (`stopOnTerminate: true`), `serviceForeground` is `false` and `lastForegroundPromotionResult` is `suppressed` — a demotion you asked for, distinct from a promotion the OS refused.

To keep the hidden notification, set `stopOnTerminate: true` and accept that tracking ends with the swipe. On Android 14+ a location foreground service must show its notification anyway once the app is not on screen, so what you gain is limited to the period the app is open.

This is Android-only. iOS has no foreground service, no notification to hide and no task-removal kill of this kind; `showNotificationOnPauseOnly` lives on `AndroidConfig` and is not read by the iOS SDK.

---

## 3. Kalman Filter Integration

GPS signals can be noisy, especially in urban canyons (between tall buildings) or under heavy tree cover. Tracelet 2.1.0 introduces a native-layer **Kalman Filter** to smooth out these erratic GPS coordinates and provide a fluid, accurate trail.

### How It Works
The Kalman Filter applies predictive mathematical modeling based on the device's previous location, speed, and heading to estimate the true location and discard impossible coordinate jumps (outliers).

### Common Scenarios & Setup Examples

#### Scenario D: Fitness / Running App
Runners often travel through parks with trees or downtown areas with tall buildings. The raw GPS path looks jagged. 

```dart
final config = TlConfig(
  location: LocationConfig(
    // Enable the native Kalman filter
    useKalmanFilter: true,
    
    desiredAccuracy: DesiredAccuracy.navigation, // Maximum accuracy
    distanceFilter: 10.0, // High frequency updates for running
  ),
);
```

> **Tip**: The Kalman Filter slightly delays the exact position by a few meters as it calculates the smoothed vector. It is highly recommended for visual route drawing (polylines on a map) but can be disabled if raw, unadulterated GPS points are required for strict auditing.
