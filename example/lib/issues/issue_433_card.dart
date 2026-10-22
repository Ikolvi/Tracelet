import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #433 — on Android 10+, crash/fall detection got no accelerometer
/// samples unless ACTIVITY_RECOGNITION was granted, even with
/// `disableMotionActivityUpdates: true`, the mode documented as needing no
/// permissions.
///
/// Impact samples come from `MotionDetector`'s accelerometer, which needs no
/// runtime permission. `TraceletSdk.start()` nevertheless started the detector
/// only once ACTIVITY_RECOGNITION was granted: it asked for the permission and
/// returned, so a denied prompt, or a background start with no activity to ask
/// from, left impact detection, gyro/barometer corroboration and motion
/// detection off for the whole session. The boot paths had the same gate. And
/// nothing told the host.
///
/// The detector now always starts. Only the activity transitions need the
/// permission: full mode skips them and says so on the always-on channel, and
/// registers them if the grant arrives later. Accelerometer-only mode no longer
/// asks for the permission at all.
///
/// **What this card proves** — only when ACTIVITY_RECOGNITION is *not* granted,
/// because with it the detector always started: the detector's own start line
/// appears in the log in accelerometer-only mode and in full mode, and full
/// mode records that activity transitions are unavailable. With the permission
/// granted it says so and claims nothing. Impact detection itself needs a real
/// impact and is not exercised here.
class Issue433Card extends StatefulWidget {
  const Issue433Card({super.key});

  @override
  State<Issue433Card> createState() => _Issue433CardState();
}

class _Issue433CardState extends State<Issue433Card>
    with IssueCardRun<Issue433Card> {
  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  @override
  IssueRunner? get cardRunner => _run;

  static const _accelOnlyStart = 'startAccelerometerOnlyMode()';
  static const _fullStart = 'startFullMode()';
  static const _transitionsUnavailable = 'activity transitions unavailable';

  Future<List<LogEntry>> _startAndCollect({required bool accelOnly}) async {
    await Tracelet.ready(
      Config(
        motion: MotionConfig(
          isMoving: true,
          disableMotionActivityUpdates: accelOnly,
        ),
        http: const HttpConfig(autoSync: false),
        // The detector's start lines are debug lines.
        logger: const LoggerConfig(logLevel: LogLevel.debug),
      ),
    );
    await Tracelet.destroyLog();
    await Tracelet.start();
    await Future<void>.delayed(const Duration(seconds: 3));
    final logs = await Tracelet.getLogs(500);
    await Tracelet.stop();
    return logs;
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
          'ℹ️ Android only. iOS reads the accelerometer through CoreMotion, '
          'which needs no motion permission for raw samples.',
        );
        return;
      }

      final motionAuth = await Tracelet.getMotionAuthorization();
      if (motionAuth == MotionAuthorizationStatus.granted) {
        setStatus(
          'ℹ️ Not verified — Physical activity is granted on this device (or '
          'it runs Android 9 or lower), and with it the detector always '
          'started. Revoke it in Settings → Apps → this app → Permissions → '
          'Physical activity, then run again.',
        );
        return;
      }

      setStatus('⏳ Accelerometer-only mode, without ACTIVITY_RECOGNITION…');
      final accelOnly = await _startAndCollect(accelOnly: true);
      final accelStarted = accelOnly.any(
        (l) => l.message.contains(_accelOnlyStart),
      );
      check(
        'accelerometer-only: the motion detector starts',
        pass: accelStarted,
        detail: accelStarted
            ? '"$_accelOnlyStart" logged — impact detection has samples'
            : 'no detector start line — the accelerometer is off for the '
                  'session (the bug)',
      );

      setStatus('⏳ Full mode, without ACTIVITY_RECOGNITION…');
      final full = await _startAndCollect(accelOnly: false);
      final fullStarted = full.any((l) => l.message.contains(_fullStart));
      final unavailable = full
          .where((l) => l.message.contains(_transitionsUnavailable))
          .map((l) => l.message)
          .toList();
      check(
        'full mode: the motion detector still starts',
        pass: fullStarted,
        detail: fullStarted
            ? '"$_fullStart" logged'
            : 'no detector start line — start() waited on the permission',
      );
      check(
        'full mode records that activity transitions are unavailable',
        pass: unavailable.isNotEmpty,
        detail: unavailable.isNotEmpty
            ? unavailable.first
            : 'no line — a reader could not tell why there is no activity type',
      );

      final header = allPass
          ? '✅ SUCCESS: the detector runs without ACTIVITY_RECOGNITION.'
          : '❌ FAILED — #433 not satisfied on this build.';
      setStatus(
        '$header\n\n${results.join('\n')}\n\n'
        'Motion permission during this run: ${motionAuth.name}. Full mode may '
        'have shown the permission prompt; denying it is the case this card '
        'is for. Before the fix, neither start produced a detector start line, '
        'and crash/fall detection received no samples for the whole session.',
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
          'android crash fall impact detection accelerometer activity '
          'recognition permission physical activity disableMotionActivityUpdates '
          'motion detector 433',
      title: '#433: impact detection works without ACTIVITY_RECOGNITION',
      description:
          'start() only started the motion detector, the accelerometer that '
          'feeds crash/fall detection, once ACTIVITY_RECOGNITION was granted, '
          'even in accelerometer-only mode. Starts in both modes without the '
          'permission and checks the detector came up.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
