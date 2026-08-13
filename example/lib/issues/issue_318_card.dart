import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #318 — killed-state failures left no usable evidence in the logs
/// table (Android + iOS).
///
/// The killed-state diagnostics the SDK already writes — boot bootstrap
/// outcomes, sticky restarts, motion-state transitions — are all `debug`, and
/// the level gate drops them. Flutter's default `logLevel` is `info`, so the log
/// table has content but none of it answers the question; a direct native SDK
/// consumer defaults to `off` and gets nothing at all. Either way the one class
/// of problem a developer cannot reproduce on demand — background behaviour,
/// with no UI and no attached logcat — left nothing usable behind.
///
/// A curated **lifecycle** channel now bypasses the level gate on both
/// platforms. Both record the tracking-session boundaries themselves —
/// `session: start` / `session: stop`, with the mode, the motion state and the
/// strategy the session actually ran with — because "tracking was stopped" is
/// the single most common answer to "it stopped tracking", and every other
/// entry is read against them. On top of that, Android records its separate
/// background pipeline — service create / destroy / sticky restarts, boot and
/// task-removal bootstrap outcomes, and motion-state transitions on the in-app
/// and killed-state paths. iOS has no separate pipeline (a relaunched process
/// runs the same handlers), so it records the relaunch and termination
/// boundaries instead, including which precondition made a relaunch decline to
/// resume. These are low-frequency, which is what makes always-on affordable,
/// and they share the existing retention caps — a row cap by level (500–2000)
/// plus `logMaxDays` (3 by default) — so worst-case database size is unchanged.
///
/// The card pins `logLevel` to `error`, stricter than either platform default,
/// so anything that survives did so by bypassing the gate. That is the whole
/// point: it must work for a developer who never asked for logs, on the run that
/// actually failed.
///
/// The session boundaries are also what make this card honest on a **repeat**
/// run. It clears the log first, so it can only see what the run itself
/// produces — and until #324 every emitter reachable from a foreground
/// start/stop was either a one-shot per process or fired only on a real motion
/// change. The card passed once after a fresh launch and reported a regression
/// on every run after it, with nothing wrong in the SDK.
class Issue318Card extends StatefulWidget {
  const Issue318Card({super.key});

  @override
  State<Issue318Card> createState() => _Issue318CardState();
}

class _Issue318CardState extends State<Issue318Card>
    with IssueCardRun<Issue318Card> {
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
      if (kIsWeb) {
        _set(
          'ℹ️ Not applicable on web — there is no killed-state pipeline and no '
          'native log store.',
        );
        return;
      }

      // Pin the level to `error` — stricter than any default. Everything the
      // killed-state paths log through the level-based methods is debug or
      // info, so all of it is dropped here. Whatever survives did so by
      // bypassing the gate, which is exactly the property under test. Running
      // at a permissive level would make the card pass for the wrong reason.
      await Tracelet.requestLocationAuthorization();
      await Tracelet.ready(
        const Config(logger: LoggerConfig(logLevel: LogLevel.error)),
      );
      await Tracelet.clearLogs();

      final levelIsStrict =
          Tracelet.activeConfig.logger.logLevel == LogLevel.error;
      check(
        'log level is pinned below the diagnostics',
        levelIsStrict,
        levelIsStrict
            ? 'logLevel=error — debug and info are dropped, so anything '
                  'recorded below bypassed the level gate'
            : 'logLevel=${Tracelet.activeConfig.logger.logLevel}; this card is '
                  'only meaningful at a level that excludes debug/info',
      );

      // Starting and stopping drives real service lifecycle + motion wiring,
      // which is what the channel records.
      //
      // The start/stop pair is deliberately the assertion's only source of
      // entries. Everything else on the channel is either a one-shot per process
      // (Android's "service: onCreate", iOS's "relaunch:"/"termination:") or
      // fires only on a real change (motion transitions), so a card that cleared
      // the log and then leaned on those passed on the first run of a process
      // and failed on every run after it — with nothing wrong in the SDK
      // (#324). The session boundaries fire on every run, which is what makes
      // this re-runnable.
      await Tracelet.start();
      await Future<void>.delayed(const Duration(seconds: 4));
      await Tracelet.stop();
      await Future<void>.delayed(const Duration(seconds: 1));

      final logs = await Tracelet.getLogs(200);
      final lifecycle = logs
          .where((e) => e.level.toUpperCase() == 'LIFECYCLE')
          .toList();

      // Report the total too. Without it a failure cannot distinguish "the
      // lifecycle channel is broken" from "nothing is being logged at all",
      // which are different bugs in different layers.
      final levels = logs.map((e) => e.level.toUpperCase()).toSet().toList()
        ..sort();
      check(
        '#318 lifecycle entries are persisted despite logLevel=error',
        lifecycle.isNotEmpty,
        lifecycle.isNotEmpty
            ? '${lifecycle.length} lifecycle entr'
                  '${lifecycle.length == 1 ? 'y' : 'ies'} recorded — a killed-state '
                  'report now arrives with a trail attached'
            : logs.isEmpty
            ? 'REGRESSED — the log table is empty entirely. Nothing is being '
                  'persisted, so this is the log store, not the lifecycle '
                  'channel. Check that ready() completed and the database '
                  'opened.'
            : 'REGRESSED — ${logs.length} log entries exist but none are '
                  'LIFECYCLE (levels seen: ${levels.join(', ')}). The store '
                  'works, so the always-on channel is what is not reaching it.',
      );

      // "session:" is the one anchor both platforms always emit, because the
      // start/stop above is itself a session boundary. The rest are the
      // platform-specific killed-state machinery — Android runs a separate
      // foreground-service pipeline ("service:", "boot-tracking:"), while on
      // iOS a relaunched process runs the same handlers as a foreground one
      // ("relaunch:", "termination:", "motion:") — and appear only when that
      // machinery actually ran, which a foreground run like this one cannot
      // force. Accept any of the shapes rather than asserting one platform's.
      const anchors = <String>[
        'session:',
        'service:',
        'boot-tracking:',
        'relaunch:',
        'termination:',
        'motion',
      ];
      // Only meaningful once there is something to inspect. Reported as a
      // skip rather than a failure otherwise: with no entries at all this
      // check has nothing to say, and asserting it anyway produced a second
      // red row whose text claimed "entries exist" when none did.
      if (lifecycle.isEmpty) {
        results.add(
          '⏭️ #318 killed-state anchors — skipped, no lifecycle entries to '
          'inspect. Fix the row above first; this one cannot fail '
          'independently of it.',
        );
      } else {
        final sawAnchor = lifecycle.any((e) => anchors.any(e.message.contains));
        check(
          '#318 killed-state anchors are recorded',
          sawAnchor,
          sawAnchor
              ? 'session lifecycle captured — a report now says which pipeline '
                    'ran and what it decided'
              : '${lifecycle.length} lifecycle entries exist but none carry a '
                    'killed-state anchor (${anchors.join(', ')}). Sample: '
                    '${lifecycle.take(3).map((e) => e.message).join(' | ')}',
        );
      }

      if (lifecycle.isNotEmpty) {
        final sample = lifecycle
            .take(8)
            .map((e) => '  • ${e.message}')
            .join('\n');
        results.add('ℹ️ sample of what a bug report would now carry:\n$sample');
      }

      final header = allPass
          ? '✅ SUCCESS: killed-state diagnostics are recorded even at a log '
                'level that drops everything else.'
          : '❌ FAILED — see the failing rows below.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'Retention is unchanged and already bounded on two axes: a row cap from '
        'the configured level (500–2000 rows) and logMaxDays (3 days by '
        'default). Lifecycle entries share those caps, so this cannot grow the '
        'database without limit.\n\n'
        'To use this on a real killed-state bug: reproduce it (swipe the app '
        'away, leave the device idle, then move), reopen the app and read the '
        'log — or paste TraceletBugReport, which includes it.\n\n'
        'What the absence of an entry tells you:\n'
        '• Both — a "session: stop" with nothing after it: tracking was '
        'stopped and never restarted. Rule this out first; it is the ordinary '
        'explanation. On Android "restart=true" marks setConfig()\'s in-place '
        'restart, which is always followed by a start and is not the session '
        'ending.\n'
        '• Android — "motion (foreground)" present but no "motion '
        '(killed-state, …)": the background detector never ran. No '
        '"boot-tracking: bootstrapping": the pipeline never came up at all.\n'
        '• iOS — a "termination:" entry with no "relaunch:" after it: iOS never '
        'relaunched the app, which is expected after a force-quit and a bug '
        'otherwise. A "relaunch: declined to resume" entry names the '
        'precondition that failed, and downgraded Always authorization is the '
        'usual one.',
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
          'logs logging logLevel off diagnostics lifecycle killed state '
          'background motion pace transition boot bootstrap sticky restart '
          'session start stop boundary retention logMaxDays prune bug report '
          'evidence 318 324',
      title: '#318: killed-state diagnostics survive the log level',
      description:
          'Verifies that the curated lifecycle channel (motion transitions, '
          'service start/stop, boot bootstrap outcomes) is persisted to the log '
          'table even though logLevel defaults to off — so an intermittent '
          'background failure can be diagnosed from the run that actually '
          'failed, instead of asking the user to reproduce it with logging on.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
