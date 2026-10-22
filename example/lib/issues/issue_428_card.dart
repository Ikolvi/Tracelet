import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #428 (and #436) — on Android, reopening the app after a killed-state
/// stationary period resumed PERIODIC on `ready()` and stopped the foreground
/// service and the motion detector.
///
/// The killed-state engine parks a still device with
/// `LocationService.switchToStationaryPeriodic`, which wrote PERIODIC into
/// `StateManager.trackingMode` (#319). That is a *pace*. Every resume decision
/// read the same field as the *strategy*:
///
///  * `ready()` resumed `startPeriodic()`, which stops the motion detector and,
///    without `periodicUseForegroundService`, the foreground service (#428);
///  * a START_STICKY restart after process death was declined as "periodic
///    without a foreground service", and the boot path built no engine and no
///    detector, leaving a cached process (importance 400) with nothing to wake
///    it, which the low-memory killer then reaps over and over. That is the
///    `exit-info` pattern in #436.
///
/// The strategy is now persisted separately (`sessionTrackingMode`), written
/// only by `start()`, `startPeriodic()` and `startGeofences()`, and read by
/// `ready()`, `setConfig()`, the sticky restart, task removal and the boot
/// bootstrap. A restored session that was parked is re-parked once its
/// detector is armed.
///
/// **What this card can prove:** it cannot swipe the app away or wait out a
/// killed-state park itself, so Run has two phases. With no killed-state park
/// in the log, Run *arms* the scenario — continuous tracking with
/// `stopOnTerminate: false` — and prints the steps. After them, Run again
/// checks that `ready()` brought the session back continuous with the
/// foreground service running, and reads the log for the line the SDK writes
/// when it resumes the strategy over a parked pace. It claims nothing until
/// the park has actually happened.
class Issue428Card extends StatefulWidget {
  const Issue428Card({super.key});

  @override
  State<Issue428Card> createState() => _Issue428CardState();
}

class _Issue428CardState extends State<Issue428Card>
    with IssueCardRun<Issue428Card> {
  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  @override
  IssueRunner? get cardRunner => _run;

  static const _resumedStrategy = 'resuming the started strategy';
  static const _parked = 'switching to stationary periodic';
  static const _declined = 'sticky restart declined';

  static const _config = Config(
    motion: MotionConfig(isMoving: true),
    app: AppConfig(stopOnTerminate: false, startOnBoot: true),
    http: HttpConfig(autoSync: false),
  );

  Future<void> _arm() async {
    try {
      await Tracelet.destroyLog();
      await Tracelet.start();
      await Tracelet.changePace(true);
      setStatus(
        '🟡 Armed: continuous tracking with stopOnTerminate: false.\n\n'
        '1. Swipe the app away from Recents.\n'
        '2. Leave the device still for ~6 minutes, until the killed-state '
        'engine parks (the log line "$_parked").\n'
        '3. Reopen the app and press Run on this card again.',
      );
    } catch (e) {
      setStatus('❌ FAILED to arm: $e');
    }
  }

  Future<void> _run() async {
    setRunning(running: true);
    final results = <String>[];
    var allPass = true;

    void check(String name, {required bool pass, required String detail}) {
      results.add('${pass ? '✅' : '❌'} $name — $detail');
      if (!pass) allPass = false;
    }

    try {
      if (!_isAndroid) {
        setStatus(
          'ℹ️ Android only — the killed-state engine is Android-specific.',
        );
        return;
      }

      // ready() is the call that used to resume the parked pace as periodic.
      final state = await Tracelet.ready(_config);
      final health = await Tracelet.getForegroundServiceHealth();
      final logs = await Tracelet.getLogs(2000);
      final parked = logs.any((l) => l.message.contains(_parked));
      final resumedLine = logs
          .where((l) => l.message.contains(_resumedStrategy))
          .map((l) => l.message)
          .toList();
      final declined = logs
          .where((l) => l.message.contains(_declined))
          .map((l) => l.message)
          .toList();
      final serviceRunning = health['serviceRunning'] == true;

      if (!state.enabled || !parked) {
        await _arm();
        return;
      }

      check(
        'ready() resumed the continuous strategy',
        pass: state.trackingMode == TrackingMode.location,
        detail:
            'trackingMode=${state.trackingMode.name}'
            '${state.trackingMode == TrackingMode.periodic ? ' — the parked pace was resumed as the strategy (the bug)' : ''}',
      );
      check(
        'the foreground service survived ready()',
        pass: serviceRunning,
        detail: 'serviceRunning=$serviceRunning',
      );
      check(
        'no sticky restart was declined',
        pass: declined.isEmpty,
        detail: declined.isEmpty ? 'none in the log' : declined.first,
      );
      if (resumedLine.isNotEmpty) {
        results.add('ℹ️ ${resumedLine.first}');
      }

      final header = allPass
          ? '✅ SUCCESS: the reopened session is continuous with its service.'
          : '❌ FAILED — #428 not satisfied on this build.';
      setStatus(
        '$header\n\n${results.join('\n')}\n\n'
        'Walking afterwards should produce "motion … isMoving=true" and '
        'continuous fixes again. Before the fix, ready() reported '
        'trackingMode=periodic here, the service was gone and the detector '
        'never re-armed.',
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
          'android killed state stationary periodic ready resume foreground '
          'service stopped motion detector low memory exit-info sticky restart '
          'trackingMode 428 436 319',
      title: '#428 / #436: a parked session reopens continuous',
      description:
          'The killed-state stationary park wrote PERIODIC as the tracking '
          'strategy, so ready() resumed periodic (stopping the service and '
          'detector) and a sticky restart was declined. Arm, swipe away, wait '
          'for the park, reopen, then Run again.',
      status: status,
      running: running,
      onRun: _run,
      // The card's own ready() is the call under test; the harness would
      // otherwise make it first, with a different config.
      prepare: false,
    );
  }
}
