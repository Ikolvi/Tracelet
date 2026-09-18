import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #414 — an in-app fence wake-up promotes the session to moving, so a
/// parked device streams GPS for the rest of its life.
///
/// A fence too small for the OS to resolve is registered *inflated* and decided
/// in-app, so the transition Android fires is a **hint** that you are near it,
/// not a crossing. Acting on that hint used to run the same switch a real motion
/// wake-up does: `isMoving = true`, tracking mode continuous, stationary
/// schedule cancelled. The device had parked itself correctly one line earlier
/// (`accelMoving=false speedMoving=false`) and then streamed 2-second GPS with
/// the indicator lit for the rest of the session, reporting `Is moving: true`
/// on a desk.
///
/// The pace was inherited from there, too: every later resume read it, forced
/// the speed machine back to moving, and left the coordinator with no stationary
/// decision to make.
///
/// **What this card proves.** That the wake-up **borrows** the stream instead of
/// committing a pace — the motion state stays exactly as the sensors set it, and
/// the loan is bounded: when the window closes the coordinator re-judges, and
/// parks again if both inputs still say stationary.
class Issue414Card extends StatefulWidget {
  const Issue414Card({super.key});

  @override
  State<Issue414Card> createState() => _Issue414CardState();
}

class _Issue414CardState extends State<Issue414Card>
    with IssueCardRun<Issue414Card> {
  static const String _fenceId = 'issue_414_wakeup_fence';

  /// Under the 100 m the OS can resolve, so it is evaluated in-app whatever
  /// `geofenceModeHighAccuracy` says (#355) — which is what makes the OS
  /// transition a hint rather than a crossing.
  static const double _radiusMeters = 10;

  /// Long enough to cover the park, the wake-up, and the 60 s loan window that
  /// follows it.
  static const _observeWindow = Duration(seconds: 100);

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
            stopTimeout: 1,
          ),
          http: HttpConfig(autoSync: false),
          logger: LoggerConfig(logLevel: LogLevel.off),
        ),
      );

      await Tracelet.stop();
      await Tracelet.removeGeofences();

      setStatus('⏳ Taking a position to put the fence on…');
      final here = await Tracelet.getCurrentPosition(
        desiredAccuracy: DesiredAccuracy.high,
        timeout: 30,
      );
      // Centred where you are, so the OS reports you inside it immediately and
      // the wake-up fires without you moving.
      await Tracelet.addGeofence(
        Geofence(
          identifier: _fenceId,
          latitude: here.coords.latitude,
          longitude: here.coords.longitude,
          radius: _radiusMeters,
        ),
      );

      await Tracelet.destroyLog();
      await Tracelet.start();

      setStatus(
        '🧍 Keep the device still for ${_observeWindow.inSeconds}s.\n\n'
        'The session parks, the fence wakes it, and the question is whether the '
        'wake-up quietly claims you are moving.',
      );
      await Future<void>.delayed(_observeWindow);

      final logs = await Tracelet.getLogs(600);
      bool saw(String needle) => logs.any((l) => l.message.contains(needle));

      final woke = saw('resumeStreamForEvaluator') || saw('[geofence]');
      check(
        'the fence wake-up ran',
        pass: woke,
        detail: woke
            ? 'the precondition holds — an in-app fence pulled the stream back up'
            : 'no evaluator wake-up in the log. Either the fence was not stored '
                  'or the OS never fired a transition, and without that the bug '
                  'cannot be exercised',
      );

      // The bug: the wake-up committed a pace no sensor asked for.
      final state = await Tracelet.getState();
      check(
        'the wake-up did not commit a moving pace',
        pass: !state.isMoving,
        detail: !state.isMoving
            ? 'the device is still reported as stationary, which is what the '
                  'motion sensors actually said'
            : 'isMoving=true on a device that has not moved. The hint was '
                  'promoted to a motion transition, and every later resume will '
                  'inherit it (#414)',
      );

      final reparked =
          saw('reconcilePosture') || saw('continuous updates stopping');
      check(
        'the borrowed stream was handed back',
        pass: reparked,
        detail: reparked
            ? 'the loan window closed and the coordinator re-judged the state, '
                  'parking again because both inputs still said stationary'
            : 'the stream is still open with nothing holding it. A wake-up that '
                  'never gives the stream back is a full-rate session on a '
                  'parked device',
      );

      await Tracelet.removeGeofences();
      await Tracelet.stop();

      final header = allPass
          ? '✅ SUCCESS: a fence wake-up borrows the stream without claiming motion.'
          : '❌ FAILED — #414 not satisfied on this build.';

      setStatus(
        '$header\n\n${results.join('\n')}\n\n'
        'The fence still gets what it needs: the wake-up starts the engine so '
        'the evaluator has a stream to decide from. What it no longer does is '
        'write a pace on the strength of a proximity hint — the sensors keep '
        'that job, and the loan expires on its own.',
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
          'geofence wakeup evaluator hint promotes moving pace parked device '
          'continuous GPS battery drain borrow stream loan window reconcile '
          '414 412 409 355 357',
      title: '#414: a fence wake-up tells the session the device is moving',
      description:
          'Stores a 10 m fence around you, parks a stationary session, and checks '
          'that the OS wake-up borrows a stream without writing a moving pace — '
          'and hands it back. No walking required.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
