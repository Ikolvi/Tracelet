# Sparse Updates

Sparse updates provide **app-level location deduplication**, reducing database
writes and event dispatches by recording only locations that exceed a minimum
distance threshold from the last recorded point.

---

## Quick Start

```dart
import 'package:tracelet/tracelet.dart' as tl;

await tl.Tracelet.ready(tl.Config(
  geo: tl.GeoConfig(
    enableSparseUpdates: true,
    sparseDistanceThreshold: 50.0,   // Record only when 50m+ from last point
    sparseMaxIdleSeconds: 300,       // Force update every 5 min even if stationary
  ),
));

await tl.Tracelet.start();
```

---

## How It Works

### Decision Flow

```
New location received from platform
  ↓
Calculate distance to last recorded location
  ↓
Distance ≥ sparseDistanceThreshold?
  YES → Record, dispatch to listeners, sync
  NO  → Check idle timeout
         ↓
         Time since last record ≥ sparseMaxIdleSeconds?
           YES → Force record ("heartbeat")
           NO  → Drop silently
```

### Example

With `sparseDistanceThreshold: 50` and `sparseMaxIdleSeconds: 300`:

| Time | Distance from last | Action |
|------|--------------------|--------|
| 10:00:00 | — | First location → **Record** |
| 10:00:05 | 3 m | Below 50m → **Drop** |
| 10:00:10 | 8 m | Below 50m → **Drop** |
| 10:00:30 | 52 m | Above 50m → **Record** |
| 10:00:35 | 5 m | Below 50m → **Drop** |
| 10:05:35 | 12 m | Below 50m but 5 min idle → **Force record** |

---

## Sparse Updates vs. distanceFilter

These two features operate at different levels and serve different purposes:

| Aspect | `distanceFilter` | Sparse Updates |
|--------|-----------------|----------------|
| **Level** | Platform / native GPS subsystem | Dart app-level post-processing |
| **Applied** | Before location delivered to app | After location received by app |
| **Controls** | GPS radio wake-up frequency | Database write frequency |
| **Battery** | Directly reduces GPS power usage | No battery impact (app-level filter) |
| **Fallback** | None — platform-enforced | Forced update via `maxIdleSeconds` |
| **Relationship** | Coarse filter | Fine filter on top of `distanceFilter` |

### When to Use Each

| Scenario | Recommendation |
|----------|----------------|
| Reduce GPS battery drain | Use `distanceFilter` |
| Reduce database/sync volume | Use sparse updates |
| Both battery and storage savings | Use both together |

### Combined Example

```dart
GeoConfig(
  distanceFilter: 10.0,            // Platform: wake GPS every 10m
  enableSparseUpdates: true,
  sparseDistanceThreshold: 50.0,   // App: record only every 50m
)
```

This means GPS wakes every 10 meters (platform-level), but locations are
only written to the database and dispatched to listeners when the device
moves 50+ meters from the last recorded point.

---

## Configuration

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `enableSparseUpdates` | `bool` | `false` | Enable app-level location deduplication |
| `sparseDistanceThreshold` | `double` | `50.0` | Minimum meters before recording a new location |
| `sparseMaxIdleSeconds` | `int` | `300` | Max seconds between forced updates (`0` = disabled) |

### Threshold Guidelines

| Use Case | Threshold | Idle Timeout | Notes |
|----------|-----------|-------------|-------|
| Fleet tracking | 100–200 m | 600 s | Reduce server load for large fleets |
| Fitness tracking | 20–50 m | 300 s | Balance detail vs. data volume |
| Asset monitoring | 200–500 m | 1800 s | Minimal updates for stationary assets |
| Delivery tracking | 50–100 m | 300 s | Good resolution at stops |

### Idle Timeout Behavior

The `sparseMaxIdleSeconds` parameter ensures periodic "heartbeat" updates even
when the device is stationary:

- **`300`** (default): Force a record every 5 minutes — good for live dashboards.
- **`0`**: Disabled — no forced updates when stationary. Use only if you don't
  need real-time presence confirmation.
- **`1800`**: Every 30 minutes — suitable for low-priority asset tracking.

---

## Impact on Other Features

| Feature | Behavior |
|---------|----------|
| HTTP Sync | Only recorded locations are synced — fewer HTTP requests |
| Audit Trail | Hash chain covers only recorded locations |
| Delta Encoding | Operates on recorded locations only; larger deltas improve compression |
| Privacy Zones | Applied before sparse filter — suppressed locations never reach dedup |
| Geofence Events | Not affected — geofence enter/exit events bypass sparse filtering |

---

## Monitoring

Track how many locations are being filtered:

```dart
// Compare platform events vs. recorded locations
int platformEvents = 0;
int recordedLocations = 0;

tl.Tracelet.onLocation((location) {
  recordedLocations++;
  final ratio = recordedLocations / platformEvents;
  print('Recording ${(ratio * 100).toStringAsFixed(0)}% of GPS events');
});
```

---

## Related Guides

- [Adaptive Sampling](ADAPTIVE-SAMPLING.md) — Activity-based distance filter adjustment
- [Battery Budget](BATTERY-BUDGET.md) — Automatic parameter tuning for battery targets
- [Configuration](CONFIGURATION.md) — All config groups with property tables
