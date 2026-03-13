# tracelet_platform_interface

A common platform interface for the [Tracelet](https://pub.dev/packages/tracelet) background geolocation plugin.

This package provides the abstract classes and types that the platform-specific implementations (`tracelet_android`, `tracelet_ios`, `tracelet_web`) implement.

It also contains shared Dart algorithms used by all platforms: `LocationProcessor` (distance/accuracy/speed/mock filtering), `KalmanLocationFilter` (GPS smoothing), `AdaptiveSamplingEngine` (activity/battery/speed-based distance filter), `GeofenceEvaluator`, `TripManager`, `ScheduleParser`, `PersistDecider`, and `GeoUtils`. See `MockDetectionLevel` enum and `LocationProcessor` mock detection for cross-platform spoof rejection.

### New in 1.1.0

- **`BatteryBudgetEngine`** — feedback control loop that adjusts `distanceFilter`, `desiredAccuracy`, and periodic interval to maintain a configurable battery budget (%/hr). Emits `BudgetAdjustmentEvent` with current drain, target, and new parameters.
- **`CarbonEstimator`** — per-trip and cumulative CO₂ emission calculator using mode-specific factors (gCO₂/km). Returns `TripCarbonSummary` with emissions and distance by transport mode.
- **`DeltaEncoder`** — batch location compression codec achieving 60–80% payload reduction via delta encoding with configurable coordinate precision.
- **`RTree<T>`** — generic R-tree spatial index for O(log n) geofence proximity queries. Supports `queryCircle()` and `queryBBox()` with Haversine post-filtering.

The OEM Compatibility API (`getSettingsHealth()`, `openOemSettings()`) is defined here as abstract methods, with platform implementations providing manufacturer-specific behavior.

## Usage

**You should not depend on this package directly.** Instead, depend on [`tracelet`](https://pub.dev/packages/tracelet) which automatically includes the correct platform implementation.

This package is only relevant if you are writing a custom platform implementation for Tracelet.

## Related Packages

| Package | Description |
|---|---|
| [`tracelet`](https://pub.dev/packages/tracelet) | App-facing Dart API — the only package you depend on |
| [`tracelet_android`](https://pub.dev/packages/tracelet_android) | Android implementation |
| [`tracelet_ios`](https://pub.dev/packages/tracelet_ios) | iOS implementation |
| [`tracelet_web`](https://pub.dev/packages/tracelet_web) | Web implementation |

## More Information

- [GitHub Repository](https://github.com/Ikolvi/Tracelet)
- [Documentation](https://github.com/Ikolvi/Tracelet/tree/main/help)
- [Issue Tracker](https://github.com/Ikolvi/Tracelet/issues)
