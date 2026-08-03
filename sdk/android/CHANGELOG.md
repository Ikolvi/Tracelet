## 3.7.4

**FIX**: (Android + iOS) in `geofenceModeHighAccuracy`, a stationary device inside a geofence no longer emits a false ENTER on every resume/boot. `startGeofences()` calls `clearHighAccuracyState()`, which wipes the evaluator's in-memory inside-set, and it runs on every `ready()`/takeover ("Resuming geofence tracking on ready/takeover") and after boot/task-removal — so on an aggressive OEM it fires many times per hour. After each wipe the next fix satisfies `entered && !was_inside` and the evaluator re-emits ENTER; on an attendance backend each becomes a punch-in/punch-out, and a field report showed ~9 auto IN/OUT pairs in a day while the employee never left the office. The exit hysteresis from [#268](https://github.com/Ikolvi/Tracelet/issues/268) and the accuracy-aware EXIT from [#274](https://github.com/Ikolvi/Tracelet/issues/274)/[#276](https://github.com/Ikolvi/Tracelet/issues/276) cannot help, because they govern the crossing math *within* one evaluator lifetime while the "already inside" memory is discarded on every resume — so each takeover looks like a legitimate first-ever ENTER. `startGeofences()` now takes an `isResume` flag: a resume/boot preserves inside-state and only a fresh explicit start resets it (which still re-emits the initial-entry ENTER once). In addition, `GeofenceManager` persists a "known inside" set (SharedPreferences on Android, UserDefaults on iOS) that dedups high-accuracy ENTER/EXIT emissions and survives process death, so even a cold-start re-entry after an OEM kill is suppressed while a genuine departure and return still fire ([#292](https://github.com/Ikolvi/Tracelet/issues/292)). Finally, `startGeofences()` is now idempotent — calling it again while already tracking in geofence mode (the common "refresh fences on every app launch" pattern) is treated as a resume and preserves the inside-set, so only a genuine (re)start (first enable, or after `stop()`) re-arms the initial-entry ENTER.

## 3.7.3

**FIX**: (Android) minified release builds no longer fall back to the AOSP location stack on devices that have Google Play services. `TraceletServices.isGmsAvailable` resolved `GoogleApiAvailability` reflectively so `play-services-base` could stay a soft dependency, but R8 rewrites the `Class.forName` string literal to the renamed class while leaving the `getMethod("getInstance")` argument untouched — so the class resolved, the method lookup threw `NoSuchMethodException`, and the `catch` reported GMS as missing. Field logs show it verbatim: `Exception in isGmsAvailable reflection check: v2.d.getInstance []` on a Galaxy S23. Every minified build since 3.6.x was therefore running on raw `LocationManager` with `GPS_PROVIDER` + `NETWORK_PROVIDER` interleaved, the deprecated `addProximityAlert`, and a no-op activity-recognition client — feeding coarse network fixes straight into the geofence evaluator, which the accuracy-aware EXIT gating from [#274](https://github.com/Ikolvi/Tracelet/issues/274)/[#276](https://github.com/Ikolvi/Tracelet/issues/276) cannot defend against. The probe now distinguishes "GMS absent" from "the probe could not run": a probe failure falls back to an OS package-manager query that no shrinker can rename, and a `-keep` rule for `GoogleApiAvailability` ships in both consumer ProGuard files so the precise reflective path keeps working in host apps.

**FIX**: geofence ENTER/EXIT transitions are now logged, at `INFO`, with the full decision trace on both Android and iOS. `evaluateHighAccuracyProximity` and the OS-transition handler previously logged nothing at any level, so a report of an occasional false EXIT produced a bug report with zero geofence content and had to be triaged from configuration alone. Each crossing now emits `[geofence] EXIT <id> dist= radius= buffer= thr= margin= accRaw= accEff= exitAccuracyMax=`, which is what separates a genuine departure from drift: a small `accRaw` with a large `dist` is an over-confident fix, `clampApplied=true` shows `geofenceExitAccuracyMax` binding and weakening drift immunity relative to the `-1` default, and `accuracyInvalid=true gatingDisabled=true` flags a fix with no valid accuracy (negative `horizontalAccuracy` on iOS, `0.0` on Android), which the evaluator treats as *zero* uncertainty. The line carries distance-from-centre rather than coordinates, so it is safe to paste into an issue. The OS/AOSP path logs `source=os` and states that it has no accuracy gating, and `updateProximity` now labels its line "not ENTER/EXIT" — it reports monitoring scope, and apps that read `geofencesChange.off` as an exit will see phantom exits from a single far-drifting fix.

**FEAT**: `TraceletBugReport` gained a **Geofence transitions (decision trace)** section that lifts `[geofence]` lines out of the general log stream and scans `geofenceTraceLimit` (2000) entries rather than the 500-entry log window. Crossings are rare while lifecycle chatter is not, so in a busy app the transitions were being pushed out of the exported window before anyone generated a report.

**PERF**: the native loggers no longer run a `DELETE` after every log write. Retention is 500-2000 rows, so pruning is now amortized every 50 writes on both platforms.

## 3.7.2

**FIX**: (smart motion) `start()` now seeds the coordinator's accelerometer flag from the state it starts in, and re-syncs the coordinator's tracking mode. The Rust coordinator initialises `is_accel_moving = false` and ignores an unchanged flag, so a start that began in MOVING left the accelerometer inert — the stop-timeout fired, reported stationary, and nothing was emitted. The mode was also only synced in `initialize()` from the *persisted* mode, so a session that ended stationary could leave the coordinator unable to switch again ([#288](https://github.com/Ikolvi/Tracelet/issues/288)).

**FIX**: (smart motion) `MotionDetector` no longer writes `isMoving` itself in smart mode, where the coordinator owns the decision. Claiming the transition locally left the reported state disagreeing with the last motionchange event whenever the coordinator stayed continuous ([#288](https://github.com/Ikolvi/Tracelet/issues/288)).

**FIX**: sensor thresholds sent from Dart (`shakeThreshold`, `stillThreshold`, `stillSampleCount`) are now only applied when the app actually set them, so each platform keeps its own tuned default ([#288](https://github.com/Ikolvi/Tracelet/issues/288)).

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

**FIX**: (Android) `addGeofence()` no longer returns `false` for a geofence that was actually registered. When no device location is known yet, `addGeofence()` persists the record and calls `registerGeofence()`, whose Google Play Services registration is asynchronous. The call runs on the main thread, where the SDK correctly does not block on the registration callback — but it then returned the still-`false` result before the callback ran, so callers saw a bogus failure even though `getGeofences()` listed the geofence. On the main thread the SDK now returns `true` once the registration request has been scheduled without a synchronous error (off the main thread it still awaits the real callback result); genuine Play Services failures continue to be logged. iOS and web were unaffected ([#265](https://github.com/Ikolvi/Tracelet/issues/265)).

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

## 3.3.4

**FIX**: resolve battery and extras DB persistence (#175)

## 3.3.0

* **FEAT** (Battery, Android): Motion-gated wakelock — drop the OEM partial wakelock when stationary and re-assert it on movement, via `AndroidConfig.releaseWakelockWhenStationary` (opt-in, default off; gated on the hardware significant-motion wake sensor) ([#162](https://github.com/Ikolvi/Tracelet/issues/162)).
* **FEAT**: Native runtime for the 3.3.0 behavior engines — TelematicsEngine (driving events), TransportModeClassifier (fused transport mode), and ImpactDetector (crash/fall) wired into the location + accelerometer pipeline. All opt-in / default-off. ([#163](https://github.com/Ikolvi/Tracelet/issues/163), [#164](https://github.com/Ikolvi/Tracelet/issues/164), [#165](https://github.com/Ikolvi/Tracelet/issues/165))

## 3.2.19

**CHORE**: version bump for patch release

## 3.2.18

* **FIX**: Interval-based sync — honor `HttpConfig.syncInterval` with a repeating timer that flushes the offline queue on the configured cadence ([#149](https://github.com/Ikolvi/Tracelet/issues/149)).
* **FIX**: `destroySyncedLocations()` returns the real number of synced-and-pruned locations instead of a hardcoded `0` stub ([#154](https://github.com/Ikolvi/Tracelet/issues/154)).
* **FIX**: Honor the `useKalmanFilter` config key so the Extended Kalman Filter is no longer silently disabled by a key mismatch ([#148](https://github.com/Ikolvi/Tracelet/issues/148)).
* **FIX**: Propagate the detected activity (walking / driving / still) into recorded locations — fixes a permanent `"activity": "unknown"` ([#155](https://github.com/Ikolvi/Tracelet/issues/155)).
* **FIX**: Rebuild the native location processor when `ready()` applies a new config, so settings such as `distanceFilter` take effect immediately instead of using stale defaults ([#157](https://github.com/Ikolvi/Tracelet/issues/157)).
* **FIX**: `getCount()` honors time-bound queries instead of always returning the whole-database total ([#152](https://github.com/Ikolvi/Tracelet/issues/152)).
* **FIX**: The HTTP sync payload now includes each point's motion state `is_moving` ([#151](https://github.com/Ikolvi/Tracelet/issues/151)) and its trigger `event` ([#156](https://github.com/Ikolvi/Tracelet/issues/156)) — both were previously omitted by `SyncLocationRecord`.

## 3.2.17

* **FIX** (Native): Resolve iOS auto-sync thread starvation by offloading synchronous HTTP requests to a background DispatchQueue to prevent blocking Swift Concurrency pools ([#146](https://github.com/Ikolvi/Tracelet/issues/146)).
* **CHORE** (Docs): Fix Nextra changelog rendering bug and improve auto-translation glossary script for internationalization.

## 3.2.16

* **FIX**: Resolve getting stuck in the moving state and never transitioning back to stationary (continuous GPS + battery drain). The accelerometer stillness sampler stays active during the stop-timeout countdown and requires sustained motion — not a single noisy or stale sample — to abort it ([#142](https://github.com/Ikolvi/Tracelet/issues/142)).
* **FIX**: Background and post-reboot location captures are persisted (and therefore synced) again. Headless boot tracking never calls `ready()`, so an `isReady` guard in `insertLocation` silently dropped every captured location before it reached the Rust database, leaving auto-sync with nothing to upload.
* **FIX**: The foreground-service notification now appears when the app is backgrounded or terminated with `showNotificationOnPauseOnly` enabled. The service's own `IMPORTANCE_FOREGROUND_SERVICE` importance (and OS importance lag) made the app read as foregrounded, suppressing the pause-only notification while tracking and sync continued.

## 3.2.15

* **FIX**: Allow `getState()` and `stop()` to be called before `ready()` is invoked, correctly reporting persistent state and shutting down background services if the app was restarted from a killed state.

## 3.2.13

- **FIX**(android): `startOnBoot` now resumes tracking after a reboot even when the OS refuses to start the location foreground service from `BOOT_COMPLETED` (Android 14 disallows starting a `location`-type foreground service from boot). The boot start is no longer deferred until the app is next opened; `BootReceiver` falls back to background WorkManager/alarm tracking when the foreground-service start is blocked.
- **FIX**(android): Background HTTP sync now functions in a headless boot process. The host framework wires `dartSyncInterceptor` at process start (via a `ContentProvider`), so `NativeSyncProvider` can drive the registered headless Dart callbacks for token refresh and custom sync body after a reboot.
- **FIX**(android): Guard against a null `Build.MANUFACTURER` in OEM detection so it degrades gracefully instead of crashing on ROMs/environments where it is unset.

## 3.2.12

- **CHORE**: Re-release to align the full federated package set and native SDKs to a single consistent version. The 3.2.11 release published with mismatched versions across some packages (a few resolved to 3.2.10). No functional code changes.

## 3.2.11

- **FIX**(android): Handle cooperative coroutine cancellation in `PeriodicLocationWorker` — cancellation is no longer logged as an error and is correctly re-thrown so WorkManager records the work as cancelled cleanly.

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

## 3.2.5
- **FIX**: Resolved iOS accelerometer sensitivity mismatch (stationary lock) by normalizing incoming m/s² thresholds to g-force expected by CMMotionManager.
- **FIX**: Unify motion detection initial state and resume behavior across Android and iOS, preventing incorrect forced states on app launch and correctly resuming saved states.
- **FIX**: Resolved `flutter_rust_bridge` dynamic library load failures on release builds for users without `use_frameworks!` by preserving global symbols during Xcode stripping.

## 3.2.3

- **FIX**: Force speed motion manager to evaluate initial speed on Android to prevent the state machine from being permanently stuck in `MOVING` when indoors ([#115](https://github.com/Ikolvi/Tracelet/issues/115)).
- **FIX**: Resolve `flutter_rust_bridge has not been initialized` crash by ensuring the Rust core is instantiated and initialized before accessing methods ([#116](https://github.com/Ikolvi/Tracelet/issues/116)).
- **CHORE**: Sync release versions across all packages.

## 3.2.2

- **CHORE**: Sync release versions across all federated packages and update Swift Package Manager configuration.

## 3.2.1

- **CHORE**: Align federated package versions and include additional patch updates.

## 3.1.8

- Fix iOS SPM publishing

## 3.1.7

 - **FIX**(android): apply kotlin-android plugin to fix gradle build errors on newer AGP versions.
 - **FIX**(ios): fix SPM source folder paths in release bundling to ensure SDK compiles properly via CocoaPods.
 - **FIX**(ios): fix duplicate module import errors by adding conditional import checks for TraceletSDK.

## 3.1.4

- **CHORE**: Sync release versions across workspace.

# Changelog

## 3.2.9

- **FIX**(ios): Remove `TraceletCore+Dummy.swift` / `TraceletSyncFFI+Dummy.swift` — `@_silgen_name` declarations from the old static library model caused "Undefined symbol" linker errors after the static→dynamic xcframework migration.
- **FIX**(android): Catch `ForegroundServiceStartNotAllowedException` in `LocationService.start()` so calling `ready()` from the background on Android 12+ no longer crashes the host app; the foreground service start is deferred until the app returns to foreground.

## 3.2.9

- **FIX**(ios): Remove `TraceletCore+Dummy.swift` / `TraceletSyncFFI+Dummy.swift` — `@_silgen_name` declarations from the old static library model caused "Undefined symbol" linker errors after the static→dynamic xcframework migration.
- **FIX**(android): Catch `ForegroundServiceStartNotAllowedException` in `LocationService.start()` so calling `ready()` from the background on Android 12+ no longer crashes the host app; the foreground service start is deferred until the app returns to foreground.

## 3.2.9

- **FIX**(ios): Remove `TraceletCore+Dummy.swift` / `TraceletSyncFFI+Dummy.swift` — `@_silgen_name` declarations from the old static library model caused "Undefined symbol" linker errors after the static→dynamic xcframework migration.
- **FIX**(android): Catch `ForegroundServiceStartNotAllowedException` in `LocationService.start()` so calling `ready()` from the background on Android 12+ no longer crashes the host app; the foreground service start is deferred until the app returns to foreground.

## 3.2.9

- **FIX**(ios): Remove `TraceletCore+Dummy.swift` / `TraceletSyncFFI+Dummy.swift` — `@_silgen_name` declarations from the old static library model caused "Undefined symbol" linker errors after the static→dynamic xcframework migration.
- **FIX**(android): Catch `ForegroundServiceStartNotAllowedException` in `LocationService.start()` so calling `ready()` from the background on Android 12+ no longer crashes the host app; the foreground service start is deferred until the app returns to foreground.

## 3.2.9

- **FIX**(ios): Remove `TraceletCore+Dummy.swift` / `TraceletSyncFFI+Dummy.swift` — `@_silgen_name` declarations from the old static library model caused "Undefined symbol" linker errors after the static→dynamic xcframework migration.
- **FIX**(android): Catch `ForegroundServiceStartNotAllowedException` in `LocationService.start()` so calling `ready()` from the background on Android 12+ no longer crashes the host app; the foreground service start is deferred until the app returns to foreground.

## 3.2.9

- **FIX**(ios): Remove `TraceletCore+Dummy.swift` / `TraceletSyncFFI+Dummy.swift` — `@_silgen_name` declarations from the old static library model caused "Undefined symbol" linker errors after the static→dynamic xcframework migration.
- **FIX**(android): Catch `ForegroundServiceStartNotAllowedException` in `LocationService.start()` so calling `ready()` from the background on Android 12+ no longer crashes the host app; the foreground service start is deferred until the app returns to foreground.

## 3.2.9

- **FIX**(ios): Remove `TraceletCore+Dummy.swift` / `TraceletSyncFFI+Dummy.swift` — `@_silgen_name` declarations from the old static library model caused "Undefined symbol" linker errors after the static→dynamic xcframework migration.
- **FIX**(android): Catch `ForegroundServiceStartNotAllowedException` in `LocationService.start()` so calling `ready()` from the background on Android 12+ no longer crashes the host app; the foreground service start is deferred until the app returns to foreground.

## 3.2.9

- **FIX**(ios): Remove `TraceletCore+Dummy.swift` / `TraceletSyncFFI+Dummy.swift` — `@_silgen_name` declarations from the old static library model caused "Undefined symbol" linker errors after the static→dynamic xcframework migration.
- **FIX**(android): Catch `ForegroundServiceStartNotAllowedException` in `LocationService.start()` so calling `ready()` from the background on Android 12+ no longer crashes the host app; the foreground service start is deferred until the app returns to foreground.

## 3.2.9

- **FIX**(ios): Remove `TraceletCore+Dummy.swift` / `TraceletSyncFFI+Dummy.swift` — `@_silgen_name` declarations from the old static library model caused "Undefined symbol" linker errors after the static→dynamic xcframework migration.
- **FIX**(android): Catch `ForegroundServiceStartNotAllowedException` in `LocationService.start()` so calling `ready()` from the background on Android 12+ no longer crashes the host app; the foreground service start is deferred until the app returns to foreground.

## 3.2.1

- **CHORE**: Align federated package versions and include additional patch updates.

## 2026-05-31

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`tracelet` - `v3.2.0`](#tracelet---v320)
 - [`tracelet_platform_interface` - `v3.2.0`](#tracelet_platform_interface---v320)
 - [`tracelet_android` - `v3.2.0`](#tracelet_android---v320)
 - [`tracelet_ios` - `v3.2.0`](#tracelet_ios---v320)
 - [`tracelet_web` - `v3.2.0`](#tracelet_web---v320)
 - [`tracelet_doctor` - `v3.2.0`](#tracelet_doctor---v320)
 - [`tracelet_firebase` - `v3.2.0`](#tracelet_firebase---v320)
 - [`tracelet_supabase` - `v3.2.0`](#tracelet_supabase---v320)

---

#### `tracelet` - `v3.2.0`

 - **FEAT**: Implement short-lived WakeLocks for transient background tasks (`startBackgroundTask` / `stopBackgroundTask`), improving background execution reliability on Android (matches iOS `beginBackgroundTask`).
 - **FEAT**: The SQLCipher dependency is no longer required for database encryption (Tracelet Core now natively uses AES-GCM in Rust, reducing APK size by ~16MB).
 - **FEAT**: HTTP sync logic has been moved to the `tracelet_sync` module, which must now be included if you require network synchronization.
 - **FEAT**: Add reverse geocoding functionality. ([0fe7b89a](https://github.com/Ikolvi/Tracelet/commit/0fe7b89aad0e22ea28cf81dd81723a534300c175))

#### `tracelet_platform_interface` - `v3.2.0`

 - **FIX**(web): safe BigInt to int casting for rust bridge 64-bit integers. ([2e592b34](https://github.com/Ikolvi/Tracelet/commit/2e592b344ecc242d03e3c4f840d1f1380d6fecd0))
 - **FEAT**: Add reverse geocoding functionality. ([0fe7b89a](https://github.com/Ikolvi/Tracelet/commit/0fe7b89aad0e22ea28cf81dd81723a534300c175))

#### `tracelet_android` - `v3.2.0`

 - **FEAT**: Add reverse geocoding functionality. ([0fe7b89a](https://github.com/Ikolvi/Tracelet/commit/0fe7b89aad0e22ea28cf81dd81723a534300c175))

#### `tracelet_ios` - `v3.2.0`

 - **FEAT**: Add reverse geocoding functionality. ([0fe7b89a](https://github.com/Ikolvi/Tracelet/commit/0fe7b89aad0e22ea28cf81dd81723a534300c175))

#### `tracelet_web` - `v3.2.0`

#### `tracelet_doctor` - `v3.2.0`

#### `tracelet_firebase` - `v3.2.0`

#### `tracelet_supabase` - `v3.2.0`

## 3.0.1

- **CHORE**: Version bump for monorepo consistency with Flutter plugins (resolves SPM FlutterFramework missing dependency in wrapper).

## 3.0.0

- **FEAT**: Massive Architecture Rewrite — Core algorithms are now powered by a high-performance **Rust Core** using `flutter_rust_bridge`.
- **FEAT**: Smart Motion Mode — Introduced `MotionDetectionMode.smart` powered by the Rust battery budget engine.

## 2.1.0

- **CHORE**: Major release synchronized with Tracelet Flutter 2.1.0.
- **FEAT**: Smart foreground notification visibility — dynamically manages foreground service UI to hide the notification when the app is foregrounded and show it automatically in the background.
- **FEAT**: Implemented `SpeedMotionManager` for the new `tl.MotionDetectionMode.speed` tracking mode, bypassing raw accelerometer triggers and exclusively using GPS speed variations for motion state transitions.
- **FIX**: Prevented a critical logic flaw where the accelerometer was completely shut down during the `stopTimeout` countdown. Motion (e.g., hitting a pothole) during the countdown now correctly aborts the stationary transition (#85).
- **FIX**: Corrected `retryBackoffCap` backoff interval parsing from seconds to milliseconds, fixing an issue where HTTP sync retries fired continuously and exhausted CPU/network resources.
- **FIX**: Prevented `LocationEngine.stop` from unintentionally clobbering the global `stateManager.enabled` flag when transitioning into stationary states in speed mode.
- **REFACTOR**: Transitioned all string-based config values to type-safe Enums across the platform bridge.

## 2.0.7

- **FIX**: Resolved `UnsatisfiedLinkError` crash when optional SQLCipher dependency was added by explicitly loading the `sqlcipher` JNI library before creating the encrypted database ([#78](https://github.com/Ikolvi/Tracelet/issues/78)).
- **FIX**: Prevented false-positive shake events on Android by applying absolute magnitude thresholds (`Math.abs(magnitude)`) to align with iOS behavior, and fixed an edge case where a `stopTimeout` of 0 would skip the stillness transition entirely ([#79](https://github.com/Ikolvi/Tracelet/issues/79)).
- **FIX**: Resolved an issue where Android could get permanently stuck in the `moving` state in full mode if the device was woken up via the shake detector, by enabling accelerometer stillness detection as a continuous fallback even when Activity Recognition is active.

## 2.0.6

- **PERF**: Implemented hardware-level sensor batching (`maxReportLatencyUs`) on accelerometer registration (3s for shake, 5s for stillness) reducing CPU wake-ups by over 90% during active tracking.
- **FEAT**: Added graceful fallback to `TYPE_SIGNIFICANT_MOTION` hardware sensor when `TYPE_ACCELEROMETER` is unavailable.
- **FIX**: Dispatched explicit permission-missing `providerChange` events on `start()` call when location permissions are absent.

## 2.0.5

- **CHORE**: Bump version to 2.0.5 to align with federated Flutter packages and coordinated monorepo release.

## 2.0.3

- **FIX**: Refined Android elapsed realtime drift mock detection check. Age comparisons are now verified between wall-clock time and monotonic system clock to avoid false positives under network clock drift.

## 2.0.2

- **FIX**: `deferTime` is now accounted for in the heuristic mock detection drift calculation. Deferred locations are no longer incorrectly flagged as mock locations.

## 2.0.0

- **CHORE**: Major release synchronized with Tracelet Flutter 2.0.0.
- **FEAT**: Added `shakeThreshold`, `stillThreshold`, and `stillSampleCount` to `MotionConfig` for granular accelerometer tuning.
- **REFACTOR**: Core SDK now supports an "on-demand" dependency model. GMS Location, SQLCipher, and Play Integrity are no longer hard dependencies and are resolved via reflection at runtime.
- **CHORE**: Aligned versioning across the entire Tracelet monorepo.

## 1.1.4

- **CHORE**: Aligned repository podspec files and updated release documentation.
- **CHORE**: Maintenance release to sync native SDK versions.

## 1.1.3

- **CHORE**: Version bump for monorepo consistency.

## 1.1.2

- **FIX**: `destroyAll()` now guards **all** background-critical subsystems behind `stopOnTerminate: false`, not just `locationEngine` and `geofenceManager` (#65). `httpSyncManager.stop()`, `scheduleManager.stop()`, and `stopHeartbeat()` were still called unconditionally on every swipe-to-dismiss, killing HTTP sync, scheduled tasks, and heartbeat monitoring even when background tracking should survive. Uses a unified `keepAlive` flag derived from `!stopOnTerminate && stateManager.enabled`.

## 1.1.1

- **FIX**: `TraceletSdk.destroyAll()` now respects `stopOnTerminate: false` for continuous (mode 0) and geofence (mode 1) tracking modes (#63). `locationEngine.destroy()` was unconditionally called, racing with `LocationService.onTaskRemoved()` bootstrap. Mirrors the existing guards already in place for `PeriodicLocationWorker` and `GeofenceManager`.

## 1.1.0

- **FIX**: `LocationService.onStartCommand` now always calls `startForegroundWithNotification()` at the top, before dispatching on `intent?.action`. Previously only `ACTION_START` promoted the service to the foreground, so any other entry path (`ACTION_STOP`, `ACTION_UPDATE_NOTIFICATION`, `ACTION_BUTTON`, and — most importantly — null-intent sticky restarts after a system kill) would fail Android's foreground-service contract and crash the host app with `RemoteServiceException: Context.startForegroundService() did not then call Service.startForeground()` (#59). The promotion is idempotent, so calling it on every entry is safe. An explicit `null ->` branch was added to `when(intent?.action)` so START_STICKY restarts no longer fall through. Added Robolectric `LocationServiceForegroundContractTest` covering all 5 entry paths.

## 1.0.12

- **PERF**: `LocationEngine.changePace(true)` now fires an additional one-shot `getCurrentLocation()` on stationary → moving transitions, delivering a fresh GPS fix as soon as the hardware is warm without waiting for the `locationUpdateInterval` tick on the continuous stream. Reduces first-fix latency on motion start from 5–10s to ~1–5s (#54). The one-shot is guarded by a `CancellationTokenSource` that is cancelled on `stop()` and superseded on subsequent transitions to prevent late callbacks from firing after a stop.
- **FIX**: After a manual `Tracelet.changePace(false)` (force stationary), the SDK can now detect real motion and resume tracking automatically. Previously, MotionDetector's accelerometer + significant-motion listeners stayed torn down (because `declareMoving()` had stopped them and `declareStationary()` is never invoked from outside), leaving the SDK in a permanent dead-state where no future motion could wake it. `TraceletSdk.changePace()` now invokes a new `MotionDetector.onManualPaceChange()` hook that re-engages the wake-up sensors. iOS was unaffected because CMMotionActivityManager runs continuously at the kernel level.

## 1.0.11

- **FIX**: Geofence and location `extras` now round-trip through SQLite as a `Map` instead of a non-parseable `Map.toString()` representation. Previously, `extras` passed to `addGeofence()` were lost before reaching geofence callbacks (#51 follow-up). Location `extras` are now also included in the read-back location map (previously silently dropped).
- **FIX**: Geofence and location extras are serialized via `org.json.JSONObject` on write and parsed back on read, matching the iOS SDK format. Legacy rows with malformed extras are safely ignored.

## 1.0.10

- **FIX**: Killed-state tracking — `LocationService.stopBootTracking()` is no longer called during `TraceletSdk.initialize()`. Boot-mode LocationEngine and HttpSyncManager now survive until `ready()` is explicitly called, fixing the race where `onAttachedToEngine` destroyed boot tracking before Dart could take over (#50).

## 1.0.9

- **FEAT**: Add `getSyncInterval()` to `ConfigManager` and timer-based sync to `HttpSyncManager` (#50).

## 1.0.8

- **FIX**: `cursorToLocation()` now uses canonical `is_moving` (snake_case) instead of `isMoving` (camelCase) — HTTP sync payload now matches iOS format (#48).
- **FIX**: `cursorToLocation()` now returns ISO 8601 timestamp string instead of numeric epoch milliseconds.
- **FIX**: `insertLocation()` now accepts both `is_moving` and `isMoving` keys for backward compatibility.
- **FIX**: `enrichLocation()`, `buildLocationMap()`, `onDrLocationEstimated()` now use canonical `is_moving` key.
- **FIX**: Audit trail `appendToChain()` and `verifyChain()` accept both `is_moving` and `isMoving` for hash computation.

## 1.0.7

- **CHORE**: Sync release versions with Flutter package updates.

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