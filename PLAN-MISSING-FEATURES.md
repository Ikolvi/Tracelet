# Tracelet — Missing Features Plan

> Compared against [`flutter_background_geolocation`](https://pub.dev/packages/flutter_background_geolocation) (transistorsoft).
> This plan covers features that require **new native implementation**, not just Dart model additions.

---

## Status Legend

| Symbol | Meaning |
|--------|---------|
| ✅ | Implemented (Dart + Android + iOS) |
| 🟡 | Dart model added, native wiring pending |
| 🔴 | Not started |

---

## 1. Elasticity (Distance-Filter Scaling) 🟡

**What**: Dynamically adjust `distanceFilter` based on current speed — more recordings at low speed, fewer at high speed.

**Dart model**: `GeoConfig.disableElasticity`, `GeoConfig.elasticityMultiplier` — ✅ done.

**Native work needed**:
- **Android** (`LocationEngine.kt`): On each location callback, compute speed → scale `distanceFilter` by `elasticityMultiplier`. Skip scaling when `disableElasticity == true`.
- **iOS** (`LocationEngine.swift`): Same logic in `CLLocationManagerDelegate.didUpdateLocations`.

**Effort**: ~2–4 hours. Low risk.

---

## 2. Location Filtering / Denoising 🟡

**What**: Reject GPS spikes, enforce accuracy thresholds, filter impossible speed jumps.

**Dart model**: `LocationFilter` class with `policy`, `maxImpliedSpeed`, `odometerAccuracyThreshold`, `trackingAccuracyThreshold` — ✅ done.

**Native work needed**:
- **Both platforms**: Before recording a location:
  1. Check `trackingAccuracyThreshold` — skip if `location.accuracy > threshold`.
  2. Check `maxImpliedSpeed` — compute distance/time between consecutive points. If implied speed > max, reject.
  3. Check `odometerAccuracyThreshold` — if failed, don't add to odometer but may still record.
  4. Apply `policy`: `adjust` → substitute last-known-good, `ignore` → drop silently, `discard` → drop + emit error event.

**Effort**: ~4–6 hours. Medium complexity.

---

## 3. Persistence Config (DB Retention, Templates) 🟡

**What**: Control which records are persisted, for how long, max record count, and custom JSON templates.

**Dart model**: `PersistenceConfig` with `persistMode`, `maxDaysToPersist`, `maxRecordsToPersist`, `locationTemplate`, `geofenceTemplate`, `disableProviderChangeRecord`, `extras` — ✅ done.

**Native work needed**:
- **Both platforms** (`LocationDao` / `LocationDatabase`):
  - `persistMode`: Before INSERT, check mode: `none` → skip, `location` → skip geofences, `geofence` → skip locations.
  - `maxDaysToPersist`: Run periodic `DELETE WHERE timestamp < now - maxDays` (on start + after inserts).
  - `maxRecordsToPersist`: Run `DELETE WHERE id NOT IN (SELECT id ... ORDER BY id DESC LIMIT max)`.
  - `locationTemplate` / `geofenceTemplate`: Apply Mustache-style interpolation when serializing for HTTP sync.
  - `disableProviderChangeRecord`: Skip the automatic record when provider changes.
  - `extras`: Merge into every record's JSON before INSERT.

**Effort**: ~6–10 hours. Medium-high complexity (template engine, retention pruning).

---

## 4. Activity Recognition Tuning 🟡

**What**: Fine-tune motion detection: recognition interval, confidence threshold, stop detection, trigger activities.

**Dart model**: `MotionConfig` expanded with `activityRecognitionInterval`, `minimumActivityRecognitionConfidence`, `disableStopDetection`, `stopDetectionDelay`, `stopOnStationary`, `triggerActivities` — ✅ done.

**Native work needed**:
- **Android** (`MotionDetector.kt`):
  - Pass `activityRecognitionInterval` to `ActivityRecognitionClient.requestActivityTransitionUpdates()`.
  - Filter by `minimumActivityRecognitionConfidence` before triggering motion change.
  - `disableStopDetection` → don't start stop timer.
  - `stopDetectionDelay` → add extra delay before stop-detection activates.
  - `stopOnStationary` → call `stop()` instead of just emitting stationary event.
  - `triggerActivities` → only trigger motion for listed activity types.
- **iOS** (`MotionDetector.swift`):
  - `activityRecognitionInterval` → polling interval for `CMMotionActivityManager`.
  - Same confidence filtering and stop-detection logic.

**Effort**: ~4–8 hours. Medium complexity.

---

## 5. `stopAfterElapsedMinutes` 🟡

**What**: Automatically stop tracking after N minutes of operation.

**Dart model**: `GeoConfig.stopAfterElapsedMinutes` — ✅ done.

**Native work needed**:
- **Both platforms**: When tracking starts, if `stopAfterElapsedMinutes > 0`, schedule a timer. On fire → call internal `stop()`. Cancel on manual stop.

**Effort**: ~1–2 hours. Low risk.

---

## 6. iOS `preventSuspend` (Silent Audio Keep-Alive) 🟡

**What**: Play an inaudible audio clip in a loop to prevent iOS from suspending the app in the background.

**Dart model**: `AppConfig.preventSuspend` — ✅ done.

**Native work needed**:
- **iOS only**: Use `AVAudioSession` with `.playback` category + silent MP3/CAF in bundle. Start on `start()`, stop on `stop()`.

**Effort**: ~2–3 hours. Need silent audio asset. iOS review risk: Apple has flagged this pattern before.

---

## 7. `scheduleUseAlarmManager` 🟡

**What**: Use `AlarmManager` for precise schedule timing instead of `JobScheduler` / `WorkManager`.

**Dart model**: `AppConfig.scheduleUseAlarmManager` — ✅ done.

**Native work needed**:
- **Android only** (`ScheduleManager.kt`): If `true`, use `AlarmManager.setExactAndAllowWhileIdle()` instead of `WorkManager` for schedule triggers. Requires `SCHEDULE_EXACT_ALARM` permission on Android 12+.

**Effort**: ~3–4 hours. Medium risk (exact alarm permission flow).

---

## 8. `disableAutoSyncOnCellular` 🟡

**What**: Only auto-sync over Wi-Fi, skip when on cellular.

**Dart model**: `HttpConfig.disableAutoSyncOnCellular` — ✅ done.

**Native work needed**:
- **Android** (`HttpService.kt`): Before auto-sync, check `ConnectivityManager` for transport type. Skip if cellular + flag is true.
- **iOS** (`HttpService.swift`): Check `NWPathMonitor` or `SCNetworkReachability` for connection type.

**Effort**: ~2–3 hours. Low risk.

---

## 9. `backgroundPermissionRationale` 🟡

**What**: Show a rationale dialog before requesting background location on Android 11+.

**Dart model**: `PermissionRationale` class + `AppConfig.backgroundPermissionRationale` — ✅ done.

**Native work needed**:
- **Android only** (`TraceletAndroidPlugin.kt` / new `PermissionHelper.kt`):
  - If rationale is provided and `shouldShowRequestPermissionRationale()` returns true, show an AlertDialog with title, message, positive/negative actions.
  - On positive → proceed with `requestPermissions()`. On negative → resolve with denied status.

**Effort**: ~2–3 hours. Low risk.

## 11. `enableTimestampMeta` 🟡

**What**: Attach extra timestamp metadata to each location record (e.g., `timestampMeta.time`, `timestampMeta.systemTime`).

**Dart model**: `GeoConfig.enableTimestampMeta` — ✅ done.

**Native work needed**:
- **Both platforms**: When recording a location and flag is true, add `"timestampMeta": {"time": ..., "systemTime": ..., "systemClockElapsedRealtime": ...}` to the record.

**Effort**: ~1–2 hours. Low risk.

---

## 12. Geofence Mode High Accuracy 🟡

**What**: During geofence-only mode (`startGeofences()`), use standard GPS tracking for precise in/out detection instead of relying solely on platform geofence APIs.

**Dart model**: `GeoConfig.geofenceModeHighAccuracy` — ✅ done.

**Native work needed**:
- **Android**: When `startGeofences()` is called and `geofenceModeHighAccuracy` is `true`, also enable `FusedLocationProvider` continuous updates and calculate geofence transitions in-app.
- **iOS**: Already uses `CLCircularRegion` monitoring; for high accuracy, additionally enable standard location updates and compute transitions.

**Effort**: ~6–8 hours. High complexity.

---

## 13. `removeListeners()` ✅

**Dart**: `Tracelet.removeListeners()` — clears event stream caches. ✅ Implemented.

---

## Priority Order (Recommended)

| # | Feature | Impact | Effort | Priority |
|---|---------|--------|--------|----------|
| 1 | Elasticity | High (battery + accuracy) | Low | **P0** |
| 2 | Location Filtering | High (data quality) | Medium | **P0** |
| 3 | `stopAfterElapsedMinutes` | Medium | Low | **P1** |
| 4 | `enableTimestampMeta` | Low | Low | **P1** |
| 5 | Activity Recognition Tuning | Medium | Medium | **P1** |
| 6 | DB Retention (persistence) | High | Medium-High | **P1** |
| 7 | `disableAutoSyncOnCellular` | Medium | Low | **P2** |
| 8 | `backgroundPermissionRationale` | Medium (Android UX) | Low | **P2** |
| 9 | iOS `preventSuspend` | Medium (iOS reliability) | Low | **P2** |
| 10 | `scheduleUseAlarmManager` | Low | Medium | **P2** |
| 11 | Geofence High Accuracy | Low (niche) | High | **P3** |
| 12 | Persistence Templates | Low (niche) | Medium | **P3** |
| 13 | Authorization / JWT | Low (niche, apps can DIY) | High | **P3** |

---

## Total Estimated Effort

- **P0** (must-have): ~6–10 hours
- **P1** (important): ~12–20 hours
- **P2** (nice-to-have): ~9–13 hours
- **P3** (defer): ~14–20 hours

**Grand total**: ~41–63 hours of native implementation work.
