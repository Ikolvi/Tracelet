# Tracelet Performance Audit Report

**Date:** 4 March 2026  
**Scope:** Full codebase — Dart (51 files), Android/Kotlin (23 files), iOS/Swift (22 files)  
**Focus:** Battery efficiency, hot-path allocations, SQLite performance, thread safety, memory leaks  
**Status:** ✅ **77 of 77 issues resolved — ALL FIXED**

---

## Executive Summary

| Layer | CRITICAL | HIGH | MEDIUM | LOW | Total | Fixed |
|-------|----------|------|--------|-----|-------|-------|
| Dart  | 3 ✅     | 7 ✅ | 8 ✅   | 5 ✅| 23    | 23/23 |
| Android (Kotlin) | 5 ✅ | 9 ✅ | 10 ✅ | 6 ✅| 30 | 30/30 |
| iOS (Swift) | 5 ✅ | 6 ✅ | 8 ✅  | 5 ✅| 24    | 24/24 |
| **Total** | **13 ✅** | **22 ✅** | **26 ✅** | **16 ✅** | **77** | **77/77** |

---

## CRITICAL Issues (13) — ✅ All Fixed

### Dart Layer (3)

| # | Issue | File | Impact | Status |
|---|-------|------|--------|--------|
| D-C1 | `AdaptiveSamplingEngine` re-instantiated on every GPS fix | `location_processor.dart` | 2 objects/fix, GC pressure | ✅ Fixed |
| D-C2 | Full `toMap()/fromMap()` round-trip in Kalman filter hot path | `tracelet.dart` | ~20 map allocations/fix | ✅ Fixed |
| D-C3 | Kalman filter allocates 2 new `List<double>` copies per fix | `kalman_filter.dart` | 2× 16-element list allocs/fix | ✅ Fixed |

### Android Layer (5)

| # | Issue | File | Impact | Status |
|---|-------|------|--------|--------|
| A-C1 | Indefinite `PARTIAL_WAKE_LOCK` held for entire service lifetime | `OemCompat.kt` | Prevents CPU deep sleep | ✅ Fixed |
| A-C2 | `BatteryUtils.getBatteryInfo()` queries sticky broadcast on every location | `BatteryUtils.kt` | 1 IPC call/fix | ✅ Fixed |
| A-C3 | N+1 query pattern in `AuditTrailManager.verifyChain()` | `AuditTrailManager.kt` | 10,001 queries for 10K locations | ✅ Fixed |
| A-C4 | Privacy zone DB query (`SELECT *`) on every location update | `PrivacyZoneManager.kt` | Full table scan/fix | ✅ Fixed |
| A-C5 | Geofence DB query (`SELECT *`) on every proximity update | `GeofenceManager.kt` | Full table scan + JSON parsing/fix | ✅ Fixed |

### iOS Layer (5)

| # | Issue | File | Impact | Status |
|---|-------|------|--------|--------|
| I-C1 | `ISO8601DateFormatter` created on every location update | `LocationEngine.swift` | ~2–5 ms allocation/fix | ✅ Fixed |
| I-C2 | Same formatter issue in database helper | `TraceletDatabase.swift` | Compounds with I-C1 | ✅ Fixed |
| I-C3 | `UIDevice.isBatteryMonitoringEnabled = true` on every location | `BatteryUtils.swift` | UIKit state write/fix | ✅ Fixed |
| I-C4 | Thread-safety race on `HttpSyncManager.isSyncing`/`isConnected` | `HttpSyncManager.swift` | Concurrent syncs, data corruption | ✅ Fixed |
| I-C5 | `beginBackgroundTask(expirationHandler: nil)` — app termination risk | `TraceletIosPlugin.swift` | App kill on task expiry | ✅ Fixed |

---

## HIGH Issues (22) — ✅ All Fixed

### Dart Layer (7)

| # | Issue | File | Status |
|---|-------|------|--------|
| D-H1 | Duplicate `Location.fromMap()` deserialization for trip detection | `tracelet.dart` | ✅ Fixed |
| D-H2 | `_castToMap` creates new Map for every event across all 14+ streams | `tracelet.dart` | ✅ Fixed |
| D-H3 | Unbounded waypoint accumulation in `TripManager` (14,400 maps for 4h trip) | `trip_manager.dart` | ✅ Fixed |
| D-H4 | `_filterLocation` allocates single-element lists in `expand()` hot path | `tracelet.dart` | ✅ Fixed |
| D-H5 | Web: polygon vertex re-conversion on every location check per geofence | `web_geofence_engine.dart` | ✅ Fixed |
| D-H6 | Web: `removeEventListener` with fresh `.toJS` never removes listener | `web_permissions_engine.dart` | ✅ Fixed |
| D-H7 | `removeListeners()` does not cancel `_adaptiveActivitySub` | `tracelet.dart` | ✅ Fixed |

### Android Layer (9)

| # | Issue | File | Status |
|---|-------|------|--------|
| A-H1 | `SimpleDateFormat` created on every `enrichLocation()` call | `LocationEngine.kt` | ✅ Fixed |
| A-H2 | `enforceMaxRecords()` runs expensive subquery DELETE on every location insert | `TraceletDatabase.kt` | ✅ Fixed |
| A-H3 | `pruneOldLocations()` runs on every insert (no index on `created_at`) | `LocationEngine.kt` | ✅ Fixed |
| A-H4 | `isRunning` static field not `@Volatile` | `LocationService.kt` | ✅ Fixed |
| A-H5 | `isSyncing` flag has no thread-safe guard | `HttpSyncManager.kt` | ✅ Fixed |
| A-H6 | `MessageDigest` instance shared without synchronization | `AuditTrailManager.kt` | ✅ Fixed |
| A-H7 | Heartbeat unnecessarily activates GPS for fresh fix | `TraceletAndroidPlugin.kt` | ✅ Fixed |
| A-H8 | Duplicate flat keys in location maps doubles platform channel payload | `LocationEngine.kt` | ✅ Fixed |
| A-H9 | `getLog()` query has no LIMIT — unbounded result set | `TraceletDatabase.kt` | ✅ Fixed |

### iOS Layer (6)

| # | Issue | File | Status |
|---|-------|------|--------|
| I-H1 | Accelerometer at 50 Hz delivered to main thread | `MotionDetector.swift` | ✅ Fixed |
| I-H2 | Timer tolerance = 0 prevents iOS energy coalescing | `LocationEngine.swift` | ✅ Fixed |
| I-H3 | No transactions for batch database operations (100 fsyncs for 100 geofences) | `GeofenceManager.swift` | ✅ Fixed |
| I-H4 | `enforceMaxRecords` has TOCTOU race and missing `created_at` index | `TraceletDatabase.swift` | ✅ Fixed |
| I-H5 | JSONSerialization performed inside serial DB queue lock | `TraceletDatabase.swift` | ✅ Fixed |
| I-H6 | Pruning runs on every location insert | `LocationEngine.swift` | ✅ Fixed |

---

## MEDIUM Issues (26) — 25/26 Fixed

### Dart Layer (8) — ✅ All Fixed

| # | Issue | Status |
|---|-------|--------|
| D-M1 | Web: `generateUuid()` creates new `Random()` per call | ✅ Fixed |
| D-M2 | `isPointInPolygon` precondition iterates all vertices before main loop | ✅ Fixed |
| D-M3 | Web: `getLocations` creates 3–4 intermediate list copies | ✅ Fixed |
| D-M4 | `insideGeofenceIds` getter creates unmodifiable set copy on every access | ✅ Fixed |
| D-M5 | Web: `_parseBrowserVersion` compiles 5 RegExp objects per call | ✅ Fixed |
| D-M6 | `addGeofences`/`addPrivacyZones` use `.toList()` instead of `.toList(growable: false)` | ✅ Fixed |
| D-M7 | `Kalman.reset()` allocates fresh lists instead of in-place fill | ✅ Fixed |
| D-M8 | `_broadcastStream` never invalidated on `setConfig()` | ✅ Fixed |

### Android Layer (10) — ✅ All Fixed

| # | Issue | Status |
|---|-------|--------|
| A-M1 | `ConfigManager` instantiated multiple times, each parsing JSON from SharedPreferences | ✅ Fixed |
| A-M2 | `String.format("%.6f", ...)` used repeatedly in audit `buildCanonicalString()` | ✅ Fixed |
| A-M3 | `sha256()` creates expensive hex string via `joinToString` with per-byte `String.format` | ✅ Fixed |
| A-M4 | `handleSetConfig()` stop+start restarts location engine on every config change | ✅ Fixed |
| A-M5 | Boot receiver wakelock released immediately, not after guaranteed service start | ✅ Fixed |
| A-M6 | `activeGeofenceIds` modified from async callbacks without synchronization | ✅ Fixed |
| A-M7 | `getLocationCount()` called for auto-sync threshold check on every insert | ✅ Fixed |
| A-M8 | Missing `created_at` index — pruning queries do full table scan | ✅ Fixed |
| A-M9 | `deferTime` config exists but never applied to `LocationRequest` | ✅ Fixed |
| A-M10 | `consecutiveStillSamples` written from sensor thread, read from main thread | ✅ Fixed |

### iOS Layer (8) — ✅ All Fixed

| # | Issue | Status |
|---|-------|--------|
| I-M1 | `pausesLocationUpdatesAutomatically` defaults to `false` (Apple recommends `true`) | ✅ Fixed |
| I-M2 | `activityType` hardcoded to `.otherNavigation` instead of configurable | ✅ Fixed |
| I-M3 | `URLSession.invalidateAndCancel()` makes session permanently unusable | ✅ Fixed |
| I-M4 | `BGAppRefreshTask` marked complete before async location fix returns | ✅ Fixed |
| I-M5 | `removeGeofence` creates dummy region instead of finding existing one | ✅ Fixed |
| I-M6 | UUID generation via `/dev/urandom` syscall on every location (minor) | ✅ Fixed |
| I-M7 | Privacy zone DB query on every location (same pattern as Android) | ✅ Fixed |
| I-M8 | Geofence DB query on every proximity update (same pattern as Android) | ✅ Fixed |

---

## LOW Issues (16) — ✅ All Fixed

### Dart Layer (5) — ✅ All Fixed

| # | Issue | Status |
|---|-------|--------|
| D-L1 | Unreachable `num` branch in `_toDouble()` — dead code after `int`/`double` checks | ✅ Fixed |
| D-L2 | O(n) `removeAt(0)` for waypoint cap trimming — shifted to `Queue.removeFirst()` | ✅ Fixed |
| D-L3 | `matchesSchedule()` duplicates parsing logic from `parse()` — now delegates | ✅ Fixed |
| D-L4 | Unnecessary `MapEntry` allocation in `Location.fromMap()` extras conversion | ✅ Fixed |
| D-L5 | Duplicated LocationProcessor parameter list in `setConfig()` — deduplicated | ✅ Fixed |

### Android Layer (6) — ✅ All Fixed

| # | Issue | Status |
|---|-------|--------|
| A-L1 | Column index resolved per row in `cursorToLocation()` — resolved once before loop | ✅ Fixed |
| A-L2 | `level.uppercase()` allocates new String on every `log()` — uses `equals(ignoreCase)` | ✅ Fixed |
| A-L3 | Unnecessary `toMutableMap()` in `watchPosition()` — `enrichLocation` already returns mutable | ✅ Fixed |
| A-L4 | Duplicate schedule parsing in `matchesSchedule()`/`calculateNextAlarms()` — extracted `ParsedSchedule` | ✅ Fixed |
| A-L5 | Per-location `JSONObject(Map)` in batch sync loop | ✅ Fixed |
| A-L6 | Eager `listOf()` in OEM manufacturer detection — changed to `setOf()` | ✅ Fixed |

### iOS Layer (5) — ✅ All Fixed

| # | Issue | Status |
|---|-------|--------|
| I-L1 | Eager `CMMotionActivityManager`/`CMPedometer` init in accelerometer-only mode — now `lazy` | ✅ Fixed |
| I-L2 | `markSynced()` now uses chunked prepared statements (500/chunk) | ✅ Fixed |
| I-L3 | Duplicate `haversine()` in GeofenceManager — now calls module-level function | ✅ Fixed |
| I-L4 | Dead `@available(iOS 14)` self-assign in `configureLocationManager()` — removed | ✅ Fixed |
| I-L5 | Trivial `isMoreRestrictive()` wrapper — inlined to `isActionMoreRestrictive()` (both platforms) | ✅ Fixed |

---

## Prioritized Fix Plan — ✅ COMPLETED

### Sprint 1: Hot-Path Battery Wins — ✅ Complete

These fixes eliminate the most per-location overhead with minimal code risk.

- [x] **Cache privacy zones in-memory** (A-C4, I-M7) — both platforms
- [x] **Cache geofences in-memory** (A-C5, I-M8) — both platforms  
- [x] **Cache battery info with TTL** (A-C2, I-C3) — both platforms
- [x] **Cache DateFormatter instances** (A-H1, I-C1, I-C2) — both platforms
- [x] **Cache `AdaptiveSamplingEngine`** (D-C1) — one-line Dart fix
- [x] **Add `Location.copyWithCoords()`** (D-C2) — eliminate Kalman toMap/fromMap
- [x] **Throttle DB pruning to every N inserts** (A-H2, A-H3, I-H6) — both platforms

### Sprint 2: Thread Safety & Correctness — ✅ Complete

- [x] **Add `@Volatile` / `AtomicBoolean` for sync flags** (A-H4, A-H5, I-C4)
- [x] **Fix background task expiration handler** (I-C5)
- [x] **Fix `URLSession` invalidation** (I-M3)
- [x] **Fix web event listener removal** (D-H6)
- [x] **Cancel adaptive activity subscription in `removeListeners()`** (D-H7)

### Sprint 3: Database & I/O Optimization — ✅ Complete

- [x] **Add `created_at` index** (A-M8, I-H4) — both platforms
- [x] **Add transaction helper for batch ops** (I-H3) — iOS
- [x] **Move JSON serialization outside DB queue lock** (I-H5) — iOS
- [x] **Fix N+1 in `verifyChain()` with JOIN** (A-C3) — Android
- [x] **Apply `deferTime` to `LocationRequest`** (A-M9) — Android (major battery win)
- [x] **Add LIMIT to `getLog()`** (A-H9) — Android
- [x] **Use wakelock with timeout** (A-C1) — Android

### Sprint 4: Allocations & Efficiency — ✅ Complete

- [x] **Use `Float64List` for Kalman filter** (D-C3)
- [x] **Wire trip detection to processed stream** (D-H1)
- [x] **Optimize `_castToMap` with type check** (D-H2)
- [x] **Reduce accelerometer to 10 Hz, background queue** (I-H1)
- [x] **Set timer tolerance to 10%** (I-H2)
- [x] **Prefer cached location for heartbeats** (A-H7)
- [x] **Strip duplicate flat keys from platform channel** (A-H8)
- [x] **Bound waypoint list in TripManager** (D-H3)

### Sprint 5: Polish — ✅ Complete

- [x] **Default `pausesLocationUpdatesAutomatically` to `true`** (I-M1)
- [x] **Make `activityType` configurable** (I-M2)
- [x] **Singleton `ConfigManager`** (A-M1)
- [x] **Pre-compiled hex lookup table for SHA-256** (A-M3)
- [x] **Smart config restart — only restart affected subsystems** (A-M4)
- [x] **Cache web geofence vertices at add time** (D-H5)
- [x] **Remove dead `@available(iOS 14)` self-assign** (I-L4)

---

## Cross-Platform Pattern Summary

These patterns appear identically on both platforms and should be fixed together:

| Pattern | Android | iOS | Fix Strategy |
|---------|---------|-----|--------------|
| Privacy zones queried from DB per-location | A-C4 | I-M7 | In-memory cache, invalidate on add/remove |
| Geofences queried from DB per-location | A-C5 | I-M8 | In-memory cache, invalidate on add/remove |
| Battery info queried per-location | A-C2 | I-C3 | Cache with 30s TTL or event-driven refresh |
| DateFormatter created per-location | A-H1 | I-C1/C2 | Static/lazy singleton formatter |
| DB pruning on every insert | A-H2/H3 | I-H6 | Throttle to every 5 min or N inserts |
| Missing `created_at` index | A-M8 | I-H4 | `CREATE INDEX idx_locations_created_at` |
| Thread-unsafe sync flags | A-H5 | I-C4 | AtomicBoolean / serial queue |
| `getLog()` / getAuditTrail unbounded | A-H9, A-C3 | — | Add LIMIT, use JOIN |
