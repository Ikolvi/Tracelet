# Periodic Mode

Periodic mode takes **one-shot GPS fixes at timed intervals** instead of
continuous tracking. The GPS radio activates for ~5–10 seconds per fix, then
shuts down completely — dramatically reducing battery consumption compared to
continuous mode.

---

## Quick Start

```dart
import 'package:tracelet/tracelet.dart' as tl;

await tl.Tracelet.ready(tl.Config(
  geo: tl.GeoConfig(
    periodicLocationInterval: 900,             // Fix every 15 minutes
    periodicDesiredAccuracy: tl.DesiredAccuracy.medium,  // WiFi/cell accuracy
    periodicUseForegroundService: false,        // Android: use WorkManager
  ),
));

// Start in periodic mode
await tl.Tracelet.start(mode: tl.TrackingMode.periodic);
```

---

## How It Works

```
Sleep for periodicLocationInterval seconds
  ↓
Wake device → request one-shot fix (GPS/WiFi/cell)
  ↓
Receive fix (~5–10 seconds)
  ↓
Dispatch location via EventChannel
  ↓
Return to sleep
  ↓
Repeat
```

The GPS icon appears **only during the brief fix window**, not continuously.
Users see minimal visual indication of background tracking.

---

## Configuration

| Property | Type | Default | Range | Description |
|----------|------|---------|-------|-------------|
| `periodicLocationInterval` | `int` | `900` | 60–43200 | Seconds between one-shot fixes |
| `periodicDesiredAccuracy` | `DesiredAccuracy` | `medium` | — | Accuracy for periodic fixes |
| `periodicUseForegroundService` | `bool` | `false` | — | Android: use foreground service instead of WorkManager |
| `periodicUseExactAlarms` | `bool` | `false` | — | Android: use AlarmManager for precise timing |

### Interval Guidelines

| Interval | Fixes/Day | Use Case |
|----------|-----------|----------|
| 60 s (1 min) | 1,440 | High-frequency monitoring |
| 300 s (5 min) | 288 | Active delivery tracking |
| 900 s (15 min) | 96 | Default — fleet check-ins |
| 1800 s (30 min) | 48 | Asset tracking |
| 3600 s (1 hr) | 24 | Low-power presence monitoring |
| 43200 s (12 hr) | 2 | Daily check-in |

### Accuracy Levels

| Level | Method | Typical Accuracy | Battery |
|-------|--------|-----------------|---------|
| `high` | GPS + GLONASS | 3–10 m | Highest |
| `medium` | WiFi + cell towers | 50–200 m | Low |
| `low` | Cell only | 500–3000 m | Very low |

For most periodic use cases, `medium` provides sufficient accuracy at
minimal battery cost.

---

## Platform Behavior

### Android

Three scheduling strategies are available:

#### WorkManager (Default)

```dart
GeoConfig(
  periodicUseForegroundService: false,
  periodicUseExactAlarms: false,
)
```

| Aspect | Detail |
|--------|--------|
| Minimum interval | **15 minutes** (WorkManager constraint) |
| Notification | None — no persistent notification |
| GPS indicator | Brief icon during fix only |
| App kill survival | ✅ WorkManager re-schedules automatically |
| Reboot survival | ✅ Via `BootReceiver` |
| Battery optimization | Best — OS manages wake scheduling |

#### Foreground Service

```dart
GeoConfig(
  periodicUseForegroundService: true,
)
```

| Aspect | Detail |
|--------|--------|
| Minimum interval | **60 seconds** (no WorkManager constraint) |
| Notification | Persistent notification visible |
| GPS indicator | Brief icon during fix only |
| App kill survival | ✅ `START_STICKY` restarts service |
| Reboot survival | ✅ Via `BootReceiver` |
| Battery optimization | Good — GPS only during fix window |

Use this when you need **sub-15-minute intervals**.

#### Exact Alarms

```dart
GeoConfig(
  periodicUseForegroundService: false,
  periodicUseExactAlarms: true,
)
```

| Aspect | Detail |
|--------|--------|
| Timing | Precise via `AlarmManager.setExactAndAllowWhileIdle()` |
| Permission | Requires `SCHEDULE_EXACT_ALARM` (API 31+) |
| Use case | When WorkManager deferral is too imprecise |

### iOS

```
Primary:    startMonitoringSignificantLocationChanges()
Secondary:  Timer.scheduledTimer() → requestLocation()
Background: BGAppRefreshTask for timer re-scheduling
```

| Aspect | Detail |
|--------|--------|
| Minimum interval | ~60 seconds |
| Blue arrow | No — significant location changes don't show it |
| GPS indicator | Brief arrow during fix only |
| App kill survival | ✅ Significant location changes re-launch app |
| Background refresh | ✅ Via `BGAppRefreshTask` |

---

## Killed-State Recovery

| Scenario | WorkManager | Foreground Service | iOS |
|----------|------------|-------------------|-----|
| App swiped | Re-scheduled | Service restarts | Re-launched by OS |
| OS kills (OOM) | Survives | `START_STICKY` | Re-launched |
| Device reboot | `BootReceiver` | `BootReceiver` | Significant location change |
| Force-stop | ❌ Dead | ❌ Dead | ❌ Dead |

> **Note**: Force-stop (Settings → Force Stop) terminates all background
> mechanisms on both platforms. This is by design — the user has explicitly
> revoked background execution.

---

## Configuration Examples

### Fleet Check-In (Every 15 Minutes)

```dart
GeoConfig(
  periodicLocationInterval: 900,
  periodicDesiredAccuracy: DesiredAccuracy.medium,
  periodicUseForegroundService: false,  // WorkManager, no notification
)
```

### Active Delivery (Every 5 Minutes)

```dart
GeoConfig(
  periodicLocationInterval: 300,
  periodicDesiredAccuracy: DesiredAccuracy.high,
  periodicUseForegroundService: true,   // Needs FG service for < 15 min
)
```

### Low-Power Asset Tracking (Every Hour)

```dart
GeoConfig(
  periodicLocationInterval: 3600,
  periodicDesiredAccuracy: DesiredAccuracy.low,   // Cell-only, minimal battery
  periodicUseForegroundService: false,
)
```

### Precise Timing (Exact Alarms)

```dart
GeoConfig(
  periodicLocationInterval: 1800,       // Every 30 minutes, exactly
  periodicDesiredAccuracy: DesiredAccuracy.medium,
  periodicUseForegroundService: false,
  periodicUseExactAlarms: true,          // Don't let WorkManager defer
)
```

---

## Battery Comparison

Approximate battery drain for 8-hour periods (varies by device and conditions):

| Mode | Interval | Estimated Drain |
|------|----------|----------------|
| Continuous (high accuracy) | — | 25–40% |
| Periodic | 1 min | 8–12% |
| Periodic | 5 min | 3–5% |
| Periodic | 15 min | 1–3% |
| Periodic | 1 hr | < 1% |

---

## Switching Between Modes

```dart
// Start continuous tracking
await tl.Tracelet.start(mode: tl.TrackingMode.location);

// Switch to periodic when app goes to background
await tl.Tracelet.start(mode: tl.TrackingMode.periodic);

// Switch back to continuous
await tl.Tracelet.start(mode: tl.TrackingMode.location);
```

---

## Android Manifest Requirements

When using foreground service mode, ensure your `AndroidManifest.xml` includes:

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
```

For exact alarms (API 31+):

```xml
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
```

---

## Related Guides

- [Background Tracking](BACKGROUND-TRACKING.md) — Continuous background tracking
- [Battery Budget](BATTERY-BUDGET.md) — Automatic battery-aware parameter tuning
- [Configuration](CONFIGURATION.md) — All config groups with property tables
- [Install Android](INSTALL-ANDROID.md) — Android setup and permissions
- [Install iOS](INSTALL-IOS.md) — iOS setup and capabilities
