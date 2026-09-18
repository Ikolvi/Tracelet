import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #404 — a stale near-zero speed vetoes an accelerometer wake, so a
/// backgrounded device may never leave stationary mode.
///
/// When the GPS-speed machine says stationary and the accelerometer disagrees,
/// the SDK settles it with the last resolved speed: near zero means the
/// accelerometer is reading hand tremor on a still device, and it is overruled.
/// That reading had no freshness check, while the pace machine next door has
/// refused fixes older than 10 s since 3.8.7 — so the two disagreed about a
/// number neither could vouch for.
///
/// The failure needs no exotic state. A parked device stops its stream and
/// `lastEffectiveSpeed` freezes at whatever it last resolved — 0.0057 m/s in the
/// reported trace, well under the 0.15 m/s tremor cutoff. Stationary-periodic
/// mode then produces no fresh fix **by construction**, so minutes later, when
/// the accelerometer fires on a genuine walk, the override reads that frozen
/// value and discards the wake. Reopening the app calls `ready()`, which
/// produces a fresh fix and unwedges it — which is why this was reported as
/// *"the location indicator only appears while the app is in the foreground"*.
///
/// **What this card proves.** That after a park, a stored speed is treated as
/// *unknown* rather than as proof the device is still parked: the SDK declines
/// it on the always-on channel and leaves the accelerometer standing, instead of
/// overruling it.
///
/// **Walking is required, and the card says when.** The device has to actually
/// park — that is what freezes the reading — and then actually move. There is no
/// desk-bound version of this.
///
/// The park has to be a *transition*. A session started stationary is
/// reconciled straight into the parked posture and never logs a switch, and it
/// has no resolved speed to freeze — so the card starts *moving*, lets the
/// stream resolve a speed, and then waits for the smart coordinator to park it.
/// In smart mode that needs both inputs stationary: the accelerometer after
/// `stopTimeout`, the GPS-speed machine after `speedStationaryDelay` of
/// near-zero fixes. Both are shortened so the park lands inside the card's
/// window. Indoors, with no fix, the speed machine cannot get there and the
/// run is reported as *not exercised*, not as a failure.
class Issue404Card extends StatefulWidget {
  const Issue404Card({super.key});

  @override
  State<Issue404Card> createState() => _Issue404CardState();
}

class _Issue404CardState extends State<Issue404Card>
    with IssueCardRun<Issue404Card> {
  /// Accelerometer stop timeout, minutes. The shortest the config allows.
  static const _stopTimeoutMinutes = 1;

  /// GPS-speed machine's stationary delay, seconds. Default 180 s — longer than
  /// any sensible card. Both inputs have to be stationary for the park.
  static const _speedStationaryDelaySeconds = 30;

  /// Past both delays with margin, and comfortably past the 10 s freshness
  /// gate, so the fix the park left behind is unambiguously stale by the time
  /// the walk starts.
  static const _settleWindow = Duration(seconds: 120);

  /// Long enough for a real walk to be seen by the accelerometer and reach the
  /// engine.
  static const _walkWindow = Duration(seconds: 60);

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
          motion: MotionConfig(
            // Moving, so the stream runs and a speed resolves; the park that
            // freezes it is the transition the card then waits for.
            isMoving: true,
            motionDetectionMode: MotionDetectionMode.smart,
            stopTimeout: _stopTimeoutMinutes,
            speedStationaryDelay: _speedStationaryDelaySeconds,
          ),
          http: HttpConfig(autoSync: false),
          // A released app runs here, and this is where the evidence has to
          // survive — the decline is on the always-on lifecycle channel.
          logger: LoggerConfig(logLevel: LogLevel.off),
        ),
      );

      await Tracelet.stop();
      await Tracelet.destroyLog();
      await Tracelet.start();

      setStatus(
        '🧍 Put the phone down where it has a GPS fix and keep still for '
        '${_settleWindow.inSeconds}s.\n\n'
        'This is the setup, not the test: the session has to park so the last '
        'resolved speed freezes. That frozen number is what used to veto the '
        'walk you are about to take.',
      );
      await Future<void>.delayed(_settleWindow);

      final settleLogs = await Tracelet.getLogs(400);
      final parked = settleLogs.any(
        (l) => l.message.contains('smart-motion: switching to STATIONARY'),
      );
      if (!parked) {
        // Not a verdict on the build: without the park there is no frozen
        // reading, and every later check would pass for the wrong reason.
        await Tracelet.stop();
        setStatus(
          'ℹ️ NOT EXERCISED — the session never parked in '
          '${_settleWindow.inSeconds}s, so nothing is stale yet and the bug '
          'cannot be reached on this run.\n\n'
          'The park needs the accelerometer still for $_stopTimeoutMinutes min '
          'and $_speedStationaryDelaySeconds s of near-zero GPS speed. Indoors '
          'with no fix the speed machine never gets there. Try again somewhere '
          'with a usable fix, put the phone down, and do not touch it.',
        );
        return;
      }
      results.add(
        '✅ the session parked, so a speed is now frozen behind it — the stream '
        'stopped and the last resolved speed is the one the override will read',
      );

      setStatus(
        '🚶 Now pocket the phone and walk for ${_walkWindow.inSeconds}s.\n\n'
        'Walk normally. The accelerometer will fire; the question is whether a '
        'speed frozen ${_settleWindow.inSeconds}s ago is allowed to overrule it.',
      );
      await Future<void>.delayed(_walkWindow);

      final logs = await Tracelet.getLogs(600);
      bool saw(String needle) => logs.any((l) => l.message.contains(needle));

      // Both signals are on the always-on channel; the override's own line is
      // debug-level and invisible at this logLevel, so it is not consulted.
      final woke = saw('smart-motion: switching to CONTINUOUS');
      final declined = saw('declining a') && saw('for the tremor override');

      check(
        'the session is tracking after the walk',
        pass: woke,
        detail: woke
            ? 'the accelerometer wake reached the engine and continuous '
                  'tracking resumed'
            : 'no switch to CONTINUOUS in the log. If you genuinely walked, the '
                  'wake was discarded — the symptom users report as "the '
                  'indicator only appears in the foreground", and #404 exactly',
      );

      // Whether the gate was consulted at all. A fresh fix arriving before the
      // accelerometer fired gives the override a current speed — a legitimate
      // pass that proves nothing about staleness, so it is reported as such.
      final exercised = declined;
      if (exercised) {
        results.add(
          '✅ a declined stale reading is named on the always-on channel — the '
          'decline is reported at the default logLevel, so a released build can '
          'show why a wake survived',
        );
      } else {
        results.add(
          'ℹ️ no decline entry on this run — the wake arrived with a fresh '
          'fix already in hand, so the stale-reading gate was not consulted. '
          'The wake survived, but not because of #404. Rerun to exercise it.',
        );
      }

      await Tracelet.stop();

      final header = !allPass
          ? '❌ FAILED — #404 not satisfied on this build.'
          : exercised
          ? '✅ SUCCESS: a stale speed no longer vetoes a real wake.'
          : 'ℹ️ INCONCLUSIVE: the wake survived, but the stale-reading gate was '
                'not consulted on this run.';

      setStatus(
        '$header\n\n${results.join('\n')}\n\n'
        'The override itself is still there and still needed: a genuinely still '
        'device whose accelerometer is picking up hand tremor is overruled as '
        'before. What changed is that it now needs a *current* fix to do it — '
        'an old reading is unknown in exactly the sense a missing one always '
        'was, and unknown leaves the accelerometer standing.',
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
          'stale speed tremor override accelerometer wake vetoed stationary '
          'periodic background never leaves stationary location indicator '
          'foreground only lastEffectiveSpeed fix age 404 344 333',
      title: '#404: a stale near-zero speed vetoes an accelerometer wake',
      description:
          'Starts moving so a speed resolves, waits for the session to park so '
          'that reading freezes, then has you walk for 60 s and checks the '
          'frozen reading is treated as unknown rather than as proof you are '
          'still standing still. Requires a GPS fix and walking.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
