import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_doctor/tracelet_doctor.dart';
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #407 — the stall watchdog was fix-driven, so total silence was the one
/// failure it could not see.
///
/// `noteFilterDecision()` is only reached from the location callback. A stream
/// delivering **nothing** therefore never tripped the watchdog added in #397:
/// the clock was seeded at `start()` and then nothing read it again until a fix
/// arrived. The failure mode where the SDK is most blind was the one the
/// watchdog was structurally incapable of announcing.
///
/// It was not a theoretical gap. A Doctor report covering the #405 background
/// window — 52 seconds, zero location callbacks — printed *"the stream has been
/// accepting fixes and the budget has not throttled."* It had accepted nothing.
/// That line was the report's own summary of the section, and it stated the
/// opposite of the fault, which is why diagnosing #405 needed `dumpsys` on a
/// physically connected device.
///
/// The same blindness covered every total-silence cause: a permission revoked
/// mid-session, a provider that stops delivering, an OEM freezing the process,
/// GPS switched off at the OS level.
///
/// **Rejection and silence are different faults.** Rejection means the pipeline
/// is alive and mis-tuned — a threshold change fixes it. Silence means the OS
/// has stopped talking to the app, and no threshold change ever will. The SDK
/// now announces them separately, on the always-on lifecycle channel, each
/// carrying what the reader needs to tell which one they have.
///
/// **What this card proves.** Two of the three halves, without waiting out a
/// 45-second window:
///
///  * the designed silences stay quiet. Stationary-periodic mode spends nearly
///    all of its life delivering nothing — that is what it is for — and a
///    watchdog that announces it makes every parked device look broken. This
///    card parks the stream and checks no silence line appears.
///  * the Doctor no longer renders an empty stream-health section as health.
///    This is the reported symptom, and it is checkable directly from the
///    report text.
///
/// The positive case — a live stream that genuinely delivers nothing for 45
/// seconds — is environment-dependent and deliberately not asserted here: on a
/// device with a working fix it cannot be produced, and indoors it fires on its
/// own. If it happens during the run the card reports the line as context.
class Issue407Card extends StatefulWidget {
  const Issue407Card({super.key});

  @override
  State<Issue407Card> createState() => _Issue407CardState();
}

class _Issue407CardState extends State<Issue407Card>
    with IssueCardRun<Issue407Card> {
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

      await Tracelet.ready(
        const Config(
          geo: GeoConfig(distanceFilter: 0),
          // Start moving so the session opens a real continuous stream — the
          // only kind the silence watchdog covers.
          motion: MotionConfig(
            isMoving: true,
            motionDetectionMode: MotionDetectionMode.smart,
          ),
          http: HttpConfig(autoSync: false),
          // The evidence rides the always-on channel, and it has to survive the
          // level a released app actually runs at.
          logger: LoggerConfig(logLevel: LogLevel.off),
        ),
      );
      await Tracelet.destroyLog();
      await Tracelet.start();

      setStatus('⏳ Opening a continuous stream…');
      await Future<void>.delayed(const Duration(seconds: 8));

      final opened = await Tracelet.getLogs(200);
      final streamStarted = opened.any(
        (l) => l.message.contains('continuous updates starting'),
      );
      check(
        'the session opened a continuous stream',
        pass: streamStarted,
        detail: streamStarted
            ? 'the precondition holds — the watchdog only covers a stream that '
                  'is supposed to be delivering'
            : 'no stream started, so there is nothing for the watchdog to watch. '
                  'Check location permission and that the device has a fix',
      );

      // ---------------------------------------------------------------------
      // 1. The designed silence stays quiet.
      // ---------------------------------------------------------------------
      await Tracelet.changePace(false);
      setStatus('⏳ Parked. Checking the park is not announced as silence…');
      await Future<void>.delayed(const Duration(seconds: 20));

      final parked = await Tracelet.getLogs(300);
      final parkedStream = parked.any(
        (l) => l.message.contains('continuous updates stopping'),
      );
      check(
        'the stream actually parked',
        pass: parkedStream,
        detail: parkedStream
            ? 'the stationary switch was reached, so the quiet below is the '
                  'designed kind'
            : 'the stream never parked, so the next check proves nothing about '
                  'the park — see the #409 card',
      );

      final silenceAfterPark = parked
          .where((l) => l.message.contains('location stream silent'))
          .toList();
      check(
        'a parked stream is not announced as silent',
        pass: !parkedStream || silenceAfterPark.isEmpty,
        detail: silenceAfterPark.isEmpty
            ? 'nothing announced — silence between periodic ticks is the design, '
                  'and a red line here would appear in every parked device’s '
                  'report and get the real one ignored'
            : 'the watchdog announced a park as a fault: '
                  '${silenceAfterPark.first.message}',
      );

      // ---------------------------------------------------------------------
      // 2. The Doctor no longer reads an empty section as health.
      // ---------------------------------------------------------------------
      final report = await TraceletBugReport.build(logLimit: 100);
      final hasSection = report.contains('## Location stream health');
      check(
        'the bug report still has a stream-health section',
        pass: hasSection,
        detail: hasSection ? 'present' : 'missing — #397’s section is gone',
      );

      final claimsHealth = report.contains('has been accepting fixes');
      check(
        'an empty stream-health section is not reported as health',
        pass: !claimsHealth,
        detail: !claimsHealth
            ? 'the section states the absence of markers as an absence, not as '
                  'evidence the stream was working'
            : 'the report still says "the stream has been accepting fixes". '
                  'That sentence is what sent #405 to dumpsys — it was printed '
                  'over a 52-second window in which nothing was accepted',
      );

      final namesSilence = report.contains('silence');
      check(
        'the section summary names silence as a thing it can be missing',
        pass: namesSilence,
        detail: namesSilence
            ? 'a reader can tell "no silence recorded" from "no silence '
                  'happened"'
            : 'the summary mentions only stalls and the budget, so a silent '
                  'stream still has no vocabulary in the report',
      );

      await Tracelet.stop();

      // Context, never a check: whether a live stream went quiet during the run
      // depends on where the phone is.
      final observed = parked
          .where((l) => l.message.contains('location stream silent'))
          .map((l) => l.message)
          .toList();
      final context = observed.isEmpty
          ? 'No silence was observed during this run, which is the expected '
                'result outdoors with a fix. Indoors, or with location switched '
                'off at the OS level, the run would also produce a '
                '"location stream silent" line after 45 seconds — that is the '
                'positive case, and it is not asserted here because it depends '
                'on where the phone is.'
          : 'A live stream did go quiet during this run and was announced:\n'
                '${observed.first}';

      final header = allPass
          ? '✅ SUCCESS: silence has its own watchdog, and the report no longer '
                'reads empty as healthy.'
          : '❌ FAILED — #407 not satisfied on this build.';

      setStatus(
        '$header\n\n${results.join('\n')}\n\n$context\n\n'
        'The watchdog is armed when the continuous stream starts and re-armed '
        'on every delivered callback, so silence is announced on its own '
        'schedule rather than on the next fix’s. It is cancelled at stop() '
        'and at every stationary park. The threshold is 45s — shorter than the '
        'stall watchdog’s 120s, because silence is the harder failure: '
        'rejection means the pipeline is alive and mis-tuned, silence means the '
        'OS has stopped talking to the app and no threshold change will help.\n\n'
        'The callback clock is deliberately separate from the filter clock. '
        'Sharing them was the bug: a stream delivering fixes the filter rejects '
        'and a stream delivering nothing are different faults, and both were '
        'reported as neither.',
      );
    } catch (e) {
      setStatus('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'silence watchdog stall location stream nothing delivered no fixes '
          'doctor bug report health accepting fixes provider dead window '
          'lifecycle 407 397 405',
      title: '#407: a stream that delivers nothing now says so',
      description:
          'The stall watchdog only ran when a fix arrived, so total silence — '
          'the failure the SDK is blindest to — produced no signal, and the '
          'Doctor called it health. Parks the stream to check the designed '
          'silences stay quiet, and reads the report to check an empty section '
          'is no longer rendered as "the stream has been accepting fixes".',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
