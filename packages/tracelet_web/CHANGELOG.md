# Changelog

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
