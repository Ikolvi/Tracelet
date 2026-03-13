# Battery Budget Engine

Tracelet's Battery Budget Engine is a feedback control loop that automatically
adjusts tracking parameters — `distanceFilter`, `desiredAccuracy`, and
periodic interval — to stay within a configurable battery drain budget.

Unlike [Adaptive Sampling](ADAPTIVE-SAMPLING.md) which reacts to activity and
speed in real-time, the Battery Budget Engine measures **actual battery drain**
over time and adjusts parameters to meet a **target drain rate** (%/hour).

---

## Quick Start

```dart
import 'package:tracelet/tracelet.dart' as tl;

await tl.Tracelet.ready(tl.Config(
  geo: tl.GeoConfig(
    batteryBudgetPerHour: 3.0,  // Target: max 3% battery drain per hour
    distanceFilter: 10.0,       // Initial distance filter (will be adjusted)
    desiredAccuracy: tl.DesiredAccuracy.high,  // Initial accuracy (will be adjusted)
  ),
));

// Listen for budget adjustment events
tl.Tracelet.onBudgetAdjustment((event) {
  print('Battery drain: ${event.currentBatteryDrain}%/hr');
  print('Target: ${event.targetBudget}%/hr');
  print('New distance filter: ${event.newDistanceFilter}m');
  print('New accuracy: ${event.newDesiredAccuracy}');
  if (event.newPeriodicInterval != null) {
    print('New periodic interval: ${event.newPeriodicInterval}s');
  }
});

await tl.Tracelet.start();
```

---

## How It Works

The engine operates on a **measure → compare → adjust** cycle:

```
1. Measure actual battery drain over a sampling window (~5 minutes)
2. Compare measured drain against the configured target
3. If over budget → increase distanceFilter, degrade accuracy
4. If under budget → decrease distanceFilter, improve accuracy
5. Repeat
```

### Sampling

Every ~5 minutes, the engine reads the current battery level and calculates
the drain rate in percentage points per hour. The first sample is discarded
(baseline establishment).

### Adjustment Logic

| Condition | Action |
|-----------|--------|
| Drain > target | Increase `distanceFilter` by 20%, degrade accuracy one level |
| Drain < target × 0.7 | Decrease `distanceFilter` by 10%, improve accuracy one level |
| Drain within range | No change |

### Accuracy Levels (Ordered by Battery Cost)

| Index | Level | Battery Impact |
|-------|-------|----------------|
| 0 | `high` | Highest — GPS + GLONASS |
| 1 | `medium` | Medium — WiFi + cell |
| 2 | `low` | Low — cell only |
| 3 | `veryLow` | Very low — coarse |
| 4 | `passive` | Lowest — piggyback on other apps |

### Parameter Bounds

The engine clamps adjusted values to prevent extreme behavior:

| Parameter | Min | Max |
|-----------|-----|-----|
| `distanceFilter` | 10 m | 1000 m |
| `accuracyIndex` | 0 (high) | 4 (passive) |
| `periodicInterval` | 60 s | 43200 s (12 hrs) |

---

## Configuration

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `batteryBudgetPerHour` | `double` | `0.0` | Target max battery drain per hour (%). `0` = disabled. |

### Recommended Values

| Use Case | Budget | Notes |
|----------|--------|-------|
| Fleet tracking | 2.0–3.0 | Good balance for 8+ hour shifts |
| Fitness app | 4.0–5.0 | Higher resolution for workout tracking |
| Asset tracking | 1.0–2.0 | Long battery life for unattended devices |
| Delivery driver | 3.0–4.0 | Dense tracking during active deliveries |

---

## BudgetAdjustmentEvent

When the engine adjusts parameters, it emits a `BudgetAdjustmentEvent`:

```dart
class BudgetAdjustmentEvent {
  final double currentBatteryDrain;   // Measured drain (%/hr)
  final double targetBudget;          // Configured target (%/hr)
  final double newDistanceFilter;     // Adjusted distance filter (m)
  final String newDesiredAccuracy;    // Adjusted accuracy level name
  final int? newPeriodicInterval;     // Adjusted interval (s), or null
}
```

### Example: Dashboard Display

```dart
tl.Tracelet.onBudgetAdjustment((event) {
  final status = event.currentBatteryDrain > event.targetBudget
      ? '⚠️ Over budget'
      : '✅ Within budget';
  print('$status: ${event.currentBatteryDrain.toStringAsFixed(1)}%/hr '
      '(target: ${event.targetBudget}%/hr)');
});
```

---

## Interaction with Other Features

| Feature | Behavior |
|---------|----------|
| Adaptive Sampling | Battery budget takes priority — it overrides adaptive mode adjustments |
| Elasticity | Budget engine adjusts the base filter; elasticity multiplier still applies |
| Periodic Mode | Budget engine may adjust the periodic interval within bounds |
| Manual `setConfig()` | Calling `setConfig()` with new values resets the budget engine |

---

## Troubleshooting

### Budget Engine Not Adjusting

- Ensure `batteryBudgetPerHour > 0` in your config — `0` disables the engine.
- Allow at least 10 minutes for initial calibration (2 sampling windows).
- Some devices report battery in 1% steps, limiting precision for small budgets.

### Accuracy Stuck at Passive

This indicates the device consistently drains more than the budget allows even
at the lowest tracking resolution. Consider:

1. Increasing the `batteryBudgetPerHour` value.
2. Checking for other apps consuming battery.
3. Using periodic mode for lower-duty-cycle tracking.

---

## Related Guides

- [Adaptive Sampling](ADAPTIVE-SAMPLING.md) — Activity/battery/speed-based distance filter
- [Configuration](CONFIGURATION.md) — All config groups with property tables
- [Health Check](HEALTH-CHECK.md) — Diagnostic API including battery state
