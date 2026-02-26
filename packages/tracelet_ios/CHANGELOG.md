## 0.5.2

* **FEAT**: Accelerometer-only motion detection mode — when `disableMotionActivityUpdates` is `true`, uses `CMMotionManager` raw accelerometer for permission-free stationary↔moving detection (no `NSMotionUsageDescription` required).
* **FEAT**: `getMotionAuthorizationStatus()` / `requestMotionPermission()` return `3` (granted) immediately in accelerometer-only mode — no OS dialog shown.
* **PERF**: Reuse shared `CMMotionManager` instance for sensor queries instead of creating throwaway instances.
* **FIX**: Auto-fallback to accelerometer-only when `CMMotionActivityManager.isActivityAvailable()` returns `false`.

## 0.5.1

* **DOCS**: Rewrite README with proper description, setup guide link, and related packages table.

## 0.5.0

* **CHORE**: Bump `tracelet_platform_interface` to ^0.5.0.
* **CHORE**: Bump version to 0.5.0.

## 0.4.0

* **FEAT**: `getMotionPermissionStatus()` / `requestMotionPermission()` — CMMotionActivityManager authorization check.
* **FIX**: Speed always zero in motionchange events — track `lastEffectiveSpeed` in LocationEngine.
* **FIX**: "Upgrade to Always" dialog not appearing — fix `handleStart` isMoving initialization.
* **FIX**: MotionDetector motion state bugs — proper accelerometer + activity recognition lifecycle.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.4.0.

## 0.3.0

* **FEAT**: One-shot location via `getCurrentPosition()` with `persist`, `samples`, `maximumAge`, and `extras` parameters.
* **FEAT**: Multi-sample collection with `distanceFilter = kCLDistanceFilterNone` and `DispatchQueue` timeout guard.
* **FEAT**: `getLastKnownLocation()` — prefers own cached location, falls back to `CLLocationManager.location`.
* **FEAT**: `ForegroundServiceConfig.enabled` support.
* **FIX**: Add `CLAuthorizationStatus` guard in `getCurrentPosition()` — returns nil if not authorized instead of hanging.
* **FIX**: Single-sample path now sets `desiredAccuracy = kCLLocationAccuracyBest` before `requestLocation()`.
* **BREAKING**: Requires `tracelet_platform_interface: ^0.3.0`.

## 0.2.4

* Fix LICENSE file format for proper SPDX detection on pub.dev.

## 0.2.3

* Fix `ConfigManager.setConfig()` — flatten nested section sub-maps (`geo`, `app`, `http`, etc.) sent by Dart before processing. Fixes all user config values being silently ignored in favor of defaults.

## 0.2.2

* Fix duplicate keys in `ConfigManager.defaultConfig()` dictionary literal causing runtime crash.

## 0.2.1

* Version bump for coordinated release.

## 0.2.0

* Add Swift Package Manager support.
* Fix podspec homepage URL.
* Fix podspec source_files and resource_bundles paths for SPM layout.
* Add SPDX `license: Apache-2.0` identifier for pub.dev scoring.

## 0.1.0

* Initial release.
* CLLocationManager-based location tracking.
* CoreMotion activity recognition.
* SQLite3 persistence.
* HTTP auto-sync with URLSession.
* CLCircularRegion geofencing.
* Headless FlutterEngine execution.
* BGTaskScheduler integration.
* Significant-change monitoring support.
