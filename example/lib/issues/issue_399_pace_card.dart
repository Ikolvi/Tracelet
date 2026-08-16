import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// A walking user was classified as stationary, and on Android a stationary
/// session could not be woken again.
///
/// Two defects behind one report of "tracking stops on its own".
///
/// **The pace.** `speedMovingThreshold` defaulted to 1.5 m/s, above an average
/// walking pace of ~1.4 m/s, and one threshold governed both directions. A
/// field trace shows what that does to an ordinary walk:
///
/// ```
/// 15:21:58 STATIONARY -> MOVING — woke on speed=1.50 >= threshold=1.50
/// 15:21:59 MOVING -> SLOWING — speed=1.31 < threshold=1.50
/// 15:22:29 SLOWING -> STATIONARY — speed=1.47, elapsed=30s, lowCount=28
/// ```
///
/// Reaching STATIONARY switches the session to periodic fixes. The entry
/// threshold is now 0.9 m/s and leaving MOVING uses a separate lower one
/// (`speedStationaryThreshold`, 65 % of the entry threshold by default); the gap
/// is a hysteresis band.
///
/// **The wake.** On Android, `TYPE_SIGNIFICANT_MOTION` is a one-shot trigger
/// sensor, and the wake path tore down both wake sources before asking the
/// coordinator what to do with the event. A declined wake left the session
/// stationary with significant motion consumed, shake monitoring stopped and the
/// accelerometer switched to stillness detection — which only notices the device
/// *stopping*. Backgrounded, where `TYPE_ACCELEROMETER` delivers nothing while
/// the device is suspended, nothing could ever wake it again.
///
/// **What this card proves.** The thresholds in force, that the band is ordered
/// correctly, and — by walking — that a normal pace is reported as moving rather
/// than sliding into stationary.
class Issue399PaceCard extends StatefulWidget {
  const Issue399PaceCard({super.key});

  @override
  State<Issue399PaceCard> createState() => _Issue399PaceCardState();
}

class _Issue399PaceCardState extends State<Issue399PaceCard>
    with IssueCardRun<Issue399PaceCard> {
  /// Longer than `speedStationaryDelay` (30 s in the demo config), so a walk
  /// that was going to be misread as stationary has time to be.
  static const _walkWindow = Duration(seconds: 75);

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

    StreamSubscription<Location>? motionSub;
    try {
      // ---------------------------------------------------------------------
      // 1. The defaults, before anything moves
      // ---------------------------------------------------------------------
      const defaults = MotionConfig();
      check(
        'the moving threshold sits below a walking pace',
        pass: defaults.speedMovingThreshold < 1.2,
        detail:
            '${defaults.speedMovingThreshold} m/s — an average walk is ~1.4 m/s, '
            'so the old 1.5 put the median pedestrian on the wrong side',
      );
      check(
        'leaving MOVING takes a lower speed than entering it',
        pass: defaults.speedStationaryThreshold < defaults.speedMovingThreshold,
        detail:
            'enter ≥ ${defaults.speedMovingThreshold} m/s, '
            'leave < ${defaults.speedStationaryThreshold.toStringAsFixed(3)} m/s '
            '— the gap is the hysteresis band',
      );

      const configured = MotionConfig(
        speedMovingThreshold: 2,
        speedStationaryThreshold: 5,
      );
      check(
        'an exit threshold above the entry one is clamped',
        pass: configured.speedStationaryThreshold <= 2.0,
        detail:
            '${configured.speedStationaryThreshold} m/s — an exit threshold '
            'above the entry one would re-create the flapping the band prevents',
      );

      // ---------------------------------------------------------------------
      // 2. Walk, and stay 'moving' while doing it
      // ---------------------------------------------------------------------
      await Tracelet.requestLocationAuthorization();
      await Tracelet.ready(
        const Config(
          geo: GeoConfig(distanceFilter: 10),
          motion: MotionConfig(
            motionDetectionMode: MotionDetectionMode.smart,
            speedStationaryDelay: 30,
            stopTimeout: 1,
          ),
          http: HttpConfig(autoSync: false),
          logger: LoggerConfig(logLevel: LogLevel.debug),
        ),
      );

      final motionChanges = <bool>[];
      motionSub = Tracelet.onMotionChange(
        (location) => motionChanges.add(location.isMoving),
      );

      await Tracelet.start();
      _set('🚶 Walk at a normal pace for ${_walkWindow.inSeconds}s…');
      await Future<void>.delayed(_walkWindow);

      final state = await Tracelet.getState();
      final wentStationary = motionChanges.contains(false);

      check(
        'the session still reports moving after a walk',
        pass: state.isMoving,
        detail: state.isMoving
            ? 'isMoving=true throughout'
            : 'isMoving=false — the pace machine stood the walk down, which is '
                  'the defect. Check the lifecycle trace for '
                  '"speed-motion: MOVING -> SLOWING"',
      );
      check(
        'no stationary motionchange was emitted mid-walk',
        pass: !wentStationary,
        detail: wentStationary
            ? 'a motionchange(isMoving: false) arrived while you were walking'
            : '${motionChanges.length} motionchange event(s), none stationary',
      );

      await Tracelet.stop();

      final header = allPass
          ? '✅ SUCCESS: a normal walking pace reads as moving.'
          : '❌ FAILED — the pace machine still stands a walk down.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'On Android there is a second half to this: a stationary session that '
        'declined a wake used to leave itself unwakeable, because '
        'TYPE_SIGNIFICANT_MOTION is a one-shot trigger and both wake sources '
        'were torn down before the coordinator was consulted. That path now '
        're-arms them and records it on the lifecycle channel — reproduce it by '
        'backgrounding the app while stationary, then moving, and check the '
        'Doctor report for "motion: wake declined".',
      );
    } catch (e) {
      _set('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      await motionSub?.cancel();
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'pace stationary while walking speedMovingThreshold hysteresis '
          'speedStationaryThreshold significant motion wake stuck background '
          'tracking stops on its own 399',
      title: 'Pace: a walking user was classified as stationary',
      description:
          'Checks the moving/stationary thresholds form a hysteresis band with '
          'the entry below walking pace, then walks for 75 s — longer than the '
          'stationary delay — and fails if the session stands the walk down. '
          'Walk at a normal pace for the whole run.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
