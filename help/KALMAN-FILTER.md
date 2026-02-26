# Kalman Filter — GPS Smoothing

Tracelet includes a built-in **Extended Kalman Filter (EKF)** that smooths raw
GPS coordinates in real time. It removes jitter, absorbs sudden jumps, and
produces cleaner paths without adding latency — useful for map rendering,
distance calculations, and trip routes.

---

## What Is a Kalman Filter?

A Kalman filter is a mathematical algorithm that fuses noisy measurements (GPS
fixes) with a motion model (constant-velocity prediction) to estimate the
device's "true" position more accurately than either source alone.

### How It Works

1. **Predict** — between GPS fixes the filter predicts where the device should
   be, based on its last known velocity and elapsed time.
2. **Update** — when a new GPS fix arrives, the filter blends the prediction
   with the measurement, weighting each by its uncertainty:
   - High GPS accuracy (low `horizontalAccuracy`) → trust the measurement more
   - Low GPS accuracy (high `horizontalAccuracy`) → trust the prediction more
3. **Output** — the corrected position is emitted as the location event and
   persisted to the database.

### State Vector

The filter tracks four values simultaneously:

| Variable | Description        |
|----------|--------------------|
| `x`      | East-west position (meters from origin) |
| `y`      | North-south position (meters from origin) |
| `vx`     | East-west velocity (m/s) |
| `vy`     | North-south velocity (m/s) |

The origin is set to the first GPS fix after each `start()` call. All lat/lng
values are converted to a local meter grid using equirectangular projection,
processed through the filter, and converted back to lat/lng for output.

### Noise Model

- **Process noise** (`Q`): 3.0 m/s² — models acceleration uncertainty
  (walking / driving / transit). The filter adapts automatically to the actual
  time gap between fixes.
- **Measurement noise** (`R`): `horizontalAccuracy²` — taken directly from the
  GPS chip. A fix with 5 m accuracy produces `R = 25 m²`; a fix with 50 m
  accuracy produces `R = 2500 m²`, causing the filter to rely more on
  prediction. Minimum clamped to `1.0` to avoid numerical collapse.

---

## How to Enable

Add `useKalmanFilter: true` to the `LocationFilter` in your config:

```dart
await Tracelet.ready(Config(
  geo: GeoConfig(
    distanceFilter: 10.0,
    filter: LocationFilter(
      useKalmanFilter: true,              // ← enable Kalman smoothing
      trackingAccuracyThreshold: 100,     // reject fixes > 100 m accuracy
      odometerAccuracyThreshold: 50,      // only add to odometer if ≤ 50 m
    ),
  ),
));
await Tracelet.start();
```

No additional parameters are required. The filter auto-tunes based on GPS
accuracy reported by the platform.

---

## What Gets Smoothed

| Data                  | Smoothed? | Details |
|-----------------------|-----------|---------|
| Location events       | ✅ Yes    | `latitude`/`longitude` in `onLocation` events |
| Persisted locations   | ✅ Yes    | Database records use smoothed coords |
| One-shot positions    | ❌ No     | `getCurrentPosition()` returns raw GPS |
| Watch positions       | ✅ Yes    | `watchPosition` events use smoothed coords |
| Odometer distance     | ❌ No     | Computed from **raw** coordinates for accuracy |
| Distance filter       | ❌ No     | Applied before smoothing for consistent gating |
| Geofence proximity    | ✅ Yes    | When high-accuracy mode is active, proximity uses the smoothed position |

> **Design rationale:** Distance/odometer calculations use raw coordinates
> because the Kalman filter introduces a slight lag — using smoothed coords for
> distance gating could incorrectly accept or reject locations near the
> threshold.

---

## When to Use It

### Recommended

- **Map rendering** — eliminates GPS jitter that creates zigzag polylines,
  especially when stationary or walking slowly.
- **Trip routes** — produces cleaner route polylines for trip summaries.
- **Fleet dashboards** — reduces visual noise on tracking maps.
- **Urban canyons** — multipath reflections from buildings cause sporadic GPS
  jumps; the filter absorbs them.

### Not Recommended

- **Surveying / precision mapping** — the filter smooths real position changes
  too, which may mask small but real movements.
- **Indoor tracking** — the constant-velocity model doesn't apply indoors where
  GPS is unreliable and movements are non-linear.
- **Very high-speed vehicles** — at >200 km/h, the default process noise may
  not track rapid course changes fast enough (airplane, high-speed rail).

---

## Behavior Details

### Reset Conditions

The filter resets its state in these situations:

| Event                 | What Happens |
|-----------------------|-------------|
| `Tracelet.start()`    | Full reset — origin, state, covariance |
| `Tracelet.stop()`     | No explicit reset (irrelevant, no updates) |
| App restart / reboot  | Full reset on next `start()` |
| Large time gap (>30s) | The filter naturally adapts — prediction uncertainty grows, so the next fix is trusted more heavily |

There is **no distance-based reset**. If the device teleports (e.g., user
boards a plane), the filter will converge on the new location within 2–3 fixes
as the high prediction uncertainty makes it defer to measurements.

### Latency

The filter adds **zero latency**. Each GPS fix produces an output immediately.
The smoothed position is a weighted average of the prediction and the current
fix — it doesn't buffer or delay updates.

### Battery Impact

**None.** The filter is a pure math operation on coordinates already received.
It doesn't request additional GPS fixes, change location accuracy settings, or
wake the CPU. Computational cost is negligible (~0.01 ms per fix for 4 matrix
multiplications).

---

## Platform Implementation

| Platform | File | Algorithm |
|----------|------|-----------|
| All      | `kalman_filter.dart` | Shared Dart Extended Kalman filter with 4×4 state/covariance matrices |

The Kalman filter runs in shared Dart code (`tracelet_platform_interface/lib/src/algorithms/kalman_filter.dart`), so it works identically on Android, iOS, web, and future desktop platforms. The implementation uses manual matrix math (no external linear algebra library). The 4×4 matrices are stored as 16-element lists for performance.

---

## Debugging

When `debug: true` and `logLevel: LogLevel.verbose` are set, the filter logs
each update to the platform console:

**Android (Logcat):**
```
D/LocationEngine: Kalman filter: raw=(37.7749, -122.4194) → smoothed=(37.7748, -122.4193)
```

**iOS (Console):**
```
[Tracelet] Kalman filter: raw=(37.7749, -122.4194) → smoothed=(37.7748, -122.4193)
```

---

## FAQ

**Q: Does it affect battery life?**
No. It's a pure computation on already-received GPS data.

**Q: Can I adjust the smoothing strength?**
Not directly. The filter auto-tunes smoothing based on GPS accuracy. High GPS
accuracy → less smoothing. Low GPS accuracy → more smoothing. The process
noise constant (3.0 m/s²) provides a good balance for walking, cycling, and
driving.

**Q: Does it work with `useSignificantChangesOnly`?**
Yes, but the large time gaps between significant-change fixes (minutes) mean
the filter's prediction is very uncertain at each update. It will still smooth
individual fixes but won't interpolate between them.

**Q: Is it safe to use with `geofenceModeHighAccuracy`?**
Yes. The high-accuracy geofence evaluator uses the smoothed coordinates, which
improves enter/exit transition accuracy.

**Q: What happens if the first GPS fix has very low accuracy (e.g., 300 m)?**
The filter initializes its origin with whatever coordinates arrive first. The
high measurement noise (300² = 90,000 m²) means the initial covariance will be
large. As better fixes arrive, the filter rapidly converges (typically 2–3
fixes).
