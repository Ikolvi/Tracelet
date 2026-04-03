# Changelog

## 1.0.8

- **FIX**: Fix `SubsystemTests` — use `HttpSyncManager.onRequestFreshHeaders` (static type) instead of instance access.

## 1.0.7

- **CHORE**: Re-release — 1.0.6 was published alongside partially-released Flutter packages.

## 1.0.6

- **FIX**: `getCurrentPosition(samples: 1)` routes through `collectSamples` using `startUpdatingLocation` instead of `CLLocationManager.requestLocation()` — forces a fresh GPS fix with proper timeout instead of returning stale cached locations (#46).
- **PERF**: Remove per-batch `onRequestFreshHeaders` invocation from `HttpSyncManager.syncBatch()` — eliminates unnecessary callback overhead. Token refresh handled reactively via `onAuthorizationRequired` on 401.
- **FIX**: Relax `isReady` guards to `manager != nil` for privacy zones, audit trail, and encryption — these features only need DB init, not active tracking.

## 1.0.5

- **FIX**: `getCurrentPosition()` / `collectSamples()` / `didFailWithError` fall back to last known location when `CLLocationManager` returns no fix — fixes `LOCATION_UNAVAILABLE` on simulators and GPS-off devices (#46).

## 1.0.4

- **CHORE**: Version bump for strict dependency pinning in Flutter wrapper.

## 1.0.3

- **FIX**: Add `isReady` guards to **all** SDK methods that access subsystem properties — prevents crash when any method is called before `ready()`, not just `stop()` (re-fixes #46).
- **FIX**: `getState()` returns a safe default disabled state before `ready()` instead of crashing.
- **FIX**: `setConfig()`, `reset()`, `getLog()`, `playSound()`, `getSensors()`, all geofence/location/persistence/sync/schedule/privacy-zone/audit-trail methods now guard against pre-ready access.

## 1.0.2

- **FIX**: `TraceletSdk.stop()` now checks `isReady` before accessing managers — prevents crash when `stop()` is called before `ready()` (fixes #46).

## 1.0.1

- Initial release on CocoaPods.
