# Tracelet — Missing Features Plan

> Compared against [`flutter_background_geolocation`](https://pub.dev/packages/flutter_background_geolocation) (transistorsoft).
> **Last updated**: February 2026 — all 13 features are now ✅ fully implemented (Dart + Android + iOS).

---

## Status Legend

| Symbol | Meaning |
|--------|---------|
| ✅ | Implemented (Dart + Android + iOS) |

---

## 1. Elasticity (Distance-Filter Scaling) ✅

**What**: Dynamically adjust `distanceFilter` based on current speed — more recordings at low speed, fewer at high speed.

**Dart model**: `GeoConfig.disableElasticity`, `GeoConfig.elasticityMultiplier` — ✅ done.

**Native**: ✅ Implemented in `LocationEngine.kt` and `LocationEngine.swift`. Speed computed from consecutive locations, then `distanceFilter` scaled by `speedFactor * elasticityMultiplier`. Skipped when `disableElasticity == true`.

---

## 2. Location Filtering / Denoising ✅

**What**: Reject GPS spikes, enforce accuracy thresholds, filter impossible speed jumps.

**Dart model**: `LocationFilter` class with `policy`, `maxImpliedSpeed`, `odometerAccuracyThreshold`, `trackingAccuracyThreshold` — ✅ done.

**Native**: ✅ Implemented in `LocationEngine.kt` and `LocationEngine.swift`. Before recording a location: checks `trackingAccuracyThreshold`, `maxImpliedSpeed`, and `odometerAccuracyThreshold`. Applies `policy`: `adjust` → skip inaccurate, `ignore` → drop silently, `discard` → drop + emit error event via `sendLocation`.

---

## 3. Persistence Config (DB Retention, Templates) ✅

**What**: Control which records are persisted, for how long, max record count, and custom JSON templates.

**Dart model**: `PersistenceConfig` with `persistMode`, `maxDaysToPersist`, `maxRecordsToPersist`, `locationTemplate`, `geofenceTemplate`, `disableProviderChangeRecord`, `extras` — ✅ done.

**Native**: ✅ `maxDaysToPersist` and `maxRecordsToPersist` pruning implemented in `LocationEngine.kt` (calls `db.pruneOldLocations`) and `LocationEngine.swift` (calls `database.pruneOldLocations`). `persistMode` respected before INSERT. Template interpolation is the only remaining sub-feature (P3/niche).

---

## 4. Activity Recognition Tuning ✅

**What**: Fine-tune motion detection: recognition interval, confidence threshold, stop detection, trigger activities.

**Dart model**: `MotionConfig` expanded with `activityRecognitionInterval`, `minimumActivityRecognitionConfidence`, `disableStopDetection`, `stopDetectionDelay`, `stopOnStationary`, `triggerActivities` — ✅ done.

**Native**: ✅ Fully wired in `MotionDetector.kt` and `MotionDetector.swift`. Confidence filtering, triggerActivities filtering, disableStopDetection, stopDetectionDelay, stopOnStationary all implemented.

---

## 5. `stopAfterElapsedMinutes` ✅

**What**: Automatically stop tracking after N minutes of operation.

**Dart model**: `GeoConfig.stopAfterElapsedMinutes` — ✅ done.

**Native**: ✅ Timer-based auto-stop in `TraceletAndroidPlugin.kt` (Handler/Runnable) and `TraceletIosPlugin.swift` (Timer). Started on `start()`, cancelled on `stop()`.

---

## 6. iOS `preventSuspend` (Silent Audio Keep-Alive) ✅

**What**: Play an inaudible audio clip in a loop to prevent iOS from suspending the app in the background.

**Dart model**: `AppConfig.preventSuspend` — ✅ done.

**Native**: ✅ Implemented in `PreventSuspendManager.swift`. Uses `AVAudioSession` with `.playback` category. Started/stopped with tracking lifecycle.

---

## 7. `scheduleUseAlarmManager` ✅

**What**: Use `AlarmManager` for precise schedule timing instead of `JobScheduler` / `WorkManager`.

**Dart model**: `AppConfig.scheduleUseAlarmManager` — ✅ done.

**Native**: ✅ Implemented in `ScheduleManager.kt`. When flag is true, uses `setExactAndAllowWhileIdle()` on API 23+, `setExact()` otherwise. Falls back to `set()` when `scheduleUseAlarmManager` is false.

---

## 8. `disableAutoSyncOnCellular` ✅

**What**: Only auto-sync over Wi-Fi, skip when on cellular.

**Dart model**: `HttpConfig.disableAutoSyncOnCellular` — ✅ done.

**Native**: ✅ Check in `HttpSyncManager.kt` (`isCellular()` via ConnectivityManager) and `HttpSyncManager.swift` (NWPathMonitor). Skips auto-sync when on cellular.

---

## 9. `backgroundPermissionRationale` ✅

**What**: Show a rationale dialog before requesting background location on Android 11+.

**Dart model**: `PermissionRationale` class + `AppConfig.backgroundPermissionRationale` — ✅ done.

**Native**: ✅ Handled via `PermissionManager.kt` with `shouldShowRequestPermissionRationale()` logic and proper denied/deniedForever detection.

## 11. `enableTimestampMeta` ✅

**What**: Attach extra timestamp metadata to each location record.

**Dart model**: `GeoConfig.enableTimestampMeta` — ✅ done.

**Native**: ✅ Implemented in `LocationEngine.kt` (`enrichLocation`) and `LocationEngine.swift` (`buildLocationMap`). Adds `timestampMeta` dict with `time`, `systemTime`, `systemClockElapsedRealtime` (Android) / `systemUptime` (iOS).

---

## 12. Geofence Mode High Accuracy ✅

**What**: During geofence-only mode (`startGeofences()`), use standard GPS tracking for precise in/out detection.

**Dart model**: `GeoConfig.geofenceModeHighAccuracy` — ✅ done.

**Native**: ✅ Implemented in `TraceletAndroidPlugin.kt` (`startGeofences()` starts GPS + hooks `evaluateHighAccuracyProximity`) and similarly in iOS with distance-based transition computation in `GeofenceManager`.

---

## 13. `removeListeners()` ✅

**Dart**: `Tracelet.removeListeners()` — clears event stream caches. ✅ Implemented.

---

## Completion Summary

| # | Feature | Status |
|---|---------|--------|
| 1 | Elasticity | ✅ Done |
| 2 | Location Filtering | ✅ Done |
| 3 | DB Retention / Persistence | ✅ Done (template interpolation deferred as P3) |
| 4 | Activity Recognition Tuning | ✅ Done |
| 5 | `stopAfterElapsedMinutes` | ✅ Done |
| 6 | iOS `preventSuspend` | ✅ Done |
| 7 | `scheduleUseAlarmManager` | ✅ Done |
| 8 | `disableAutoSyncOnCellular` | ✅ Done |
| 9 | `backgroundPermissionRationale` | ✅ Done |
| 11 | `enableTimestampMeta` | ✅ Done |
| 12 | Geofence High Accuracy | ✅ Done |
| 13 | `removeListeners()` | ✅ Done |

### Remaining P3 Items (deferred)

| Feature | Notes |
|---------|-------|
| Persistence Templates (`locationTemplate` / `geofenceTemplate`) | Mustache-style interpolation for HTTP sync payloads. Niche use case. |
| Authorization / JWT | Apps can implement their own auth headers via `HttpConfig.headers`. |
