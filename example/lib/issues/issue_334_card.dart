import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #334 — the GPS-speed motion machine and the coordinator's mode
/// switches were `debug`-only, so a bug report gathered at the shipped log
/// levels could show a mid-trip downgrade with no record of what decided it.
///
/// A real report of tracking dropping to periodic mode mid-drive was
/// diagnosable only because that user happened to be running with
/// `logLevel: debug`. At the defaults — `info` for Flutter, `off` for a direct
/// SDK consumer — every `[SpeedMotion]` line and every "Location filtered by
/// Rust processor" line is dropped before it reaches the store.
///
/// `TraceletLogger.lifecycle` (#318) already exists for exactly this: a
/// curated, low-frequency set of events that bypasses the level gate and
/// persists to the SQLite log store, surfaced by Doctor under
/// `## Session lifecycle`. Its own doc comment lists "motion-state transitions"
/// and "tracking-mode switches" as belonging on the channel — and the speed
/// machine's transitions were on neither.
///
/// What moved onto the always-on channel:
///
/// * `speed-motion: MOVING -> SLOWING — speed=0.00 < threshold=1.50` — the
///   deciding speed is the whole story of #332, and it was invisible.
/// * `speed-motion: restored STATIONARY …` on start, so a relaunched process
///   inheriting STATIONARY is distinguishable from tracking having silently
///   stopped.
/// * `smart-motion: switching to STATIONARY_PERIODIC — accelMoving=false
///   speedMoving=false lastSpeed=8.53m/s` — which of the OR's two inputs was
///   false, and what the last resolved speed was.
///
/// State names are spelled out rather than logged as `rawValue: 2`, because the
/// trace is read by a human in a pasted report.
///
/// This card verifies the persistence contract directly, and does not depend on
/// the device moving.
class Issue334Card extends StatefulWidget {
  const Issue334Card({super.key});

  @override
  State<Issue334Card> createState() => _Issue334CardState();
}

class _Issue334CardState extends State<Issue334Card>
    with IssueCardRun<Issue334Card> {
  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _run;

  Future<void> _run() async {
    setRunning(running: true);
    final results = <String>[];
    var allPass = true;

    void check(String name, bool pass, String detail) {
      results.add('${pass ? '✅' : '❌'} $name — $detail');
      if (!pass) allPass = false;
    }

    try {
      // Raise the level gate as high as it goes. Anything still reaching the
      // store after this is on the always-on channel by definition — which is
      // the property that has to hold in a release build.
      await Tracelet.setConfig(
        const Config(logger: LoggerConfig(logLevel: LogLevel.error)),
      );

      // A start/stop pair is the one boundary that fires on every run, so the
      // card is re-runnable within a single process (#324's lesson). Starting
      // also constructs the speed machine, which records its restored state.
      await Tracelet.start();
      await Future<void>.delayed(const Duration(seconds: 4));
      await Tracelet.stop();
      await Future<void>.delayed(const Duration(seconds: 1));

      final logs = await Tracelet.getLogs(300);
      final lifecycle = logs
          .where((e) => e.level.toUpperCase() == 'LIFECYCLE')
          .toList();

      // Row 1: distinguishes "the always-on channel is broken" from "nothing is
      // being logged at all" — different bugs in different layers.
      final levels = logs.map((e) => e.level.toUpperCase()).toSet().toList()
        ..sort();
      check(
        'the always-on channel survives logLevel=error',
        lifecycle.isNotEmpty,
        lifecycle.isNotEmpty
            ? '${lifecycle.length} lifecycle entries persisted with the level '
                  'gate at its maximum'
            : logs.isEmpty
            ? 'REGRESSED — the log table is empty entirely, so this is the log '
                  'store rather than the lifecycle channel.'
            : 'REGRESSED — ${logs.length} entries exist but none are LIFECYCLE '
                  '(levels seen: ${levels.join(', ')}).',
      );

      // Row 2: the entry this issue is about. `speed-motion: restored …` is
      // written by every start(), so it is present on any platform where the
      // machine runs — no movement required.
      final speedMotion = lifecycle
          .where((e) => e.message.contains('speed-motion:'))
          .toList();
      check(
        '#334 the speed machine records itself on the always-on channel',
        speedMotion.isNotEmpty,
        speedMotion.isNotEmpty
            ? '${speedMotion.length} entr'
                  '${speedMotion.length == 1 ? 'y' : 'ies'} — most recent: '
                  '"${speedMotion.last.message}"'
            : 'REGRESSED — no `speed-motion:` entries. start() records the '
                  'restored state, so this should be present on any run where '
                  'the speed machine is active.',
      );

      // Row 3: a transition entry has to carry its deciding speed. An entry
      // that only says MOVING -> SLOWING repeats the mistake in a new place:
      // #332 was invisible precisely because the speed was not written down.
      final transitions = speedMotion
          .where((e) => e.message.contains('->'))
          .toList();
      if (transitions.isEmpty) {
        results.add(
          '⏭️ transition entries carry their deciding speed — skipped, this '
          'run produced no state change (a stationary device that starts and '
          'stops in the same state legitimately produces none). The restored '
          'entry asserted above proves the channel itself.',
        );
      } else {
        final withEvidence = transitions
            .where(
              (e) =>
                  e.message.contains('speed=') ||
                  e.message.contains('expired') ||
                  e.message.contains('manual pace change'),
            )
            .length;
        check(
          'transition entries carry the reason they fired',
          withEvidence == transitions.length,
          withEvidence == transitions.length
              ? 'all $withEvidence transition entries name the speed or the '
                    'timer that caused them'
              : 'REGRESSED — ${transitions.length - withEvidence} of '
                    '${transitions.length} transitions recorded no reason, '
                    'which is the gap #334 was filed for.',
        );
      }

      // Row 4: state names, not raw enum ordinals. The old motion entries read
      // "mode=MotionDetectionMode(rawValue: 2)", which needs the source to
      // decode — in the one output meant to be read without it.
      final readable = speedMotion.any(
        (e) =>
            e.message.contains('MOVING') ||
            e.message.contains('SLOWING') ||
            e.message.contains('STATIONARY'),
      );
      check(
        'the trace is readable without the source',
        speedMotion.isEmpty || readable,
        speedMotion.isEmpty
            ? 'no entries to inspect — see the row above'
            : readable
            ? 'states are spelled out (MOVING/SLOWING/STATIONARY) rather than '
                  'logged as raw ordinals'
            : 'REGRESSED — entries carry no readable state name: '
                  '"${speedMotion.last.message}"',
      );

      final header = allPass
          ? '✅ SUCCESS: the speed machine now leaves a trace that survives a '
                'release build at default log settings.'
          : '❌ FAILED — see the failing rows below.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'Why the level matters: this card sets logLevel=error before running, '
        'so everything it then finds reached the store despite the gate. That '
        'is the release-build property — `lifecycle()` writes to the SQLite '
        'store with no level check and no debug guard on either platform.\n\n'
        'Retention is unchanged and bounded on two axes: the row cap from '
        'pruneOldLogs() and logMaxDays (3 days by default). These entries fire '
        'a handful of times per trip rather than per fix, which is the '
        'affordability bar the channel documents.\n\n'
        'Still missing, and worth knowing when reading a report: `## Active '
        'configuration` mirrors Tracelet.activeConfig, a Dart-side in-memory '
        'copy, so a report generated after a background relaunch renders it as '
        '{}. The same restart empties `## Location filter (in force vs. '
        'configured)`. Both are process-scoped by construction and are not '
        'addressed here.',
      );
    } catch (e) {
      _set('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'lifecycle log level release build debug speed motion transition '
          'trace bug report doctor sqlite persisted always-on diagnostics '
          'smart motion mode switch 334 318',
      title: '#334: speed-motion decisions are recorded in release builds',
      description:
          'Raises logLevel to error, runs a tracking session, and verifies the '
          'speed machine still records its transitions — with the deciding '
          'speed and readable state names — on the always-on lifecycle channel '
          'that Doctor reads.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
