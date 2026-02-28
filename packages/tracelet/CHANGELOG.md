## 0.7.1

* **DOCS**: Add mock location detection feature to README with documentation links and feature description.
* **DOCS**: Add Mock Detection guide to documentation table.
* **CHORE**: Bump all platform dependencies to ^0.7.1.

## 0.7.0

* **FEAT**: Mock location detection & prevention — detect and reject spoofed GPS locations across Android, iOS, and Web.
* **FEAT**: `Location.isMock` field — boolean flag indicating if a location came from a mock provider.
* **FEAT**: `Location.mockHeuristics` field — `MockHeuristics` metadata (satellite count, elapsed realtime drift, timestamp drift, platform flag).
* **FEAT**: `LocationFilter.rejectMockLocations` config — block spoofed locations from reaching the app.
* **FEAT**: `LocationFilter.mockDetectionLevel` config — `MockDetectionLevel` enum (`disabled`, `basic`, `heuristic`) for configurable detection depth.
* **FEAT**: `ProviderChangeEvent.mockLocationsDetected` — real-time alert when mock locations are detected.
* **FEAT**: Re-export `MockDetectionLevel` from `tracelet.dart` barrel file.
* **DOCS**: Comprehensive [MOCK-DETECTION.md](help/MOCK-DETECTION.md) guide.
* **DOCS**: Updated [CONFIGURATION.md](help/CONFIGURATION.md) with mock detection options.
* **CHORE**: Bump all platform dependencies to ^0.7.0.

## 0.6.1

* **CHORE**: Bump all platform dependencies to ^0.6.1.

## 0.6.0

* **FEAT**: Integrate shared Dart `LocationProcessor` into `onLocation` stream — distance filtering, elasticity, accuracy filtering, and speed filtering now run in Dart for cross-platform consistency.
* **FEAT**: Integrate shared Dart `GeofenceEvaluator` for high-accuracy proximity checks.
* **FIX**: Fix broadcast stream bug — stateful `LocationProcessor` and `KalmanLocationFilter` were called once per listener per event, causing second subscriber to see distance=0 and filter all locations. Now uses cached `.asBroadcastStream()` so transformations run exactly once.
* **PERF**: Native code no longer duplicates filtering logic — significantly reduces native code surface.
* **CHORE**: Bump all platform dependencies to ^0.6.0.

## 0.5.5

* **FIX**: iOS `onSchedule` event now sends full state map instead of partial data.
* **CHORE**: Bump all platform dependencies to ^0.5.5.

## 0.5.4

* **FIX**: Heartbeat events no longer return zero coordinates on Android and iOS.

## 0.5.3

* **CHORE**: Bump all platform dependencies to ^0.5.3.

## 0.5.2

* **FEAT**: `disableMotionActivityUpdates` now falls back to permission-free accelerometer-only motion detection instead of disabling all motion detection entirely.
* **DOCS**: Expanded `MotionConfig.disableMotionActivityUpdates` documentation with fallback behavior, use cases, and battery notes.
* **DOCS**: Updated `getMotionPermissionStatus()` / `requestMotionPermission()` docs to reflect accelerometer-only mode behavior.
* **DOCS**: Added "Opting Out of Motion Permission" section to PERMISSIONS.md with comparison table.

## 0.5.1

* **DOCS**: Update README with web platform in architecture and documentation tables.

## 0.5.0

* **FEAT**: Add web platform support via `tracelet_web` package.
* **FEAT**: Guard `registerHeadlessTask()` for web compatibility (`kIsWeb` early return).
* **DOCS**: Add Web Support guide (`help/WEB-SUPPORT.md`) with full API compatibility matrix.
* **DOCS**: Update README with web platform in architecture table and documentation links.
* **CHORE**: Bump all platform dependencies to ^0.5.0.

## 0.4.0

* **FEAT**: `getMotionPermissionStatus()` and `requestMotionPermission()` APIs for activity recognition permission.
* **FIX**: Speed always zero in motionchange events — track `lastEffectiveSpeed` across location updates.
* **DOCS**: Split README into focused help guides (Permissions, Background Tracking, API, Configuration).
* **DOCS**: Add side-by-side Android/iOS demo recordings.
* **CHORE**: Bump all platform dependencies to ^0.4.0.
* **CHORE**: Format all Dart files.

## 0.3.0

* **FEAT**: One-shot location — `getCurrentPosition()` now supports `persist`, `samples`, `maximumAge`, and `extras` parameters for enterprise single-time location requests.
* **FEAT**: `getLastKnownLocation()` — returns the last cached location without triggering the GPS, or `null` if unavailable.
* **FEAT**: `ForegroundServiceConfig.enabled` — disable foreground service/notification for lightweight one-shot requests.
* **BREAKING**: Bump all platform dependencies to ^0.3.0.

## 0.2.5

* Fix LICENSE file format for proper SPDX detection on pub.dev.
* Bump `tracelet_android` dependency to ^0.2.3.
* Bump `tracelet_ios` dependency to ^0.2.4.

## 0.2.4

* Bump `tracelet_android` dependency to ^0.2.2 (fixes config not applied to foreground notification).
* Bump `tracelet_ios` dependency to ^0.2.3 (fixes config values ignored on iOS).

## 0.2.3

* Bump `tracelet_ios` dependency to ^0.2.2 (fixes iOS `ConfigManager` crash).

## 0.2.2

* Fix dangling library doc comment lint in `_helpers.dart`.

## 0.2.1

* Add `tracelet_android` and `tracelet_ios` as explicit dependencies to fix default plugin resolution warnings.

## 0.2.0

* Add `isMoving` field to `State` model.
* Fix `Config.toMap()` — use nested map structure to prevent extras key collision.
* Fix `watchPosition` listener leak — subscriptions now tracked and cancelled.
* Fix `removeListeners()` to cancel all Dart-side stream subscriptions.
* Change `LogLevel` default from `off` to `info`.
* Complete `==`/`hashCode` on all sub-config classes.
* Extract shared deserialization helpers to reduce code duplication.
* Fix example (`LogConfig` → `LoggerConfig`).

## 0.1.1

* Fix pubspec description length for pub.dev scoring.
* Add SPDX `license: Apache-2.0` identifier.
* Add `example/main.dart` for pub.dev documentation score.

## 0.1.0

* Initial release.
* Full background geolocation API with 38 public methods.
* 14 real-time event streams (location, motion, geofence, HTTP, etc.).
* Comprehensive config system: GeoConfig, AppConfig, HttpConfig, MotionConfig, GeofenceConfig, PersistenceConfig, LoggerConfig.
* Elasticity-based distance filter scaling.
* Location filtering and denoising.
* Headless Dart execution for background events.
* Scheduling with cron-like expressions.
* `removeListeners()` for centralized cleanup.
