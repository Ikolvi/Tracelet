## 1.8.4

- **FIX**: Add `isReady` guards to all Android SDK methods — prevents `UninitializedPropertyAccessException` when called before `ready()` (re-fixes #46).
- **FIX**: Pin native SDK dependency to exact version `1.0.4` — prevents auto-resolving to incompatible newer releases.

## 1.8.3

- **FIX**: Add `isReady` guards to all Android SDK methods — prevents `UninitializedPropertyAccessException` when called before `ready()` (re-fixes #46).
- **CHORE**: Bump native SDK dependency `com.ikolvi:tracelet-sdk` 1.0.2 → 1.0.3.

## 1.8.2

- **FIX**: Guard `soundManager` access in `handleMotionStateChange()` and `destroyAll()` — prevents `UninitializedPropertyAccessException` if motion detector fires before full initialization.
- **FIX**: Use `LocationManagerCompat.isLocationEnabled()` instead of `LocationManager.isLocationEnabled()` — fixes crash on Android API 26/27.
- **FIX**: Enterprise dependencies (SQLCipher, Play Integrity, security-crypto) now degrade gracefully when absent — runtime `Class.forName` checks prevent `NoClassDefFoundError`.
- **FIX**: `DeviceAttestor` uses lazy `IntegrityManagerFactory` initialization — prevents crash when Play Integrity is not on the classpath.
- **REFACTOR**: Refined ProGuard/R8 consumer rules — narrower keep rules, `-dontwarn` for optional deps.
- **TEST**: Add `destroyAll_doesNotCrash_withoutSoundManager` unit test.

## 1.8.1

- **CHORE**: Version bump for iOS periodic mode location indicator fix.

## 1.8.0

- **FIX**: ConfigManager null-merge — partial `setConfig()` no longer overwrites existing non-null values (e.g. HTTP URL) with null defaults.
- **FIX**: PeriodicLocationWorker catch block now re-schedules the next exact alarm before returning `Result.retry()`, preventing permanent chain breaks on exceptions.
- **FIX**: GeofenceBroadcastReceiver bootstraps SDK when app is killed and `geofenceManager` is null, instead of silently dropping events.
- **FIX**: Align location map format — `isCharging` → `is_charging`, flat coords → nested `coords` map, add `activity` map, `isMock` → `mock`.
- **FIX**: DB `cursorToLocation` outputs `is_charging` in battery map.
- **FEAT**: Add `destroySyncedLocations()` — deletes only synced locations from the database.
- **FEAT**: Auto-purge synced locations after successful HTTP sync in `HttpSyncManager`.
- **TEST**: Add 28 location map format tests, 5 unit tests for ConfigManager null-merge and `destroySyncedLocations`.

## 1.7.1

- **FIX**: ConfigManager null-merge — partial `setConfig()` no longer overwrites existing non-null values (e.g. HTTP URL) with null defaults.
- **FIX**: PeriodicLocationWorker catch block now re-schedules the next exact alarm before returning `Result.retry()`, preventing permanent chain breaks on exceptions.
- **FIX**: GeofenceBroadcastReceiver bootstraps SDK when app is killed and `geofenceManager` is null, instead of silently dropping events.
- **FEAT**: Add `destroySyncedLocations()` — deletes only synced locations from the database.
- **FEAT**: Auto-purge synced locations after successful HTTP sync in `HttpSyncManager`.
- **TEST**: Add 5 unit tests for ConfigManager null-merge protection, `deleteSyncedLocations`, and `destroySyncedLocations` facade.

## 1.7.0

- **FIX**: Wire `headlessFallback` in `eventSenderFactory` — fixes geofence events silently dropped on task removal (#43).
- **FIX**: Add missing `sendTrip`/`sendBudgetAdjustment` to `NoOpEventSender`.
- **FEAT**: Rewrite `EventDispatcher` to use Pigeon `TraceletEventApi` FlutterApi.
- **FEAT**: Add `TraceletHostApiImpl` for type-safe Pigeon HostApi dispatch.
- **REFACTOR**: Extract native SDK to standalone `sdk/android/` module (Maven Central: `com.ikolvi:tracelet-sdk`).
- **REFACTOR**: Remove misleading headless wiring dead code in `LocationService.startBootTracking()`.
- **CHORE**: Enable `returnDefaultValues` for Android unit tests.

## 1.6.3-alpha.1

- **FEAT**: Rewrite `EventDispatcher` to use Pigeon `TraceletEventApi` FlutterApi instead of EventChannels.
- **FEAT**: Add `TraceletHostApiImpl` for type-safe Pigeon HostApi dispatch.
- **REFACTOR**: Extract native SDK code to `sdk/android/` module.
- **CHORE**: Update cross-package dependency constraints to `^1.6.3-alpha.1`.

## 1.6.1

- **FEAT**: Add 401-aware retry — on HTTP 401 Unauthorized, invoke headless headers callback to refresh token, then retry once with updated dynamic headers.

## 1.6.0

- **FEAT**: Add SSL certificate pinning — support for PEM certificates (`CertificatePinner`) and SHA-256 fingerprints (`HandshakeCertificates`) via OkHttp TLS.
- **FEAT**: Add dynamic HTTP headers with runtime callback support and headless background execution.
- **FEAT**: Add route context — attach arbitrary metadata to synced locations.
- **FEAT**: Add custom sync body builder with headless callback support.
- **TEST**: Add `ConfigManagerSyncFeaturesTest` — 12 Robolectric unit tests for sync features.
- **CHORE**: Add `okhttp-tls:5.3.2` dependency.
- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.6.0`.

## 1.5.0

- **FEAT**: Add boot-mode `HttpSyncManager` — locations are auto-synced to the server even when the app is killed or the device reboots.
- **FEAT**: Periodic-mode (WorkManager/ExactAlarm) now creates a dedicated boot-mode `HttpSyncManager` so periodic locations sync without the Flutter engine.
- **TEST**: Add Robolectric unit tests for boot-mode HTTP sync lifecycle.
- **DOCS**: Add "Background / Killed-State Sync" section to HTTP-SYNC.md.
- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.5.0`.

## 1.4.6

- **FIX**: Rename `PermissionManager` to `TraceletPermissionManager` to avoid class name collision with `permission_handler_apple` (#32).
- **CHORE**: Bump `kotlin-gradle-plugin` 2.3.10 → 2.3.20.
- **CHORE**: Bump `androidx.sqlite:sqlite` 2.4.0 → 2.6.2.
- **CHORE**: Bump `com.google.android.play:integrity` 1.4.0 → 1.6.0.
- **CHORE**: Bump `org.mockito.kotlin:mockito-kotlin` 5.4.0 → 6.3.0.
- **CHORE**: Bump `androidx.security:security-crypto` 1.1.0-alpha06 → 1.1.0 (stable).
- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.6`.

## 1.4.5

- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.5`.

## 1.4.4

- **FEAT**: Add `reducedAccuracy` field to location map for cross-platform API consistency with iOS 14+.
- **TEST**: Add Robolectric unit tests for GPS fallback utilities (provider state transitions, location source classification).
- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.4`.

## 1.4.3

- **FEAT**: Automatic GPS-off fallback — when GPS hardware is disabled, the engine auto-downgrades to `PRIORITY_BALANCED_POWER_ACCURACY` for Wi-Fi/cell tower fixes. Restores original priority when GPS is re-enabled.
- **FEAT**: Add `locationSource` classification to every location fix (`gps`, `wifi`, `cell`, `network`, `unknown`).
- **FEAT**: Add `gpsFallback` flag to provider state for Dart-side awareness of fallback state.
- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.3`.

## 1.4.2

- **FIX**: Dead reckoning activation now uses `LocationManager.isProviderEnabled(GPS_PROVIDER)` instead of accuracy heuristic — Wi-Fi/cell fixes no longer prevent DR from activating when GPS hardware is disabled.
- **FIX**: Mock detection heuristic no longer false-flags Wi-Fi/cell locations as mock when GPS is disabled (satellite count 0 is expected without GPS hardware).
- **FIX**: `activateDeadReckoning()` now retries via timer instead of silently returning when `lastLocation` is null.
- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.2`.

## 1.4.1

- **FEAT**: Dead reckoning — full IMU sensor fusion implementation (`DeadReckoningEngine`). Pedestrian Dead Reckoning with step detection (Weinberg formula) and magnetic heading. Vehicle mode with high-pass-filtered acceleration integration.
- **FEAT**: Auto-activation on GPS loss after configurable delay, auto-deactivation on GPS recovery or max duration.
- **CHORE**: Add dead reckoning config getters to `ConfigManager`.
- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.1`.

## 1.4.0

- **FEAT**: Encrypted SQLite — database encryption via SQLCipher with Android Keystore-backed key management (`DatabaseEncryptionManager`).
- **FEAT**: Device attestation — Play Integrity API integration with nonce generation, token caching, and periodic refresh (`DeviceAttestor`).
- **FEAT**: Remote config — fetch remote configuration via HTTPS with ETag caching and config-change event streaming.
- **FEAT**: Dead reckoning — `getDeadReckoningState()` stub for future accelerometer/gyroscope-based position estimation.
- **FEAT**: Carbon estimator — `getCarbonReport()` returns CO₂ estimates from tracked locations using EU average emission factors.
- **CHORE**: Add `net.zetetic:sqlcipher-android`, `androidx.sqlite:sqlite`, `androidx.security:security-crypto`, and `com.google.android.play:integrity` dependencies.
- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.0`.

## 1.3.7

- **FIX**: Fix `ClassNotFoundException` crash for `BootReceiver`, `GeofenceBroadcastReceiver`, `PeriodicAlarmReceiver`, and `LocationService` caused by package path mismatch in `AndroidManifest.xml` (fixes #31).
- **FIX**: Fix foreground notification not appearing due to `LocationService` not being resolved from the manifest.
- **FIX**: Fix ProGuard/R8 consumer rules referencing wrong package paths — prevents class stripping in release builds.
- **FIX**: Fix pre-existing test compilation errors caused by missing cross-package imports.
- **CHORE**: Update cross-package dependency constraints to `^1.3.7`.

## 1.3.6

- **FIX**: `getLocations()` now honors `SQLQuery.start` and `SQLQuery.end` timestamp filtering.
- **FIX**: `getCount()` now accepts optional `SQLQuery` for time-bounded counting.
- **CHORE**: Update cross-package dependency constraints to `^1.3.6`.

## 1.3.5

- **CHORE**: Update cross-package dependency constraints to `^1.3.5`.

## 1.3.4

- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.3.3`.

## 1.3.3

- **FIX**: Bundle native core Kotlin source files (`com.tracelet.core.*`) directly inside the plugin package so they are included when published to pub.dev. Previously, the build.gradle referenced sources via a relative monorepo path that was inaccessible to pub.dev consumers.

## 1.3.2

- **PERF**: Replace per-location `JSONObject` allocations with streaming `android.util.JsonWriter` in `HttpSyncManager.buildJsonBody()` (A-L5).

## 1.3.1

- **FIX**: `getHttpExtras()` and `getPersistenceExtras()` now read distinct config keys (`httpExtras`, `persistenceExtras`) with backward-compatible fallback.

## 1.3.0

- **CHORE**: Version bump for federation consistency with `tracelet` 1.3.0.

## 1.2.0

- **CHORE**: Version bump for federation consistency with `tracelet_platform_interface` 1.2.0 (new `NotificationPriority` and `HashAlgorithm` enums).

## 1.1.0

### New Features

- **FEAT**: Add native `DeltaEncoder` (Kotlin) for delta-compressed HTTP sync payloads — mirrors the Dart implementation exactly for platform consistency. Encodes only field deltas between consecutive locations using shortened keys (`la`, `lo`, `t`, `s`, `h`, `a`, `al`, `b`), achieving 60–80% bandwidth reduction. Uses `java.time.Instant` for ISO 8601 timestamp parsing with flexible numeric type coercion.
- **FEAT**: `ConfigManager` now reads and applies the following new configuration fields from Dart: `batteryBudgetPerHour` (adaptive battery budget target), `enableSparseUpdates`, `sparseDistanceThreshold`, `sparseMaxIdleSeconds` (app-level deduplication), `enableDeadReckoning`, `deadReckoningActivationDelay`, `deadReckoningMaxDuration` (inertial navigation when GPS lost), `enableDeltaCompression`, `deltaCoordinatePrecision` (HTTP delta encoding), and `disableAutoSyncOnCellular` (WiFi-only sync).
- **FEAT**: `HttpSyncManager` now supports `disableAutoSyncOnCellular` — skips auto-sync when device is on cellular network, syncing only on WiFi. Also conditionally applies `DeltaEncoder.encode()` to multi-location batches before HTTP upload when `enableDeltaCompression` is enabled, reducing upload size by 60–80%.

## 1.0.2

- **FIX**: `destroyAll()` unconditionally removed geofence registrations from Play Services even when `stopOnTerminate: false` was configured with `trackingMode=1` (geofence mode). Geofences now survive app termination and are re-registered on boot/task-removal ([#23](https://github.com/Ikolvi/Tracelet/issues/23)).

## 1.0.1

- **FIX**: HTTP auto-sync never triggered from automatic location tracking — `onLocationInserted()` was only called from the manual `insertLocation` handler, not from `LocationEngine.persistLocationIfAllowed()` ([#21](https://github.com/Ikolvi/Tracelet/issues/21)).
- **FIX**: `PeriodicLocationWorker` now triggers HTTP auto-sync after each periodic location insert.

## 1.0.0

### 🎉 Stable Release

- **FEAT**: First stable release of `tracelet_android`.
- **DOCS**: Add Play Store background location declaration guide.
- **REFACTOR**: Remove third-party company name references.
- All native Android APIs are finalized and production-ready.

## 0.12.0

### Performance Audit — 29 Android issues resolved

- **PERF**: Add 10-minute wakelock timeout to prevent indefinite CPU wake (A-C1).
- **PERF**: Cache battery info with 30s TTL — eliminates sticky broadcast IPC per location (A-C2).
- **PERF**: Replace N+1 audit trail verification with JOIN query (A-C3).
- **PERF**: Add in-memory privacy zone cache with CRUD invalidation (A-C4).
- **PERF**: Add in-memory geofence cache with CRUD invalidation (A-C5).
- **PERF**: Cache `SimpleDateFormat` as static `isoFormatter` (A-H1).
- **PERF**: Throttle DB pruning to every 100 inserts instead of every insert (A-H2, A-H3).
- **PERF**: Add `@Volatile` to `isRunning` in `LocationService` (A-H4).
- **PERF**: Add `@Volatile` to sync flags in `HttpSyncManager` (A-H5).
- **PERF**: Use `ThreadLocal<MessageDigest>` for thread-safe SHA-256 (A-H6).
- **PERF**: Use cached location for heartbeat events instead of activating GPS (A-H7).
- **PERF**: Remove duplicate flat keys from platform channel location maps (A-H8).
- **PERF**: Add LIMIT 5000 to `getLog()` query (A-H9).
- **PERF**: Singleton `ConfigManager` with double-checked locking (A-M1).
- **PERF**: Add `Locale.US` to all `String.format()` in `buildCanonicalString()` (A-M2).
- **PERF**: Pre-compiled hex lookup table for SHA-256 byte-to-hex conversion (A-M3).
- **PERF**: Smart config restart — only restart location engine when location-relevant keys change (A-M4).
- **PERF**: Rely on wakelock auto-release timeout in `BootReceiver` (A-M5).
- **PERF**: Use `ConcurrentHashMap.newKeySet()` for `activeGeofenceIds` (A-M6).
- **PERF**: Track insert count to avoid `SELECT COUNT(*)` for auto-sync threshold (A-M7).
- **PERF**: Add `created_at` index on locations table (DB v5) (A-M8).
- **PERF**: Apply `deferTime` to `LocationRequest.setMaxUpdateDelayMillis()` (A-M9).
- **PERF**: Add `@Volatile` to `consecutiveStillSamples` in `MotionDetector` (A-M10).
- **PERF**: Resolve cursor column indices once before loop in `cursorToLocationList()` (A-L1).
- **PERF**: Use `equals(ignoreCase = true)` instead of `uppercase()` allocation in logger (A-L2).
- **PERF**: Remove unnecessary `toMutableMap()` in `watchPosition()` (A-L3).
- **PERF**: Extract `ParsedSchedule` data class to deduplicate schedule parsing (A-L4).
- **PERF**: Use `setOf()` instead of `listOf()` for OEM manufacturer detection (A-L6).
- **REFACTOR**: Remove trivial `isMoreRestrictive()` wrapper, inline `isActionMoreRestrictive()` call.
- **CHORE**: Bump DB version from 4 to 5 (v4→v5 migration adds `created_at` index).

## 0.11.5

- **FIX**: Persist polygon geofence `vertices` to SQLite — add `vertices TEXT` column, DB migration v3→v4, and JSON serialization/deserialization in `insertGeofence()`/`cursorToGeofence()`.
- **FIX**: Skip malformed vertex entries instead of coercing invalid coordinates to `0.0`; require ≥ 3 valid vertices for polygon storage.
- **TEST**: Add Robolectric tests for geofence vertices CRUD (11 tests covering round-trip, validation, edge cases).
- **TEST**: Add DB migration integration tests — v3→v4 and v1→v4 upgrade paths, existing data preservation, fresh install.

## 0.11.4

- **CHORE**: Version bump for platform consistency.

## 0.11.3

- **FIX**: Add `ACCESS_BACKGROUND_LOCATION` permission checks to all killed-state restart paths — `BootReceiver`, `LocationService.onTaskRemoved()`, `LocationService.startBootTracking()`, `PeriodicAlarmReceiver`, and `PeriodicLocationWorker`. Prevents "While In Use" permission from triggering tracking in killed/boot state.
- **FEAT**: New `hasBackgroundPermission()` utility on `LocationEngine` for proactive background permission verification.

## 0.11.2

- **CHORE**: Tighten `tracelet_platform_interface` constraint to `^0.11.2`.

## 0.11.1

- **FIX**: Auto-select exact alarms for periodic intervals < 15 min without foreground service.
- **FIX**: Re-scheduling chain in `PeriodicLocationWorker.doWork()` now uses `interval < 900` auto-detect to match initial scheduling strategy.
- **FIX**: Doze-safe alarm fallback — changed `set()` to `setAndAllowWhileIdle()` in `scheduleExactAlarm()`.
- **FIX**: Re-wire `EventDispatcher` in `onAttachedToEngine()` when periodic mode is already active (fixes null dispatcher after process restart).
- **FIX**: Preserve periodic alarms in `destroyAll()` when `stopOnTerminate=false` and periodic tracking is active.
- **FEAT**: Add `canScheduleExactAlarms` and `openExactAlarmSettings` method channel handlers.
- **CHORE**: Bump platform interface to 0.11.1.

## 0.11.0

- **FEAT**: `AuditTrailManager` — SHA-256 hash chain with SQLite persistence and SharedPreferences chain state.
- **FEAT**: `PrivacyZoneManager` — Haversine distance-based zone evaluation with exclude, degrade, and event-only actions.
- **FEAT**: Privacy zones database table with CRUD operations (v2→v3 migration).
- **FEAT**: Audit trail database table with hash chain linkage.
- **FEAT**: `ConfigManager` getters for audit and privacy zone configuration.
- **CHORE**: Bump `tracelet_platform_interface` to ^0.11.0.

## 0.10.0

- **FEAT**: Periodic mode — GPS-friendly interval tracking via `startPeriodic()`. Three scheduling strategies: WorkManager (default), foreground service, and exact alarms.
- **FEAT**: `PeriodicLocationWorker` — WorkManager `CoroutineWorker` for one-shot GPS fixes with automatic SQLite persistence and EventChannel/headless dispatch.
- **FEAT**: `PeriodicAlarmReceiver` — `BroadcastReceiver` for AlarmManager exact alarm chaining when `periodicUseExactAlarms: true`.
- **FEAT**: `SCHEDULE_EXACT_ALARM` permission with graceful fallback to inexact alarms on Android 13+.
- **FIX**: `TraceletAndroidPluginTest` — make `mainHandler` lazy to avoid `RuntimeException` in plain JUnit tests.
- **CHORE**: Bump `tracelet_platform_interface` to ^0.10.0.

## 0.9.1

- **FIX**: Fire heartbeat events in boot-mode headless tracking. `LocationService.startBootTracking()` now starts a self-rescheduling heartbeat timer so heartbeat events dispatch to `HeadlessTaskService` after device reboot.

## 0.9.0

* **FEAT**: HTTP sync retry engine — configurable retry with exponential backoff for transient 5xx, 429, and timeout failures. Respects `Retry-After` headers. Defers sync on connectivity loss.
* **FEAT**: Configurable motion sensitivity — `MotionDetector` reads `shakeThreshold`, `stillThreshold`, `stillSampleCount` from `ConfigManager` at runtime instead of hardcoded constants.
* **FIX**: HTTP 429 (Too Many Requests) now correctly treated as transient (was previously treated as permanent failure).
* **FIX**: Added `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` permission to AndroidManifest.xml for battery exemption settings.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.9.0.

## 0.8.3

* **FEAT**: Proximity-based geofence auto-load/unload — only geofences within `geofenceProximityRadius` are registered with the OS, sorted by distance, capped at 100 (Android limit). Enables monitoring thousands of geofences.
* **FEAT**: `GeofenceManager.updateProximity()` — re-evaluates which geofences to monitor on every location update, dynamically swapping registrations as the device moves.
* **FEAT**: `geofencesChange` event fires with `on`/`off` arrays when geofences are activated/deactivated from proximity monitoring.
* **FEAT**: `maxMonitoredGeofences` config respected — caps simultaneously monitored geofences below the platform limit.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.8.3.

## 0.8.2

* **DOCS**: Improve README visuals with combined Android & iOS demo image.

## 0.8.1

* **DOCS**: Document iOS background hardening changes (no Android code changes in this release).

## 0.8.0

* **FEAT**: `OemCompat` utility — comprehensive OEM compatibility layer with manufacturer detection (Huawei, Xiaomi, OnePlus, Samsung, Oppo, Vivo), aggression ratings (0–5), and OEM-specific settings deep-links.
* **FEAT**: Huawei PowerGenie wakelock hack — uses `LocationManagerService` wakelock tag to bypass PowerGenie background killing.
* **FEAT**: Xiaomi autostart detection — runtime check for MIUI autostart management activity availability.
* **FEAT**: OEM settings deep-links — 8 manufacturer-specific settings screens (autostart, battery saver, app launch, protected apps) validated via `PackageManager.resolveActivity()`.
* **FEAT**: `getSettingsHealth` method channel handler — returns full device OEM health map.
* **FEAT**: `openOemSettings` method channel handler — launches OEM settings by label.
* **PERF**: OEM-safe wakelock lifecycle in `LocationService` — acquire on start, release on stop/destroy/taskRemoved.
* **PERF**: Boot receiver wakelock — temporary 60-second wakelock during `BOOT_COMPLETED` processing to survive aggressive OEM process killing.
* **CHORE**: ProGuard/R8 consumer rules (`consumer-rules.pro`) — prevents stripping of services, receivers, Room entities, and Kotlin metadata in release builds.
* **DOCS**: Update README with OEM compatibility feature and documentation link.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.8.0.

## 0.7.1

* **DOCS**: Add mock location detection feature to README with platform-specific detection details.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.7.1.

## 0.7.0

* **FEAT**: Mock location detection — `isLocationMock()` uses `Location.isMock()` (API 31+) and `isFromMockProvider()` (API 18+) to flag spoofed GPS.
* **FEAT**: Heuristic mock detection (level 2) — satellite count check (< 4 = suspicious) and `SystemClock.elapsedRealtimeNanos` drift detection (> 5s = suspicious).
* **FEAT**: `enrichLocation()` includes `mock` flag and `mockHeuristics` metadata map (satellites, elapsedRealtimeDriftMs, platformFlagMock).
* **FEAT**: Native-level mock rejection — when `rejectMockLocations` is enabled, drops mocked locations before sending to Dart and fires `ProviderChangeEvent.mockLocationsDetected`.
* **FEAT**: `ConfigManager.getMockDetectionLevel()` and `getRejectMockLocations()` getters.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.7.0.

## 0.6.1

* **REFACTOR**: Remove 6 dead `ConfigManager` constants and methods for filtering migrated to Dart in 0.6.0 (`getDisableElasticity`, `getElasticityMultiplier`, `getFilterPolicy`, `getMaxImpliedSpeed`, `getTrackingAccuracyThreshold`, `getUseKalmanFilter`).
* **REFACTOR**: Remove dead `EventDispatcher.sendTrip()` and `"trip"` channel registration — trip events now from Dart `TripManager`.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.6.1.

## 0.6.0

* **REFACTOR**: Remove duplicate location filtering from `LocationEngine.onLocationReceived()` — elasticity, distance filter, accuracy filter, and speed filter now handled by shared Dart `LocationProcessor`.
* **REFACTOR**: Replace `GeofenceManager.evaluateHighAccuracyProximity()` with no-op stub — proximity evaluation moved to shared Dart `GeofenceEvaluator`.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.6.0.

## 0.5.5

* **CHORE**: Bump `tracelet_platform_interface` to ^0.5.5.

## 0.5.4

* **FIX**: Heartbeat event now wraps location data in `{"location": ...}` to match `HeartbeatEvent.fromMap()` — fixes heartbeat always returning zero coordinates.
* **FIX**: Heartbeat falls back to last known location (via `enrichLocation()`) when `getCurrentPosition` returns null.

## 0.5.3

* **CHORE**: Bump `tracelet_platform_interface` to ^0.5.3.

## 0.5.2

* **FEAT**: Accelerometer-only motion detection mode — when `disableMotionActivityUpdates` is `true`, uses hardware accelerometer + `TYPE_SIGNIFICANT_MOTION` sensor for permission-free stationary↔moving detection.
* **PERF**: Lazily initialize `ActivityRecognitionClient` — no longer created when unused in accelerometer-only mode.
* **PERF**: Cache `SensorManager` instance via `obtainSensorManager()` instead of re-fetching on each call.
* **FIX**: Graceful degradation — if `ACTIVITY_RECOGNITION` permission throws `SecurityException`, automatically falls back to accelerometer-only mode.
* **REFACTOR**: Extract `activityTransition()` helper to reduce boilerplate in transition registration.

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
