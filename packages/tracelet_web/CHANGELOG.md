## 3.8.8

Version alignment with tracelet 3.8.8.

## 3.8.7

Version alignment with tracelet 3.8.7.

## 3.8.6

Version alignment with tracelet 3.8.6.

## 3.8.5

**FIX**: `setOdometer()` drops the reference the odometer measures from. Accumulation runs off `_lastLocation`, which the setter left in place, so the next browser fix added the whole span since the previous one and a reset survived exactly one fix — the same defect the native engines had, reached independently ([#387](https://github.com/Ikolvi/Tracelet/issues/387)).

Version alignment with tracelet 3.8.5.

## 3.8.4

Version alignment with tracelet 3.8.4.

## 3.8.3

**FIX**: `maxRecordsToPersist: -1` no longer throws `RangeError` on every insert. `-1` is the documented "unlimited" sentinel, and because `ready()` resolves every field before it crosses the channel it is what the *default* configuration sends — so the unguarded `while (_locations.length > _maxRecords) removeAt(0)` emptied the store and then ran off the end of it on the first insert of every web session. A non-positive cap now means unlimited, as it already did on the native platforms ([#362](https://github.com/Ikolvi/Tracelet/issues/362)).

**FIX**: `maxDaysToPersist` is now enforced on web. `applyConfig` never read the key, so the web store had no age-based retention at all. A record whose `timestamp` is absent or unparseable is kept rather than treated as ancient; the record cap bounds those ([#361](https://github.com/Ikolvi/Tracelet/issues/361)).

## 3.8.2

Version alignment with tracelet 3.8.2.

## 3.8.1

Version alignment with tracelet 3.8.1.

## 3.8.0

Version alignment with tracelet 3.8.0.

## 3.8.0-beta.2

**FEAT**: `Tracelet.getCurrentLocationTuning()` reports the location-filter thresholds **actually in force**, read back from the native processor rather than from the config you set. `activeConfig` is a Dart-side mirror of the last `Config` passed in, so it cannot tell you whether a value reached the filter that uses it — and it cannot show a transport-mode auto-tune, which changes these thresholds with no config call at all. Returns `null` before a tracking session has built a processor, and always `null` on Web ([#303](https://github.com/Ikolvi/Tracelet/issues/303)).

**FIX**: the method-channel `android` config block now carries the same `geofenceModeHighAccuracy` value as the `geofence` block. Native reads the key from both, so emitting the raw Android-only flag in one and the OR'd value in the other made behavior depend on which block the platform happened to consult ([#305](https://github.com/Ikolvi/Tracelet/issues/305)).

**FIX**: (Android + iOS) the location-filter configuration now reaches the Rust processor at runtime. `setConfig()` rebuilt the processor only for a short list of location keys, so `trackingAccuracyThreshold`, `odometerAccuracyThreshold`, `maxImpliedSpeed`, `filterPolicy`, `enableAdaptiveMode`, `rejectMockLocations`, `mockDetectionLevel`, the sparse-update trio and `useKalmanFilter` were accepted, cached, and then ignored until the next cold start. Because `LocationProcessor` captured its base thresholds at construction, this also broke the #301 guarantee that disabling `autoTuneFromTransportMode` restores "the values you configured" — it restored the values captured when the processor was built. A new `set_base_tuning` carries thresholds in without dropping the positional anchor a rebuild would cost (the reason `retune` exists, #299); the remaining constructor-only parameters trigger a targeted rebuild, and the Kalman filter is toggled independently of the processor ([#303](https://github.com/Ikolvi/Tracelet/issues/303)).

**FIX**: (iOS) the whole `LocationFilter` block now reaches the config cache. Every transport serializes it as a `filter` sub-map nested inside `geo`, but the iOS `ConfigManager` flattened only one level and then stored that block as a single opaque value no getter ever read — so `trackingAccuracyThreshold`, `odometerAccuracyThreshold`, `maxImpliedSpeed`, `rejectMockLocations`, `mockDetectionLevel` and `useKalmanFilter` were pinned to their defaults (100 m / 0 m / 80 m/s / off) no matter what was configured, at `ready()` as well as at runtime. The change detection added above compared key names absent from both config snapshots, so a filter change triggered neither the targeted rebuild nor `setBaseTuning` — the fix landed on a bridge that was never connected. Caches persisted in the nested shape are lifted on load, because `autoResumeTracking()` starts the pipeline off the persisted cache with no `ready()` in between ([#303](https://github.com/Ikolvi/Tracelet/issues/303)).

**FIX**: (Android + iOS) `LocationFilter.policy` is now applied. It is serialized under `policy` by every transport, while `getFilterPolicy()` — and the processor-rebuild key list — read `filterPolicy`, so the value was cached under a name nothing asked for and the policy stayed at `adjust` however it was configured. It is renamed during flattening, so both readers see it ([#303](https://github.com/Ikolvi/Tracelet/issues/303)).

**FIX**: (Android + iOS) `logMaxDays` is now applied. Both platforms pruned logs only by a row count derived from `logLevel`, so the configured retention window was accepted and discarded — `logMaxDays: 3` and `logMaxDays: 90` behaved identically. Log pruning now enforces both caps ([#304](https://github.com/Ikolvi/Tracelet/issues/304)).

**FIX**: (iOS) `disableLocationAuthorizationAlert` is now honored. The permission manager requested authorization unconditionally, so apps that wanted to own their pre-permission UX could not suppress the system prompt. It now reports the current status instead of prompting ([#304](https://github.com/Ikolvi/Tracelet/issues/304)).

**FIX**: (Web) `GeofenceConfig.geofenceModeHighAccuracy` is now honored. The web plugin read only the deprecated `AndroidConfig.geofenceModeHighAccuracy`, so setting the documented cross-platform flag had no effect on web. It is now OR'd with the deprecated flag, matching both Pigeon hosts, and `geofenceExitAccuracyMax` is carried too ([#305](https://github.com/Ikolvi/Tracelet/issues/305)).

**FIX**: the method-channel transport no longer drops geofence configuration. `_geofenceToMap` emitted two of the five geofence keys, silently discarding `geofenceModeHighAccuracy` (so no OR was performed on that path), `geofenceInitialTrigger`, and `geofenceExitAccuracyMax` — the #276 tunable ([#305](https://github.com/Ikolvi/Tracelet/issues/305)).

**FIX**: the four built-in `TraceletProfile` presets now set high-accuracy geofencing through the cross-platform `geofence` block instead of the deprecated `android` one. `TraceletProfile.highAccuracy` therefore enables it on iOS as well, and the deprecated field has no remaining internal dependants ([#305](https://github.com/Ikolvi/Tracelet/issues/305)).

**FIX**: the pure-Dart `GeofenceEvaluator` now applies the `geofenceExitAccuracyMax` policy (`-1` full gating, `0` disabled, `N` clamp). It is documented as a mirror of the Rust core but gated EXIT on raw accuracy, diverging from both native managers, which pass accuracy through `effectiveExitAccuracy` first (#276). The parameter defaults to `-1`, so existing callers are unaffected ([#306](https://github.com/Ikolvi/Tracelet/issues/306)).

**FIX**: the Rust geofence evaluator drops pending exit confirmations for fences a re-index no longer covers. `clear()` and `remove_geofence()` both pruned them; `index_geofences()` did not, so a half-accumulated count survived and could contribute to a later EXIT ([#306](https://github.com/Ikolvi/Tracelet/issues/306)).

**DEPRECATED**: `AuditConfig.includeExtrasInHash` and `AttestationConfig.verificationUrl` were never implemented — no platform reads either value. They are now annotated so the analyzer surfaces it, rather than being silently discarded at runtime. Implementing them is not a patch: the first changes what the audit chain hashes and so invalidates every existing chain, and the second needs a token-verification transport ([#304](https://github.com/Ikolvi/Tracelet/issues/304)).

## 3.8.0-beta

Version alignment with tracelet 3.8.0-beta.

## 3.8.0-alpha

Version alignment with tracelet 3.8.0-alpha.

## 3.7.6

Version alignment with tracelet 3.7.6.

## 3.7.5

Version alignment with tracelet 3.7.5.

## 3.7.4

Version alignment with tracelet 3.7.4.

## 3.7.3

Version alignment with tracelet 3.7.3.

## 3.7.2

Version alignment with tracelet 3.7.2.

## 3.7.1

Version alignment with tracelet 3.7.1.

## 3.7.0

Version alignment with tracelet 3.7.0.

## 3.6.15

Version alignment with tracelet 3.6.15.

## 3.6.14

Version alignment with tracelet 3.6.14.

## 3.6.13

Version alignment with tracelet 3.6.13.

## 3.6.12

Version alignment with tracelet 3.6.12.

## 3.6.11

Version alignment with tracelet 3.6.11.

## 3.6.10

Version alignment with tracelet 3.6.10.

## 3.6.9

Version alignment with tracelet 3.6.9.

## 3.6.8

Version alignment with tracelet 3.6.8.

## 3.6.7

Version alignment with tracelet 3.6.7.

## 3.6.6

Version alignment with tracelet 3.6.6.

## 3.6.5

Version alignment with tracelet 3.6.5.

## 3.6.4

Version alignment with tracelet 3.6.4.

## 3.6.3

Version alignment with tracelet 3.6.3.

## 3.6.2

Version alignment with tracelet 3.6.2.

## 3.6.1

Version alignment with tracelet 3.6.1.

## 3.6.0

**FEAT**: `Tracelet.updateLocationProviderOptions()` — live provider-options override without a pipeline restart, on iOS and Android ([#241](https://github.com/Ikolvi/Tracelet/pull/241)).

Version alignment with tracelet 3.6.0.

## 3.5.7

**FIX**: Build fails without AGP built-in Kotlin (AGP <9 / builtInKotlin=false) ([#239](https://github.com/Ikolvi/Tracelet/issues/239)).

## 3.5.6

**FIX**: Custom sync body 400 Bad Request HTTP errors now gracefully return fallback results instead of propagating fatal exceptions in native Sync engines ([#238](https://github.com/Ikolvi/Tracelet/issues/238)).

## 3.5.5

**FIX**: Ensure foreground service is properly started in periodic mode when configured ([#237](https://github.com/Ikolvi/Tracelet/issues/237)).

## 3.5.4

**FIX**: Enrich geofence transition events with real coordinate metrics and battery ([#231](https://github.com/Ikolvi/Tracelet/issues/231)).
**FIX**: Propagate runtime `setConfig` changes to active native tracking/sensor loops ([#230](https://github.com/Ikolvi/Tracelet/issues/230)).
**FIX**: Null-guard subsystems during teardown so Activity destruction never throws ([#227](https://github.com/Ikolvi/Tracelet/issues/227)).
**FIX**: Android: standard geofence mode no longer runs a foreground service, complying with Google Play's 2026-10-28 foreground-service-for-geofencing policy.

## 3.5.3

**FIX**: Added explicit ProGuard keep rules for `TraceletStartupProvider` in the `tracelet_android` package to prevent `ClassNotFoundException` on process start when aggressive shrinking (like R8 full mode) is used ([#228](https://github.com/Ikolvi/Tracelet/issues/228)).

## 3.5.2

**FIX**: Android continuous tracking no longer silently stops after a while on aggressive OEMs (Samsung One UI, etc.). The foreground-service wakelock used a fixed 10-minute auto-expiry and was never renewed, so once it lapsed the CPU could deep-sleep and FusedLocationProvider stopped delivering updates with no error or callback. The wakelock is now renewed for the lifetime of tracking ([#222](https://github.com/Ikolvi/Tracelet/issues/222)).

## 3.5.1

**FEAT**: Crash detection now uses the device barometer as an extra confirmation clue — a serious crash or airbag deployment causes a quick cabin air-pressure change that raises crash confidence on phones with a pressure sensor; phones without one skip it with no downside ([#173](https://github.com/Ikolvi/Tracelet/issues/173)).
**FEAT**: Stronger crash/fall corroboration — a sudden post-impact speed collapse ([#181](https://github.com/Ikolvi/Tracelet/issues/181)) and the free-fall → impact → stillness signature ([#180](https://github.com/Ikolvi/Tracelet/issues/180)) now raise confidence, and confirmation is process-death-safe so a confirmed event survives the app being killed ([#182](https://github.com/Ikolvi/Tracelet/issues/182)).

## 3.5.0

**FEAT**: Crash-detection ML model promoted from **beta to stable** (trained on a CC0 / public-domain dataset, cleared for commercial use) and the on-device model cache now auto-re-downloads on a new published version ([#183](https://github.com/Ikolvi/Tracelet/issues/183)).

## 3.4.2

 - **FEAT**: implement telematics deduplication with synced-state tracking and improved foreground service fault tolerance. ([0581c6e7](https://github.com/Ikolvi/Tracelet/commit/0581c6e7a30a5d436ceb2e8c5d75e46505431e4b))

## 3.4.1

 - Update a dependency to the latest release.

## 3.4.0

 - Update a dependency to the latest release.

## 3.3.4

**CHORE**: bump version.

## 3.3.3

 - **FIX**: Correct the `geofenceModeHighAccuracy` config mapping in Web plugin to prevent runtime getter errors. ([065b3bbc](https://github.com/Ikolvi/Tracelet/commit/065b3bbc631a367364eba2b666c54120174530cc))

## 3.3.1

- **CHORE**: version bump for patch release

## 3.3.0

* **FEAT** (Driving & Safety): On-device driving-behavior telematics — `harsh_braking` / `harsh_acceleration` / `harsh_cornering` / `speeding` via `TelematicsConfig` + `Tracelet.onDrivingEvent` (opt-in, default off) ([#163](https://github.com/Ikolvi/Tracelet/issues/163)).
* **FEAT** (Driving & Safety): On-device transport-mode classifier (still/walking/running/cycling/vehicle) fusing accelerometer + GPS via `ClassifierConfig` + `Tracelet.onModeChange` ([#164](https://github.com/Ikolvi/Tracelet/issues/164)).
* **FEAT** (Driving & Safety): Crash & fall detection with a cancel-countdown confirmation flow via `ImpactConfig` + `Tracelet.onImpact` and `Tracelet.confirmImpact` / `Tracelet.cancelImpact` (opt-in, default off) ([#165](https://github.com/Ikolvi/Tracelet/issues/165)).
* All three features are **default-off** and side-channel — no change to existing tracking when disabled. See [Driving & Safety](https://github.com/Ikolvi/Tracelet/blob/main/help/DRIVING-AND-SAFETY.md).

## 3.2.19

**CHORE**: version bump for patch release

## 3.2.18

* **FIX** (Native): `ready()` / `getState()` now populate `State.config` with the active configuration instead of leaving it permanently `null` ([#147](https://github.com/Ikolvi/Tracelet/issues/147)).
* **FEAT**: Add `HttpConfig.syncInterval` for interval-based sync — the documented repeating-timer cadence was missing from the Dart config and the Pigeon layer; the native interval timer now flushes the offline queue on this cadence ([#149](https://github.com/Ikolvi/Tracelet/issues/149)).
* **FIX** (Native): `destroySyncedLocations()` returns the real number of synced-and-pruned locations instead of a hardcoded `0` stub ([#154](https://github.com/Ikolvi/Tracelet/issues/154)).
* **FEAT**: Expose the offline queue with `getPendingLocations()` and `getPendingLocationCount()` ([#159](https://github.com/Ikolvi/Tracelet/issues/159)).
* **FIX** (Native): Honor the `useKalmanFilter` config key so the Extended Kalman Filter is no longer silently disabled by a key mismatch ([#148](https://github.com/Ikolvi/Tracelet/issues/148)).
* **FIX** (Native): Propagate the detected activity (walking / driving / still) into recorded locations — fixes a permanent `"activity": "unknown"` ([#155](https://github.com/Ikolvi/Tracelet/issues/155)).
* **FIX** (Native): Rebuild the native location processor when `ready()` applies a new config, so settings such as `distanceFilter` take effect immediately instead of using stale defaults ([#157](https://github.com/Ikolvi/Tracelet/issues/157)).
* **FIX** (Native): `getCount()` honors time-bound queries instead of always returning the whole-database total ([#152](https://github.com/Ikolvi/Tracelet/issues/152)).
* **FIX**: Guard the `AuditConfig` hash-algorithm mapping so configuring `sha384` / `sha512` no longer crashes with a fatal `RangeError` during `ready()` — unsupported variants fall back to `sha256` ([#150](https://github.com/Ikolvi/Tracelet/issues/150)).
* **FIX** (Native): The HTTP sync payload now includes each point's motion state `is_moving` ([#151](https://github.com/Ikolvi/Tracelet/issues/151)) and its trigger `event` (location / motionchange / heartbeat / geofence) ([#156](https://github.com/Ikolvi/Tracelet/issues/156)) — both were previously omitted by the native sync record.

## 3.2.17

* **FIX** (Native): Resolve iOS auto-sync thread starvation by offloading synchronous HTTP requests to a background DispatchQueue to prevent blocking Swift Concurrency pools ([#146](https://github.com/Ikolvi/Tracelet/issues/146)).
* **CHORE** (Docs): Fix Nextra changelog rendering bug and improve auto-translation glossary script for internationalization.

## 3.2.16

* **FIX** (Native): Resolve Android/iOS getting stuck in the moving state and never transitioning back to stationary, which kept continuous GPS active and drained the battery. The accelerometer stillness sampler now stays active during the stop-timeout countdown and requires sustained motion — rather than a single noisy or stale sample — to abort it ([#142](https://github.com/Ikolvi/Tracelet/issues/142)).
* **FIX** (Native): Background and post-reboot location captures are persisted (and therefore synced) again. Headless tracking (killed-state relaunch / boot) never calls `ready()`, so an internal readiness guard silently dropped every captured location before it reached the database, leaving auto-sync with nothing to upload.
* **FIX** (Android): The foreground-service notification now reliably appears when the app is backgrounded or terminated with `showNotificationOnPauseOnly` enabled. The app's own foreground service skewed foreground/background detection (and OS process-importance updates lag), so the pause-only notification was suppressed even though tracking and syncing continued.

## 3.2.15

* **FIX** (Native): Allow `getState()` and `stop()` to be called before `ready()` is invoked, correctly reporting persistent state and shutting down background services if the app was restarted from a killed state.
* **CHORE**: Update dependencies and constraints.
* **FIX**: Resolve `MissingPluginException` and test timing issues with `setHasCustomSyncBodyBuilder`.

## 3.2.14

 - **DOCS**: add official documentation URL to all package READMEs. ([9eb6951e](https://github.com/Ikolvi/Tracelet/commit/9eb6951e64c13007f3264e2d44f0feb9222500a3))
 - **DOCS**: integrate nextra website and update pubspec URLs. ([99b7fda8](https://github.com/Ikolvi/Tracelet/commit/99b7fda82e290ca6c8175313eae62a2475360050))

## 3.2.13

- **CHORE**: Version bump to 3.2.13 to stay in lockstep with the federated set (Android `startOnBoot` reboot-tracking fix — see `tracelet_android`). No changes to this package.

## 3.2.12

- **CHORE**: Re-release to align the full federated package set and native SDKs to a single consistent version. The 3.2.11 release published with mismatched versions across some packages (a few resolved to 3.2.10). No functional code changes.

## 3.2.11

- **CHORE**: Version bump to align with 3.2.11 platform release.

## 3.2.10

- **FIX**(ios): Remove `TraceletCore+Dummy.swift` / `TraceletSyncFFI+Dummy.swift` — `@_silgen_name` declarations from the old static library model caused "Undefined symbol" linker errors after the static→dynamic xcframework migration.
- **FIX**(android): Catch `ForegroundServiceStartNotAllowedException` in `LocationService.start()` so calling `ready()` from the background on Android 12+ no longer crashes the host app; the foreground service start is deferred until the app returns to foreground.

## 3.2.9

- **FIX**(ios): Remove `TraceletCore+Dummy.swift` / `TraceletSyncFFI+Dummy.swift` — `@_silgen_name` declarations from the old static library model caused "Undefined symbol" linker errors after the static→dynamic xcframework migration.
- **FIX**(android): Catch `ForegroundServiceStartNotAllowedException` in `LocationService.start()` so calling `ready()` from the background on Android 12+ no longer crashes the host app; the foreground service start is deferred until the app returns to foreground.


## 3.2.8

- **FIX**: Persist geofence ENTER/EXIT events in offline queue and auto-sync to server — events were previously dispatched to the app but never stored in the local SQLite database (Issue #128).
- **FIX**: Structured event envelope (`event_type`, `event_payload`) for geofence events round-trips correctly through `getLocations()` and `insertLocation()`.
- **FIX**(sync): Stop POSTing malformed error payloads on failed HTTP sync requests; fix iOS custom-body deadlock in `setSyncBodyBuilder` (Issue #125).
- **FIX**(android): Throw `NOT_READY` error before `ready()` is called to match iOS parity; previously Android silently ignored SDK calls before initialization (Issue #129).
- **FIX**(ios): Resolve `flutter_rust_bridge has not been initialized` on release builds — `TraceletCore` is now a dynamic framework, preventing dead-code stripping of FRB symbols (Issues #116, #123, #124).
- **FIX**(android): Resolve `Failed to lookup symbol 'frb_get_rust_content_hash'` — Rust symbols are now loaded directly from `libtracelet_core.so` bypassing `RTLD_LOCAL` isolation (Issues #116, #123).
- **PERF**(ios): Reduce background motion sensor CPU/battery usage — accelerometer polling is now paused when stationary (Issue #130).
- **FIX**: Persist historical `is_moving` state per location record so `getLocations()` returns accurate values instead of always returning the current live state (Issue #126).

## 3.2.7

- **FIX**(ios): prevent dead code stripping of flutter_rust_bridge symbols in release builds.
- **FIX**(android): implement OEM hardening mitigations and introduce `showPowerManager` to handle aggressive battery restrictions on specific OEM devices.

## 3.2.6

- **PERF**: Optimize database timestamp queries for O(log N) fast filtering and resolve precision bugs (Issue #119).
- **FEAT**: Implement `sslPinningFingerprints` natively across iOS and Android with Rust configs.
- **FIX**: Include pinned fingerprints in SSL verification error logs and messages.
- **FIX**: Rate limit Android MotionDetector logcat flooding during stillness (Issue #121).
- **FIX**: Resolve race conditions in tests for Issue 118.
- **REFACTOR**: Update integration test to use Config.fromMap for comprehensive Tracelet configuration testing.

## 3.2.4

* **FIX**(ios): safely resolve dynamic symbols when `use_frameworks! :linkage => :dynamic` is used.

## 3.2.3

- **FIX**: Force speed motion manager to evaluate initial speed on Android to prevent the state machine from being permanently stuck in `MOVING` when indoors ([#115](https://github.com/Ikolvi/Tracelet/issues/115)).
- **FIX**: Resolve `flutter_rust_bridge has not been initialized` crash by ensuring the Rust core is instantiated and initialized before accessing methods ([#116](https://github.com/Ikolvi/Tracelet/issues/116)).
- **CHORE**: Sync release versions across all packages.

## 3.2.2

- **CHORE**: Sync release versions across all federated packages and update Swift Package Manager configuration.

## 3.2.1

- **CHORE**: Align federated package versions and include additional patch updates.

## 3.2.0

- **FEAT**(web): Add reverse geocoding functionality (`resolveAddress`).

## 3.1.14

- **CHORE**: Sync release versions across workspace.


## 3.1.10

 - Bump "tracelet_web" to `3.1.10`.

## 3.1.9

- **FIX**(android): conditionally apply kotlin-android plugin to support older flutter SDKs while preventing warnings in modern Flutter environments.
- **CHORE**(ci): add strict pre-publish flutter build verification step to `release.yml`.

## 3.1.8

- Fix iOS SPM publishing

## 3.1.7

 - **FIX**(android): apply kotlin-android plugin to fix gradle build errors on newer AGP versions.
 - **FIX**(ios): fix SPM source folder paths in release bundling to ensure SDK compiles properly via CocoaPods.
 - **FIX**(ios): fix duplicate module import errors by adding conditional import checks for TraceletSDK.

## 3.1.4

- **CHORE**: Sync release versions across workspace.

## 3.0.1

- **FIX**(ios): Add missing `FlutterFramework` dependency to SPM plugin configuration to resolve compilation failures and `PlatformException`s.

## 3.0.0

- **FEAT**: Smart Motion Mode — Introduced `MotionDetectionMode.smart` mode interface mapping for web platform.

## 2.1.0

- **FIX**: Implement all typed event stream getters (`locationEvents`, `motionChangeEvents`, `watchPositionEvents`, `activityChangeEvents`, `providerChangeEvents`, `geofenceEvents`, `heartbeatEvents`, `httpEvents`, `scheduleEvents`, `powerSaveChangeEvents`, `connectivityChangeEvents`, `enabledChangeEvents`, `notificationActionEvents`, `authorizationEvents`) — these were previously unimplemented and threw `UnimplementedError`, preventing `Tracelet.ready()` from completing on web.
- **FIX**: Geolocation permission request no longer hangs indefinitely — added a `try/catch` around `getCurrentPosition()` to intercept synchronous JS errors thrown on insecure origins or blocked contexts, and added a 15-second Dart-side timeout as a safety net.
- **FIX**: Geolocation `PositionOptions.timeout` removed to prevent silent timeouts blocking the browser's native permission dialog.
- **FEAT**: Speed-based motion detection mode — `WebLocationEngine` now respects `MotionConfig.motionDetectionMode = speed`, transitioning `isMoving` state based on GPS speed vs. `speedMovingThreshold` with a configurable `speedStationaryDelay` debounce timer.
- **FEAT**: Enterprise features — privacy zones (`addPrivacyZone`, `removePrivacyZone`, `getPrivacyZones`), audit trail (`verifyAuditTrail`, `getAuditProof`), carbon estimator (`getCarbonReport`), and database encryption stubs (`isDatabaseEncrypted`, `encryptDatabase`, `getAttestationToken`).
- **CHORE**: Version bump for monorepo lockstep alignment with `tracelet 2.1.0`.
- **CHORE**: Update `tracelet_platform_interface` constraint to `^2.1.0`.

## 2.0.9

 - Update a dependency to the latest release.

## 2.0.8

- **CHORE**: Update `tracelet_platform_interface` constraint to `^2.0.8`.
- **CHORE**: Version bump for monorepo consistency and package lockstep alignment.

## 2.0.7

- **CHORE**: Version bump for monorepo consistency and package lockstep alignment.
- **CHORE**: Update `tracelet_platform_interface` constraint to `^2.0.7`.

## 2.0.6

- **CHORE**: Update `tracelet_platform_interface` constraint to `^2.0.6`.

## 2.0.5

- **CHORE**: Version bump for monorepo consistency and package lockstep alignment.
- **CHORE**: Update `tracelet_platform_interface` constraint to `^2.0.5`.

## 2.0.4

- **CHORE**: Version bump for monorepo consistency and native SDK alignment.
- **CHORE**: Update `tracelet_platform_interface` constraint to `^2.0.4`.

## 2.0.3

- **FIX**: Removed unreliable timestamp drift heuristic from location spoofing detection.

# Changelog

## 2.0.1

- **CHORE**: Version bump for iOS status bar fix consistency.
- **CHORE**: Update `tracelet_platform_interface` constraint to `^2.0.1`.

## 2.0.0

- **CHORE**: Global version synchronization for the Tracelet 2.0.0 release.
- **CHORE**: Update `tracelet_platform_interface` constraint to `^2.0.0`.

## 1.9.3
2: 
3: - **CHORE**: Version bump for monorepo consistency and native SDK alignment.
4: 
5: ## 1.9.2

- **CHORE**: Constraint bump to `tracelet_platform_interface` 1.9.2. No web-side changes.

## 1.9.1

- **CHORE**: Constraint bump to `tracelet_platform_interface` 1.9.1. No web-side changes.

## 1.9.0

- **CHORE**: Constraint bump to `tracelet_platform_interface` 1.9.0 (#58 fix). No web-side changes.

## 1.8.13

- **CHORE**: Version bump for first-fix latency improvement in `tracelet_android` and `tracelet_ios` (#54).

## 1.8.12

- **CHORE**: Version bump for geofence/location `extras` round-trip fix in `tracelet_android` (#51 follow-up).

## 1.8.11

- **FIX**: Version bump for secondary FlutterEngine guard fix in `tracelet_android` and `tracelet_ios` (#51).

## 1.8.10

- **FIX**: Version bump for killed-state tracking fix in `tracelet_android` (#50).

## 1.8.9

- **CHORE**: Version bump for `syncInterval` feature (#50).

## 1.8.8

- **CHORE**: Version bump for HTTP sync payload consistency fix (#48).

## 1.8.7

- **CHORE**: Align federated package versions and include additional patch updates.

## 1.8.6

- **CHORE**: Version bump for HTTP sync headers fix.

## 1.8.5

- **CHORE**: Version bump for `getCurrentPosition` fallback fix (#46).

## 1.8.4

- **CHORE**: Version bump for Android pre-ready guard fixes and strict native SDK pinning.

## 1.8.3

- **CHORE**: Version bump for iOS pre-ready guard fixes.

## 1.8.2

- **CHORE**: Version bump for Android/iOS stability fixes.

## 1.8.1

- **CHORE**: Version bump for iOS periodic mode location indicator fix.

## 1.8.0

- **FEAT**: Add `destroySyncedLocations()` web implementation.

## 1.7.1

- **FEAT**: Add `destroySyncedLocations()` web implementation.

## 1.7.0

- **CHORE**: Update cross-package dependency constraints to `^1.7.0`.

## 1.6.3-alpha.1

- **CHORE**: Update cross-package dependency constraints to `^1.6.3-alpha.1`.

## 1.6.1

- **FIX**: Add 5 missing HTTP Sync method overrides (`setDynamicHeaders`, `setRouteContext`, `clearRouteContext`, `registerHeadlessHeadersCallback`, `registerHeadlessSyncBodyBuilder`) that previously threw `UnimplementedError` at runtime.
- **FEAT**: `WebHttpEngine` now supports dynamic headers and route context in HTTP requests.
- **TEST**: Add platform interface coverage test to prevent future method stub regressions.

## 1.6.0

- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.6.0`.

## 1.5.0

- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.5.0`.

## 1.4.6

- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.6`.

## 1.4.5

- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.5`.

## 1.4.4

- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.4`.

## 1.4.3

- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.3`.

## 1.4.2

- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.2`.

## 1.4.1

- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.1`.

## 1.4.0

- **FEAT**: Add stub implementations for enterprise methods: `isDatabaseEncrypted()`, `encryptDatabase()`, `getAttestationToken()`, `getDeadReckoningState()`, `getCarbonReport()`.
- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.0`.

## 1.3.6

- **FIX**: `getCount()` now supports time-range filtering via optional `SQLQuery` parameter.
- **FIX**: Fix `getLocations()` timestamp filtering — `start`/`end` were incorrectly cast as `String?` instead of `int?` (millisecondsSinceEpoch).
- **CHORE**: Update cross-package dependency constraints to `^1.3.6`.

## 1.3.5

- **CHORE**: Update cross-package dependency constraints to `^1.3.5`.

## 1.3.4

- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.3.3`.

## 1.3.3

- **CHORE**: Patch bump for federation consistency with `tracelet` 1.3.3.

## 1.3.2

- **CHORE**: Patch bump for federation consistency with `tracelet` 1.3.2.

## 1.3.1

- **CHORE**: Patch bump for federation consistency with `tracelet` 1.3.1.

## 1.3.0

- **CHORE**: Version bump for federation consistency with `tracelet` 1.3.0.

## 1.2.0

- **CHORE**: Version bump for federation consistency with `tracelet_platform_interface` 1.2.0 (new `NotificationPriority` and `HashAlgorithm` enums).

## 1.1.0

### New Features

- **FEAT**: `WebHttpEngine` now supports delta-compressed batch uploads — conditionally applies `DeltaEncoder.encode()` when `enableDeltaCompression` is true and batch size > 1, achieving 60–80% payload reduction for high-frequency tracking scenarios. Reads `enableDeltaCompression` (bool) and `deltaCoordinatePrecision` (int, default 6) from HTTP config.
- **FEAT**: `WebHttpEngine` supports `disableAutoSyncOnCellular` — guards auto-sync on cellular networks via the Network Information API (where available), syncing only on WiFi connections.

## 1.0.1

- **FIX**: HTTP auto-sync now triggers after `insertLocation()` and `getCurrentPosition(persist: true)` — previously auto-sync was never invoked on web ([#21](https://github.com/Ikolvi/Tracelet/issues/21)).
- **FEAT**: `WebHttpEngine` now parses `autoSync`, `autoSyncThreshold`, and `disableAutoSyncOnCellular` from config.

## 1.0.0

### 🎉 Stable Release

- **FEAT**: First stable release of `tracelet_web`.
- **REFACTOR**: Remove third-party company name references.
- All Web APIs are finalized and production-ready.

## 0.12.0

### Performance Audit — Web optimizations

- **PERF**: Hoist `math.Random()` to top-level constant in `generateUuid()` (D-M1).
- **PERF**: Use lazy `Iterable` chaining in `getLocations()`, materialize only once (D-M3).
- **PERF**: Promote browser version `RegExp` patterns to `static final` (D-M5).
- **PERF**: Cache `.toJS` references for web event listeners (D-H6).
- **PERF**: Cache polygon vertices at `addGeofence` time (D-H5).

## 0.11.4

- **CHORE**: Version bump for platform consistency.

## 0.11.3

- **CHORE**: Version bump for platform consistency.

## 0.11.2

- **FIX**: Fix LICENSE file formatting so pana correctly detects Apache-2.0.
- **DOCS**: Add `example/example.dart` for pub.dev documentation score.
- **CHORE**: Tighten `tracelet_platform_interface` constraint to `^0.11.2`.

## 0.11.1

- **FEAT**: Add `canScheduleExactAlarms()` (returns `true`) and `openExactAlarmSettings()` (returns `false`) stub implementations.
- **CHORE**: Bump platform interface to 0.11.1.

## 0.11.0

- **FEAT**: Stub implementations for privacy zone and audit trail methods (no-op on web).
- **CHORE**: Bump `tracelet_platform_interface` to ^0.11.0.

## 0.10.0

- **FEAT**: `startPeriodic()` — falls back to `watchPosition()` on web (periodic scheduling not available in browsers).
- **CHORE**: Bump `tracelet_platform_interface` to ^0.10.0.

## 0.9.1

- **CHORE**: Version bump for consistency.

## 0.9.0

* **CHORE**: Version bump for adaptive sampling, health check, and motion sensitivity release.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.9.0.

## 0.8.3

* **CHORE**: Version bump for proximity-based geofence monitoring release.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.8.3.

## 0.8.2

* **DOCS**: Improve README visuals with combined Android & iOS demo image.

## 0.8.1

* **FIX**: Fix `_bridgedController` dropping all EventChannel events — `onLocation`, `onMotionChange`, `onHeartbeat`, `onGeofence`, and all other event streams were broken on web (events consumed but never forwarded to Dart). Now properly pipes data via `controller.add()`.
* **FIX**: `WebEventDispatcher.log()` was a no-op — now prints to browser console for debugging visibility.
* **FEAT**: Diagnostic logging in `WebLocationEngine.getCurrentPosition()` and `_browserGetPosition()` — logs request parameters, success/error callbacks, and `_positionToMap` errors to the browser console.

## 0.8.0

* **FEAT**: OEM compatibility stubs — `getSettingsHealth()` returns `isAggressiveOem: false` (no OEM power management on web), `openOemSettings()` returns `false`.
* **DOCS**: Update README with OEM compatibility stub in feature table.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.8.0.

## 0.7.1

* **DOCS**: Add mock detection passthrough note to README feature table.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.7.1.

## 0.7.0

* **FEAT**: `_positionToMap()` and `_emptyLocation()` now include `mock: false` field — browser Geolocation API has no mock detection capability.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.7.0.

## 0.6.1

* **FIX**: Remove duplicate distance filter from `WebLocationEngine` — all location filtering now handled by shared Dart `LocationProcessor` via `tracelet.dart` pipeline, matching Android/iOS behavior.
* **REFACTOR**: Replace duplicate `_haversine()` in `WebLocationEngine` with shared `GeoUtils.haversine()`.
* **REFACTOR**: Deduplicate UUID generators into shared `web_utils.dart` (`generateUuid()`).
* **REFACTOR**: Remove dead internal logging from `WebEventDispatcher` (`_logs`, `getLog()`, `clearLog()`).
* **CHORE**: Bump `tracelet_platform_interface` to ^0.6.1.

## 0.6.0

* **CHORE**: Bump `tracelet_platform_interface` to ^0.6.0. Inherits shared Dart algorithm improvements.

## 0.5.5

* **CHORE**: Bump `tracelet_platform_interface` to ^0.5.5.

## 0.5.4

* **CHORE**: Bump `tracelet_platform_interface` to ^0.5.4.

## 0.5.3

* **CHORE**: Bump `tracelet_platform_interface` to ^0.5.3.

## 0.5.2

* **FIX**: Replace deprecated `registrar.messenger` with `registrar` directly in event channel registration.
* **CHORE**: Bump version to 0.5.2.

## 0.5.1

* **DOCS**: Update README with usage instructions, compatibility table, and related packages.
* **FIX**: Add `.gitignore` to exclude `build/` directory from publish.
* **FIX**: Add `flutter` environment constraint to `pubspec.yaml`.

## 0.5.0

* **FEAT**: Initial web platform release.
* **FEAT**: Foreground-only location tracking via Web Geolocation API.
* **FEAT**: Geofence emulation (distance-based enter/exit/dwell detection).
* **FEAT**: In-memory persistence for locations and logs.
* **FEAT**: HTTP sync via browser `fetch()` API.
* **FEAT**: Permission queries via `navigator.permissions`.
* **FEAT**: Connectivity monitoring via `online`/`offline` events.
* **FEAT**: Auto-fallback from high to low accuracy on timeout.
* **DOCS**: Add comprehensive Web Support guide (`help/WEB-SUPPORT.md`).

## 0.4.0

- Initial web implementation (pre-release).
- Connectivity detection via `navigator.onLine`.
- Stub implementations for platform-specific APIs (background tasks, settings, etc.).