import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';

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
/// platforms. Android records its separate background pipeline — service start /
/// stop / sticky restarts, boot and task-removal bootstrap outcomes, and
/// motion-state transitions on the in-app and killed-state paths. iOS has no
/// separate pipeline (a relaunched process runs the same handlers), so it
/// records the relaunch and termination boundaries instead, including which
/// precondition made a relaunch decline to resume. These are low-frequency,
/// which is what makes always-on affordable, and they share the existing
/// retention caps — a row cap by level (500–2000) plus `logMaxDays` (3 by
/// default) — so worst-case database size is unchanged.
///
/// The card pins `logLevel` to `error`, stricter than either platform default,
/// so anything that survives did so by bypassing the gate. That is the whole
/// point: it must work for a developer who never asked for logs, on the run that
/// actually failed.
class Issue318Card extends StatefulWidget {
  const Issue318Card({super.key});

  @override
  State<Issue318Card> createState() => _Issue318CardState();
}

class _Issue318CardState extends State<Issue318Card> {
  String _status = 'Idle';
  bool _running = false;

  void _set(String s) {
    if (mounted) setState(() => _status = s);
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
      await Tracelet.start();
      await Future<void>.delayed(const Duration(seconds: 4));
      await Tracelet.stop();
      await Future<void>.delayed(const Duration(seconds: 1));

      final logs = await Tracelet.getLogs(200);
      final lifecycle = logs
          .where((e) => e.level.toUpperCase() == 'LIFECYCLE')
          .toList();

      check(
        '#318 lifecycle entries are persisted despite logLevel=error',
        lifecycle.isNotEmpty,
        lifecycle.isNotEmpty
            ? '${lifecycle.length} lifecycle entr'
                  '${lifecycle.length == 1 ? 'y' : 'ies'} recorded — a killed-state '
                  'report now arrives with a trail attached'
            : 'REGRESSED — none recorded. A user reporting a background failure '
                  'would still have nothing to send.',
      );

      // The two platforms have different killed-state machinery, so they emit
      // different anchors: Android runs a separate foreground-service pipeline
      // ("service:", "boot-tracking:"), while on iOS a relaunched process runs
      // the same handlers as a foreground one ("relaunch:", "termination:",
      // "motion:"). Accept either shape rather than asserting Android's.
      const anchors = <String>[
        'service:',
        'boot-tracking:',
        'relaunch:',
        'termination:',
        'motion',
      ];
      final sawAnchor = lifecycle.any((e) => anchors.any(e.message.contains));
      check(
        '#318 killed-state anchors are recorded',
        sawAnchor,
        sawAnchor
            ? 'session lifecycle captured — a report now says which pipeline ran '
                  'and what it decided'
            : 'entries exist but none of the killed-state anchors '
                  '(${anchors.join(', ')}) are present',
      );

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
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'logs logging logLevel off diagnostics lifecycle killed state '
          'background motion pace transition boot bootstrap sticky restart '
          'retention logMaxDays prune bug report evidence 318',
      title: '#318: killed-state diagnostics survive the log level',
      description:
          'Verifies that the curated lifecycle channel (motion transitions, '
          'service start/stop, boot bootstrap outcomes) is persisted to the log '
          'table even though logLevel defaults to off — so an intermittent '
          'background failure can be diagnosed from the run that actually '
          'failed, instead of asking the user to reproduce it with logging on.',
      status: _status,
      running: _running,
      onRun: _run,
    );
  }
}
