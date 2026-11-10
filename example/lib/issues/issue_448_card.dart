import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #448 — Android `ready()` on a parked SMART session dropped the
/// stationary periodic check.
///
/// `ready()` resumes with `start()`, which cancels the periodic work, and the
/// coordinator — already holding "stationary periodic" — answered NONE, so
/// nothing re-armed it. No periodic fix arrived again.
///
/// **What this card proves**: with a 60 s stationary interval, a parked SMART
/// session taken over by a second `ready()` (what reopening the app does)
/// still delivers a `periodic` fix within 2 minutes.
class Issue448Card extends StatefulWidget {
  const Issue448Card({super.key});

  @override
  State<Issue448Card> createState() => _Issue448CardState();
}

class _Issue448CardState extends State<Issue448Card>
    with IssueCardRun<Issue448Card> {
  @override
  IssueRunner? get cardRunner => _run;

  static const _config = Config(
    motion: MotionConfig(
      motionDetectionMode: MotionDetectionMode.smart,
      stationaryTrackingMode: StationaryTrackingMode.periodic,
      stationaryPeriodicInterval: 60,
      // Low accuracy so a network fix is enough: indoors a high-accuracy
      // request can time out, and the card would fail with the timer armed.
      stationaryPeriodicAccuracy: DesiredAccuracy.low,
    ),
    app: AppConfig(stopOnTerminate: false),
    http: HttpConfig(autoSync: false),
  );

  Future<void> _run() async {
    if (!Platform.isAndroid) {
      setStatus('ℹ️ Android only.');
      return;
    }
    setRunning(running: true);
    StreamSubscription<Location>? sub;
    try {
      await Tracelet.requestLocationAuthorization();
      await Tracelet.ready(_config);
      await Tracelet.start();
      await Tracelet.changePace(false);
      setStatus('⏳ Parked. Calling ready() again, as a reopen does…');
      await Tracelet.ready(_config);

      final periodic = Completer<void>();
      sub = Tracelet.onLocation((l) {
        if (l.event == 'periodic' && !periodic.isCompleted) {
          periodic.complete();
        }
      });
      setStatus('⏳ Waiting up to 2 min for a periodic fix…');
      await periodic.future.timeout(const Duration(minutes: 2));
      setStatus(
        '✅ SUCCESS: a periodic fix arrived after the ready() takeover.',
      );
    } on TimeoutException {
      setStatus(
        '❌ FAILED — no periodic fix in 2 min after ready(). Either the '
        'stationary check was not re-armed (#448), or it fired and the device '
        'could not get a fix (check logcat for "switching to '
        'STATIONARY_PERIODIC", and try near a window).',
      );
    } catch (e) {
      setStatus('❌ FAILED: $e');
    } finally {
      await sub?.cancel();
      await Tracelet.stop();
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'ready takeover smart stationary periodic timer re-arm coordinator '
          'action NONE 448',
      title: '#448: ready() keeps the SMART stationary check',
      description:
          'Reopening the app on a parked SMART session cancelled the periodic '
          'check for good. Parks, calls ready() again, and waits for a '
          'periodic fix.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
