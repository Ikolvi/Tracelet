import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #237 — periodic mode with `periodicUseForegroundService: true` did not
/// start a foreground service, so tracking died the moment the app was swiped
/// away (only reproducible for sub-15-min intervals, the foreground-service
/// strategy).
///
/// Root cause: `startPeriodic()` tore the foreground service down up-front
/// (ACTION_STOP) and immediately restarted it (ACTION_START) in the same call.
/// On a fresh start the ACTION_STOP handler's `stopSelf()` raced the pending
/// ACTION_START and could win, destroying the service right after it was
/// promoted — leaving no foreground service at all. Continuous mode never
/// pre-stops, which is why it was unaffected.
///
/// This test starts the exact reporter configuration (periodic + foreground
/// service, 60s interval) and verifies tracking is enabled in periodic mode.
/// Foreground service is Android-only, so it is skipped on other platforms.
/// Confirm on-device that the service now survives with:
///
///   adb shell dumpsys activity services <your.package.name>
class Issue237Card extends StatefulWidget {
  const Issue237Card({super.key});

  @override
  State<Issue237Card> createState() => _Issue237CardState();
}

class _Issue237CardState extends State<Issue237Card>
    with IssueCardRun<Issue237Card> {
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

      _set('Configuring periodic + foreground service (60s interval)...');
      await Tracelet.ready(
        const Config(
          // 60s — well under the 15-min WorkManager floor, so the plugin picks
          // the foreground-service strategy (matches the #237 report).
          geo: GeoConfig(periodicLocationInterval: 60),
          android: AndroidConfig(periodicUseForegroundService: true),
          // Periodic mode already does one-shot fixes; no heartbeat needed.
          app: AppConfig(heartbeatInterval: -1),
          logger: LoggerConfig(debug: true, logLevel: LogLevel.verbose),
        ),
      );

      _set('Starting periodic tracking...');
      final state = await Tracelet.startPeriodic();

      if (state.enabled && state.trackingMode == TrackingMode.periodic) {
        _set(
          '✅ SUCCESS: periodic tracking started with a foreground service. '
          'The service is no longer torn down by the ACTION_STOP/ACTION_START '
          'race, so it survives when you swipe the app away. Verify on-device:\n'
          'adb shell dumpsys activity services <your.package.name>\n'
          '→ a LocationService entry should be listed (isForeground=true).',
        );
      } else {
        _set(
          '❌ FAILED: expected enabled periodic mode but got '
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
      title: '#237: periodic mode does not start a foreground service',
      description:
          'Starts periodic mode with periodicUseForegroundService:true and a 60s '
          'interval (the exact reporter setup). The foreground service used to '
          'be stopped-then-restarted, racing itself into oblivion; now it starts '
          'and survives app swipe-away. Android-only. Verify via dumpsys.',
      status: status,
      running: running,
      onRun: _test,
    );
  }
}
