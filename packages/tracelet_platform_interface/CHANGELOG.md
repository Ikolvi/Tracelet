## 3.8.8

**FEAT**: `TlCurrentPositionOptions` carries `accuracyTarget` and `requestId`, and the host API exposes `cancelCurrentPosition`.

**FEAT**: `TripManager` surfaces the trip-start edge and `currentTripId` from the Rust core, and passes `tripId`, `startedAt`, and `endedAt` through to the trip maps ([#402](https://github.com/Ikolvi/Tracelet/issues/402)).

## 3.8.7

Version alignment with tracelet 3.8.7.

## 3.8.6

Version alignment with tracelet 3.8.6.

## 3.8.5

Version alignment with tracelet 3.8.5.

## 3.8.4

**FEAT**: `TlForegroundServiceConfig` carries `notificationStartedAt`, `notificationShowTimer` and `notificationOnlyAlertOnce`, and `TlLiveActivityConfig` carries `startedAt` and `showTimer`, for the OS-rendered elapsed timer. The fields are appended at the end of each Pigeon class and the generated decoders read those indices unconditionally, so a native package must resolve against this interface version or newer — the platform packages' constraints move with this release ([#376](https://github.com/Ikolvi/Tracelet/issues/376)).

**FIX**: the method-channel fallback sends `liveActivityConfig`. `_iosToMap` never wrote the key, so a platform implementation on that path saw no Live Activity configuration at all — timer fields or otherwise ([#376](https://github.com/Ikolvi/Tracelet/issues/376)).

## 3.8.3

**FEAT**: `TlTelematicsRecord` carries `speed` and `value`. Both are nullable, so a Dart side newer than the native plugin decodes a missing field as `null` rather than failing. `severity` is unchanged ([#367](https://github.com/Ikolvi/Tracelet/issues/367)).

## 3.8.2

Version alignment with tracelet 3.8.2.

## 3.8.1

Version alignment with tracelet 3.8.1.

## 3.8.0

**FIX**: every leaf `Tl*Config` field is nullable, so "the caller did not set this" survives the channel and the platform can leave the persisted value alone instead of overwriting it with a default. The method-channel and web transports omit unset fields rather than sending them as explicit nulls or resolved defaults ([#321](https://github.com/Ikolvi/Tracelet/issues/321)).

**FIX**: `TlForegroundServiceConfig` fields are nullable, so "the caller did not set this" survives the channel and the platform can leave the persisted value alone instead of overwriting it with a default ([#320](https://github.com/Ikolvi/Tracelet/issues/320)).

**FIX**: the method-channel path serialised no `showNotificationOnPauseOnly` at all, so the flag never reached the platform over that transport however it was configured — the same class of silent drop as the geofence flag in [#305](https://github.com/Ikolvi/Tracelet/issues/305). It is now sent, and the whole foreground-service map omits fields the caller left unset ([#320](https://github.com/Ikolvi/Tracelet/issues/320)).

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

**FIX**: `TlMotionConfig.shakeThreshold`, `stillThreshold` and `stillSampleCount` are now nullable, so "unset" can be expressed across the platform channel. They were required, which meant Dart's defaults (the Android-tuned values) were transmitted unconditionally and silently overrode each platform's own tuned defaults — on iOS `stillThreshold: 0.4 m/s²` arrived as `0.04 g`, about four times stricter than the `0.15 g` iOS default. `null` now means "use the platform default"; the Pigeon bindings were regenerated from the schema ([#288](https://github.com/Ikolvi/Tracelet/issues/288)).

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

 - **FEAT**(geofence): cross-platform geofenceModeHighAccuracy via GeofenceConfig. ([491d5b83](https://github.com/Ikolvi/Tracelet/commit/491d5b836fbd98a2e456d7d07bafc500f95a2fac))
 - **DOCS**: update FAQ with iOS build setup and geofencing mock location testing details. ([063145fe](https://github.com/Ikolvi/Tracelet/commit/063145fe80e1285f876568fa7c81caad8b5ee7d2))

## 3.4.0

 - **FIX**: forward `desiredAccuracy` and per-call `extras` through the pigeon options conversion — they were silently dropped, so `getCurrentPosition(extras:/desiredAccuracy:)` never reached native ([#201](https://github.com/Ikolvi/Tracelet/issues/201)).
 - **REFACTOR**: extract issues 185 and 198, fix iOS config mapping. ([1d088e0d](https://github.com/Ikolvi/Tracelet/commit/1d088e0d58e863b11217c5040410381f91930e59))

## 3.3.4

**CHORE**: bump version.

## 3.3.3

 - **FIX**: Correct the pigeon mock stub for `TlGeofenceConfig` to accommodate removed fields and update config tests. ([065b3bbc](https://github.com/Ikolvi/Tracelet/commit/065b3bbc631a367364eba2b666c54120174530cc))
 - **FIX**(android): deliver headless geofence events after reboot in high-accuracy mode ([#185](https://github.com/Ikolvi/Tracelet/issues/185)). ([b197dc5f](https://github.com/Ikolvi/Tracelet/commit/b197dc5f0e4b5f081590e806b27a6eb52a4ed253))

## 3.3.2

* **FIX** (Location data, Android/iOS): Several location-map fields surfaced as static/default values in the Dart layer because the native-map → platform-channel converters dropped or mis-keyed them ([#175](https://github.com/Ikolvi/Tracelet/issues/175)):
  * `getCurrentPosition(extras:, desiredAccuracy:)` were silently ignored on Android (never forwarded to the SDK) — now applied.
  * `battery.isCharging` was always `false` — the converter read `isCharging` instead of the native snake_case `is_charging`.
  * `isMoving` was always `false` — read `isMoving` instead of native `is_moving`.

  Converters now read the native keys (with camelCase fallback), and field-by-field regression tests over the converters were added on both platforms to prevent recurrence.
* **TUNE** (Crash detection): Lowered the default `crashGThreshold` from `3.0 g` to `2.0 g`. Validation against the large [VZCrash](https://huggingface.co/datasets/vzc-research-chapter/VZCrash) field dataset showed the 3.0 g speed-gated rule missed ~48% of real crashes (median impact ~2.2 g) while the false-positive budget was small. Crash detection is opt-in with a cancel-countdown, so the default now favours recall — raise it if you see too many prompts. See [#173](https://github.com/Ikolvi/Tracelet/issues/173). *(Crash detection remains beta pending first-party field validation.)*

## 3.3.1

* **FIX** (Crash detection, Android/iOS): Confirmed `crash`/`fall` events are no longer lost when tracking stops right after the impact (the common crash → vehicle-at-rest → `stopTimeout` case). The confirmation countdown now runs independently of tracking state and self-terminates when no candidate is pending ([#169](https://github.com/Ikolvi/Tracelet/issues/169)).
* **FIX** (Crash detection): The effective crash g-threshold matched the documented value — the confidence gate previously raised a 3.0 g threshold to ~3.6 g, increasing false negatives ([#170](https://github.com/Ikolvi/Tracelet/issues/170)).
* **FIX** (Crash detection): A single crash (primary spike + bounce/secondary impacts) no longer raises multiple candidates; a refractory period debounces one event into one prompt ([#171](https://github.com/Ikolvi/Tracelet/issues/171)).
* **IMPROVE** (Crash detection, Android/iOS): When crash/fall detection is enabled, the accelerometer is sampled at a higher rate (Android `SENSOR_DELAY_GAME` + no batch latency; iOS 100 Hz) so short impact peaks (~50–150 ms) are actually captured instead of missed between motion-detection samples ([#172](https://github.com/Ikolvi/Tracelet/issues/172)). Roadmap for research-grade robustness (Δv, sensor fusion, free-fall signature, process-death survival): [#173](https://github.com/Ikolvi/Tracelet/issues/173).

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

 - **FIX**: streamline geofence event payload handling in fromMap method.
 - **FIX**: ensure geofence action (ENTER/EXIT/DWELL) is correctly parsed from nested payloads on all platforms and update CI to scan dynamic frameworks for symbols.


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

- **FIX**(web): safe BigInt to int casting for rust bridge 64-bit integers.
- **FEAT**: Add reverse geocoding functionality (`resolveAddress`).

## 3.1.14

- **CHORE**: Sync release versions across workspace.


## 3.1.10

 - Bump "tracelet_platform_interface" to `3.1.10`.

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

- **FEAT**: Massive Architecture Rewrite — Core algorithms are now powered by a high-performance **Rust Core** using `flutter_rust_bridge`.
- **FEAT**: Smart Motion Mode — Introduced `MotionDetectionMode.smart` powered by the Rust battery budget engine.
- **FEAT**: Migrated all platform event channels to use strongly-typed Pigeon bridges.

## 2.1.0

 - **FIX**: resolve background tracking loops, location stream drops, and permission issues. ([8abc7d41](https://github.com/Ikolvi/Tracelet/commit/8abc7d415b742a1aee7da50e16763babd83f9e53))
 - **FIX**: refactor speed motion strings to typed enums across Flutter, Pigeon, Android, and iOS SDKs. ([e974b728](https://github.com/Ikolvi/Tracelet/commit/e974b728142eb7b31b887a3b795cd527da6cbae1))
 - **FEAT**(android): smart foreground notification visibility. ([fbf46b27](https://github.com/Ikolvi/Tracelet/commit/fbf46b27d401828e1c79fd1853.1.4046aaf3f72))
 - **FEAT**: Speed-Based Motion Detection ([#83](https://github.com/Ikolvi/Tracelet/issues/83)). ([5421e7a0](https://github.com/Ikolvi/Tracelet/commit/5421e7a0974033ede6ee5234c641d9bb68cd4460))

## 2.0.8

- **CHORE**: Version bump for monorepo consistency and package lockstep alignment.

## 2.0.7

- **CHORE**: Version bump for monorepo consistency and package lockstep alignment.

## 2.0.6

- **CHORE**: Version bump for monorepo consistency and package lockstep alignment.

## 2.0.5

- **CHORE**: Version bump for monorepo consistency and package lockstep alignment.

## 2.0.4

- **CHORE**: Version bump for monorepo consistency and native SDK alignment.

## 2.0.3

- **FIX**: Removed unreliable timestamp drift heuristic from location spoofing detection.

## 2.0.1

- **CHORE**: Version bump for iOS status bar fix consistency.

## 2.0.0

- **BREAKING**: Migrated all platform communication to Pigeon for strictly-typed host and flutter APIs.
- **BREAKING**: Refactored `Config` into a nested compound model (`GeoConfig`, `AppConfig`, `AndroidConfig`, `HttpConfig`, `LoggerConfig`, `MotionConfig`, `GeofenceConfig`, `SecurityConfig`).
- **FEAT**: Added `shakeThreshold`, `stillThreshold`, and `stillSampleCount` to `TlMotionConfig` Pigeon model for granular motion sensitivity tuning.
- **BREAKING**: Prefixed internal platform interface enums with `Tl` (e.g., `TlAuthorizationStatus`, `TlTrackingMode`) to avoid naming collisions while maintaining stable public-facing Dart enums.
- **FEAT**: Added comprehensive support for optional native dependencies (GMS, SQLCipher) via graceful degradation in the platform layer.

## 1.9.3
2: 
3: - **CHORE**: Version bump for monorepo consistency and native SDK alignment.
4: 
5: ## 1.9.2

- **CHORE**: Constraint bump for `tracelet` 1.9.2 release. No interface changes.

## 1.9.1

- **CHORE**: Constraint bump for `tracelet` 1.9.1 release. No interface changes.

## 1.9.0

- **FIX**: `_mapToGeofence` was silently dropping `extras` and `vertices` when converting the Dart map into the Pigeon `TlGeofence`, so they never reached native and were persisted as `null` (#58). Both fields now round-trip from `Geofence.toMap()` through the platform channel intact. The earlier 1.8.12 patch only addressed the Android read path; the actual data loss was one layer up at the federated platform-interface layer and affected both Android and iOS.
- **CHORE**: Constraint bump for `tracelet` 1.9.0 typed permission API additions (#57). No interface changes — the int-based platform-interface methods are unchanged.
- **TEST**: Added unit test in `pigeon_tracelet_test.dart` asserting `extras` and `vertices` reach `TraceletHostApi.addGeofence`.

## 1.8.13

- **CHORE**: Version bump for first-fix latency improvement in `tracelet_android` and `tracelet_ios` (#54). No interface changes.

## 1.8.12

- **CHORE**: Version bump for geofence/location `extras` round-trip fix in `tracelet_android` (#51 follow-up).

## 1.8.11

- **FIX**: Version bump for secondary FlutterEngine guard fix in `tracelet_android` and `tracelet_ios` (#51).

## 1.8.10

- **FIX**: Version bump for killed-state tracking fix in `tracelet_android` (#50).

## 1.8.9

- **FEAT**: Add `syncInterval` field to `HttpConfig` for fixed-cadence HTTP sync (#50).

## 1.8.8

- **CHORE**: Version bump for HTTP sync payload consistency fix (#48).

## 1.8.7

- **CHORE**: Align federated package versions and include additional patch updates.

## 1.8.6

- **CHORE**: Version bump for HTTP sync headers fix.
- **FIX**: Fix Pigeon-generated `getPrivacyZones()` lazy `.cast<Map<String, Object?>>()` — eagerly deep-cast each map to prevent `_Map<Object?, Object?>` type error at runtime.

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

- **FEAT**: Add `destroySyncedLocations()` Pigeon HostApi method — deletes only synced locations and returns count.
- **FIX**: Align location map format contract across all platforms (camelCase accuracy keys, nested `coords` map).

## 1.7.1

- **FEAT**: Add `destroySyncedLocations()` Pigeon HostApi method — deletes only synced locations and returns count.

## 1.7.0

- **FEAT**: Migrate all event delivery from EventChannels to Pigeon `TraceletEventApi` FlutterApi.
- **FEAT**: Add `PigeonEventReceiver` with 15 broadcast StreamControllers for type-safe native→Dart event routing.
- **FEAT**: Add `PigeonTracelet` platform implementation wrapping Pigeon HostApi + FlutterApi.
- **REFACTOR**: Extract native SDK to standalone `sdk/android` (Maven Central) and `sdk/ios` (CocoaPods/SPM) modules.

## 1.6.3-alpha.1

- **FEAT**: Add `TraceletEventApi` Pigeon FlutterApi with 15 event methods replacing EventChannels.
- **FEAT**: Add `PigeonEventReceiver` with 15 broadcast StreamControllers for type-safe native→Dart event routing.
- **FEAT**: Add `PigeonTracelet` platform implementation wrapping Pigeon HostApi + FlutterApi.
- **FEAT**: Add 15 event stream getters to `TraceletPlatform` interface.
- **CHORE**: Update cross-package dependency constraints to `^1.6.3-alpha.1`.

## 1.6.0

- **FEAT**: Add `setDynamicHeaders`, `setRouteContext`, `clearRouteContext`, `registerHeadlessHeadersCallback`, and `registerHeadlessSyncBodyBuilder` platform methods.
- **CHORE**: Update cross-package dependency constraints to `^1.6.0`.

## 1.5.0

- **CHORE**: Update cross-package dependency constraints to `^1.5.0`.

## 1.4.6

- **CHORE**: Update cross-package dependency constraints to `^1.4.6`.

## 1.4.5

- **CHORE**: Update cross-package dependency constraints to `^1.4.5`.

## 1.4.4

- **CHORE**: Update cross-package dependency constraints to `^1.4.4`.

## 1.4.3

- **CHORE**: Update cross-package dependency constraints to `^1.4.3`.

## 1.4.2

- **CHORE**: Update cross-package dependency constraints to `^1.4.2`.

## 1.4.1

- **CHORE**: Update cross-package dependency constraints to `^1.4.1`.

## 1.4.0

- **FEAT**: Add `isDatabaseEncrypted()` and `encryptDatabase()` platform methods for encrypted SQLite support.
- **FEAT**: Add `getAttestationToken()` platform method for device attestation (Play Integrity / App Attest).
- **FEAT**: Add `getDeadReckoningState()` platform method for dead reckoning position estimation.
- **FEAT**: Add `getCarbonReport()` platform method for carbon emission estimation from tracked journeys.
- **CHORE**: Update cross-package dependency constraints to `^1.4.0`.

## 1.3.6

- **FIX**: Add `offset` field to `SQLQuery` to match native platform handlers that read it.
- **PERF**: Optimize `DeltaEncoder` — 2.1x faster encode via cached DateTime parsing and precomputed rounding factors.
- **PERF**: Optimize `GeoUtils.haversine` — eliminate redundant `sqrt`, precompute `pi/180`, inline `_toRad`.
- **DOCS**: Clarify `getCount()` ignores `limit`/`offset`/`order` from `SQLQuery`.

## 1.3.5

- **CHORE**: Update cross-package dependency constraints to `^1.3.5`.

## 1.3.4

- **CHORE**: Patch bump for federation consistency with `tracelet` 1.3.4.

## 1.3.3

- **CHORE**: Patch bump for federation consistency with `tracelet` 1.3.3.

## 1.3.2

- **CHORE**: Patch bump for federation consistency with `tracelet` 1.3.2.

## 1.3.1

- **CHORE**: Patch bump for federation consistency with `tracelet` 1.3.1.

## 1.3.0

- **CHORE**: Version bump for federation consistency with `tracelet` 1.3.0.

## 1.2.0

### New Enums

- **FEAT**: Add `NotificationPriority` enum — `min`, `low`, `defaultPriority`, `high`, `max` — replacing raw `int` for Android foreground notification priority.
- **FEAT**: Add `HashAlgorithm` enum — `sha256`, `sha384`, `sha512` — replacing `String` for audit trail hash algorithm configuration.

## 1.1.0

### New Algorithms

- **FEAT**: Add `BatteryBudgetEngine` — a pure-Dart feedback control loop that automatically adjusts `distanceFilter`, `desiredAccuracy`, and periodic interval to stay within a configurable battery budget (% drain/hour). Compares measured drain against target every 5 minutes; if over budget, increases distance filter (up to 1000 m) and degrades accuracy (high → medium → low → veryLow → passive); if under budget, tightens distance filter (down to 10 m) and improves accuracy. Includes `BudgetAdjustmentEvent` with `currentBatteryDrain`, `targetBudget`, `newDistanceFilter`, `newDesiredAccuracy`, and optional `newPeriodicInterval`.
- **FEAT**: Add `CarbonEstimator` — per-trip and cumulative CO₂ emission calculator using mode-specific emission factors (gCO₂/km). Default factors use EU EEA 2024 averages: car = 192, bus = 89, train = 41, walking/cycling = 0. Accepts GPS coordinates + activity type from activity recognition, accumulates distance per mode via Haversine, and provides structured `TripCarbonSummary` with `totalCarbonGrams`, `totalDistanceMeters`, `carbonByMode`, `distanceByMode`, and `dominantMode`. Tracks cumulative totals across multiple trips for fleet/compliance reporting.
- **FEAT**: Add `DeltaEncoder` — batch location compression codec using delta encoding. First location in a batch is transmitted in full (marked `ref: true`); subsequent positions sent as deltas with shortened field names (`la` = Δlatitude, `lo` = Δlongitude, `t` = Δtime in seconds, `s` = Δspeed, `h` = Δheading with shortest-arc normalization, `a` = Δaccuracy, `al` = Δaltitude, `b` = Δbattery). Coordinate precision configurable (5 = ~1.1 m, 6 = ~0.11 m). Symmetric `encode()`/`decode()` for bidirectional use. Achieves 60–80% payload reduction for high-frequency tracking batches.
- **FEAT**: Add `RTree<T>` — generic R-tree spatial index enabling O(log n) geofence proximity queries versus O(n) linear search. Supports `insert(lat, lng, radius, data)`, `remove(data)`, `queryCircle(lat, lng, radiusMeters)`, and `queryBBox(minLat, minLng, maxLat, maxLng)`. Uses quadratic split strategy, latitude-corrected degree-to-meter bbox conversion, and Haversine post-filtering for accurate circle queries. Handles 10,000+ geofences with sub-millisecond lookup times.

### Changes

- **FEAT**: Export `BatteryBudgetEngine`, `BudgetAdjustmentEvent`, `CarbonEstimator`, `TripCarbonSummary`, `DeltaEncoder`, and `RTree` from the `algorithms.dart` barrel file.
- **REFACTOR**: Update `GeofenceEvaluator` and `LocationProcessor` for improved algorithm integration with new sparse updates and dead reckoning configuration.

## 1.0.0

### 🎉 Stable Release

- **FEAT**: First stable release of `tracelet_platform_interface`.
- **REFACTOR**: Remove third-party company name references — use generic `flutter_background_geolocation` throughout.
- All APIs are finalized and production-ready.

## 0.12.0

### Performance Audit — Dart algorithm optimizations

- **PERF**: Use `Float64List` for Kalman filter state matrices, add `_pTemp` scratch buffer (D-C3).
- **PERF**: In-place `_p.fillRange()` in `Kalman.reset()` instead of re-allocating (D-M7).
- **PERF**: Bound `TripManager` waypoints list to 5000 entries (D-H3).
- **PERF**: Use `Queue<Map>` with O(1) `removeFirst()` instead of `List.removeAt(0)` O(n) for waypoint cap trimming (D-L2).
- **PERF**: Merge isPointInPolygon precondition check into main loop — validates each vertex inline (D-M2).
- **PERF**: Cache `_cachedInsideView` in `GeofenceEvaluator` with invalidation at all 6 mutation points (D-M4).
- **PERF**: Remove dead `num` branch in `_toDouble()` — `int`/`double` already cover all `num` subtypes (D-L1).
- **REFACTOR**: `matchesSchedule()` now delegates to `parse()` to eliminate duplicated parsing logic (D-L3).

## 0.11.4

- **CHORE**: Version bump for platform consistency.

## 0.11.3

- **CHORE**: Version bump for platform consistency.

## 0.11.2

- **DOCS**: Fix unresolved dartdoc references (`[GeoConfig]`, `[GeoConfig.periodicLocationInterval]`).
- **DOCS**: Add `example/example.dart` for pub.dev documentation score.

## 0.11.1

- **FEAT**: Add `canScheduleExactAlarms()` and `openExactAlarmSettings()` abstract methods to `TraceletPlatform` and MethodChannel implementations.

## 0.11.0

- **FEAT**: Add privacy zone abstract methods to `TraceletPlatform` and MethodChannel implementations.
- **FEAT**: Add audit trail abstract methods to `TraceletPlatform` and MethodChannel implementations.

## 0.10.0

- **FEAT**: Add `TrackingMode.periodic` enum value for periodic interval tracking.
- **FEAT**: Add `startPeriodic()` method to `TraceletPlatform` and `MethodChannelTracelet`.

## 0.9.1

- **CHORE**: Version bump for consistency.

## 0.9.0

* **FEAT**: `AdaptiveSamplingEngine` — multi-factor distance filter computation (activity type, battery level, charging state, speed). 33 unit tests.
* **FEAT**: `HealthCheck` model with `HealthWarning` enum (12 warning types) and `HealthWarningDescription` extension.
* **FEAT**: `LocationProcessor` integration with adaptive sampling via `AdaptiveContext`.

## 0.8.3

* **CHORE**: Version bump for proximity-based geofence monitoring release.

## 0.8.2

* **DOCS**: Improve README visuals with combined Android & iOS demo image.

## 0.8.1

* **DOCS**: Document iOS background hardening and session manager support in README.

## 0.8.0

* **FEAT**: `getSettingsHealth()` abstract method — OEM settings health check returning manufacturer, aggression rating, battery optimization status, and available OEM settings screens.
* **FEAT**: `openOemSettings(String label)` abstract method — open OEM-specific settings screens by label.
* **FEAT**: `MethodChannelTracelet` implementations for both new OEM methods.
* **DOCS**: Update README with OEM Compatibility API reference.

## 0.7.1

* **DOCS**: Update README with shared Dart algorithms description and mock detection reference.

## 0.7.0

* **FEAT**: `MockDetectionLevel` enum — `disabled`, `basic`, `heuristic` detection depth for mock/spoofed GPS.
* **FEAT**: `LocationProcessor` mock location filter — rejects locations with `isMock: true` when `rejectMockLocations` is enabled.
* **FEAT**: `LocationProcessor` timestamp monotonicity check — detects backward timestamps as heuristic spoof indicator (level ≥ 2).
* **FEAT**: `LocationProcessor.mockDetectionLevel` field + `copyWith()` support.

## 0.6.1

* **REFACTOR**: Remove dead `TraceletEvents.trip` constant and `TraceletEvents.all` list — trip events now produced by Dart `TripManager`.
* **REFACTOR**: `TripManager` now uses `GeoUtils.haversine()` instead of duplicate private `_haversine()` implementation.

## 0.6.0

* **FEAT**: `LocationProcessor` — shared Dart implementation of distance filtering, elasticity, accuracy filtering (adjust/ignore/discard), speed filtering, and odometer gating. Replaces duplicate native Kotlin/Swift code.
* **FEAT**: `GeofenceEvaluator` — shared Dart high-accuracy geofence proximity evaluation for circular and polygon geofences with ENTER/EXIT state tracking.
* **FEAT**: `ScheduleParser` — shared Dart schedule string parsing, window matching, and alarm calculation for cross-platform scheduling.
* **FEAT**: `PersistDecider` — shared Dart persistence decision logic based on `PersistMode`.
* **FEAT**: Export all 7 algorithm classes via `algorithms.dart` barrel file (GeoUtils, KalmanLocationFilter, TripManager, LocationProcessor, GeofenceEvaluator, ScheduleParser, PersistDecider).
* **CHORE**: 46 new unit tests across 4 test files (86 total algorithm tests).

## 0.5.5

* **CHORE**: Bump version to 0.5.5.

## 0.5.4

* **CHORE**: Bump version to 0.5.4.

## 0.5.3

* **CHORE**: Bump version to 0.5.3.

## 0.5.2

* **CHORE**: Bump version to 0.5.2.

## 0.5.1

* **DOCS**: Update README with links to all federated packages.

## 0.5.0

* **FEAT**: Web platform support.
* **CHORE**: Bump version to 0.5.0.

## 0.4.0

* **FEAT**: Add `getMotionPermissionStatus()` and `requestMotionPermission()` to platform interface.
* **CHORE**: Format all Dart files.

## 0.3.0

* **FEAT**: Add `getLastKnownLocation()` abstract method to platform interface.
* **FEAT**: Add `ForegroundServiceConfig.enabled` field to `AppConfig` for toggling foreground service.
* **FEAT**: Enhance `getCurrentPosition()` with `persist`, `samples`, `maximumAge`, and `extras` parameters for enterprise one-shot location requests.

## 0.2.2

* Fix LICENSE file format for proper SPDX detection on pub.dev.

## 0.2.1

* Bump Pigeon dependency from ^22.7.0 to ^26.1.7.

## 0.2.0

* Add SPDX `license: Apache-2.0` identifier for pub.dev scoring.

## 0.1.0

* Initial release.
* Abstract platform interface with 38 methods.
* Pigeon-generated type-safe communication layer.
* 13 enum types for location, activity, geofence, and HTTP configuration.
* EventChannel definitions for 14 real-time event streams.