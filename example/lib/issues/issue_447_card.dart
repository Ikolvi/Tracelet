import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #447 — Android reboot of a parked SMART session.
///
/// Going stationary in SMART mode writes PERIODIC as the *pace*;
/// `BootReceiver` read that instead of the *strategy* the app started, so a
/// `start()` session rebooted into a 15-minute WorkManager fix with no
/// foreground service, motion detector or heartbeat.
///
/// **What this card does**: a reboot cannot be driven from inside the app, so
/// it only sets up the state the bug needs — a SMART `start()` session parked
/// stationary, with `startOnBoot` — and lists the manual check.
class Issue447Card extends StatefulWidget {
  const Issue447Card({super.key});

  @override
  State<Issue447Card> createState() => _Issue447CardState();
}

class _Issue447CardState extends State<Issue447Card>
    with IssueCardRun<Issue447Card> {
  @override
  IssueRunner? get cardRunner => _run;

  Future<void> _run() async {
    if (!Platform.isAndroid) {
      setStatus('ℹ️ Android only.');
      return;
    }
    setRunning(running: true);
    try {
      await Tracelet.requestLocationAuthorization();
      await Tracelet.ready(
        const Config(
          motion: MotionConfig(
            motionDetectionMode: MotionDetectionMode.smart,
            stationaryTrackingMode: StationaryTrackingMode.periodic,
          ),
          app: AppConfig(stopOnTerminate: false, startOnBoot: true),
        ),
      );
      await Tracelet.start();
      // Move, then stop: only a real moving -> stationary switch writes the
      // PERIODIC pace the bug needs.
      await Tracelet.changePace(true);
      await Future<void>.delayed(const Duration(seconds: 2));
      await Tracelet.changePace(false);
      final s = await Tracelet.getState();
      setStatus(
        'ℹ️ Set up: SMART start() session, parked (isMoving=${s.isMoving}), '
        'startOnBoot on. Tracking is left running.\n\n'
        'Manual check (needs "Allow all the time"):\n'
        '1. adb reboot — do not open the app.\n'
        '2. adb shell dumpsys activity services <pkg> → LocationService is '
        'running.\n'
        '3. logcat shows "startOnBoot=true, trackingMode=CONTINUOUS '
        '(pace=PERIODIC)". Before the fix: only PeriodicLocationWorker, no '
        'service.\n\nStop tracking afterwards from the main screen.',
      );
    } catch (e) {
      setStatus('❌ FAILED: $e');
    } finally {
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'boot reboot BootReceiver startOnBoot smart periodic pace '
          'sessionTrackingMode workmanager 447 428',
      title: '#447: reboot restores a parked SMART session',
      description:
          'A parked SMART start() session rebooted into a 15-minute WorkManager '
          'fix. Sets up the state; the reboot check is manual.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
