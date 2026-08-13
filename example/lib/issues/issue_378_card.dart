import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #378 — `showNotificationOnPauseOnly: true` silently defeats
/// `stopOnTerminate: false` on Android.
///
/// Pause-only visibility is implemented by *demoting* the service:
/// `updateNotificationVisibility` calls `stopForeground(STOP_FOREGROUND_REMOVE)`
/// while the app is on screen (`LocationService.kt:1870-1880`) and calls
/// `startForeground` again when `ProcessLifecycleOwner` reports the app
/// backgrounded (`:1881-1887`). Between those two points the process is running
/// a *plain* started service, not a foreground one.
///
/// That gap is what the report is about. On task removal `ActivityManager`
/// decides whether to kill the hosting process from `proc.foregroundServices`,
/// and it decides while holding its own lock — before the `onTaskRemoved`
/// callback has run on the app's main thread. So a swipe from recents inside
/// the gap kills the process, and `stopOnTerminate: false` buys nothing: no
/// headless engine, no events, no `onDetachedFromEngine`, no logs. The reporter
/// measured 0.7 s and 1.5 s gaps on an API 35 device and got one kill out of
/// three swipes.
///
/// The mitigation that was already in `onTaskRemoved` forces the notification
/// on when the task is removed. It cannot work, and this card exists partly to
/// show why: it runs after the kill decision.
///
/// **The fix** is `pauseOnlyVisibilityAllowed` (`LocationService.kt:1842`):
/// while `stopOnTerminate` is false the service is never demoted, so no window
/// exists to swipe into, and the refusal is announced once per `start()` on the
/// always-on lifecycle channel. `stopOnTerminate: true` keeps the feature
/// unchanged — nothing is promised past the swipe there. The card scores the
/// announcement too: a fix that traded a silent kill for a silent override
/// would have solved only half of what was reported.
///
/// **What each row is read from**, tagged in the output the way #376's card
/// tags its own evidence:
///
/// * `[Dart mirror]` — the configured combination, from
///   [Tracelet.activeConfig]. It says what this app asked for, not what native
///   stored; the `[native log]` rows below are what confirm native agrees.
/// * `[native log]` — lines written by Kotlin and read back through
///   [Tracelet.getLogs]: `Suppressing notification (App in foreground)`,
///   `Showing notification (App in background)`, and the always-on lifecycle
///   channel (`service: sticky restart after process death`,
///   `boot-tracking: bootstrapping`).
/// * `[native State]` — `lastForegroundTransitionAt` out of
///   [Tracelet.getForegroundServiceHealth], which `recordPromotion` stamps on
///   every successful `startForeground`. That epoch-ms value is what makes the
///   window *measurable* rather than merely visible: the log table stores
///   `datetime('now')`, one-second resolution, and the window is shorter than
///   that.
///
/// **How the window is measured.** The card observes its own
/// `AppLifecycleState.paused` — the moment the UI leaves the screen, which is
/// the moment the app becomes swipeable in recents — and on resume reads the
/// last promotion stamp. `promotionAt - uiLeftAt` is the interval during which
/// a swipe would have found no foreground service. It is captured in the
/// lifecycle callback rather than on the Run tap because re-entering the app
/// re-demotes the service, and any intent that reaches the service afterwards
/// would re-stamp the value.
///
/// **What it cannot do.** No foreground card can swipe itself out of recents,
/// so the kill row is only measured when the operator actually performs the
/// swipe inside the window. Its absence is reported as NOT MEASURED, never as a
/// pass. The window row, by contrast, needs nothing but a Home press and is the
/// reproduction proper: a non-zero window *is* the bug, whether or not a swipe
/// happened to land in it.
///
/// Android only — iOS has no foreground service and no task-removal kill.
class Issue378Card extends StatefulWidget {
  const Issue378Card({super.key});

  @override
  State<Issue378Card> createState() => _Issue378CardState();
}

class _Issue378CardState extends State<Issue378Card>
    with IssueCardRun<Issue378Card>, WidgetsBindingObserver {
  @override
  IssueRunner? get cardRunner => _run;

  /// Written by this card, so the verify phase can tell this run's trail from
  /// everything the app logged before it. The arm phase clears the log first;
  /// this is the belt to that braces, and it survives a killed process because
  /// the log table is on disk.
  static const _armedMarker = 'issue378: armed at ';

  /// Stamped when the UI leaves the screen — the instant the app becomes
  /// swipeable. The durable copy of [_uiLeftAtMs].
  static const _uiLeftMarker = 'issue378: ui left the screen at ';

  /// `updateNotificationVisibility` demoting the service while the app is
  /// visible. Its presence proves the process is running without a foreground
  /// service — the precondition for the reported kill.
  static const _suppressedMarker =
      'Suppressing notification (App in foreground)';

  /// The fix announcing itself on the always-on lifecycle channel: pause-only
  /// visibility refused because `stopOnTerminate` is false. Written once per
  /// explicit `start()`, so it is in the trail of any armed run.
  static const _overrideMarker =
      'showNotificationOnPauseOnly ignored because stopOnTerminate=false';

  /// The re-promotion on the background transition. Present in the trail, it
  /// corroborates the measured window; the exact instant comes from
  /// `lastForegroundTransitionAt`, not from this line's timestamp.
  static const _shownMarker = 'Showing notification (App in background)';

  /// Lifecycle channel, always persisted. `onStartCommand` writes it when the
  /// system restarts the START_STICKY service with a null intent — which only
  /// happens after the process died.
  static const _stickyRestartMarker = 'sticky restart after process death';

  /// The surviving path: `onTaskRemoved` ran, background permission was there,
  /// and tracking continued natively.
  static const _taskRemovalMarker = 'continuing tracking after task removal';

  /// #318's killed-state anchor — the background pipeline actually came up.
  static const _bootstrapMarker = 'boot-tracking: bootstrapping';

  /// A service instance being constructed. After a kill the restarted process
  /// writes this again, which is the second death signature.
  static const _serviceCreatedMarker = 'service: onCreate';

  // Static rather than instance state: the Issues page is a virtualized
  // ListView, so this card's State is routinely disposed while the app is in
  // the background — exactly the interval being measured.
  static int? _uiLeftAtMs;
  static int? _promotionAtResumeMs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (state == AppLifecycleState.paused) {
      final now = DateTime.now().millisecondsSinceEpoch;
      _uiLeftAtMs = now;
      _promotionAtResumeMs = null;
      unawaited(_logQuietly('$_uiLeftMarker$now'));
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_captureResumeStamp());
    }
  }

  Future<void> _logQuietly(String message) async {
    try {
      await Tracelet.log('info', message);
    } catch (_) {
      // A card must never crash the app it is diagnosing. The measurement
      // falls back to the in-memory stamp.
    }
  }

  /// Reads the promotion stamp the instant the app comes back, before the Run
  /// tap can disturb it.
  Future<void> _captureResumeStamp() async {
    try {
      final health = await Tracelet.getForegroundServiceHealth();
      final at = health['lastForegroundTransitionAt'];
      _promotionAtResumeMs = at is num ? at.toInt() : null;
    } catch (_) {
      _promotionAtResumeMs = null;
    }
  }

  Future<void> _run() async {
    setRunning(running: true);
    final results = <String>[];
    var allPass = true;

    void check(String name, bool pass, String detail) {
      results.add('${pass ? '✅' : '❌'} $name — $detail');
      if (!pass) allPass = false;
    }

    void note(String name, String detail) =>
        results.add('➖ NOT MEASURED $name — $detail');

    try {
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
        setStatus(
          'ℹ️ Not applicable on this platform. #378 is the Android '
          'foreground-service demotion that pause-only visibility performs; '
          'iOS has no foreground service and no task-removal process kill.',
        );
        return;
      }

      final logs = await Tracelet.getLogs(800);
      final ordered = [...logs]..sort((a, b) => a.id.compareTo(b.id));
      final armedAtId = _lastIdContaining(ordered, _armedMarker);

      if (armedAtId == null) {
        await _arm(results, check);
        return;
      }

      // ── Verify phase ──────────────────────────────────────────────────────
      final trail = ordered.where((e) => e.id > armedAtId).toList();
      final config = Tracelet.activeConfig;
      final pauseOnly =
          config.android.foregroundService.showNotificationOnPauseOnly;
      final stopOnTerminate = config.app.stopOnTerminate;

      check(
        '[Dart mirror] the reported combination is in force',
        pauseOnly && !stopOnTerminate,
        pauseOnly && !stopOnTerminate
            ? 'showNotificationOnPauseOnly=true with stopOnTerminate=false — '
                  'the app has asked for a hidden notification AND for tracking '
                  'to outlive task removal'
            : 'this run is NOT the reported combination '
                  '(showNotificationOnPauseOnly=$pauseOnly, '
                  'stopOnTerminate=$stopOnTerminate), so the rows below do not '
                  'describe #378. The demo baseline sets both; something '
                  'reconfigured the SDK after prepareIssueRun().',
      );

      if (!pauseOnly || stopOnTerminate) {
        note(
          '[native log] the override announces itself',
          'only meaningful for the reported combination, which this run is not',
        );
      } else {
        final announced = trail.where(
          (e) => e.message.contains(_overrideMarker),
        );
        check(
          '[native log] the override announces itself',
          announced.isNotEmpty,
          announced.isNotEmpty
              ? 'the lifecycle channel carries "${announced.first.message}" — '
                    'a developer who wonders why the notification is visible '
                    'has the answer in the log, at every log level, including '
                    'from a killed-state run'
              : 'nothing in the trail explains the notification. Either the '
                    'override is not applied at all (see the rows below) or it '
                    'is applied silently, which is the half of #378 that made '
                    'it cost the reporter a debugging session rather than a '
                    'config change.',
        );
      }

      final suppressed = trail.where(
        (e) => e.message.contains(_suppressedMarker),
      );
      check(
        '[native log] the service stays promoted while the app is on screen',
        suppressed.isEmpty,
        suppressed.isEmpty
            ? 'no "$_suppressedMarker" entry since arming — the foreground '
                  'service was never demoted, so there is no interval in which '
                  'task removal can kill the process'
            : 'REPRODUCED — ${suppressed.length} demotion(s) since arming, the '
                  'first at ${suppressed.first.timestamp}. '
                  'stopForeground(STOP_FOREGROUND_REMOVE) ran while the app was '
                  'visible, so from that point the process holds no foreground '
                  'service and ActivityManager will kill it on task removal.',
      );

      final uiLeftAt =
          _uiLeftAtMs ?? _lastStampFromMarker(ordered, _uiLeftMarker);
      final promotedAt = _promotionAtResumeMs;
      final reShown = trail.any((e) => e.message.contains(_shownMarker));

      if (uiLeftAt == null) {
        note(
          '[native State] the kill window',
          'the app has not been backgrounded since arming. Press Home, count '
              'to three, reopen, and press Run again — that round trip is what '
              'measures the window.',
        );
      } else if (promotedAt == null) {
        note(
          '[native State] the kill window',
          'no promotion stamp was captured on resume '
              '(lastForegroundTransitionAt was null). Either the service never '
              'promoted at all — check the foreground-service rows on the '
              '#255 card — or the app was reopened while this card was '
              'scrolled off screen. Keep the card visible across the round '
              'trip and repeat.',
        );
      } else {
        final windowMs = promotedAt - uiLeftAt;
        check(
          '[native State] no window between the UI leaving and the service '
          'being promoted',
          windowMs <= 0,
          windowMs <= 0
              ? 'the last promotion (${_hms(promotedAt)}) predates the UI '
                    'leaving the screen (${_hms(uiLeftAt)}) — the foreground '
                    'service was already up throughout, so a swipe at any '
                    'instant finds one'
              : 'REPRODUCED — ${windowMs}ms with no foreground service. The UI '
                    'left the screen at ${_hms(uiLeftAt)} and startForeground '
                    'did not succeed until ${_hms(promotedAt)}'
                    '${reShown ? ' ("$_shownMarker" is in the trail)' : ''}. '
                    'A swipe from recents inside those ${windowMs}ms is what '
                    "killed the reporter's process; the reporter measured "
                    '700ms and 1500ms.',
        );
      }

      final died = trail.any((e) => e.message.contains(_stickyRestartMarker));
      final survived = trail.any(
        (e) =>
            e.message.contains(_taskRemovalMarker) ||
            e.message.contains(_bootstrapMarker),
      );
      final recreatedAfterBackground = _sawAfterMarker(
        trail,
        marker: _uiLeftMarker,
        needle: _serviceCreatedMarker,
      );

      if (!died && !survived && !recreatedAfterBackground) {
        note(
          '[native log] the process survives a swipe inside the window',
          'no task removal in this trail. To test the kill itself: press Run '
              'to re-arm, press Recents, and swipe the app away immediately — '
              'inside the window measured above — then reopen and press Run.',
        );
      } else {
        check(
          '[native log] the process survives a swipe inside the window',
          survived && !died,
          survived && !died
              ? 'onTaskRemoved ran and tracking continued natively '
                    '(task-removal and/or boot-tracking entries are in the '
                    'trail, with no sticky restart) — stopOnTerminate: false '
                    'did what it promises'
              : 'REPRODUCED — the process was killed on task removal. '
                    '${died ? 'The system restarted the START_STICKY service '
                              'with a null intent ("$_stickyRestartMarker"), which '
                              'only happens after the hosting process died. ' : ''}'
                    '${recreatedAfterBackground && !died ? 'A fresh '
                              '"$_serviceCreatedMarker" appears after the app was '
                              'backgrounded, with no task-removal handling before '
                              'it — a new process, not a survivor. ' : ''}'
                    'Nothing ran onTaskRemoved to completion, so the headless '
                    'engine never attached and the events of that run are gone.',
        );
      }

      final header = allPass
          ? '✅ SUCCESS: pause-only visibility no longer opens a window in '
                'which task removal kills the process.'
          : '❌ #378 REPRODUCED — see the failing rows below.';

      setStatus(
        '$header\n\n${results.join('\n')}\n\n'
        'Scope: the window row is a real measurement of this device and this '
        "run — Dart's pause callback against the native promotion stamp. It "
        'is a lower bound on the exposure: the process also has no foreground '
        'service for however long it takes ActivityManager to notice, which is '
        'not observable from here. The kill row is only ever as good as the '
        'swipe you performed; a green kill row after a slow swipe proves '
        'nothing about a fast one, which is why the window row is the one that '
        'matters.\n\n'
        'Press Run again to re-arm and repeat.',
      );
    } catch (e) {
      setStatus('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      setRunning(running: false);
    }
  }

  /// Clears the trail, starts tracking, and marks the log so the verify phase
  /// reads only what this run produced.
  Future<void> _arm(
    List<String> results,
    void Function(String, bool, String) check,
  ) async {
    final auth = await Tracelet.getLocationAuthorization();
    check(
      'background location is granted',
      auth == AuthorizationStatus.always,
      auth == AuthorizationStatus.always
          ? 'ACCESS_BACKGROUND_LOCATION is granted, so onTaskRemoved will take '
                'the continue-tracking branch rather than standing the service '
                'down'
          : 'authorization is $auth. onTaskRemoved stops tracking outright '
                'without "always" (LocationService.kt:776-788), so a kill row '
                'measured now would be that guard, not #378. Grant background '
                'location before arming.',
    );

    _uiLeftAtMs = null;
    _promotionAtResumeMs = null;

    await Tracelet.clearLogs();
    await _logQuietly('$_armedMarker${DateTime.now().millisecondsSinceEpoch}');

    // stop() before start() on purpose: `start()` while tracking is already
    // live returns before it ever reaches the service ("start ignored — already
    // tracking continuously"), so the arm phase would produce no ACTION_START,
    // no fresh service instance, and none of the entries the verify phase reads.
    await Tracelet.stop();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await Tracelet.start();

    setStatus(
      'ARMED — the log was cleared, tracking is running, and the demo baseline '
      'has the reported combination (stopOnTerminate: false, '
      'showNotificationOnPauseOnly: true).\n\n'
      '${results.join('\n')}\n\n'
      'To measure the window (no kill, repeatable):\n'
      '1. Keep this card on screen and press Home.\n'
      '2. Count to three.\n'
      '3. Reopen the app and press Run.\n\n'
      'To reproduce the kill itself:\n'
      '1. Press Recents.\n'
      '2. Swipe this app away IMMEDIATELY — the window is under two seconds.\n'
      '3. Reopen the app and press Run.\n'
      "Swipe slowly and it will survive; that is the reporter's whole point, "
      'so a survival here is only meaningful next to the measured window.\n\n'
      'Do not force-stop the app — that kills the process by a different route '
      'and tells you nothing about this bug.',
    );
  }

  /// Id of the newest entry containing [needle], or null.
  int? _lastIdContaining(List<LogEntry> ordered, String needle) {
    for (var i = ordered.length - 1; i >= 0; i--) {
      if (ordered[i].message.contains(needle)) return ordered[i].id;
    }
    return null;
  }

  /// The epoch-ms this card embedded in the newest [marker] entry — the durable
  /// copy of a stamp lost when the card's State was recycled.
  int? _lastStampFromMarker(List<LogEntry> ordered, String marker) {
    for (var i = ordered.length - 1; i >= 0; i--) {
      final message = ordered[i].message;
      final at = message.indexOf(marker);
      if (at < 0) continue;
      return int.tryParse(message.substring(at + marker.length).trim());
    }
    return null;
  }

  /// Whether [needle] appears after the newest [marker] entry.
  bool _sawAfterMarker(
    List<LogEntry> trail, {
    required String marker,
    required String needle,
  }) {
    final markerId = _lastIdContaining(trail, marker);
    if (markerId == null) return false;
    return trail.any((e) => e.id > markerId && e.message.contains(needle));
  }

  String _hms(int epochMs) {
    final t = DateTime.fromMillisecondsSinceEpoch(epochMs).toLocal();
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    final ms = t.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'showNotificationOnPauseOnly stopOnTerminate task removal swipe '
          'recents killed process foreground service demoted stopForeground '
          'notification gap window headless 378',
      title: '#378: pause-only notification defeats stopOnTerminate: false',
      description:
          'Hiding the notification while the app is open demotes the '
          'foreground service, so a swipe from recents before it is re-posted '
          'kills the process. Measures the window in milliseconds, and '
          'classifies a swipe you perform inside it as survived or killed.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
