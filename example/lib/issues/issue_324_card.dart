import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #324 — the always-on lifecycle channel never recorded a tracking
/// session's own start or stop, so a foreground run left evidence only on the
/// first run of a process.
///
/// #318 gave the channel the background and killed-state machinery, but not the
/// session boundaries: `start()` and `stop()` logged at `info`, which every
/// stricter level drops. So the trail could not say the one thing that answers
/// most "it stopped tracking overnight" reports — *tracking was stopped*. iOS
/// already wrote `relaunch: declined to resume — tracking was stopped before
/// termination`, pointing at a stop the reader had no way to see.
///
/// The visible symptom was the #318 card. It clears the log and then runs one
/// `start()`/`stop()` cycle, and every emitter reachable from that window was
/// either a **one-shot per process** — Android's `service: onCreate`, iOS's
/// `relaunch:`/`termination:` — or fired **only on a real change** (motion
/// transitions). It passed once after a fresh launch and reported a regression
/// on every run after it, with nothing wrong in the SDK.
///
/// Both platforms now record `session: start` and `session: stop` with the mode
/// and the strategy the session actually ran with. Android additionally marks
/// `setConfig()`'s in-place restart `restart=true`, so a config change does not
/// read as the session ending, and promotes `LocationService.onDestroy` to the
/// channel so a service reclaimed by the OS is distinguishable from one that was
/// never created.
///
/// This card exists separately from #318 because it can prove the thing #318
/// structurally cannot: it runs the whole clear-then-cycle sequence **twice in
/// one press**, in the same process, and requires evidence from both. That is
/// the regression, and a card that ran the cycle once could not see it.
class Issue324Card extends StatefulWidget {
  const Issue324Card({super.key});

  @override
  State<Issue324Card> createState() => _Issue324CardState();
}

class _Issue324CardState extends State<Issue324Card> {
  String _status = 'Idle';
  bool _running = false;

  void _set(String s) {
    if (mounted) setState(() => _status = s);
  }

  /// Clears the log, runs one `start()`/`stop()` cycle, and returns the
  /// `LIFECYCLE` messages it produced.
  ///
  /// Clearing first is what makes the result attributable to this cycle alone —
  /// and it is also what made the original bug visible, since a one-shot from
  /// process startup does not survive it.
  Future<List<String>> _cycle() async {
    await Tracelet.clearLogs();
    await Tracelet.start();
    await Future<void>.delayed(const Duration(seconds: 3));
    await Tracelet.stop();
    await Future<void>.delayed(const Duration(seconds: 1));
    final logs = await Tracelet.getLogs(200);
    return logs
        .where((e) => e.level.toUpperCase() == 'LIFECYCLE')
        .map((e) => e.message)
        .toList();
  }

  Future<void> _run() async {
    setState(() => _running = true);
    final results = <String>[];
    var allPass = true;

    void check(String name, bool pass, String detail) {
      results.add('${pass ? '✅' : '❌'} $name — $detail');
      if (!pass) allPass = false;
    }

    try {
      if (kIsWeb) {
        _set(
          'ℹ️ Not applicable on web — there is no tracking session to bound and '
          'no native log store to record it in.',
        );
        return;
      }

      // Pinned below the diagnostics, exactly as #318 does: `start()` and
      // `stop()` log at `info`, so at `error` anything that survives got there
      // by bypassing the level gate. Running at a permissive level would make
      // this card pass on the ordinary `info` lines instead.
      await Tracelet.requestLocationAuthorization();
      await Tracelet.ready(
        const Config(logger: LoggerConfig(logLevel: LogLevel.error)),
      );

      final levelIsStrict =
          Tracelet.activeConfig.logger.logLevel == LogLevel.error;
      check(
        'log level is pinned below the diagnostics',
        levelIsStrict,
        levelIsStrict
            ? 'logLevel=error — the info-level start()/stop() lines are dropped, '
                  'so a session boundary that survives bypassed the gate'
            : 'logLevel=${Tracelet.activeConfig.logger.logLevel}; this card is '
                  'only meaningful at a level that excludes info',
      );

      // ---------------------------------------------------------------------
      // The regression: the same cycle, twice, in one process.
      // ---------------------------------------------------------------------
      final first = await _cycle();
      final second = await _cycle();

      bool hasBoundaries(List<String> trail) =>
          trail.any((m) => m.startsWith('session: start')) &&
          trail.any((m) => m.startsWith('session: stop'));

      check(
        'the first run records both session boundaries',
        hasBoundaries(first),
        hasBoundaries(first)
            ? '${first.length} lifecycle entries, including a session: start '
                  'and a session: stop'
            : first.isEmpty
            ? 'REGRESSED — no lifecycle entries at all. If #318 also fails, the '
                  'log store is the problem, not the boundaries.'
            : 'REGRESSED — ${first.length} lifecycle entries but not both '
                  'boundaries: ${first.join(' | ')}',
      );

      // This is the row that was failing. It cannot pass on a one-shot: the
      // process is the same, so anything that fires once per process already
      // fired during the first cycle and was cleared by the second.
      check(
        '#324 the second run in the same process records them too',
        hasBoundaries(second),
        hasBoundaries(second)
            ? '${second.length} lifecycle entries again — the evidence is '
                  'per-session, not per-process launch'
            : second.isEmpty
            ? 'REGRESSED — the first run left a trail and the second left '
                  'nothing, which is exactly the one-shot behaviour #324 fixed. '
                  'Only a process-lifetime event is being recorded.'
            : 'REGRESSED — ${second.length} entries but not both boundaries: '
                  '${second.join(' | ')}',
      );

      // A boundary that does not say which mode ran cannot answer "was it even
      // tracking continuously?", which is the first question of a killed-state
      // report.
      final startLine = second.firstWhere(
        (m) => m.startsWith('session: start'),
        orElse: () => '',
      );
      final namesMode = startLine.contains('mode=continuous');
      check(
        'the boundary names the mode the session ran with',
        namesMode,
        namesMode
            ? 'session: start carries mode=continuous, so a report says which '
                  'pipeline ran rather than only that something started'
            : startLine.isEmpty
            ? 'no session: start to inspect — fix the row above first'
            : 'REGRESSED — the entry does not name a mode: $startLine',
      );

      // ---------------------------------------------------------------------
      // A config restart must not read as the session ending.
      // ---------------------------------------------------------------------
      // `distanceFilter` is a tracking-relevant key on both platforms, so this
      // setConfig() stops and restarts the live pipeline. Without a marker the
      // trail would show a bare `session: stop` and a reader would conclude
      // tracking had been stopped — the very thing this channel is read for.
      await Tracelet.clearLogs();
      await Tracelet.start();
      await Future<void>.delayed(const Duration(seconds: 2));
      await Tracelet.setConfig(
        const Config(geo: GeoConfig(distanceFilter: 17)),
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      final restartLogs = await Tracelet.getLogs(200);
      final restartTrail = restartLogs
          .where((e) => e.level.toUpperCase() == 'LIFECYCLE')
          .map((e) => e.message)
          .toList();
      await Tracelet.stop();

      // Asserted as a *pair* because that is what holds on both platforms: only
      // Android's stop() takes the preserve-the-service flag the `restart=`
      // marker is derived from, while iOS's restart is a plain stop() followed
      // immediately by a start. The Android marker is reported below when found.
      final stopIndex = restartTrail.indexWhere(
        (m) => m.startsWith('session: stop'),
      );
      final restartedAfterStop =
          stopIndex >= 0 &&
          restartTrail
              .skip(stopIndex + 1)
              .any((m) => m.startsWith('session: start'));
      final marked = restartTrail.any((m) => m.contains('restart=true'));
      check(
        'a setConfig() restart is visible as a restart, not a bare stop',
        restartedAfterStop,
        restartedAfterStop
            ? 'the trail shows session: stop followed by session: start'
                  '${marked ? ', and the stop is marked restart=true' : ''} — a '
                  'config change cannot be misread as tracking ending'
            : stopIndex < 0
            ? 'no session: stop was recorded for the restart, so the trail is '
                  'silent about a pipeline that did come down'
            : 'REGRESSED — a session: stop with no start after it. A reader '
                  'would conclude tracking was stopped: '
                  '${restartTrail.join(' | ')}',
      );

      if (defaultTargetPlatform == TargetPlatform.android) {
        results.add(
          marked
              ? 'ℹ️ Android — the restart carries restart=true, which is the '
                    'marker that distinguishes it from a real stop without '
                    'relying on what follows it.'
              : 'ℹ️ Android — no restart=true in this trail. That is expected '
                    'when the restart landed in a mode that does not keep the '
                    'foreground service (the flag is derived from that '
                    'decision), so the ordering above is the assertion.',
        );
      }

      if (second.isNotEmpty) {
        final sample = second.map((m) => '  • $m').join('\n');
        results.add("ℹ️ the second run's trail, in full:\n$sample");
      }

      final header = allPass
          ? '✅ SUCCESS: the session boundaries are recorded on every run, not '
                'only the first one in a process.'
          : '❌ FAILED — see the failing rows below.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'Why two runs: the card clears the log before each cycle, so it only '
        'sees what that cycle produced. Every other emitter on the channel is a '
        'one-shot per process (Android "service: onCreate", iOS "relaunch:" / '
        '"termination:") or fires only on a real motion change — none of which '
        'a stationary device in the foreground can produce twice. A single-cycle '
        'card therefore passed after a fresh launch and failed on every run '
        'after it.\n\n'
        'These are session-rate events, a handful per session rather than per '
        'fix, so they share the existing retention caps (a row cap of 500–2000 '
        'by level, plus logMaxDays) without moving worst-case database size.\n\n'
        'What to read in a real bug report:\n'
        '• A "session: stop" with nothing after it — tracking was stopped and '
        'never restarted. Rule this out first; it is the ordinary explanation.\n'
        '• Android "restart=true" — setConfig()\'s in-place restart, always '
        'followed by a start. Not the session ending.\n'
        '• Android "service: onDestroy — stopRequested=false" — the OS reclaimed '
        'a service nobody asked to stop, the shape of "tracking died while '
        'idle".\n'
        '• "session: start — resume=true" — the SDK\'s own takeover on ready() '
        'or a killed-state relaunch, rather than a call from the app.',
      );
    } catch (e) {
      _set('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'logs logging logLevel lifecycle session start stop boundary '
          'diagnostics killed state background evidence second run repeat '
          'one-shot service onDestroy restart setConfig mode strategy 324 318',
      title: '#324: session start/stop survive the log level, on every run',
      description:
          'Runs the same clear-log → start → stop cycle twice in one process '
          'and requires lifecycle evidence from both. The boundaries used to be '
          'logged at info only, so the trail could not say that tracking was '
          'stopped — and the only entries a foreground run produced were '
          'one-shots that fire once per process launch.',
      status: _status,
      running: _running,
      onRun: _run,
    );
  }
}
