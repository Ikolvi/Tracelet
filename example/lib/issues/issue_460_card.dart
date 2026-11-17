import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

class Issue460Card extends StatefulWidget {
  const Issue460Card({super.key});

  @override
  State<Issue460Card> createState() => _Issue460CardState();
}

class _Issue460CardState extends State<Issue460Card>
    with IssueCardRun<Issue460Card> {
  static const _window = Duration(seconds: 45);

  @override
  IssueRunner? get cardRunner => _run;

  Future<int> _freshFixCount({required bool isMoving}) async {
    final startedAt = DateTime.now();
    final timestamps = <String>{};
    final done = Completer<int>();
    final subscription = Tracelet.onLocation((fix) {
      final timestamp = DateTime.tryParse(fix.timestamp);
      if (fix.isMoving != isMoving ||
          !const [null, '', 'location'].contains(fix.event) ||
          timestamp == null ||
          timestamp.isBefore(startedAt)) {
        return;
      }
      timestamps.add(fix.timestamp);
      if (timestamps.length == 2 && !done.isCompleted) done.complete(2);
    });
    try {
      return await done.future.timeout(
        _window,
        onTimeout: () => timestamps.length,
      );
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> _run() async {
    setRunning(running: true);
    final results = <String>[];
    try {
      await Tracelet.stop();
      await Tracelet.ready(
        const Config(
          geo: GeoConfig(
            desiredAccuracy: DesiredAccuracy.high,
            distanceFilter: 0,
          ),
          android: AndroidConfig(
            allowIdenticalLocations: true,
            stationaryLocationUpdateInterval: 5000,
          ),
          motion: MotionConfig(
            isMoving: true,
            motionDetectionMode: MotionDetectionMode.speed,
            stationaryTrackingMode: StationaryTrackingMode.continuous,
            stationaryPeriodicAccuracy: DesiredAccuracy.low,
          ),
          persistence: PersistenceConfig(persistMode: PersistMode.none),
          http: HttpConfig(autoSync: false),
        ),
      );
      await Tracelet.start();

      setStatus(
        'Waiting for two fresh moving-pace locations. Keep the app open.',
      );
      final moving = await _freshFixCount(isMoving: true);
      if (moving < 2) {
        setStatus(
          'NOT EXERCISED — received $moving initial fixes. Try with a clear view of the sky.',
        );
        return;
      }
      results.add('Initial moving pace: $moving fresh fixes');

      await Tracelet.changePace(false);
      setStatus(
        'Waiting for two stationary-pace locations. Leave the phone still.',
      );
      final stationary = await _freshFixCount(isMoving: false);
      results.add('Stationary pace: $stationary fresh fixes');

      await Tracelet.changePace(true);
      setStatus(
        'Waiting for two fresh locations after resuming the moving pace.',
      );
      final resumed = await _freshFixCount(isMoving: true);
      results.add('Resumed moving pace: $resumed fresh fixes');
      final pass = stationary == 2 && resumed == 2;
      setStatus('${pass ? 'PASS' : 'FAIL'}\n${results.join('\n')}');
    } on Exception catch (error, stack) {
      debugPrint(
        'Issue #460 testing stationary continuous tracking: $error\n$stack',
      );
      setStatus('Could not complete the tracking check. $error');
    } finally {
      try {
        await Tracelet.stop();
      } on Exception catch (error, stack) {
        debugPrint(
          'Issue #460 stopping tracking after the check: $error\n$stack',
        );
        setStatus('$status\nStopping tracking failed. $error');
      } finally {
        setRunning(running: false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => IssueCardShell(
    title: '#460 — Keep delivering fixes while stationary',
    description:
        'Checks fresh location events before parking, while stationary, and '
        'after returning to the moving pace. Leave the phone where it can '
        'receive a location. The card sets the pace directly and does not '
        'measure automatic wake latency or power use.',
    status: status,
    running: running,
    onRun: _run,
  );
}
