## 3.8.8

Version alignment with tracelet 3.8.8.

## 3.8.7

Version alignment with tracelet 3.8.7.

## 3.8.6

Version alignment with tracelet 3.8.6.

## 3.8.5

Version alignment with tracelet 3.8.5.

## 3.8.4

Version alignment with tracelet 3.8.4.

## 3.8.3

Version alignment with tracelet 3.8.3.

## 3.8.2

Version alignment with tracelet 3.8.2.

## 3.8.1

Version alignment with tracelet 3.8.1.

## 3.8.0

Version alignment with tracelet 3.8.0.

## 3.8.0-beta.2

Version alignment with tracelet 3.8.0-beta.2.

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

 - Update a dependency to the latest release.

## 3.4.1

 - Update a dependency to the latest release.

## 3.4.0

 - Update a dependency to the latest release.

## 3.3.4

**CHORE**: bump version.

## 3.3.3

 - Update a dependency to the latest release.

## 3.3.2

 - Update a dependency to the latest release.

## 3.3.1

 - Update a dependency to the latest release.

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

 - **DOCS**: integrate nextra website and update pubspec URLs. ([99b7fda8](https://github.com/Ikolvi/Tracelet/commit/99b7fda82e290ca6c8175313eae62a2475360050))

## 3.2.13

- **CHORE**: Version bump to 3.2.13 to stay in lockstep with the federated set (Android `startOnBoot` reboot-tracking fix — see `tracelet_android`). No changes to this package.

## 3.2.12

- **CHORE**: Re-release to align the full federated package set and native SDKs to a single consistent version. The 3.2.11 release published with mismatched versions across some packages (a few resolved to 3.2.10). No functional code changes.

## 3.2.11

- **CHORE**: Version bump to align with 3.2.11 platform release.

## 3.2.10

 - Update a dependency to the latest release.

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

- **CHORE**: Bump dependency to tracelet `3.2.0`.


## 3.1.14

- **CHORE**: Sync release versions across workspace.


## 3.1.10

 - Bump "tracelet_firebase" to `3.1.10`.

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

- **CHORE**: bump version to match tracelet 3.0.0 release.
- **FEAT**: upgraded `tracelet` core dependency to `^3.0.0` which includes the new high-performance Rust Engine rewrite for improved battery efficiency and tracking reliability.

## 1.0.1

* chore: optimize package description and metadata.

## 1.0.0

* Initial release of the Tracelet Firebase Adapter.