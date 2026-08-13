import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #243 — startPeriodic posts the foreground notification even though
/// `periodicUseForegroundService: false` and `foregroundService.enabled: false`.
///
/// Root cause: on aggressive OEMs (Xiaomi/Huawei/Samsung/OnePlus/Oppo/Vivo)
/// the native ConfigManager silently forced both flags back to true, so
/// startPeriodic() took the foreground-service branch and posted the default
/// "Tracelet / Tracking location in background" notification. The explicit
/// config is now authoritative; the SDK logs a reliability warning instead.
///
/// This test runs the reporter's exact repro. The deterministic part asserts
/// periodic mode started with the intended config; the notification check is
/// visual — background the app and confirm NO Tracelet notification appears.
class Issue243Card extends StatefulWidget {
  const Issue243Card({super.key});

  @override
  State<Issue243Card> createState() => _Issue243CardState();
}

class _Issue243CardState extends State<Issue243Card>
    with IssueCardRun<Issue243Card> {
  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _test;

  Future<void> _test() async {
    if (running) return;
    setRunning(running: true);

    try {
      if (!Platform.isAndroid) {
        _set('N/A: this is an Android foreground-service issue.');
        return;
      }

      _set('Stopping any existing tracking...');
      await Tracelet.stop();

      _set("Applying the reporter's periodic no-foreground config...");
      await Tracelet.ready(
        Config.balanced().copyWith(
          geo: const GeoConfig(
            // periodicLocationInterval: 900 and
            // periodicUseForegroundService/periodicUseExactAlarms: false are
            // the defaults — the reporter set them explicitly; kept implicit
            // here to satisfy avoid_redundant_argument_values.
            periodicDesiredAccuracy: DesiredAccuracy.low,
          ),
          app: const AppConfig(stopOnTerminate: false, startOnBoot: true),
          android: const AndroidConfig(
            foregroundService: ForegroundServiceConfig(enabled: false),
          ),
        ),
      );

      final state = await Tracelet.startPeriodic();

      final config = Tracelet.activeConfig;
      final fgDisabled =
          !config.android.foregroundService.enabled &&
          !config.android.periodicUseForegroundService;

      if (!state.enabled) {
        _set('❌ FAILED: startPeriodic() did not enable tracking.');
      } else if (!fgDisabled) {
        _set(
          '❌ FAILED: active config lost the foreground-service opt-out '
          '(enabled=${config.android.foregroundService.enabled}, '
          'periodicUseForegroundService='
          '${config.android.periodicUseForegroundService}).',
        );
      } else {
        _set(
          '✅ Periodic tracking started with the foreground service disabled.\n'
          'Now BACKGROUND the app and wait for a periodic fetch: no '
          '"Tracelet — Tracking location in background" notification may '
          'appear — especially on Xiaomi/Samsung/Huawei/OnePlus/Oppo/Vivo, '
          'where the old code silently forced the service back on.\n'
          'Press Run again (or Stop on the dashboard) to stop.',
        );
      }
    } catch (e) {
      _set('❌ ERROR: $e');
    } finally {
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      title: 'Issue #243: periodic posts notification with FGS disabled',
      description:
          'Runs startPeriodic() with periodicUseForegroundService: false and '
          "foregroundService.enabled: false — the reporter's exact config. "
          'On aggressive OEMs the old native config layer silently forced '
          'both flags to true, posting the default foreground notification. '
          'Explicit config is now honored (WorkManager strategy, no service).',
      status: status,
      running: running,
      onRun: _test,
    );
  }
}
