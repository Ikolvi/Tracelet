import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #409 — a stationary pace with a live stream never stopped the stream.
///
/// The SMART coordinator holds a **posture**: whether the engine is streaming
/// right now or is parked in a stationary schedule. The Rust core only emits the
/// stop action when it believes that posture is Continuous, and `syncCurrentMode()`
/// read the posture from the committed pace (`isMoving`) alone. So a session that
/// resumed stationary while a stream was still live — a `ready()` takeover after
/// the boot engine handed over — wrote "parked" into a coordinator whose engine
/// was streaming, and every later stationary decision returned no action at all.
///
/// The device kept a continuous GPS stream open for the rest of the session. The
/// field report shows six unbroken minutes of 2-second fixes at 3 m accuracy,
/// every one of them `is_moving: false`, on a phone lying on a desk. Nothing in
/// the SDK was wrong about the pace — `Is moving` read `false` throughout, the
/// motion detector had correctly switched to its stationary sensors. Only the
/// stream was never told.
///
/// **What this card proves.** That committing a stationary pace while the stream
/// is live actually stops the stream. `changePace(false)` drives the exact
/// decision the bug swallowed, so the check takes seconds rather than the
/// 30-second stationary dwell a real transition needs — and no walking.
///
/// Before the fix the run ends with the stream still open and no
/// `location stream: continuous updates stopping` on the lifecycle channel.
///
/// **The iOS half.** The posture fix alone did not make this card pass there,
/// for three more reasons. The coordinator resolves "speed says stationary,
/// accelerometer says moving" by reading the last resolved speed, and a
/// near-zero one overrides the accelerometer — an override that *is* the stop
/// transition whenever the speed input is already stationary, and whose result
/// was discarded. The speed input got into that state on its own: only a
/// session starting stationary re-asserted it, so a session that parked handed
/// the next started-moving one a value it could never clear. And the evidence
/// this card reads did not exist on iOS: the motion pipeline parks by stopping
/// location updates without ending the session, so it never went through the
/// path that records the stop — the same reason `isTracking` (still true while
/// parked) was the wrong signal for "is the stream live".
class Issue409Card extends StatefulWidget {
  const Issue409Card({super.key});

  @override
  State<Issue409Card> createState() => _Issue409CardState();
}

class _Issue409CardState extends State<Issue409Card>
    with IssueCardRun<Issue409Card> {
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
          // Start moving so the session opens a real continuous stream — that is
          // the precondition the bug needs.
          motion: MotionConfig(
            isMoving: true,
            motionDetectionMode: MotionDetectionMode.smart,
          ),
          http: HttpConfig(autoSync: false),
          // The always-on lifecycle channel carries the evidence, and it has to
          // survive the level a released app runs at.
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
            ? 'the precondition holds — a live stream with a pace about to be '
                  'committed stationary'
            : 'no stream started, so the bug cannot be exercised. Check location '
                  'permission and that the device has a fix',
      );

      // The decision the bug swallowed. Both coordinator inputs go stationary
      // while the engine is streaming — the pair that used to return no action.
      await Tracelet.changePace(false);
      await Future<void>.delayed(const Duration(seconds: 6));

      final after = await Tracelet.getLogs(200);
      final stopped = after.any(
        (l) => l.message.contains('continuous updates stopping'),
      );
      check(
        'committing a stationary pace stops the live stream',
        pass: stopped,
        detail: stopped
            ? 'the stationary switch was reached — the posture matched the '
                  'engine, so the core emitted the stop action'
            : 'the stream is still open. The coordinator believed it was already '
                  'parked, so no stop action was emitted and GPS keeps running '
                  'for the rest of the session (#409)',
      );

      final switched = after.any(
        (l) => l.message.contains('smart-motion: switching to STATIONARY'),
      );
      check(
        'the switch is named on the always-on channel',
        pass: switched,
        detail: switched
            ? 'a released app can report this transition at the default logLevel'
            : 'no smart-motion line — the transition is invisible in a bug report',
      );

      await Tracelet.stop();

      final header = allPass
          ? '✅ SUCCESS: a stationary pace now stops the stream it inherited.'
          : '❌ FAILED — #409 not satisfied on this build.';

      setStatus(
        '$header\n\n${results.join('\n')}\n\n'
        "The posture is now the OR of the committed pace and the engine's "
        'actual state. Reading the pace alone was #409 — parked belief over a '
        'live stream. Reading the engine alone would be #344 again, because '
        'syncCurrentMode() runs before start() subscribes anything: a moving '
        'start would sync parked and then stream, wedged the same way from the '
        'other side.\n\n'
        'On iOS the same run also needed three more things: the stop the '
        'tremor override produces is handled instead of discarded, the '
        "coordinator's speed input is seeded on a started-moving session "
        'instead of inheriting the last one, and parking the stream is '
        'recorded on the always-on channel — which is the second check above.',
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
          'stationary continuous stream battery drain posture coordinator '
          'syncCurrentMode smart motion changePace parked GPS never stops '
          'drain 409 410 344',
      title: '#409: a stationary pace never stopped the stream it inherited',
      description:
          'Opens a real continuous stream, then commits a stationary pace and '
          'checks the stream actually stops. Drives the exact decision the bug '
          'swallowed, so it takes seconds instead of a 30-second stationary '
          'dwell. No walking required.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
