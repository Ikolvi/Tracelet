## 3.8.8

**FEAT**: forwards quality-target one-shot options and cancellation to the Android SDK.

**FIX**: the pinned native SDK stops the stream it inherited when the motion pipeline parks; no Dart or plugin change ([#409](https://github.com/Ikolvi/Tracelet/issues/409)).

**FEAT**: the pinned native SDK mints and stamps a trip id; no Dart or plugin change ([#402](https://github.com/Ikolvi/Tracelet/issues/402)).

## 3.8.7

**FIX**: the pinned native SDK carries the pedestrian pace hysteresis, the stationary wake re-arm and the reduced per-fix log volume; no Dart or plugin change.

**FIX**: the pinned native SDK carries the battery-budget ladder, the adaptive-sampling idle escape and the always-on stream diagnostics ([#393](https://github.com/Ikolvi/Tracelet/issues/393)–[#397](https://github.com/Ikolvi/Tracelet/issues/397)); no Dart or plugin change.

## 3.8.6

Version alignment with tracelet 3.8.6.

## 3.8.5

**FIX**: the pinned native SDK clears the odometer's distance anchor in `setOdometer()`, so a reset counter is no longer re-inflated by the next fix. No Dart or plugin change; the fix arrives with the `com.ikolvi:tracelet-sdk` version this release pins ([#387](https://github.com/Ikolvi/Tracelet/issues/387)).

**FIX**: the pinned native SDK acquires a first location when a session starts stationary, which is the default pace — previously `start()` acquired nothing until the device physically moved. No Dart or plugin change; the fix arrives with the `com.ikolvi:tracelet-sdk` version this release pins ([#385](https://github.com/Ikolvi/Tracelet/issues/385)).

**FIX**: the pinned native SDK applies `persistMode` to geofence ENTER/EXIT records, which previously bypassed it entirely and were persisted and synced under `location` and `none` alike. No Dart or plugin change; the fix arrives with the `com.ikolvi:tracelet-sdk` version this release pins ([#383](https://github.com/Ikolvi/Tracelet/issues/383)).

## 3.8.4

**FEAT**: the foreground-service host API carries `notificationStartedAt`, `notificationShowTimer` and `notificationOnlyAlertOnce` through to the SDK, so the notification's OS-rendered elapsed timer and its alert-once behaviour are configurable from Dart ([#376](https://github.com/Ikolvi/Tracelet/issues/376)).

**FIX**: events reach the registered headless task when no member of the event fan-out can receive them. After #364 a foreign plugin's FlutterEngine correctly stays out of `MultiEventSender` — and `onDetachedFromEngine` then removes the primary's own dispatcher, leaving the SDK holding a composite with no members at all while the other plugin's background engine keeps the process alive. Every `send*` was `dispatchers.forEach { … }`, a no-op on an empty list, and `headlessFallback` belonged to `EventDispatcher`, i.e. to the members that had just left: native tracking kept running, Dart received nothing after task removal, and no log line said so. `MultiEventSender` now takes the routing decision itself — broadcast when any member can receive, otherwise a single dispatch to the same `HeadlessTaskService` instance the per-dispatcher fallbacks use, which also de-duplicates the case where several members hold a dead `eventApi` — and both transitions are logged on the always-on lifecycle channel. Reproduced with the plugin that actually causes it: firebase_messaging's own background service, whose engine survives task removal ([#371](https://github.com/Ikolvi/Tracelet/issues/371)).

## 3.8.3

**FEAT**: the telematics host API carries `speed` and `value` through to Dart, so `Tracelet.getTelematicsEvents()` returns the magnitudes behind each event's normalized severity rather than dropping them at the platform boundary ([#367](https://github.com/Ikolvi/Tracelet/issues/367)).

**FIX**: a FlutterEngine created by **another plugin** no longer captures every event for the rest of the process. `isSpawningHeadlessEngine` — the flag #358 introduced — identifies only the engines Tracelet spawns itself, so an engine built by firebase_messaging's `FlutterFirebaseMessagingBackgroundService` (or flutter_local_notifications, background_downloader, …) took the UI branch, and plugin auto-registration handed its dispatcher a live Pigeon `eventApi`. `EventDispatcher` reads a non-null `eventApi` as "a Flutter engine can receive this", so `fallback()` stopped routing to `HeadlessTaskService` — and the isolate it delivered to instead had never called `Tracelet.onLocation`. `onDetachedFromEngine` then made it permanent: the primary removes only its own dispatcher from the fan-out, so after task removal the real UI engine died while the foreign engine survived holding delivery, and native tracking ran on with nothing reaching Dart at all. A secondary engine now joins the fan-out only once its **own Dart side subscribes**, which the native side learns from `requestStateFlush` — `PigeonTracelet._ensureEventsRegistered()` sends exactly one per isolate, immediately after `TraceletEventApi.setUp(...)`, and the Pigeon HostApi is registered per messenger, so its arrival names the engine. An engine that never subscribes never joins, and events keep falling through to the registered headless task. Nothing is lost by waiting: before Dart subscribes there is no handler on the other end, so the deferred events were being dropped by that engine anyway. In-process UI engines that do consume events — an `flutter_overlay_window` overlay, say — are unaffected, since subscribing is exactly what they do; the primary still registers at attach, because `ready()` and the state flush it triggers both run through it; and a headless engine is still excluded even if its task subscribes to a stream, so this cannot re-open #358 ([#364](https://github.com/Ikolvi/Tracelet/issues/364)).

## 3.8.2

**FIX**: geofence crossings (and every other event) reach the registered headless task again once a headless engine has run in the process. `onAttachedToEngine` called `register()` for *every* attaching engine, including headless background isolates, which gave that `EventDispatcher` a non-null Pigeon `eventApi` — read as "a Flutter engine can receive this" — so each event was posted into an isolate with no `onGeofence` listener instead of falling through to `headlessFallback`. The headless task receives events through `HeadlessTaskService.dispatchEvent`, a different channel entirely, so one transient headless engine was enough to swallow every crossing for the rest of the process. Secondary engines are now told apart by `HeadlessTaskService.isSpawningHeadlessEngine`, the flag already wrapped around the `FlutterEngine` constructor that triggers the attach: an in-process UI engine (EngineGroup, e.g. an overlay) still joins the fan-out, a headless engine is kept out of it. The attach *thread* cannot make this call even though it looks like it can — Flutter constructs `FlutterEngine` on the main looper either way — so the decision is recorded on the always-on lifecycle channel instead of DEBUG, which the release build whose report needs it would drop ([#358](https://github.com/Ikolvi/Tracelet/issues/358)).

**FIX**: a geofence crossing that cannot be delivered to the headless task now reports the drop and names the cause. The registration guard was an `if (isRegistered())` repeated at each call site that dropped the event in silence — the worst possible failure for this event, since the crossing is evaluated, logged and persisted natively *before* delivery, so a bug report showed the fence working perfectly while the app never heard about it, and `dispatchEvent`'s own trace line never appeared because the call was never made. Those guards are now one `dispatchToHeadless` helper ([#358](https://github.com/Ikolvi/Tracelet/issues/358)).

## 3.8.1

**FIX**: a headless task after task removal could silently never fire — the engine spawn now times out, retries, and reports failures on the lifecycle channel instead of stalling forever, and its pending-event queue is capped instead of growing without limit ([#331](https://github.com/Ikolvi/Tracelet/issues/331)).

**FIX**: `requestSyncBody` now falls back to a registered headless sync-body builder instead of posting the SDK default when no foreground builder is registered ([#340](https://github.com/Ikolvi/Tracelet/issues/340)).

## 3.8.0

**FIX**: the whole config payload is forwarded with its nulls intact rather than substituted with defaults, so `ConfigManager`'s existing null-skip applies to every section and not only the foreground service ([#321](https://github.com/Ikolvi/Tracelet/issues/321)).

**FIX**: the foreground-service section of a `setConfig()` payload is forwarded with its nulls intact rather than substituted with defaults, so `ConfigManager`'s existing null-skip can do its job and a partial `setConfig()` leaves the stored notification settings untouched ([#320](https://github.com/Ikolvi/Tracelet/issues/320)).

**FEAT**: implements the `getCurrentLocationTuning` host API, which reports the location-filter thresholds actually in force in the native processor rather than echoing the configured values ([#303](https://github.com/Ikolvi/Tracelet/issues/303)).

## 3.8.0-beta.2

**FEAT**: implements the `getCurrentLocationTuning` host API, which reports the location-filter thresholds actually in force in the native processor rather than echoing the configured values ([#303](https://github.com/Ikolvi/Tracelet/issues/303)).

## 3.8.0-beta

**FEAT**: (Android + iOS) `ModeChangeEvent.appliedTuning` reports the four thresholds a committed transport mode put in force — `distanceFilter`, `trackingAccuracyThreshold`, `odometerAccuracyThreshold` and `maxImpliedSpeed` — and is `null` when auto-tuning is off or the mode is `unknown`. Both SDKs already put these on the native mode-change payload in 3.8.0-alpha, but `TlModeChangeEvent` carried only `mode` and `confidence`, so the plugin dispatchers dropped them: an auto-tune was silent for exactly the Flutter apps documented as being able to observe it ([#301](https://github.com/Ikolvi/Tracelet/issues/301)).

**FIX**: (Android + iOS) turning `autoTuneFromTransportMode` off at runtime now restores the thresholds you configured. `applyTransportModeTuning` returned early when the flag was false, before it could restore anything, and the flag does not trigger a processor rebuild — so a session that had auto-tuned to `walking` kept the walking thresholds in force indefinitely after the feature was switched off. Disabling `enableFusedClassifier` had the same effect, since destroying the classifier means no further mode change ever arrives to undo the tuning ([#301](https://github.com/Ikolvi/Tracelet/issues/301)).

**FIX**: (Android + iOS) `setConfig()` no longer silently drops an active auto-tune. A location-key change rebuilds the location processor from the configured values, but the classifier's committed mode was unchanged, so the tuning was not re-applied until a *different* mode committed — a user who stayed on foot across the `setConfig()` kept the base thresholds while `onModeChange` still reported `walking`. Both SDKs now re-align the processor with the committed mode after any reconfiguration ([#301](https://github.com/Ikolvi/Tracelet/issues/301)).

**FIX**: (Android + iOS) enabling `enableFusedClassifier` through `setConfig()` while already tracking now starts the ~1 Hz accelerometer-window loop that drives the classifier. It was started only from `start()`, so a mid-session enable produced a classifier that never classified — and, with auto-tuning on, never retuned. Configuring the classifier at `ready()` was unaffected ([#301](https://github.com/Ikolvi/Tracelet/issues/301)).

**FIX**: (iOS) `autoTuneFromTransportMode` is now watched in the behaviour-key comparison that decides whether `setConfig()` rebuilds the behaviour engines, matching Android ([#301](https://github.com/Ikolvi/Tracelet/issues/301)).

## 3.8.0-alpha

**FIX**: (Android + iOS) `useKalmanFilter: true` now affects recorded **distance**, not just the rendered track. The odometer accumulated raw inter-fix deltas because Kalman smoothing ran *after* the location processor and fed only `coords`, so enabling the filter visibly smoothed the map while distance kept integrating GPS jitter — over-reporting badly on foot, where noise is large relative to real displacement. Smoothing now runs **before** the processor on both platforms, so the distance filter, accuracy filter, implied-speed filter and the odometer all operate on the de-noised track. Every fix feeds the filter (not only accepted ones), keeping its velocity estimate continuous across rejections ([#299](https://github.com/Ikolvi/Tracelet/issues/299)).

**FIX**: (Android + iOS) `fusedClassifierAuthoritative: true` now genuinely drives sampling. The adaptive sampler was built from the raw platform Activity-Recognition value rather than the effective activity, so the fused classifier never reached `AdaptiveSamplingEngine` despite the option being documented as overriding the platform activity for sampling ([#299](https://github.com/Ikolvi/Tracelet/issues/299)).

**FIX**: (iOS) the `classifier` config section was dropped entirely when flattening the plugin config, making `enableFusedClassifier` — and every other classifier option — undeliverable from Flutter on iOS ([#299](https://github.com/Ikolvi/Tracelet/issues/299)).

**FIX**: (Android + iOS) a fix too coarse for the odometer now **defers** its distance instead of deleting it. `odometerAccuracyThreshold` blocked such a fix from contributing, but the odometer's reference point advanced anyway — so the ground actually covered during that segment was lost for good, and the tighter the gate the more distance silently went missing. The odometer now keeps its own anchor, advanced only by fixes that clear the gate, so the next trustworthy fix books the whole span it covered. Without this, tightening the gate (which transport-mode auto-tuning does on foot) traded over-reporting for systematic under-reporting ([#299](https://github.com/Ikolvi/Tracelet/issues/299)).

**FEAT**: (Android + iOS) new `ClassifierConfig.autoTuneFromTransportMode` (default `false`). When enabled, a **committed** transport mode retunes `distanceFilter`, `trackingAccuracyThreshold`, `odometerAccuracyThreshold` and `maxImpliedSpeed` for that mode — tighter on foot, looser in a vehicle — from a table shared by both platforms via the Rust core. This removes the hand-tuning that distance-accurate tracking previously required, and which neither the app developer nor the end user can get right in advance: a single session routinely contains walking, jogging and running. Retuning happens only on a committed change (confidence-gated and debounced by `modeSwitchDwellMs`), never per accelerometer window, and swaps thresholds **in place** so the odometer stays continuous across the change. A mode of `unknown` restores your configured values, and the applied thresholds ride on the `modechange` payload so an auto-tune is never silent. Requires `enableFusedClassifier: true` ([#299](https://github.com/Ikolvi/Tracelet/issues/299)).

## 3.7.6

**FIX**: (Android + iOS) high-accuracy geofence ENTER/EXIT transitions no longer intermittently fail to fire for a stationary device. In `geofenceModeHighAccuracy` the crossing evaluator is now fed the **raw** fix stream and the provider is requested with time-based delivery (`minUpdateDistanceMeters = 0` / `kCLDistanceFilterNone`), decoupling geofence evaluation from the tracking distance filter. That filter is a *persistence*-volume control, but it was also gating the fixes reaching the evaluator: a device standing still on a stable provider — GMS FusedLocationProvider (Android, since 3.7.3) or CoreLocation with a distance filter (iOS) — never moves the filter's distance, so no fix was delivered and no transition was evaluated (field logs show an iPhone parked inside a 50 m zone emitting many ENTERs and never an EXIT). Persistence is unchanged — the Rust `LocationProcessor` keeps its distance filter, so stored/synced location volume does not increase — and the decision logic (accuracy gating [#274](https://github.com/Ikolvi/Tracelet/issues/274), 2-fix confirmation [#294](https://github.com/Ikolvi/Tracelet/issues/294), hysteresis) is untouched; it simply now sees every fix. Standard OS region-monitoring geofence mode is unaffected ([#297](https://github.com/Ikolvi/Tracelet/issues/297)).

## 3.7.5

**FIX**: (Android + iOS) a geofence EXIT is now confirmed across `GEOFENCE_EXIT_CONFIRMATIONS` (2) consecutive out-of-fence fixes rather than a single one. Consumer GNSS routinely emits an isolated "over-confident" fix — one that lands hundreds of metres outside while reporting a tight accuracy the accuracy-aware gate ([#274](https://github.com/Ikolvi/Tracelet/issues/274)) cannot see through; field logs from a vivo V2431 and a Samsung SM-G781B show a stationary office device jumping to 198–301 m out at 1.7–9 m reported accuracy and straight back. Such a fix is always transient, so requiring the device to be confidently outside for two consecutive fixes absorbs the glitch on every device, while a genuine departure — which stays outside — still fires exactly one EXIT, delayed only by one fix interval. This is the temporal complement to the spatial exit hysteresis ([#268](https://github.com/Ikolvi/Tracelet/issues/268)); the decision lives in the Rust core, so Android and iOS inherit it identically, and the pure-Dart evaluator mirrors it ([#294](https://github.com/Ikolvi/Tracelet/issues/294)).

## 3.7.4

**FIX**: (Android + iOS) in `geofenceModeHighAccuracy`, a stationary device inside a geofence no longer emits a false ENTER on every resume/boot. `startGeofences()` calls `clearHighAccuracyState()`, which wipes the evaluator's in-memory inside-set, and it runs on every `ready()`/takeover ("Resuming geofence tracking on ready/takeover") and after boot/task-removal — so on an aggressive OEM it fires many times per hour. After each wipe the next fix satisfies `entered && !was_inside` and the evaluator re-emits ENTER; on an attendance backend each becomes a punch-in/punch-out, and a field report showed ~9 auto IN/OUT pairs in a day while the employee never left the office. The exit hysteresis from [#268](https://github.com/Ikolvi/Tracelet/issues/268) and the accuracy-aware EXIT from [#274](https://github.com/Ikolvi/Tracelet/issues/274)/[#276](https://github.com/Ikolvi/Tracelet/issues/276) cannot help, because they govern the crossing math *within* one evaluator lifetime while the "already inside" memory is discarded on every resume — so each takeover looks like a legitimate first-ever ENTER. `startGeofences()` now takes an `isResume` flag: a resume/boot preserves inside-state and only a fresh explicit start resets it (which still re-emits the initial-entry ENTER once). In addition, `GeofenceManager` persists a "known inside" set (SharedPreferences on Android, UserDefaults on iOS) that dedups high-accuracy ENTER/EXIT emissions and survives process death, so even a cold-start re-entry after an OEM kill is suppressed while a genuine departure and return still fire ([#292](https://github.com/Ikolvi/Tracelet/issues/292)). Finally, `startGeofences()` is now idempotent — calling it again while already tracking in geofence mode (the common "refresh fences on every app launch" pattern) is treated as a resume and preserves the inside-set, so only a genuine (re)start (first enable, or after `stop()`) re-arms the initial-entry ENTER. The persisted set is also kept honest across the full geofence lifecycle: removing a geofence clears its inside-state (so a re-added id, or an id reused for a different location, can ENTER again), and on cold start the evaluator is re-seeded from the persisted set so a device that left a fence *while the app was killed* reports a real EXIT on the next fix instead of getting stuck inside and suppressing the next genuine ENTER.

## 3.7.3

**FIX**: (Android) minified release builds no longer fall back to the AOSP location stack on devices that have Google Play services. `TraceletServices.isGmsAvailable` resolved `GoogleApiAvailability` reflectively so `play-services-base` could stay a soft dependency, but R8 rewrites the `Class.forName` string literal to the renamed class while leaving the `getMethod("getInstance")` argument untouched — so the class resolved, the method lookup threw `NoSuchMethodException`, and the `catch` reported GMS as missing. Field logs show it verbatim: `Exception in isGmsAvailable reflection check: v2.d.getInstance []` on a Galaxy S23. Every minified build since 3.6.x was therefore running on raw `LocationManager` with `GPS_PROVIDER` + `NETWORK_PROVIDER` interleaved, the deprecated `addProximityAlert`, and a no-op activity-recognition client — feeding coarse network fixes straight into the geofence evaluator, which the accuracy-aware EXIT gating from [#274](https://github.com/Ikolvi/Tracelet/issues/274)/[#276](https://github.com/Ikolvi/Tracelet/issues/276) cannot defend against. The probe now distinguishes "GMS absent" from "the probe could not run": a probe failure falls back to an OS package-manager query that no shrinker can rename, and a `-keep` rule for `GoogleApiAvailability` ships in both consumer ProGuard files so the precise reflective path keeps working in host apps.

**FIX**: geofence ENTER/EXIT transitions are now logged, at `INFO`, with the full decision trace on both Android and iOS. `evaluateHighAccuracyProximity` and the OS-transition handler previously logged nothing at any level, so a report of an occasional false EXIT produced a bug report with zero geofence content and had to be triaged from configuration alone. Each crossing now emits `[geofence] EXIT <id> dist= radius= buffer= thr= margin= accRaw= accEff= exitAccuracyMax=`, which is what separates a genuine departure from drift: a small `accRaw` with a large `dist` is an over-confident fix, `clampApplied=true` shows `geofenceExitAccuracyMax` binding and weakening drift immunity relative to the `-1` default, and `accuracyInvalid=true gatingDisabled=true` flags a fix with no valid accuracy (negative `horizontalAccuracy` on iOS, `0.0` on Android), which the evaluator treats as *zero* uncertainty. The line carries distance-from-centre rather than coordinates, so it is safe to paste into an issue. The OS/AOSP path logs `source=os` and states that it has no accuracy gating, and `updateProximity` now labels its line "not ENTER/EXIT" — it reports monitoring scope, and apps that read `geofencesChange.off` as an exit will see phantom exits from a single far-drifting fix.

**FEAT**: `TraceletBugReport` gained a **Geofence transitions (decision trace)** section that lifts `[geofence]` lines out of the general log stream and scans `geofenceTraceLimit` (2000) entries rather than the 500-entry log window. Crossings are rare while lifecycle chatter is not, so in a busy app the transitions were being pushed out of the exported window before anyone generated a report.

**PERF**: the native loggers no longer run a `DELETE` after every log write. Retention is 500-2000 rows, so pruning is now amortized every 50 writes on both platforms.

## 3.7.2

**FIX**: (smart motion) `start()` seeds the coordinator's accelerometer flag and re-syncs its tracking mode, so the accelerometer can contribute to a stationary decision after a start that begins in MOVING ([#288](https://github.com/Ikolvi/Tracelet/issues/288)).

**FIX**: (smart motion) `MotionDetector` no longer writes `isMoving` itself in smart mode, where the coordinator owns the decision ([#288](https://github.com/Ikolvi/Tracelet/issues/288)).

**FIX**: `shakeThreshold`, `stillThreshold` and `stillSampleCount` are only forwarded to the native SDK when the app set them, so platform-tuned defaults survive ([#288](https://github.com/Ikolvi/Tracelet/issues/288)).

**FIX**: a still device now reaches STATIONARY on schedule instead of being stranded in MOVING. While the speed state machine counted down in SLOWING, a *single* GPS fix at or above `speedMovingThreshold` cancelled the countdown and restarted the whole `speedStationaryDelay` window. GPS speed is noisy on a stationary device — an isolated `1.56 m/s` blip amid a stream of `0.00 m/s` fixes was enough — so the pace could keep restarting its countdown indefinitely while the accelerometer had already reported sustained stillness. SLOWING now requires three consecutive above-threshold fixes before returning to MOVING (the same sustained-motion remedy `MotionDetector` applies to accelerometer noise) and the countdown keeps its original start time across a blip. Safe by construction: SLOWING is still continuous tracking, so confirming over a couple of fixes costs no location fidelity. Applied on Android and iOS ([#288](https://github.com/Ikolvi/Tracelet/issues/288)).

**FIX**: the `tracelet_sync` sink is now process-wide instead of one per `FlutterEngine`. Both native plugins created a new `TraceletSyncSink` on every engine attach and never detached one, so any host that spawns secondary engines — `workmanager` creates one per background task, plus headless engines and engine groups — accumulated sinks for the life of the process. Each sink owns its own concurrency guard (a `CoroutineScope` + `Mutex` on Android, a `SyncCoordinator` actor on iOS), so those guards stopped serializing anything and a single persisted location fanned out into N blocking auto-syncs, each pinning one or two threads: `OutOfMemoryError: pthread_create failed`, heap exhaustion, duplicate points server-side and racing `clearLocationsUpTo` calls. The sink is now created once and reused by every later engine, and it is deliberately kept alive on detach so native/headless tracking keeps syncing after a short-lived engine goes away. On iOS the plugin also stopped subscribing the sink twice per engine (directly *and* through the `syncProvider` didSet) and gained a `detachFromEngine(for:)` hook ([#286](https://github.com/Ikolvi/Tracelet/issues/286)).

**FIX**: (iOS) a superseded sync provider can no longer stay subscribed to the `LocationEngine`. `registerSink` was a bare append with no dedupe and there was no way to remove a sink at all, so duplicate and stale sinks each fanned out another `insertLocation` for the same fix. `registerSink` now dedupes by identity, `unregisterSink` was added (Android has had both since #204), and `TraceletSdk.syncProvider` cancels and unregisters the provider it replaces ([#286](https://github.com/Ikolvi/Tracelet/issues/286)).

## 3.7.1

**FIX**: `locationSource` and `reducedAccuracy` are no longer dropped from persisted and synced locations. Both fields are emitted on the live `onLocation` event, but the persist path only serialized `audit_*`, `battery` and `extras` into the `route_context` column, so the classification was lost at write time — every DB-sourced read (`getLocations`, `getPendingLocations`) and the DB-sourced sync payload (`setSyncBodyBuilder`) reported `locationSource: "unknown"` / `reducedAccuracy: false`. This broke the documented guidance to filter historical/synced fixes by `locationSource == "gps"`. Both fields are now persisted as first-class `route_context` keys (like `audit_*`) and promoted back to the top level by `LocationMapper` on read; because the Pigeon `TlLocation` boundary has no dedicated fields for them, they are carried across it via `extras` (like the live event) and unpacked by `Location.fromMap`, so the live event and DB-sourced reads agree. Applied on Android and iOS ([#280](https://github.com/Ikolvi/Tracelet/issues/280)).

**FIX**: (iOS) high-accuracy periodic fixes are no longer a single `requestLocation()` one-shot, which frequently returned a stale cached or first-coarse fix before the GPS hardware converged (persisting a Wi-Fi/cell-level fix for a periodic tick). When `periodicDesiredAccuracy` is `DesiredAccuracy.high`, `performPeriodicFix()` now routes through the same best-of-N sampling window `getCurrentPosition` already uses (`collectSamples` → most-accurate sample), bounded by `locationTimeout`, so periodic fixes are GPS-quality. Non-high periodic accuracy keeps the cheaper single-shot path, and overlapping ticks are guarded against ([#282](https://github.com/Ikolvi/Tracelet/issues/282)).

## 3.7.0

**FEAT**(geofence): accuracy-aware geofence EXIT for high-accuracy mode. A circular geofence now only fires EXIT once the entire GPS error circle clears the fence (`distance - accuracy > radius + buffer`), so a single high-drift, low-confidence fix no longer produces a false EXIT while a device is stationary inside a small geofence. ENTER stays accuracy-agnostic so arrivals still trigger promptly ([#274](https://github.com/Ikolvi/Tracelet/issues/274)).

**FEAT**(geofence): new `GeofenceConfig.geofenceExitAccuracyMax` (meters) to tune the accuracy-aware EXIT gating — `-1` full gating (default, most drift-resistant), `0` disables gating (fastest, most eager EXIT), and `N > 0` clamps the accuracy used in the exit test to `N` to bound the worst-case exit delay while still absorbing drift up to `N`. High-accuracy path only; no effect in standard OS region-monitoring mode ([#276](https://github.com/Ikolvi/Tracelet/issues/276)).

## 3.6.15

**FIX**: (Android) geofence transitions and confirmed crash/fall deliveries could be silently dropped right after a cold boot. Since [#260](https://github.com/Ikolvi/Tracelet/issues/260) moved the heavy `initialize()` setup (Rust DB open, `lateinit` `geofenceManager`/engines) onto a background thread, `initialize()` returns before those managers exist. [#264](https://github.com/Ikolvi/Tracelet/issues/264) guarded the `ready()` / `bootstrapForBackground()` paths, but the native broadcast entry points still raced init: `GeofenceBroadcastReceiver` read `geofenceManager` immediately after `initialize()` (so a cold-boot ENTER/EXIT — a trip start — was swallowed and lost), and `CrashConfirmReceiver` delivered a confirmed impact onto not-yet-wired state. Both now funnel through a new `awaitInit()` gate that blocks until init completes (or reports failure/timeout) before touching those managers, so the transition/impact is delivered instead of dropped. iOS is unaffected (its `initialize()` is synchronous) ([#271](https://github.com/Ikolvi/Tracelet/pull/271)).

## 3.6.14

**FIX**: geofence `ENTER`/`EXIT` flapping for a stationary device inside the radius (high-accuracy mode). The evaluator used a single `distance <= radius` threshold for both entry and exit, so a motionless device whose GPS fixes jittered across the boundary emitted repeated `ENTER`/`EXIT` events. Exit now applies hysteresis — the device `ENTER`s at the true radius but only `EXIT`s once it is farther than `radius + max(radius * 0.1, 20 m)` from the center — so boundary jitter no longer flips the state. Applied in both the pure-Dart evaluator (the active high-accuracy path) and the Rust core used by the native SDKs ([#268](https://github.com/Ikolvi/Tracelet/issues/268)).

**FEAT**: (Android) add `Tracelet.requestTermination()` to stop the GPS foreground service from a headless Dart isolate. When an FCM silent push runs a background task while the app is terminated, `Tracelet.stop()` is unavailable because it relies on Pigeon, which headless isolates cannot reach — so the foreground service kept polling and draining battery until the app was reopened. A new `requestTermination` handler on the `com.tracelet/methods` MethodChannel (registered on the headless `FlutterEngine`) calls `TraceletSdk.stop()`, letting background handlers shut tracking down cleanly ([#267](https://github.com/Ikolvi/Tracelet/issues/267)).

## 3.6.13

**FIX**: (Android) prevent a runtime crash when `com.google.android.gms:play-services-location` resolves below 21.2.0. Tracelet's Android bytecode calls the interface-based `FusedLocationProviderClient` and `ActivityRecognitionClient` APIs, which only became interfaces in play-services-location 21.2.0. When a host app resolved an older version (e.g. 19.0.0) transitively, those types were still concrete classes, so calling into them threw `java.lang.IncompatibleClassChangeError` (crashing the periodic location worker and, after permission handling, the main thread). play-services-location stays `compileOnly`, so the SDK still degrades gracefully to the AOSP `LocationManager` when GMS is absent; a published Gradle dependency constraint now raises the resolved version to a compatible floor (>= 21.2.0) whenever the dependency is present, without adding it to the dependency graph ([#263](https://github.com/Ikolvi/Tracelet/issues/263)).

**FIX**: (Android) prevent a boot/restart crash with `UninitializedPropertyAccessException: lateinit property geofenceManager has not been initialized`. With `startOnBoot: true` and `stopOnTerminate: false`, `LocationService.startBootTracking()` called `bootstrapForBackground()` and then immediately accessed the `geofenceManager`. Since 3.6.9, `initialize()` runs on a background `tracelet-init` thread and `bootstrapForBackground()` did not wait for it, so on a cold boot the `lateinit` managers could still be unassigned — crashing the service in `onStartCommand` before the foreground notification was posted (a timing race most reliably seen on slower environments such as emulators). `bootstrapForBackground()` now blocks on the init latch and returns a success flag: it preserves the initialization exception (no longer mistaking a released latch for success) and verifies the Rust DB and `geofenceManager` are actually assigned. `startBootTracking()` defers gracefully without touching any manager, and `PeriodicLocationWorker` returns `Result.retry()`, when initialization has not completed ([#264](https://github.com/Ikolvi/Tracelet/issues/264)).

**FIX**: (Android) `Tracelet.addGeofence()` no longer returns `false` for a geofence that was actually registered. When no device location is known yet, `addGeofence()` persists the record and calls `registerGeofence()`, whose Google Play Services registration is asynchronous. The Flutter host calls this on the main thread, where the SDK correctly does not block on the registration callback — but it then returned the still-`false` result before the callback ran, so apps saw a bogus failure even though `getGeofences()` listed the geofence. On the main thread the SDK now returns `true` once the registration request has been scheduled without a synchronous error (off the main thread it still awaits the real callback result); genuine Play Services failures continue to be logged. iOS and web were unaffected ([#265](https://github.com/Ikolvi/Tracelet/issues/265)).

## 3.6.12

**FIX**: `Tracelet.ready()` no longer surfaces remote-config event registration failure as an *uncaught* async error. Since 3.6.10, `ready()` subscribes to `remoteConfigEvents`, which lazily registers the Pigeon event channel and fired `requestStateFlush()` fire-and-forget. When the platform side was unreachable (e.g. a headless `flutter test` with no channels, or a temporarily detached engine), the rejected future became an uncaught async error routed to the zone error handler instead of one the caller's `await ready(...)` could catch — fatal for a ride-start path that wrapped `ready()` in try/catch and still got torn down. The best-effort flush is now awaited inside a guarded helper that contains any failure, so it can never escape as an uncaught async error; event registration itself already succeeded, so nothing observable is lost and callers can always recover ([#262](https://github.com/Ikolvi/Tracelet/issues/262)).

## 3.6.11

**FIX**: (iOS) `IosConfig.useSignificantChangesOnly` no longer keeps the persistent system location indicator on. On iOS 17+, enabling significant-change monitoring and calling `Tracelet.start()` still showed an ongoing location indicator (Dynamic Island / status-bar pill) because `start()` opened a `CLBackgroundActivitySession` whenever the device was moving, even though continuous GPS was correctly skipped. `CLBackgroundActivitySession` holds a background location activity alive and auto-shows the indicator, defeating the whole point of significant-change monitoring (low-power background location with no persistent indicator). The SDK now fully honors significant-changes-only mode — it neither opens a `CLBackgroundActivitySession` nor starts continuous GPS (`startUpdatingLocation`), which independently light up the system location indicator — across `start()`, the motion-detection pipeline's switch-to-continuous, `changePace` transitions, and killed-state auto-resume, matching the existing behaviour of periodic mode and low-accuracy geofence-only mode. High-accuracy geofencing and the explicit `IosConfig.useBackgroundActivitySession` opt-in are unaffected. The indicator may still blink briefly when a significant-change event is delivered, which is normal iOS behaviour. (#261)

## 3.6.10

**FIX**: Remote configuration overrides (Enterprise `remoteConfigUrl`) now propagate to the Dart layer. Remote config is fetched and applied entirely on the native side; previously the result never crossed back to Dart, so `Tracelet.activeConfig` — and anything reading it, such as `tracelet_doctor` and the Dart-side battery-budget engine — kept showing the last locally-set values (e.g. a remotely fetched `batteryBudgetPerHour` of `1.0` never appeared, while a local `setConfig` value did). The native layer now emits an `onRemoteConfig` event whenever it applies a remote override — both the freshly fetched config and the cached copy restored at `ready()` — and the Dart layer folds it into the active config, re-initialising the Dart-side battery-budget engine. A new `Tracelet.onRemoteConfig(...)` callback and `Tracelet.remoteConfigStream` let apps react to server-driven configuration changes.

## 3.6.9

**FIX**: Remote config (and any runtime `setConfig()`) now applies `batteryBudgetPerHour`. The battery-budget engine was only built during `ready()`, so a remote-config push such as `{"geo":{"batteryBudgetPerHour":1.0}}` delivered at runtime via `setConfig()` was stored but never acted on — it only appeared to work after a cold restart (which applies the cached copy before `ready()` builds the engine). The engine is now rebuilt when `batteryBudgetPerHour` changes at runtime on both Android and iOS, and battery-budget sampling is started or stopped to match the live tracking state.

**FIX**: iOS — all `Double` configuration getters now read through `NSNumber`, so integer-encoded values (e.g. `1` instead of `1.0` from a remote-config JSON endpoint, or a plain Swift `Int`) coerce correctly instead of silently falling back to their defaults. This matches the existing Android coercion behaviour.

**FIX**: Android — `initialize()` now runs its heavy setup (opening the Rust database, which `fsync`s to disk) on a background thread instead of the caller's main thread, and `ready()` waits for it to finish. Previously, when the system re-created a background `FlutterEngine` (e.g. `audio_service`'s media service after the app was killed), `GeneratedPluginRegistrant` re-attached the plugin and the disk `fsync` ran on that service's main thread, causing an ANR on databases grown large over days of tracking. Thanks to [@dagovalsusa](https://github.com/dagovalsusa) ([#260](https://github.com/Ikolvi/Tracelet/pull/260)).

## 3.6.8

**FEAT**: Expose `Tracelet.updateNotification()`, a public API to refresh the active Android foreground-service notification after changing its configuration ([#257](https://github.com/Ikolvi/Tracelet/issues/257)). The foreground-service notification is configured through `ForegroundServiceConfig` (title, text, icon, color, actions, priority, ongoing state), but there was previously no public way to apply notification-only changes to an already-running service — a notification-only `setConfig()` did not repost the live notification, so new content only appeared after an unrelated service restart or foreground transition. `updateNotification()` now refreshes the active on-screen tracking indicator from the latest configuration without restarting the tracking pipeline. On Android the `ACTION_UPDATE_NOTIFICATION` service path rebuilds and reposts the foreground-service notification (previously a no-op) when the service is promoted, and is a safe no-op when the service is not running. iOS has no foreground-service notification, so `updateNotification()` instead refreshes the running Live Activity — when the app opted into one via `liveActivityConfig` — from the latest config (the dynamic body; the title is immutable on a running activity), and is a safe no-op otherwise. Web is a no-op.

## 3.6.7

**FIX**: In `MotionDetectionMode.smart` / `.speed`, `setConfig()` could restore a temporary stationary mode as the main tracking mode. Those modes run a single continuous motion-aware pipeline that temporarily flips the tracking mode to periodic/geofences while the device is stationary. A restart-sensitive `setConfig()` captured that temporary tracking mode and rebuilt the pipeline via the standalone `startPeriodic()`/`startGeofences()` paths, tearing down the motion-detection pipeline that switches back to continuous on movement — stranding tracking in a standalone stationary mode. `setConfig()` (and, on iOS, `ready()`'s resume path) now restarts the continuous motion-aware pipeline via `start(isResume: true)` whenever the motion-detection mode is smart/speed, regardless of the temporary tracking mode; the pipeline re-enters the stationary sub-state on its own when still stationary. Fixed on both Android and iOS ([#256](https://github.com/Ikolvi/Tracelet/issues/256)).

## 3.6.6

**FEAT**: Added `Tracelet.getForegroundServiceHealth()` — exposes the authoritative native foreground-service state (whether the service is running and promoted to the foreground, the last promotion result of `success`/`deferred`/`failed` with its failure class and message, the notification id, and the last transition timestamp) alongside the desired `enabled` state. On Android 12+ a foreground-service start can be deferred or rejected by the OS even while tracking is enabled, so `enabled` alone is not proof that background tracking is operational; this lets apps build accurate tracking-health indicators, diagnostics, and recovery. iOS reports the desired state with null/false promotion fields (it has no foreground service), and web returns a minimal disabled map ([#255](https://github.com/Ikolvi/Tracelet/issues/255)).

**FIX**: On Android, changing a restart-sensitive setting via `setConfig()` while tracking with a foreground service could kill that service. The restart path called the full `stop()` — which sends `ACTION_STOP` to `LocationService` (`stopForeground` + `stopSelf`) — and immediately restarted the pipeline with `ACTION_START`. On a fresh promotion the `ACTION_STOP` handler's `stopSelf()` could win the race and destroy the service right after `ACTION_START` promoted it, leaving no foreground service at all — the same race fixed for `startPeriodic()` in #237. `stop()` now accepts a `preserveForegroundService` flag and the `setConfig()` restart path keeps the service alive whenever the target mode still needs it, letting the idempotent `ACTION_START` re-assert foreground with no gap; modes that do not use the service stop it cleanly with no follow-up start to race. iOS is unaffected ([#254](https://github.com/Ikolvi/Tracelet/issues/254)).

## 3.6.5

**FIX**: On Android a failed foreground promotion no longer leaves the service marked as a running foreground service. `LocationService.startForegroundWithNotification()` catches a `startForeground()` failure and tears the service down (`stopForeground` + `stopSelf` + `isRunning = false`), but because the exception was swallowed, execution returned normally and every caller then set `isForegroundService = true` unconditionally. The method now returns whether the promotion succeeded and all callers gate `isForegroundService` on that result, so a failed promotion leaves the flag `false`. iOS is unaffected — it has no foreground-service promotion that can fail after the fact ([#253](https://github.com/Ikolvi/Tracelet/issues/253)).

## 3.6.4

**FIX**: On iOS the heartbeat writer no longer persists a GPS fix that the normal dispatch already stored, so `getLocations()` no longer returns byte-identical duplicate location rows (roughly half the points of a moving trip were duplicated on-device). The normal dispatch persists with `event="location"` and the heartbeat timer re-tagged the same cached fix with `event="heartbeat"` and inserted it again; the dedup guard only skipped repeats for `event="location"`, so the heartbeat write slipped through. The guard now shares one last-inserted-timestamp key across both writers. The Android guard is kept in parity ([#252](https://github.com/Ikolvi/Tracelet/issues/252)).

## 3.6.3

**FIX**: `destroyLocation(uuid)` now deletes the record addressed by its public UUID on both Android and iOS. Previously both native SDKs parsed the UUID string as a numeric database id (`toLongOrNull()` / `Int64(uuid)`), so any real UUID failed to parse and the call returned `false` without deleting anything — pending locations could never be acknowledged and the queue never drained. The UUID is now resolved to its row id before deletion, with the legacy numeric-id path kept for backward compatibility ([#251](https://github.com/Ikolvi/Tracelet/issues/251)).

**FIX**: `IosConfig.activityType` is now applied to `CLLocationManager` as configured on iOS. Two independent bugs previously made every value resolve to `.otherNavigation`: the Dart bridge mapped between two differently-ordered enums by raw index (so e.g. `otherNavigation` was sent as `fitness`), and the native side stored the value as an Int but read it back as a String and always fell through to the default. Both sides now agree, so `automotiveNavigation`/`fitness`/`airborne` take effect ([#250](https://github.com/Ikolvi/Tracelet/issues/250)).

## 3.6.2

**FEAT**: Remote config (`remoteConfigUrl`) is now fetched and applied natively on iOS and Android. On `ready()` the SDK fetches a JSON config map from your HTTPS endpoint, applies it over the local config (restarting the tracking pipeline when a tracking-relevant key changes), and refreshes it in the background on the `remoteConfigRefreshInterval` cadence. The last successful response is cached to disk, so a restart resumes on the freshest known settings instantly and offline. Only HTTPS URLs are honored. Previously both platforms recognized the field but never fetched it — the native side silently fell back to the local config.

**FIX**: Stop double-inserting stationary periodic fixes with the same uuid. The stationary periodic timer in `LocationService` now passes `persist=false` to `getCurrentPosition()` so it stays the single writer of the enriched "periodic" record (and the single event dispatch). Fixes the "UNIQUE constraint failed: location_events.uuid" error that occurred every stationary tick ([#248](https://github.com/Ikolvi/Tracelet/issues/248)).

## 3.6.1

**FIX**: Explicit `GeofenceConfig(geofenceModeHighAccuracy: false)` is now honored on aggressive OEMs (Samsung/Xiaomi/Huawei/OnePlus/Oppo/Vivo) instead of being silently forced to `true` — which made `startGeofences()` start the location engine and the `LocationService` foreground service with its persistent notification, the exact thing low-accuracy geofences-only mode exists to avoid (and which Google Play prohibits solely for geofencing from 2026-10-28). Consistent with the #243 fix, the configured value is authoritative on every device and the SDK logs a reliability warning instead ([#247](https://github.com/Ikolvi/Tracelet/issues/247)).

## 3.6.0

**FEAT**: `Tracelet.updateLocationProviderOptions()` — temporarily override `desiredAccuracy`/`distanceFilter` on the running OS provider without a pipeline restart; ephemeral (cleared by `stop()`), persisted config untouched. Live on iOS (`CLLocationManager` property update) and Android (callback-preserving fused re-subscription) ([#241](https://github.com/Ikolvi/Tracelet/pull/241)).

**FIX**: Explicit `foregroundService.enabled: false` / `periodicUseForegroundService: false` are now honored on aggressive OEMs (Xiaomi/Huawei/Samsung/OnePlus/Oppo/Vivo) instead of being silently forced back on with the default foreground notification; the SDK logs a reliability warning instead. Leftover foreground services are also torn down when switching to a no-service periodic strategy, and sticky service restarts re-validate state/config before re-posting the notification ([#243](https://github.com/Ikolvi/Tracelet/issues/243)).

**FIX**: `rejectMockLocations` now guards every Android delivery path — `getCurrentPosition()` (including the last-known fallback), `watchPosition()`, and periodic fixes — not just continuous tracking (found auditing [#243](https://github.com/Ikolvi/Tracelet/issues/243)).

**FIX**: iOS `buildLocationMap` hardcoded `activity: {type: "unknown", confidence: -1}` on every persisted/dispatched location, dropping the classified transport mode even with `fusedClassifierAuthoritative: true`. Per-point `activity` now carries the effective mode and confidence (fused when authoritative, scaled 0–100; otherwise platform Activity Recognition), including on the dead-reckoning path, and Android pairs the authoritative fused type with the fused confidence instead of the unrelated AR confidence ([#244](https://github.com/Ikolvi/Tracelet/pull/244)).

**FIX**: Fused transport modes are persisted in the Activity Recognition vocabulary on both platforms (`vehicle` → `in_vehicle`, `cycling` → `on_bicycle`), and the Dart `Location.activity.type` parser now accepts the native snake_case strings — `in_vehicle`/`on_bicycle`/`on_foot` previously collapsed to `ActivityType.unknown` (follow-up to [#244](https://github.com/Ikolvi/Tracelet/pull/244)).

**FIX**: `activity.confidence` now survives the DB round-trip — new `activity_confidence` column in the location store (auto-migrated; `-1` for rows persisted before the column existed), stored on every insert including encrypted payloads, and returned by `getLocations()` and the sync-interceptor sink instead of a hardcoded `100` ([#245](https://github.com/Ikolvi/Tracelet/issues/245)).

## 3.5.7

**FIX**: Build fails without AGP built-in Kotlin (AGP <9 / builtInKotlin=false) ([#239](https://github.com/Ikolvi/Tracelet/issues/239)).

## 3.5.6

**FIX**: Custom sync body 400 Bad Request HTTP errors now gracefully return fallback results instead of propagating fatal exceptions in native Sync engines ([#238](https://github.com/Ikolvi/Tracelet/issues/238)).

## 3.5.5

**FIX**: Ensure foreground service is properly started in periodic mode when configured ([#237](https://github.com/Ikolvi/Tracelet/issues/237)).

## 3.5.4

**FIX**: Enrich geofence transition events with real coordinate metrics (accuracy/speed/heading/altitude) from the last GPS fix and attach the battery snapshot, instead of hardcoded zeros ([#231](https://github.com/Ikolvi/Tracelet/issues/231)).
**FIX**: Propagate runtime `setConfig` changes to the active native tracking/sensor loops by performing a clean full-pipeline restart (location + motion/speed) when a tracking-relevant key changes ([#230](https://github.com/Ikolvi/Tracelet/issues/230)).
**FIX**: Null-guard subsystems in `destroyAll()` so engine/Activity teardown never throws when the SDK was never initialized (fatal `Unable to destroy activity`) ([#227](https://github.com/Ikolvi/Tracelet/issues/227)).
**FIX**: Android: standard geofence mode no longer starts a foreground service, complying with Google Play's policy (effective 2026-10-28) that prohibits using a foreground service solely for geofencing. Native geofences keep firing while the app is suspended/terminated; geofence-only apps can remove `FOREGROUND_SERVICE_LOCATION` from their manifest.

## 3.5.3

**FIX**: Added explicit ProGuard keep rules for `TraceletStartupProvider` in the `tracelet_android` package to prevent `ClassNotFoundException` on process start when aggressive shrinking (like R8 full mode) is used ([#228](https://github.com/Ikolvi/Tracelet/issues/228)).

## 3.5.2

**FIX**: Android continuous tracking no longer silently stops after a while on aggressive OEMs (Samsung One UI, etc.). The foreground-service wakelock used a fixed 10-minute auto-expiry and was never renewed, so once it lapsed the CPU could deep-sleep and FusedLocationProvider stopped delivering updates with no error or callback. The wakelock is now renewed for the lifetime of tracking ([#222](https://github.com/Ikolvi/Tracelet/issues/222)).

## 3.5.1

**FEAT**: Crash detection now uses the device barometer as an extra confirmation clue — a serious crash or airbag deployment causes a quick cabin air-pressure change, which raises crash confidence on phones that have a pressure sensor. Phones without one simply skip this check, with no downside ([#173](https://github.com/Ikolvi/Tracelet/issues/173)).
**FEAT**: Crashes are now corroborated by a sudden post-impact speed collapse — when the vehicle goes from fast to nearly stopped in the seconds right after the jolt, crash confidence is raised. It only ever adds confidence, never cancels a real crash ([#181](https://github.com/Ikolvi/Tracelet/issues/181)).
**FEAT**: Falls are now corroborated by the classic free-fall → impact → stillness signature — a brief weightless drop followed by the body coming to rest raises fall confidence ([#180](https://github.com/Ikolvi/Tracelet/issues/180)).
**FEAT**: Crash/fall confirmation is now process-death-safe — if the OS kills the app during the cancel countdown (phone thrown, vehicle at rest, Doze), the confirmed event is still delivered from a re-armed exact `AlarmManager` wake-up ([#182](https://github.com/Ikolvi/Tracelet/issues/182)).
**DOCS**: Rewrote the Driving & Safety crash/fall confirmation section in plain, beginner-friendly language.

## 3.5.0

**FEAT**: Crash-detection ML model promoted from **beta to stable** — the shipped model is trained on the CC0 / public-domain Smartphone IMU Road Accident Detection dataset, so it is cleared for commercial use in production apps ([#183](https://github.com/Ikolvi/Tracelet/issues/183)).
**FEAT**: The on-device encrypted model cache now auto-re-downloads when a new model version is published (SHA-256 of the cached blob no longer matches the expected digest), so model upgrades roll out in the same session instead of falling back to the rule engine for a cycle.
**FEAT** (example): Driving & Safety page now shows a live crash-model download/load status indicator, a "Crash (ML model)" debug inference path, a "Benign bump" demo, and a bench "Throw-test" mode.
**PERF**: Per-window crash-model probability is now logged for on-device observability.

## 3.4.2

 - **FEAT**: implement telematics deduplication with synced-state tracking and improved foreground service fault tolerance. ([0581c6e7](https://github.com/Ikolvi/Tracelet/commit/0581c6e7a30a5d436ceb2e8c5d75e46505431e4b))

## 3.4.1

 - **FEAT**(geofence): cross-platform geofenceModeHighAccuracy via GeofenceConfig. ([491d5b83](https://github.com/Ikolvi/Tracelet/commit/491d5b836fbd98a2e456d7d07bafc500f95a2fac))

## 3.4.0

 - **FIX**: a single location batch is uploaded exactly once — replacing/cancelling a previously-registered sync provider prevents duplicate `requestSyncBody` calls and duplicate uploads/DB rows ([#204](https://github.com/Ikolvi/Tracelet/issues/204)).
 - **FIX**: `getCurrentPosition` floors passive priority to balanced so an explicit one-shot always obtains a fix instead of failing with `LOCATION_FAILURE`; per-call extras merge with global extras ([#201](https://github.com/Ikolvi/Tracelet/issues/201)).
 - **REFACTOR**: extract issues 185 and 198, fix iOS config mapping. ([1d088e0d](https://github.com/Ikolvi/Tracelet/commit/1d088e0d58e863b11217c5040410381f91930e59))

## 3.3.4

**FIX**: resolve battery and extras DB persistence (#175)

## 3.3.3

 - **FIX**(android): deliver headless geofence events after reboot in high-accuracy mode ([#185](https://github.com/Ikolvi/Tracelet/issues/185)). ([b197dc5f](https://github.com/Ikolvi/Tracelet/commit/b197dc5f0e4b5f081590e806b27a6eb52a4ed253))

## 3.3.2

* **FIX** (Location data, Android/iOS): Several location-map fields surfaced as static/default values in the Dart layer because the native-map → platform-channel converters dropped or mis-keyed them ([#175](https://github.com/Ikolvi/Tracelet/issues/175)):
  * `getCurrentPosition(extras:, desiredAccuracy:)` were silently ignored on Android (never forwarded to the SDK) — now applied.
  * `battery.isCharging` was always `false` — the converter read `isCharging` instead of the native snake_case `is_charging`.
  * `isMoving` was always `false` — read `isMoving` instead of native `is_moving`.

  Converters now read the native keys (with camelCase fallback), and field-by-field regression tests over the converters were added on both platforms to prevent recurrence.
* **TUNE** (Crash detection): Lowered the default `crashGThreshold` from `3.0 g` to `2.0 g`. Validation against the large [VZCrash](https://huggingface.co/datasets/vzc-research-chapter/VZCrash) field dataset showed the 3.0 g speed-gated rule missed ~48% of real crashes (median impact ~2.2 g) while the false-positive budget was small. Crash detection is opt-in with a cancel-countdown, so the default now favours recall — raise it if you see too many prompts. See [#173](https://github.com/Ikolvi/Tracelet/issues/173). *(Crash detection remains beta pending first-party field validation.)*

## 3.3.1

 - **REFACTOR**(logging): route all SDK logs through TraceletLogger (no raw Log/NSLog). ([e42b676a](https://github.com/Ikolvi/Tracelet/commit/e42b676ae63581d80cee4ac6e35c6103cf7dd0f6))

## 3.3.0

* **FEAT** (Battery, Android): Motion-gated wakelock — drop the OEM partial wakelock when stationary and re-assert it on movement, via `AndroidConfig.releaseWakelockWhenStationary` (opt-in, default off; gated on the hardware significant-motion wake sensor) ([#162](https://github.com/Ikolvi/Tracelet/issues/162)).
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

 - **FIX**(sync): fix background auto-sync abortion when no custom builder is registered (Issue [#134](https://github.com/Ikolvi/Tracelet/issues/134)). ([631542a1](https://github.com/Ikolvi/Tracelet/commit/631542a1c89cece565160966c6f6301a0e18098a))
 - **FIX**(android): prevent headless engine from overwriting sync interceptor (Issue 136). ([b166bcd5](https://github.com/Ikolvi/Tracelet/commit/b166bcd56ad171e488b8c9aed9dda63ef2cc58bd))
 - **FIX**(android): align deltaCoordinatePrecision default with Dart (Issue [#137](https://github.com/Ikolvi/Tracelet/issues/137)). ([5edb9910](https://github.com/Ikolvi/Tracelet/commit/5edb99108eedd7e9dbbcb2a311af6729def6ff79))
 - **DOCS**(android): document Issue 136 fix to prevent regression. ([36b4b9c9](https://github.com/Ikolvi/Tracelet/commit/36b4b9c94f81ee8b852ce2cfcd8d368dd7cabba6))
 - **DOCS**: add official documentation URL to all package READMEs. ([9eb6951e](https://github.com/Ikolvi/Tracelet/commit/9eb6951e64c13007f3264e2d44f0feb9222500a3))
 - **DOCS**: integrate nextra website and update pubspec URLs. ([99b7fda8](https://github.com/Ikolvi/Tracelet/commit/99b7fda82e290ca6c8175313eae62a2475360050))

## 3.2.13

- **FIX**(android): `startOnBoot` now resumes tracking after a reboot even when the OS refuses to start the location foreground service from `BOOT_COMPLETED` (Android 14 disallows starting a `location`-type foreground service from boot). Previously the boot start was deferred until the app was next opened, so tracking silently never resumed after a reboot — `BootReceiver` now falls back to background WorkManager/alarm tracking when the foreground-service start is blocked.
- **FIX**(android): HTTP sync now works headlessly after a reboot. A new process-start `ContentProvider` wires the headless Dart bridge (`TraceletSdk.dartSyncInterceptor` + `TraceletBootstrap.headlessDispatcherFactory`) so background sync can refresh the auth token and build a custom sync body via the registered headless callbacks — previously these were only wired when a UI Flutter engine attached, so after a reboot sync POSTed with a stale token (or the wrong payload) until the app was opened.

## 3.2.12

- **CHORE**: Re-release to align the full federated package set and native SDKs to a single consistent version. The 3.2.11 release published with mismatched versions across some packages (a few resolved to 3.2.10). No functional code changes.

## 3.2.11

- **FIX**(android): Fall back to the headless engine when a custom sync-body round-trip times out, instead of aborting the sync. Fixes location sync stopping after a few minutes while the app is backgrounded (Issue #134).

## 3.2.10

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

## 3.2.5
- **FIX**: Resolved iOS accelerometer sensitivity mismatch (stationary lock) by normalizing incoming m/s² thresholds to g-force expected by CMMotionManager.
- **FIX**: Unify motion detection initial state and resume behavior across Android and iOS, preventing incorrect forced states on app launch and correctly resuming saved states.
- **FIX**: Resolved `flutter_rust_bridge` dynamic library load failures on release builds for users without `use_frameworks!` by preserving global symbols during Xcode stripping.

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

- **FEAT**(android): Add reverse geocoding functionality.

## 3.1.14

- **FIX**(android): bump Android SDK and tracelet_android build.gradle versions to 3.1.14


## 3.1.10

 - Bump "tracelet_android" to `3.1.10`.

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
 - **FIX**: refactor string comparisons to enum indexing across all layers. ([b591b246](https://github.com/Ikolvi/Tracelet/commit/b591b246cca9d46a4fda32634e4b01d7c774ed05))
 - **FIX**: refactor speed motion strings to typed enums across Flutter, Pigeon, Android, and iOS SDKs. ([e974b728](https://github.com/Ikolvi/Tracelet/commit/e974b728142eb7b31b887a3b795cd527da6cbae1))
 - **FEAT**(android): smart foreground notification visibility. ([fbf46b27](https://github.com/Ikolvi/Tracelet/commit/fbf46b27d401828e1c79fd1853.1.4046aaf3f72))
 - **FEAT**: Speed-Based Motion Detection ([#83](https://github.com/Ikolvi/Tracelet/issues/83)). ([5421e7a0](https://github.com/Ikolvi/Tracelet/commit/5421e7a0974033ede6ee5234c641d9bb68cd4460))

## 2.0.8

 - **CHORE**: Update `tracelet_platform_interface` constraint to `^2.0.8`.
 - **CHORE**: Version bump for monorepo consistency and package lockstep alignment.

## 2.0.7

 - **FIX**(interface): correct intToAuthStatus permission index mappings ([[#80](https://github.com/Ikolvi/Tracelet/issues/80)](https://github.com/Ikolvi/Tracelet/issues/80)). ([8cfd7f51](https://github.com/Ikolvi/Tracelet/commit/8cfd7f5150791063bc1286c5c185d01f1d3fc306))
 - **FIX**(android): resolve SQLCipher migration crashes by explicitly loading the sqlcipher native library and decoupling the classpath availability check ([[#78](https://github.com/Ikolvi/Tracelet/issues/78)](https://github.com/Ikolvi/Tracelet/issues/78)). ([757147ee](https://github.com/Ikolvi/Tracelet/commit/757147eeacae07866aa04989a24ca9937307ff2f))
 - **FIX**(android): prevent false positive shake events using absolute sensor magnitude, and declare stationary state immediately when timeout is zero or negative ([[#79](https://github.com/Ikolvi/Tracelet/issues/79)](https://github.com/Ikolvi/Tracelet/issues/79)). ([2aac0a17](https://github.com/Ikolvi/Tracelet/commit/2aac0a179c04debf816ed682f581666cd62006e7))
 - **FIX**(android): removed manual Kotlin Gradle Plugin (KGP) configuration to support Flutter's new Built-in Kotlin feature ([[#81](https://github.com/Ikolvi/Tracelet/issues/81)](https://github.com/Ikolvi/Tracelet/issues/81)).
 - **CHORE**: Update `tracelet_platform_interface` constraint to `^2.0.7`.

## 2.0.6

- **CHORE**: Update `tracelet_platform_interface` constraint to `^2.0.6`.
- **CHORE**: Bump native plugin implementation version to `2.0.6`.

## 2.0.5

- **CHORE**: Version bump for monorepo consistency and package lockstep alignment.
- **CHORE**: Update `tracelet_platform_interface` constraint to `^2.0.5`.
- **CHORE**: Bump native plugin implementation version to `2.0.5`.

## 2.0.4

- **CHORE**: Version bump for monorepo consistency and native SDK alignment.
- **CHORE**: Update `tracelet_platform_interface` constraint to `^2.0.4`.

## 2.0.3

- **FIX**: Removed unreliable timestamp drift heuristic from location spoofing detection.

## 2.0.1

- **CHORE**: Version bump for iOS status bar fix consistency.
- **CHORE**: Update `tracelet_platform_interface` constraint to `^2.0.1`.

## 2.0.0

- **BREAKING**: Adopts an "on-demand" dependency model. Core SDK no longer bundles GMS Location, SQLCipher, or Play Integrity by default, reducing APK size by ~16 MB. Developers must now explicitly add these to their `android/app/build.gradle` if required.
- **BREAKING**: Migrated to Pigeon for all platform-to-native communication, replacing `MethodChannel` with type-safe generated interfaces.
- **FEAT**: Full support for AOSP-only environments via standard `LocationManager` fallback when GMS is unavailable.
- **CHORE**: Bump native `tracelet-sdk` constraint to `2.0.0`.

## 1.9.3
2: 
3: - **CHORE**: Bump native `tracelet-sdk` constraint to `1.1.4`.
4: 
5: ## 1.9.2

- **FIX**: `Tracelet.locationStream` no longer goes silent when `flutter_overlay_window` (or any `FlutterEngineGroup` plugin) creates a secondary in-process `FlutterEngine`. The primary-instance guard (#51) unconditionally skipped `EventDispatcher` re-binding for all secondary engines, including in-process overlay engines that attach on the main thread. A Looper-based discriminator now selectively re-binds the dispatcher for main-thread overlay engines while preserving the full skip for off-thread headless/Firebase engines (#51 fix intact).
- **FIX**: `destroyAll()` now guards all background-critical subsystems when `stopOnTerminate: false` (#65). `httpSyncManager.stop()`, `scheduleManager.stop()`, and `stopHeartbeat()` were still called unconditionally on every swipe-to-dismiss, killing HTTP sync and heartbeat even when background tracking should survive. Fixed in native `tracelet-sdk` 1.1.2.
- **TEST**: Added `secondaryMainThreadEngine_rebindsDispatcherOnly` and `secondaryBackgroundThreadEngine_fullySkipped` to `PluginSecondaryEngineGuardTest` covering both discriminator branches. Existing headless tests updated to stub `isMainThread=false`.
- **CHORE**: Bump native `tracelet-sdk` constraint to 1.1.2.

## 1.9.1

- **FIX**: `destroyAll()` now respects `stopOnTerminate: false` for continuous (mode 0) and geofence (mode 1) tracking modes (#63). `locationEngine.destroy()` was unconditionally called, racing with `LocationService.onTaskRemoved()` native bootstrap. `PeriodicLocationWorker` static refs (`eventSender`, `httpSyncManager`) are also now preserved when `keepPeriodicAlive` is true.
- **CHORE**: Bump native `tracelet-sdk` constraint to 1.1.1.

## 1.9.0

- **FIX**: `LocationService` no longer crashes the host app with `RemoteServiceException: Context.startForegroundService() did not then call Service.startForeground()` (#59). Reproducible on real devices when using `periodicUseForegroundService: true`. Root cause: `onStartCommand` only promoted to foreground for `ACTION_START`, but the system can deliver intents for other actions (and null-intent sticky restarts after a system kill) under the same foreground-service contract. Fixed in native `tracelet-sdk` 1.1.0 by always promoting at the top of `onStartCommand`.
- **FIX**: Picks up the `tracelet_platform_interface` 1.9.0 fix that restores `extras` and `vertices` propagation for `addGeofence` (#58). No native-side changes for this part.
- **CHORE**: Bump native `tracelet-sdk` constraint to 1.1.0.
- **TEST**: Added Robolectric `LocationServiceForegroundContractTest` covering all 5 entry paths (ACTION_START, ACTION_STOP, ACTION_UPDATE_NOTIFICATION, ACTION_BUTTON, null-intent sticky restart).
- **TEST**: Added Robolectric regression test for `EventDispatcher` headless-fallback geofence extras forwarding.

## 1.8.13

- **PERF**: Reduce first-fix latency on stationary → moving transitions. `LocationEngine.changePace(true)` now fires an additional one-shot `getCurrentLocation()` so a fresh GPS fix arrives as soon as the hardware is warm, instead of waiting for `locationUpdateInterval` on the continuous stream. The one-shot is guarded by a `CancellationTokenSource` that is cancelled on `stop()` (#54).
- **FIX**: After a manual `Tracelet.changePace(false)`, MotionDetector’s accelerometer + significant-motion listeners are now re-engaged so real motion can resume tracking. Previously the SDK could get stuck in a permanent stationary state with no sensors listening.
- **FIX**: Bump Android native SDK to 1.0.12.

## 1.8.12

- **FIX**: Geofence `extras` are now delivered correctly to `onGeofence` callbacks. Previously, extras were persisted via `Map.toString()` and could not be parsed back into a Map, causing `GeofenceEvent.extras` to always arrive empty (#51 follow-up).
- **FIX**: Location `extras` are now included in read-back location maps (previously silently dropped in `cursorToLocation`).
- **FIX**: Bump Android native SDK to 1.0.11.

## 1.8.11

- **FIX**: Guard against secondary FlutterEngine (e.g. Firebase background messaging) overwriting SDK singleton's event sender and callbacks (#51).

## 1.8.10

- **FIX**: Killed-state tracking now works reliably — `stopBootTracking()` deferred from `sdk.initialize()` to `sdk.ready()` so boot-mode native tracking (LocationEngine + HttpSyncManager) survives until the Dart side explicitly takes over (#50).
- **FIX**: Bump Android SDK to 1.0.10.

## 1.8.9

- **FEAT**: Add `syncInterval` support — timer-based HTTP sync via `ScheduledExecutorService` (#50).
- **FEAT**: Bump native SDK dependency to exact version `1.0.9`.

## 1.8.8

- **FIX**: HTTP sync payload now uses canonical `is_moving` (snake_case) and ISO 8601 timestamps, matching iOS format (#48).
- **FIX**: Bump native SDK dependency to exact version `1.0.8`.

## 1.8.7

- **CHORE**: Align federated package versions and include additional patch updates.
- **FIX**: Bump native SDK dependency to exact version `1.0.7`.

## 1.8.6

- **FIX**: `getCurrentPosition(samples: 1)` now uses `requestLocationUpdates` instead of `FusedLocationProviderClient.getCurrentLocation()` — forces a fresh GPS fix with proper timeout instead of returning stale cached locations (#46).
- **FIX**: Guard `onAttachedToEngine` callback wiring with `primaryInstance` — prevents headless `FlutterEngine` from overwriting foreground `httpSyncManager` callbacks, which caused `requestFreshHeaders` to timeout (10s) or return `notImplemented`.
- **PERF**: Remove per-batch `onRequestFreshHeaders` invocation — eliminates MethodChannel round-trip before every sync request. Token refresh handled by `onAuthorizationRequired` on 401.
- **FIX**: Bump native SDK dependency to exact version `1.0.6`.
- **FIX**: Privacy zones, audit trail, and encryption APIs now work before `ready()` — guards relaxed from `isReady` to `::manager.isInitialized`.

## 1.8.5

- **FIX**: `getCurrentPosition()` falls back to last known location when `FusedLocationProviderClient.getCurrentLocation()` returns null (e.g. emulator, GPS-off) — fixes `LOCATION_UNAVAILABLE` errors (#46).
- **FIX**: Add public `clearPendingPermissionCallback()` to `TraceletSdk` — resolves cross-module `internal` visibility error.
- **FIX**: Bump native SDK dependency to exact version `1.0.5`.

## 1.8.4

- **FIX**: Add `isReady` guards to all Android SDK methods — prevents `UninitializedPropertyAccessException` when called before `ready()` (re-fixes #46).
- **FIX**: Pin native SDK dependency to exact version `1.0.4` — prevents auto-resolving to incompatible newer releases.

## 1.8.3

- **FIX**: Add `isReady` guards to all Android SDK methods — prevents `UninitializedPropertyAccessException` when called before `ready()` (re-fixes #46).
- **CHORE**: Bump native SDK dependency `com.ikolvi:tracelet-sdk` 1.0.2 → 1.0.3.

## 1.8.2

- **FIX**: Guard `soundManager` access in `handleMotionStateChange()` and `destroyAll()` — prevents `UninitializedPropertyAccessException` if motion detector fires before full initialization.
- **FIX**: Use `LocationManagerCompat.isLocationEnabled()` instead of `LocationManager.isLocationEnabled()` — fixes crash on Android API 26/27.
- **FIX**: Enterprise dependencies (SQLCipher, Play Integrity, security-crypto) now degrade gracefully when absent — runtime `Class.forName` checks prevent `NoClassDefFoundError`.
- **FIX**: `DeviceAttestor` uses lazy `IntegrityManagerFactory` initialization — prevents crash when Play Integrity is not on the classpath.
- **REFACTOR**: Refined ProGuard/R8 consumer rules — narrower keep rules, `-dontwarn` for optional deps.
- **TEST**: Add `destroyAll_doesNotCrash_withoutSoundManager` unit test.

## 1.8.1

- **CHORE**: Version bump for iOS periodic mode location indicator fix.

## 1.8.0

- **FIX**: ConfigManager null-merge — partial `setConfig()` no longer overwrites existing non-null values (e.g. HTTP URL) with null defaults.
- **FIX**: PeriodicLocationWorker catch block now re-schedules the next exact alarm before returning `Result.retry()`, preventing permanent chain breaks on exceptions.
- **FIX**: GeofenceBroadcastReceiver bootstraps SDK when app is killed and `geofenceManager` is null, instead of silently dropping events.
- **FIX**: Align location map format — `isCharging` → `is_charging`, flat coords → nested `coords` map, add `activity` map, `isMock` → `mock`.
- **FIX**: DB `cursorToLocation` outputs `is_charging` in battery map.
- **FEAT**: Add `destroySyncedLocations()` — deletes only synced locations from the database.
- **FEAT**: Auto-purge synced locations after successful HTTP sync in `HttpSyncManager`.
- **TEST**: Add 28 location map format tests, 5 unit tests for ConfigManager null-merge and `destroySyncedLocations`.

## 1.7.1

- **FIX**: ConfigManager null-merge — partial `setConfig()` no longer overwrites existing non-null values (e.g. HTTP URL) with null defaults.
- **FIX**: PeriodicLocationWorker catch block now re-schedules the next exact alarm before returning `Result.retry()`, preventing permanent chain breaks on exceptions.
- **FIX**: GeofenceBroadcastReceiver bootstraps SDK when app is killed and `geofenceManager` is null, instead of silently dropping events.
- **FEAT**: Add `destroySyncedLocations()` — deletes only synced locations from the database.
- **FEAT**: Auto-purge synced locations after successful HTTP sync in `HttpSyncManager`.
- **TEST**: Add 5 unit tests for ConfigManager null-merge protection, `deleteSyncedLocations`, and `destroySyncedLocations` facade.

## 1.7.0

- **FIX**: Wire `headlessFallback` in `eventSenderFactory` — fixes geofence events silently dropped on task removal (#43).
- **FIX**: Add missing `sendTrip`/`sendBudgetAdjustment` to `NoOpEventSender`.
- **FEAT**: Rewrite `EventDispatcher` to use Pigeon `TraceletEventApi` FlutterApi.
- **FEAT**: Add `TraceletHostApiImpl` for type-safe Pigeon HostApi dispatch.
- **REFACTOR**: Extract native SDK to standalone `sdk/android/` module (Maven Central: `com.ikolvi:tracelet-sdk`).
- **REFACTOR**: Remove misleading headless wiring dead code in `LocationService.startBootTracking()`.
- **CHORE**: Enable `returnDefaultValues` for Android unit tests.

## 1.6.3-alpha.1

- **FEAT**: Rewrite `EventDispatcher` to use Pigeon `TraceletEventApi` FlutterApi instead of EventChannels.
- **FEAT**: Add `TraceletHostApiImpl` for type-safe Pigeon HostApi dispatch.
- **REFACTOR**: Extract native SDK code to `sdk/android/` module.
- **CHORE**: Update cross-package dependency constraints to `^1.6.3-alpha.1`.

## 1.6.1

- **FEAT**: Add 401-aware retry — on HTTP 401 Unauthorized, invoke headless headers callback to refresh token, then retry once with updated dynamic headers.

## 1.6.0

- **FEAT**: Add SSL certificate pinning — support for PEM certificates (`CertificatePinner`) and SHA-256 fingerprints (`HandshakeCertificates`) via OkHttp TLS.
- **FEAT**: Add dynamic HTTP headers with runtime callback support and headless background execution.
- **FEAT**: Add route context — attach arbitrary metadata to synced locations.
- **FEAT**: Add custom sync body builder with headless callback support.
- **TEST**: Add `ConfigManagerSyncFeaturesTest` — 12 Robolectric unit tests for sync features.
- **CHORE**: Add `okhttp-tls:5.3.2` dependency.
- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.6.0`.

## 1.5.0

- **FEAT**: Add boot-mode `HttpSyncManager` — locations are auto-synced to the server even when the app is killed or the device reboots.
- **FEAT**: Periodic-mode (WorkManager/ExactAlarm) now creates a dedicated boot-mode `HttpSyncManager` so periodic locations sync without the Flutter engine.
- **TEST**: Add Robolectric unit tests for boot-mode HTTP sync lifecycle.
- **DOCS**: Add "Background / Killed-State Sync" section to HTTP-SYNC.md.
- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.5.0`.

## 1.4.6

- **FIX**: Rename `PermissionManager` to `TraceletPermissionManager` to avoid class name collision with `permission_handler_apple` (#32).
- **CHORE**: Bump `kotlin-gradle-plugin` 2.3.10 → 2.3.20.
- **CHORE**: Bump `androidx.sqlite:sqlite` 2.4.0 → 2.6.2.
- **CHORE**: Bump `com.google.android.play:integrity` 1.4.0 → 1.6.0.
- **CHORE**: Bump `org.mockito.kotlin:mockito-kotlin` 5.4.0 → 6.3.0.
- **CHORE**: Bump `androidx.security:security-crypto` 1.1.0-alpha06 → 1.1.0 (stable).
- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.6`.

## 1.4.5

- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.5`.

## 1.4.4

- **FEAT**: Add `reducedAccuracy` field to location map for cross-platform API consistency with iOS 14+.
- **TEST**: Add Robolectric unit tests for GPS fallback utilities (provider state transitions, location source classification).
- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.4`.

## 1.4.3

- **FEAT**: Automatic GPS-off fallback — when GPS hardware is disabled, the engine auto-downgrades to `PRIORITY_BALANCED_POWER_ACCURACY` for Wi-Fi/cell tower fixes. Restores original priority when GPS is re-enabled.
- **FEAT**: Add `locationSource` classification to every location fix (`gps`, `wifi`, `cell`, `network`, `unknown`).
- **FEAT**: Add `gpsFallback` flag to provider state for Dart-side awareness of fallback state.
- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.3`.

## 1.4.2

- **FIX**: Dead reckoning activation now uses `LocationManager.isProviderEnabled(GPS_PROVIDER)` instead of accuracy heuristic — Wi-Fi/cell fixes no longer prevent DR from activating when GPS hardware is disabled.
- **FIX**: Mock detection heuristic no longer false-flags Wi-Fi/cell locations as mock when GPS is disabled (satellite count 0 is expected without GPS hardware).
- **FIX**: `activateDeadReckoning()` now retries via timer instead of silently returning when `lastLocation` is null.
- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.2`.

## 1.4.1

- **FEAT**: Dead reckoning — full IMU sensor fusion implementation (`DeadReckoningEngine`). Pedestrian Dead Reckoning with step detection (Weinberg formula) and magnetic heading. Vehicle mode with high-pass-filtered acceleration integration.
- **FEAT**: Auto-activation on GPS loss after configurable delay, auto-deactivation on GPS recovery or max duration.
- **CHORE**: Add dead reckoning config getters to `ConfigManager`.
- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.1`.

## 1.4.0

- **FEAT**: Encrypted SQLite — database encryption via SQLCipher with Android Keystore-backed key management (`DatabaseEncryptionManager`).
- **FEAT**: Device attestation — Play Integrity API integration with nonce generation, token caching, and periodic refresh (`DeviceAttestor`).
- **FEAT**: Remote config — fetch remote configuration via HTTPS with ETag caching and config-change event streaming.
- **FEAT**: Dead reckoning — `getDeadReckoningState()` stub for future accelerometer/gyroscope-based position estimation.
- **FEAT**: Carbon estimator — `getCarbonReport()` returns CO₂ estimates from tracked locations using EU average emission factors.
- **CHORE**: Add `net.zetetic:sqlcipher-android`, `androidx.sqlite:sqlite`, `androidx.security:security-crypto`, and `com.google.android.play:integrity` dependencies.
- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.4.0`.

## 1.3.7

- **FIX**: Fix `ClassNotFoundException` crash for `BootReceiver`, `GeofenceBroadcastReceiver`, `PeriodicAlarmReceiver`, and `LocationService` caused by package path mismatch in `AndroidManifest.xml` (fixes #31).
- **FIX**: Fix foreground notification not appearing due to `LocationService` not being resolved from the manifest.
- **FIX**: Fix ProGuard/R8 consumer rules referencing wrong package paths — prevents class stripping in release builds.
- **FIX**: Fix pre-existing test compilation errors caused by missing cross-package imports.
- **CHORE**: Update cross-package dependency constraints to `^1.3.7`.

## 1.3.6

- **FIX**: `getLocations()` now honors `SQLQuery.start` and `SQLQuery.end` timestamp filtering.
- **FIX**: `getCount()` now accepts optional `SQLQuery` for time-bounded counting.
- **CHORE**: Update cross-package dependency constraints to `^1.3.6`.

## 1.3.5

- **CHORE**: Update cross-package dependency constraints to `^1.3.5`.

## 1.3.4

- **CHORE**: Update `tracelet_platform_interface` dependency constraint to `^1.3.3`.

## 1.3.3

- **FIX**: Bundle native core Kotlin source files (`com.tracelet.core.*`) directly inside the plugin package so they are included when published to pub.dev. Previously, the build.gradle referenced sources via a relative monorepo path that was inaccessible to pub.dev consumers.

## 1.3.2

- **PERF**: Replace per-location `JSONObject` allocations with streaming `android.util.JsonWriter` in `HttpSyncManager.buildJsonBody()` (A-L5).

## 1.3.1

- **FIX**: `getHttpExtras()` and `getPersistenceExtras()` now read distinct config keys (`httpExtras`, `persistenceExtras`) with backward-compatible fallback.

## 1.3.0

- **CHORE**: Version bump for federation consistency with `tracelet` 1.3.0.

## 1.2.0

- **CHORE**: Version bump for federation consistency with `tracelet_platform_interface` 1.2.0 (new `NotificationPriority` and `HashAlgorithm` enums).

## 1.1.0

### New Features

- **FEAT**: Add native `DeltaEncoder` (Kotlin) for delta-compressed HTTP sync payloads — mirrors the Dart implementation exactly for platform consistency. Encodes only field deltas between consecutive locations using shortened keys (`la`, `lo`, `t`, `s`, `h`, `a`, `al`, `b`), achieving 60–80% bandwidth reduction. Uses `java.time.Instant` for ISO 8601 timestamp parsing with flexible numeric type coercion.
- **FEAT**: `ConfigManager` now reads and applies the following new configuration fields from Dart: `batteryBudgetPerHour` (adaptive battery budget target), `enableSparseUpdates`, `sparseDistanceThreshold`, `sparseMaxIdleSeconds` (app-level deduplication), `enableDeadReckoning`, `deadReckoningActivationDelay`, `deadReckoningMaxDuration` (inertial navigation when GPS lost), `enableDeltaCompression`, `deltaCoordinatePrecision` (HTTP delta encoding), and `disableAutoSyncOnCellular` (WiFi-only sync).
- **FEAT**: `HttpSyncManager` now supports `disableAutoSyncOnCellular` — skips auto-sync when device is on cellular network, syncing only on WiFi. Also conditionally applies `DeltaEncoder.encode()` to multi-location batches before HTTP upload when `enableDeltaCompression` is enabled, reducing upload size by 60–80%.

## 1.0.2

- **FIX**: `destroyAll()` unconditionally removed geofence registrations from Play Services even when `stopOnTerminate: false` was configured with `trackingMode=1` (geofence mode). Geofences now survive app termination and are re-registered on boot/task-removal ([#23](https://github.com/Ikolvi/Tracelet/issues/23)).

## 1.0.1

- **FIX**: HTTP auto-sync never triggered from automatic location tracking — `onLocationInserted()` was only called from the manual `insertLocation` handler, not from `LocationEngine.persistLocationIfAllowed()` ([#21](https://github.com/Ikolvi/Tracelet/issues/21)).
- **FIX**: `PeriodicLocationWorker` now triggers HTTP auto-sync after each periodic location insert.

## 1.0.0

### 🎉 Stable Release

- **FEAT**: First stable release of `tracelet_android`.
- **DOCS**: Add Play Store background location declaration guide.
- **REFACTOR**: Remove third-party company name references.
- All native Android APIs are finalized and production-ready.

## 0.12.0

### Performance Audit — 29 Android issues resolved

- **PERF**: Add 10-minute wakelock timeout to prevent indefinite CPU wake (A-C1).
- **PERF**: Cache battery info with 30s TTL — eliminates sticky broadcast IPC per location (A-C2).
- **PERF**: Replace N+1 audit trail verification with JOIN query (A-C3).
- **PERF**: Add in-memory privacy zone cache with CRUD invalidation (A-C4).
- **PERF**: Add in-memory geofence cache with CRUD invalidation (A-C5).
- **PERF**: Cache `SimpleDateFormat` as static `isoFormatter` (A-H1).
- **PERF**: Throttle DB pruning to every 100 inserts instead of every insert (A-H2, A-H3).
- **PERF**: Add `@Volatile` to `isRunning` in `LocationService` (A-H4).
- **PERF**: Add `@Volatile` to sync flags in `HttpSyncManager` (A-H5).
- **PERF**: Use `ThreadLocal<MessageDigest>` for thread-safe SHA-256 (A-H6).
- **PERF**: Use cached location for heartbeat events instead of activating GPS (A-H7).
- **PERF**: Remove duplicate flat keys from platform channel location maps (A-H8).
- **PERF**: Add LIMIT 5000 to `getLog()` query (A-H9).
- **PERF**: Singleton `ConfigManager` with double-checked locking (A-M1).
- **PERF**: Add `Locale.US` to all `String.format()` in `buildCanonicalString()` (A-M2).
- **PERF**: Pre-compiled hex lookup table for SHA-256 byte-to-hex conversion (A-M3).
- **PERF**: Smart config restart — only restart location engine when location-relevant keys change (A-M4).
- **PERF**: Rely on wakelock auto-release timeout in `BootReceiver` (A-M5).
- **PERF**: Use `ConcurrentHashMap.newKeySet()` for `activeGeofenceIds` (A-M6).
- **PERF**: Track insert count to avoid `SELECT COUNT(*)` for auto-sync threshold (A-M7).
- **PERF**: Add `created_at` index on locations table (DB v5) (A-M8).
- **PERF**: Apply `deferTime` to `LocationRequest.setMaxUpdateDelayMillis()` (A-M9).
- **PERF**: Add `@Volatile` to `consecutiveStillSamples` in `MotionDetector` (A-M10).
- **PERF**: Resolve cursor column indices once before loop in `cursorToLocationList()` (A-L1).
- **PERF**: Use `equals(ignoreCase = true)` instead of `uppercase()` allocation in logger (A-L2).
- **PERF**: Remove unnecessary `toMutableMap()` in `watchPosition()` (A-L3).
- **PERF**: Extract `ParsedSchedule` data class to deduplicate schedule parsing (A-L4).
- **PERF**: Use `setOf()` instead of `listOf()` for OEM manufacturer detection (A-L6).
- **REFACTOR**: Remove trivial `isMoreRestrictive()` wrapper, inline `isActionMoreRestrictive()` call.
- **CHORE**: Bump DB version from 4 to 5 (v4→v5 migration adds `created_at` index).

## 0.11.5

- **FIX**: Persist polygon geofence `vertices` to SQLite — add `vertices TEXT` column, DB migration v3→v4, and JSON serialization/deserialization in `insertGeofence()`/`cursorToGeofence()`.
- **FIX**: Skip malformed vertex entries instead of coercing invalid coordinates to `0.0`; require ≥ 3 valid vertices for polygon storage.
- **TEST**: Add Robolectric tests for geofence vertices CRUD (11 tests covering round-trip, validation, edge cases).
- **TEST**: Add DB migration integration tests — v3→v4 and v1→v4 upgrade paths, existing data preservation, fresh install.

## 0.11.4

- **CHORE**: Version bump for platform consistency.

## 0.11.3

- **FIX**: Add `ACCESS_BACKGROUND_LOCATION` permission checks to all killed-state restart paths — `BootReceiver`, `LocationService.onTaskRemoved()`, `LocationService.startBootTracking()`, `PeriodicAlarmReceiver`, and `PeriodicLocationWorker`. Prevents "While In Use" permission from triggering tracking in killed/boot state.
- **FEAT**: New `hasBackgroundPermission()` utility on `LocationEngine` for proactive background permission verification.

## 0.11.2

- **CHORE**: Tighten `tracelet_platform_interface` constraint to `^0.11.2`.

## 0.11.1

- **FIX**: Auto-select exact alarms for periodic intervals < 15 min without foreground service.
- **FIX**: Re-scheduling chain in `PeriodicLocationWorker.doWork()` now uses `interval < 900` auto-detect to match initial scheduling strategy.
- **FIX**: Doze-safe alarm fallback — changed `set()` to `setAndAllowWhileIdle()` in `scheduleExactAlarm()`.
- **FIX**: Re-wire `EventDispatcher` in `onAttachedToEngine()` when periodic mode is already active (fixes null dispatcher after process restart).
- **FIX**: Preserve periodic alarms in `destroyAll()` when `stopOnTerminate=false` and periodic tracking is active.
- **FEAT**: Add `canScheduleExactAlarms` and `openExactAlarmSettings` method channel handlers.
- **CHORE**: Bump platform interface to 0.11.1.

## 0.11.0

- **FEAT**: `AuditTrailManager` — SHA-256 hash chain with SQLite persistence and SharedPreferences chain state.
- **FEAT**: `PrivacyZoneManager` — Haversine distance-based zone evaluation with exclude, degrade, and event-only actions.
- **FEAT**: Privacy zones database table with CRUD operations (v2→v3 migration).
- **FEAT**: Audit trail database table with hash chain linkage.
- **FEAT**: `ConfigManager` getters for audit and privacy zone configuration.
- **CHORE**: Bump `tracelet_platform_interface` to ^0.11.0.

## 0.10.0

- **FEAT**: Periodic mode — GPS-friendly interval tracking via `startPeriodic()`. Three scheduling strategies: WorkManager (default), foreground service, and exact alarms.
- **FEAT**: `PeriodicLocationWorker` — WorkManager `CoroutineWorker` for one-shot GPS fixes with automatic SQLite persistence and EventChannel/headless dispatch.
- **FEAT**: `PeriodicAlarmReceiver` — `BroadcastReceiver` for AlarmManager exact alarm chaining when `periodicUseExactAlarms: true`.
- **FEAT**: `SCHEDULE_EXACT_ALARM` permission with graceful fallback to inexact alarms on Android 13+.
- **FIX**: `TraceletAndroidPluginTest` — make `mainHandler` lazy to avoid `RuntimeException` in plain JUnit tests.
- **CHORE**: Bump `tracelet_platform_interface` to ^0.10.0.

## 0.9.1

- **FIX**: Fire heartbeat events in boot-mode headless tracking. `LocationService.startBootTracking()` now starts a self-rescheduling heartbeat timer so heartbeat events dispatch to `HeadlessTaskService` after device reboot.

## 0.9.0

* **FEAT**: HTTP sync retry engine — configurable retry with exponential backoff for transient 5xx, 429, and timeout failures. Respects `Retry-After` headers. Defers sync on connectivity loss.
* **FEAT**: Configurable motion sensitivity — `MotionDetector` reads `shakeThreshold`, `stillThreshold`, `stillSampleCount` from `ConfigManager` at runtime instead of hardcoded constants.
* **FIX**: HTTP 429 (Too Many Requests) now correctly treated as transient (was previously treated as permanent failure).
* **FIX**: Added `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` permission to AndroidManifest.xml for battery exemption settings.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.9.0.

## 0.8.3

* **FEAT**: Proximity-based geofence auto-load/unload — only geofences within `geofenceProximityRadius` are registered with the OS, sorted by distance, capped at 100 (Android limit). Enables monitoring thousands of geofences.
* **FEAT**: `GeofenceManager.updateProximity()` — re-evaluates which geofences to monitor on every location update, dynamically swapping registrations as the device moves.
* **FEAT**: `geofencesChange` event fires with `on`/`off` arrays when geofences are activated/deactivated from proximity monitoring.
* **FEAT**: `maxMonitoredGeofences` config respected — caps simultaneously monitored geofences below the platform limit.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.8.3.

## 0.8.2

* **DOCS**: Improve README visuals with combined Android & iOS demo image.

## 0.8.1

* **DOCS**: Document iOS background hardening changes (no Android code changes in this release).

## 0.8.0

* **FEAT**: `OemCompat` utility — comprehensive OEM compatibility layer with manufacturer detection (Huawei, Xiaomi, OnePlus, Samsung, Oppo, Vivo), aggression ratings (0–5), and OEM-specific settings deep-links.
* **FEAT**: Huawei PowerGenie wakelock hack — uses `LocationManagerService` wakelock tag to bypass PowerGenie background killing.
* **FEAT**: Xiaomi autostart detection — runtime check for MIUI autostart management activity availability.
* **FEAT**: OEM settings deep-links — 8 manufacturer-specific settings screens (autostart, battery saver, app launch, protected apps) validated via `PackageManager.resolveActivity()`.
* **FEAT**: `getSettingsHealth` method channel handler — returns full device OEM health map.
* **FEAT**: `openOemSettings` method channel handler — launches OEM settings by label.
* **PERF**: OEM-safe wakelock lifecycle in `LocationService` — acquire on start, release on stop/destroy/taskRemoved.
* **PERF**: Boot receiver wakelock — temporary 60-second wakelock during `BOOT_COMPLETED` processing to survive aggressive OEM process killing.
* **CHORE**: ProGuard/R8 consumer rules (`consumer-rules.pro`) — prevents stripping of services, receivers, Room entities, and Kotlin metadata in release builds.
* **DOCS**: Update README with OEM compatibility feature and documentation link.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.8.0.

## 0.7.1

* **DOCS**: Add mock location detection feature to README with platform-specific detection details.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.7.1.

## 0.7.0

* **FEAT**: Mock location detection — `isLocationMock()` uses `Location.isMock()` (API 31+) and `isFromMockProvider()` (API 18+) to flag spoofed GPS.
* **FEAT**: Heuristic mock detection (level 2) — satellite count check (< 4 = suspicious) and `SystemClock.elapsedRealtimeNanos` drift detection (> 5s = suspicious).
* **FEAT**: `enrichLocation()` includes `mock` flag and `mockHeuristics` metadata map (satellites, elapsedRealtimeDriftMs, platformFlagMock).
* **FEAT**: Native-level mock rejection — when `rejectMockLocations` is enabled, drops mocked locations before sending to Dart and fires `ProviderChangeEvent.mockLocationsDetected`.
* **FEAT**: `ConfigManager.getMockDetectionLevel()` and `getRejectMockLocations()` getters.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.7.0.

## 0.6.1

* **REFACTOR**: Remove 6 dead `ConfigManager` constants and methods for filtering migrated to Dart in 0.6.0 (`getDisableElasticity`, `getElasticityMultiplier`, `getFilterPolicy`, `getMaxImpliedSpeed`, `getTrackingAccuracyThreshold`, `getUseKalmanFilter`).
* **REFACTOR**: Remove dead `EventDispatcher.sendTrip()` and `"trip"` channel registration — trip events now from Dart `TripManager`.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.6.1.

## 0.6.0

* **REFACTOR**: Remove duplicate location filtering from `LocationEngine.onLocationReceived()` — elasticity, distance filter, accuracy filter, and speed filter now handled by shared Dart `LocationProcessor`.
* **REFACTOR**: Replace `GeofenceManager.evaluateHighAccuracyProximity()` with no-op stub — proximity evaluation moved to shared Dart `GeofenceEvaluator`.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.6.0.

## 0.5.5

* **CHORE**: Bump `tracelet_platform_interface` to ^0.5.5.

## 0.5.4

* **FIX**: Heartbeat event now wraps location data in `{"location": ...}` to match `HeartbeatEvent.fromMap()` — fixes heartbeat always returning zero coordinates.
* **FIX**: Heartbeat falls back to last known location (via `enrichLocation()`) when `getCurrentPosition` returns null.

## 0.5.3

* **CHORE**: Bump `tracelet_platform_interface` to ^0.5.3.

## 0.5.2

* **FEAT**: Accelerometer-only motion detection mode — when `disableMotionActivityUpdates` is `true`, uses hardware accelerometer + `TYPE_SIGNIFICANT_MOTION` sensor for permission-free stationary↔moving detection.
* **PERF**: Lazily initialize `ActivityRecognitionClient` — no longer created when unused in accelerometer-only mode.
* **PERF**: Cache `SensorManager` instance via `obtainSensorManager()` instead of re-fetching on each call.
* **FIX**: Graceful degradation — if `ACTIVITY_RECOGNITION` permission throws `SecurityException`, automatically falls back to accelerometer-only mode.
* **REFACTOR**: Extract `activityTransition()` helper to reduce boilerplate in transition registration.

## 0.5.1

* **DOCS**: Rewrite README with proper description, setup guide link, and related packages table.

## 0.5.0

* **CHORE**: Bump `tracelet_platform_interface` to ^0.5.0.
* **CHORE**: Bump version to 0.5.0.

## 0.4.0

* **FEAT**: `getMotionPermissionStatus()` / `requestMotionPermission()` — ACTIVITY_RECOGNITION permission handling.
* **FIX**: Auto-pace not triggering — start accelerometer monitoring in `MotionDetector.start()` when stationary.
* **FIX**: Speed always zero in motionchange events — track `lastEffectiveSpeed` in LocationEngine.
* **FIX**: Kotlin compilation error from literal `\n` in import line.
* **CHORE**: Bump `tracelet_platform_interface` to ^0.4.0.

## 0.3.0

* **FEAT**: One-shot location via `getCurrentPosition()` with `persist`, `samples`, `maximumAge`, and `extras` parameters.
* **FEAT**: `getLastKnownLocation()` with 3-tier fallback — in-memory cache → FusedLocationProviderClient → system LocationManager (GPS/Network).
* **FEAT**: `ForegroundServiceConfig.enabled` — conditionally start/stop foreground service based on config.
* **FIX**: Replace `requestLocationUpdates` with sequential `getCurrentLocation()` calls in `collectSamples()` to avoid silent throttling on budget devices without foreground service.
* **BREAKING**: Requires `tracelet_platform_interface: ^0.3.0`.

## 0.2.3

* Fix LICENSE file format for proper SPDX detection on pub.dev.

## 0.2.2

* Fix `ConfigManager.setConfig()` — flatten nested section sub-maps (`geo`, `app`, `http`, etc.) sent by Dart before processing. Fixes foreground service notification config (title, text, channel, priority) and all other sub-config values being silently ignored.

## 0.2.1

* Version bump for coordinated release.

## 0.2.0

* Add SPDX `license: Apache-2.0` identifier for pub.dev scoring.

## 0.1.0

* Initial release.
* FusedLocationProvider-based location tracking.
* Foreground service with configurable notification.
* Activity recognition via Google Play Services.
* SQLite persistence with Room.
* HTTP auto-sync with OkHttp.
* Geofencing with platform GeofencingClient.
* Headless Dart isolate execution.
* Boot-completed receiver for start-on-boot.
* WorkManager-based scheduling.