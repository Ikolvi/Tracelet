## 1.6.3-alpha.1

- **FEAT**: Rewrite `EventDispatcher` to use Pigeon `TraceletEventApi` FlutterApi instead of FlutterEventChannels.
- **FEAT**: Add `TraceletHostApiImpl` for type-safe Pigeon HostApi dispatch.
- **REFACTOR**: Extract native SDK code to `sdk/ios/` module.
- **CHORE**: Update cross-package dependency constraints to `^1.6.3-alpha.1`.

## 1.6.1

- **FEAT**: Add 401-aware retry — on HTTP 401 Unauthorized, invoke headless headers callback to refresh token, then retry once with updated dynamic headers.

## 1.6.0

- **FEAT**: Add SSL certificate pinning — `URLSessionDelegate`-based validation with SHA-256 fingerprint matching via CommonCrypto.
- **FEAT**: Add dynamic HTTP headers with runtime callback support and headless background execution.
- **FEAT**: Add route context — attach arbitrary metadata to synced locations.
- **FEAT**: Add custom sync body builder with headless callback support.
- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.6.0`.

## 1.5.0

- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.5.0`.

## 1.4.6

- **FIX**: Rename `PermissionManager` to `TraceletPermissionManager` to avoid class name collision with `permission_handler_apple` (#32).
- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.6`.

## 1.4.5

- **FEAT**: Auto-request temporary full accuracy (iOS 14+) when tracking starts with reduced accuracy authorization.
- **TEST**: Add XCTest unit tests for `buildLocationMap()` locationSource classification and `reducedAccuracy` field.
- **DOCS**: Update INSTALL-IOS.md with `TraceletFullAccuracy` purpose key documentation.
- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.5`.

## 1.4.4

- **FEAT**: iOS 14+ reduced accuracy detection — engine logs warnings when approximate location is active and tracks authorization transitions.
- **FEAT**: Add `reducedAccuracy` flag to each location fix — `true` when iOS grants only approximate location (~5 km).
- **FEAT**: Improved `locationSource` classification — under reduced accuracy, source is classified as `cell` since iOS returns coarse fixes.
- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.4`.

## 1.4.3

- **FEAT**: Add `locationSource` classification to every location fix (`gps`, `wifi`, `cell`, `unknown`) based on `horizontalAccuracy` heuristic.
- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.3`.

## 1.4.2

- **FIX**: `activateDeadReckoning()` now retries via timer instead of silently returning when `lastLocation` is nil.
- **FIX**: Add debug logging to GPS-loss timer and dead reckoning activation flow.
- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.2`.

## 1.4.1

- **FEAT**: Dead reckoning — full IMU sensor fusion implementation (`DeadReckoningEngine`). Uses `CMDeviceMotion` (fused accelerometer + gyroscope + magnetometer) for heading and step detection. Vehicle mode with acceleration integration.
- **FEAT**: Auto-activation on GPS loss after configurable delay, auto-deactivation on GPS recovery or max duration.
- **CHORE**: Add dead reckoning config getters to `ConfigManager`.
- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.1`.

## 1.4.0

- **FEAT**: Encrypted SQLite — database encryption via iOS Data Protection API (`NSFileProtectionComplete`).
- **FEAT**: Device attestation — App Attest (DCAppAttestService) integration with challenge generation, token caching, and periodic refresh (`DeviceAttestor`).
- **FEAT**: Remote config — fetch remote configuration via HTTPS with ETag caching and config-change event streaming.
- **FEAT**: Dead reckoning — `getDeadReckoningState()` stub for future accelerometer/gyroscope-based position estimation.
- **FEAT**: Carbon estimator — `getCarbonReport()` returns CO₂ estimates from tracked locations using EU average emission factors.
- **CHORE**: Add `DeviceCheck` framework dependency.
- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.0`.

## 1.3.6

- **FIX**: `getLocations()` now honors `SQLQuery.start` and `SQLQuery.end` timestamp filtering.
- **FIX**: `getCount()` now accepts optional `SQLQuery` for time-bounded counting.
- **CHORE**: Update cross-package dependency constraints to `^1.3.6`.

## 1.3.5

- **FIX**: Fix `Unable to find module dependency: 'TraceletCore'` Swift compiler error by consolidating SPM targets into a single module and removing invalid cross-module imports.
- **FIX**: Add missing `AVFoundation`, `AudioToolbox`, and `Network` framework linker settings in `Package.swift`.

## 1.3.4

- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.3.3`.

## 1.3.3

- **FIX**: Bundle TraceletCore Swift source files directly inside the plugin package instead of depending on an unpublished local CocoaPod. Fixes unresolved `import TraceletCore` when installed from pub.dev.

## 1.3.2

- **PERF**: Replace `Foundation UUID()` with C-level `uuid_generate_random`/`uuid_unparse_lower` in `LocationEngine` and `TraceletDatabase` (I-M6).

## 1.3.1

- **FIX**: `getPersistenceExtras()` now reads distinct `persistenceExtras` config key with backward-compatible fallback.
- **PERF**: `markSynced()` uses chunked SQL statements (500 UUIDs/chunk) instead of unbounded placeholder lists.

## 1.3.0

- **FIX**: `getState()` always returned `enabled: false` on iOS — `StateManager.toMap()` flat-merged the config dictionary into the state dictionary, causing config keys (`enabled` from audit section, `isMoving` from motion section) to overwrite runtime state values. Config is now correctly nested under a `"config"` key, matching the Android implementation and the Dart `State.fromMap()` contract ([#26](https://github.com/Ikolvi/Tracelet/issues/26)).

## 1.2.1

### iOS↔Android Parity Fixes

- **FEAT**: Add `ConfigManager.hasConfig()` — returns `true` if a config has been persisted at least once (checks UserDefaults for stored config data). Matches existing Android `ConfigManager.hasConfig()`.
- **FEAT**: Add `StateManager.lastPeriodicLatitude` / `lastPeriodicLongitude` — persisted coordinates for odometer computation across periodic tracking restarts. Returns `NaN` when no fix has been recorded; setting `NaN` removes the persisted value. Matches Android `StateManager.lastPeriodicLatitude/Longitude`.
- **FEAT**: Add `StateManager.addOdometer(distance:)` — incremental odometer accumulation method. Matches Android `StateManager.addOdometer(distance)`.
- **FEAT**: Add `LocationEngine.stopAllWatchers()` — clears all active watch-position subscriptions. Called automatically from `destroy()`. Matches Android `LocationEngine.stopAllWatchers()`.
- **FEAT**: Add `TraceletEventSending.hasListener(eventName:)` protocol method and `EventDispatcher.hasListener(eventName:)` implementation — checks if a Dart listener is attached for a given event channel. Accepts both full path (`com.tracelet/events/location`) and short name (`location`). Matches Android `EventSender.hasListener()`.
- **REFACTOR**: All TraceletCore members made `public` for cross-module access with `use_frameworks!` CocoaPods integration.

## 1.2.0

- **CHORE**: Version bump for federation consistency with `tracelet_platform_interface` 1.2.0 (new `NotificationPriority` and `HashAlgorithm` enums).

## 1.1.0

### New Features

- **FEAT**: Add native `DeltaEncoder` (Swift) for delta-compressed HTTP sync payloads — mirrors the Dart implementation exactly for platform consistency. Encodes only field deltas between consecutive locations using shortened keys (`la`, `lo`, `t`, `s`, `h`, `a`, `al`, `b`), achieving 60–80% bandwidth reduction. Uses Foundation's `ISO8601DateFormatter` with fractional seconds fallback for robust timestamp handling.
- **FEAT**: `ConfigManager` now reads and applies the following new configuration fields from Dart: `batteryBudgetPerHour` (adaptive battery budget target), `enableSparseUpdates`, `sparseDistanceThreshold`, `sparseMaxIdleSeconds` (app-level deduplication), `enableDeadReckoning`, `deadReckoningActivationDelay`, `deadReckoningMaxDuration` (inertial navigation when GPS lost), `enableDeltaCompression`, `deltaCoordinatePrecision` (HTTP delta encoding), and `disableAutoSyncOnCellular` (WiFi-only sync).
- **FEAT**: `HttpSyncManager` now supports `disableAutoSyncOnCellular` — skips auto-sync when device is on cellular network, syncing only on WiFi. Also conditionally applies `DeltaEncoder.encode()` to multi-location batches before HTTP upload when `enableDeltaCompression` is enabled, reducing upload size by 60–80%.

## 1.0.2

- **FIX**: `handleReset()` unconditionally removed geofence registrations from CLLocationManager even when `stopOnTerminate: false` was configured with `trackingMode=1` (geofence mode). Geofences now survive the reset call so CLLocationManager continues monitoring regions after app termination ([#23](https://github.com/Ikolvi/Tracelet/issues/23)).

## 1.0.1

- **FIX**: HTTP auto-sync never triggered from automatic location tracking — `onLocationInserted()` was only called from the manual `insertLocation` handler, not from `LocationEngine.persistLocationIfAllowed()` ([#21](https://github.com/Ikolvi/Tracelet/issues/21)).
- **FIX**: `ConfigManager.getHttpMethod()` cast `Int` as `String`, silently ignoring `HttpMethod.put` — now correctly maps `0` → POST, `1` → PUT.
- **FIX**: `ConfigManager.getHttpHeaders()` strict `[String: String]` cast could drop headers when platform channel delivers `[String: Any]` — now coerces values to strings.
- **FIX**: `maxBatchSize` default corrected from 100 to 250 to match Dart and Android defaults.

## 1.0.0

### 🎉 Stable Release

- **FEAT**: First stable release of `tracelet_ios`.
- **REFACTOR**: Remove third-party company name references.
- All native iOS APIs are finalized and production-ready.

## 0.12.0

### Performance Audit — 22 iOS issues resolved

- **PERF**: Cache `ISO8601DateFormatter` as static instance (I-C1, I-C2).
- **PERF**: Call `UIDevice.isBatteryMonitoringEnabled` once at plugin initialization (I-C3).
- **PERF**: Add serial `stateQueue` for thread-safe sync flag access (I-C4).
- **PERF**: Use `BackgroundTaskHelper.shared.begin()` with proper expiration handler (I-C5).
- **PERF**: Reduce accelerometer to 10 Hz and deliver on background queue (I-H1).
- **PERF**: Set timer tolerance to 10% for iOS energy coalescing (I-H2).
- **PERF**: Use SQLite transactions for batch geofence inserts (I-H3).
- **PERF**: Throttle DB pruning to every 100 inserts (I-H4, I-H6).
- **PERF**: Move JSON serialization outside DB queue lock (I-H5).
- **PERF**: Default `pausesLocationUpdatesAutomatically` to `true` (I-M1).
- **PERF**: Make `activityType` configurable via `getActivityType()` mapping (I-M2).
- **PERF**: Reuse `URLSession` — `getAllTasks` cancel instead of `invalidateAndCancel` (I-M3).
- **PERF**: Defer `BGAppRefreshTask.setTaskCompleted` until async location fix returns (I-M4).
- **PERF**: Find monitored region by identifier instead of creating dummy `CLCircularRegion` (I-M5).
- **PERF**: Add in-memory privacy zone cache with CRUD invalidation (I-M7).
- **PERF**: Add in-memory geofence cache with CRUD invalidation (I-M8).
- **PERF**: Lazy-init `CMMotionActivityManager` and `CMPedometer` for accelerometer-only mode (I-L1).
- **PERF**: Remove duplicate `haversine()` from `GeofenceManager`, call module-level function (I-L3).
- **PERF**: Remove dead `@available(iOS 14)` self-assign no-op (I-L4).
- **REFACTOR**: Remove trivial `isMoreRestrictive()` wrapper, inline `isActionMoreRestrictive()` call (I-L5).
- **CHORE**: Add CoreLocation import to `ConfigManager.swift` for `CLActivityType`.

## 0.11.5

- **FIX**: Persist polygon geofence `vertices` to SQLite — add `vertices TEXT` column with `PRAGMA table_info` migration for existing installs, and JSON serialization/deserialization in `insertGeofence()`/`geofenceRowToMap()`.
- **FIX**: Use `NSNumber` bridging for `JSONSerialization` vertex deserialization (fixes silent cast failure with `[[Double]]`).
- **FIX**: Handle heterogeneous vertex arrays — skip non-array entries instead of failing the entire cast.
- **TEST**: Add XCTest tests for geofence vertices CRUD (11 tests covering round-trip, validation, edge cases).
- **TEST**: Add DB migration integration tests — column addition, data preservation, idempotency, multi-geofence migration, fresh install.

## 0.11.4

- **FIX**: Revert over-aggressive `allowsBackgroundLocationUpdates` and significant-location guards — When In Use permission now works correctly for foreground and background tracking. iOS enforces permission at the OS level; only the killed-state entry point (`autoResumeTracking`) requires Always authorization.

## 0.11.3

- **FIX**: Add `.authorizedAlways` guard to `autoResumeTracking()` — prevents "When In Use" permission from triggering tracking after app is relaunched from killed state via significant-location-change.
- **FIX**: Guard `allowsBackgroundLocationUpdates` in `configureLocationManager()` and `performPeriodicFix()` — only set to `true` when Always authorization is granted.

## 0.11.2

- **CHORE**: Tighten `tracelet_platform_interface` constraint to `^0.11.2`.

## 0.11.1

- **FIX**: Set `event: "periodic"` in all `didUpdateLocations` code paths for periodic tracking (was empty string).
- **FEAT**: Add `canScheduleExactAlarms` (returns `true`) and `openExactAlarmSettings` (returns `false`) method channel stubs.
- **CHORE**: Add NSLog diagnostic logging to `startPeriodic()` and `performPeriodicFix()`.
- **CHORE**: Bump platform interface to 0.11.1.

## 0.11.0

- **FEAT**: `AuditTrailManager` — SHA-256 hash chain with SQLite persistence and UserDefaults chain state.
- **FEAT**: `PrivacyZoneManager` — Haversine distance-based zone evaluation with exclude, degrade, and event-only actions.
- **FEAT**: Privacy zones database table with CRUD operations.
- **FEAT**: Audit trail database table with hash chain linkage.
- **FEAT**: `ConfigManager` getters for audit and privacy zone configuration.
- **CHORE**: Bump `tracelet_platform_interface` to ^0.11.0.

## 0.10.0

- **FEAT**: Periodic mode — GPS-friendly interval tracking via `startPeriodic()`. Timer-based scheduling with background location toggling per fix.
- **FEAT**: `ConfigManager` periodic config getters for interval, accuracy, foreground service, and exact alarms.
- **FIX**: `ConfigManager.swift` escaped string literals causing Swift compilation failure.
- **CHORE**: Bump `tracelet_platform_interface` to ^0.10.0.

## 0.9.1

- **FIX**: Safe optional unwrap of `UIBackgroundTaskIdentifier` in `HttpSyncManager.syncNextBatch()` — fixes Swift compiler error.

## 0.9.0

* **FEAT**: HTTP sync retry engine — configurable retry with exponential backoff for transient 5xx, 429, and timeout failures. Defers sync on connectivity loss via `NWPathMonitor`. Batch continuation loop.
* **FEAT**: Configurable motion sensitivity — `MotionDetector` reads `shakeThreshold`, `stillThreshold`, `stillSampleCount` from `ConfigManager` at runtime (auto-converts m/s² to g-force).
* **CHORE**: Bump `tracelet_platform_interface` to ^0.9.0.

## 0.8.3

* **FEAT**: Proximity-based geofence auto-load/unload — only geofences within `geofenceProximityRadius` are registered with CLLocationManager, sorted by distance, capped at 20 (iOS limit). Enables monitoring thousands of geofences.
* **FEAT**: `GeofenceManager.updateProximity()` — re-evaluates which geofences to monitor on every location update, dynamically swapping region registrations as the device moves.
* **FEAT**: `geofencesChange` event fires with `on`/`off` arrays when geofences are activated/deactivated from proximity monitoring.
* **FEAT**: `maxMonitoredGeofences` config respected — caps simultaneously monitored regions below the platform limit.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.8.3.

## 0.8.2

* **DOCS**: Improve README visuals with combined Android & iOS demo image.

## 0.8.1

* **FEAT**: `BackgroundTaskHelper` — central thread-safe utility wrapping `UIApplication.beginBackgroundTask` for safe background execution of native operations.
* **FEAT**: iOS 17+ `CLBackgroundActivitySession` support via `BackgroundActivitySessionManager` — extends background runtime for location-tracking apps.
* **FEAT**: iOS 18+ `CLServiceSession` support via `ServiceSessionManager` — maintains authorization state during background execution.
* **PERF**: Wrap `LocationEngine.didUpdateLocations` in background task — protects persist + dispatch chain from iOS suspension.
* **PERF**: Wrap `HttpSyncManager.sync()` in background task — protects entire HTTP upload + DB cleanup cycle.
* **PERF**: Wrap `HeadlessRunner.dispatchEvent()` engine boot in background task — ensures Dart engine starts fully before iOS reclaims resources.
* **PERF**: Wrap all `TraceletIosPlugin` lifecycle transitions (`handleStop`, `handleReset`, `onStopRequested`, `handleScheduleStop`, `stopAfterElapsedTimer`) in background tasks.
* **FIX**: `preventSuspendManager.start()` now called in `startGeofences()` — was missing, causing audio keep-alive to not activate in geofence-only mode.
* **FIX**: `preventSuspendManager.stop()` now called in all stop paths (reset, stopOnStationary, scheduleStop, stopAfterElapsed) — was only called in `handleStop()`.
* **FIX**: `setConfig()` now toggles `preventSuspendManager` mid-session when `preventSuspend` changes.
* **FIX**: `reset()` now calls `cancelStopAfterElapsedTimer()` — was leaving stale timer running after reset.
* **FIX**: iOS 17+/18+ session managers wired into all lifecycle paths (start, stop, startGeofences, reset, scheduleStart/Stop, stopOnStationary, stopAfterElapsed).

## 0.8.0

* **FEAT**: OEM compatibility stubs — `getSettingsHealth` returns `isAggressiveOem: false` (iOS has no OEM power management issues), `openOemSettings` returns `false`.
* **DOCS**: Update README with OEM compatibility note and documentation link.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.8.0.

## 0.7.1

* **DOCS**: Add mock location detection feature to README with platform-specific detection details.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.7.1.

## 0.7.0

* **FEAT**: Mock location detection — `isLocationMock()` uses `CLLocationSourceInformation` (iOS 15+) to detect simulated locations.
* **FEAT**: Heuristic mock detection (level 2) — timestamp drift check (> 10s between location timestamp and system time = suspicious).
* **FEAT**: `buildLocationMap()` includes `mock` flag and `mockHeuristics` metadata map (timestampDriftMs, platformFlagMock).
* **FEAT**: Native-level mock rejection — when `rejectMockLocations` is enabled, drops mocked locations before sending to Dart and fires `ProviderChangeEvent.mockLocationsDetected`.
* **FEAT**: `ConfigManager.getMockDetectionLevel()` and `getRejectMockLocations()` getters.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.7.0.

## 0.6.1

* **REFACTOR**: Remove 6 dead `ConfigManager` methods for filtering migrated to Dart in 0.6.0 (`getDisableElasticity`, `getElasticityMultiplier`, `getFilterPolicy`, `getMaxImpliedSpeed`, `getTrackingAccuracyThreshold`, `getUseKalmanFilter`).
* **REFACTOR**: Remove dead `EventDispatcher.sendTrip()` and `"trip"` channel registration — trip events now from Dart `TripManager`.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.6.1.

## 0.6.0

* **REFACTOR**: Remove duplicate location filtering from `LocationEngine.didUpdateLocations()` — elasticity, distance filter, accuracy filter, and speed filter now handled by shared Dart `LocationProcessor`.
* **REFACTOR**: Replace `GeofenceManager.evaluateHighAccuracyProximity()` with no-op stub — proximity evaluation moved to shared Dart `GeofenceEvaluator`.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.6.0.

## 0.5.5

* **FIX**: `onSchedule` event now sends full state map (via `stateManager.toMap()`) instead of partial `["state": "on", "enabled": true]` — fixes `State.fromMap()` crash on schedule events.

## 0.5.4

* **FIX**: Heartbeat event now wraps location data in `{"location": ...}` to match `HeartbeatEvent.fromMap()` — fixes heartbeat always returning zero coordinates.
* **FIX**: Heartbeat falls back to last known location (via `buildLocationMap()`) when `getCurrentPosition` returns null.

## 0.5.3

* **CHORE**: Bump `tracelet_platform_interface` to ^0.5.3.

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
