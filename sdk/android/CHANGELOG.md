## 3.8.8

**FEAT**: one-shot acquisition accepts `accuracyTarget` and `requestId`, keeps continuous high-accuracy updates active until the target or deadline, returns the best coarse candidate at timeout, and supports generation-safe cancellation without persistence.

**FIX**: `SmartMotionCoordinator.onSpeedStateChange` handles the action its tremor override produces instead of leaving the return of `coreCoordinator.onAccelStateChange(false)` unread. With `isSpeedMoving` already false that override *is* the transition `evaluate_state` answers with SWITCH_TO_STATIONARY_PERIODIC, and the `onSpeedStateChange` behind it dedupes to NONE, so the engine was never switched. `TraceletSdk.start()`'s SMART branch now seeds `smartMotionCoordinator.onSpeedStateChange(true)` on a forced-moving start: `adoptSpeedMotionPace()` runs only on the non-forced path, so the FFI-side `is_speed_moving` kept a previous session's stationary value for the life of the process ([#409](https://github.com/Ikolvi/Tracelet/issues/409)).

**FIX**: `SmartMotionCoordinator.syncCurrentMode()` maps the coordinator posture from `stateManager.isMoving || locationEngine.isTracking` rather than the committed pace alone, so a start that inherits a live stream still reaches the stationary switch ([#409](https://github.com/Ikolvi/Tracelet/issues/409)). `LocationService.startBootTracking()` reads the new `TraceletSdk.hasLiveSessionEngine` — narrower than `isTracking`, which is unconditionally true from inside the service — before `bootstrapForBackground()` can re-initialise and answer it wrongly, and returns without building a second engine when a session engine is already live in the process ([#410](https://github.com/Ikolvi/Tracelet/issues/410)).

**FIX**: `LocationService` records the procstate its record was created in (`serviceCreatedInForeground`) and reports it through `foregroundServiceHealth()` as `serviceStartedInForeground`, alongside a derived `locationCapabilityLikelyDenied`. Android latches `mAllowWhileInUsePermissionInFgs` at record creation and holds it for the record's life, so a background-started service is denied the foreground-location capability permanently — observable only as `caps=---NFU` in `dumpsys activity processes` and a `ProviderRequest[OFF]` GPS provider, with `isForeground=true` and a posted notification throughout. A promotion in that state is announced once on the lifecycle channel rather than recorded as an unqualified success ([#405](https://github.com/Ikolvi/Tracelet/issues/405)). New `BackgroundRestrictions` reads `ActivityManager.isBackgroundRestricted` (falling back to the `android:run_any_in_background` app-op) and the standby bucket, surfaced as `backgroundRestricted`/`standbyBucket`/`standbyBucketName` and announced at `onCreate` when set ([#406](https://github.com/Ikolvi/Tracelet/issues/406)). `LocationEngine` gains a timer-driven silence watchdog on `SystemClock.elapsedRealtime()` — `noteFilterDecision` only ran when a fix arrived, so a provider delivering nothing tripped nothing. It is armed by `start()`, cleared by `stop()`, and does not fire in stationary-periodic mode, where silence between ticks is the design ([#407](https://github.com/Ikolvi/Tracelet/issues/407)).

**FEAT**: `TripManager` mints a UUIDv4 at trip start and exposes it through `currentTripId`; `onMotionStateChanged` now reports a `TripTransition` (`Started`/`Ended`) rather than only trip-end data, and a new `onTripStart` callback carries the id, start instant, and start location. `TraceletSdk` sets the id on the Rust `DatabaseManager` via `setActiveTripId` at trip start and clears it at trip end, so every insert — including the ones that never touch the trip manager, such as `PeriodicLocationWorker` and `GeofenceManager` — is stamped without a signature change. `telematicsJsonArray` emits `trip_id` (JSON `null` outside a trip), and `NativeSyncProvider` carries `tripId` from the row into `SyncLocationRecord` rather than resolving it at flush time. `TraceletListener.onTripStart` and `TraceletEventSending.sendTripStart` are defaulted no-ops so an implementation outside the SDK keeps compiling ([#402](https://github.com/Ikolvi/Tracelet/issues/402)).

## 3.8.7

**FIX**: `LocationEngine.start`/`stop` announce the continuous stream on the lifecycle channel; the stale-fix pace guard reports the start and end of each run via `staleFixesSincePace` rather than per fix; `TraceletSdk`'s seed-skip and `LocationService`'s background/foreground and foreground-service promotion/demotion transitions move from `debug` to `lifecycle`.

**FIX**: `LocationEngine` gates `speedMotionSpeedSink` on the fix's age, measured from `elapsedRealtimeNanos` against a ten-second `MAX_PACE_FIX_AGE_MS`. The fused provider's cached fix arrives the instant `requestLocationUpdates` is called and used to hand the pace machine a speed from before the device stopped.

**FIX**: `TraceletSdk.startMotionDetection` seeds `SpeedMotionManager` from `locationEngine.lastEffectiveSpeed` only when `locationEngine.getLastLocation()` is non-null — the same "a null location is unknown, not zero" reading `SmartMotionCoordinator.resolvedSpeed` already takes. Both the SPEED and SMART branches were affected. `LocationEngine`'s periodic-fix dispatch no longer defaults a missing `speed` to `0.0` before invoking `speedMotionSpeedSink`.

**FIX**: `ConfigManager.DEFAULT_SPEED_MOVING_THRESHOLD` drops from 1.5 to 0.9 m/s and `SpeedMotionManager` gains a separate exit threshold. `onLocationMoving` now leaves MOVING on `effectiveStationaryThreshold` (the new `speedStationaryThreshold`, or 65 % of the moving threshold when unset) rather than on the entry threshold, which is what stopped a walking pace oscillating across a single value into STATIONARY_PERIODIC.

**FIX**: `TraceletSdk.handleMotionStateChange` re-arms the stationary wake sources when `SmartMotionCoordinator` declines a wake. `MotionDetector.declareMoving()` consumes the one-shot `TYPE_SIGNIFICANT_MOTION` registration, stops shake monitoring and switches to stillness detection before the coordinator is consulted, so a declined wake left a stationary session with nothing armed — unrecoverable in the background, where `TYPE_ACCELEROMETER` delivers nothing while suspended. The declined path now calls `motionDetector.onManualPaceChange(false)` and records it on the lifecycle channel, and the significant-motion trigger itself is recorded there too.

**FIX**: per-fix `isLocationMock` (four lines) and `resolveAddressAndDispatch` (five lines) narration moves from `debug` to `verbose`. At `debug` these consumed the log-row cap in minutes, so a bug report exported after a background failure no longer contained the failure — the retained window covered roughly the last ten seconds of tracking. Detections and errors keep their levels.

**FIX**: `TraceletSdk.startBatteryBudgetSampling` no longer writes the throttle into `ConfigManager`. It called `setConfig(mapOf("distanceFilter" to …, "desiredAccuracy" to …))` and then `locationEngine.stop()/start()`, which rebuilt the Rust `LocationProcessor` with the throttled numbers as its *base* tuning — so the core's protection for a configured `distance_filter == 0` had nothing left to protect. `BatteryBudgetEngine` gains `noteCharging()`, `updateConfigured()`, `throttleLevel` and `throttleState`, and the new `applyBudgetThrottle` installs the result through `LocationEngine.applyBudgetOverlay(distanceFilter, desiredAccuracy, cadenceMultiplier, trackingAccuracyFloor)` — resolved in `effectiveDesiredAccuracy()`/`effectiveDistanceFilter()` below any explicit `updateLocationProviderOptions` override, with `effectiveUpdateInterval()` stretching the fused request's cadence and `LocationProcessor.setAccuracyFloor` keeping the tracking gate no tighter than the accuracy tier being requested. The overlay is applied through `reapplyProviderOptionsIfTracking()`, which replaces the fused request in place rather than restarting the engine. The engine is told Android reports battery level in whole percent ([#393](https://github.com/Ikolvi/Tracelet/issues/393), [#396](https://github.com/Ikolvi/Tracelet/issues/396)).

**FIX**: `LocationEngine` announces a stalled stream. A `noteFilterDecision` on both the accept and reject paths tracks the last accepted fix and a per-reason rejection histogram, and writes stall, recovery, idle-escape and anchor-re-seed lines to `TraceletLog.lifecycle` — the always-on channel — after 120 s without an accepted fix. The `debug` rejection line now formats `result.accuracy`, `result.distance`, `result.effectiveDistanceFilter` and `result.anchorAgeSeconds` beside `currentTuning()` ([#394](https://github.com/Ikolvi/Tracelet/issues/394), [#395](https://github.com/Ikolvi/Tracelet/issues/395), [#397](https://github.com/Ikolvi/Tracelet/issues/397)).

## 3.8.6

Version alignment with tracelet 3.8.6.

## 3.8.5

**FIX**: `setOdometer()` clears the processor's odometer anchor. `LocationProcessor` keeps that anchor separate from the tracking one — deliberately, so a fix too coarse to trust defers its distance rather than losing it — and advances it on every fix that passes the accuracy gate. `LocationEngine.setOdometer` wrote `state.odometer` and nothing else, and nothing on any platform ever cleared the anchor (`LocationProcessor.reset()` existed with no callers outside the core), so the next accepted fix booked `haversine(previous_fix, new_fix)` against the value just set. The call now goes through a new `LocationProcessor.reset_odometer_anchor()`, which clears `odo_last_latitude`/`odo_last_longitude` alone: a full `reset()` would also drop `last_latitude`, which is what decides whether the next fix clears the distance filter, so setting a counter would have changed which locations are recorded. Covered by `LocationEngineSetOdometerAnchorTest`, which drives real fixes through the pipeline rather than asserting on the number it set ([#387](https://github.com/Ikolvi/Tracelet/issues/387)).

**FIX**: a session that starts stationary acquires an anchor fix. `start()` branches on the committed pace and only the moving branch called the provider; `changePace(false)` cannot fill the gap, because `syncCurrentMode()` sets the coordinator's posture to `STATIONARY_PERIODIC` from the pace just committed and `adoptSpeedMotionPace` only then pushes both inputs to stationary — so `evaluate_state` sees no mode change, returns `None`, and `handleAction` never schedules `PeriodicLocationWorker` either. The one-shot that exists, `LocationEngine.requestImmediateFix`, is fired from `changePace(true)`, a transition a session beginning stationary never takes, so nothing called the fused client at all. A new `LocationEngine.requestStartupFix()` fires one `getCurrentLocation` from the stationary branch, routed through `onLocationReceived` so filters, Kalman, odometer, `persistMode` and dispatch all apply; it returns early when `isTracking` (a moving start, or the #357 in-app-evaluated-geofence branch) and is called only for a fresh `start()`, leaving the resume path untouched. `PRIORITY_PASSIVE` is floored to balanced for this request alone — it only yields a fix while another app is actively requesting one, and would reproduce the silence being fixed — while the transition path keeps its configured priority. The anchor contributes only a measured speed: `lastLocation` and the Rust processor's own anchor both survive `stop()`, so the first fix of a new session in a live process derives its speed against wherever the previous session ended, and ~8 m/s from a 5 km inter-session hop sits inside `maxImpliedSpeed` and above `speedMovingThreshold` — enough to overturn the pace `start()` had just committed (#344). The rule is applied to the speed-motion sink, to `lastEffectiveSpeed` (which `start()` seeds the machine from), to `rawSpeedSink` behind the transport auto-tune, and to the dispatched payload; for every fix that is not the anchor the value is unchanged. An accepted anchor also arms `forcePersistNextFilteredLocation`, handing back the free pass it consumed: the processor waives its distance filter only for a fix with no predecessor, so before the anchor existed the fix that woke a stationary session — the #54 one-shot on `changePace(true)`, or the first fix of the stream `SmartMotionCoordinator` starts — *was* that first fix and was delivered for free. With the anchor holding the slot it is a ~0 m duplicate and is dropped, leaving the app told it is moving with no position to go with it. Arming the existing flag rather than patching one wake path covers the accelerometer wake, the coordinator and the foreground-service switch alike, and while the session stays stationary there is no stream to consume it early. Restores acquisition lost in 3.2.0 (`bb8af6a0`), which replaced an unconditional `locationEngine.start()` with the pace branch. Covered by `StationaryStartInitialFixTest` ([#385](https://github.com/Ikolvi/Tracelet/issues/385)).

**FIX**: `persistMode` governs geofence transitions, not just GPS fixes. The single behavioural read of `getPersistMode()` was `LocationEngine.persistLocationIfAllowed`, which sits on the ordinary location path; `GeofenceManager.onGeofenceEvent` was wired straight to the SDK's unconditional `insertLocation`, so `location` ("persist only location records") and `none` ("do not persist any records") both wrote every ENTER/EXIT to the local DB and handed it to the sync provider for the next HTTP batch. That is privacy-relevant rather than merely incorrect: `none` is a reasonable choice for an app that wants geofence callbacks without the SDK keeping a location history, and such an app was silently accumulating a record of every fence the device crossed. The write now goes through `persistGeofenceIfAllowed`, gated on a new `ConfigManager.shouldPersistGeofenceRecords()` mirroring the check the location path already had. Only the DB write is gated — the listener event is dispatched separately via `events.sendGeofence`, so `none` keeps its documented "events are still fired" behaviour. The gate sits on the single callback both transition sources funnel through (OS-delivered `handleGeofenceEvent` and software-evaluated proximity) and reads config live, so a `setConfig` mid-session takes effect on the next crossing; an unrecognised mode falls back to persisting rather than to silent data loss ([#383](https://github.com/Ikolvi/Tracelet/issues/383)).

## 3.8.4

**FEAT**: the foreground-service notification can render an OS-ticked elapsed timer. `notificationStartedAt` (epoch ms) together with `notificationShowTimer` map onto `setWhen` + `setShowWhen` + `setUsesChronometer`, so the clock advances with no reposts at all — an app that wanted an elapsed time previously had to rewrite the notification text itself once a minute, and every one of those reposts re-alerted the device. `notificationOnlyAlertOnce` exposes `setOnlyAlertOnce` for that second half. The timer counts up only; a `startedAt` in the future is clamped to the current instant per post, leaving the persisted value untouched so a device clock correction self-heals on the next repost; and `notificationShowTimer` without a `notificationStartedAt` shows no timer and writes one debug line rather than substituting "now", which would restart the clock on every repost and misreport the session. All three default to today's behaviour and are appended at the END of `ForegroundServiceConfig`, so positional construction, `copy` and `componentN` are unchanged ([#376](https://github.com/Ikolvi/Tracelet/issues/376)).

**FIX**: `showNotificationOnPauseOnly` no longer silently defeats `stopOnTerminate: false`. Hiding the notification is implemented by demoting the service — Android has no foreground service without one — and `ActivityManager` picks the processes to kill on task removal from `proc.foregroundServices`, under its own lock, *before* `onTaskRemoved` is dispatched to the app's main thread. The forced re-promotion sitting in that callback therefore never had a chance: the decision is already made by the time it runs. A swipe from recents inside the window — 285ms measured on a Pixel Fold, 700-1500ms on the reporter's API 35 device — killed the process outright, taking the headless engine, the queued events and the logs with it. The stronger promise wins: while `stopOnTerminate` is false the service is never demoted, so no window exists, and the refusal is written once per `start()` to the always-on lifecycle channel, because the failure it replaces was silent. With `stopOnTerminate: true` nothing is promised past the swipe and pause-only visibility behaves exactly as before ([#378](https://github.com/Ikolvi/Tracelet/issues/378)).

**FIX**: the foreground-service health snapshot reports a deliberate demotion instead of hiding it. `serviceForeground` kept reporting the last successful promotion while pause-only visibility had the notification down, so the API whose whole purpose is to say whether background tracking is operational claimed a foreground service precisely during the window where there was none. Demotions are now recorded as a fourth `lastForegroundPromotionResult` value, `suppressed` — distinct from `deferred` and `failed`, since the service is alive and tracking — and `lastForegroundTransitionAt` stamps state changes only, not every `startForeground` re-post of a notification the service already held ([#378](https://github.com/Ikolvi/Tracelet/issues/378)).

## 3.8.3

**FIX**: a failed telematics sync no longer deletes the events. With `syncTelematics` enabled, the post-sync branch keyed off whether telematics had been *attached* to the batch rather than whether the upload had *succeeded* — `if (count > 0 || hasTelematics)` — and then ran an unpredicated `DELETE` over the whole table. The sync provider returns `0` on HTTP failure, so a device that was offline destroyed exactly the driving events it was supposed to be queueing. Events are now settled only when the request that carried them succeeded, and settling marks the uploaded id range synced via `markTelematicsSynced` instead of clearing the table, so an event recorded between the batch read and the POST is no longer collateral either. `markTelematicsSynced` already existed and the custom-sync-body path already used it correctly; only the default payload path took the destructive shortcut ([#366](https://github.com/Ikolvi/Tracelet/issues/366)).

**FIX**: `syncTelematics` takes effect at all. `sync()` read the flag as `getConfig()["http"]["syncTelematics"]`, but `setConfig` flattens Dart's nested sections into the top level of the config cache on the way in, so `["http"]` was always null and the flag always `false` — however the app configured it. The failure was silent in both directions: a false flag simply skips the telematics block, so there was no error path, and `State.config` still reported `true` because that reads a different structure. Apps with a custom sync-body builder registered were unaffected, since that path uses the correct accessor, which made the gap look integration-specific rather than broken. Now read through `getSyncTelematics()`, with regression tests pinning the flat accessor and asserting the nested form yields null ([#370](https://github.com/Ikolvi/Tracelet/issues/370)).

**FIX**: stored telematics carry `speed` and `value`. `DrivingEvent` has always held both and always delivered them to `onDrivingEvent`, but `tracelet_telematics` had no columns for them, so anything reading an event back — local history, the Doctor bug report, every synced payload — got a normalized 0–1 `severity` flag with no physical quantity behind it: no indication of how hard the braking was or how fast the vehicle was going. Added by `ALTER TABLE` alongside the existing migrations, so upgrades are seamless; rows written before the migration read back as `0.0`, since the columns are `NOT NULL DEFAULT 0.0` and an upgraded install cannot distinguish an old row from a genuine zero. Impacts persist their analogues, entry speed and peak g ([#367](https://github.com/Ikolvi/Tracelet/issues/367)).

**FEAT**: `telematicsUrl` is honored. The field was plumbed from the public API all the way to the Rust config struct and then read by nothing — `telematics_url` appeared exactly once in the entire core, its own declaration — and never reached the sync provider at all, so a separate telematics endpoint silently received no traffic and no warning. When set, telematics are now POSTed there on their own request as `{"telematics": [...]}`, routed through the sync provider so headers, timeouts, retry/backoff, 401 token refresh and SSL pinning behave exactly as they do for locations, and accounted for separately from the location batch: a failed telematics POST leaves those rows unsynced and does not take the locations down with it. When unset — the default — they stay in `extras.__telematics` on the location request, so existing integrations are untouched ([#368](https://github.com/Ikolvi/Tracelet/issues/368)).

**NOTE**: uploading a telematics event no longer removes it from local history, which is what [#313](https://github.com/Ikolvi/Tracelet/issues/313) intended and what the table-wide delete defeated in practice. Because sync now marks rather than deletes, the synced tail is capped at the newest 1000 rows so the table cannot grow for the lifetime of the install; unsynced rows are never subject to that trim, as they are still owed to the server. The wire format is additive throughout — `speed` and `value` join the objects in `extras.__telematics`, and no existing key is renamed or removed ([#366](https://github.com/Ikolvi/Tracelet/issues/366), [#367](https://github.com/Ikolvi/Tracelet/issues/367)).

**FIX**: `maxDaysToPersist` and `maxRecordsToPersist` are enforced against `location_events` again. Both round-tripped from Dart through `ConfigManager` into the Rust `PersistenceConfig` and were then read by nothing: the only retention-scoped delete in the core was `prune_logs`, against the unrelated diagnostic `logs` table. `LocationEngine` still declared `PRUNE_EVERY_N_INSERTS = 100` and `insertCountSincePrune`, and `persistLocationIfAllowed`'s docstring still claimed to run retention pruning, but neither the constant nor the counter was read anywhere in the repo — the calls that used them were deleted by `2afc926f` ("prepare for 3.1.0") when that commit replaced the persist body's `db.insertLocationAsync` with the sink fan-out, taking the `db.pruneOldLocations` / `db.enforceMaxRecords` pair in the same body with it. Enforcement now lives in the Rust core as `prune_locations_older_than` / `enforce_max_location_records`, so both platforms share one implementation instead of the two hand-written SQL copies that were lost, and is applied from `TraceletSdk.insertLocation` — the single funnel every persisted location passes through. Deliberately not from `LocationEngine`, where the leftover counter sat: the engine's persist path is only one caller, and the public `Tracelet.insertLocation()` API and the headless boot path insert straight through the SDK, so pruning in the engine would have left the reported repro (100+ explicit `insertLocation` calls) still unbounded. Age is read from the indexed `timestamp_ms`; rows written before that column existed carry `0` and fall back to the text `timestamp`, and a row whose timestamp SQLite cannot parse is kept rather than read as epoch-old and destroyed on the first prune. The audit-chain rows go with the locations they belong to, as they already did on the sync path — retention that dropped locations but left `audit_trail` behind would just move the unbounded growth into a table with no cap of its own, whose orphans nothing can reach because they are keyed by a `uuid` that no longer resolves. A retention failure is contained and logged, never allowed to fail the insert: the record is already committed, and losing it to a prune error would be strictly worse than an oversized queue ([#361](https://github.com/Ikolvi/Tracelet/issues/361)).

## 3.8.2

**FIX**: a geofence added after `start()` now gets the fix cadence it is decided from. A fence the in-app evaluator owns — a polygon, or a circle below the ~100 m Play Services can resolve — is judged from the raw fix stream, so #355 requests the provider with `minUpdateDistanceMeters = 0` to have fixes delivered on time rather than on displacement. That question was settled **once**, at `start()`/`startGeofences()`/boot, and `start()` then `addGeofence()` is the ordinary order: with no fence registered yet the answer was "no", and `addGeofence()`/`removeGeofence()` never re-asked it. The fused request kept the configured distance filter for the rest of the session, so the evaluator was handed one fix per that many metres travelled — and EXIT requires two *consecutive* fixes beyond the hysteresis band, which a walker can cross and re-enter between two deliveries. The fence set now drives the cadence at every point it changes: adding an evaluator-owned fence re-issues the request live (in place, so processor state and odometer continuity are untouched), removing the last one restores the configured gate, and in `geofences` mode the same signal drives the location stream and its foreground service, so a fence added later can reach that posture and one removed later — KnockOut removes on EXIT — can leave it instead of leaking continuous GPS and a service Google Play no longer permits for geofencing alone. **The stationary state no longer takes the stream away from a fence that is decided from it, either.** #319 stops the engine when the committed motion state goes stationary, on the premise that nothing needs a continuous stream while the device is still; a sub-100 m fence breaks that premise, and the killed-state reconcile already refused the throttle for exactly this reason — the alive app did not. A device trace shows the cost: `session: start — isMoving=false` sends `start()` down its `changePace(false)` branch, so a 10 m fence registered seconds later was correctly detected as evaluator-owned, correctly re-aligned the cadence, and then saw **not one fix in the following minute** because the engine had never been running. Going stationary now keeps the stream while such a fence is registered, and registering one while already stationary starts it; with no such fence, stationary still stops the engine and #319's battery saving is untouched ([#357](https://github.com/Ikolvi/Tracelet/issues/357)).

**FIX**: a geofence crossing that could not be delivered to the headless task was dropped in silence — the worst possible failure for this event. The crossing is evaluated, logged on the lifecycle channel and persisted natively *before* delivery, so a bug report showed the fence working perfectly while the app never heard about it, and `dispatchEvent`'s own trace line never appeared because the registration guard at each call site meant the call was never made. Those guards are now one `dispatchToHeadless` helper that reports the drop and names the cause ([#358](https://github.com/Ikolvi/Tracelet/issues/358)).

**FIX**: geofence crossings (and every other event) stopped reaching the registered headless task once any headless engine had run in that process — so a killed-app crossing was logged, persisted and synced natively but never surfaced to the app. `EventDispatcher` decides "can a Flutter engine receive this?" by whether its Pigeon `eventApi` is non-null, and the plugin called `register()` for *every* attaching engine, including headless background isolates, adding each to the event fan-out. From then on each event took the engine branch and was posted into an isolate that has no `onGeofence` listener — the headless task receives events through `HeadlessTaskService.dispatchEvent`, a different channel — so `headlessFallback` never ran and the event was silently dropped. One transient headless engine, spawned for something unrelated like a custom sync body, was enough to swallow every crossing for the rest of the process. Secondary engines are now told apart by `HeadlessTaskService.isSpawningHeadlessEngine`, the flag already wrapped around the `FlutterEngine` constructor that triggers the attach: an in-process UI engine (EngineGroup, e.g. an overlay) still joins the fan-out, while a headless engine is kept out of it. The attach *thread* cannot make this call even though it looks like it can — Flutter requires `FlutterEngine` to be constructed on the main looper, so a headless spawn attaches from the main thread too and a thread check silently classifies it as a UI engine. The decision is recorded on the always-on lifecycle channel: it selects who delivers every subsequent event, it is taken in the killed state, and its failure mode is silence — so a DEBUG line would have been dropped by exactly the release build whose report needs it ([#358](https://github.com/Ikolvi/Tracelet/issues/358)).

**FIX**: a geofence the OS cannot resolve no longer goes quiet once the app is killed. #319 throttles the location engine to stationary-periodic when the committed motion state is stationary, on the premise that nothing needs the continuous stream while the device is still — and `switchToStationaryPeriodic` calls `engine.stop()`. A sub-100 m fence or a polygon breaks that premise: since the in-app evaluator took them over it is decided *from* that stream, so the throttle silenced exactly the fences that depend on it, seconds after the app was swiped away. The reconcile now leaves the stream alone when such a fence is registered. Separately, the inflated 100 m OS registration added as a wake-up was not actually being used as one — its transitions were discarded (correctly, since they describe the wrong boundary) without acting on their arrival, so the wake-up woke nothing. Coming near an in-app-evaluated fence now resumes continuous tracking before the transition is dropped, which is what lets a killed app recover a stream that doze or an OEM has stopped ([#355](https://github.com/Ikolvi/Tracelet/issues/355)).

**FEAT**: geofences smaller than the OS can resolve are now supported rather than merely warned about. Play Services and CoreLocation both need a radius of roughly 100 m — below that the fence is smaller than the error of the fixes it is compared against, so neither ever becomes confident enough to report a crossing. A fence under that radius is now owned by the in-app evaluator instead: it is decided against its *true* radius, the OS region is registered at 100 m purely as a wake-up, and the OS's own transitions for it are discarded because they describe the wrong boundary. Three changes make that decidable. The exit-hysteresis band now tracks the **measured** fix accuracy — clamped to 3–20 m — instead of a flat 20 m floor, so a 10 m fence on a 4 m-accurate handset needs ~8 m of travel to EXIT rather than ~28 m; the flat floor is kept only for fixes that report no accuracy at all, where there is nothing to measure. Repeated fixes of the same spot are combined by inverse-variance weighting into a tighter estimate (`accuracy / sqrt(n)`), discarded the moment the device demonstrably moves so the average never lags a walking user. And ownership is decided per fence, so a 20 m fence and a 500 m fence in one config are each handled by whichever component can actually resolve them. **Polygons are covered by the same change**: CoreLocation and Play Services only monitor circles, so a polygon was always the SDK's to evaluate, but it was only ever evaluated when `geofenceModeHighAccuracy` happened to be on — at default settings a polygon geofence silently never fired. Note the cost: a fence the OS cannot serve needs the location stream (and on Android its foreground service) running, which an OS-resolvable fence does not ([#355](https://github.com/Ikolvi/Tracelet/issues/355)).

**FIX**: a device carried while walking is no longer declared stationary. Accelerometer stillness was tested with `|‖a‖ - g|`, a scalar that cannot see a vector which is *rotating* rather than growing: a phone held or pocketed at a tilt keeps a norm within a few hundredths of g while walking, so sample after sample scored as still, the 25-sample streak completed, and the stop-timeout turned a moving user stationary a minute later. The field trace shows it directly — `raw=[-0.42, 6.35, 7.24]` has a norm of 9.64, a deviation of 0.17 against a 0.4 threshold, on a device that was demonstrably in motion. Stillness now additionally requires the acceleration *vector* to be steady between samples, which a resting device satisfies at any orientation and a carried one does not ([#357](https://github.com/Ikolvi/Tracelet/issues/357)).

**FIX**: a circular geofence whose radius the platform cannot resolve now records how it will be handled instead of failing silently. Registering while inside fires an immediate ENTER from the initial trigger, so the fence looks live, and then no crossing is ever reported again — a field report of "ENTER fires once, EXIT never" came from exactly this. A note is now written on the always-on lifecycle channel, so it reaches a release-build bug report. Superseded in part by the in-app evaluator above, which makes these fences work rather than merely explain themselves ([#355](https://github.com/Ikolvi/Tracelet/issues/355)).

**FIX**: `notifyOnEntry`, `notifyOnExit`, `notifyOnDwell` and `loiteringDelay` are now persisted with the geofence. The `geofences` table has had these columns all along but never wrote or read them, so every fence rebuilt from the database — on each proximity change, reboot, task removal and killed-state relaunch — came back with `notifyOnDwell` false and `loiteringDelay` zero. **DWELL therefore stopped working permanently after the first restore**, and an explicitly configured `notifyOnExit: false` was silently reverted. No migration is needed: rows written before this carry the column defaults, which is the historical behaviour ([#355](https://github.com/Ikolvi/Tracelet/issues/355)).

**FIX**: geofence ENTER/EXIT no longer stop firing when the location filter tightens. In standard (OS) geofence mode the SDK detects nothing itself — Play Services does — so *which* fences are registered with it is the entire feature, and `GeofenceManager.updateProximity()` is what registers them. It rode the persistence-filtered location stream, firing only for fixes the Rust `LocationProcessor` accepted, so the filter silently decided whether geofencing worked at all. 3.8.0's transport-mode auto-tune (#299) made that fatal: a committed `still` mode retunes `maxImpliedSpeed` to 3 m/s and `trackingAccuracy` to 15 m, so the moment the device starts moving every fix is rejected — registration freezes, fences coming into `geofenceProximityRadius` are never registered, and no crossing is ever reported again. This is the same starvation #297 fixed for crossing *detection*; proximity *scope* was left behind. Both geofence duties now ride the raw stream on `start()`, `startGeofences()` and the boot/task-removal path (which had never received the #297 fix, so even high-accuracy crossings were filter-gated there, and `geofenceModeHighAccuracy` was not propagated to the boot engine). Trip waypoints stay on the filtered stream, and persistence volume is unchanged ([#352](https://github.com/Ikolvi/Tracelet/issues/352)).

**FIX**: geofences added alongside continuous tracking — via `addGeofence()`/`addGeofences()`, not `startGeofences()` — are no longer unregistered from Play Services on task removal and left unrestored after a reboot. Those calls never set `trackingMode = GEOFENCES` (that mode is only the dedicated geofence-only session `startGeofences()` starts), but `destroyAll()` only kept `GeofenceManager` alive when `trackingMode == GEOFENCES` — even with `stopOnTerminate: false` — and `startBootTracking()` only called `reRegisterAll()` for that same mode. A `start()` (continuous) session with standalone geofences therefore had every fence unregistered on the very first task removal, with nothing ever re-registering them: continuous tracking kept working, so the geofence feature could die silently. Both paths now key off the same `keepAlive`/no-op-when-empty logic every other subsystem uses, regardless of tracking mode, and the destroy/restore decisions are logged through the always-on `lifecycle` channel added in #318 so a release-build Doctor bug report can show them ([#353](https://github.com/Ikolvi/Tracelet/issues/353)).

## 3.8.1

**FIX**: the speed-motion state machine no longer reports STATIONARY from a filtered 0 m/s fix or treats an unavailable GPS speed as standing still, and no longer double-emits a no-op transition ([#332](https://github.com/Ikolvi/Tracelet/issues/332), [#333](https://github.com/Ikolvi/Tracelet/issues/333), [#334](https://github.com/Ikolvi/Tracelet/issues/334), [#337](https://github.com/Ikolvi/Tracelet/issues/337)).

**FIX**: a near-zero time delta between fixes no longer derives an implausible fallback speed that wakes a parked device ([#342](https://github.com/Ikolvi/Tracelet/issues/342)).

**FIX**: `start(isMoving: false)` no longer permanently deafens the SMART motion coordinator to the accelerometer ([#344](https://github.com/Ikolvi/Tracelet/issues/344)).

**FIX**: transport-mode auto-tuning no longer overrides an explicitly configured `distanceFilter: 0` ([#346](https://github.com/Ikolvi/Tracelet/issues/346)).

**FIX**: only a *resumed* session inherits the previous session's speed-motion pace ([#348](https://github.com/Ikolvi/Tracelet/issues/348)).

**FIX**: every HTTP sync — not just the debounced auto-sync — now reports which body it posted on the always-on lifecycle channel ([#340](https://github.com/Ikolvi/Tracelet/issues/340)).

## 3.8.0

**FIX**: (Android) killed-state tracking no longer keeps running continuous GPS after the motion subsystems settle back to stationary. The engine's mode is switched only from a motion *transition*, but `MotionDetector.onManualPaceChange()` swaps its sensor set between the shake/significant-motion and stillness configurations directly, without routing through `declareStationary()` — so no transition is emitted, and the engine stays continuous for the rest of the process lifetime with the OS location indicator pinned on and fixes landing every couple of seconds. A field report showed a single `isMoving=true` transition followed by 87 s of a demonstrably still device (peak 0.02 g against a 2.0 g threshold) still persisting continuous fixes, with the detector already back in its stationary configuration. `startBootTracking()` reconciled this once at bootstrap, which is why it only appeared mid-session — and why reopening the app showed a stationary pace while the location indicator stayed on. The reconciliation now runs on every heartbeat, so a missed transition costs one interval instead of the session, and the correction is recorded as a lifecycle entry ([#319](https://github.com/Ikolvi/Tracelet/issues/319)).

**FIX**: (Android) the per-sample `[SHAKE]` accelerometer trace moved from `debug` to `verbose`. Every persisted line is a SQLite insert sharing one row cap with everything else, so at `debug` this single statement dominated the log — a device sampling at ~200 Hz emitted ~4 lines/s, turning the entire 2000-row table over about every 8 minutes. The database never grew (the cap held) but the retention window collapsed from the configured 3 days to minutes, evicting the background events the developer turned logging up to investigate. Turning logging up must not destroy the evidence ([#319](https://github.com/Ikolvi/Tracelet/issues/319)).

**FEAT**: (Android) background and killed-state diagnostics are now persisted to the log table regardless of `logLevel`. The entries that explain a background failure — motion-state transitions on both the in-app and killed-state paths, service start/stop and sticky restarts, and boot/task-removal bootstrap outcomes — were all written at `debug`, so the default level dropped them: a Flutter app (default `info`) had a populated log table containing none of the answers, and a direct native SDK consumer (default `off`) had nothing at all. They now go through a curated, low-frequency **lifecycle** channel that bypasses the level gate, and entries recorded before the database is open are buffered and flushed once it is — so a bootstrap that never completed still leaves a trail. Retention is unchanged and already bounded on two axes (a row cap from the configured level, plus `logMaxDays`), so worst-case database size does not move. Ordinary `debug`/`verbose` logging stays gated by `logLevel` exactly as before ([#318](https://github.com/Ikolvi/Tracelet/issues/318)).

**FIX**: a crash ML model whose declared feature names the SDK cannot supply is now **rejected at load** instead of loading into a state that silently disables crash detection. The hosts map declared names through a lookup that defaults misses to `0.0`, so a model trained on other names scored an all-zero feature vector on every window — and because a probability of `0.0` still satisfies `crashProba >= 0`, the detector stayed in ML *Replace* mode and never fell back to the g-threshold rule. Crash detection was dead while the SDK reported the model ready. A model declaring no features at all (previously allowed through by a `serde` default) is rejected for the same reason ([#309](https://github.com/Ikolvi/Tracelet/issues/309)).

**FIX**: the crash model's `peak_g`, `mean_g` and `gyro_peak_dps` are aggregated over the same ~16 s window the model was trained on. They were taken from the single 1 s window being scored while `speed_max`/`dv` already used a 16 s history, so the feature vector straddled two time bases and none of it matched training — `mean_g` worst of all, since the mean over a 1 s window containing a spike is nothing like the mean over 16 s of driving. Detection still evaluates once a second; only the features widen ([#310](https://github.com/Ikolvi/Tracelet/issues/310)).

**FIX**: (iOS) the loaded crash model is no longer read and written across threads without synchronization. It was written from the loader's background queue and read from the main run loop — an unsynchronized cross-thread ARC retain/release on a class reference, a crash risk rather than merely a stale read. Android already guarded the same field with `@Volatile` ([#311](https://github.com/Ikolvi/Tracelet/issues/311)).

**FIX**: the crash speed gate uses the **pre-impact** speed rather than the latest fix. A collision collapses speed within 1–2 s against ~1 Hz GPS and 1 Hz accelerometer windows, so a post-impact fix could land before the impact window was scored, dropping the reported speed below `crashMinSpeedKmh` and failing the gate that both the rule and the ML path sit behind — losing the crash. The on-foot fall context derives from the same value so the two branches stay coherent ([#312](https://github.com/Ikolvi/Tracelet/issues/312)).

**FIX**: `getTelematicsEvents()` returns the **most recent** events, regardless of sync state. It shared the sync batcher's query (`WHERE synced = 0 ORDER BY id ASC`), so it returned the *oldest* events rather than the newest and emptied out entirely once `syncTelematics` was enabled — contradicting both its own documentation and the Doctor's "most recent" bug-report section. Sync keeps the original query; the history API has its own ([#313](https://github.com/Ikolvi/Tracelet/issues/313)).

**FIX**: the encrypted crash-model cache is keyed by model URL, so repointing `crashModelUrl` invalidates it even when the optional `crashModelSha256` is absent — previously one fixed filename meant the old blob was loaded forever. On iOS the cache directory (`Library/Application Support`, which iOS does not create by default) is now created before writing, and a failed write is logged rather than swallowed; the model was silently re-downloaded on every `ready()` and behaviour-config `setConfig()` ([#314](https://github.com/Ikolvi/Tracelet/issues/314)).

**FIX**: standard (low-power) geofence-only tracking no longer restores as **continuous** tracking after a reboot, a task removal, or a killed-state relaunch. Every restore path started the full location engine regardless of `geofenceModeHighAccuracy`, so a geofence-only app silently converted to continuous GPS for the rest of the process lifetime — on iOS bringing back the persistent blue location indicator that #210 removed, and on Android running a foreground service *solely* for geofencing, which Google Play prohibits as of 2026-10-28. The restore paths now branch on `geofenceModeHighAccuracy` exactly as `startGeofences()` does. On Android the boot service still starts long enough to re-register the fences (Play Services clears them on reboot) and then stands itself down ([#316](https://github.com/Ikolvi/Tracelet/issues/316)).

**FIX**: (Android) boot and task-removal tracking retries with backoff when the SDK cannot bootstrap, instead of returning and never trying again. `START_STICKY` only redelivers after the process is killed, and the service is alive at that point — it just returned early — so nothing called it again short of the user reopening the app, while the foreground notification advertised an active session that was tracking nothing. After the retries are exhausted the service stops rather than leaving that notification standing ([#317](https://github.com/Ikolvi/Tracelet/issues/317)).

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