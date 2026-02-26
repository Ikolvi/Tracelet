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
