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
class Issue404Card extends StatefulWidget {
  const Issue404Card({super.key});

  @override
  State<Issue404Card> createState() => _Issue404CardState();
}

class _Issue404CardState extends State<Issue404Card>
    with IssueCardRun<Issue404Card> {
  /// Comfortably past the 10 s gate, so the fix the park left behind is
  /// unambiguously stale by the time the walk starts.
  static const _settleWindow = Duration(seconds: 90);

  /// Longer than `speedStationaryDelay`, so a real walk has time to be seen.
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
            isMoving: false,
            motionDetectionMode: MotionDetectionMode.smart,
            // Short, so the card parks within its own runtime rather than
            // waiting out a production stopTimeout.
            stopTimeout: 1,
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
        '🧍 Put the phone down and keep still for ${_settleWindow.inSeconds}s.\n\n'
        'This is the setup, not the test: the session has to park so the last '
        'resolved speed freezes. That frozen number is what used to veto the '
        'walk you are about to take.',
      );
      await Future<void>.delayed(_settleWindow);

      final settleLogs = await Tracelet.getLogs(400);
      final parked = settleLogs.any(
        (l) => l.message.contains('smart-motion: switching to STATIONARY'),
      );
      check(
        'the session parked, so a speed is now frozen behind it',
        pass: parked,
        detail: parked
            ? 'the precondition holds — the stream stopped and the last '
                  'resolved speed is the one the override will read'
            : 'the session never parked in ${_settleWindow.inSeconds}s, so '
                  'nothing is stale yet and the bug cannot be exercised. Try '
                  'again somewhere with a usable GPS fix, and keep the device '
                  'still',
      );

      setStatus(
        '🚶 Now pocket the phone and walk for ${_walkWindow.inSeconds}s.\n\n'
        'Walk normally. The accelerometer will fire; the question is whether a '
        'speed frozen ${_settleWindow.inSeconds}s ago is allowed to overrule it.',
      );
      await Future<void>.delayed(_walkWindow);

      final logs = await Tracelet.getLogs(600);
      bool saw(String needle) => logs.any((l) => l.message.contains(needle));

      // The fix: an old reading routes to the same "unknown" branch an absent
      // one always did, and says so where a released build can report it.
      final declined = saw('declining a') && saw('for the tremor override');
      // The bug: the override fired anyway, on a reading minutes old.
      final overrode = saw('overriding accel to false (hand tremor)');
      final woke = saw('smart-motion: switching to CONTINUOUS');

      check(
        'the walk was not vetoed by a stale reading',
        pass: !overrode || woke,
        detail: !overrode
            ? 'the tremor override did not fire against the wake'
            : woke
            ? 'the override fired but the session still went continuous — check '
                  'the ordering in the log before trusting this run'
            : 'the override fired and the session stayed stationary. A reading '
                  'from before you started walking stood the wake down, which '
                  'is #404 exactly',
      );

      check(
        'the session is tracking after the walk',
        pass: woke,
        detail: woke
            ? 'the accelerometer wake reached the engine and continuous '
                  'tracking resumed'
            : 'no switch to CONTINUOUS in the log. If you genuinely walked, the '
                  'wake was discarded — the symptom users report as "the '
                  'indicator only appears in the foreground"',
      );

      check(
        'a declined stale reading is named on the always-on channel',
        pass: declined || !overrode,
        detail: declined
            ? 'the decline is reported at the default logLevel, so a released '
                  'build can show why a wake survived'
            : 'no decline entry — either no stale reading was consulted on this '
                  'run (fine, if the walk produced fresh fixes quickly) or the '
                  'gate is not in this build',
      );

      await Tracelet.stop();

      final header = allPass
          ? '✅ SUCCESS: a stale speed no longer vetoes a real wake.'
          : '❌ FAILED — #404 not satisfied on this build.';

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
          'Parks a session so the last resolved speed freezes, then has you walk '
          'for 60 s and checks that the frozen reading is treated as unknown '
          'rather than as proof you are still standing still. Requires walking.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
