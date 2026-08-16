import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_doctor/tracelet_doctor.dart';
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issues #397 and #398 — a released app could not report what went wrong, or
/// which version it went wrong in.
///
/// Everything that explains a stalled or spiking location stream was logged at
/// `debug`. Flutter defaults `logLevel` to `info` and a direct SDK consumer to
/// `off`, so a released app's bug report contained none of it. Diagnosing
/// #393/#394 from the field was only possible because the reporter happened to
/// be running at `debug` — and even then the rejection line said only
/// `DISTANCE_FILTER` and a speed, with no accuracy, no distance, and no gate to
/// check it against, so an 8 m gate and the 750 m one adaptive sampling can
/// inflate it to were indistinguishable in the log.
///
/// Three changes. Stalls, recoveries, throttle movements, idle-escape
/// admissions and anchor re-seeds are now written on the always-on **lifecycle**
/// channel, which bypasses `logLevel` entirely (the #318 mechanism). The
/// per-fix rejection line — still `debug`, still one line per fix — carries the
/// accuracy, the distance moved, the effective gate, the anchor age and the
/// thresholds in force. And the Doctor report gained a "Location stream health"
/// section that lifts those lifecycle lines out of the general log, plus the
/// Tracelet version in its header (#398).
///
/// **What this card proves.** That lifecycle entries survive `logLevel: off`,
/// that the enriched rejection line carries its decision inputs at `debug`, and
/// that a generated bug report names the version that produced it.
class Issue397Card extends StatefulWidget {
  const Issue397Card({super.key});

  @override
  State<Issue397Card> createState() => _Issue397CardState();
}

class _Issue397CardState extends State<Issue397Card>
    with IssueCardRun<Issue397Card> {
  /// Long enough for a stationary session to produce filtered fixes.
  static const _observationWindow = Duration(seconds: 25);

  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _run;

  Future<void> _run() async {
    setRunning(running: true);
    final results = <String>[];
    var allPass = true;

    void check(String name, {required bool pass, required String detail}) {
      results.add('${pass ? '✅' : '❌'} $name — $detail');
      if (!pass) allPass = false;
    }

    try {
      await Tracelet.requestLocationAuthorization();

      // ---------------------------------------------------------------------
      // 1. Lifecycle entries survive the level a released app actually runs at
      // ---------------------------------------------------------------------
      await Tracelet.ready(
        const Config(
          geo: GeoConfig(distanceFilter: 10),
          motion: MotionConfig(isMoving: true),
          http: HttpConfig(autoSync: false),
          // The setting that hid everything: OFF drops every level-based line.
          logger: LoggerConfig(logLevel: LogLevel.off),
        ),
      );
      await Tracelet.destroyLog();
      await Tracelet.start();
      await Future<void>.delayed(const Duration(seconds: 5));
      await Tracelet.stop();

      final quietLogs = await Tracelet.getLogs(500);
      final lifecycle = quietLogs
          .where((l) => l.level.toUpperCase() == 'LIFECYCLE')
          .toList();
      final levelled = quietLogs
          .where((l) => l.level.toUpperCase() == 'DEBUG')
          .toList();

      check(
        'lifecycle entries are recorded at logLevel: off',
        pass: lifecycle.isNotEmpty,
        detail: lifecycle.isNotEmpty
            ? '${lifecycle.length} entry(ies) — a released app can report these'
            : 'none. At OFF the report carries nothing, which is #397',
      );
      check(
        'ordinary debug logging still respects logLevel: off',
        pass: levelled.isEmpty,
        detail: levelled.isEmpty
            ? 'no DEBUG entries, so the always-on channel is curated rather '
                  'than a logging bypass'
            : '${levelled.length} DEBUG entries leaked past the level gate',
      );

      // ---------------------------------------------------------------------
      // 2. The rejection line carries its decision inputs
      // ---------------------------------------------------------------------
      await Tracelet.setConfig(
        const Config(logger: LoggerConfig(logLevel: LogLevel.debug)),
      );
      await Tracelet.destroyLog();
      await Tracelet.start();
      _set('⏳ Collecting filter decisions (${_observationWindow.inSeconds}s)…');
      await Future<void>.delayed(_observationWindow);
      await Tracelet.stop();

      final verboseLogs = await Tracelet.getLogs(500);
      final rejections = verboseLogs
          .where((l) => l.message.contains('filtered by Rust processor'))
          .toList();

      if (rejections.isEmpty) {
        check(
          'a filter decision was logged',
          pass: false,
          detail:
              'no fixes were filtered in this window, so the enriched line '
              'could not be checked. Re-run somewhere with a location fix',
        );
      } else {
        final sample = rejections.first.message;
        check(
          'the rejection line names the gate the fix was measured against',
          pass: sample.contains('gate='),
          detail: sample.contains('gate=')
              ? 'present — a DISTANCE_FILTER can now be told from a 750 m one'
              : 'missing. Line was: $sample',
        );
        check(
          "the rejection line carries the fix's accuracy and the anchor age",
          pass: sample.contains('acc=') && sample.contains('anchor='),
          detail: sample.contains('acc=') && sample.contains('anchor=')
              ? 'present'
              : 'missing. Line was: $sample',
        );
      }

      // ---------------------------------------------------------------------
      // 3. The bug report names the version that produced it (#398)
      // ---------------------------------------------------------------------
      final report = await TraceletBugReport.build(logLimit: 50);
      check(
        'the bug report states the Tracelet version',
        pass: report.contains('**Tracelet:** $traceletVersion'),
        detail: report.contains('**Tracelet:** $traceletVersion')
            ? 'reports $traceletVersion'
            : 'no version line — triage has to ask, and a report pasted into an '
                  'issue weeks later can never answer',
      );
      check(
        'the bug report has a location stream health section',
        pass: report.contains('## Location stream health'),
        detail: report.contains('## Location stream health')
            ? 'present — stalls and throttle movements have their own section'
            : 'missing',
      );

      final header = allPass
          ? '✅ SUCCESS: a released app can now report what happened.'
          : '❌ FAILED — #397/#398 not satisfied on this build.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'The always-on channel stays curated: stalls, recoveries, budget '
        'throttle movements, idle-escape admissions and anchor re-seeds. All of '
        'them are per-session events, not per-fix, which is what makes '
        'bypassing logLevel affordable — the same reasoning #318 used for '
        'motion transitions and killed-state relaunches. Retention is unchanged '
        'and still bounded by both the row cap and logMaxDays.',
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
          'logs release mode logLevel off lifecycle always-on diagnostics '
          'bug report version doctor stall histogram DISTANCE_FILTER enriched '
          '397 398',
      title: '#397/#398: release builds could not report a stalled stream',
      description:
          'Runs at logLevel: off and checks lifecycle entries are still '
          'recorded, then at debug to check the rejection line carries the '
          'accuracy, distance, gate and anchor age it was decided on — and '
          'builds a bug report to check it names the Tracelet version. No '
          'walking required.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
