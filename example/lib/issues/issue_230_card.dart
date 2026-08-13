// ignore_for_file: avoid_redundant_argument_values

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #230 — runtime config changes (setConfig) did not propagate to the
/// active native tracking/sensor loops. Only a few location keys triggered a
/// restart, and only the LocationEngine was restarted — motion-detector /
/// speed-manager parameter changes (e.g. switching ACCELEROMETER → SPEED) were
/// silently ignored until the app was force-killed.
///
/// The fix performs a clean stop/start of the whole active pipeline when a
/// tracking-relevant key changes. This test starts in ACCELEROMETER mode, clears
/// the native log, switches to SPEED mode via setConfig, then inspects the log
/// for the stop→start lifecycle that proves the pipeline was rebuilt.
class Issue230Card extends StatefulWidget {
  const Issue230Card({super.key});

  @override
  State<Issue230Card> createState() => _Issue230CardState();
}

class _Issue230CardState extends State<Issue230Card>
    with IssueCardRun<Issue230Card> {
  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _test;

  Future<void> _test() async {
    setRunning(running: true);
    try {
      _set('Requesting permissions...');
      final auth = await Tracelet.requestLocationAuthorization();
      if (auth != AuthorizationStatus.always &&
          auth != AuthorizationStatus.whenInUse) {
        _set('❌ FAILED: location permission denied ($auth).');
        return;
      }

      const baseConfig = Config(
        geo: GeoConfig(
          desiredAccuracy: DesiredAccuracy.high,
          distanceFilter: 10,
        ),
        motion: MotionConfig(
          motionDetectionMode: MotionDetectionMode.accelerometer,
          shakeThreshold: 3.5,
          isMoving: true,
        ),
        logger: LoggerConfig(debug: true, logLevel: LogLevel.verbose),
      );

      _set('Starting tracking (ACCELEROMETER mode)...');
      await Tracelet.ready(baseConfig);
      await Tracelet.start();
      await Future<void>.delayed(const Duration(seconds: 1));

      // Clear logs to establish a clean baseline for the setConfig assertion.
      await Tracelet.destroyLog();

      _set('Switching to SPEED mode via setConfig...');
      final newConfig = baseConfig.copyWith(
        motion: const MotionConfig(
          motionDetectionMode: MotionDetectionMode.speed,
          speedMovingThreshold: 0.8,
          isMoving: true,
        ),
      );
      await Tracelet.setConfig(newConfig);

      // Give the native pipeline time to tear down and restart.
      await Future<void>.delayed(const Duration(seconds: 2));

      final logs = (await Tracelet.getLog()).toLowerCase();
      await Tracelet.stop();

      // A correct restart executes a stop→start cycle on the active loops.
      final hasStop = logs.contains('stop') || logs.contains('destroy');
      final hasStart =
          logs.contains('start') || logs.contains('restarting active');

      if (hasStop && hasStart) {
        _set(
          '✅ SUCCESS: setConfig propagated! The native pipeline performed a '
          'stop→start restart to apply the new motion strategy.',
        );
      } else {
        _set(
          '❌ FAILED: setConfig ignored — no stop/start lifecycle in the native '
          'log (hasStop=$hasStop, hasStart=$hasStart). Sensors are stale.',
        );
      }
    } catch (e) {
      _set('❌ FAILED: $e');
    } finally {
      try {
        await Tracelet.stop();
      } catch (_) {}
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      title: '#230: setConfig ignored by active tracking loops',
      description:
          'Starts in ACCELEROMETER mode, clears the native log, switches to '
          'SPEED mode via setConfig, then asserts the native log shows a '
          'stop→start restart of the pipeline (previously the motion sensors '
          'kept running on stale parameters until the app was force-killed).',
      status: status,
      running: running,
      onRun: _test,
    );
  }
}
