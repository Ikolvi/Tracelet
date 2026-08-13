import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #254 — `setConfig()` restart exposed the same foreground-service race
/// that #237 fixed for `startPeriodic()`.
///
/// When tracking was active and a restart-sensitive key (e.g. `distanceFilter`,
/// `desiredAccuracy`, a motion parameter) changed, `setConfig()` called the full
/// `stop()` — which sends `ACTION_STOP` to `LocationService` (`stopForeground()`
/// + `stopSelf()`) — and then immediately restarted the pipeline with `start()`
/// (`ACTION_START`). On a fresh promotion the `ACTION_STOP` handler's
/// `stopSelf()` could win the race and destroy the service right after
/// `ACTION_START` promoted it, leaving NO foreground service at all — killing
/// background tracking on the next app swipe-away.
///
/// The fix: `stop()` now takes `preserveForegroundService`, and the `setConfig()`
/// restart path passes `true` whenever the target mode still needs the service.
/// The up-front `ACTION_STOP` is skipped and the idempotent `ACTION_START` from
/// the following `start*()` re-asserts foreground with no gap and no race. When
/// the target mode does not use the service, it is stopped cleanly (no
/// immediately-following start to race).
///
/// This test starts continuous tracking with a foreground service, then applies
/// a restart-sensitive `setConfig()` and verifies tracking stays enabled with a
/// running service. Foreground service is Android-only, so it is skipped on
/// other platforms. Confirm on-device that the service survives with:
///
///   adb shell dumpsys activity services <your.package.name>
class Issue254Card extends StatefulWidget {
  const Issue254Card({super.key});

  @override
  State<Issue254Card> createState() => _Issue254CardState();
}

class _Issue254CardState extends State<Issue254Card>
    with IssueCardRun<Issue254Card> {
  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _test;

  Future<void> _test() async {
    if (!Platform.isAndroid) {
      _set('⏭️ SKIPPED: foreground service is Android-only.');
      return;
    }

    setRunning(running: true);
    try {
      _set('Requesting permissions...');
      final auth = await Tracelet.requestLocationAuthorization();
      if (auth != AuthorizationStatus.always &&
          auth != AuthorizationStatus.whenInUse) {
        _set('❌ FAILED: location permission denied ($auth).');
        return;
      }

      _set('Starting continuous tracking with a foreground service...');
      await Tracelet.ready(
        const Config(
          // Non-default distanceFilter (default is 10) so the setConfig() below
          // genuinely changes it and flips needsRestart=true.
          geo: GeoConfig(distanceFilter: 50),
          android: AndroidConfig(
            foregroundService: ForegroundServiceConfig(
              notificationTitle: 'Issue #254 tracking',
            ),
          ),
          logger: LoggerConfig(debug: true, logLevel: LogLevel.verbose),
        ),
      );

      final started = await Tracelet.start();
      if (!started.enabled) {
        _set('❌ FAILED: tracking did not start (enabled=false).');
        return;
      }

      // Apply a restart-sensitive change. Changing distanceFilter flips
      // needsRestart=true, so the SDK stops and restarts the active pipeline —
      // the exact path that used to race the foreground service into oblivion.
      _set('Applying restart-sensitive setConfig (distanceFilter 50 → 0)...');
      await Tracelet.setConfig(const Config(geo: GeoConfig(distanceFilter: 0)));

      // Give the ACTION_STOP/ACTION_START commands time to be delivered so a
      // lingering stopSelf() from the old buggy path would have destroyed the
      // service by now.
      await Future.delayed(const Duration(seconds: 2));

      final state = await Tracelet.getState();
      if (state.enabled && state.trackingMode == TrackingMode.location) {
        _set(
          '✅ SUCCESS: tracking is still enabled in continuous (location) mode '
          'after a restart-sensitive setConfig(). The foreground service is '
          'preserved '
          'across the restart (no ACTION_STOP → stopSelf() racing the follow-up '
          'ACTION_START), so it survives app swipe-away. Verify on-device:\n'
          'adb shell dumpsys activity services <your.package.name>\n'
          '→ a LocationService entry should still be listed '
          '(isForeground=true).',
        );
      } else {
        _set(
          '❌ FAILED: expected enabled continuous mode after setConfig but got '
          'enabled=${state.enabled}, mode=${state.trackingMode.name}.',
        );
      }
    } catch (e) {
      _set('❌ FAILED: $e');
    } finally {
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      title: '#254: setConfig() restart kills the active foreground service',
      description:
          'Starts continuous tracking with a foreground service, then applies a '
          'restart-sensitive setConfig() (distanceFilter change). The full '
          'stop()/start() used to race ACTION_STOP against ACTION_START and '
          'could destroy the just-promoted service; the service is now preserved '
          'across the restart. Android-only. Verify via dumpsys.',
      status: status,
      running: running,
      onRun: _test,
    );
  }
}
