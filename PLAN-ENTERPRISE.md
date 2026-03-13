# Tracelet — Enterprise Features Plan

> **Target**: v1.1–v1.3 release timeline
> **Last updated**: July 2025

---

## Overview

Five Tier-1 enterprise features that address the most common blockers for enterprise adoption, plus five Tier-2 features that create unique competitive differentiation. Each feature includes Dart model changes, Android implementation, iOS implementation, and Web considerations.

---

## Status Legend

| Symbol | Meaning |
|--------|---------|
| ⏳ | Not started |
| 🔧 | In progress |
| ✅ | Implemented (Dart + Android + iOS) |

---

## Tier 1 — Must-Have for Enterprise Contracts

---

### Feature 1: Encrypted SQLite (SQLCipher) ⏳

**Priority**: P0 — Without this, enterprise security teams will reject adoption (GDPR Art. 32, HIPAA §164.312, SOC2 CC6.1).

**What**: AES-256 at-rest encryption for the SQLite databases containing location history, geofence state, audit trail, and log tables.

#### Dart Model Changes

New sub-config `SecurityConfig` added to `Config`:

```dart
@immutable
class SecurityConfig {
  /// Enable at-rest database encryption.
  /// Default: false (plain SQLite for backward compatibility).
  final bool encryptDatabase;

  /// Custom encryption key. If null, a secure random key is generated
  /// and stored in platform-secure storage (Android Keystore / iOS Keychain).
  /// Provide this only if your app manages its own key material.
  final String? encryptionKey;

  const SecurityConfig({
    this.encryptDatabase = false,
    this.encryptionKey,
  });
}
```

New methods on `TraceletPlatform`:

```dart
/// Check if the current database is encrypted.
Future<bool> isDatabaseEncrypted();

/// Migrate an existing unencrypted database to encrypted (one-time).
/// Returns true on success. Existing data is preserved.
Future<bool> encryptDatabase();
```

#### Android Implementation

**Dependency**: `net.zetetic:sqlcipher-android:4.6.1` (~1.2 MB AAR)
*(Note: Uses `sqlcipher-android` — the official Android-specific artifact, NOT the legacy `android-database-sqlcipher`. The `sqlcipher-android` artifact integrates more cleanly with modern Android builds.)*

**Key storage**: Android Keystore via `EncryptedSharedPreferences` (Jetpack Security).

**Changes**:

| File | Change |
|------|--------|
| `build.gradle` | Add `implementation("net.zetetic:sqlcipher-android:4.6.1")` and `implementation("androidx.security:security-crypto:1.1.0-alpha06")` |
| `TraceletDatabase.kt` | Replace `android.database.sqlite.SQLiteOpenHelper` with `net.zetetic.database.sqlcipher.SupportOpenHelperFactory` when `encryptDatabase == true`. Pass key from Keystore. |
| `ConfigManager.kt` | Add `getEncryptDatabase()`, `getEncryptionKey()` readers. |
| `TraceletAndroidPlugin.kt` | Add `isDatabaseEncrypted` and `encryptDatabase` method channel handlers. |

**Migration from unencrypted → encrypted**:
```kotlin
// 1. Open existing unencrypted DB
// 2. ATTACH encrypted DB with key
// 3. SELECT sqlcipher_export('encrypted')
// 4. DETACH
// 5. Replace file
// 6. Store key in Keystore
```

**DB version**: Bump to `6`. No schema change — only encryption wrapper.

#### iOS Implementation

**Approach**: Use `CommonCrypto` (built into iOS SDK) + custom SQLite VFS layer. **No third-party CocoaPod needed** (respects project dependency policy).

Alternative: Use system SQLite compiled with `SQLITE_HAS_CODEC` (available since iOS 16). If unavailable, use `CC_AES_encrypt` to encrypt/decrypt database file pages on read/write.

**Key storage**: iOS Keychain via `SecItemAdd` / `SecItemCopyMatching`.

| File | Change |
|------|--------|
| `TraceletDatabase.swift` | Add `openEncrypted(path:key:)` method. Use `sqlite3_key()` if SQLCipher is bundled, or page-level AES-256-CBC via CommonCrypto. |
| `TraceletIosPlugin.swift` | Add `isDatabaseEncrypted` and `encryptDatabase` method channel handlers. |
| `Package.swift` | Add SQLCipher as SPM dependency (if SQLCipher approach chosen over CommonCrypto). |

**Preferred approach**: Bundle SQLCipher via Swift Package Manager (SPM) — this is an Apple framework dependency, not a CocoaPod third-party lib. SPM `SQLCipher` package:
```swift
.package(url: "https://github.com/nicklama/sqlcipher-spm", from: "4.6.1")
```

#### Web Implementation

**Approach**: No native encryption needed. Web uses in-memory storage (lost on page refresh). If `localStorage` persistence is added later, use the Web Crypto API (`crypto.subtle.encrypt(AES-GCM)`).

**Status**: Web: no-op (return `false` for `isDatabaseEncrypted()`).

#### Test Plan

| Test | Description |
|------|-------------|
| Unit: encrypt fresh DB | Create encrypted DB, insert 100 locations, verify read-back |
| Unit: migrate unencrypted → encrypted | Create 50 locations unencrypted, call `encryptDatabase()`, verify all data preserved |
| Unit: wrong key | Open encrypted DB with wrong key, verify graceful error (not crash) |
| Unit: key rotation | Currently out of scope (v1.1 does not support key rotation) |
| Integration: full lifecycle | `ready(encryptDatabase: true)` → `start()` → insert locations → `sync()` → `stop()` → relaunch → verify data |

---

### Feature 2: Sparse Updates (Intelligent Deduplication) ✅

**Priority**: P0 — Saves 40–70% server bandwidth and battery. The most requested feature at scale. Transistor v5.0.5 has this.

**What**: Skip sending/persisting location updates when the device position hasn't changed meaningfully beyond a configurable threshold. Unlike `distanceFilter` (which controls GPS sampling frequency), sparse updates control whether a *received* location is worth *recording*.

**Key difference from `distanceFilter`**:
- `distanceFilter` = "Don't give me GPS fixes closer than X meters apart" (upstream, platform-level)
- Sparse updates = "I received a fix, but it's essentially the same as my last recorded position — skip it" (downstream, app-level)

#### Dart Model Changes

New fields in `GeoConfig`:

```dart
@immutable
class GeoConfig {
  // ... existing fields ...

  /// Enable sparse updates. When true, locations that haven't moved
  /// beyond [sparseDistanceThreshold] meters from the last recorded
  /// location are silently dropped.
  /// Default: false
  final bool enableSparseUpdates;

  /// Minimum distance (meters) from the last recorded location before
  /// a new update is persisted/dispatched. Only applies when
  /// [enableSparseUpdates] is true.
  /// Default: 50.0 (meters)
  final double sparseDistanceThreshold;

  /// Maximum time (seconds) between recorded locations, even if the
  /// device hasn't moved beyond [sparseDistanceThreshold]. Ensures
  /// periodic "I'm still here" updates.
  /// 0 = disabled (no forced updates — only movement triggers recording).
  /// Default: 300 (5 minutes)
  final int sparseMaxIdleSeconds;
}
```

#### Implementation: Shared Dart Algorithm (LocationProcessor)

**Where**: `packages/tracelet_platform_interface/lib/src/algorithms/location_processor.dart`

Add a new filter step **after** the existing distance/accuracy/speed filters:

```dart
// Step 8: Sparse deduplication (after all other filters pass)
if (config.enableSparseUpdates) {
  final lastRecorded = _lastRecordedLocation;
  if (lastRecorded != null) {
    final distance = GeoUtils.haversine(
      lastRecorded.coords.latitude, lastRecorded.coords.longitude,
      location.coords.latitude, location.coords.longitude,
    );
    final elapsed = location.timestamp.difference(lastRecorded.timestamp).inSeconds;
    
    if (distance < config.sparseDistanceThreshold &&
        (config.sparseMaxIdleSeconds == 0 || elapsed < config.sparseMaxIdleSeconds)) {
      return FilterResult.sparse; // New enum value — silently dropped
    }
  }
  _lastRecordedLocation = location; // Update reference point
}
```

**Native changes**: None — this runs in the shared Dart LocationProcessor. Both Android and iOS already call `LocationProcessor.process()` before persisting.

**Edge cases**:
- First location after `start()`: always record (no previous reference)
- After `changePace(isMoving: true)`: always record (motion state change)
- During `watchPosition()`: sparse updates do NOT apply (explicit high-frequency stream)
- Geofence events: sparse updates do NOT apply (geofence evaluation uses raw GPS)

#### Web Implementation

Automatic — `LocationProcessor` is shared Dart code, runs on all platforms.

#### Test Plan

| Test | Description |
|------|-------------|
| Unit: dedup within threshold | 10 locations within 50m radius → only 1st recorded |
| Unit: dedup with movement | Locations gradually moving 200m → all recorded |
| Unit: idle timeout | Stationary for 6 min with `sparseMaxIdleSeconds: 300` → 2 recorded (0s + 300s) |
| Unit: disabled by default | `enableSparseUpdates: false` → all locations recorded |
| Unit: interaction with distance filter | `distanceFilter: 10, sparseDistanceThreshold: 50` → more filtering than distance alone |
| Unit: motion change resets | `changePace(true)` → next location always recorded regardless of sparse |
| Benchmark: throughput | 1000 locations, 80% stationary → verify ~80% reduction in records |

---

### Feature 3: Remote Config Endpoint ⏳

**Priority**: P1 — Enables ops teams to change tracking behavior fleet-wide without deploying an app update. Critical for 1000+ device deployments.

**What**: On `ready()`, optionally fetch a JSON config from a server URL. The remote config is merged with the local config (remote wins on conflicts). Supports ETag/304 caching to avoid redundant downloads.

#### Dart Model Changes

New fields in `AppConfig`:

```dart
@immutable
class AppConfig {
  // ... existing fields ...

  /// URL to fetch remote config JSON. When set, `ready()` will attempt
  /// to download config from this URL before initializing.
  /// The response must be a JSON object matching the Config structure.
  /// Default: null (disabled)
  final String? remoteConfigUrl;

  /// Custom headers for the remote config request (e.g., auth tokens).
  /// Default: empty
  final Map<String, String> remoteConfigHeaders;

  /// Timeout for the remote config fetch (milliseconds).
  /// If the fetch fails or times out, the local config is used as fallback.
  /// Default: 10000 (10 seconds)
  final int remoteConfigTimeout;

  /// How often to re-fetch remote config (seconds).
  /// 0 = only on ready() (one-time fetch).
  /// Default: 0
  final int remoteConfigRefreshInterval;
}
```

New event stream:

```dart
/// Fires when remote config is fetched and applied.
Tracelet.onRemoteConfig(void Function(RemoteConfigEvent) callback)

class RemoteConfigEvent {
  final bool success;
  final int statusCode;
  final Map<String, Object?>? appliedConfig;
  final String? error;
}
```

#### Android Implementation

| File | Change |
|------|--------|
| `TraceletAndroidPlugin.kt` | In `handleReady()`: if `remoteConfigUrl` is set, fetch JSON via OkHttp on background thread → parse → merge with local config → proceed with init. Cache ETag in SharedPreferences. |
| `ConfigManager.kt` | Add `mergeRemoteConfig(remoteMap)` — deep merge with remote values winning. Store merged result. |
| `EventDispatcher.kt` | Add `sendRemoteConfig(event)` channel. |

**Merge strategy**:
```
local config    → { geo: { distanceFilter: 10 }, http: { url: "..." } }
remote config   → { geo: { distanceFilter: 50 }, logger: { debug: true } }
merged result   → { geo: { distanceFilter: 50 }, http: { url: "..." }, logger: { debug: true } }
```
Remote values override local values at the leaf level. Null remote values are ignored (don't delete local).

**Security considerations**:
- HTTPS-only enforcement (reject HTTP URLs)
- Certificate pinning support (optional, via `remoteConfigCertificateHash`)
- Response body size limit (max 100 KB — prevents DoS)
- Server must return `Content-Type: application/json`

#### iOS Implementation

Same logic using `URLSession`. Store ETag in `UserDefaults`.

#### Web Implementation

Use `fetch()` API. Same merge logic (shared Dart code for merging).

#### Test Plan

| Test | Description |
|------|-------------|
| Unit: merge logic | Local + remote maps → verify correct merged output |
| Unit: fallback on timeout | Remote URL times out → local config used, `onRemoteConfig(success: false)` |
| Unit: ETag caching | 304 Not Modified → skip merge, use cached |
| Unit: HTTPS enforcement | HTTP URL → reject with error, don't fetch |
| Unit: size limit | Response > 100 KB → reject |
| Integration: end-to-end | Ready with remote URL → verify merged config applied → tracking starts |

---

### Feature 4: Device Attestation ⏳

**Priority**: P1 — Proves locations came from a genuine, non-rooted device. Pairs with existing mock detection (Level 1+2) to create 3-layer trust.

**What**: Generate a signed attestation token from the device's hardware-backed security module. The token can be sent alongside HTTP sync payloads for server-side verification.

**Trust layers** (cumulative):
1. **Mock detection** (existing) — Rejects spoofed GPS coordinates
2. **Device attestation** (new) — Proves the device hardware/software is genuine
3. **Audit trail** (existing) — Proves the location chain hasn't been tampered with

#### Dart Model Changes

New sub-config `AttestationConfig` added to `Config`:

```dart
@immutable
class AttestationConfig {
  /// Enable device attestation. When true, an attestation token is
  /// generated periodically and attached to HTTP sync payloads.
  /// Default: false
  final bool enabled;

  /// How often to refresh the attestation token (seconds).
  /// Attestation API calls have rate limits — don't set below 60s.
  /// Default: 3600 (1 hour)
  final int refreshInterval;

  /// Server URL to verify the attestation token (optional).
  /// If set, the plugin sends the token to this URL for server-side
  /// verification before including it in sync payloads.
  /// Default: null
  final String? verificationUrl;

  const AttestationConfig({
    this.enabled = false,
    this.refreshInterval = 3600,
    this.verificationUrl,
  });
}
```

New methods:

```dart
/// Request a fresh attestation token from the platform.
/// Returns null on platforms that don't support attestation (web).
Future<AttestationToken?> getAttestationToken();

class AttestationToken {
  /// Platform-specific token string.
  /// Android: Play Integrity API verdict token (JWT).
  /// iOS: App Attest assertion (CBOR).
  final String token;

  /// When this token was generated.
  final DateTime timestamp;

  /// Platform attestation provider.
  /// "play_integrity" | "app_attest" | "device_check"
  final String provider;

  /// Whether the device passed integrity checks.
  /// null if server-side verification hasn't been performed yet.
  final bool? verified;
}
```

#### Android Implementation

**API**: Google Play Integrity API (replaces deprecated SafetyNet).

**Dependency**: `implementation("com.google.android.play:integrity:1.4.0")`

| File | Change |
|------|--------|
| `build.gradle` | Add Play Integrity dependency |
| `attestation/DeviceAttestor.kt` (new) | `IntegrityManager.requestIntegrityToken(nonce)` → cache token → refresh on interval |
| `http/HttpSyncManager.kt` | Attach attestation token as HTTP header `X-Attestation-Token` on every sync request |
| `TraceletAndroidPlugin.kt` | Add `getAttestationToken` method channel handler |

**Nonce generation**: SHA-256 of `device_id + timestamp + random_bytes`.

**Rate limiting**: Google allows ~10,000 requests/day for free tier. Default 1hr refresh = 24 requests/day per device.

#### iOS Implementation

**API**: App Attest (iOS 14+) + DeviceCheck (iOS 11+ fallback).

| File | Change |
|------|--------|
| `attestation/DeviceAttestor.swift` (new) | `DCAppAttestService.shared.attestKey()` for primary. `DCDevice.current.generateToken()` for fallback. |
| `http/HttpSyncManager.swift` | Attach token as HTTP header `X-Attestation-Token`. |
| `TraceletIosPlugin.swift` | Add `getAttestationToken` method channel handler. |

**Key generation**: One-time `generateKey()` → attest key with Apple → cache assertion.

#### Web Implementation

No-op. Web has no device attestation API. `getAttestationToken()` returns `null`.

#### Test Plan

| Test | Description |
|------|-------------|
| Unit: token generation (mock) | Mock Play Integrity / App Attest → verify token structure |
| Unit: caching | Request token twice within refresh interval → second returns cached |
| Unit: HTTP header attachment | Verify `X-Attestation-Token` present in sync request headers |
| Unit: graceful degradation | Attestation unavailable (old device) → HTTP sync still works without token |
| Unit: nonce uniqueness | 100 consecutive nonces → all unique |
| Integration: end-to-end | Real device → generate token → send with sync → server verifies |

---

### Feature 5: Location Delta Compression ✅

**Priority**: P1 — Reduces HTTP sync payload size by 60–80%. Critical for cellular bandwidth in emerging markets and high-frequency tracking.

**What**: Instead of sending full location objects `{ lat, lng, speed, heading, ... }` for every record, send one full "reference" location followed by deltas: `{ Δlat, Δlng, Δspeed, Δheading, Δtime }`.

#### Dart Model Changes

New fields in `HttpConfig`:

```dart
@immutable
class HttpConfig {
  // ... existing fields ...

  /// Enable delta compression for HTTP sync payloads.
  /// When true, batch sync sends one full reference location followed
  /// by deltas relative to the previous location in the batch.
  /// Only applies when batchSync is true.
  /// Default: false
  final bool enableDeltaCompression;

  /// Coordinate precision (decimal places) for delta encoding.
  /// 5 = ~1.1m precision, 6 = ~0.11m. Lower = smaller payloads.
  /// Default: 6
  final int deltaCoordinatePrecision;
}
```

#### Implementation: Shared Dart + Native HTTP

**Where**: Compression logic in shared Dart (new `DeltaEncoder` algorithm class). Applied in native `HttpSyncManager` before sending batch.

**Payload format**:

Full location (reference):
```json
{
  "location": {
    "uuid": "abc-123",
    "timestamp": "2026-03-13T10:00:00Z",
    "coords": { "latitude": 37.785834, "longitude": -122.406417, "speed": 12.5, "heading": 90, "accuracy": 5.0, "altitude": 15.2 },
    "battery": { "level": 0.85, "is_charging": false },
    "activity": { "type": "in_vehicle", "confidence": 92 }
  }
}
```
**Size**: ~450 bytes

Delta location:
```json
{
  "d": {
    "u": "def-456",
    "t": 5,
    "la": 12,
    "lo": -8,
    "s": -2.1,
    "h": 5,
    "a": 1.0,
    "al": 0.3,
    "b": -0.02
  }
}
```
**Size**: ~120 bytes (73% reduction)

**Delta field mapping**:

| Short | Full | Encoding |
|-------|------|----------|
| `u` | `uuid` | Full string (always unique) |
| `t` | `Δtime` | Seconds since previous location |
| `la` | `Δlatitude` | Integer: `(lat - prevLat) * 10^precision` |
| `lo` | `Δlongitude` | Integer: `(lng - prevLng) * 10^precision` |
| `s` | `Δspeed` | Float: `speed - prevSpeed` |
| `h` | `Δheading` | Float: `heading - prevHeading` (mod 360) |
| `a` | `Δaccuracy` | Float: `accuracy - prevAccuracy` |
| `al` | `Δaltitude` | Float: `altitude - prevAltitude` |
| `b` | `Δbattery` | Float: `level - prevLevel` |

**Batch JSON structure**:
```json
{
  "location": [
    { "ref": true, "uuid": "abc-123", "timestamp": "...", "coords": { ... }, ... },
    { "d": { "u": "def-456", "t": 5, "la": 12, "lo": -8, ... } },
    { "d": { "u": "ghi-789", "t": 5, "la": 8, "lo": -3, ... } }
  ]
}
```

**Server-side decoding** (example Node.js):
```javascript
function decodeBatch(batch, precision = 6) {
  const factor = Math.pow(10, precision);
  let prev = batch[0]; // Reference
  return batch.map((item, i) => {
    if (i === 0) return item;
    const d = item.d;
    prev = {
      uuid: d.u,
      timestamp: new Date(new Date(prev.timestamp).getTime() + d.t * 1000),
      coords: {
        latitude: prev.coords.latitude + d.la / factor,
        longitude: prev.coords.longitude + d.lo / factor,
        speed: prev.coords.speed + d.s,
        // ...
      }
    };
    return prev;
  });
}
```

#### Android / iOS Implementation

| File | Change |
|------|--------|
| `http/HttpSyncManager.kt` | In `sendBatch()`: if `enableDeltaCompression`, call `DeltaEncoder.encode(locations)` before building JSON. |
| `http/HttpSyncManager.swift` | Same as Android — call shared encoder. |

**Alternatively**: Implement `DeltaEncoder` in Dart (shared algorithm) and pass the pre-encoded JSON from Dart to native via method channel. This avoids duplicating encoding logic.

Native approach is preferred since `HttpSyncManager` already builds JSON natively.

#### Web Implementation

Automatic if implemented in Dart shared code. If native, add `DeltaEncoder` to `tracelet_web` fetch logic.

#### Test Plan

| Test | Description |
|------|-------------|
| Unit: encode → decode roundtrip | 100 locations → encode deltas → decode → verify lossless (within precision) |
| Unit: precision levels | 5 vs 6 decimal places → verify accuracy within 1.1m / 0.11m |
| Unit: heading wraparound | 355° → 5° = Δ+10, not Δ-350 |
| Unit: payload size | 250 locations → verify ≥60% reduction vs full JSON |
| Unit: single location | Batch of 1 → full reference, no deltas |
| Unit: disabled | `enableDeltaCompression: false` → standard JSON payload |
| Benchmark: encoding speed | 1000 locations → verify < 1ms total encoding time |

---

## Tier 2 — Differentiating Features (No Competitor Has These)

---

### Feature 6: Battery Budget Mode ✅

**Priority**: P2 — Unique differentiator. Developer specifies maximum battery consumption per hour, plugin auto-adjusts all parameters to stay within budget.

**What**: A high-level API where the developer says "use no more than 2% battery per hour" and the plugin automatically adjusts `desiredAccuracy`, `distanceFilter`, `periodicLocationInterval`, and GPS duty cycle to meet the budget.

#### Dart Model Changes

New fields in `GeoConfig`:

```dart
@immutable
class GeoConfig {
  // ... existing fields ...

  /// Maximum battery consumption per hour (percentage points).
  /// When set (> 0), the plugin auto-adjusts accuracy, distance filter,
  /// and sampling rate to stay within the budget.
  /// Overrides manual distanceFilter/desiredAccuracy settings.
  /// 0 = disabled (manual configuration).
  /// Typical values: 1.0 (ultra-conservative) to 5.0 (high-accuracy).
  /// Default: 0.0 (disabled)
  final double batteryBudgetPerHour;
}
```

New event:

```dart
/// Fires when battery budget mode adjusts tracking parameters.
Tracelet.onBudgetAdjustment(void Function(BudgetAdjustmentEvent) callback)

class BudgetAdjustmentEvent {
  final double currentBatteryDrain; // Estimated %/hr
  final double targetBudget;        // Configured %/hr
  final double newDistanceFilter;
  final String newDesiredAccuracy;
  final int? newPeriodicInterval;   // null if not periodic mode
}
```

#### Algorithm: `BatteryBudgetEngine` (Shared Dart)

**Location**: `packages/tracelet_platform_interface/lib/src/algorithms/battery_budget_engine.dart`

**Inputs** (sampled every 5 minutes):
- Current battery level (from `Location.battery.level`)
- Battery level 5 minutes ago
- Number of GPS fixes in the window
- Current tracking mode

**Output**:
- Adjusted `distanceFilter` (increase to reduce fixes)
- Adjusted `desiredAccuracy` (degrade to save radio power)
- Adjusted `periodicLocationInterval` (increase if periodic mode)

**Control loop**:
```
every 5 minutes:
  actual_drain = (prev_battery - current_battery) * 12  // normalize to %/hr
  error = actual_drain - target_budget
  
  if error > 0.5:     // draining too fast
    distanceFilter *= 1.5
    accuracy = degrade_one_level(accuracy)
  elif error < -0.5:  // under budget, can improve
    distanceFilter *= 0.8
    accuracy = improve_one_level(accuracy)
  
  clamp(distanceFilter, 10, 5000)
  emit BudgetAdjustmentEvent
```

**Accuracy levels** (ordered by battery cost):
`high → medium → low → veryLow → lowestUnbiased`

#### Native Implementation

Minimal — the engine runs in shared Dart. Native only needs to:
1. Report battery level accurately (already done via `Location.battery`)
2. Apply config changes via existing `setConfig()` path

#### Test Plan

| Test | Description |
|------|-------------|
| Unit: high drain → throttle | Simulate 5%/hr drain with 2%/hr budget → verify distanceFilter increases |
| Unit: under budget → improve | Simulate 0.5%/hr drain with 2%/hr budget → verify distanceFilter decreases |
| Unit: clamping | Verify distanceFilter never below 10m or above 5000m |
| Unit: accuracy degradation | Track accuracy level transitions through all 5 levels |
| Unit: periodic mode | Verify periodic interval adjusts alongside distanceFilter |
| Integration: 30-min test | Real device, 2%/hr budget → verify battery usage within ±0.5% of target |

---

### Feature 7: Dead Reckoning (IMU Fusion) ⏳

**Priority**: P2 — Provides position estimates in GPS-denied areas (tunnels, underground parking, indoor). Even 50m accuracy is valuable when GPS reads zero.

**What**: When GPS signal is lost for >10 seconds, switch to inertial navigation using accelerometer + gyroscope + compass. Integrates acceleration readings to estimate displacement from last known GPS position.

#### Dart Model Changes

New fields in `GeoConfig`:

```dart
@immutable
class GeoConfig {
  // ... existing fields ...

  /// Enable dead reckoning when GPS signal is lost.
  /// Requires accelerometer + gyroscope (most modern devices).
  /// Default: false
  final bool enableDeadReckoning;

  /// Seconds of GPS absence before dead reckoning activates.
  /// Default: 10
  final int deadReckoningActivationDelay;

  /// Maximum duration (seconds) of dead reckoning before stopping.
  /// IMU drift makes estimates unreliable beyond ~2 minutes.
  /// Default: 120
  final int deadReckoningMaxDuration;
}
```

Location metadata:

```dart
class Location {
  // ... existing fields ...

  /// True if this location was estimated via dead reckoning (not GPS).
  final bool isDeadReckoned;
}
```

#### Algorithm: `DeadReckoningEngine` (Native)

**Must be native** — requires raw sensor data at 50-100 Hz, too fast for Dart method channel round-trips.

**Android**: `SensorManager.registerListener()` for `TYPE_LINEAR_ACCELERATION`, `TYPE_GYROSCOPE`, `TYPE_MAGNETIC_FIELD`.

**iOS**: `CMMotionManager.startDeviceMotionUpdates(using: .xMagneticNorthZReference)` at 100 Hz.

**Algorithm** (Pedestrian Dead Reckoning — PDR):
```
1. Detect step events (peak detection on accelerometer magnitude)
2. Estimate step length: 0.7 * sqrt(accel_peak - accel_trough)
3. Get heading from magnetometer (fused with gyroscope for stability)
4. new_lat = prev_lat + step_length * cos(heading) / meters_per_degree
5. new_lng = prev_lng + step_length * sin(heading) / (meters_per_degree * cos(lat))
6. Set accuracy = 50.0 + (elapsed_seconds * 2)  // Accuracy degrades over time
```

**For vehicle mode** (detected via activity recognition):
```
1. Double-integrate linear acceleration (with high-pass filter)
2. Apply heading from gyroscope-fused compass
3. Accuracy = 100.0 + (elapsed_seconds * 5)  // Vehicle IMU drift is worse
```

#### Implementation Files

| Platform | New Files | Existing Changes |
|----------|-----------|-----------------|
| Android | `location/DeadReckoningEngine.kt` | `LocationEngine.kt`: detect GPS loss → start DR → emit DR locations |
| iOS | `location/DeadReckoningEngine.swift` | `LocationEngine.swift`: same |
| Dart | none (native-only) | `location_processor.dart`: mark `isDeadReckoned` locations, apply wider accuracy threshold |

#### Test Plan

| Test | Description |
|------|-------------|
| Unit: step detection | Simulated accelerometer data → verify step count within 10% |
| Unit: heading fusion | Gyroscope + magnetometer data → verify heading within 15° |
| Unit: accuracy degradation | Verify accuracy increases linearly with elapsed time |
| Unit: max duration cutoff | After 120s → DR stops, no more estimated locations |
| Unit: GPS recovery | GPS returns → DR stops, seamless transition back to GPS |
| Integration: tunnel test | Walk through 200m tunnel → verify track within 50m of actual |

---

### Feature 8: Compliance Report Generator ✅

**Priority**: P2 — Auto-generate GDPR Article 30 / CCPA data processing reports. No manual audit needed.

**What**: `generateComplianceReport()` returns a structured report of all location data processing: what was collected, stored, synced, for how long, privacy zones active, audit trail status.

#### Dart Model Changes

```dart
/// Generate a GDPR/CCPA compliance report.
Future<ComplianceReport> generateComplianceReport();

class ComplianceReport {
  /// Report generation timestamp.
  final DateTime generatedAt;
  
  /// Data inventory.
  final int totalLocationsStored;
  final int totalLocationsSynced;
  final int totalLocationsDeleted;
  
  /// Retention policy.
  final int maxDaysToPersist;
  final int maxRecordsToPersist;
  final DateTime? oldestRecord;
  final DateTime? newestRecord;
  
  /// Privacy measures.
  final bool databaseEncrypted;
  final int activePrivacyZones;
  final List<String> privacyZoneIdentifiers;
  
  /// Data destinations.
  final String? httpSyncUrl;
  final bool autoSyncEnabled;
  
  /// Audit trail.
  final bool auditTrailEnabled;
  final bool auditTrailValid; // Last verification result
  
  /// Consent.
  final int locationPermissionStatus;
  final int motionPermissionStatus;
  
  /// Data minimization.
  final bool sparseUpdatesEnabled;
  final bool kalmanFilterEnabled;
  
  /// Export as JSON for automated compliance tooling.
  Map<String, Object?> toJson();
  
  /// Export as human-readable Markdown report.
  String toMarkdown();
}
```

#### Implementation

Entirely in Dart (shared code) — queries existing APIs:
- `getCount()`, `getLocations()` for data inventory
- `getState()` for config snapshot
- `getHealth()` for permission status
- `verifyAuditTrail()` for chain integrity
- `getPrivacyZones()` for active zones
- `isDatabaseEncrypted()` for encryption status

No native changes needed.

---

### Feature 9: Geofence Clustering (R-tree Spatial Index) ✅

**Priority**: P2 — Enables 10,000+ geofences with O(log n) lookup. Required for delivery/logistics apps.

**What**: Replace the current O(n) linear scan for geofence proximity evaluation with an R-tree spatial index. On each location update, query the R-tree for geofences within the proximity radius instead of iterating all geofences.

#### Implementation: Shared Dart Algorithm

**Where**: `packages/tracelet_platform_interface/lib/src/algorithms/rtree.dart` (new file)

**Algorithm**: R-tree with M=8 (8 entries per node). Bulk-loaded via Sort-Tile-Recursive (STR) for optimal initial layout.

**API**:
```dart
class RTree<T> {
  void insert(double lat, double lng, double radius, T data);
  void remove(T data);
  List<T> queryCircle(double lat, double lng, double radiusMeters);
  List<T> queryBBox(double minLat, double minLng, double maxLat, double maxLng);
  int get size;
}
```

**Integration point**: `GeofenceEvaluator` replaces `for (final geofence in allGeofences)` with `rtree.queryCircle(lat, lng, proximityRadius)`.

**Performance target**: 10,000 geofences → < 1ms per query (current O(n): ~10ms).

---

### Feature 10: Transport Mode Carbon Estimator 🔧

**Priority**: P3 — EU CSRD (Corporate Sustainability Reporting Directive) requires companies to report Scope 3 emissions from employee commuting by 2026. Growing regulatory requirement.

**What**: Automatically calculate CO₂ emissions per trip based on detected transport mode. Integrate with trip detection to produce per-trip and cumulative carbon reports.

#### Dart Model Changes

```dart
class TripEvent {
  // ... existing fields ...
  
  /// Estimated CO₂ emissions for this trip (grams).
  /// Based on transport mode × distance.
  /// null if carbon estimation is disabled.
  final double? carbonGrams;
  
  /// Dominant transport mode for this trip.
  final String dominantTransportMode;
}

/// Get cumulative carbon emissions.
Future<CarbonReport> getCarbonReport({DateTime? from, DateTime? to});

class CarbonReport {
  final double totalCarbonGrams;
  final Map<String, double> carbonByMode; // mode → grams
  final Map<String, double> distanceByMode; // mode → meters
  final int totalTrips;
}
```

**Emission factors** (gCO₂/km, EU EEA 2024 averages):

| Mode | Factor | Source |
|------|--------|--------|
| `in_vehicle` (car) | 192 | EU average new car |
| `on_bicycle` | 0 | Zero emission |
| `walking` | 0 | Zero emission |
| `running` | 0 | Zero emission |
| `on_foot` | 0 | Zero emission |
| Bus (if detectable) | 89 | EU urban bus average |
| Train (if detectable) | 41 | EU rail average |

**Implementation**: Shared Dart algorithm. Extend `TripManager` to accumulate distance-per-mode and multiply by emission factors on trip end.

---

## Implementation Roadmap

### v1.1.0 — "Enterprise Core" (Estimated: 4 features)

| Order | Feature | Status | Dependencies |
|-------|---------|--------|-------------|
| 1 | **Sparse Updates** | ✅ Done | None — pure Dart, smallest scope |
| 2 | **Remote Config Endpoint** | ⏳ | Depends on OkHttp (Android) / URLSession (iOS) — already available |
| 3 | **Delta Compression** | ✅ Done | Should ship after **Sparse Updates** (they compose well) |
| 4 | **Compliance Report** | ✅ Done | Pure Dart, no native — quick win |

### v1.2.0 — "Trust & Security"

| Order | Feature | Status | Dependencies |
|-------|---------|--------|-------------|
| 1 | **Encrypted SQLite** | ⏳ | SQLCipher dependency, DB migration |
| 2 | **Device Attestation** | ⏳ | Play Integrity (Android) / App Attest (iOS) |

### v1.3.0 — "Intelligence"

| Order | Feature | Status | Dependencies |
|-------|---------|--------|-------------|
| 1 | **Battery Budget Mode** | ✅ Done | Requires battery drain calibration data |
| 2 | **Geofence Clustering** | ✅ Done | R-tree algorithm |
| 3 | **Dead Reckoning** | ⏳ | Native sensor access, complex IMU math |
| 4 | **Carbon Estimator** | 🔧 Algorithm exists, not wired | Depends on trip detection (already complete) |

---

## Publish Order (per Monorepo Rules)

For each release:
1. `tracelet_platform_interface` (new models, method signatures)
2. `tracelet_android` + `tracelet_ios` + `tracelet_web` (implementations)
3. `tracelet` (app-facing API re-exports)

---

## Competitive Impact Summary

| Feature | Tracelet | Transistor/FBG | Other OSS |
|---------|----------|---------------|-----------|
| Sparse Updates | ✅ v0.8 | ✅ v5.0.5 | ❌ |
| Remote Config | 🔜 v1.1 | ⚠️ Partial | ❌ |
| Delta Compression | ✅ v0.8 | ❌ | ❌ |
| Compliance Report | ✅ v0.8 | ❌ | ❌ |
| Encrypted SQLite | 🔜 v1.2 | ❌ | ❌ |
| Device Attestation | 🔜 v1.2 | ❌ | ❌ |
| Battery Budget | ✅ v0.8 | ❌ | ❌ |
| R-tree Geofences | ✅ v0.8 | ❌ | ❌ |
| Dead Reckoning | 🔜 v1.3 | ❌ | ❌ |
| Carbon Estimator | 🔧 v1.3 | ❌ | ❌ |
| **Audit Trail** | ✅ v1.0 | ❌ | ❌ |
| **Privacy Zones** | ✅ v1.0 | ❌ | ❌ |
| **Mock Detection** | ✅ v1.0 | ❌ | ❌ |
| **Polygon Geofences** | ✅ v1.0 | ❌ | ❌ |
| **Periodic Mode** | ✅ v1.0 | ❌ | ❌ |
| **Web Support** | ✅ v1.0 | ❌ | ❌ |

After v1.3, Tracelet will have **16 features that no competitor offers at any price** — making its free, open-source nature a decisive advantage for enterprise adoption.
