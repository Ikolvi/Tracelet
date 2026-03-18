# Dead Reckoning

Dead reckoning provides **inertial navigation** when GPS signal is temporarily
lost. Using the device's accelerometer, gyroscope, and compass, Tracelet
estimates position changes during GPS gaps — tunnels, parking structures,
indoor transitions, and urban canyons.

---

## Quick Start

```dart
import 'package:tracelet/tracelet.dart' as tl;

await tl.Tracelet.ready(tl.Config(
  geo: tl.GeoConfig(
    enableDeadReckoning: true,
    deadReckoningActivationDelay: 10,   // seconds without GPS before activating
    deadReckoningMaxDuration: 120,      // max seconds of IMU estimation
  ),
));

await tl.Tracelet.start();
// Dead reckoning activates automatically when GPS is lost
```

---

## How It Works

### Activation Flow

```
GPS signal lost
  ↓
Wait deadReckoningActivationDelay seconds (default: 10s)
  ↓
Still no GPS? → Activate IMU dead reckoning
  ↓
Estimate position using accelerometer + gyroscope + compass
  ↓
Continue for up to deadReckoningMaxDuration seconds
  ↓
GPS returns → Resume standard tracking
   OR
Max duration reached → Stop estimating, wait for GPS
```

### IMU Sensors Used

| Sensor | Purpose | Platform API |
|--------|---------|-------------|
| Accelerometer | Linear displacement estimation | Android: `SensorManager` / iOS: `CMMotionManager` |
| Gyroscope | Rotation and heading change | Android: `SensorManager` / iOS: `CMMotionManager` |
| Compass | Absolute bearing reference | Android: `SensorManager` / iOS: `CLHeading` |

### Drift Characteristics

IMU-based position estimation accumulates drift over time due to sensor noise
and double-integration errors:

| Duration | Typical Drift | Reliability |
|----------|--------------|-------------|
| 0–30 s | < 5 m | High |
| 30–60 s | 5–20 m | Moderate |
| 60–120 s | 20–100 m | Low |
| > 120 s | Unreliable | Not recommended |

The default `deadReckoningMaxDuration` of 120 seconds balances coverage for
common GPS gaps (tunnels, parking structures) against drift accumulation.

---

## Configuration

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `enableDeadReckoning` | `bool` | `false` | Activate inertial navigation during GPS loss |
| `deadReckoningActivationDelay` | `int` | `10` | Seconds without GPS fix before IMU takeover |
| `deadReckoningMaxDuration` | `int` | `120` | Maximum seconds of dead reckoning estimation |

### Activation Delay

The delay prevents unnecessary IMU activation during brief GPS interruptions
(e.g., passing under a bridge). Recommended values:

| Use Case | Delay | Rationale |
|----------|-------|-----------|
| Vehicle tracking | 5–10 s | Tunnels need fast handover |
| Pedestrian | 10–15 s | Brief indoor transitions |
| Asset tracking | 15–30 s | Conservative, minimize false activations |

### Max Duration

| Use Case | Duration | Rationale |
|----------|----------|-----------|
| Short tunnels | 60 s | Minimal drift, high confidence |
| Parking structures | 120 s | Default — covers most garage traversals |
| Long tunnels | 180 s | Accept higher drift for coverage |

---

## Battery Impact

Dead reckoning has **minimal battery impact** compared to GPS:

| Component | Power Draw |
|-----------|-----------|
| GPS radio | ~150 mW (active) |
| Accelerometer | ~1–3 mW |
| Gyroscope | ~5–10 mW |
| Compass | ~1–2 mW |

IMU sensors draw roughly **5–10%** of the power used by GPS. Dead reckoning
only activates during GPS gaps, so the overall battery impact is negligible.

---

## Querying Dead Reckoning State

Use `getDeadReckoningState()` to check if dead reckoning is currently active
and inspect its estimation accuracy:

```dart
final state = await Tracelet.getDeadReckoningState();
if (state != null) {
  final active = state['active'] as bool;       // true if currently estimating
  final elapsed = state['elapsed'] as int;       // seconds since activation
  final accuracy = state['estimatedAccuracy'] as double; // estimated accuracy (meters)

  print('DR active: $active');
  print('Elapsed: ${elapsed}s');
  print('Estimated accuracy: ${accuracy.toStringAsFixed(1)}m');
} else {
  print('Dead reckoning is not active');
}
```

### Return Value

Returns `Map<String, Object?>?` — `null` if dead reckoning is disabled or
GPS is available (DR engine not initialized).

| Field | Type | Description |
| --- | --- | --- |
| `active` | `bool` | `true` if currently estimating position via IMU |
| `elapsed` | `int` | Seconds since dead reckoning activated |
| `estimatedAccuracy` | `double` | Estimated position accuracy in meters |

### Accuracy Degradation

The `estimatedAccuracy` field reflects IMU drift accumulation over time:

| Activity | Formula | Example (30s) |
| --- | --- | --- |
| Pedestrian | 5 + 1 × elapsed | 35 m |
| Vehicle | 10 + 3 × elapsed | 100 m |

> **Tip:** Use `estimatedAccuracy` to visually indicate confidence in your UI —
> for example, expanding an accuracy circle on the map as drift accumulates.

### Polling Example

For real-time UI updates, poll the state at regular intervals:

```dart
Timer.periodic(Duration(seconds: 5), (_) async {
  final state = await Tracelet.getDeadReckoningState();
  if (state != null && state['active'] == true) {
    updateDRIndicator(
      elapsed: state['elapsed'] as int,
      accuracy: state['estimatedAccuracy'] as double,
    );
  }
});
```

---

## Location Events During Dead Reckoning

Locations emitted during dead reckoning are marked so your application can
distinguish them from GPS-derived positions:

```dart
tl.Tracelet.onLocation((location) {
  if (location.mock) {
    // This may be a dead-reckoned position
    print('Estimated position: ${location.latitude}, ${location.longitude}');
  }
});
```

---

## Use Cases

### Delivery Tracking

Maintain continuous tracking when drivers enter underground loading docks
or parking garages:

```dart
GeoConfig(
  enableDeadReckoning: true,
  deadReckoningActivationDelay: 5,   // Fast activation for vehicles
  deadReckoningMaxDuration: 180,     // Cover long parking garages
)
```

### Transit Apps

Track passengers through subway stations and tunnels:

```dart
GeoConfig(
  enableDeadReckoning: true,
  deadReckoningActivationDelay: 10,
  deadReckoningMaxDuration: 300,     // Longer for subway tunnels
)
```

### Fitness Tracking

Handle brief GPS loss during runs through underpasses or tree cover:

```dart
GeoConfig(
  enableDeadReckoning: true,
  deadReckoningActivationDelay: 15,  // Avoid false starts
  deadReckoningMaxDuration: 60,      // Short — GPS usually returns quickly
)
```

---

## Limitations

- **Not a GPS replacement** — dead reckoning is a bridge for temporary signal
  loss, not a substitute for satellite navigation.
- **Drift accumulates** — accuracy degrades with duration. Keep max duration
  as short as practical for your use case.
- **Device-dependent** — sensor quality varies between devices. Higher-end
  devices with better IMU hardware produce more accurate estimates.
- **Stationary detection** — if the device is stationary during GPS loss,
  dead reckoning correctly reports no movement.

---

## Related Guides

- [Kalman Filter](KALMAN-FILTER.md) — GPS noise smoothing
- [Background Tracking](BACKGROUND-TRACKING.md) — Ensuring continuous tracking
- [Configuration](CONFIGURATION.md) — All config groups with property tables
- [Mock Detection](MOCK-DETECTION.md) — Detecting spoofed locations
