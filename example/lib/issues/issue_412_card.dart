import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #412 — a stationary start that opens a stream for an in-app-evaluated
/// fence never parks it.
///
/// A fence the OS cannot resolve — anything under 100 m, and every polygon — is
/// decided in-app, from the location stream. A session that starts stationary
/// runs no stream by design, so the SDK starts one for it (#357). The
/// coordinator was told the session's *pace* before that happened, and it only
/// ever acts on a **change**: with both motion inputs already stationary, every
/// later reading is a repeat that the core discards. Nothing the session can say
/// will end that stream.
///
/// The field report is a phone on a desk holding a 2-second GPS stream at 3 m
/// accuracy from the moment Start was pressed until Stop was, every fix
/// `is_moving: false`, with the location indicator lit the whole time.
///
/// This is the half of #409 its fix could not reach: that posture is decided
/// once, inside `start()`, *before* the branch that opens this stream runs.
///
/// **What this card proves.** That a stationary session which inherits a stream
/// for a fence parks it — and keeps the fence, on the stationary schedule,
/// rather than at full rate.
class Issue412Card extends StatefulWidget {
  const Issue412Card({super.key});

  @override
  State<Issue412Card> createState() => _Issue412CardState();
}

class _Issue412CardState extends State<Issue412Card>
    with IssueCardRun<Issue412Card> {
  static const String _fenceId = 'issue_412_small_fence';

  /// Under the 100 m the OS can resolve, so it is evaluated in-app whatever
  /// `geofenceModeHighAccuracy` says (#355) — which is what pulls the stream up.
  static const double _radiusMeters = 10;

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
          // The default pace, and the one the report starts in: stationary.
          motion: MotionConfig(
            isMoving: false,
            motionDetectionMode: MotionDetectionMode.smart,
          ),
          http: HttpConfig(autoSync: false),
          // A released app runs here, and this is where the evidence has to
          // survive.
          logger: LoggerConfig(logLevel: LogLevel.off),
        ),
      );

      // A session left running by an earlier card would hide the start this
      // card is about.
      await Tracelet.stop();
      await Tracelet.removeGeofences();

      setStatus('⏳ Taking a position to put the fence on…');
      final here = await Tracelet.getCurrentPosition(
        desiredAccuracy: DesiredAccuracy.high,
        timeout: 30,
      );
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

      setStatus('⏳ Watching what the stationary start leaves running…');
      await Future<void>.delayed(const Duration(seconds: 12));

      final logs = await Tracelet.getLogs(300);
      bool saw(String needle) => logs.any((l) => l.message.contains(needle));

      final opened = saw(
        'starting the location stream for an in-app-evaluated',
      );
      check(
        'the fence pulled a location stream up on a stationary start',
        pass: opened,
        detail: opened
            ? 'the precondition holds — a stream the pace never asked for, on a '
                  'session both motion inputs report as parked'
            : 'no stream was opened for the fence. Either the fence was not '
                  'stored, or this build does not evaluate it in-app — without '
                  'that the bug cannot be exercised',
      );

      final parked = saw('continuous updates stopping');
      check(
        'the inherited stream is parked',
        pass: parked,
        detail: parked
            ? 'the coordinator judged the state it was in and switched to the '
                  'stationary schedule'
            : 'the stream is still open. Nothing can stop it: the coordinator '
                  'believes it is parked, and a motion input repeating what it '
                  'already said is discarded — so GPS runs at the configured '
                  'interval, indicator lit, until the session ends (#412)',
      );

      final named = saw('smart-motion: switching to STATIONARY');
      check(
        'the switch is named on the always-on channel',
        pass: named,
        detail: named
            ? 'a released app can report this transition at the default logLevel'
            : 'no smart-motion line — the transition is invisible in a bug report',
      );

      await Tracelet.removeGeofences();
      await Tracelet.stop();

      final header = allPass
          ? '✅ SUCCESS: a stationary start no longer holds a fence stream open.'
          : '❌ FAILED — #412 not satisfied on this build.';

      setStatus(
        '$header\n\n${results.join('\n')}\n\n'
        'The fence is not lost by parking: the stationary schedule fires its '
        'first one-shot immediately and then runs at '
        'motion.stationaryPeriodicInterval, and any real motion puts the '
        'session back on continuous. What it no longer does is hold a '
        'full-rate stream open on a device that never moved.',
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
          'geofence in-app evaluation small radius polygon stationary start '
          'stream never parks continuous GPS battery drain location indicator '
          'always on posture coordinator reconcile 412 409 357 355',
      title:
          '#412: a stationary start never parks the stream it opens for a fence',
      description:
          'Stores a 10 m fence, starts a stationary session, and checks that the '
          'stream the fence pulls up is parked instead of running at full rate '
          'for the whole session. No walking required.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
