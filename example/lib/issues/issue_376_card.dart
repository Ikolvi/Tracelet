import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #376 — the tracking notification can carry an OS-rendered elapsed
/// timer, and can be updated without a `Config` round trip.
///
/// **Where this card's evidence comes from.** Rows are not all the same kind of
/// evidence, so each one is tagged in the status output with what it was read
/// from: `[native log]`, `[native State]` or `[Dart mirror]`.
///
/// The timer rows are `[native log]`: lines written by Kotlin, read back via
/// [Tracelet.getLogs], carrying the values the Android `ConfigManager` handed
/// to the notification builder. That channel matters because
/// `Tracelet.getState().config` is backfilled from the Dart mirror
/// `_currentConfig`, which `setConfig` merges into *before* it calls the
/// platform. A card that read the timer fields back that way would be
/// asserting that a Dart field holds what the card itself had just written
/// into it — which is what the first version of this card did, and it proved
/// nothing.
///
/// The line those rows key off:
///
/// ```
/// chronometer applied: when=… startedAt=… clamped=…
/// ```
///
/// **What that line proves.** It is logged inside `applyChronometer`
/// (`LocationService.kt:56`) immediately after `setWhen` / `setShowWhen` /
/// `setUsesChronometer`, and the values it prints are the ones passed to those
/// setters. So it evidences *that the builder was configured with those
/// values*.
///
/// **What it does not prove.** It fires before `builder.build()`
/// (`LocationService.kt:1765`) and before `nm.notify(…)` (`:1770`). It is
/// therefore not evidence that a notification was built, posted, or rendered.
/// No row here says "drew" — the wording throughout is "configured the
/// builder", and that is the strongest claim the line supports.
///
/// **How far the round trip is proven.** `buildNotification` passes
/// `configManager.getFgNotificationStartedAt()` / `…ShowTimer()` into
/// `applyChronometer` (`LocationService.kt:1757-1762`). Those getters read the
/// in-memory `configCache` (`ConfigManager.kt:545-549`), and `setConfig`
/// assigns that cache (`:250`) *before* it calls `persistToPrefs` (`:251`). So
/// a `startedAt` equal to the one this card supplied proves
/// Dart → Pigeon → native in-memory config → notification builder, and stops
/// there. **Durability is not measured.** SharedPreferences could be failing
/// outright and every row below would still pass; nothing here restarts the
/// process or re-reads from disk.
///
/// **What it does not claim.** It cannot see what the lock screen or shade
/// drew, whether the clock is ticking, or whether the device alerted. Those are
/// reported at the end as things for the operator to look at, never as rows. A
/// card reporting PASS for something it never measured is worse than no card,
/// because it will be believed.
///
/// **On iOS it takes a different route.** The markers above are Android
/// foreground-service logs and have no Live Activity equivalent, so rather than
/// refuse to run — or worse, assert against the Dart mirror it just wrote to —
/// the card drives the Live Activity end to end and hands the judging over: it
/// enables the timer, holds a window open for you to look at the Lock Screen,
/// reposts text-only to show the clock does not restart, and reports what
/// should have happened without claiming a single pass.
class Issue376Card extends StatefulWidget {
  const Issue376Card({super.key});

  @override
  State<Issue376Card> createState() => _Issue376CardState();
}

class _Issue376CardState extends State<Issue376Card> {
  String _status = 'Idle';
  bool _running = false;

  /// Written by `applyChronometer` on the branch that calls the three builder
  /// setters — so its presence means they were called with the values it
  /// prints, and its absence means the function returned before them. It says
  /// nothing about the build or the post that follow it.
  static const _chronometerMarker = 'chronometer applied:';

  /// `LocationService.onStartCommand` logs the action of every intent it
  /// receives, before it builds anything. Finding this line proves the repost
  /// reached the service; finding a chronometer line with a *higher id* proves
  /// the rebuild that followed it is the one this card provoked.
  static const _repostMarker =
      'onStartCommand: action=com.tracelet.ACTION_UPDATE_NOTIFICATION';

  /// The negative path: `TraceletSdk.updateNotification` refuses to dispatch
  /// when the service is not promoted. Quoted in failure diagnostics because it
  /// separates "the feature is broken" from "there was no notification to
  /// update".
  static const _serviceNotRunningMarker =
      'updateNotification: foreground service not running';

  /// The degenerate branch of `applyChronometer` — `showTimer` on with no
  /// start instant. Quoted in diagnostics for the same reason.
  static const _noStartInstantMarker =
      'notificationShowTimer is set but notificationStartedAt is not';

  /// Pause-only mode demoting the service while the app is on screen. The
  /// service still receives repost intents in that state but rebuilds nothing
  /// (`LocationService.kt:716-727`), so this line separates "the timer fields
  /// were missing" from "there was nothing to rebuild".
  static const _suppressedMarker =
      'Suppressing notification (App in foreground)';

  /// `when=… startedAt=… clamped=…` out of the applied line.
  static final _chronometerValues = RegExp(
    r'when=(\d+) startedAt=(\d+) clamped=(true|false)',
  );

  /// The repost is dispatched through `startService`, so the rebuild happens
  /// asynchronously and cannot be awaited — every assertion polls for it.
  /// One constant for every wait, so a slow emulator is a one-line change.
  static const _pollBudget = Duration(seconds: 8);
  static const _pollInterval = Duration(milliseconds: 500);

  /// 500 matches the #357 card. Verbose tracking logging is chatty and the
  /// store is row-capped, so the markers are always taken immediately before
  /// the step that has to be observed.
  static const _logFetchLimit = 500;

  /// Two hours back, so a rendered chronometer reads about "2:00:00" and the
  /// operator can tell at a glance that it started from the supplied instant
  /// rather than from the moment of the call.
  static const _elapsedForDisplay = Duration(hours: 2);

  /// Long enough to look at the shade before the card turns the timer off
  /// again. The opt-out step has to come last (it is the end state the closing
  /// instructions describe), so the looking has to happen here.
  static const _observationSeconds = 20;

  /// Gives the service time to *not* log a chronometer line, before the opt-out
  /// row asserts that it did not.
  static const _absenceSettle = Duration(seconds: 2);

  /// Bound on how long to wait, after `start()` returns, for the native
  /// `isRunning` flag to flip true inside `onStartCommand`
  /// (LocationService.kt:688) — see the call site in step 2 for why this
  /// wait exists at all.
  static const _serviceStartTimeout = Duration(seconds: 5);
  static const _serviceStartPollInterval = Duration(milliseconds: 100);

  void _set(String s) {
    if (mounted) setState(() => _status = s);
  }

  /// Writes only the notification fields, then reposts the indicator.
  ///
  /// `setConfig` is a partial update on both sides (#320, #321): a field left
  /// null here is *not supplied* rather than *set to its default*, so
  /// everything this does not name — `http.url` and `headers` included — keeps
  /// the value the platform already persisted. That is what makes a content
  /// update safe without a bespoke payload type.
  ///
  /// `setConfig` persists; `updateNotification()` is what pushes the change
  /// onto the notification already on screen (#257).
  ///
  /// The iOS half is sent too, so running this card on a device drives the Live
  /// Activity as well as the Android notification. It is built differently on
  /// purpose: `ForegroundServiceConfig` tracks each field's unset state, so the
  /// nulls above are simply not supplied, whereas `LiveActivityConfig` requires
  /// `title` and `body` and iOS replaces the whole `liveActivityConfig` map on
  /// write. Passing only the timer fields would therefore blank the text, so
  /// the unsupplied fields are carried over from the active config instead.
  Future<void> _setNotification({
    String? title,
    String? text,
    int? startedAt,
    bool? showTimer,
  }) async {
    final live = Tracelet.activeConfig.ios.liveActivityConfig;

    await Tracelet.setConfig(
      Config(
        android: AndroidConfig(
          foregroundService: ForegroundServiceConfig(
            notificationTitle: title,
            notificationText: text,
            notificationStartedAt: startedAt,
            notificationShowTimer: showTimer,
          ),
        ),
        ios: live == null
            ? const IosConfig()
            : IosConfig(
                liveActivityConfig: LiveActivityConfig(
                  title: title ?? live.title,
                  body: text ?? live.body,
                  startedAt: startedAt ?? live.startedAt,
                  showTimer: showTimer ?? live.showTimer,
                ),
              ),
      ),
    );
    await Tracelet.updateNotification();
  }

  /// The iOS half of #376, driven end to end and reported for the operator to
  /// judge.
  ///
  /// Deliberately asserts nothing. iOS exposes no read-back for what a Live
  /// Activity rendered: `getLogs()` carries no equivalent of the Android
  /// builder line, and `getState().config` is backfilled from the Dart mirror
  /// this card just wrote to, so a row keyed off it would only be checking
  /// that `setConfig` assigned a Dart field. What this flow *can* do is put
  /// the feature in front of you in a state where the answer is visible on the
  /// Lock Screen.
  Future<void> _runIos() async {
    try {
      _set('1/4 — configuring a Live Activity with the timer enabled…');

      // A complete LiveActivityConfig rather than a partial one: iOS replaces
      // the whole liveActivityConfig map on write, and title/body are required.
      final startedAt = DateTime.now().subtract(_elapsedForDisplay);

      await Tracelet.setConfig(
        Config(
          logger: const LoggerConfig(logLevel: LogLevel.verbose, debug: true),
          ios: IosConfig(
            liveActivityConfig: LiveActivityConfig(
              title: 'Issue 376 — shift in progress',
              body: 'Timer requested; started two hours ago',
              startedAt: startedAt.millisecondsSinceEpoch,
              showTimer: true,
            ),
          ),
        ),
      );

      _set('2/4 — starting tracking so the Live Activity is presented…');
      await Tracelet.start();
      await Tracelet.updateNotification();

      for (var left = _observationSeconds; left > 0; left--) {
        _set(
          '3/4 — LOOK AT THE LOCK SCREEN OR DYNAMIC ISLAND NOW. The Live '
          'Activity should show a clock reading about 2:00:00 and counting '
          'up. ${left}s…',
        );
        await Future<void>.delayed(const Duration(seconds: 1));
      }

      // The point of the repost: the clock must not jump back to zero. The
      // persisted startedAt is the only source of truth, so changing the body
      // reconfigures the activity from the same instant.
      _set('4/4 — reposting with new text only; the clock must not restart…');
      await _setNotification(
        text: 'Reposted — the elapsed time must not jump back to zero',
      );
      await Future<void>.delayed(const Duration(seconds: 4));

      _set(
        'DRIVEN, NOT ASSERTED — iOS gives this card nothing to read back, so '
        'every line below is for you to confirm by looking. No row here '
        'claims a pass.\n\n'
        'What should have happened:\n'
        '• A Live Activity appeared with the title "Issue 376 — shift in '
        'progress".\n'
        '• It showed a clock counting up from about 2:00:00 — rendered by iOS '
        'via Text(timerInterval:), not by any update this card sent. The SDK '
        'pushed no periodic updates to advance it.\n'
        '• At step 4 the body text changed and the clock kept counting rather '
        'than restarting, because the persisted startedAt is the only source '
        'of truth.\n\n'
        'If you saw no clock at all, the most likely cause is the Widget '
        'Extension rather than the SDK: a custom TraceletActivityAttributes '
        'whose ContentState lacks startedAt/showTimer decodes the payload '
        "fine and simply draws nothing. This example app compiles the SDK's "
        'own TraceletActivityAttributes.swift into the widget target, so it '
        'has the fields; a host app that hand-copied the struct from the docs '
        'must add them.\n\n'
        'If you saw no Live Activity at all: it requires iOS 16.2+, a Widget '
        'Extension in the build, NSSupportsLiveActivities in Info.plist, and '
        'Live Activities enabled for this app in Settings. It is also bound to '
        'the moving sub-state, so it can be dismissed when tracking pauses on '
        'going stationary.\n\n'
        'Cleanup: the timer is left ON here, unlike the Android flow, because '
        'the whole point is that you can still look at it after the card '
        'finishes. Re-run any other card to restore the demo baseline.',
      );
    } catch (e, s) {
      _set('❌ ERROR — $e\n\n$s');
    }
  }

  /// Highest log id currently stored — the window boundary.
  ///
  /// Ids rather than timestamps: monotonic, no date parsing, and they order the
  /// intent against the rebuild it caused.
  Future<int> _latestLogId() async {
    final logs = await Tracelet.getLogs(_logFetchLimit);
    return logs.fold<int>(0, (max, e) => e.id > max ? e.id : max);
  }

  Future<List<LogEntry>> _linesSince(int sinceId, String marker) async {
    final logs = await Tracelet.getLogs(_logFetchLimit);
    return logs
        .where((e) => e.id > sinceId && e.message.contains(marker))
        .toList();
  }

  /// Waits for the first line after [sinceId] containing [marker], or null if
  /// the budget runs out.
  Future<LogEntry?> _awaitLine(int sinceId, String marker) async {
    final deadline = DateTime.now().add(_pollBudget);
    while (true) {
      final hits = await _linesSince(sinceId, marker);
      if (hits.isNotEmpty) return hits.first;
      if (DateTime.now().isAfter(deadline)) return null;
      await Future<void>.delayed(_pollInterval);
    }
  }

  /// Whether any line after [sinceId] contains [marker] (no waiting).
  Future<bool> _sawLine(int sinceId, String marker) async =>
      (await _linesSince(sinceId, marker)).isNotEmpty;

  /// Polls `getForegroundServiceHealth()['serviceRunning']` until it reports
  /// true or [_serviceStartTimeout] elapses. Does not fail the card on
  /// timeout: if the service genuinely never comes up, the row-2 diagnostic
  /// below already names that case correctly. This only removes the false
  /// failure where the service *would* have come up, but the first
  /// [_setNotification] was sent before it did.
  Future<bool> _awaitServiceRunning() async {
    final deadline = DateTime.now().add(_serviceStartTimeout);
    while (true) {
      final health = await Tracelet.getForegroundServiceHealth();
      if (health['serviceRunning'] == true) return true;
      if (DateTime.now().isAfter(deadline)) return false;
      await Future<void>.delayed(_serviceStartPollInterval);
    }
  }

  /// The three values the native line logged, or null if the line is not one of
  /// ours / the format moved.
  ({int when, int startedAt, bool clamped})? _values(LogEntry? entry) {
    if (entry == null) return null;
    final m = _chronometerValues.firstMatch(entry.message);
    if (m == null) return null;
    return (
      when: int.parse(m.group(1)!),
      startedAt: int.parse(m.group(2)!),
      clamped: m.group(3) == 'true',
    );
  }

  /// One notification update, observed as far as the logs go: the intent
  /// reaching the service, then the `applyChronometer` line that followed *it*
  /// (id ordering, not just "some line appeared").
  ///
  /// `marker` is taken by the caller before it calls [_setNotification], so
  /// both halves are attributable to that call.
  Future<({LogEntry? repost, LogEntry? applied})> _observeBuilderCall(
    int marker,
  ) async {
    final repost = await _awaitLine(marker, _repostMarker);
    if (repost == null) return (repost: null, applied: null);
    final applied = await _awaitLine(repost.id, _chronometerMarker);
    return (repost: repost, applied: applied);
  }

  /// Failure text that says which of the two failures this was — the whole
  /// point of watching the intent as well as the chronometer line.
  Future<String> _diagnose(
    int marker,
    ({LogEntry? repost, LogEntry? applied}) o,
  ) {
    if (o.repost == null) {
      return _serviceDiagnostic(marker);
    }
    return _builderDiagnostic(marker);
  }

  Future<String> _serviceDiagnostic(int marker) async {
    final refused = await _sawLine(marker, _serviceNotRunningMarker);
    return refused
        ? 'the SDK logged "$_serviceNotRunningMarker" — the foreground service '
              'was not running, so there was no notification to update. Not a '
              'chronometer failure; check that tracking really started'
        : 'no "$_repostMarker" line within ${_pollBudget.inSeconds}s — the '
              'repost never reached the service. Check the '
              'showNotificationOnPauseOnly override this card applies';
  }

  Future<String> _builderDiagnostic(int marker) async {
    if (await _sawLine(marker, _noStartInstantMarker)) {
      return 'the service reposted and logged "$_noStartInstantMarker" — '
          'showTimer survived the trip to the native config but the start '
          'instant did not';
    }
    // onStartCommand logs the action (LocationService.kt:650) before the
    // ACTION_UPDATE_NOTIFICATION branch checks isForegroundService (:716-727),
    // so "the intent arrived" does not imply "the notification was rebuilt".
    // Both causes are named rather than guessing between them.
    final suppressed = await _sawLine(marker, _suppressedMarker);
    return 'the service received the repost intent but logged no '
        '"$_chronometerMarker" line. Two causes look identical from here: the '
        'native config did not hold the timer fields when the notification was '
        'rebuilt (the regression this card exists to catch), or the service '
        'was not promoted to the foreground, in which case it took the intent '
        'and rebuilt nothing. '
        '${suppressed ? 'A "$_suppressedMarker" line is present after the '
                  'marker, which points at the second: pause-only mode won over '
                  'the override this card applies.' : 'No "$_suppressedMarker" '
                  'line is present, which is weak evidence against the second.'}';
  }

  Future<void> _run() async {
    setState(() => _running = true);

    // iOS has no equivalent evidence channel: the markers below are Android
    // service logs, and the Live Activity path writes nothing this card can
    // read. So iOS gets its own flow that *drives* the feature and hands the
    // judging to the operator, rather than rows that would be asserting
    // nothing. Reporting green off a Dart field the card itself wrote is the
    // failure mode this whole card exists to avoid.
    if (defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb) {
      await _runIos();
      setState(() => _running = false);
      return;
    }

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      _set(
        'NOT RUN — this card covers the Android notification-build path and '
        'the iOS Live Activity. There is no tracking indicator to drive on '
        'this platform.',
      );
      setState(() => _running = false);
      return;
    }

    final results = <String>[];
    var allPass = true;

    void check(String name, bool pass, String detail) {
      results.add('${pass ? '✅' : '❌'} $name — $detail');
      if (!pass) allPass = false;
    }

    try {
      // ── 1. Prepare ───────────────────────────────────────────────────────
      _set('1/6 — configuring and starting tracking…');

      // Merged onto the harness baseline (setConfig is a partial update on both
      // sides — Dart mirrors the native merge at tracelet.dart:485-486 — so
      // everything buildDemoConfig set survives).
      //
      // showNotificationOnPauseOnly is not cosmetic here: the demo baseline
      // sets it true (demo_config.dart:56-57), which un-promotes the service
      // while the app is on screen, and ACTION_UPDATE_NOTIFICATION only reposts
      // content while promoted (LocationService.kt:716-727). With it left true
      // this card would observe nothing at all, and the operator could not look
      // at the notification either. The logger override is what puts the debug
      // lines in the store to be read.
      await Tracelet.setConfig(
        const Config(
          logger: LoggerConfig(logLevel: LogLevel.verbose, debug: true),
          android: AndroidConfig(
            foregroundService: ForegroundServiceConfig(
              showNotificationOnPauseOnly: false,
              notificationTitle: 'Issue 376',
              notificationText: 'Baseline, before any timer is requested',
            ),
          ),
        ),
      );

      // Snapshot for the last row. The card deliberately never *writes* http:
      // buildDemoConfig reads its own url back through
      // `activeConfig.http.url ?? …` (demo_config.dart:82-87), so a sentinel
      // written here would propagate into every later card in this session and
      // could not be cleared (a null field is skipped by the merge).
      final baselineHttpUrl = Tracelet.activeConfig.http.url;

      await Tracelet.start();

      final startState = await Tracelet.getState();
      check(
        '[native State] tracking is enabled — the desired state, not proof the '
            'service was promoted',
        startState.enabled,
        'enabled=${startState.enabled} trackingMode=${startState.trackingMode}, '
            'read from the native State rather than the Dart config mirror. '
            'State.enabled is *desired* state: the SDK documents that a '
            'foreground-service start can be deferred or rejected on Android 12+ '
            'while enabled stays true (TraceletSdk.kt:2759-2766), so this row does '
            'not assert the service is promoted. Promotion is not measured by any '
            'row below either — their evidence is a builder-configuration log '
            '(LocationService.kt:56) emitted before build() (:1765) and notify() '
            '(:1770), so a green row proves the builder was configured, not that '
            'a notification existed to update. Their diagnostics do name the case '
            'where the repost intent never reached the service at all',
      );

      // ── 2. Enable the timer ──────────────────────────────────────────────
      _set('2/6 — requesting the timer via setConfig + updateNotification…');

      // Tracelet.start() only dispatches startForegroundService; the native
      // isRunning flag that updateNotification() gates on is set later,
      // inside onStartCommand (LocationService.kt:649-689), which runs
      // asynchronously after start() returns. Racing ahead with the first
      // repost risks losing that race — updateNotification()
      // would see isRunning still false and refuse the update
      // (TraceletSdk.kt:1692-1695), which this card would otherwise report
      // as a chronometer failure it did not cause. Closed once, up front.
      await _awaitServiceRunning();

      final startedAt = DateTime.now()
          .subtract(_elapsedForDisplay)
          .millisecondsSinceEpoch;

      var marker = await _latestLogId();
      await _setNotification(
        title: 'Issue 376 — shift in progress',
        text: 'Timer requested; started two hours ago',
        startedAt: startedAt,
        showTimer: true,
      );

      final enable = await _observeBuilderCall(marker);
      final enabled = _values(enable.applied);
      check(
        '[native log] the builder was configured with the start instant this '
        'card supplied',
        enabled != null &&
            enabled.startedAt == startedAt &&
            enabled.when == startedAt &&
            !enabled.clamped,
        enabled == null
            ? await _diagnose(marker, enable)
            : 'native line: when=${enabled.when} startedAt=${enabled.startedAt} '
                  'clamped=${enabled.clamped}, supplied $startedAt. The only code '
                  'path to applyChronometer on a repost reads the config cache '
                  '(LocationService.kt:1757-1762), so equality here means the '
                  'value made the trip Dart → Pigeon → native in-memory config → '
                  'builder. Not measured here: whether it was persisted to SharedPreferences '
                  '(the getter reads the cache, not the file), and whether the '
                  'notification was then built or posted (this line is logged '
                  'before both)',
      );

      // ── 3. Observation window ────────────────────────────────────────────
      // The looking has to happen here. Step 5 resets the visible clock to zero
      // (it clamps a future instant to the rebuild time) and step 6 ends with
      // the timer off, which is the state the closing instructions describe —
      // so this is the only window where a clock reading 2:00:00 is on screen.
      for (var left = _observationSeconds; left > 0; left--) {
        _set(
          '3/6 — OPEN THE NOTIFICATION SHADE NOW. The notification should show '
          'a clock reading about 2:00:00 and counting up. ${left}s…',
        );
        await Future<void>.delayed(const Duration(seconds: 1));
      }

      // ── 4. Text-only repost ──────────────────────────────────────────────
      _set('4/6 — reposting with new text only…');
      marker = await _latestLogId();
      await _setNotification(
        text: 'Reposted — the elapsed time must not jump back to zero',
      );

      final repost = await _observeBuilderCall(marker);
      final reposted = _values(repost.applied);
      check(
        '[native log] a text-only repost reconfigured the builder from the same '
        'start instant, not from the time of the call',
        reposted != null &&
            reposted.startedAt == startedAt &&
            reposted.when == startedAt &&
            !reposted.clamped,
        reposted == null
            ? await _diagnose(marker, repost)
            : 'the service took the repost intent, then logged '
                  'when=${reposted.when} startedAt=${reposted.startedAt} '
                  'clamped=${reposted.clamped} — both values unchanged from '
                  'step 2 ($startedAt). `when` is the value setWhen received, '
                  'so it is asserted as well as '
                  'startedAt: a regression that kept startedAt for logging but '
                  'called setWhen(now) would move `when` to the time of this '
                  'call and fail here',
      );

      // ── 5. A future start instant ────────────────────────────────────────
      _set('5/6 — supplying a start instant in the future…');
      final future = DateTime.now()
          .add(const Duration(hours: 1))
          .millisecondsSinceEpoch;

      marker = await _latestLogId();
      // The clamp is asserted to land inside a bracket, not merely to be
      // "earlier than startedAt": `when < startedAt` alone would accept 0, or
      // any stale instant, while the row claims it counts from the moment the
      // notification was rebuilt. Both ends of the bracket are read from the
      // same device clock the native code stamps into `when`
      // (System.currentTimeMillis), so they are directly comparable.
      final beforeCall = DateTime.now().millisecondsSinceEpoch;
      await _setNotification(startedAt: future, showTimer: true);

      final futureBuild = await _observeBuilderCall(marker);
      final clamped = _values(futureBuild.applied);
      final afterObserved = DateTime.now().millisecondsSinceEpoch;
      check(
        '[native log] a future start instant is kept as supplied, and the '
        'value passed to setWhen falls inside the bracketed wall-clock window',
        clamped != null &&
            clamped.startedAt == future &&
            clamped.clamped &&
            clamped.when >= beforeCall &&
            clamped.when <= afterObserved,
        clamped == null
            ? await _diagnose(marker, futureBuild)
            : 'native line: startedAt=${clamped.startedAt} (supplied $future, '
                  'so the native config kept it unchanged) but '
                  'when=${clamped.when} clamped=${clamped.clamped}. That '
                  '`when` falls inside [$beforeCall, $afterObserved] — the '
                  'instant before this card made the call, and the instant it '
                  'saw the line — so the value passed to setWhen falls inside '
                  'that bracket, not the future instant and not a stale value. '
                  'Both halves are read off the same line, which is why the '
                  'clamp can be shown not to have been written back into the '
                  'config',
      );

      // ── 6. Opting out ────────────────────────────────────────────────────
      // Three calls, because the absence of a log line is weak evidence on its
      // own: off (expect silence), on again (expect a line — the control), off
      // again (the end state the card leaves behind). Without the control in
      // the middle, a dead build path, an exception thrown before
      // applyChronometer, or a lost start instant would all read the same as a
      // working opt-out.
      _set(
        '6/6 — turning the timer off, proving the path is alive, off again…',
      );

      // Sent with the opt-out so the config is not left holding the step-5
      // future instant: a later card setting notificationShowTimer: true
      // would otherwise reactivate an hour-ahead start (buildDemoConfig sets
      // neither timer field, and the native merge skips nulls, so nothing else
      // clears it).
      final saneStartedAt = DateTime.now().millisecondsSinceEpoch;
      marker = await _latestLogId();
      await _setNotification(
        showTimer: false,
        startedAt: saneStartedAt,
        text: 'Timer disabled — the notification should now show no clock',
      );

      final optOut = await _awaitLine(marker, _repostMarker);
      // The absence has to be given time to be an absence: wait past the point
      // where the line would have been written, then look.
      if (optOut != null) await Future<void>.delayed(_absenceSettle);
      final loggedAnyway =
          optOut != null && await _sawLine(optOut.id, _chronometerMarker);
      check(
        '[native log, negative] with showTimer:false no chronometer line '
        'followed the repost',
        optOut != null && !loggedAnyway,
        optOut == null
            ? await _serviceDiagnostic(marker)
            : loggedAnyway
            ? 'the service reposted and still logged "$_chronometerMarker" — '
                  'the opt-out did not reach the native config, or the rebuild '
                  'ignored it'
            : 'the repost intent reached the service (id ${optOut.id}) and no '
                  '"$_chronometerMarker" line appeared in the '
                  '${_absenceSettle.inSeconds}s after it. This is a negative '
                  'result and it is weaker than the rows above: it shows the '
                  'line was not written, which is consistent with '
                  'applyChronometer returning early, but silence alone cannot '
                  'distinguish that from a rebuild that never happened. The '
                  'control row below shows the path working again '
                  'immediately after this window, which makes a '
                  'silently-aborted rebuild during it less likely but does '
                  'not exclude one',
      );

      // The control. Flip only showTimer back on: if a line appears carrying
      // the instant supplied with the opt-out, then the intent path, the
      // rebuild and the log channel were all working again immediately after
      // the silent window, and the start instant was still in the config at
      // that point — evidence that makes the silence above attributable to
      // showTimer:false rather than a broken path, though it cannot see
      // inside the window itself.
      marker = await _latestLogId();
      await _setNotification(showTimer: true);

      final control = await _observeBuilderCall(marker);
      final controlValues = _values(control.applied);
      check(
        '[native log] control — flipping showTimer back on made the line '
        'reappear, so the path was working again immediately after the '
        'silent window',
        controlValues != null && controlValues.startedAt == saneStartedAt,
        controlValues == null
            ? '${await _diagnose(marker, control)}. Because this control '
                  'failed, the negative row above proves nothing: the silence '
                  'it observed cannot be attributed to showTimer:false'
            : 'native line: when=${controlValues.when} '
                  'startedAt=${controlValues.startedAt} '
                  'clamped=${controlValues.clamped}, matching the '
                  '$saneStartedAt sent with the opt-out. So the '
                  'builder-configuration line was produced immediately before '
                  'the silent window (step 2 onward) and again immediately '
                  'after it. That makes the builder configuration being '
                  'skipped silently during the window less likely, but this '
                  'line cannot see inside the window itself, so it does not '
                  'exclude one',
      );

      // Back off again, so the card ends where its closing instructions say it
      // does. Not asserted: it is the same weak negative as the row above, and
      // repeating it would add a row without adding evidence.
      //
      // startedAt is refreshed here too, as close to the card's actual end as
      // the API allows, rather than left at saneStartedAt (captured several
      // polling rounds earlier, at the start of step 6). Neither field can be
      // cleared (see the closing text below), so the freshest instant this
      // card can leave behind is the best it can do for whatever inherits it.
      marker = await _latestLogId();
      final finalStartedAt = DateTime.now().millisecondsSinceEpoch;
      await _setNotification(
        showTimer: false,
        startedAt: finalStartedAt,
        text: 'Timer disabled — the notification should now show no clock',
      );
      await _awaitLine(marker, _repostMarker);

      // ── 7. The Dart mirror's http.url ────────────────────────────────────
      // Honest scope: this is a Dart-side check. Every write above went through
      // setConfig carrying only foregroundService fields, so this verifies the
      // partial-merge guarantee (#320, #321) held across all six of them and
      // left http untouched — a real bug class for copyWith chains. It says
      // nothing about native http state, which has no read-back at all.
      final httpUrlNow = Tracelet.activeConfig.http.url;
      check(
        '[Dart mirror] the Dart config mirror reports the baseline http.url '
            'as its final state, read once after the whole sequence of '
            'notification calls above',
        httpUrlNow == baselineHttpUrl,
        'http.url=$httpUrlNow (baseline $baselineHttpUrl). This is a Dart-side '
            'field comparison, not a native read-back: it pins the partial-merge '
            'chain setConfig runs on _currentConfig, which is a real bug '
            'class, and says nothing about native http state. See NOT MEASURED '
            'below for what covers that instead',
      );

      final header = allPass
          ? '✅ PASS — all ${results.length} rows below passed. They are not the '
                'same kind of evidence, so each is tagged: [native log] rows '
                'were read back from foreground-service log lines, '
                '[native State] from getState(), [Dart mirror] from a Dart-side '
                'field, and [native log, negative] is an observed absence of a '
                'line rather than a positive observation. No row asserts what '
                'was rendered on screen.'
          : '❌ FAILED — see the rows below. Tags say what each row was read '
                'from.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'NOT MEASURED — please look and judge for yourself:\n'
        '• Whether any notification was built or posted at all. The line every '
        'row above keys off is logged inside applyChronometer '
        '(LocationService.kt:56), before builder.build() (:1765) and before '
        'nm.notify() (:1770). It evidences that the builder setters were '
        'called with those values. An exception between the log and the post, '
        'or a notification the system dropped, would look identical here.\n'
        '• What the shade or lock screen actually drew. Nothing in Dart can '
        'read it. During step 3 the notification should have shown a clock '
        'near 2:00:00 counting up, and it should have kept counting across the '
        'step 4 repost rather than restarting. Right now, after step 6, it '
        'should still be there and show no clock at all.\n'
        '• Durability. The getters the service reads at build time '
        '(ConfigManager.kt:545-549) return the in-memory config cache, which '
        'setConfig assigns before it writes SharedPreferences (:250-251). '
        'Nothing above survives a process restart to check the write landed, '
        'so a broken persist would still show every row green.\n'
        '• The alert behaviour. Each repost re-alerts unless '
        'notificationOnlyAlertOnce is set. That is audible, not readable.\n'
        '• iOS. This run measured the Android path only. Run this same card on '
        'an iOS device and it takes a different route: it drives the Live '
        'Activity and asks you to look, because iOS exposes no read-back it '
        'could honestly assert against.\n'
        '• Native http state. There is no config read-back from the platform, '
        'so the guarantee is structural rather than measured: every write above '
        'sent a Config carrying only foregroundService fields, and setConfig is '
        'a partial update on both sides (#320, #321) — an unset section is '
        'absent from the payload, so ConfigManager never sees http at all.\n\n'
        'Cleanup: the card ends with showTimer:false and notificationStartedAt '
        'refreshed to the instant immediately before this final call returns '
        '— not the hour-ahead instant step 5 used, and not the earlier '
        'saneStartedAt captured at the start of step 6. Neither field can be '
        'cleared — buildDemoConfig sets neither, and the native merge skips '
        'nulls — so a later card setting notificationShowTimer: true '
        'without supplying its own startedAt inherits this instant. How '
        'stale it is by then is not something this card controls: it '
        'depends on how long you wait before running that later card, not on '
        'anything measured here — run it immediately and the inherited '
        'chronometer will read close to zero; leave it an hour and it will '
        'read close to an hour. Left as a future instant it would be worse '
        '(a clock stuck at zero, or counting down, until the future instant '
        'passed), which is why this card refreshes it rather than leaving it '
        'as-is. The logger, pause-only, title and text overrides are all set '
        "explicitly by buildDemoConfig, so the next card's harness run "
        'restores those. Tracking is deliberately left running so you can '
        'look at the notification — note that a later card calling start() '
        'will be a no-op on this session (TraceletSdk.kt:897-915: a manual '
        'start() while already tracking only touches enabled/trackingMode '
        'and returns, it resets nothing else), so any timer-related rows in '
        'that later card would build on the state this one left rather than '
        'a clean baseline; use "Stop" on the main tab when you are done.',
      );
    } catch (e) {
      _set(
        '❌ FAILED: $e\n\n${results.join('\n')}\n\n'
        'Cleanup did not run: this card throws before its final opt-out '
        'call, so tracking may still be running and the notification timer '
        'configuration may be left partially applied (possibly still the '
        'future startedAt from step 5, or another intermediate value). '
        'Check the notification and stop tracking manually if needed.',
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'notification chronometer elapsed timer setUsesChronometer setWhen '
          'onlyAlertOnce updateNotification live activity timerInterval '
          'foreground service startedAt showTimer clamp repost 376',
      title: '#376: an OS-rendered elapsed timer in the tracking notification',
      description:
          "Reads the foreground service's own log lines back to show how the "
          'notification builder was configured: from the start instant this '
          'card supplied, unchanged across a text-only repost (both `when` and '
          'startedAt), with a future instant kept as given but the value '
          'passed to setWhen bracketed between two wall-clock reads, and '
          'with no chronometer line at all under '
          'showTimer:false — that last one a negative, backed by a control '
          'that turns the timer on again to show the path was alive. The log '
          'line is written before the notification is built or posted, so no '
          'row claims anything was rendered. What the shade drew and whether '
          'the values were persisted have no Dart read-back: reported for you '
          'to look at, never asserted. On iOS the card instead drives the Live '
          'Activity timer and asks you to look at the Lock Screen, since that '
          'path exposes nothing it could honestly assert.',
      status: _status,
      running: _running,
      onRun: _run,
    );
  }
}
