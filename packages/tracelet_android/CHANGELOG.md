## 0.5.1

* **DOCS**: Rewrite README with proper description, setup guide link, and related packages table.

## 0.5.0

* **CHORE**: Bump `tracelet_platform_interface` to ^0.5.0.
* **CHORE**: Bump version to 0.5.0.

## 0.4.0

* **FEAT**: `getMotionPermissionStatus()` / `requestMotionPermission()` — ACTIVITY_RECOGNITION permission handling.
* **FIX**: Auto-pace not triggering — start accelerometer monitoring in `MotionDetector.start()` when stationary.
* **FIX**: Speed always zero in motionchange events — track `lastEffectiveSpeed` in LocationEngine.
* **FIX**: Kotlin compilation error from literal `\n` in import line.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.4.0.

## 0.3.0

* **FEAT**: One-shot location via `getCurrentPosition()` with `persist`, `samples`, `maximumAge`, and `extras` parameters.
* **FEAT**: `getLastKnownLocation()` with 3-tier fallback — in-memory cache → FusedLocationProviderClient → system LocationManager (GPS/Network).
* **FEAT**: `ForegroundServiceConfig.enabled` — conditionally start/stop foreground service based on config.
* **FIX**: Replace `requestLocationUpdates` with sequential `getCurrentLocation()` calls in `collectSamples()` to avoid silent throttling on budget devices without foreground service.
* **BREAKING**: Requires `tracelet_platform_interface: ^0.3.0`.

## 0.2.3

* Fix LICENSE file format for proper SPDX detection on pub.dev.

## 0.2.2

* Fix `ConfigManager.setConfig()` — flatten nested section sub-maps (`geo`, `app`, `http`, etc.) sent by Dart before processing. Fixes foreground service notification config (title, text, channel, priority) and all other sub-config values being silently ignored.

## 0.2.1

* Version bump for coordinated release.

## 0.2.0

* Add SPDX `license: Apache-2.0` identifier for pub.dev scoring.

## 0.1.0

* Initial release.
* FusedLocationProvider-based location tracking.
* Foreground service with configurable notification.
* Activity recognition via Google Play Services.
* SQLite persistence with Room.
* HTTP auto-sync with OkHttp.
* Geofencing with platform GeofencingClient.
* Headless Dart isolate execution.
* Boot-completed receiver for start-on-boot.
* WorkManager-based scheduling.
