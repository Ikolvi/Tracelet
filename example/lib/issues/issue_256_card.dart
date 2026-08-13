import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #256 — `setConfig()` could restore a TEMPORARY stationary mode as the
/// main tracking mode.
///
/// In `MotionDetectionMode.smart` / `.speed`, the SDK runs a single continuous
/// motion-aware pipeline that TEMPORARILY flips `trackingMode` to
/// `periodic`/`geofences` while the device is stationary (the stationary
/// sub-state chosen by `stationaryTrackingMode`). That temporary value is not an
/// explicitly-started standalone mode.
///
/// A restart-sensitive `setConfig()` used to capture that temporary
/// `trackingMode` and rebuild the pipeline via the standalone
/// `startPeriodic()` / `startGeofences()` paths — which tear down the very
/// motion-detection pipeline that is supposed to switch back to continuous once
/// the device moves again. Tracking could get stranded in a standalone
/// stationary mode with no way back to continuous.
///
/// The fix mirrors the resume-on-ready logic: when the motion-detection mode is
/// `smart`/`speed`, `setConfig()` restarts the continuous motion-aware pipeline
/// via `start(isResume: true)` regardless of the temporary `trackingMode`; the
/// pipeline re-enters the stationary sub-state on its own when still stationary.
///
/// This test starts SMART tracking with `stationaryTrackingMode: geofences`,
/// forces the stationary sub-state via `changePace(false)`, clears the native
/// log, then applies a restart-sensitive `setConfig()` and inspects the log to
/// confirm the restart went through the continuous `start()` path and did NOT
/// rebuild a standalone geofence-only mode.
class Issue256Card extends StatefulWidget {
  const Issue256Card({super.key});

  @override
  State<Issue256Card> createState() => _Issue256CardState();
}

class _Issue256CardState extends State<Issue256Card>
    with IssueCardRun<Issue256Card> {
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

      _set('Starting SMART tracking (stationaryTrackingMode: geofences)...');
      await Tracelet.ready(
        const Config(
          // Non-default distanceFilter so the setConfig() below genuinely
          // changes it and flips needsRestart=true.
          geo: GeoConfig(distanceFilter: 50),
          motion: MotionConfig(
            motionDetectionMode: MotionDetectionMode.smart,
            stationaryTrackingMode: StationaryTrackingMode.geofences,
            isMoving: true,
          ),
          logger: LoggerConfig(debug: true, logLevel: LogLevel.verbose),
        ),
      );

      final started = await Tracelet.start();
      if (!started.enabled) {
        _set('❌ FAILED: tracking did not start (enabled=false).');
        return;
      }

      // Force the continuous motion-aware pipeline into its stationary
      // sub-state. With stationaryTrackingMode=geofences this flips the
      // persisted trackingMode to `geofences` even though the pipeline is still
      // fundamentally the continuous SMART pipeline.
      _set('Forcing stationary sub-state via changePace(false)...');
      await Tracelet.changePace(false);
      await Future<void>.delayed(const Duration(seconds: 2));

      final stationaryState = await Tracelet.getState();
      final tempMode = stationaryState.trackingMode;

      // Clear the log so the assertion only sees the setConfig restart path.
      await Tracelet.destroyLog();

      // Apply a restart-sensitive change (distanceFilter). This flips
      // needsRestart=true, so the SDK stops and restarts the active pipeline —
      // the exact path that used to rebuild a standalone stationary mode.
      _set('Applying restart-sensitive setConfig (distanceFilter 50 → 0)...');
      await Tracelet.setConfig(const Config(geo: GeoConfig(distanceFilter: 0)));
      await Future<void>.delayed(const Duration(seconds: 2));

      final logs = (await Tracelet.getLog()).toLowerCase();
      final state = await Tracelet.getState();

      await Tracelet.stop();

      final didRestart = logs.contains('restarting active pipeline');
      final restartedContinuous =
          logs.contains('start() — tracking started') ||
          logs.contains('start() - tracking started') ||
          logs.contains('resuming motion-aware') ||
          logs.contains('resuming tracking with motion detection');
      // The bug rebuilt a STANDALONE stationary mode via the public
      // startGeofences()/startPeriodic() entry points.
      final rebuiltStandaloneStationary =
          logs.contains('geofence-only mode') ||
          logs.contains('periodic tracking started');

      if (!state.enabled) {
        _set(
          '❌ FAILED: tracking is disabled after setConfig '
          '(temp stationary mode was: ${tempMode.name}).',
        );
        return;
      }

      if (didRestart && restartedContinuous && !rebuiltStandaloneStationary) {
        _set(
          '✅ SUCCESS: while temporarily stationary in SMART mode (trackingMode '
          'became "${tempMode.name}"), the restart-sensitive setConfig() '
          'restarted the continuous motion-aware pipeline via start() — it did '
          'NOT rebuild a standalone ${tempMode.name}-only mode that would strand '
          'tracking. The motion pipeline that switches back to continuous on '
          'movement is preserved.',
        );
      } else if (rebuiltStandaloneStationary) {
        _set(
          '❌ FAILED: setConfig() rebuilt a standalone stationary mode after a '
          'temporary "${tempMode.name}" sub-state — the motion-detection '
          'pipeline was torn down (didRestart=$didRestart, '
          'restartedContinuous=$restartedContinuous).',
        );
      } else {
        _set(
          '⚠️ INCONCLUSIVE: could not confirm the restart path from the native '
          'log (didRestart=$didRestart, restartedContinuous=$restartedContinuous, '
          'tempMode=${tempMode.name}). This environment may not have entered the '
          'stationary sub-state. Verify on-device while genuinely stationary.',
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
      title: '#256: setConfig() restores a temporary stationary mode',
      description:
          'Starts SMART tracking with stationaryTrackingMode=geofences, forces '
          'the stationary sub-state (changePace(false)) so trackingMode '
          'temporarily becomes geofences, clears the log, then applies a '
          'restart-sensitive setConfig(). Asserts the restart went through the '
          'continuous motion-aware start() path and did NOT rebuild a standalone '
          'geofence/periodic mode (which would strand tracking).',
      status: status,
      running: running,
      onRun: _test,
    );
  }
}
