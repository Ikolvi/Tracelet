## 3.8.8

**FIX**: the report states a **verdict** on the foreground service instead of leaving it to be inferred from six rows that all say `true`. A service that is running, promoted, carrying `FOREGROUND_SERVICE_TYPE_LOCATION` and denied location by the OS rendered as an entirely green table, which is how a report covering 52 seconds of recording nothing read as healthy. The foreground-service section gains `Started in foreground`, `Background restricted` and `Standby bucket`, and the in-app card no longer shows "Healthy" for either state ([#405](https://github.com/Ikolvi/Tracelet/issues/405), [#406](https://github.com/Ikolvi/Tracelet/issues/406)). The **Location stream health** section picks up the new silence and resume entries, and its empty case no longer claims "the stream has been accepting fixes" — it had asserted exactly that over a window in which it accepted none. An absence of markers is now reported as an absence of markers ([#407](https://github.com/Ikolvi/Tracelet/issues/407)).

## 3.8.7

**FIX**: the bug report names the Tracelet version that produced it, and gained a **Location stream health** section — stalls, recoveries and battery-budget throttle movements lifted out of the general log, each stall line carrying the rejection histogram, the gate the last fix was measured against, the configured gate beside it and the thresholds in force. These are written on the always-on lifecycle channel, so the section is populated even for an app running at the default `logLevel` ([#397](https://github.com/Ikolvi/Tracelet/issues/397), [#398](https://github.com/Ikolvi/Tracelet/issues/398)).

## 3.8.6

Version alignment with tracelet 3.8.6.

## 3.8.5

Version alignment with tracelet 3.8.5.

## 3.8.4

**FEAT**: the foreground-service card renders `suppressed` as a state of its own. A notification hidden on purpose by `showNotificationOnPauseOnly` used to read as "not confirmed yet", indistinguishable from the OS refusing a promotion; it is now labelled and explained as the configured behaviour it is — tracking continues, the service is promoted again when the app backgrounds, and the setting is ignored entirely under `stopOnTerminate: false` ([#378](https://github.com/Ikolvi/Tracelet/issues/378)).

## 3.8.3

Version alignment with tracelet 3.8.3.

## 3.8.2

Version alignment with tracelet 3.8.2.

## 3.8.1

Version alignment with tracelet 3.8.1.

## 3.8.0

**FEAT**: `TraceletBugReport` gains a `## Session lifecycle (background & killed-state trace)` section carrying what the background pipelines actually did — service start/stop, sticky restarts and boot bootstrap outcomes on Android, relaunch and termination boundaries on iOS, and motion-state transitions on both. These are recorded regardless of `logLevel`, so a pasted report carries them even when the developer never enabled logging. Given its own section for the same reason as the geofence trace: lifecycle events are rare while routine chatter is not, so at `debug`/`verbose` the entry from the overnight run that actually failed is exactly the one pushed out of the `## Logs` window. An absent entry is diagnostic too — `motion (foreground)` with no killed-state counterpart means the background detector never ran, and an iOS `termination:` with no following `relaunch:` means the app was never woken ([#318](https://github.com/Ikolvi/Tracelet/issues/318)).

**FEAT**: a **Location Filter** section reports the thresholds `Tracelet.getCurrentLocationTuning()` says are **actually in force**, beside the ones you configured. Every other card reads `Tracelet.activeConfig` — a Dart-side mirror of the last `Config` passed in — so until now the Doctor could only show what was asked for, never what the native filter was using. The verdict chip separates the two ways those can disagree: with `autoTuneFromTransportMode` on, a committed transport mode owns the thresholds and the difference is expected (`Auto-tuned`); with it off, nothing should be moving them and the configured value did not reach the processor (`Mismatch`, the #303 failure class). Reads `N/A` before a tracking session has built a processor, and always on Web ([#303](https://github.com/Ikolvi/Tracelet/issues/303)).

**FEAT**: `TraceletBugReport` gains a `## Location filter (in force vs. configured)` section carrying the same two columns and the same auto-tune verdict, so a pasted issue distinguishes an auto-tune from configuration that never landed without a maintainer having to ask ([#303](https://github.com/Ikolvi/Tracelet/issues/303)).

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

**FIX**: the Permissions card no longer reports a granted motion/activity permission as a red "Restricted". `HealthCheck.motionPermission` carries a `MotionAuthorizationStatus` index (`notDetermined`, `granted`, `deniedForever` → 0, 1, 2), but the card decoded it against CoreMotion's `CMAuthorizationStatus` scale, where index 1 is `restricted` — so a healthy device showed a red "Restricted" beside an "All Clear" warning list, the warning path checking `== 2` and being unaffected. The card now switches over the enum via the new `HealthCheck.motionAuthorization` getter, which makes the mapping exhaustive at compile time, and the dead `3 => 'Granted'` branch (unreachable — the enum has no index 3) is gone.

**FIX**: the bug report prints the motion permission by name rather than as a bare index, so `Motion permission | 0` no longer reads as a boolean or a count.

**FEAT**: the bug report gained a **Geofence transitions (decision trace)** section, filtering `[geofence]` log lines and scanning 2000 entries rather than the 500-entry general log window, so rare ENTER/EXIT crossings are not buried by lifecycle chatter. Both the copy and share actions include it.

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

**FEAT**: Added a **Foreground Service** card to the Doctor overlay and a matching section to the generated bug report, powered by `Tracelet.getForegroundServiceHealth()`. It surfaces the authoritative native foreground-service state — whether the service is running and promoted to the foreground, and the last promotion result (`success`/`deferred`/`failed`) with its failure class and message — so "tracking stops in the background" reports show whether the foreground service was actually running. iOS/web (which have no foreground service) are reflected accordingly ([#255](https://github.com/Ikolvi/Tracelet/issues/255)).

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

* **FEAT** (Doctor): One-tap **bug report** — the *Copy* button now bundles health + active configuration (secrets redacted) + recent logs + telematics into a single Markdown report, and a new *Share* button exports it as a downloadable `.md` file. Available programmatically via `TraceletBugReport.build()` and `TraceletBugReport.redactConfig()`.
* **FEAT** (Doctor): **Copy logs** button added to the log viewer sheet.
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

 - Bump "tracelet_doctor" to `3.1.10`.

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
- **FEAT**: UI now detects and displays the new `Smart` (Hybrid) motion detection mode in the Tracking Card.
- **FEAT**: Display `Battery Budget` target in the Battery & OEM Card.

## 1.0.4

 - Update a dependency to the latest release.

## 1.0.3

 - Update a dependency to the latest release.

## 1.0.2

 - Update a dependency to the latest release.

# Changelog

## 1.0.1

- **CHORE**: Update `tracelet` dependency to `^2.0.6`.
- **DOCS**: Added `example/example.dart` for pub.dev documentation scoring.
- **DOCS**: Added documentation cross-references back to `tracelet` in README.md.

## 1.0.0

- **Initial release** of Tracelet Doctor.
- Drop-in diagnostic bottom sheet via `TraceletDoctor.show(context)`.
- Permission status card (location, motion activity, accuracy authorization).
- Tracking state card (enabled/disabled, mode, motion, odometer, scheduler).
- Battery & OEM card with aggression rating meter (Huawei, Xiaomi, Samsung detection).
- Configuration review card with 5 smart issue detectors:
  - Missing headless task registration detection.
  - Tracking active without "Always" permission warning.
  - Mock locations detected during active tracking.
  - Power Save mode active during tracking.
  - Aggressive OEM without battery optimization exemption.
- Sensor availability grid (accelerometer, gyroscope, magnetometer, significant-motion).
- Database & device card with pending queue count and **clear pending locations** button with confirmation dialog.
- Warning list with 12 `HealthWarning` types and human-readable descriptions.
- Friendly "Tracelet Not Available" screen when plugin is not initialized.
- Copy-to-clipboard for full JSON diagnostic report.
- Re-run diagnostics without dismissing the sheet.
- Animated loading state and graceful error handling with retry.
- Dark glassmorphic theme with semantic status colors.