## 1.8.6

- **FIX**: `getCurrentPosition(samples: 1)` now forces a fresh GPS fix instead of returning stale cached locations — uses `requestLocationUpdates`/`startUpdatingLocation` instead of `getCurrentLocation`/`requestLocation` which may return cached data without waking GPS hardware (#46).
- **FIX**: HTTP sync headers callback (`setHeadersCallback`) no longer invoked per-batch — eliminates unnecessary MethodChannel round-trip latency on every sync request. Token refresh now handled exclusively via `setTokenRefreshCallback` on 401.
- **FIX**: Headless `FlutterEngine` no longer overwrites foreground `httpSyncManager` callbacks — fixes 10-second timeout on `requestFreshHeaders` caused by MethodChannel messages routed to the wrong Dart isolate.
- **FIX**: Bump native SDKs to 1.0.6.

## 1.8.5

- **FIX**: `getCurrentPosition()` falls back to last known location when GPS returns no fix (e.g. emulator, GPS-off) — fixes `LOCATION_UNAVAILABLE` errors (#46).
- **FIX**: Bump native SDKs to 1.0.5.

## 1.8.4

- **FIX**: Add `isReady` guards to all Android SDK methods — prevents `UninitializedPropertyAccessException` when called before `ready()` (re-fixes #46).
- **FIX**: Pin native SDK dependencies to exact versions — prevents auto-resolving to incompatible newer native SDK releases.

## 1.8.3

- **FIX**: Prevent crash when `getState()`, `setConfig()`, or any other method is called before `ready()` on iOS — comprehensive `isReady` guards across all native SDK methods (re-fixes #46).

## 1.8.2

- **FIX**: Prevent crash when `stop()` is called before `ready()` on iOS — returns `NOT_READY` error instead of accessing uninitialized properties.
- **FIX**: Guard `soundManager` access on Android to prevent `UninitializedPropertyAccessException` during motion state changes or cleanup.
- **FIX**: Use `LocationManagerCompat.isLocationEnabled()` on Android — fixes `NoSuchMethodError` crash on API 26/27 devices.
- **FIX**: Enterprise optional dependencies (SQLCipher, Play Integrity, security-crypto) now gracefully degrade at runtime when not on the classpath — no more `NoClassDefFoundError` crashes.
- **REFACTOR**: Refined ProGuard/R8 consumer rules — narrower keep rules, added `-dontwarn` for optional enterprise dependencies.
- **DOCS**: Updated `INSTALL-ANDROID.md` and `DATABASE-ENCRYPTION.md` with enterprise dependency setup instructions.

## 1.8.1

- **FIX**: iOS periodic mode no longer shows persistent location indicator in the status bar.

## 1.8.0

- **FIX**: Align location map format contract across Android, iOS, and Dart layers — fixes 9 format mismatches.
- **FEAT**: Add `Tracelet.destroySyncedLocations()` — deletes only synced locations, returns count deleted.
- **FEAT**: Auto-purge synced locations from database after successful HTTP sync.
- **TEST**: Add 25 Dart location map format tests.
- **DOCS**: Add `help/LOCATION-MAP-FORMAT.md` canonical format contract reference.

## 1.7.1

- **FIX**: ConfigManager null-merge — partial `setConfig()` no longer overwrites existing values with null defaults (fixes periodic mode HTTP sync failure).
- **FEAT**: Add `Tracelet.destroySyncedLocations()` — deletes only synced locations, returns count deleted.
- **FEAT**: Auto-purge synced locations from database after successful HTTP sync.

## 1.7.0

- **FEAT**: Migrate all event subscriptions from EventChannels to Pigeon FlutterApi platform streams.
- **FEAT**: Add `Location.fromTl` and `LocationActivity.fromTl` factory constructors for Pigeon type conversion.
- **FIX**: Headless geofence events no longer silently dropped on Android task removal (#43).
- **REFACTOR**: Extract native SDKs to standalone modules — Android (Maven Central) and iOS (CocoaPods/SPM).
- **DOCS**: Add local development workflow documentation to CONTRIBUTING.md.

## 1.6.3-alpha.1

- **FEAT**: Migrate all event subscriptions from EventChannels to Pigeon FlutterApi platform streams.
- **FEAT**: Add `Location.fromTl` and `LocationActivity.fromTl` factory constructors for Pigeon type conversion.
- **REFACTOR**: Remove `_eventChannels`, `_eventStreams` maps, and `_getEventStream()` helper.
- **CHORE**: Update cross-package dependency constraints to `^1.6.3-alpha.1`.

## 1.6.2

- **FIX**: Update `tracelet_web` dependency to `^1.6.1` — fixes 5 missing HTTP Sync method stubs that caused `UnimplementedError` on web.

## 1.6.1

- **FEAT**: Add 401-aware retry — native HTTP sync now detects 401 responses, invokes the headless headers callback (`registerHeadlessHeadersCallback`) to refresh authorization tokens, and retries the request once with updated dynamic headers. Works in both foreground and killed-state (headless) modes.

## 1.6.0

- **FEAT**: Add SSL certificate pinning via `HttpConfig.sslPinningCertificates` and `HttpConfig.sslPinningFingerprints`.
- **FEAT**: Add dynamic HTTP headers — `setDynamicHeaders()`, `setHeadersCallback()`, `refreshHeaders()`, and headless `registerHeadlessHeadersCallback()`.
- **FEAT**: Add route context — `setRouteContext()` / `clearRouteContext()` to attach metadata to every synced location.
- **FEAT**: Add custom sync body builder — `setSyncBodyBuilder()` and headless `registerHeadlessSyncBodyBuilder()`.
- **TEST**: Add 19 Dart unit tests for `RouteContext`, `SyncBodyContext`, and `HttpConfig` SSL fields.
- **TEST**: Add 6 MethodChannel mock tests for new platform methods.
- **DOCS**: Update API.md, CONFIGURATION.md, HTTP-SYNC.md with new sync feature documentation.
- **CHORE**: Update cross-package dependency constraints to `^1.6.0`.

## 1.5.0

- **FEAT**: Boot-mode HTTP auto-sync — locations sync to your server even when the app is killed or the device reboots (Android).
- **FIX**: Test server now correctly reads `latitude`/`longitude` from nested `coords` object.
- **CHORE**: Update cross-package dependency constraints to `^1.5.0`.

## 1.4.6

- **FIX**: Rename native `PermissionManager` to `TraceletPermissionManager` to avoid class name collision with `permission_handler_apple` (#32).
- **CHORE**: Update cross-package dependency constraints to `^1.4.6`.

## 1.4.5

- **TEST**: Add integration tests for GPS-off fallback and reduced accuracy field serialization.
- **CHORE**: Update cross-package dependency constraints to `^1.4.5`.

## 1.4.4

- **FEAT**: Add `reducedAccuracy` field to `Location` — `true` when iOS 14+ grants only approximate location authorization.
- **FEAT**: Example app now shows `[REDUCED]` tag and `gpsFallback=ON` indicator for reduced/fallback location states.
- **TEST**: Add 5 unit tests for `reducedAccuracy` field (default, parse, snake_case, round-trip, copyWithCoords).
- **CHORE**: Update cross-package dependency constraints to `^1.4.4`.

## 1.4.3

- **FEAT**: Add `locationSource` field to `Location` — classifies each fix as `gps`, `wifi`, `cell`, `network`, or `unknown`.
- **FEAT**: Add `gpsFallback` field to `ProviderChangeEvent` — signals when the engine auto-downgrades to Wi-Fi/cell positioning because GPS is disabled.
- **CHORE**: Update cross-package dependency constraints to `^1.4.3`.

## 1.4.2

- **FIX**: Dead reckoning activation now reliably detects GPS hardware state instead of using accuracy-based heuristic.
- **FIX**: Mock detection heuristic no longer produces false positives for Wi-Fi/cell locations when GPS is disabled.
- **CHORE**: Update cross-package dependency constraints to `^1.4.2`.

## 1.4.1

- **FEAT**: Dead reckoning — full native IMU sensor fusion for GPS-denied environments (tunnels, parking structures, urban canyons). Activates automatically on GPS loss, deactivates on GPS recovery.
- **CHORE**: Update cross-package dependency constraints to `^1.4.1`.

## 1.4.0

- **FEAT**: Encrypted SQLite — `Tracelet.isDatabaseEncrypted()` and `Tracelet.encryptDatabase()` for at-rest database encryption (SQLCipher on Android, Data Protection on iOS).
- **FEAT**: Device attestation — `Tracelet.getAttestationToken()` returns a platform attestation token (Play Integrity on Android, App Attest on iOS).
- **FEAT**: Remote config — automatic fetch of remote configuration with ETag caching and `onRemoteConfig` event stream.
- **FEAT**: Dead reckoning — `Tracelet.getDeadReckoningState()` stub for future accelerometer/gyroscope-based position estimation.
- **FEAT**: Carbon estimator — `Tracelet.getCarbonReport()` returns CO₂ emission estimates from tracked journeys.
- **FEAT**: Add `SecurityConfig` and `AttestationConfig` to `Config` model for enterprise feature configuration.
- **CHORE**: Update cross-package dependency constraints to `^1.4.0`.

## 1.3.7

- **FIX**: Android — fix `ClassNotFoundException` crash on app upgrade for `BootReceiver` and other manifest-declared components (fixes #31).
- **CHORE**: Update `tracelet_android` dependency constraint to `^1.3.7`.

## 1.3.6

- **FIX**: `SQLQuery.start` and `SQLQuery.end` now correctly filter locations on all platforms (Android, iOS, Web).
- **FIX**: Add `offset` field to `SQLQuery` to match native handler expectations.
- **FIX**: `getCount()` now accepts optional `SQLQuery` for time-bounded counting.
- **PERF**: `DeltaEncoder.encode` is 2.1x faster (cached DateTime parsing, precomputed rounding factors).
- **PERF**: `GeoUtils.haversine` optimized — fewer trig calls, precomputed constants.
- **CHORE**: Update cross-package dependency constraints to `^1.3.6`.

## 1.3.5

- **FIX**: iOS — fix `Unable to find module dependency: 'TraceletCore'` build error.
- **CHORE**: Update cross-package dependency constraints to `^1.3.5`.

## 1.3.4

- **CHORE**: Update cross-package dependency constraints to `^1.3.3`.

## 1.3.3

- **FIX**: Android — bundle native core Kotlin source (`com.tracelet.core.*`) directly inside the plugin package, fixing "Unresolved reference" build errors when installed from pub.dev.
- **FIX**: iOS — bundle TraceletCore Swift source directly inside the plugin package instead of depending on an unpublished local CocoaPod.
- **CHORE**: Remove React Native support to simplify the monorepo.

## 1.3.2

- **PERF**: Android — streaming `JsonWriter` replaces per-location `JSONObject` allocations in batch sync (A-L5).
- **PERF**: iOS — C-level UUID generation replaces Foundation `UUID()` in `LocationEngine` and `TraceletDatabase` (I-M6).
- **PERF**: Performance audit now 77/77 items resolved (100%).

## 1.3.1

- **FIX**: Resolve `extras` key collision between `HttpConfig` and `PersistenceConfig` — serialization keys renamed to `httpExtras` and `persistenceExtras` to prevent native ConfigManager flat-merge from overwriting one with the other. Backward-compatible via `fromMap` fallback.
- **PERF**: Add 22 new benchmarks covering DeltaEncoder, BatteryBudgetEngine, CarbonEstimator, PersistDecider, Config/State serialization.
- **PERF**: iOS `markSynced()` now uses chunked prepared statements (500 UUIDs/chunk) to avoid SQLite variable limit and improve sync performance.

## 1.3.0

- **FIX**: `getState()` always returned `enabled: false` on iOS — the iOS `StateManager.toMap()` flat-merged config keys into the state dictionary, overwriting `enabled` and `isMoving` with config defaults. Fixed by nesting config under a `"config"` key, matching Android behavior ([#26](https://github.com/Ikolvi/Tracelet/issues/26)).

## 1.2.0

### Breaking Changes

- **REFACTOR**: `ForegroundServiceConfig.notificationPriority` changed from `int` to `NotificationPriority` enum. Replace raw integers (`-2`..`2`) with enum values (`NotificationPriority.min`, `.low`, `.defaultPriority`, `.high`, `.max`).
- **REFACTOR**: `AuditConfig.hashAlgorithm` changed from `String` to `HashAlgorithm` enum. Replace `'SHA-256'` with `HashAlgorithm.sha256`, `'SHA-512'` with `HashAlgorithm.sha512`, etc.
- **REFACTOR**: `MotionConfig.triggerActivities` changed from comma-separated `String` to `Set<ActivityType>`. Replace `'on_foot, in_vehicle'` with `{ActivityType.onFoot, ActivityType.inVehicle}`.

### Notes

- Native platform channel serialization is backward-compatible — no native code changes required. `notificationPriority` still serializes as int, `hashAlgorithm` as `"SHA-256"` string, and `triggerActivities` as comma-separated string.

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
