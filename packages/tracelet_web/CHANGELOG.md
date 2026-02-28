# Changelog

## 0.7.1

* **DOCS**: Add mock detection passthrough note to README feature table.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.7.1.

## 0.7.0

* **FEAT**: `_positionToMap()` and `_emptyLocation()` now include `mock: false` field — browser Geolocation API has no mock detection capability.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.7.0.

## 0.6.1

* **FIX**: Remove duplicate distance filter from `WebLocationEngine` — all location filtering now handled by shared Dart `LocationProcessor` via `tracelet.dart` pipeline, matching Android/iOS behavior.
* **REFACTOR**: Replace duplicate `_haversine()` in `WebLocationEngine` with shared `GeoUtils.haversine()`.
* **REFACTOR**: Deduplicate UUID generators into shared `web_utils.dart` (`generateUuid()`).
* **REFACTOR**: Remove dead internal logging from `WebEventDispatcher` (`_logs`, `getLog()`, `clearLog()`).
* **CHORE**: Bump `tracelet_platform_interface` to ^0.6.1.

## 0.6.0

* **CHORE**: Bump `tracelet_platform_interface` to ^0.6.0. Inherits shared Dart algorithm improvements.

## 0.5.5

* **CHORE**: Bump `tracelet_platform_interface` to ^0.5.5.

## 0.5.4

* **CHORE**: Bump `tracelet_platform_interface` to ^0.5.4.

## 0.5.3

* **CHORE**: Bump `tracelet_platform_interface` to ^0.5.3.

## 0.5.2

* **FIX**: Replace deprecated `registrar.messenger` with `registrar` directly in event channel registration.
* **CHORE**: Bump version to 0.5.2.

## 0.5.1

* **DOCS**: Update README with usage instructions, compatibility table, and related packages.
* **FIX**: Add `.gitignore` to exclude `build/` directory from publish.
* **FIX**: Add `flutter` environment constraint to `pubspec.yaml`.

## 0.5.0

* **FEAT**: Initial web platform release.
* **FEAT**: Foreground-only location tracking via Web Geolocation API.
* **FEAT**: Geofence emulation (distance-based enter/exit/dwell detection).
* **FEAT**: In-memory persistence for locations and logs.
* **FEAT**: HTTP sync via browser `fetch()` API.
* **FEAT**: Permission queries via `navigator.permissions`.
* **FEAT**: Connectivity monitoring via `online`/`offline` events.
* **FEAT**: Auto-fallback from high to low accuracy on timeout.
* **DOCS**: Add comprehensive Web Support guide (`help/WEB-SUPPORT.md`).

## 0.4.0

- Initial web implementation (pre-release).
- Connectivity detection via `navigator.onLine`.
- Stub implementations for platform-specific APIs (background tasks, settings, etc.).
