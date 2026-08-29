## 3.8.8

**FEAT**: `getCurrentPosition` accepts a horizontal `accuracyTarget` and caller-owned `requestId`; `cancelCurrentPosition` stops an active native one-shot. Targeted requests converge on quality rather than treating a fixed sample count as equivalent.

**FIX**: (Android, iOS) the parked-device GPS drain had two further causes, and on iOS a report could not show either. When the GPS-speed machine reports stationary while the accelerometer still reports motion, the SDK settles the disagreement with the last resolved speed: near zero means the accelerometer is reading hand tremor on a still device, and it is overruled. That override is itself a motion transition, and whenever the speed input was already stationary it is the one carrying the whole stop decision — it was computed and then discarded, and the speed transition behind it then changed nothing, so the stream was never told. The speed input reaches that stale state on its own: it lives for the whole process, and only a session *starting stationary* re-asserted it, so any session that parked handed the next started-moving one a value it could never clear — leaving that session's continuous GPS hanging on the accelerometer alone. On iOS the transition was also invisible: the motion pipeline parks by stopping location updates without ending the session, which never runs the code that records `location stream: continuous updates stopping`, so a released app's report could not say when — or whether — GPS was parked, the one line an Android report has always carried. And iOS decided whether a stream was live from a flag that stays true on a parked engine, which could wedge the same belief in the opposite direction and swallow the next wake-up ([#409](https://github.com/Ikolvi/Tracelet/issues/409)).

**FIX**: (Android, iOS) a session that resumed stationary while a location stream was still running never stopped it — continuous GPS ran for the rest of the session on a device the SDK correctly reported as parked. The SMART coordinator holds a *posture* (is the engine streaming, or is it in a stationary schedule), and the core only emits the stop action when it believes that posture is continuous. `syncCurrentMode()` read the posture from the committed pace alone, so a `ready()` takeover with `isMoving = false` over a live stream wrote "parked" into a coordinator whose engine was streaming, and every later stationary decision produced nothing. The reported device held a 2-second GPS stream open for six unbroken minutes, every fix `is_moving: false`, while lying on a desk — the pace was right the whole time, only the stream was never told. The posture is now the OR of the committed pace and the engine's actual state, which is the only reading that survives this and the opposite wedge in #344 ([#409](https://github.com/Ikolvi/Tracelet/issues/409)).

**FIX**: (Android) boot-mode tracking no longer builds a second `LocationEngine` beside a live session engine. Task removal tears down the Flutter engine but deliberately keeps the SDK, so the session engine, its motion detector and its heartbeat all survive — and boot mode used to start a full second set beside them. Two streams then ran in parallel with separate fix caches, and a stationary switch stopped only the engine its own coordinator held: the reported device had the boot engine parked on a 5.7-minute-stale fix while the other streamed at 2 s. Boot mode exists for a process with no session left to do the work — a cold boot, or a sticky restart after process death — and it now checks for one before starting anything ([#410](https://github.com/Ikolvi/Tracelet/issues/410)).

**FIX**: (Android) background tracking could stop dead while every diagnostic said it was healthy, and the SDK now names the three reasons. Android 12+ decides whether a foreground service may use location when the *service record is created* — at `startService()`, not at `startForeground()` — and keeps that verdict for the life of the record. A service started from a background trigger (a reboot, an alarm, a geofence, a sticky restart) therefore posts its notification, reports itself promoted, carries `FOREGROUND_SERVICE_TYPE_LOCATION`, and is handed no location at all: GPS never starts, the status-bar location indicator never appears, and not one fix arrives until the app is reopened. `getForegroundServiceHealth()` gains `serviceStartedInForeground` and `locationCapabilityLikelyDenied`, which separate "promoted" from "promoted and able to track" — a distinction nothing in the API could previously express ([#405](https://github.com/Ikolvi/Tracelet/issues/405)). It also gains `backgroundRestricted`, `standbyBucket` and `standbyBucketName`: the "Restricted" battery state is independent of the battery-optimization exemption the health check already reported, and stronger — it blocks the promotion outright — so a device could report `isIgnoringBatteryOptimizations: true` and refuse to run in the background at the same time ([#406](https://github.com/Ikolvi/Tracelet/issues/406)). And the stall watchdog runs on its own timer instead of waiting for a fix to arrive, so a stream delivering *nothing* — the case where the SDK was completely blind — announces itself after 45s with the request it is complaining about, and announces its recovery. Silence and rejection are reported as different faults because they are: one means the pipeline is alive and mis-tuned, the other means the OS has stopped talking to the app ([#407](https://github.com/Ikolvi/Tracelet/issues/407)). All of it is on the always-on lifecycle channel, so a **release** build reports it. Not yet fixed: keeping the service record out of the background in the first place, and recovering once it is there.

**FEAT**: (Android, iOS) trips have an identity, and the records made during them carry it. The SDK mints a UUIDv4 when a trip starts, keeps it for the trip's lifetime, and discards it at the end, so an id is never handed to a second journey. It is written into the new `trip_id` column on locations and driving events **at insert time**, which is what makes an offline backlog correct: a row recorded during one trip still uploads as that trip's even when a different trip is running by the time the flush happens, where resolving it at sync time would silently reassign the whole queue. The default sync payload gains a `trip_id` field on each location and telematics record — present as an explicit `null` outside a trip, so the key can be relied on — and nothing else is renamed or moved. `Tracelet.onTripStart` is new: a trip previously only became observable once it had *ended*, so an app that wanted to group records by trip had to re-derive the boundary from `onMotionChange` and would drift from the SDK's own detection. `Tracelet.currentTripId` reports the trip in force right now, so app-side data can be tagged with the same key. `TripEvent` gains `tripId` plus absolute `startedAt`/`endedAt` bounds — `duration` alone could not place a trip on a timeline. Additive throughout: the new fields are nullable and read `null` for trips and rows from before this version ([#402](https://github.com/Ikolvi/Tracelet/issues/402)).

## 3.8.7

**FIX**: (Android, iOS) the events that explain a background tracking failure are recorded on the always-on lifecycle channel, so a **release** build can report them. A released app runs at the default `logLevel`, where every `debug` line is discarded — which is why diagnosing the last round took repeated captures and a source read rather than one report. Now recorded regardless of level, and all per-session rather than per-fix: the continuous location stream starting and stopping (the transition the OS location indicator follows, so "the icon disappeared" is answerable); the app moving to background and to foreground — iOS never observed the background edge at all, so a report could show the app coming back but never leaving; foreground-service promotion and demotion, naming the demotion window in which a task removal is fatal; a pace machine refused a stale fix's speed, and the moment it gets a current one again; and a session start that declined to seed the pace machine because no fix had been resolved yet. The stale-fix lines are emitted once per run rather than once per fix, so a long run of them costs one line.

**FIX**: (Android, iOS) a stale cached fix can no longer stand a session down the moment it wakes. Both platforms deliver a cached last-known fix as soon as location updates restart, carrying the speed from whenever it was taken — which, on a session the accelerometer has just woken, is from before the device stopped. The field trace shows the wake and the stand-down in the same second: `speed-motion: STATIONARY -> MOVING — manual pace change` immediately followed by `MOVING -> SLOWING — speed=0.10 m/s`, then STATIONARY again 30 s later. Walking with the app backgrounded or killed therefore produced a cycle — the accelerometer wakes the stream, a stale reading stands it down, the stream stops — rather than tracking, with the location indicator flickering off and staying off. Only a fix less than ten seconds old may now drive the pace machine. Persistence and dispatch are untouched: a cached fix is still a real position, and the processor's own gates decide whether to keep it; it is only its *speed* that says nothing about the present.

**FIX**: (Android, iOS) tracking survives being backgrounded or killed while moving. On startup the speed state machine was seeded with `LocationEngine.lastEffectiveSpeed`, which is `0.0` on a process that has not yet handled a fix — exactly the state a killed-state relaunch or a background takeover begins in. A session that had just resumed as MOVING was therefore told it was stopped: it dropped to SLOWING immediately and, `speedStationaryDelay` later, to STATIONARY, which switches off the continuous stream. The device had not moved differently and nothing else had changed; the location indicator simply disappeared shortly after the app left the screen. A field trace shows it twice in one minute — `boot-tracking: bootstrapping … speedState=MOVING` followed within the same second by `MOVING -> SLOWING — speed=0.00 m/s`, and 30 s later `SLOWING -> STATIONARY — countdown expired`. `0.0` means "no speed reported", not "stopped", so the machine is now seeded only when this process has actually resolved a speed. The same fabricated zero is gone from the periodic-fix path, which fed `0.0` into the machine whenever a periodic fix arrived without a speed.

**FIX**: (Android, iOS) a walking user is no longer classified as stationary. `MotionConfig.speedMovingThreshold` defaulted to 1.5 m/s — *above* an average walking pace of ~1.4 m/s — and a single threshold governed both directions with no band between them, so an ordinary walk straddled it: wake at 1.50-1.55 m/s, drop to SLOWING a second later at 1.31-1.48, run the countdown to STATIONARY with 26-28 consecutive fixes just below, wake again. Reaching STATIONARY switches the session to periodic fixes, which is what a walking user reports as "tracking stopped on its own". The entry threshold is now 0.9 m/s, comfortably below a slow walk and well above the 0.1-0.3 m/s a parked device reports from GPS noise, and leaving MOVING uses a separate, lower threshold — the new `MotionConfig.speedStationaryThreshold`, defaulting to 65 % of the entry one and clamped to it if set higher. The gap between the two is a hysteresis band, so a pace that varies either side of the entry threshold no longer oscillates. Both values are configurable; apps that tuned `speedMovingThreshold` themselves are unaffected.

**FIX**: (Android) a stationary session that declines a wake can still be woken by the next one. `TYPE_SIGNIFICANT_MOTION` is a one-shot trigger sensor — firing consumes the registration — and the wake path tore down both wake sources before asking the motion coordinator what to do with the event. When the coordinator declined it (returning no action, leaving the session stationary), nothing re-armed either one: significant motion was consumed, shake monitoring had been stopped, and the accelerometer had been switched to stillness detection, which by construction only notices the device *stopping*. In the foreground that self-heals, because the CPU stays awake and a later shake or periodic fix rescues it; backgrounded it does not, since `TYPE_ACCELEROMETER` is a non-wakeup sensor and delivers nothing while the device is suspended. The session stayed stationary until tracking was restarted by hand. A declined wake now restores stationary monitoring, re-arming both sources, and says so on the lifecycle channel.

**FIX**: (Android, iOS) tracking no longer freezes mid-walk and then jumps. Three faults compounded into one failure. The battery-budget engine measured drain from a single pair of battery-level readings five minutes apart — a level iOS reports in 5 % steps — so one reporting step read as 60 %/hr against a 3 %/hr budget and throttled a device that was draining normally. It throttled by writing its output into your live configuration, where `distanceFilter: 0` (the documented "record every fix" opt-out) multiplied to 0 and was clamped *up* to 10 m: the processor's protection for a configured zero reads the base tuning that write had just replaced, nothing could ever restore it, and `Tracelet.activeConfig` began reporting a configuration you had never set. With a distance gate now in play, adaptive sampling multiplied it by an unbounded activity and battery factor — 750 m for a `Still` classification below 50 % battery — and because the processor's anchor advances only on an *accepted* fix, once nothing was accepted nothing could be. Four minutes of walking produced 59 rejections, zero locations and a frozen odometer. The jump was the same bug's second act: the implied-speed guard divides by the anchor's age, so a 1.65 km cell fix arriving 196 s later reads as 8.4 m/s and clears any ceiling meant for a car. Now: drain is measured over at least 15 minutes and discounted by one reporting step, so a figure only counts when it beats the budget by more than the measurement can resolve; throttling is a bounded five-rung ladder applied as an overlay that never touches your configuration, moves one rung per two consecutive conclusive windows, throttles sampling cadence before accuracy, relaxes the tracking accuracy gate whenever it does coarsen accuracy, and drops to zero on a charger; adaptive sampling may only *delay* a fix, with anything clearing the un-inflated `distanceFilter` admitted after 60 s — which leaves a genuinely parked device silent, since its jitter never clears that filter; and the implied-speed guard measures from the last fix the processor *observed* rather than the last one it accepted, which turns that same 8.4 m/s jump into 51 m/s. When nothing has been observed at all the anchor is re-seeded: the position is taken, but the span contributes no odometer distance and no derived speed ([#393](https://github.com/Ikolvi/Tracelet/issues/393), [#394](https://github.com/Ikolvi/Tracelet/issues/394), [#395](https://github.com/Ikolvi/Tracelet/issues/395), [#396](https://github.com/Ikolvi/Tracelet/issues/396)).

**FIX**: (Android, iOS) a released app can report a stalled location stream. Everything explaining one was logged at `debug`, which Flutter's default `info` — and a direct SDK consumer's default `off` — discards, so the bug report contained none of it; and the rejection line named only a reason and a speed, leaving an 8 m distance gate and an inflated 750 m one indistinguishable in a log. Stalls, recoveries, battery-budget throttle movements, idle-escape admissions and anchor re-seeds now go to the always-on lifecycle channel that bypasses `logLevel` (the #318 mechanism), staying affordable because all of them are per-session rather than per-fix events. The per-fix rejection line keeps its level and its frequency but now carries the accuracy, the distance moved, the effective gate, the anchor age and the thresholds in force ([#397](https://github.com/Ikolvi/Tracelet/issues/397)).

**FIX**: (Dart) the Doctor bug report says which Tracelet produced it. The report opened with a generation timestamp and, optionally, the host app's own version, so triage began by asking — and a report pasted into an issue weeks later could not answer at all. `traceletVersion` is now exported from `package:tracelet` and kept in lockstep with the pubspec by the release hook, and the report header carries it. The report also gained a **Location stream health** section: stalls, recoveries and throttle movements lifted out of the general log, each stall line carrying the rejection histogram, the gate the last fix was measured against, the configured gate beside it and the thresholds in force ([#398](https://github.com/Ikolvi/Tracelet/issues/398)).

## 3.8.6

**FIX**: (iOS) an app with Swift Package Manager disabled links again. Flutter installs plugins as `:path` pods, and the published podspecs pointed `s.source :http` at the GitHub Release zips — a source CocoaPods never downloads for path pods, so `TraceletCore.xcframework` / `TraceletSyncFFI.xcframework` were simply absent and the build failed at `ld` with hundreds of undefined UniFFI symbols. The podspecs now fetch and checksum their own binary during evaluation, and each links the framework it vendors, which CocoaPods does only for a *dependency's* vendored frameworks ([#390](https://github.com/Ikolvi/Tracelet/issues/390)).

## 3.8.5

**FIX**: (Android, iOS, web) `Tracelet.setOdometer()` moves the reference the odometer measures from, not just the total. Distance is accumulated from an anchor held by the location processor, and setting the odometer wrote the counter alone — so the next accepted fix immediately added the whole span since the previous one and the value you had just set survived exactly one fix. The everyday form is "reset to zero, then start tracking": the trip began with however far the device had been carried while it was not being tracked. Only the odometer anchor is cleared, never the tracking one — that decides whether the next fix clears `distanceFilter`, so setting a counter must not quietly change which locations are recorded. All three platforms had the defect independently ([#387](https://github.com/Ikolvi/Tracelet/issues/387)).

**FIX**: (Android, iOS) a session that starts stationary now acquires its first location. `motion.isMoving` defaults to `false`, so `start()` took its stationary branch — and that branch acquired nothing at all: no continuous stream (by design), and in SMART mode no stationary schedule either, because the coordinator's posture is synced from the pace just committed and its inputs are only then pushed to stationary, so it reports no mode change and arms nothing. The only one-shot in the engine was fired from a stationary → moving *transition*, which a session that begins stationary never takes. An app could call `start()`, leave the device on a desk, and never receive a single `onLocation` — the workaround being handed out, `motion: MotionConfig(isMoving: true)`, bought that first fix with a full-rate GPS stream nobody asked for. `start()` now takes one fix and routes it through the ordinary pipeline, so it is filtered, odometer-counted, persisted under your `persistMode` and dispatched like any other location, while the pace you asked to start in is left alone. It is skipped when a stream is already running (a moving start, or the in-app-evaluated geofence branch of a stationary one) and on resume, so the killed-state relaunch path is unchanged. The anchor contributes only a *measured* speed: both platforms and the Rust processor derive speed from their own last fix when the platform reports none, and `stop()` clears neither, so a device carried between two sessions in one process would otherwise derive a credible-looking speed and wake a session you explicitly asked to begin stationary. A real Doppler reading still counts, so a device that genuinely is moving at a stationary start is detected on that same fix. The fix that later wakes the session — whether from `changePace(true)` or from the accelerometer — is still delivered too: it sits within `distanceFilter` of the anchor and would otherwise be dropped as a duplicate, so being told you are moving would come with no position to go with it. This behaviour existed until 3.2.0, which replaced an unconditional acquisition with the pace branch and left only the ongoing feed behind ([#385](https://github.com/Ikolvi/Tracelet/issues/385)).

**FIX**: (Android, iOS) `PersistenceConfig.persistMode` is applied to geofence ENTER/EXIT records. It only ever gated ordinary GPS fixes, so `persistMode: 'location'` and `persistMode: 'none'` still wrote every fence crossing to the local database and uploaded it in the next HTTP batch — an app that chose `none` precisely to get geofence callbacks without the SDK retaining a location history was accumulating a record of every fence it crossed, with nothing in the logs to say so. Crossings are now persisted only under `all` and `geofence`. Your `onGeofence` listener is unaffected in every mode: only the database write is gated, so `none` keeps its documented behaviour of firing events without storing anything. The mode is read at the moment of each crossing, so a mid-session `setConfig` applies to the next one ([#383](https://github.com/Ikolvi/Tracelet/issues/383)).

## 3.8.4

**FEAT**: (Android, iOS) the tracking notification and the Live Activity can show a self-ticking elapsed timer, rendered by the OS rather than by rewriting the text on a timer of your own. `ForegroundServiceConfig` gains `notificationStartedAt` (epoch ms) and `notificationShowTimer`; `LiveActivityConfig` gains `startedAt` and `showTimer`; and `ForegroundServiceConfig.notificationOnlyAlertOnce` maps to Android's `setOnlyAlertOnce`, so later reposts replace the notification silently instead of replaying its sound and vibration. `startedAt` is supplied by the app rather than taken from `start()`, because the period a user cares about often began before tracking did, or survives a tracking restart. Everything here is additive — the new keys are absent unless set, so both platforms' config managers never see them and existing callers are unaffected — and updating a timer goes through the ordinary partial `setConfig`, where a `foregroundService`-only write leaves `http.url` and `http.headers` untouched ([#376](https://github.com/Ikolvi/Tracelet/issues/376)).

**FIX**: (Android) `ForegroundServiceConfig.showNotificationOnPauseOnly` no longer costs you what `AppConfig.stopOnTerminate: false` promises. Hiding the notification demotes the foreground service, and a process holding no foreground service is one Android kills when its task is removed — so swiping the app from recents in the few hundred milliseconds between it leaving the screen and the notification being re-posted killed the process, with no headless task, no events and no logs. The setting is now ignored while `stopOnTerminate` is false, and the SDK says so once on the lifecycle log channel; set `stopOnTerminate: true` if you would rather have the hidden notification. `getForegroundServiceHealth()` gains a fourth `lastForegroundPromotionResult` value, `suppressed`, for a notification hidden on purpose, and `lastForegroundTransitionAt` now stamps real state changes rather than every notification re-post ([#378](https://github.com/Ikolvi/Tracelet/issues/378)).

**FIX**: (Android) events reach the registered headless task after the UI engine detaches while another plugin's background engine keeps the process alive. With, say, firebase_messaging's background service in the app, task removal left the SDK broadcasting into a fan-out with no members at all — a silent no-op — so native tracking ran on while Dart received nothing ([#371](https://github.com/Ikolvi/Tracelet/issues/371)).

## 3.8.3

**FIX**: (Android, iOS) telematics events survive a failed sync instead of being deleted by it. With `HttpConfig.syncTelematics` enabled, an upload failure — an offline device, a refused connection — cleared the entire stored telematics table rather than leaving the events queued for the next attempt. Events are now settled only when the request carrying them actually succeeded, and only over the id range that was uploaded ([#366](https://github.com/Ikolvi/Tracelet/issues/366)).

**FIX**: (Android, iOS) `HttpConfig.syncTelematics` has an effect. The flag round-tripped through config and read back correctly from `State.config`, but the native sync path looked it up in a structure that no longer existed by the time it ran, so it evaluated false on every sync and telematics were never attached ([#370](https://github.com/Ikolvi/Tracelet/issues/370)).

**FEAT**: `TelematicsRecord` exposes `speed` and `value` — the speed at the event in m/s, and the measurement that triggered it (g for harsh driving events and impacts, km/h over the limit for speeding). `severity` remains the normalized 0–1 flag; these are the physical quantities behind it. Both reached `onDrivingEvent` already but were dropped before storage, so they were missing from stored history and from every synced payload. Nullable: they read `0` for simulated events and for rows written before the migration, and `null` only if the native side did not report the field ([#367](https://github.com/Ikolvi/Tracelet/issues/367)).

**FEAT**: `HttpConfig.telematicsUrl` works. Set it — with `syncTelematics` enabled — to POST telematics to their own endpoint as `{"telematics": [...]}` instead of attaching them to the location payload, using the same headers, timeouts, retries and SSL pinning as `url`. Previously the value was accepted, stored, and ignored. Leave it unset to keep the existing behaviour ([#368](https://github.com/Ikolvi/Tracelet/issues/368)).

**NOTE**: `syncTelematics` and `telematicsUrl` are documented for the first time; both existed and neither appeared anywhere in the docs. To stop using a separate endpoint after setting one, pass an empty string rather than `null` — config is merged, not replaced, so `null` means "leave whatever is there". Raised in [#356](https://github.com/Ikolvi/Tracelet/issues/356), which remains open for trip persistence and sync.

**FIX**: (Android, iOS, web) `maxDaysToPersist` and `maxRecordsToPersist` are enforced against the local queue again. Both were accepted by `ready()`/`setConfig()` and read back correctly in `State.config`, and then applied by nothing — no code path scoped a `DELETE` against `location_events` — so the queue grew without bound however they were set, which for an app offline for a long stretch is a storage problem rather than a correctness nitpick. The caps were real up to 3.0; `2afc926f` ("prepare for 3.1.0") migrated the persist path on both platforms off the platform-native `TraceletDatabase` classes and onto the shared Rust core, and the retention calls — which lived in the same function body and hung off the same `db` object — were deleted along with it, with no equivalent added to the core to point them at. The amortization counter, its constant and a docstring claiming the function "also runs retention pruning" all survived, which is why the gap read as implemented ([#361](https://github.com/Ikolvi/Tracelet/issues/361)).

**BREAKING**: `PersistenceConfig.maxDaysToPersist` now defaults to `3` days rather than `1`. The default has always been documented as `1`, but with nothing enforcing it the value never mattered; switching a one-day window on unannounced would have had an app offline over a weekend lose everything but its last day. `3` matches `logMaxDays`. Pass `-1` to retain indefinitely and rely on `maxRecordsToPersist` alone, or set `1` to keep the previously documented figure ([#361](https://github.com/Ikolvi/Tracelet/issues/361)).

**NOTE**: pruning is amortized over 100 inserts rather than run on every insert, so a `COUNT`-and-`DELETE` is not attached to every GPS fix. The queue is bounded by `maxRecordsToPersist + 100` and is cut back to the cap itself at each prune; it is a bound on growth, not a per-insert invariant. The first insert of a process prunes, so a backlog inherited from a build that never enforced the caps is cleared on the next fix ([#361](https://github.com/Ikolvi/Tracelet/issues/361)).

## 3.8.2

**FIX**: (Android, iOS) geofence ENTER/EXIT no longer stop firing when the location filter tightens. Proximity registration — which decides *which* fences the OS is watching, and so is the whole feature in standard mode — rode the persistence-filtered location stream, so 3.8.0's transport-mode auto-tune (#299) could reject every fix, freeze registration, and leave no crossing ever reported again ([#352](https://github.com/Ikolvi/Tracelet/issues/352)).

**FIX**: (Android, iOS) geofences added alongside continuous tracking with `addGeofence()`/`addGeofences()` now survive task removal and are restored after a reboot. Only a dedicated `startGeofences()` session set the tracking mode both paths keyed off, so a `start()` session with standalone fences lost every one of them on the first task removal, with nothing to re-register them — continuous tracking kept working, so the geofence feature could die silently ([#353](https://github.com/Ikolvi/Tracelet/issues/353)).

**FEAT**: (Android, iOS) geofences smaller than the ~100 m the OS can resolve are now supported instead of silently never firing. A sub-100 m circle — and any polygon, which at default settings was never evaluated at all — is now owned by the in-app evaluator and decided against its *true* radius, with the OS region registered at 100 m purely as a wake-up. Note the cost: a fence the OS cannot serve needs the location stream (and on Android its foreground service) running, which an OS-resolvable fence does not ([#355](https://github.com/Ikolvi/Tracelet/issues/355)).

**FIX**: (Android, iOS) `notifyOnEntry`, `notifyOnExit`, `notifyOnDwell` and `loiteringDelay` are now persisted with the geofence. The columns existed but were never written or read, so **DWELL stopped working permanently after the first restore** and an explicitly configured `notifyOnExit: false` was silently reverted ([#355](https://github.com/Ikolvi/Tracelet/issues/355)).

**FIX**: (Android, iOS) an in-app-evaluated geofence no longer goes quiet once the app is killed. The stationary throttle added in #319 stops the location stream on the premise that nothing needs it while the device is still — which a sub-100 m fence, decided *from* that stream, breaks ([#355](https://github.com/Ikolvi/Tracelet/issues/355)).

**FIX**: (Android, iOS) a geofence added after `start()` now gets the fix cadence it is decided from, so EXIT no longer fires late or not at all. The cadence was settled once, at `start()` — before any fence was registered, in the ordinary `start()`-then-`addGeofence()` order — and the fence set now drives it at every point it changes, including back down again when the last such fence is removed ([#357](https://github.com/Ikolvi/Tracelet/issues/357)).

**FIX**: (Android) a device carried while walking is no longer declared stationary. Accelerometer stillness was tested with a scalar that cannot see a vector which is *rotating* rather than growing, so a phone held or pocketed at a tilt scored as still and the stop timeout ended the session a minute later ([#357](https://github.com/Ikolvi/Tracelet/issues/357)).

**FIX**: (Android) geofence crossings reach the registered headless task again. A headless engine spawned for anything else — a custom sync body, say — joined the event fan-out and swallowed every subsequent crossing for the rest of the process: evaluated, logged, persisted and synced natively, but never delivered to the app, and dropped in silence ([#358](https://github.com/Ikolvi/Tracelet/issues/358)).

## 3.8.1

**FIX**: (Android) a headless task after task removal could silently never fire — the engine spawn now retries and reports failures instead of stalling forever ([#331](https://github.com/Ikolvi/Tracelet/issues/331)).

**FIX**: (iOS) a registered custom sync body builder is now honored on every path — a background relaunch no longer silently posts the SDK's default payload instead of it ([#340](https://github.com/Ikolvi/Tracelet/issues/340)).

**FIX**: (Android, iOS) the speed-motion state machine no longer reports STATIONARY from a filtered 0 m/s fix, treats an unavailable GPS speed as standing still, or double-emits a transition ([#332](https://github.com/Ikolvi/Tracelet/issues/332), [#333](https://github.com/Ikolvi/Tracelet/issues/333), [#334](https://github.com/Ikolvi/Tracelet/issues/334), [#335](https://github.com/Ikolvi/Tracelet/issues/335), [#337](https://github.com/Ikolvi/Tracelet/issues/337)).

**FIX**: (Android, iOS) a near-zero time delta between fixes no longer derives an implausible fallback speed that wakes a parked device ([#342](https://github.com/Ikolvi/Tracelet/issues/342)).

**FIX**: (Android, iOS) `start(isMoving: false)` no longer permanently deafens the SMART motion coordinator to the accelerometer ([#344](https://github.com/Ikolvi/Tracelet/issues/344)).

**FIX**: transport-mode auto-tuning no longer overrides an explicitly configured `distanceFilter: 0` ([#346](https://github.com/Ikolvi/Tracelet/issues/346)).

**FIX**: (Android, iOS) only a *resumed* session inherits the previous session's speed-motion pace ([#348](https://github.com/Ikolvi/Tracelet/issues/348)).

## 3.8.0

**FIX**: `Config.toMap()` omits a section entirely when it carries nothing, so `const Config().toMap()` is now empty rather than sixteen empty sub-maps. Each section was guarded with `if (geo != null)`, which is dead code — the fields are non-nullable with defaults — the same mistake already fixed one level down for `geo.filter` and `android.foregroundService`, and the analyzer had been reporting all sixteen. Nothing downstream read them (the wire format is the Pigeon `toTlConfig()`, not this; `Config.fromMap` falls back through an absent section, and `activeConfig` is a resolved config after `ready()`, so every section still carries fields), but a partial update that changes nothing should not look like it touched every section — least of all in a pasted bug report. `AttestationToken.toMap()` loses the same dead guards on `token`, `timestamp` and `provider`: a token is a result, not a partial config, and those three are never absent ([#326](https://github.com/Ikolvi/Tracelet/issues/326)).

**FIX**: the always-on **lifecycle** channel now records a tracking session's own boundaries — `session: start` and `session: stop` — on both platforms. It recorded what the background and killed-state pipelines did but never that a session began or ended, and `start()`/`stop()` log only at `info`, so at any stricter level the trail could not say the one thing that answers most "it stopped tracking overnight" reports: tracking was stopped. iOS already wrote `relaunch: declined to resume — tracking was stopped before termination`, pointing at a stop the reader had no way to see. Every entry carries the mode and the strategy the session actually ran with, which is the whole diagnosis for periodic mode (WorkManager is throttled in Doze, exact alarms are not, a foreground service is neither); Android marks `setConfig()`'s in-place restart as `restart=true` so a config change does not read as the session ending, and its `LocationService.onDestroy` moves from `debug` to the channel, so a service reclaimed by the OS is finally distinguishable from one that was never created ([#324](https://github.com/Ikolvi/Tracelet/issues/324)).

**NOTE**: this also made the #318 verification card meaningful on a repeat run. Every other emitter reachable from a foreground `start()`/`stop()` is either a one-shot per process (Android's `service: onCreate`, iOS's `relaunch:`/`termination:`) or fires only on a real motion transition — so a card that clears the log first passed once after a fresh launch and reported a regression on every run after it, with nothing wrong in the SDK ([#324](https://github.com/Ikolvi/Tracelet/issues/324)).

**FIX**: `setConfig()` is now a genuine partial update across the **whole** `Config` model, not just the foreground service. Both native merges skip fields they do not receive — Android's says so outright (*"a partial setConfig() must not overwrite existing non-null config with defaults"*) and iOS has the identical guard — but every field of the Dart model was non-nullable with a default, so `toMap()` emitted all of them and a null was never sent. Those guards were correct and unreachable, and `setConfig(const Config())` serialised a complete configuration built entirely of defaults, wrote it over everything stored — `stopOnTerminate`, `startOnBoot`, `distanceFilter`, `desiredAccuracy`, the HTTP settings, the iOS keep-alive flags — and persisted the result. iOS was worse in kind: its bridge builds one flat dictionary with no section boundaries, and the fields it reset (`showsBackgroundLocationIndicator`, `preventSuspend`, `useBackgroundActivitySession`) are the ones that keep background tracking alive, so a partial update silently degraded it. Every field now records whether it was *supplied*, separately from its value: the getters still return non-nullable values with the same defaults, so reading a config is unchanged, but `toMap()`/`toTlConfig()` omit what was never set ([#321](https://github.com/Ikolvi/Tracelet/issues/321)).

**FEAT**: `ready()` and `reset()` now send a fully **resolved** configuration — every field pinned to its effective value — while `setConfig()` sends only what the caller set. This split is what makes omission safe: the baseline is always established explicitly, so the platforms' own defaults never have to match Dart's for correctness. `Config.resolved()` and `Config.mergedWith()` are public, and `Tracelet.activeConfig` applies the same merge locally so it keeps reporting what the platform actually holds ([#321](https://github.com/Ikolvi/Tracelet/issues/321)).

**NOTE**: passing a value equal to its default is still an explicit write, so a flag can always be set back — "unset" means *not provided*, never *equal to the default*. Dropping default-valued fields would have been a cheaper fix and a worse bug, making a default unreachable once changed. The one behaviour change to be aware of: `setConfig(const Config())` used to reset everything and now changes nothing. Use `ready()` or `reset()` to replace the baseline ([#321](https://github.com/Ikolvi/Tracelet/issues/321)).

**FIX**: a partial `setConfig()` no longer overwrites the persisted foreground-service configuration with defaults. `setConfig()` merges into the configuration the platform already stored, and that merge skips fields it does not receive — but every `ForegroundServiceConfig` field was non-nullable with a default, so `Config.toMap()` emitted all of them and `const Config()` serialised a complete section built entirely of defaults. The platform could not distinguish that from a deliberate configuration, wrote it over the stored values, and persisted the result. The reported symptom was `showNotificationOnPauseOnly: true` quietly reverting, so the tracking notification appeared while the app was foregrounded; the same call also reset the title, text, channel and priority. It looked like a regression because `ready()` re-sends the full config, so a fresh install always looked correct and only a later partial `setConfig()` broke it. Each field now records whether it was *supplied*, separately from its value: the getters still return non-nullable values with the same defaults, so reading a config is unchanged, but `toMap()`/`toTlConfig()` omit fields that were never set. Passing a value equal to the default is still an explicit write, so a flag can always be set back to `false`. `Tracelet.activeConfig` applies the same merge locally, so it keeps reporting what the platform actually holds ([#320](https://github.com/Ikolvi/Tracelet/issues/320)).

**NOTE**: this covers the `foregroundService` section only. Every other section of `Config` still replaces rather than merges — `setConfig(const Config())` resets `stopOnTerminate`, `distanceFilter`, the HTTP settings and the rest to their defaults. Making the whole public `Config` model unset-aware across all four platforms is tracked as [#321](https://github.com/Ikolvi/Tracelet/issues/321).

**FIX**: (Android) killed-state tracking no longer keeps running continuous GPS after the motion subsystems settle back to stationary. The engine's mode is switched only from a motion *transition*, but `MotionDetector.onManualPaceChange()` swaps its sensor set between the shake/significant-motion and stillness configurations directly, without routing through `declareStationary()` — so no transition is emitted, and the engine stays continuous for the rest of the process lifetime with the OS location indicator pinned on and fixes landing every couple of seconds. A field report showed a single `isMoving=true` transition followed by 87 s of a demonstrably still device (peak 0.02 g against a 2.0 g threshold) still persisting continuous fixes, with the detector already back in its stationary configuration. `startBootTracking()` reconciled this once at bootstrap, which is why it only appeared mid-session — and why reopening the app showed a stationary pace while the location indicator stayed on. The reconciliation now runs on every heartbeat, so a missed transition costs one interval instead of the session, and the correction is recorded as a lifecycle entry ([#319](https://github.com/Ikolvi/Tracelet/issues/319)).

**FIX**: (Android) the per-sample `[SHAKE]` accelerometer trace moved from `debug` to `verbose`. Every persisted line is a SQLite insert sharing one row cap with everything else, so at `debug` this single statement dominated the log — a device sampling at ~200 Hz emitted ~4 lines/s, turning the entire 2000-row table over about every 8 minutes. The database never grew (the cap held) but the retention window collapsed from the configured 3 days to minutes, evicting the background events the developer turned logging up to investigate. Turning logging up must not destroy the evidence ([#319](https://github.com/Ikolvi/Tracelet/issues/319)).

**FIX**: (iOS) the engine is re-aligned with the committed motion state on every heartbeat, matching the Android reconciliation. iOS has no reproduction of the Android trigger and is less exposed to it — `CMMotionActivityManager` runs continuously regardless of tracking mode, so there is no `onManualPaceChange` equivalent — but the failure class is identical and silent: the persisted state reads stationary while the engine keeps running continuous updates, costing battery for the rest of the session. Any ordering that reaches it (a queued callback landing after a mode switch, a force-switch bailing on its `enabled` guard after the state was written) is now bounded to one heartbeat interval and recorded as a lifecycle entry rather than being invisible ([#319](https://github.com/Ikolvi/Tracelet/issues/319)).

**FEAT**: (iOS) background and killed-state diagnostics are now persisted to the log table regardless of `logLevel`, matching the Android channel. iOS has no separate killed-state pipeline — a relaunched process runs the same handlers as a foreground one — so what it records is the boundaries: the termination that registered significant-location monitoring for relaunch, the relaunch that resumed (and in which mode), and, when a relaunch *declines* to resume, which precondition failed. A downgrade from Always authorization silently disables tracking on that path and is now visible rather than inferred. Motion-state transitions carry whether the session launched in the background, so a trace distinguishes "the relaunched session never detected motion" from "it detected motion and the problem is downstream". Entries recorded before the database is open are buffered and flushed once it is; retention is unchanged and shares the existing row and day caps ([#318](https://github.com/Ikolvi/Tracelet/issues/318)).

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

**FIX**: `HealthCheck.motionPermission` is documented correctly and gained a typed `HealthCheck.motionAuthorization` getter. The field carries a `MotionAuthorizationStatus` index (`notDetermined`, `granted`, `deniedForever` → 0, 1, 2), but its doc comment described CoreMotion's `CMAuthorizationStatus` scale, which orders the cases differently and has a separate `restricted` value. Callers that implemented the documented contract — including Tracelet Doctor — reported a *granted* permission as "Restricted". The new getter returns the typed value (`null` when out of range) so the mapping cannot be misread.

**PERF**: the native loggers no longer run a `DELETE` after every log write. Retention is 500-2000 rows, so pruning is now amortized every 50 writes on both platforms.

## 3.7.2

**FIX**: (smart motion) the accelerometer can now contribute to a stationary decision after a start that begins in MOVING. The Rust coordinator initialises `is_accel_moving = false` and ignores an unchanged flag, and `start()` never seeded it, so the stop-timeout fired, reported stationary, and the coordinator emitted nothing — leaving the GPS-speed machine as the only input that could ever change the pace. `start()` now seeds the flag from the state it starts in, and also re-syncs the coordinator's tracking mode (it was previously only synced in `initialize()`, from the *persisted* mode, so a session that ended stationary could leave the coordinator unable to ever switch again) ([#288](https://github.com/Ikolvi/Tracelet/issues/288)).

**FIX**: (smart motion) `MotionDetector` no longer writes `isMoving` itself in smart mode. The accelerometer is one of two inputs there — the coordinator owns the decision — so claiming the transition locally left `getState().isMoving` disagreeing with the last `onMotionChange` event and with actual GPS behaviour whenever the coordinator decided to stay continuous ([#288](https://github.com/Ikolvi/Tracelet/issues/288)).

**FIX**: `shakeThreshold`, `stillThreshold` and `stillSampleCount` are no longer transmitted unless you set them, so each platform keeps its own tuned default. Dart's defaults are the Android values, and they were sent unconditionally by any app that configured *any* motion field: iOS converts m/s² to g, so `stillThreshold: 0.4` arrived as `0.04 g` — about four times stricter than the `0.15 g` iOS default it was meant to keep — and `stillSampleCount: 25` dwelt ~2.5 s at iOS's 10 Hz instead of the intended ~5 s. Reading these properties still reports the documented Dart defaults (`2.5` / `0.4` / `25`), and setting a value — even one equal to the default — is honoured on both platforms, so this is not a breaking API change. iOS's own fallback for `stillSampleCount` was also corrected from 30 to 50 (≈5 s at 10 Hz), matching the documented intent and Android's ~5 s dwell ([#288](https://github.com/Ikolvi/Tracelet/issues/288)).

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
**FEAT**: Crash/fall confirmation is now process-death-safe — if the OS kills the app during the cancel countdown (phone thrown, vehicle at rest, Doze), the confirmed event is still delivered from a re-armed wake-up ([#182](https://github.com/Ikolvi/Tracelet/issues/182)).
**DOCS**: Rewrote the Driving & Safety crash/fall confirmation section in plain, beginner-friendly language.

## 3.5.0

**FEAT**: Crash-detection ML model promoted from **beta to stable** — the shipped model is trained on the CC0 / public-domain Smartphone IMU Road Accident Detection dataset, so it is cleared for commercial use in production apps ([#183](https://github.com/Ikolvi/Tracelet/issues/183)).
**FEAT**: The on-device encrypted model cache now auto-re-downloads when a new model version is published (SHA-256 of the cached blob no longer matches the expected digest), so model upgrades roll out in the same session instead of falling back to the rule engine for a cycle.
**FEAT** (example): Driving & Safety page now shows a live crash-model download/load status indicator, a "Crash (ML model)" debug inference path, a "Benign bump" demo, and a bench "Throw-test" mode.
**PERF**: Per-window crash-model probability is now logged for on-device observability.

## 3.4.2

 - **REFACTOR**: reformat test files and sync body context for consistent code style. ([5552f795](https://github.com/Ikolvi/Tracelet/commit/5552f7952e35472d0b69b92af0fc19440fde4038))

## 3.4.1

 - **FEAT**(geofence): cross-platform geofenceModeHighAccuracy via GeofenceConfig. ([491d5b83](https://github.com/Ikolvi/Tracelet/commit/491d5b836fbd98a2e456d7d07bafc500f95a2fac))
 - **DOCS**: add Discord community invitation link to READMEs and website documentation. ([c3baa1c3](https://github.com/Ikolvi/Tracelet/commit/c3baa1c389f90463fb7f6cabc4d57d68d1d2d512))

## 3.4.0

 - **FEAT**(ios): Live Activity for active tracking — a Lock Screen & Dynamic Island indicator backed by ActivityKit, layered over the standard background pipeline (no redundant second location stream) ([#202](https://github.com/Ikolvi/Tracelet/issues/202)).
 - **FIX**(ios): resolve release-mode launch crash (`SIGTRAP`) caused by a duplicate key in the default config, plus a Widget Extension availability gate that hid the Live Activity and could crash the extension on iOS < 18.
 - **FIX**: per-call extras passed to `getCurrentPosition(extras:)` / `getLastKnownLocation(extras:)` are now forwarded to native and **merged** with the global `HttpConfig.extras` into the synced payload — the platform layer previously dropped per-call `extras` and `desiredAccuracy` ([#201](https://github.com/Ikolvi/Tracelet/issues/201)).
 - **FIX**: `getCurrentPosition` now defaults to high accuracy and never silently runs at passive priority, which could fail an explicit one-shot request with `LOCATION_FAILURE`.
 - **FIX**(android): a single location batch is now uploaded exactly once — duplicate sync providers no longer fire `requestSyncBody` twice for the same batch, preventing duplicate server uploads and duplicate DB rows ([#204](https://github.com/Ikolvi/Tracelet/issues/204)).
 - **REFACTOR**: extract issues 185 and 198, fix iOS config mapping. ([1d088e0d](https://github.com/Ikolvi/Tracelet/commit/1d088e0d58e863b11217c5040410381f91930e59))
 - **FIX**: resolve accuracy priority mappings in Android and iOS. ([65f5127d](https://github.com/Ikolvi/Tracelet/commit/65f5127dd8a9d0ee1c3e2f832499076607ddad10))

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

* **FIX** (Crash detection, Android/iOS): Confirmed `crash`/`fall` events are no longer lost when tracking stops right after the impact (the common crash → vehicle-at-rest → `stopTimeout` case). The confirmation countdown now runs independently of tracking state and self-terminates when no candidate is pending ([#169](https://github.com/Ikolvi/Tracelet/issues/169)).
* **FIX** (Crash detection): The effective crash g-threshold matched the documented value — the confidence gate previously raised a 3.0 g threshold to ~3.6 g, increasing false negatives ([#170](https://github.com/Ikolvi/Tracelet/issues/170)).
* **FIX** (Crash detection): A single crash (primary spike + bounce/secondary impacts) no longer raises multiple candidates; a refractory period debounces one event into one prompt ([#171](https://github.com/Ikolvi/Tracelet/issues/171)).
* **IMPROVE** (Crash detection, Android/iOS): When crash/fall detection is enabled, the accelerometer is sampled at a higher rate (Android `SENSOR_DELAY_GAME` + no batch latency; iOS 100 Hz) so short impact peaks (~50–150 ms) are actually captured instead of missed between motion-detection samples ([#172](https://github.com/Ikolvi/Tracelet/issues/172)). Roadmap for research-grade robustness (Δv, sensor fusion, free-fall signature, process-death survival): [#173](https://github.com/Ikolvi/Tracelet/issues/173).

## 3.3.0

* **FIX** (Audit, Android/iOS): The tamper-proof audit chain only covered locations that flowed through the foreground location dispatcher. Background/headless persists (periodic worker, location service, killed-state relaunch, geofence events) wrote location rows with **no** matching audit-trail link, so `getAuditProof()` returned `null` for those records even with audit enabled. Audit links are now generated at the single persistence chokepoint, so **every** persisted location is chained regardless of source. Chain mutation is also now thread-safe.
* **FIX** (Audit, iOS): `appendToChain` no longer creates an audit row for records without a `uuid` (it previously used an empty string). Such orphan rows had no retrievable location and made `verifyAuditTrail()` report the whole chain as *broken* ("missing location record"). uuid-less records are now skipped on both platforms. The audit hash version was bumped (auto-resets any orphaned/incomplete chains from the prior logic on first launch).
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

 - **FIX**(sync): keep method channel alive to avoid iOS timeout bugs when no builder is registered. ([9a083478](https://github.com/Ikolvi/Tracelet/commit/9a083478733315922245fc82c36bada011378818))
 - **FIX**(sync): resolve issue 134 where custom sync body timeouts prevented background syncs. ([7fa16fdf](https://github.com/Ikolvi/Tracelet/commit/7fa16fdf05274c326f6b6b29d318f55981232f1a))
 - **FIX**(sync): fix background auto-sync abortion when no custom builder is registered (Issue [#134](https://github.com/Ikolvi/Tracelet/issues/134)). ([631542a1](https://github.com/Ikolvi/Tracelet/commit/631542a1c89cece565160966c6f6301a0e18098a))
 - **DOCS**: add official documentation URL to all package READMEs. ([9eb6951e](https://github.com/Ikolvi/Tracelet/commit/9eb6951e64c13007f3264e2d44f0feb9222500a3))
 - **DOCS**: integrate nextra website and update pubspec URLs. ([99b7fda8](https://github.com/Ikolvi/Tracelet/commit/99b7fda82e290ca6c8175313eae62a2475360050))

## 3.2.13

- **FIX**(android): `startOnBoot` now resumes tracking after a reboot on devices where the OS refuses to start a `location` foreground service from `BOOT_COMPLETED` (e.g. Android 14). Previously tracking silently never resumed after a reboot; it now falls back to background WorkManager/alarm tracking.
- **FIX**(android): HTTP sync now works headlessly after a reboot — background sync can refresh an expiring auth token and build a custom sync body without the app being opened. Previously the headless Dart sync bridge was only wired when a UI engine attached, so post-reboot sync used a stale token (or the wrong payload) until the app was launched.

## 3.2.12

- **CHORE**: Re-release to align the full federated package set and native SDKs to a single consistent version. The 3.2.11 release published with mismatched versions across some packages (a few resolved to 3.2.10). No functional code changes.

## 3.2.11

- **FIX**: Custom sync-body builder now falls back to the headless engine on timeout (instead of aborting the sync) on both Android and iOS — fixes location sync stopping after a few minutes in the background when using `setSyncBodyBuilder` (Issue #134).

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

- **FEAT**: Added `autoSyncDelay` to `HttpConfig` — configure the debounce delay in milliseconds before automatically dispatching an HTTP sync request after a location is recorded.
- **FEAT**: Introduced new `tracelet_sync` package for offline SQLite persistence and automatic HTTP synchronization.
- **FEAT**: Add reverse geocoding (`resolveAddress`) functionality for automatic address lookups.

## 3.1.14

- **FIX**(ios): prevent dead code stripping of flutter_rust_bridge symbols in SPM apps by referencing them explicitly in TraceletIosPlugin

## 3.1.10

 - Bump \"tracelet\" to `3.1.10`.

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

**FEAT**: Major architectural upgrade: Unified Rust Core.
- The heavy lifting for Geofences, Privacy Zones, Audit Trail, and SQLite persistence has been moved to a shared Rust core (`tracelet_core`).
- Guarantees 100% mathematical and behavioral parity between iOS and Android.
- Eliminates subtle cross-platform inconsistencies in geofence ray-casting and proximity evaluation.
- Native SDK wrappers (Swift/Kotlin) have been thinned out to act purely as FFI bridges via UniFFI.

**FEAT**: Introduced explicit predefined tracking profiles: `Config.highAccuracy()`, `Config.balanced()`, and `Config.lowPower()` to simplify setup.

**CHORE**: Release strategy overhaul. The iOS Rust Core is now bundled directly into the `tracelet_ios` plugin for pub.dev publication, while the Android SDK continues to be distributed via Maven Central.

## 3.0.1

- **FIX**(ios): Add missing `FlutterFramework` dependency to SPM plugin configuration to resolve compilation failures and `PlatformException`s.

## 3.0.0

### 🎉 Major Features & Improvements
- **FEAT**: Massive Architecture Rewrite — Core algorithms (Location Filtering, Kalman Filter, Trip Management, Battery Budgeting, Schedule Parsing, Delta Encoding, Audit Trail) are now powered by a high-performance **Rust Core** using `flutter_rust_bridge` and `UniFFI`. This brings identically deterministic behavior and extreme battery efficiency across Android, iOS, and Dart.
- **FEAT**: Smart Motion Mode — Introduced `MotionDetectionMode.smart`. This intelligent hybrid detection mode optimizes battery consumption dynamically by delegating evaluation to the Rust battery budget engine.
- **FEAT**: Event bridge overhaul — Migrated all platform event channels to use strongly-typed Pigeon bridges, eliminating JSON serialization overhead completely.
- **FEAT**: New Ecosystem Adapters — Introduced the official `tracelet_supabase` (Supabase Postgres background syncing & Auth) and `tracelet_firebase` (Firebase RTDB live location broadcasting) plugins.

## 2.1.0

### 🎉 Major Features & Improvements
- **FEAT**: Smart Foreground Notification Visibility (Android) — Added dynamic foreground service notification management. The notification now intelligently hides itself when the app is in the foreground, and reappears seamlessly when the app enters the background. This significantly reduces notification clutter while maintaining OS-level compliance.
- **FEAT**: Speed-Based Motion Detection Mode — Introduced a new motion detection mode (`tl.MotionDetectionMode.speed`). In this mode, motion state transitions are driven directly by GPS speed calculations rather than raw accelerometer hardware. This provides enhanced compatibility and reliability on devices with aggressive sensor sleep policies, particularly in vehicular tracking scenarios.
- **FEAT**: Strongly-Typed Enums Across Bridge — Fully refactored string-based config comparisons to typed enum indices across the Flutter, Pigeon, Android, and iOS layers. This eliminates magic strings and ensures type-safety across the entire plugin bridge.

### 🐛 Bug Fixes
- **FIX (Core)**: Fixed Accelerometer "Deaf Period" During Stop Countdown — Fixed a critical flaw in both Android and iOS native SDKs where the accelerometer was completely shut down during the `stopTimeout` countdown. Previously, if the device was still for 5 seconds on a smooth road, it would begin the 60-second stop countdown and ignore any subsequent bumps or shakes. Now, the accelerometer remains active during the countdown and will correctly abort the stationary transition if motion resumes ([#85](https://github.com/Ikolvi/Tracelet/issues/85)).
- **FIX (iOS)**: Resolved Native Permission Prompt Loop — Fixed an issue where reinstalling the app on iOS would bypass the native "Change to Always Allow" permission dialog and incorrectly redirect users to the iOS Settings app. `TraceletHasRequestedAlways` is now properly reset upon `notDetermined` OS state.
- **FIX (Core)**: Corrected Exponential Retry Backoff Scaling — Fixed a critical unit discrepancy between Dart and Swift for `retryBackoffCap` and `retryBackoffBase`. Time values are now properly cast as milliseconds instead of seconds, resolving a severe bug where HTTP retries fired every 60ms during network failure, causing excessive CPU/network thrashing and a massive 58KB+ log flood.
- **FIX (Core)**: Resolved Location Stream Dropping Events — Refactored the core `Tracelet.locationStream` pipeline. Replaced the faulty `asyncMap` batch processing with a highly robust `.expand()` implementation. The `Tracelet.locationStream` now correctly parses, type-casts, and guarantees delivery of every individual `Location` object without throwing `type '_Map<Object?, Object?>' is not a subtype of type 'Map<String, dynamic>'` or silently discarding valid coordinates.
- **FIX (Android)**: Prevent `LocationEngine.stop` from unintentionally overriding the global `stateManager.enabled` flag during speed-based motion transitions.
- **FIX (Example)**: Updated the example app's initialization config to enforce `MotionDetectionMode.accelerometer` as the default to ensure immediate indoor responsiveness upon installation.

## 2.0.8

- **FIX**(ios): Resolved type casting bug for 64-bit Pigeon `Int64` integer values across all iOS config mappings. Integer configurations (such as `stopTimeout`, `locationUpdateInterval`, etc.) are now correctly applied on iOS instead of silently falling back to defaults.
- **PERF**(ios): Added optimization to skip the GPS `distanceFilter` override to continuous tracking during `stopTimeout` when `preventSuspend` is enabled. This significantly reduces stationary battery drain when using the audio keep-alive feature.
- **CHORE**: Update platform-specific dependency constraints to `^2.0.8`.

## 2.0.7

- **FIX**: Corrected `intToAuthStatus` permission index mappings on Android and iOS — `getLocationAuthorization()` and `requestLocationAuthorization()` now return the correct `AuthorizationStatus` values ([#80](https://github.com/Ikolvi/Tracelet/issues/80)).
- **FIX**: Resolved Android SQLCipher migration crashes by loading the SQLCipher native library explicitly before migration and decoupling classpath availability checks to avoid class loading errors ([#78](https://github.com/Ikolvi/Tracelet/issues/78)).
- **FIX**: Prevented false positive shake events on Android by applying absolute values to motion sensor magnitude readings and fixed zero-timeout logic to immediately transition to stationary state when delay is zero or negative ([#79](https://github.com/Ikolvi/Tracelet/issues/79)).
- **FIX**: Removed manual Kotlin Gradle Plugin (KGP) configuration to support Flutter's new Built-in Kotlin feature, resolving build warnings and failures on newer Flutter versions ([#81](https://github.com/Ikolvi/Tracelet/issues/81)).
- **CHORE**: Update platform-specific dependency constraints to `^2.0.7`.

## 2.0.6

- **PERF**: Hardware-level sensor batching on Android reduces CPU wake-ups by over 90% during active accelerometer monitoring.
- **FIX**: iOS `BatteryBudgetEngine` adjustments (distance filter, desired accuracy, periodic interval) are now correctly applied to the location engine.
- **PERF**: iOS Heartbeat deduplication avoids redundant SQLite writes and HTTP sync attempts when stationary.
- **FIX**: Restored fast stationary detection (~5s dwell window) on iOS by correcting sample calculations to match 10Hz accelerometer rate.
- **FEAT**: Added graceful hardware fallback on Android to use `TYPE_SIGNIFICANT_MOTION` when the primary accelerometer is missing.
- **FEAT**: Added explicit permission checks and events upon start when location permissions are missing.
- **CHORE**: Update platform-specific dependency constraints to `^2.0.6`.

## 2.0.5

- **FEAT**: Added `Tracelet.isHeadlessRegistered` static getter. Returns `true` after `registerHeadlessTask()` has been called. Useful for diagnostic tools like `tracelet_doctor` to detect missing headless handlers.
- **CHORE**: New companion package `tracelet_doctor` (v1.0.0) — drop-in diagnostic overlay widget. See [tracelet_doctor](https://pub.dev/packages/tracelet_doctor).

## 2.0.4

- **FEAT**: Integrated Kalman Location Filter GPS smoothing into the Flutter plugin and the dynamic config settings in the Example App.
- **CHORE**: Update platform-specific dependency constraints to `^2.0.4`.

## 2.0.3

- **FIX**: Removed unreliable timestamp drift heuristic from Android and iOS location spoofing detection. This prevents valid locations from being incorrectly rejected when a device's wall-clock time is slightly out of sync with GPS UTC time.

## 2.0.1

- **FIX**: Fixed persistent blue location indicator on iOS by properly conditionally disabling `CLBackgroundActivitySession` and continuous GPS in low-accuracy geofence-only mode.
- **CHORE**: Bumped native SDK dependencies to `2.0.1`.

## 2.0.0

### 🎉 Major Milestone: Tracelet 2.0.0

Tracelet 2.0.0 introduces a modernized configuration schema, robust type-safe platform communication via Pigeon, and a flexible dependency model to optimize app size and compatibility.

### 🚨 Breaking Changes
- **Refactored Configuration**: The `Config` model is now a nested compound structure. Fields are grouped into `GeoConfig`, `AppConfig`, `AndroidConfig`, `HttpConfig`, `LoggerConfig`, `MotionConfig`, `GeofenceConfig`, and `SecurityConfig`.
- **Android On-Demand Dependencies**: Optional features (GMS Location, SQLCipher, Play Integrity) are no longer bundled by default, reducing APK size by ~16 MB. Developers must now explicitly add these to their `android/app/build.gradle` if required.
- **Pigeon Migration**: All platform-to-native communication now uses strictly-typed Pigeon interfaces, improving reliability and eliminating magic string/map errors.
- **Removed Deprecated APIs**: Permission methods that returned raw integers (e.g., `getPermissionStatus`, `requestPermission`) have been removed in favor of the strongly-typed `Future<AuthorizationStatus>` methods introduced in 1.9.0.

### 🛠️ Improvements
- **Motion Sensitivity Tuning**: Added `shakeThreshold`, `stillThreshold`, and `stillSampleCount` to `MotionConfig`, providing granular control over accelerometer-based motion detection across all platforms.
- **iOS Stability**: Resolved a critical issue where native permission dialogs failed to appear by enforcing main-thread execution for all `CoreLocation` and `CoreMotion` requests.
- **Cross-Platform Parity**: Aligned authorization status mapping across Android and iOS to ensure consistent behavior when checking permissions.
- **AOSP Support**: Improved fallback to standard `LocationManager` on Android when Google Play Services are unavailable.

## 1.9.3
2: 
3: - **CHORE**: Bump native SDK dependencies to `1.1.4`.
4: - **CHORE**: Aligned repository podspec files and updated release documentation.
5: 
6: ## 1.9.2

- **REFACTOR**: Migrated `TlTrackingMode` to a strongly-typed enum across the entire Pigeon bridge. This improves type safety and developer experience by eliminating magic integers in the platform communication layer. Android and iOS native implementations now use the generated enum types directly.
- **FIX**: Resolved "Unable to establish connection" regression in `locationStream` when secondary engines (like overlays or background isolates) detach. Ensured `destroyAll()` is correctly integrated into the `primaryInstance` guard on both Android and iOS to prevent resource leaks and duplicate registrations during hot restarts.
- **FIX**: `Tracelet.locationStream` no longer goes silent when `flutter_overlay_window` (or any plugin using `FlutterEngineGroup`) creates a secondary in-process `FlutterEngine`. The primary-instance guard introduced in 1.9.0 (#51) blocked `EventDispatcher` re-binding for in-process overlay engines, causing Pigeon FlutterApi `onLocation` channel to report "Unable to establish connection". A Looper-based discriminator now distinguishes overlay engines (main-thread attach → re-bind dispatcher) from headless background engines (off-thread attach → full skip, preserving #51).
- **FIX**: Android `destroyAll()` now guards all background-critical subsystems when `stopOnTerminate: false` (#65). `httpSyncManager.stop()`, `scheduleManager.stop()`, and `stopHeartbeat()` were still called unconditionally on every swipe-to-dismiss, permanently killing HTTP sync and heartbeat monitoring until the app was manually reopened. Fixed in native `tracelet-sdk` 1.1.2.
- **CHORE**: Aligned `PigeonTracelet` serialization logic to use enum indices for backward compatibility with the high-level `State` model while maintaining type-safe internal bridge contracts.

## 1.9.1

- **FIX**: Android `destroyAll()` now respects `stopOnTerminate: false` for continuous and geofence tracking modes (#63). `locationEngine.destroy()` was unconditionally called in `onDetachedFromEngine()`, racing with `LocationService.onTaskRemoved()` which bootstraps native tracking. Background location tracking now survives app swipe from recents when `stopOnTerminate: false` is configured.

## 1.9.0

- **FEAT**: Strongly typed permission APIs (#57). Added `getLocationAuthorization`, `requestLocationAuthorization`, `getNotificationAuthorization`, `requestNotificationAuthorization`, `getMotionAuthorization`, `requestMotionAuthorization`, and `requestTemporaryFullAccuracyAuthorization`, all returning `Future<AuthorizationStatus>` instead of magic ints. The matching int-returning methods (`getPermissionStatus`, `requestPermission`, `getNotificationPermissionStatus`, `requestNotificationPermission`, `getMotionPermissionStatus`, `requestMotionPermission`, `requestTemporaryFullAccuracy`) are now `@Deprecated` and will be removed in 2.0.0.
- **FIX**: Android `LocationService` no longer crashes the host app with `RemoteServiceException: Context.startForegroundService() did not then call Service.startForeground()` (#59). Reproducible on real devices when using `periodicUseForegroundService: true`. Root cause: `onStartCommand` only promoted to foreground for `ACTION_START`, but the system can deliver intents for other actions (and null-intent sticky restarts after a system kill) under the same foreground-service contract. Fixed in native `tracelet-sdk` 1.1.0 by always promoting at the top of `onStartCommand`.
- **FIX**: `Geofence(extras: {...})` now correctly persists and is returned by `getGeofences()` and delivered in `onGeofence` events (#58). Bug was in `tracelet_platform_interface`'s `_mapToGeofence`, which silently dropped `extras` and `vertices` when constructing the Pigeon payload; the 1.8.12 native fix had no effect because the data never crossed the platform channel. Affected both Android and iOS.
- **TEST**: Added on-device integration test (`example/integration_test/geofence_extras_test.dart`) that round-trips `addGeofence` → `getGeofences()` to prevent regression.

## 1.8.13

- **PERF**: Reduce first-fix latency on stationary → moving transitions on both iOS and Android. The native engines now fire an additional one-shot location request when motion starts, delivering a fresh GPS fix in ~1–5s instead of waiting for `distanceFilter` (iOS) or `locationUpdateInterval` (Android) on the continuous stream (#54).
- **FIX**: Android — after a manual `Tracelet.changePace(false)` (force stationary), the SDK can now detect real motion and resume tracking automatically. Previously the wake-up sensors stayed torn down, leaving the SDK in a dead-state. iOS was unaffected.
- **FIX**: Bump iOS native SDK to 1.0.11 and Android native SDK to 1.0.12.

## 1.8.12

- **FIX**: Geofence `extras` now arrive in `GeofenceEvent.extras` on Android (previously always empty). Location `extras` are also correctly included when reading back persisted locations (#51 follow-up).
- **FIX**: Bump Android native SDK to 1.0.11.

## 1.8.11

- **FIX**: Geofence callbacks no longer silently stop during continuous tracking when a secondary FlutterEngine (e.g. Firebase background messaging) registers the plugin (#51).

## 1.8.10

- **FIX**: Killed-state tracking now works reliably — `stopBootTracking()` deferred from `initialize()` to `ready()` so boot-mode native tracking survives until the Dart side explicitly takes over (#50).
- **FIX**: Bump native SDKs to 1.0.10.

## 1.8.9

- **FEAT**: Add `syncInterval` to `HttpConfig` — flush locations on a fixed timer instead of per-insert, for fleet/logistics use cases (#50).
- **FEAT**: Bump native SDKs to 1.0.9.

## 1.8.8

- **FIX**: HTTP sync payload now consistent between iOS and Android — Android `cursorToLocation()` and all location map producers now use canonical `is_moving` (snake_case) and ISO 8601 timestamps, matching iOS format (#48).
- **FIX**: Bump native SDKs to 1.0.8.

## 1.8.7

- **FIX**: Enhance overall stability by including pending 1.8.6 patches.
- **FIX**: Bump native SDKs to 1.0.7.

## 1.8.6

- **FIX**: `getCurrentPosition(samples: 1)` now forces a fresh GPS fix instead of returning stale cached locations — uses `requestLocationUpdates`/`startUpdatingLocation` instead of `getCurrentLocation`/`requestLocation` which may return cached data without waking GPS hardware (#46).
- **FIX**: HTTP sync headers callback (`setHeadersCallback`) no longer invoked per-batch — eliminates unnecessary MethodChannel round-trip latency on every sync request. Token refresh now handled exclusively via `setTokenRefreshCallback` on 401.
- **FIX**: Headless `FlutterEngine` no longer overwrites foreground `httpSyncManager` callbacks — fixes 10-second timeout on `requestFreshHeaders` caused by MethodChannel messages routed to the wrong Dart isolate.
- **FIX**: Bump native SDKs to 1.0.6.
- **FIX**: Privacy zones, audit trail, and encryption APIs now work before `ready()` — only require `initialize()` (DB creation), not active tracking.
- **FIX**: `getPrivacyZones()` no longer throws `_Map<Object?, Object?>` type cast error — fix Pigeon-generated lazy cast for nested map types.

## 1.8.5

- **FIX**: `getCurrentPosition()` falls back to last known location when GPS returns no fix (e.g. emulator, GPS-off) — fixes `LOCATION_UNAVAILABLE` errors (#46).
- **FIX**: Bump native SDKs to 1.0.5.

## 1.8.4

- **FIX**: Add `isReady` guards to all Android SDK methods — prevents `UninitializedPropertyAccessException` when called before `ready()` (re-fixes #46).
- **FIX**: Pin native SDK dependencies to exact versions — prevents auto-resolving to incompatible newer native SDK releases.

## 1.8.3

- **FIX**: Prevent crash when `getState()`, `setConfig()`, or any other method is called before `ready()` on iOS — comprehensive `isReady` guards across all native SDK methods (re-fixes #46).

## 1.8.2

- **FIX**: Prevent crash when `stop()` is called before `ready()` on iOS — returns `NOT_READY` error instead of accessing uninitialized properties.
- **FIX**: Guard `soundManager` access on Android to prevent `UninitializedPropertyAccessException` during motion state changes or cleanup.
- **FIX**: Use `LocationManagerCompat.isLocationEnabled()` on Android — fixes `NoSuchMethodError` crash on API 26/27 devices.
- **FIX**: Enterprise optional dependencies (SQLCipher, Play Integrity, security-crypto) now gracefully degrade at runtime when not on the classpath — no more `NoClassDefFoundError` crashes.
- **REFACTOR**: Refined ProGuard/R8 consumer rules — narrower keep rules, added `-dontwarn` for optional enterprise dependencies.
- **DOCS**: Updated `INSTALL-ANDROID.md` and `DATABASE-ENCRYPTION.md` with enterprise dependency setup instructions.

## 1.8.1

- **FIX**: iOS periodic mode no longer shows persistent location indicator in the status bar.

## 1.8.0

- **FIX**: Align location map format contract across Android, iOS, and Dart layers — fixes 9 format mismatches.
- **FEAT**: Add `Tracelet.destroySyncedLocations()` — deletes only synced locations, returns count deleted.
- **FEAT**: Auto-purge synced locations from database after successful HTTP sync.
- **TEST**: Add 25 Dart location map format tests.
- **DOCS**: Add `help/LOCATION-MAP-FORMAT.md` canonical format contract reference.

## 1.7.1

- **FIX**: ConfigManager null-merge — partial `setConfig()` no longer overwrites existing values with null defaults (fixes periodic mode HTTP sync failure).
- **FEAT**: Add `Tracelet.destroySyncedLocations()` — deletes only synced locations, returns count deleted.
- **FEAT**: Auto-purge synced locations from database after successful HTTP sync.

## 1.7.0

- **FEAT**: Migrate all event subscriptions from EventChannels to Pigeon FlutterApi platform streams.
- **FEAT**: Add `Location.fromTl` and `LocationActivity.fromTl` factory constructors for Pigeon type conversion.
- **FIX**: Headless geofence events no longer silently dropped on Android task removal (#43).
- **REFACTOR**: Extract native SDKs to standalone modules — Android (Maven Central) and iOS (CocoaPods/SPM).
- **DOCS**: Add local development workflow documentation to CONTRIBUTING.md.

## 1.6.3-alpha.1

- **FEAT**: Migrate all event subscriptions from EventChannels to Pigeon FlutterApi platform streams.
- **FEAT**: Add `Location.fromTl` and `LocationActivity.fromTl` factory constructors for Pigeon type conversion.
- **REFACTOR**: Remove `_eventChannels`, `_eventStreams` maps, and `_getEventStream()` helper.
- **CHORE**: Update cross-package dependency constraints to `^1.6.3-alpha.1`.

## 1.6.2

- **FIX**: Update `tracelet_web` dependency to `^1.6.1` — fixes 5 missing HTTP Sync method stubs that caused `UnimplementedError` on web.

## 1.6.1

- **FEAT**: Add 401-aware retry — native HTTP sync now detects 401 responses, invokes the headless headers callback (`registerHeadlessHeadersCallback`) to refresh authorization tokens, and retries the request once with updated dynamic headers. Works in both foreground and killed-state (headless) modes.

## 1.6.0

- **FEAT**: Add SSL certificate pinning via `HttpConfig.sslPinningCertificates` and `HttpConfig.sslPinningFingerprints`.
- **FEAT**: Add dynamic HTTP headers — `setDynamicHeaders()`, `setHeadersCallback()`, `refreshHeaders()`, and headless `registerHeadlessHeadersCallback()`.
- **FEAT**: Add route context — `setRouteContext()` / `clearRouteContext()` to attach metadata to every synced location.
- **FEAT**: Add custom sync body builder — `setSyncBodyBuilder()` and headless `registerHeadlessSyncBodyBuilder()`.
- **TEST**: Add 19 Dart unit tests for `RouteContext`, `SyncBodyContext`, and `HttpConfig` SSL fields.
- **TEST**: Add 6 MethodChannel mock tests for new platform methods.
- **DOCS**: Update API.md, CONFIGURATION.md, HTTP-SYNC.md with new sync feature documentation.
- **CHORE**: Update cross-package dependency constraints to `^1.6.0`.

## 1.5.0

- **FEAT**: Boot-mode HTTP auto-sync — locations sync to your server even when the app is killed or the device reboots (Android).
- **FIX**: Test server now correctly reads `latitude`/`longitude` from nested `coords` object.
- **CHORE**: Update cross-package dependency constraints to `^1.5.0`.

## 1.4.6

- **FIX**: Rename native `PermissionManager` to `TraceletPermissionManager` to avoid class name collision with `permission_handler_apple` (#32).
- **CHORE**: Update cross-package dependency constraints to `^1.4.6`.

## 1.4.5

- **TEST**: Add integration tests for GPS-off fallback and reduced accuracy field serialization.
- **CHORE**: Update cross-package dependency constraints to `^1.4.5`.

## 1.4.4

- **FEAT**: Add `reducedAccuracy` field to `Location` — `true` when iOS 14+ grants only approximate location authorization.
- **FEAT**: Example app now shows `[REDUCED]` tag and `gpsFallback=ON` indicator for reduced/fallback location states.
- **TEST**: Add 5 unit tests for `reducedAccuracy` field (default, parse, snake_case, round-trip, copyWithCoords).
- **CHORE**: Update cross-package dependency constraints to `^1.4.4`.

## 1.4.3

- **FEAT**: Add `locationSource` field to `Location` — classifies each fix as `gps`, `wifi`, `cell`, `network`, or `unknown`.
- **FEAT**: Add `gpsFallback` field to `ProviderChangeEvent` — signals when the engine auto-downgrades to Wi-Fi/cell positioning because GPS is disabled.
- **CHORE**: Update cross-package dependency constraints to `^1.4.3`.

## 1.4.2

- **FIX**: Dead reckoning activation now reliably detects GPS hardware state instead of using accuracy-based heuristic.
- **FIX**: Mock detection heuristic no longer produces false positives for Wi-Fi/cell locations when GPS is disabled.
- **CHORE**: Update cross-package dependency constraints to `^1.4.2`.

## 1.4.1

- **FEAT**: Dead reckoning — full native IMU sensor fusion for GPS-denied environments (tunnels, parking structures, urban canyons). Activates automatically on GPS loss, deactivates on GPS recovery.
- **CHORE**: Update cross-package dependency constraints to `^1.4.1`.

## 1.4.0

- **FEAT**: Encrypted SQLite — `Tracelet.isDatabaseEncrypted()` and `Tracelet.encryptDatabase()` for at-rest database encryption (SQLCipher on Android, Data Protection on iOS).
- **FEAT**: Device attestation — `Tracelet.getAttestationToken()` returns a platform attestation token (Play Integrity on Android, App Attest on iOS).
- **FEAT**: Remote config — automatic fetch of remote configuration with ETag caching and `onRemoteConfig` event stream.
- **FEAT**: Dead reckoning — `Tracelet.getDeadReckoningState()` stub for future accelerometer/gyroscope-based position estimation.
- **FEAT**: Carbon estimator — `Tracelet.getCarbonReport()` returns CO₂ emission estimates from tracked journeys.
- **FEAT**: Add `SecurityConfig` and `AttestationConfig` to `Config` model for enterprise feature configuration.
- **CHORE**: Update cross-package dependency constraints to `^1.4.0`.

## 1.3.7

- **FIX**: Android — fix `ClassNotFoundException` crash on app upgrade for `BootReceiver` and other manifest-declared components (fixes #31).
- **CHORE**: Update `tracelet_android` dependency constraint to `^1.3.7`.

## 1.3.6

- **FIX**: `SQLQuery.start` and `SQLQuery.end` now correctly filter locations on all platforms (Android, iOS, Web).
- **FIX**: Add `offset` field to `SQLQuery` to match native handler expectations.
- **FIX**: `getCount()` now accepts optional `SQLQuery` for time-bounded counting.
- **PERF**: `DeltaEncoder.encode` is 2.1x faster (cached DateTime parsing, precomputed rounding factors).
- **PERF**: `GeoUtils.haversine` optimized — fewer trig calls, precomputed constants.
- **CHORE**: Update cross-package dependency constraints to `^1.3.6`.

## 1.3.5

- **FIX**: iOS — fix `Unable to find module dependency: 'TraceletCore'` build error.
- **CHORE**: Update cross-package dependency constraints to `^1.3.5`.

## 1.3.4

- **CHORE**: Update cross-package dependency constraints to `^1.3.3`.

## 1.3.3

- **FIX**: Android — bundle native core Kotlin source (`com.tracelet.core.*`) directly inside the plugin package, fixing "Unresolved reference" build errors when installed from pub.dev.
- **FIX**: iOS — bundle TraceletCore Swift source directly inside the plugin package instead of depending on an unpublished local CocoaPod.
- **CHORE**: Remove React Native support to simplify the monorepo.

## 1.3.2

- **PERF**: Android — streaming `JsonWriter` replaces per-location `JSONObject` allocations in batch sync (A-L5).
- **PERF**: iOS — C-level UUID generation replaces Foundation `UUID()` in `LocationEngine` and `TraceletDatabase` (I-M6).
- **PERF**: Performance audit now 77/77 items resolved (100%).

## 1.3.1

- **FIX**: Resolve `extras` key collision between `HttpConfig` and `PersistenceConfig` — serialization keys renamed to `httpExtras` and `persistenceExtras` to prevent native ConfigManager flat-merge from overwriting one with the other. Backward-compatible via `fromMap` fallback.
- **PERF**: Add 22 new benchmarks covering DeltaEncoder, BatteryBudgetEngine, CarbonEstimator, PersistDecider, Config/State serialization.
- **PERF**: iOS `markSynced()` now uses chunked prepared statements (500 UUIDs/chunk) to avoid SQLite variable limit and improve sync performance.

## 1.3.0

- **FIX**: `getState()` always returned `enabled: false` on iOS — the iOS `StateManager.toMap()` flat-merged config keys into the state dictionary, overwriting `enabled` and `isMoving` with config defaults. Fixed by nesting config under a `"config"` key, matching Android behavior ([#26](https://github.com/Ikolvi/Tracelet/issues/26)).

## 1.2.0

### Breaking Changes

- **REFACTOR**: `ForegroundServiceConfig.notificationPriority` changed from `int` to `NotificationPriority` enum. Replace raw integers (`-2`..`2`) with enum values (`NotificationPriority.min`, `.low`, `.defaultPriority`, `.high`, `.max`).
- **REFACTOR**: `AuditConfig.hashAlgorithm` changed from `String` to `HashAlgorithm` enum. Replace `'SHA-256'` with `HashAlgorithm.sha256`, `'SHA-512'` with `HashAlgorithm.sha512`, etc.
- **REFACTOR**: `MotionConfig.triggerActivities` changed from comma-separated `String` to `Set<ActivityType>`. Replace `'on_foot, in_vehicle'` with `{ActivityType.onFoot, ActivityType.inVehicle}`.

### Notes

- Native platform channel serialization is backward-compatible — no native code changes required. `notificationPriority` still serializes as int, `hashAlgorithm` as `"SHA-256"` string, and `triggerActivities` as comma-separated string.

## 1.1.0

### New Features

- **FEAT**: Add `ComplianceReport` model and `Tracelet.generateComplianceReport()` API for GDPR Article 30 / CCPA data processing inventory reports. Auto-generates a structured snapshot of all location data collection metadata including: `totalLocationsStored`, `totalLocationsSynced`, data retention policy (`maxDaysToPersist`, `maxRecordsToPersist`), timestamp bounds of stored records (`oldestRecord`, `newestRecord`), database encryption status, active privacy zone count and identifiers, HTTP sync URL and auto-sync state, audit trail status with chain validation, permission states (location + motion), and tracking configuration flags (sparse updates, Kalman filter, delta compression, tracking mode). Supports `toJson()` for automated tooling integration and `toMarkdown()` for human-readable audit documents.
- **FEAT**: Add `BatteryBudgetEngine` algorithm — a feedback control loop that automatically adjusts `distanceFilter`, `desiredAccuracy`, and periodic interval to maintain a configurable battery budget. Set `batteryBudgetPerHour` in `GeoConfig` (typical range: 1.0–5.0 %/hr) to enable. Subscribe to `Tracelet.onBudgetAdjustment()` for real-time adjustment events showing current drain vs. target and the new parameters being applied.
- **FEAT**: Add `CarbonEstimator` — per-trip and cumulative CO₂ emission calculator using EU EEA 2024 mode-specific emission factors (gCO₂/km): car = 192, bus = 89, train = 41, walking/cycling = 0. Integrates with activity recognition to track distance per transport mode via Haversine. Returns `TripCarbonSummary` with `totalCarbonGrams`, `totalDistanceMeters`, `carbonByMode`, `distanceByMode`, and `dominantMode`. Tracks cumulative totals across trips.
- **FEAT**: Add `DeltaEncoder` algorithm — batch location compression codec using delta encoding with 60–80% payload reduction. First location transmitted in full; subsequent positions as deltas with shortened field names and configurable coordinate precision (5 = ~1.1 m, 6 = ~0.11 m). Native implementations provided on Android (Kotlin) and iOS (Swift) for consistency.
- **FEAT**: Add `RTree<T>` spatial index — O(log n) geofence proximity queries supporting 10,000+ geofences with sub-millisecond lookup. Provides `queryCircle()` and `queryBBox()` APIs with Haversine-verified results.

### New Configuration Fields

- **FEAT**: `GeoConfig.batteryBudgetPerHour` (`double`, default `0.0`) — target max battery drain (%/hr). When > 0, enables `BatteryBudgetEngine` which auto-adjusts accuracy, distance filter, and sample rate. Overrides manual settings.
- **FEAT**: `GeoConfig.enableSparseUpdates` (`bool`, default `false`) — app-level deduplication that drops locations within `sparseDistanceThreshold` (default 50 m) of the last recorded position. Unlike `distanceFilter` (which controls platform GPS sampling), this filters at the persistence layer. `sparseMaxIdleSeconds` (default 300) forces periodic "still here" updates.
- **FEAT**: `GeoConfig.enableDeadReckoning` (`bool`, default `false`) — inertial navigation using accelerometer + gyroscope + compass when GPS is lost for longer than `deadReckoningActivationDelay` seconds (default 10). Auto-stops after `deadReckoningMaxDuration` seconds (default 120) to prevent IMU drift accumulation.
- **FEAT**: `HttpConfig.enableDeltaCompression` (`bool`, default `false`) — enable delta encoding for batch HTTP syncs. `deltaCoordinatePrecision` (default 6) controls coordinate precision.
- **FEAT**: `HttpConfig.disableAutoSyncOnCellular` (`bool`, default `false`) — skip auto-sync on cellular networks, only sync on WiFi. Supported on Android, iOS, and Web (via Network Information API).
- **FEAT**: `GeoConfig.enableAdaptiveMode` (`bool`, default `false`) — dynamic sampling based on activity type + battery level + charging state. Activity profiles: still → 500 m, walking → 50 m, driving → 10 m; battery scaling progressively widens filter below 50%/20%/10%.
- **FEAT**: Periodic mode configuration: `periodicLocationInterval` (60–43200 sec), `periodicDesiredAccuracy`, `periodicUseForegroundService` (Android — sub-15-min intervals), `periodicUseExactAlarms` (Android — `AlarmManager` precision).

### Bug Fixes

- **FIX**: `generateComplianceReport()` and `getHealthCheck()` no longer crash with `type 'Map<Object?, Object?>' is not a subtype of type 'Map<String, Object?>'` errors. Platform channel maps are now safely converted via `Map<String, Object?>.from()` instead of direct `as` casts. Also fixed nested config sub-map casts (`config`, `geo`, `http`, `audit`, `persistence`) using null-safe `is Map` checks.

### Infrastructure

- **CHORE**: Migrate melos configuration from standalone `melos.yaml` to `pubspec.yaml` under the `melos:` key for melos 7.x compatibility. All 13 scripts (analyze, format, format:fix, test, test:dart, pigeon, clean, pub:get, build:example:android/ios/web, coverage, benchmark) now run via `melos run <name>`.
- **CHORE**: Adopt Dart pub workspaces — root `pubspec.yaml` declares `workspace:` listing all 6 packages; each package declares `resolution: workspace`. Removed 5 `pubspec_overrides.yaml` files that are no longer needed.
- **CHORE**: Upgrade melos dependency from `^6.0.0` to `^7.0.0`.

## 1.0.2

- **FIX**: (Android/iOS) Geofence registrations were unconditionally destroyed on app termination and reset, even when `stopOnTerminate: false` was configured with `trackingMode=1`. Geofences now survive process death and are properly re-registered ([#23](https://github.com/Ikolvi/Tracelet/issues/23)).

## 1.0.1

- **FIX**: HTTP auto-sync was not triggered during automatic location tracking on any platform — locations accumulated in the database without being synced to the server ([#21](https://github.com/Ikolvi/Tracelet/issues/21)).
- **FIX**: (iOS) `HttpMethod.put` was silently ignored due to type mismatch in native config parsing.
- **FIX**: (iOS) HTTP headers could be dropped when platform channel delivered mixed-type maps.
- **FIX**: (iOS) `maxBatchSize` default corrected from 100 to 250.

## 1.0.0

### 🎉 Stable Release

- **FEAT**: First stable release of `tracelet` — production-grade background geolocation for Flutter.
- **DOCS**: Add Play Store background location declaration guide.
- **REFACTOR**: Remove third-party company name references — use generic `flutter_background_geolocation` throughout.
- **REFACTOR**: Rename migration guide to `MIGRATION-FROM-FBG.md`.
- All APIs are finalized and production-ready.

## 0.12.0

### Performance Audit — 74 of 77 issues resolved

- **PERF**: Cache `AdaptiveSamplingEngine` instance instead of re-creating per GPS fix (D-C1).
- **PERF**: Add `Location.copyWithCoords()` to eliminate `toMap()/fromMap()` round-trip in Kalman filter hot path (D-C2).
- **PERF**: Wire trip detection to processed location stream, eliminating duplicate `Location.fromMap()` (D-H1).
- **PERF**: Fast-path `_castToMap` with type check — avoids map copy when already correct type (D-H2).
- **PERF**: Replace `.expand()` with `.where()` in `_filterLocation` to avoid single-element list allocations (D-H4).
- **PERF**: Cancel adaptive activity subscription in `removeListeners()` (D-H7).
- **PERF**: Use `.toList(growable: false)` for `addGeofences`/`addPrivacyZones` result lists (D-M6).
- **PERF**: Invalidate cached stream pipeline on `setConfig()` so it rebuilds with new settings (D-M8).
- **PERF**: Use `Map.from()` instead of `.map()` with `MapEntry` for extras in `Location.fromMap()` (D-L4).
- **REFACTOR**: Deduplicate `LocationProcessor` parameter list in `setConfig()` (D-L5).

## 0.11.5

- **FIX**: [Android/iOS] Polygon geofence `vertices` are now correctly persisted to the native SQLite databases. Previously, vertex data was silently dropped during `addGeofence()`, causing polygon geofences to revert to circular after app restart.

## 0.11.4

- **FIX**: [iOS] Revert over-aggressive permission guards — When In Use permission now works correctly for all tracking modes. Only the killed-state auto-resume (`autoResumeTracking`) requires Always authorization. iOS enforces permission at the OS level.

## 0.11.3

- **FIX**: [Android] Enforce `ACCESS_BACKGROUND_LOCATION` check on all killed-state restart paths (boot receiver, task removal, periodic alarms/workers). "While In Use" permission no longer triggers background tracking.
- **FIX**: [iOS] Enforce `.authorizedAlways` check on killed-state auto-resume and guard `allowsBackgroundLocationUpdates`. "When In Use" permission no longer triggers tracking from killed state.- **FEAT**: Add `Tracelet.hasBackgroundPermission` static getter — convenience check that returns `true` when location permission is `AuthorizationStatus.always`.
## 0.11.2

- **DOCS**: Fix 22 unresolved dartdoc references (`[Enterprise]`, `[Config.*]`, `[isValid]`, `[brokenAtIndex]`, `[brokenAtUuid]`).
- **CHORE**: Tighten all platform package constraints to `^0.11.2` (fixes `pub downgrade` score penalty).

## 0.11.1

- **FEAT**: Add `canScheduleExactAlarms()` and `openExactAlarmSettings()` static methods for Android exact alarm permission management.
- **FIX**: Bypass `LocationProcessor` distance/accuracy/speed filters for periodic location events — every timed fix is now delivered regardless of movement.
- **CHORE**: Bump platform interface to 0.11.1.

## 0.11.0

- **FEAT**: Tamper-proof audit trail — SHA-256 hash chain for location integrity verification.
- **FEAT**: Privacy zones — exclude, degrade, or event-only actions for geographic privacy control.
- **FEAT**: `AuditConfig` sub-config with `enabled`, `hashAlgorithm`, `includeExtrasInHash` options.
- **FEAT**: `PrivacyZoneConfig` sub-config with `enabled` toggle.
- **FEAT**: `PrivacyZone` model with `identifier`, `latitude`, `longitude`, `radius`, `action`, `degradedAccuracyMeters`.
- **FEAT**: `AuditProof` model for hash chain verification results.
- **FEAT**: CRUD API: `addPrivacyZone()`, `addPrivacyZones()`, `removePrivacyZone()`, `removePrivacyZones()`, `getPrivacyZones()`.
- **FEAT**: Audit API: `getAuditTrail()`, `verifyAuditTrail()`, `getAuditProof()`.
- **DOCS**: Added AUDIT-TRAIL.md and PRIVACY-ZONES.md guides.
- **CHORE**: Bump all platform packages to ^0.11.0.

## 0.10.0

- **FEAT**: Periodic mode — `Tracelet.startPeriodic()` for GPS-friendly interval tracking. GPS icon visible only ~5–10 seconds per fix instead of permanently.
- **FEAT**: `GeoConfig` periodic options: `periodicLocationInterval`, `periodicDesiredAccuracy`, `periodicUseForegroundService`, `periodicUseExactAlarms`.
- **FEAT**: Three Android scheduling strategies: WorkManager (default, battery-optimal), foreground service (reliable timing), and AlarmManager exact alarms (precise, no notification).
- **FEAT**: Example app: periodic mode UI section with start/stop toggle, custom settings dialog, and map integration with distinct cyan markers.
- **DOCS**: Updated API.md, CONFIGURATION.md, BACKGROUND-TRACKING.md, and INSTALL-ANDROID.md with periodic mode and exact alarms documentation.
- **CHORE**: Bump all platform packages to ^0.10.0.

## 0.9.1

- **FIX**: iOS `HttpSyncManager` optional `UIBackgroundTaskIdentifier` unwrap safety.

## 0.9.0

* **FEAT**: Adaptive sampling engine — auto-adjusts `distanceFilter` based on detected activity type, battery level, and speed. Enable with `GeoConfig(enableAdaptiveMode: true)`. See [Adaptive Sampling Guide](https://github.com/Ikolvi/Tracelet/blob/main/help/ADAPTIVE-SAMPLING.md).
* **FEAT**: Health check API — `Tracelet.getHealth()` returns a comprehensive diagnostic snapshot covering tracking state, permissions, battery, sensors, database, and geofence state with actionable `HealthWarning` enum. See [Health Check Guide](https://github.com/Ikolvi/Tracelet/blob/main/help/HEALTH-CHECK.md).
* **FEAT**: HTTP sync retry metadata — `HttpEvent` now includes `isRetry` and `retryCount` fields.
* **FEAT**: Configurable motion sensitivity — `MotionConfig` gains `shakeThreshold`, `stillThreshold`, and `stillSampleCount` for tuning accelerometer-based motion detection.
* **FEAT**: `HealthWarningDescription` extension with `.description` getter for human-readable warning text.
* **CHORE**: Bump all platform dependencies to ^0.9.0.

## 0.8.3

* **FEAT**: Unlimited geofences via proximity-based auto-load/unload — only geofences within `geofenceProximityRadius` are registered with the OS (up to 100 on Android, 20 on iOS), sorted by distance. Enables monitoring thousands of geofences despite platform limits.
* **FEAT**: `geofencesChange` event fires when geofences are activated/deactivated from proximity monitoring.
* **CHORE**: Bump all platform dependencies to ^0.8.3.

## 0.8.2

* **DOCS**: Improve README visuals with combined Android & iOS demo image.

## 0.8.1

* **PERF**: iOS background hardening — all native operations (location persist, HTTP sync, headless engine boot, lifecycle transitions) now wrapped in `beginBackgroundTask` for safe background execution.
* **FEAT**: iOS 17+ `CLBackgroundActivitySession` support — extends background runtime for location tracking.
* **FEAT**: iOS 18+ `CLServiceSession` support — maintains authorization state during background execution.
* **FIX**: iOS `preventSuspend` lifecycle gaps — audio keep-alive now correctly started/stopped in all tracking modes and transitions.
* **FIX**: Web EventChannel bridge — all event streams (`onLocation`, `onMotionChange`, `onHeartbeat`, etc.) were broken on web due to events being consumed but never forwarded. Now works correctly.
* **CHORE**: Bump `tracelet_ios` to ^0.8.1, `tracelet_web` to ^0.8.1.

## 0.8.0

* **FEAT**: OEM compatibility — automatic mitigations for aggressive OEM power management (Huawei, Xiaomi, OnePlus, Samsung, Oppo, Vivo).
* **FEAT**: `Tracelet.getSettingsHealth()` — device health API returning manufacturer, aggression rating, battery optimization status, and available OEM settings screens.
* **FEAT**: `Tracelet.openOemSettings(label)` — open OEM-specific settings screens (autostart, battery saver, app launch) by label.
* **DOCS**: Comprehensive [OEM-COMPATIBILITY.md](help/OEM-COMPATIBILITY.md) guide with per-manufacturer instructions.
* **DOCS**: Update README with OEM compatibility feature and documentation link.
* **CHORE**: Bump all platform dependencies to ^0.8.0.

## 0.7.1

* **DOCS**: Add mock location detection feature to README with documentation links and feature description.
* **DOCS**: Add Mock Detection guide to documentation table.
* **CHORE**: Bump all platform dependencies to ^0.7.1.

## 0.7.0

* **FEAT**: Mock location detection & prevention — detect and reject spoofed GPS locations across Android, iOS, and Web.
* **FEAT**: `Location.isMock` field — boolean flag indicating if a location came from a mock provider.
* **FEAT**: `Location.mockHeuristics` field — `MockHeuristics` metadata (satellite count, elapsed realtime drift, timestamp drift, platform flag).
* **FEAT**: `LocationFilter.rejectMockLocations` config — block spoofed locations from reaching the app.
* **FEAT**: `LocationFilter.mockDetectionLevel` config — `MockDetectionLevel` enum (`disabled`, `basic`, `heuristic`) for configurable detection depth.
* **FEAT**: `ProviderChangeEvent.mockLocationsDetected` — real-time alert when mock locations are detected.
* **FEAT**: Re-export `MockDetectionLevel` from `tracelet.dart` barrel file.
* **DOCS**: Comprehensive [MOCK-DETECTION.md](help/MOCK-DETECTION.md) guide.
* **DOCS**: Updated [CONFIGURATION.md](help/CONFIGURATION.md) with mock detection options.
* **CHORE**: Bump all platform dependencies to ^0.7.0.

## 0.6.1

* **CHORE**: Bump all platform dependencies to ^0.6.1.

## 0.6.0

* **FEAT**: Integrate shared Dart `LocationProcessor` into `onLocation` stream — distance filtering, elasticity, accuracy filtering, and speed filtering now run in Dart for cross-platform consistency.
* **FEAT**: Integrate shared Dart `GeofenceEvaluator` for high-accuracy proximity checks.
* **FIX**: Fix broadcast stream bug — stateful `LocationProcessor` and `KalmanLocationFilter` were called once per listener per event, causing second subscriber to see distance=0 and filter all locations. Now uses cached `.asBroadcastStream()` so transformations run exactly once.
* **PERF**: Native code no longer duplicates filtering logic — significantly reduces native code surface.
* **CHORE**: Bump all platform dependencies to ^0.6.0.

## 0.5.5

* **FIX**: iOS `onSchedule` event now sends full state map instead of partial data.
* **CHORE**: Bump all platform dependencies to ^0.5.5.

## 0.5.4

* **FIX**: Heartbeat events no longer return zero coordinates on Android and iOS.

## 0.5.3

* **CHORE**: Bump all platform dependencies to ^0.5.3.

## 0.5.2

* **FEAT**: `disableMotionActivityUpdates` now falls back to permission-free accelerometer-only motion detection instead of disabling all motion detection entirely.
* **DOCS**: Expanded `MotionConfig.disableMotionActivityUpdates` documentation with fallback behavior, use cases, and battery notes.
* **DOCS**: Updated `getMotionPermissionStatus()` / `requestMotionPermission()` docs to reflect accelerometer-only mode behavior.
* **DOCS**: Added "Opting Out of Motion Permission" section to PERMISSIONS.md with comparison table.

## 0.5.1

* **DOCS**: Update README with web platform in architecture and documentation tables.

## 0.5.0

* **FEAT**: Add web platform support via `tracelet_web` package.
* **FEAT**: Guard `registerHeadlessTask()` for web compatibility (`kIsWeb` early return).
* **DOCS**: Add Web Support guide (`help/WEB-SUPPORT.md`) with full API compatibility matrix.
* **DOCS**: Update README with web platform in architecture table and documentation links.
* **CHORE**: Bump all platform dependencies to ^0.5.0.

## 0.4.0

* **FEAT**: `getMotionPermissionStatus()` and `requestMotionPermission()` APIs for activity recognition permission.
* **FIX**: Speed always zero in motionchange events — track `lastEffectiveSpeed` across location updates.
* **DOCS**: Split README into focused help guides (Permissions, Background Tracking, API, Configuration).
* **DOCS**: Add side-by-side Android/iOS demo recordings.
* **CHORE**: Bump all platform dependencies to ^0.4.0.
* **CHORE**: Format all Dart files.

## 0.3.0

* **FEAT**: One-shot location — `getCurrentPosition()` now supports `persist`, `samples`, `maximumAge`, and `extras` parameters for enterprise single-time location requests.
* **FEAT**: `getLastKnownLocation()` — returns the last cached location without triggering the GPS, or `null` if unavailable.
* **FEAT**: `ForegroundServiceConfig.enabled` — disable foreground service/notification for lightweight one-shot requests.
* **BREAKING**: Bump all platform dependencies to ^0.3.0.

## 0.2.5

* Fix LICENSE file format for proper SPDX detection on pub.dev.
* Bump `tracelet_android` dependency to ^0.2.3.
* Bump `tracelet_ios` dependency to ^0.2.4.

## 0.2.4

* Bump `tracelet_android` dependency to ^0.2.2 (fixes config not applied to foreground notification).
* Bump `tracelet_ios` dependency to ^0.2.3 (fixes config values ignored on iOS).

## 0.2.3

* Bump `tracelet_ios` dependency to ^0.2.2 (fixes iOS `ConfigManager` crash).

## 0.2.2

* Fix dangling library doc comment lint in `_helpers.dart`.

## 0.2.1

* Add `tracelet_android` and `tracelet_ios` as explicit dependencies to fix default plugin resolution warnings.

## 0.2.0

* Add `isMoving` field to `State` model.
* Fix `Config.toMap()` — use nested map structure to prevent extras key collision.
* Fix `watchPosition` listener leak — subscriptions now tracked and cancelled.
* Fix `removeListeners()` to cancel all Dart-side stream subscriptions.
* Change `LogLevel` default from `off` to `info`.
* Complete `==`/`hashCode` on all sub-config classes.
* Extract shared deserialization helpers to reduce code duplication.
* Fix example (`LogConfig` → `LoggerConfig`).

## 0.1.1

* Fix pubspec description length for pub.dev scoring.
* Add SPDX `license: Apache-2.0` identifier.
* Add `example/main.dart` for pub.dev documentation score.

## 0.1.0

* Initial release.
* Full background geolocation API with 38 public methods.
* 14 real-time event streams (location, motion, geofence, HTTP, etc.).
* Comprehensive config system: GeoConfig, AppConfig, HttpConfig, MotionConfig, GeofenceConfig, PersistenceConfig, LoggerConfig.
* Elasticity-based distance filter scaling.
* Location filtering and denoising.
* Headless Dart execution for background events.
* Scheduling with cron-like expressions.
* `removeListeners()` for centralized cleanup.