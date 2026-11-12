import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #449 — Android `ready()` in SMART/SPEED mode resumed everything as
/// continuous.
///
/// `completeReady()` honoured the stored strategy only in accelerometer mode,
/// so a `startPeriodic()` session came back continuous, foreground service and
/// all, on the next `ready()`.
///
/// **What this card proves**: in SMART mode, `startPeriodic()` followed by a
/// second `ready()` leaves `getState().trackingMode` at `periodic`.
class Issue449Card extends StatefulWidget {
  const Issue449Card({super.key});

  @override
  State<Issue449Card> createState() => _Issue449CardState();
}

class _Issue449CardState extends State<Issue449Card>
    with IssueCardRun<Issue449Card> {
  @override
  IssueRunner? get cardRunner => _run;

  static const _config = Config(
    motion: MotionConfig(motionDetectionMode: MotionDetectionMode.smart),
    app: AppConfig(stopOnTerminate: false),
    http: HttpConfig(autoSync: false),
  );

  Future<void> _run() async {
    if (!Platform.isAndroid) {
      setStatus('ℹ️ Android only.');
      return;
    }
    setRunning(running: true);
    try {
      await Tracelet.requestLocationAuthorization();
      await Tracelet.ready(_config);
      await Tracelet.startPeriodic();
      await Tracelet.ready(_config);
      final mode = (await Tracelet.getState()).trackingMode;
      setStatus(
        mode == TrackingMode.periodic
            ? '✅ SUCCESS: ready() resumed the periodic session as periodic.'
            : '❌ FAILED — ready() resumed as $mode instead of periodic (#449).',
      );
    } catch (e) {
      setStatus('❌ FAILED: $e');
    } finally {
      await Tracelet.stop();
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'ready resume smart speed startPeriodic startGeofences strategy '
          'continuous foreground service 449 428',
      title: '#449: ready() resumes the strategy in SMART mode',
      description:
          'In SMART/SPEED mode ready() always resumed continuous tracking. '
          'Starts periodic, calls ready() again, and checks the mode.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
