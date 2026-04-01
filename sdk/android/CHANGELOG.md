# Changelog

## 1.0.6

- **FIX**: `getCurrentPosition(samples: 1)` routes through `collectSamples` using `requestLocationUpdates` instead of `FusedLocationProviderClient.getCurrentLocation()` — forces a fresh GPS fix with proper timeout instead of returning stale cached locations (#46).
- **PERF**: Remove per-batch `onRequestFreshHeaders` invocation from `HttpSyncManager.sendBatch()` — eliminates unnecessary callback overhead on every sync request. Token refresh is handled reactively via `onAuthorizationRequired` on 401.
- **FIX**: Relax `isReady` guards to `::manager.isInitialized` for privacy zones, audit trail, and encryption — these features only need DB init, not active tracking.

## 1.0.5

- **FIX**: `getCurrentPosition()` / `collectSamples()` fall back to last known location when `FusedLocationProviderClient.getCurrentLocation()` returns null — fixes `LOCATION_UNAVAILABLE` on emulators and GPS-off devices (#46).
- **FIX**: Add public `clearPendingPermissionCallback()` — resolves cross-module `internal` visibility error from Flutter plugin.

## 1.0.4

- **FIX**: Add `isReady` guards to all SDK methods — prevents `UninitializedPropertyAccessException` when methods like `getState()`, `getCurrentPosition()`, geofence, persistence, sync, logging, scheduling, enterprise methods are called before `ready()` (re-fixes #46).

## 1.0.3

- **FIX**: Add `isReady` guards to all SDK methods — prevents `UninitializedPropertyAccessException` when methods like `getState()`, `getCurrentPosition()`, geofence, persistence, sync, logging, scheduling, enterprise methods are called before `ready()` (re-fixes #46).

## 1.0.2

- **FIX**: Guard `soundManager` access in `handleMotionStateChange()` and `destroyAll()` — prevents `UninitializedPropertyAccessException` when motion detector fires before full SDK initialization (fixes #41).
- **FIX**: Add `isReady` guard to `stop()` — prevents crash when `stop()` is called before `ready()` (fixes #46).
- **FIX**: Use `LocationManagerCompat.isLocationEnabled()` instead of `LocationManager.isLocationEnabled()` — fixes `NoSuchMethodError` crash on Android API 26/27 (fixes #47).
- **FIX**: `DeviceAttestor` now checks Play Integrity availability at runtime via `Class.forName` — prevents `NoClassDefFoundError` when `com.google.android.play:integrity` is not on the classpath. Uses lazy initialization for `IntegrityManagerFactory`.
- **FIX**: `DatabaseEncryptionManager` now checks `androidx.security:security-crypto` availability at runtime — `isDatabaseEncrypted()` returns `false` and `getDatabasePassword()` returns empty array when the library is absent.
- **FIX**: `TraceletSdk.ready()` checks `SqlCipherMigrator.isAvailable()` before attempting database encryption — logs a warning with setup instructions when SQLCipher is absent instead of crashing.
- **FIX**: `TraceletDatabase.encryptDatabase()` throws `IllegalStateException` with clear setup instructions if SQLCipher dependency is missing.
- **REFACTOR**: Extracted SQLCipher migration to `SqlCipherMigrator` class — cleaner separation, testable independently.
- **REFACTOR**: Refined ProGuard consumer rules — narrower keep rules, added `-dontwarn` for optional enterprise dependencies.
- **TEST**: Add `destroyAll_doesNotCrash_withoutSoundManager` unit test.
- **TEST**: Add `DeviceAttestor` and `SqlCipherMigrator` availability tests.

## 1.0.1

- Initial release on Maven Central.
