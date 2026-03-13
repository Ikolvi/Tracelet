## 1.1.0

### New Features

- **FEAT**: Add `ComplianceReport` model and `Tracelet.generateComplianceReport()` API for GDPR Article 30 / CCPA data processing inventory reports. Auto-generates a structured snapshot of all location data collection metadata including: `totalLocationsStored`, `totalLocationsSynced`, data retention policy (`maxDaysToPersist`, `maxRecordsToPersist`), timestamp bounds of stored records (`oldestRecord`, `newestRecord`), database encryption status, active privacy zone count and identifiers, HTTP sync URL and auto-sync state, audit trail status with chain validation, permission states (location + motion), and tracking configuration flags (sparse updates, Kalman filter, delta compression, tracking mode). Supports `toJson()` for automated tooling integration and `toMarkdown()` for human-readable audit documents.
- **FEAT**: Add `BatteryBudgetEngine` algorithm — a feedback control loop that automatically adjusts `distanceFilter`, `desiredAccuracy`, and periodic interval to maintain a configurable battery budget. Set `batteryBudgetPerHour` in `GeoConfig` (typical range: 1.0–5.0 %/hr) to enable. Subscribe to `Tracelet.onBudgetAdjustment()` for real-time adjustment events showing current drain vs. target and the new parameters being applied.
- **FEAT**: Add `CarbonEstimator` — per-trip and cumulative CO₂ emission calculator using EU EEA 2024 mode-specific emission factors (gCO₂/km): car = 192, bus = 89, train = 41, walking/cycling = 0. Integrates with activity recognition to track distance per transport mode via Haversine. Returns `TripCarbonSummary` with `totalCarbonGrams`, `totalDistanceMeters`, `carbonByMode`, `distanceByMode`, and `dominantMode`. Tracks cumulative totals across trips.
- **FEAT**: Add `DeltaEncoder` algorithm — batch location compression codec using delta encoding with 60–80% payload reduction. First location transmitted in full; subsequent positions as deltas with shortened field names and configurable coordinate precision (5 = ~1.1 m, 6 = ~0.11 m). Native implementations provided on Android (Kotlin) and iOS (Swift) for consistency.
- **FEAT**: Add `RTree<T>` spatial index — O(log n) geofence proximity queries supporting 10,000+ geofences with sub-millisecond lookup. Provides `queryCircle()` and `queryBBox()` APIs with Haversine-verified results.

### New Configuration Fields

- **FEAT**: `GeoConfig.batteryBudgetPerHour` (`double`, default `0.0`) — target max battery drain (%/hr). When > 0, enables `BatteryBudgetEngine` which auto-adjusts accuracy, distance filter, and sample rate. Overrides manual settings.
- **FEAT**: `GeoConfig.enableSparseUpdates` (`bool`, default `false`) — app-level deduplication that drops locations within `sparseDistanceThreshold` (default 50 m) of the last recorded position. Unlike `distanceFilter` (which controls platform GPS sampling), this filters at the persistence layer. `sparseMaxIdleSeconds` (default 300) forces periodic "still here" updates.
- **FEAT**: `GeoConfig.enableDeadReckoning` (`bool`, default `false`) — inertial navigation using accelerometer + gyroscope + compass when GPS is lost for longer than `deadReckoningActivationDelay` seconds (default 10). Auto-stops after `deadReckoningMaxDuration` seconds (default 120) to prevent IMU drift accumulation.
- **FEAT**: `HttpConfig.enableDeltaCompression` (`bool`, default `false`) — enable delta encoding for batch HTTP syncs. `deltaCoordinatePrecision` (default 6) controls coordinate precision.
- **FEAT**: `HttpConfig.disableAutoSyncOnCellular` (`bool`, default `false`) — skip auto-sync on cellular networks, only sync on WiFi. Supported on Android, iOS, and Web (via Network Information API).
- **FEAT**: `GeoConfig.enableAdaptiveMode` (`bool`, default `false`) — dynamic sampling based on activity type + battery level + charging state. Activity profiles: still → 500 m, walking → 50 m, driving → 10 m; battery scaling progressively widens filter below 50%/20%/10%.
- **FEAT**: Periodic mode configuration: `periodicLocationInterval` (60–43200 sec), `periodicDesiredAccuracy`, `periodicUseForegroundService` (Android — sub-15-min intervals), `periodicUseExactAlarms` (Android — `AlarmManager` precision).

### Bug Fixes

- **FIX**: `generateComplianceReport()` and `getHealthCheck()` no longer crash with `type 'Map<Object?, Object?>' is not a subtype of type 'Map<String, Object?>'` errors. Platform channel maps are now safely converted via `Map<String, Object?>.from()` instead of direct `as` casts. Also fixed nested config sub-map casts (`config`, `geo`, `http`, `audit`, `persistence`) using null-safe `is Map` checks.

### Infrastructure

- **CHORE**: Migrate melos configuration from standalone `melos.yaml` to `pubspec.yaml` under the `melos:` key for melos 7.x compatibility. All 13 scripts (analyze, format, format:fix, test, test:dart, pigeon, clean, pub:get, build:example:android/ios/web, coverage, benchmark) now run via `melos run <name>`.
- **CHORE**: Adopt Dart pub workspaces — root `pubspec.yaml` declares `workspace:` listing all 6 packages; each package declares `resolution: workspace`. Removed 5 `pubspec_overrides.yaml` files that are no longer needed.
- **CHORE**: Upgrade melos dependency from `^6.0.0` to `^7.0.0`.

## 1.0.2

- **FIX**: (Android/iOS) Geofence registrations were unconditionally destroyed on app termination and reset, even when `stopOnTerminate: false` was configured with `trackingMode=1`. Geofences now survive process death and are properly re-registered ([#23](https://github.com/Ikolvi/Tracelet/issues/23)).

## 1.0.1

- **FIX**: HTTP auto-sync was not triggered during automatic location tracking on any platform — locations accumulated in the database without being synced to the server ([#21](https://github.com/Ikolvi/Tracelet/issues/21)).
- **FIX**: (iOS) `HttpMethod.put` was silently ignored due to type mismatch in native config parsing.
- **FIX**: (iOS) HTTP headers could be dropped when platform channel delivered mixed-type maps.
- **FIX**: (iOS) `maxBatchSize` default corrected from 100 to 250.

## 1.0.0

### 🎉 Stable Release

- **FEAT**: First stable release of `tracelet` — production-grade background geolocation for Flutter.
- **DOCS**: Add Play Store background location declaration guide.
- **REFACTOR**: Remove third-party company name references — use generic `flutter_background_geolocation` throughout.
- **REFACTOR**: Rename migration guide to `MIGRATION-FROM-FBG.md`.
- All APIs are finalized and production-ready.

## 0.12.0

### Performance Audit — 74 of 77 issues resolved

- **PERF**: Cache `AdaptiveSamplingEngine` instance instead of re-creating per GPS fix (D-C1).
- **PERF**: Add `Location.copyWithCoords()` to eliminate `toMap()/fromMap()` round-trip in Kalman filter hot path (D-C2).
- **PERF**: Wire trip detection to processed location stream, eliminating duplicate `Location.fromMap()` (D-H1).
- **PERF**: Fast-path `_castToMap` with type check — avoids map copy when already correct type (D-H2).
- **PERF**: Replace `.expand()` with `.where()` in `_filterLocation` to avoid single-element list allocations (D-H4).
- **PERF**: Cancel adaptive activity subscription in `removeListeners()` (D-H7).
- **PERF**: Use `.toList(growable: false)` for `addGeofences`/`addPrivacyZones` result lists (D-M6).
- **PERF**: Invalidate cached stream pipeline on `setConfig()` so it rebuilds with new settings (D-M8).
- **PERF**: Use `Map.from()` instead of `.map()` with `MapEntry` for extras in `Location.fromMap()` (D-L4).
- **REFACTOR**: Deduplicate `LocationProcessor` parameter list in `setConfig()` (D-L5).

## 0.11.5

- **FIX**: [Android/iOS] Polygon geofence `vertices` are now correctly persisted to the native SQLite databases. Previously, vertex data was silently dropped during `addGeofence()`, causing polygon geofences to revert to circular after app restart.

## 0.11.4

- **FIX**: [iOS] Revert over-aggressive permission guards — When In Use permission now works correctly for all tracking modes. Only the killed-state auto-resume (`autoResumeTracking`) requires Always authorization. iOS enforces permission at the OS level.

## 0.11.3

- **FIX**: [Android] Enforce `ACCESS_BACKGROUND_LOCATION` check on all killed-state restart paths (boot receiver, task removal, periodic alarms/workers). "While In Use" permission no longer triggers background tracking.
- **FIX**: [iOS] Enforce `.authorizedAlways` check on killed-state auto-resume and guard `allowsBackgroundLocationUpdates`. "When In Use" permission no longer triggers tracking from killed state.- **FEAT**: Add `Tracelet.hasBackgroundPermission` static getter — convenience check that returns `true` when location permission is `AuthorizationStatus.always`.
## 0.11.2

- **DOCS**: Fix 22 unresolved dartdoc references (`[Enterprise]`, `[Config.*]`, `[isValid]`, `[brokenAtIndex]`, `[brokenAtUuid]`).
- **CHORE**: Tighten all platform package constraints to `^0.11.2` (fixes `pub downgrade` score penalty).

## 0.11.1

- **FEAT**: Add `canScheduleExactAlarms()` and `openExactAlarmSettings()` static methods for Android exact alarm permission management.
- **FIX**: Bypass `LocationProcessor` distance/accuracy/speed filters for periodic location events — every timed fix is now delivered regardless of movement.
- **CHORE**: Bump platform interface to 0.11.1.

## 0.11.0

- **FEAT**: Tamper-proof audit trail — SHA-256 hash chain for location integrity verification.
- **FEAT**: Privacy zones — exclude, degrade, or event-only actions for geographic privacy control.
- **FEAT**: `AuditConfig` sub-config with `enabled`, `hashAlgorithm`, `includeExtrasInHash` options.
- **FEAT**: `PrivacyZoneConfig` sub-config with `enabled` toggle.
- **FEAT**: `PrivacyZone` model with `identifier`, `latitude`, `longitude`, `radius`, `action`, `degradedAccuracyMeters`.
- **FEAT**: `AuditProof` model for hash chain verification results.
- **FEAT**: CRUD API: `addPrivacyZone()`, `addPrivacyZones()`, `removePrivacyZone()`, `removePrivacyZones()`, `getPrivacyZones()`.
- **FEAT**: Audit API: `getAuditTrail()`, `verifyAuditTrail()`, `getAuditProof()`.
- **DOCS**: Added AUDIT-TRAIL.md and PRIVACY-ZONES.md guides.
- **CHORE**: Bump all platform packages to ^0.11.0.

## 0.10.0

- **FEAT**: Periodic mode — `Tracelet.startPeriodic()` for GPS-friendly interval tracking. GPS icon visible only ~5–10 seconds per fix instead of permanently.
- **FEAT**: `GeoConfig` periodic options: `periodicLocationInterval`, `periodicDesiredAccuracy`, `periodicUseForegroundService`, `periodicUseExactAlarms`.
- **FEAT**: Three Android scheduling strategies: WorkManager (default, battery-optimal), foreground service (reliable timing), and AlarmManager exact alarms (precise, no notification).
- **FEAT**: Example app: periodic mode UI section with start/stop toggle, custom settings dialog, and map integration with distinct cyan markers.
- **DOCS**: Updated API.md, CONFIGURATION.md, BACKGROUND-TRACKING.md, and INSTALL-ANDROID.md with periodic mode and exact alarms documentation.
- **CHORE**: Bump all platform packages to ^0.10.0.

## 0.9.1

- **FIX**: iOS `HttpSyncManager` optional `UIBackgroundTaskIdentifier` unwrap safety.

## 0.9.0

* **FEAT**: Adaptive sampling engine — auto-adjusts `distanceFilter` based on detected activity type, battery level, and speed. Enable with `GeoConfig(enableAdaptiveMode: true)`. See [Adaptive Sampling Guide](https://github.com/Ikolvi/Tracelet/blob/main/help/ADAPTIVE-SAMPLING.md).
* **FEAT**: Health check API — `Tracelet.getHealth()` returns a comprehensive diagnostic snapshot covering tracking state, permissions, battery, sensors, database, and geofence state with actionable `HealthWarning` enum. See [Health Check Guide](https://github.com/Ikolvi/Tracelet/blob/main/help/HEALTH-CHECK.md).
* **FEAT**: HTTP sync retry metadata — `HttpEvent` now includes `isRetry` and `retryCount` fields.
* **FEAT**: Configurable motion sensitivity — `MotionConfig` gains `shakeThreshold`, `stillThreshold`, and `stillSampleCount` for tuning accelerometer-based motion detection.
* **FEAT**: `HealthWarningDescription` extension with `.description` getter for human-readable warning text.
* **CHORE**: Bump all platform dependencies to ^0.9.0.

## 0.8.3

* **FEAT**: Unlimited geofences via proximity-based auto-load/unload — only geofences within `geofenceProximityRadius` are registered with the OS (up to 100 on Android, 20 on iOS), sorted by distance. Enables monitoring thousands of geofences despite platform limits.
* **FEAT**: `geofencesChange` event fires when geofences are activated/deactivated from proximity monitoring.
* **CHORE**: Bump all platform dependencies to ^0.8.3.

## 0.8.2

* **DOCS**: Improve README visuals with combined Android & iOS demo image.

## 0.8.1

* **PERF**: iOS background hardening — all native operations (location persist, HTTP sync, headless engine boot, lifecycle transitions) now wrapped in `beginBackgroundTask` for safe background execution.
* **FEAT**: iOS 17+ `CLBackgroundActivitySession` support — extends background runtime for location tracking.
* **FEAT**: iOS 18+ `CLServiceSession` support — maintains authorization state during background execution.
* **FIX**: iOS `preventSuspend` lifecycle gaps — audio keep-alive now correctly started/stopped in all tracking modes and transitions.
* **FIX**: Web EventChannel bridge — all event streams (`onLocation`, `onMotionChange`, `onHeartbeat`, etc.) were broken on web due to events being consumed but never forwarded. Now works correctly.
* **CHORE**: Bump `tracelet_ios` to ^0.8.1, `tracelet_web` to ^0.8.1.

## 0.8.0

* **FEAT**: OEM compatibility — automatic mitigations for aggressive OEM power management (Huawei, Xiaomi, OnePlus, Samsung, Oppo, Vivo).
* **FEAT**: `Tracelet.getSettingsHealth()` — device health API returning manufacturer, aggression rating, battery optimization status, and available OEM settings screens.
* **FEAT**: `Tracelet.openOemSettings(label)` — open OEM-specific settings screens (autostart, battery saver, app launch) by label.
* **DOCS**: Comprehensive [OEM-COMPATIBILITY.md](help/OEM-COMPATIBILITY.md) guide with per-manufacturer instructions.
* **DOCS**: Update README with OEM compatibility feature and documentation link.
* **CHORE**: Bump all platform dependencies to ^0.8.0.

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
