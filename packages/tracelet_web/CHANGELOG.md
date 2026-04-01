# Changelog

## 1.8.6

- **CHORE**: Version bump for HTTP sync headers fix.

## 1.8.5

- **CHORE**: Version bump for `getCurrentPosition` fallback fix (#46).

## 1.8.4

- **CHORE**: Version bump for Android pre-ready guard fixes and strict native SDK pinning.

## 1.8.3

- **CHORE**: Version bump for iOS pre-ready guard fixes.

## 1.8.2

- **CHORE**: Version bump for Android/iOS stability fixes.

## 1.8.1

- **CHORE**: Version bump for iOS periodic mode location indicator fix.

## 1.8.0

- **FEAT**: Add `destroySyncedLocations()` web implementation.

## 1.7.1

- **FEAT**: Add `destroySyncedLocations()` web implementation.

## 1.7.0

- **CHORE**: Update cross-package dependency constraints to `^1.7.0`.

## 1.6.3-alpha.1

- **CHORE**: Update cross-package dependency constraints to `^1.6.3-alpha.1`.

## 1.6.1

- **FIX**: Add 5 missing HTTP Sync method overrides (`setDynamicHeaders`, `setRouteContext`, `clearRouteContext`, `registerHeadlessHeadersCallback`, `registerHeadlessSyncBodyBuilder`) that previously threw `UnimplementedError` at runtime.
- **FEAT**: `WebHttpEngine` now supports dynamic headers and route context in HTTP requests.
- **TEST**: Add platform interface coverage test to prevent future method stub regressions.

## 1.6.0

- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.6.0`.

## 1.5.0

- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.5.0`.

## 1.4.6

- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.6`.

## 1.4.5

- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.5`.

## 1.4.4

- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.4`.

## 1.4.3

- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.3`.

## 1.4.2

- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.2`.

## 1.4.1

- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.1`.

## 1.4.0

- **FEAT**: Add stub implementations for enterprise methods: `isDatabaseEncrypted()`, `encryptDatabase()`, `getAttestationToken()`, `getDeadReckoningState()`, `getCarbonReport()`.
- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.0`.

## 1.3.6

- **FIX**: `getCount()` now supports time-range filtering via optional `SQLQuery` parameter.
- **FIX**: Fix `getLocations()` timestamp filtering — `start`/`end` were incorrectly cast as `String?` instead of `int?` (millisecondsSinceEpoch).
- **CHORE**: Update cross-package dependency constraints to `^1.3.6`.

## 1.3.5

- **CHORE**: Update cross-package dependency constraints to `^1.3.5`.

## 1.3.4

- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.3.3`.

## 1.3.3

- **CHORE**: Patch bump for federation consistency with `tracelet` 1.3.3.

## 1.3.2

- **CHORE**: Patch bump for federation consistency with `tracelet` 1.3.2.

## 1.3.1

- **CHORE**: Patch bump for federation consistency with `tracelet` 1.3.1.

## 1.3.0

- **CHORE**: Version bump for federation consistency with `tracelet` 1.3.0.

## 1.2.0

- **CHORE**: Version bump for federation consistency with `tracelet_platform_interface` 1.2.0 (new `NotificationPriority` and `HashAlgorithm` enums).

## 1.1.0

### New Features

- **FEAT**: `WebHttpEngine` now supports delta-compressed batch uploads — conditionally applies `DeltaEncoder.encode()` when `enableDeltaCompression` is true and batch size > 1, achieving 60–80% payload reduction for high-frequency tracking scenarios. Reads `enableDeltaCompression` (bool) and `deltaCoordinatePrecision` (int, default 6) from HTTP config.
- **FEAT**: `WebHttpEngine` supports `disableAutoSyncOnCellular` — guards auto-sync on cellular networks via the Network Information API (where available), syncing only on WiFi connections.

## 1.0.1

- **FIX**: HTTP auto-sync now triggers after `insertLocation()` and `getCurrentPosition(persist: true)` — previously auto-sync was never invoked on web ([#21](https://github.com/Ikolvi/Tracelet/issues/21)).
- **FEAT**: `WebHttpEngine` now parses `autoSync`, `autoSyncThreshold`, and `disableAutoSyncOnCellular` from config.

## 1.0.0

### 🎉 Stable Release

- **FEAT**: First stable release of `tracelet_web`.
- **REFACTOR**: Remove third-party company name references.
- All Web APIs are finalized and production-ready.

## 0.12.0

### Performance Audit — Web optimizations

- **PERF**: Hoist `math.Random()` to top-level constant in `generateUuid()` (D-M1).
- **PERF**: Use lazy `Iterable` chaining in `getLocations()`, materialize only once (D-M3).
- **PERF**: Promote browser version `RegExp` patterns to `static final` (D-M5).
- **PERF**: Cache `.toJS` references for web event listeners (D-H6).
- **PERF**: Cache polygon vertices at `addGeofence` time (D-H5).

## 0.11.4

- **CHORE**: Version bump for platform consistency.

## 0.11.3

- **CHORE**: Version bump for platform consistency.

## 0.11.2

- **FIX**: Fix LICENSE file formatting so pana correctly detects Apache-2.0.
- **DOCS**: Add `example/example.dart` for pub.dev documentation score.
- **CHORE**: Tighten `tracelet_platform_interface` constraint to `^0.11.2`.

## 0.11.1

- **FEAT**: Add `canScheduleExactAlarms()` (returns `true`) and `openExactAlarmSettings()` (returns `false`) stub implementations.
- **CHORE**: Bump platform interface to 0.11.1.

## 0.11.0

- **FEAT**: Stub implementations for privacy zone and audit trail methods (no-op on web).
- **CHORE**: Bump `tracelet_platform_interface` to ^0.11.0.

## 0.10.0

- **FEAT**: `startPeriodic()` — falls back to `watchPosition()` on web (periodic scheduling not available in browsers).
- **CHORE**: Bump `tracelet_platform_interface` to ^0.10.0.

## 0.9.1

- **CHORE**: Version bump for consistency.

## 0.9.0

* **CHORE**: Version bump for adaptive sampling, health check, and motion sensitivity release.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.9.0.

## 0.8.3

* **CHORE**: Version bump for proximity-based geofence monitoring release.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.8.3.

## 0.8.2

* **DOCS**: Improve README visuals with combined Android & iOS demo image.

## 0.8.1

* **FIX**: Fix `_bridgedController` dropping all EventChannel events — `onLocation`, `onMotionChange`, `onHeartbeat`, `onGeofence`, and all other event streams were broken on web (events consumed but never forwarded to Dart). Now properly pipes data via `controller.add()`.
* **FIX**: `WebEventDispatcher.log()` was a no-op — now prints to browser console for debugging visibility.
* **FEAT**: Diagnostic logging in `WebLocationEngine.getCurrentPosition()` and `_browserGetPosition()` — logs request parameters, success/error callbacks, and `_positionToMap` errors to the browser console.

## 0.8.0

* **FEAT**: OEM compatibility stubs — `getSettingsHealth()` returns `isAggressiveOem: false` (no OEM power management on web), `openOemSettings()` returns `false`.
* **DOCS**: Update README with OEM compatibility stub in feature table.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.8.0.

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
