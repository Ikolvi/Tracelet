# Carbon Estimator

Tracelet's Carbon Estimator calculates real-time CO₂ emissions for tracked
trips based on transport mode and distance travelled. Emission factors follow
**EU EEA 2024 averages** by default and can be customized per application.

---

## Quick Start

```dart
import 'package:tracelet/tracelet.dart' as tl;

// Create estimator (uses default EU EEA 2024 emission factors)
final estimator = tl.CarbonEstimator();

// Start a trip
estimator.startTrip();

// Feed locations as they arrive
tl.Tracelet.onLocation((location) {
  estimator.onLocationReceived(location.latitude, location.longitude);
});

// Update transport mode from activity recognition
tl.Tracelet.onActivityChange((activity) {
  estimator.setActivity(activity.type);  // e.g. 'in_vehicle', 'walking'
});

// End trip and get summary
final summary = estimator.endTrip();
if (summary != null) {
  print('Distance: ${(summary.totalDistanceMeters / 1000).toStringAsFixed(1)} km');
  print('CO₂: ${summary.totalCarbonGrams.toStringAsFixed(0)} g');
  print('Mode: ${summary.dominantMode}');
}
```

---

## How It Works

### Carbon Calculation

```
CO₂ (grams) = (distance in meters / 1000) × emission factor (gCO₂/km)
```

Distance between consecutive GPS points is calculated using the **Haversine
formula**. Each segment's distance accumulates under the current transport mode.

### Trip Lifecycle

```
startTrip()
  ↓
onLocationReceived()   ← repeated, accumulates distance
setActivity()          ← updates current transport mode
  ↓
endTrip() → TripCarbonSummary
```

---

## Emission Factors

Default factors follow EU European Environment Agency 2024 averages:

| Activity Type | gCO₂/km | Source |
|---------------|---------|--------|
| `in_vehicle` | 192.0 | EU average new passenger car |
| `bus` | 89.0 | EU urban bus average |
| `train` | 41.0 | EU rail average |
| `on_bicycle` | 0.0 | Zero emission |
| `walking` | 0.0 | Zero emission |
| `running` | 0.0 | Zero emission |
| `on_foot` | 0.0 | Zero emission |
| `unknown` | 96.0 | Conservative fallback (half of car) |

### Custom Emission Factors

Override defaults for your specific use case:

```dart
final estimator = CarbonEstimator(
  emissionFactors: {
    'in_vehicle': 120.0,   // Electric vehicle fleet
    'bus': 68.0,           // Modern hybrid buses
    'train': 25.0,         // Electrified rail network
    'e_scooter': 15.0,     // Custom mode
  },
);
```

Unspecified modes fall back to the default table, then to `unknown` (96.0 g/km).

---

## API Reference

### CarbonEstimator

| Method | Returns | Description |
|--------|---------|-------------|
| `CarbonEstimator({emissionFactors})` | — | Create with optional custom factors |
| `startTrip()` | `void` | Begin a new trip, reset per-trip accumulators |
| `setActivity(activityType)` | `void` | Update current transport mode |
| `onLocationReceived(lat, lng)` | `void` | Feed a GPS point, accumulate distance |
| `endTrip()` | `TripCarbonSummary?` | End trip, return summary (null if no data) |
| `getCumulativeReport()` | `Map<String, Object?>` | All-trips cumulative summary |
| `resetCumulative()` | `void` | Clear cumulative counters, keep active trip |
| `reset()` | `void` | Full reset (trip + cumulative) |

### TripCarbonSummary

| Field | Type | Description |
|-------|------|-------------|
| `totalCarbonGrams` | `double` | Total CO₂ emitted during trip |
| `totalDistanceMeters` | `double` | Total distance travelled |
| `carbonByMode` | `Map<String, double>` | CO₂ (grams) per transport mode |
| `distanceByMode` | `Map<String, double>` | Distance (meters) per transport mode |
| `dominantMode` | `String` | Mode covering the most distance |

### Cumulative Report

```dart
final report = estimator.getCumulativeReport();
// {
//   'totalCarbonGrams': 4520.0,
//   'totalTrips': 12,
//   'carbonByMode': {'in_vehicle': 3800.0, 'bus': 720.0},
//   'distanceByMode': {'in_vehicle': 19791.0, 'bus': 8089.0},
// }
```

---

## Usage Patterns

### Dashboard Display

```dart
estimator.startTrip();

tl.Tracelet.onLocation((loc) {
  estimator.onLocationReceived(loc.latitude, loc.longitude);

  // Update UI with running totals
  final report = estimator.getCumulativeReport();
  updateDashboard(
    carbon: report['totalCarbonGrams'] as double,
    trips: report['totalTrips'] as int,
  );
});
```

### Weekly Carbon Report

```dart
// Accumulate across multiple trips
for (final trip in weeklyTrips) {
  estimator.startTrip();
  for (final point in trip.points) {
    estimator.setActivity(point.activity);
    estimator.onLocationReceived(point.lat, point.lng);
  }
  estimator.endTrip();
}

final weekly = estimator.getCumulativeReport();
print('Weekly CO₂: ${weekly['totalCarbonGrams']}g across ${weekly['totalTrips']} trips');
estimator.resetCumulative();
```

### Fleet Sustainability Tracking

```dart
// Custom factors for company fleet
final fleetEstimator = CarbonEstimator(
  emissionFactors: {
    'in_vehicle': 0.0,     // All-electric fleet
    'bus': 45.0,           // Company shuttle (hybrid)
  },
);
```

---

## Activity Recognition Integration

The carbon estimator relies on accurate activity classification. Tracelet
provides two motion detection modes:

| Mode | API | Permission Required | Activity Types |
|------|-----|---------------------|----------------|
| Full | Activity Recognition / CMMotionActivity | Yes | `in_vehicle`, `on_bicycle`, `walking`, `running`, `on_foot` |
| Accelerometer-only | Hardware sensors | No | `stationary`, `moving` (no vehicle classification) |

For accurate carbon estimation, use **full mode** (default) to distinguish
vehicle types. With accelerometer-only mode, all movement defaults to `unknown`
(96 g/km).

---

## Related Guides

- [Trip Detection](TRIP-DETECTION.md) — Automatic trip start/stop
- [Configuration](CONFIGURATION.md) — All config groups with property tables
- [Background Tracking](BACKGROUND-TRACKING.md) — Ensuring continuous tracking
