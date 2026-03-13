## 1.1.0

### New Algorithms

- **FEAT**: Add `BatteryBudgetEngine` — a pure-Dart feedback control loop that automatically adjusts `distanceFilter`, `desiredAccuracy`, and periodic interval to stay within a configurable battery budget (% drain/hour). Compares measured drain against target every 5 minutes; if over budget, increases distance filter (up to 1000 m) and degrades accuracy (high → medium → low → veryLow → passive); if under budget, tightens distance filter (down to 10 m) and improves accuracy. Includes `BudgetAdjustmentEvent` with `currentBatteryDrain`, `targetBudget`, `newDistanceFilter`, `newDesiredAccuracy`, and optional `newPeriodicInterval`.
- **FEAT**: Add `CarbonEstimator` — per-trip and cumulative CO₂ emission calculator using mode-specific emission factors (gCO₂/km). Default factors use EU EEA 2024 averages: car = 192, bus = 89, train = 41, walking/cycling = 0. Accepts GPS coordinates + activity type from activity recognition, accumulates distance per mode via Haversine, and provides structured `TripCarbonSummary` with `totalCarbonGrams`, `totalDistanceMeters`, `carbonByMode`, `distanceByMode`, and `dominantMode`. Tracks cumulative totals across multiple trips for fleet/compliance reporting.
- **FEAT**: Add `DeltaEncoder` — batch location compression codec using delta encoding. First location in a batch is transmitted in full (marked `ref: true`); subsequent positions sent as deltas with shortened field names (`la` = Δlatitude, `lo` = Δlongitude, `t` = Δtime in seconds, `s` = Δspeed, `h` = Δheading with shortest-arc normalization, `a` = Δaccuracy, `al` = Δaltitude, `b` = Δbattery). Coordinate precision configurable (5 = ~1.1 m, 6 = ~0.11 m). Symmetric `encode()`/`decode()` for bidirectional use. Achieves 60–80% payload reduction for high-frequency tracking batches.
- **FEAT**: Add `RTree<T>` — generic R-tree spatial index enabling O(log n) geofence proximity queries versus O(n) linear search. Supports `insert(lat, lng, radius, data)`, `remove(data)`, `queryCircle(lat, lng, radiusMeters)`, and `queryBBox(minLat, minLng, maxLat, maxLng)`. Uses quadratic split strategy, latitude-corrected degree-to-meter bbox conversion, and Haversine post-filtering for accurate circle queries. Handles 10,000+ geofences with sub-millisecond lookup times.

### Changes

- **FEAT**: Export `BatteryBudgetEngine`, `BudgetAdjustmentEvent`, `CarbonEstimator`, `TripCarbonSummary`, `DeltaEncoder`, and `RTree` from the `algorithms.dart` barrel file.
- **REFACTOR**: Update `GeofenceEvaluator` and `LocationProcessor` for improved algorithm integration with new sparse updates and dead reckoning configuration.

## 1.0.0

### 🎉 Stable Release

- **FEAT**: First stable release of `tracelet_platform_interface`.
- **REFACTOR**: Remove third-party company name references — use generic `flutter_background_geolocation` throughout.
- All APIs are finalized and production-ready.

## 0.12.0

### Performance Audit — Dart algorithm optimizations

- **PERF**: Use `Float64List` for Kalman filter state matrices, add `_pTemp` scratch buffer (D-C3).
- **PERF**: In-place `_p.fillRange()` in `Kalman.reset()` instead of re-allocating (D-M7).
- **PERF**: Bound `TripManager` waypoints list to 5000 entries (D-H3).
- **PERF**: Use `Queue<Map>` with O(1) `removeFirst()` instead of `List.removeAt(0)` O(n) for waypoint cap trimming (D-L2).
- **PERF**: Merge isPointInPolygon precondition check into main loop — validates each vertex inline (D-M2).
- **PERF**: Cache `_cachedInsideView` in `GeofenceEvaluator` with invalidation at all 6 mutation points (D-M4).
- **PERF**: Remove dead `num` branch in `_toDouble()` — `int`/`double` already cover all `num` subtypes (D-L1).
- **REFACTOR**: `matchesSchedule()` now delegates to `parse()` to eliminate duplicated parsing logic (D-L3).

## 0.11.4

- **CHORE**: Version bump for platform consistency.

## 0.11.3

- **CHORE**: Version bump for platform consistency.

## 0.11.2

- **DOCS**: Fix unresolved dartdoc references (`[GeoConfig]`, `[GeoConfig.periodicLocationInterval]`).
- **DOCS**: Add `example/example.dart` for pub.dev documentation score.

## 0.11.1

- **FEAT**: Add `canScheduleExactAlarms()` and `openExactAlarmSettings()` abstract methods to `TraceletPlatform` and MethodChannel implementations.

## 0.11.0

- **FEAT**: Add privacy zone abstract methods to `TraceletPlatform` and MethodChannel implementations.
- **FEAT**: Add audit trail abstract methods to `TraceletPlatform` and MethodChannel implementations.

## 0.10.0

- **FEAT**: Add `TrackingMode.periodic` enum value for periodic interval tracking.
- **FEAT**: Add `startPeriodic()` method to `TraceletPlatform` and `MethodChannelTracelet`.

## 0.9.1

- **CHORE**: Version bump for consistency.

## 0.9.0

* **FEAT**: `AdaptiveSamplingEngine` — multi-factor distance filter computation (activity type, battery level, charging state, speed). 33 unit tests.
* **FEAT**: `HealthCheck` model with `HealthWarning` enum (12 warning types) and `HealthWarningDescription` extension.
* **FEAT**: `LocationProcessor` integration with adaptive sampling via `AdaptiveContext`.

## 0.8.3

* **CHORE**: Version bump for proximity-based geofence monitoring release.

## 0.8.2

* **DOCS**: Improve README visuals with combined Android & iOS demo image.

## 0.8.1

* **DOCS**: Document iOS background hardening and session manager support in README.

## 0.8.0

* **FEAT**: `getSettingsHealth()` abstract method — OEM settings health check returning manufacturer, aggression rating, battery optimization status, and available OEM settings screens.
* **FEAT**: `openOemSettings(String label)` abstract method — open OEM-specific settings screens by label.
* **FEAT**: `MethodChannelTracelet` implementations for both new OEM methods.
* **DOCS**: Update README with OEM Compatibility API reference.

## 0.7.1

* **DOCS**: Update README with shared Dart algorithms description and mock detection reference.

## 0.7.0

* **FEAT**: `MockDetectionLevel` enum — `disabled`, `basic`, `heuristic` detection depth for mock/spoofed GPS.
* **FEAT**: `LocationProcessor` mock location filter — rejects locations with `isMock: true` when `rejectMockLocations` is enabled.
* **FEAT**: `LocationProcessor` timestamp monotonicity check — detects backward timestamps as heuristic spoof indicator (level ≥ 2).
* **FEAT**: `LocationProcessor.mockDetectionLevel` field + `copyWith()` support.

## 0.6.1

* **REFACTOR**: Remove dead `TraceletEvents.trip` constant and `TraceletEvents.all` list — trip events now produced by Dart `TripManager`.
* **REFACTOR**: `TripManager` now uses `GeoUtils.haversine()` instead of duplicate private `_haversine()` implementation.

## 0.6.0

* **FEAT**: `LocationProcessor` — shared Dart implementation of distance filtering, elasticity, accuracy filtering (adjust/ignore/discard), speed filtering, and odometer gating. Replaces duplicate native Kotlin/Swift code.
* **FEAT**: `GeofenceEvaluator` — shared Dart high-accuracy geofence proximity evaluation for circular and polygon geofences with ENTER/EXIT state tracking.
* **FEAT**: `ScheduleParser` — shared Dart schedule string parsing, window matching, and alarm calculation for cross-platform scheduling.
* **FEAT**: `PersistDecider` — shared Dart persistence decision logic based on `PersistMode`.
* **FEAT**: Export all 7 algorithm classes via `algorithms.dart` barrel file (GeoUtils, KalmanLocationFilter, TripManager, LocationProcessor, GeofenceEvaluator, ScheduleParser, PersistDecider).
* **CHORE**: 46 new unit tests across 4 test files (86 total algorithm tests).

## 0.5.5

* **CHORE**: Bump version to 0.5.5.

## 0.5.4

* **CHORE**: Bump version to 0.5.4.

## 0.5.3

* **CHORE**: Bump version to 0.5.3.

## 0.5.2

* **CHORE**: Bump version to 0.5.2.

## 0.5.1

* **DOCS**: Update README with links to all federated packages.

## 0.5.0

* **FEAT**: Web platform support.
* **CHORE**: Bump version to 0.5.0.

## 0.4.0

* **FEAT**: Add `getMotionPermissionStatus()` and `requestMotionPermission()` to platform interface.
* **CHORE**: Format all Dart files.

## 0.3.0

* **FEAT**: Add `getLastKnownLocation()` abstract method to platform interface.
* **FEAT**: Add `ForegroundServiceConfig.enabled` field to `AppConfig` for toggling foreground service.
* **FEAT**: Enhance `getCurrentPosition()` with `persist`, `samples`, `maximumAge`, and `extras` parameters for enterprise one-shot location requests.

## 0.2.2

* Fix LICENSE file format for proper SPDX detection on pub.dev.

## 0.2.1

* Bump Pigeon dependency from ^22.7.0 to ^26.1.7.

## 0.2.0

* Add SPDX `license: Apache-2.0` identifier for pub.dev scoring.

## 0.1.0

* Initial release.
* Abstract platform interface with 38 methods.
* Pigeon-generated type-safe communication layer.
* 13 enum types for location, activity, geofence, and HTTP configuration.
* EventChannel definitions for 14 real-time event streams.
