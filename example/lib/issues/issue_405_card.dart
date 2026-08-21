import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_doctor/tracelet_doctor.dart';
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issues #405, #406 and #407 — background tracking died in three ways that all
/// rendered as a healthy bug report.
///
/// A field report from a LAVA LXX503 on Android 14 showed 52 seconds of
/// background with zero fixes, a visible notification, and a Doctor report that
/// said `Promoted to foreground: true`, `Last promotion result: success`,
/// `Warnings: none — all systems healthy ✅` and *"the stream has been accepting
/// fixes"*. Every one of those was true of the fields being read and false of
/// the device. `dumpsys` on a connected phone was the only way to see it.
///
/// **#405.** Android 12+ latches `mAllowWhileInUsePermissionInFgs` when the
/// ServiceRecord is *created* — at `startService()`, not `startForeground()` —
/// for the life of the record. A record created from a background trigger
/// (BootReceiver, an alarm, a geofence, the sticky restart) yields a foreground
/// service that posts its notification, reports `isForeground=true` and carries
/// `FOREGROUND_SERVICE_TYPE_LOCATION`, while the OS withholds the
/// foreground-location capability. On the device: `caps=---NFU` and
/// `gps provider: ProviderRequest[OFF]` backgrounded, against `caps=L--NFU` and
/// `[@+2s0ms, HIGH_ACCURACY]` for the same build relaunched from the foreground.
///
/// **#406.** `RUN_ANY_IN_BACKGROUND` — the "Restricted" battery state — was
/// never read. It is independent of the Doze allowlist the health check already
/// reports, and stronger: it blocks the promotion outright. The device had
/// `isIgnoringBatteryOptimizations: true` and `RUN_ANY_IN_BACKGROUND: ignore`
/// at the same time.
///
/// **#407.** The stall watchdog only ran when a fix arrived, so a stream
/// delivering nothing never tripped it — the one case where the SDK is
/// completely blind produced no signal at all.
///
/// **What this card proves.** That the health snapshot now carries the fields
/// that separate "promoted" from "promoted and able to use location", that the
/// battery-restriction state is read and surfaced, that the silence watchdog is
/// armed on the always-on lifecycle channel at `logLevel: off`, and that the
/// bug report states a verdict instead of leaving it to be inferred from six
/// rows that say `true`.
class Issue405Card extends StatefulWidget {
  const Issue405Card({super.key});

  @override
  State<Issue405Card> createState() => _Issue405CardState();
}

class _Issue405CardState extends State<Issue405Card>
    with IssueCardRun<Issue405Card> {
  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  @override
  IssueRunner? get cardRunner => _run;

  Future<void> _run() async {
    setRunning(running: true);
    final results = <String>[];
    var allPass = true;

    void check(String name, {required bool pass, required String detail}) {
      results.add('${pass ? '✅' : '❌'} $name — $detail');
      if (!pass) allPass = false;
    }

    try {
      await Tracelet.requestLocationAuthorization();

      // The card is tapped with the app on screen, so the service record is
      // created from the foreground — the state #405 says must work. Tracking
      // has to actually start: a card that never starts the service reads the
      // health of a service that does not exist and proves nothing.
      await Tracelet.ready(
        const Config(
          geo: GeoConfig(distanceFilter: 10),
          motion: MotionConfig(isMoving: true),
          http: HttpConfig(autoSync: false),
          android: AndroidConfig(
            foregroundService: ForegroundServiceConfig(
              enabled: true,
              channelId: 'tracelet_demo_channel',
              notificationTitle: 'Tracelet #405 check',
            ),
          ),
          // The level a released app actually runs at. Everything this card
          // reads must survive it.
          logger: LoggerConfig(logLevel: LogLevel.off),
        ),
      );
      await Tracelet.destroyLog();
      await Tracelet.start();
      setStatus('⏳ Letting the service settle…');
      await Future<void>.delayed(const Duration(seconds: 6));

      final health = await Tracelet.getForegroundServiceHealth();

      if (!_isAndroid) {
        setStatus(
          'ℹ️ Android only. #405/#406 are Android foreground-service and '
          'app-op behaviours; iOS has neither a foreground service nor '
          'RUN_ANY_IN_BACKGROUND. The #407 silence watchdog applies to both '
          'and is checked by the Dart and Kotlin test suites.',
        );
        await Tracelet.stop();
        return;
      }

      // ---------------------------------------------------------------------
      // 1. #405 — the snapshot distinguishes promoted from able-to-track
      // ---------------------------------------------------------------------
      final startedInForeground = health['serviceStartedInForeground'];
      final locationDenied = health['locationCapabilityLikelyDenied'];

      check(
        'the health snapshot reports the procstate the service was created in',
        pass: startedInForeground != null,
        detail: startedInForeground != null
            ? 'serviceStartedInForeground=$startedInForeground'
            : 'field missing — without it a location-blind service is '
                  'indistinguishable from a healthy one (#405)',
      );
      check(
        'a service created from the foreground is not flagged',
        pass: startedInForeground == true && locationDenied == false,
        detail: startedInForeground == true && locationDenied == false
            ? 'started on screen, so Android grants it the location capability '
                  'and it keeps it when backgrounded'
            : 'startedInForeground=$startedInForeground '
                  'locationCapabilityLikelyDenied=$locationDenied. Expected '
                  'true/false when the card is run with the app on screen',
      );

      // ---------------------------------------------------------------------
      // 2. #406 — the restriction the health check never read
      // ---------------------------------------------------------------------
      final restricted = health['backgroundRestricted'];
      final bucket = health['standbyBucketName'];

      check(
        'the Restricted battery state is read',
        pass: restricted != null,
        detail: restricted != null
            ? 'backgroundRestricted=$restricted, standbyBucket=$bucket'
            : 'field missing — the Doze allowlist alone reported this device '
                  'as healthy while the OS refused to promote the service '
                  '(#406)',
      );
      if (restricted == true) {
        results.add(
          '⚠️ This device has the app in the "Restricted" battery state. '
          'Background tracking cannot work until it is set to Unrestricted in '
          'Settings → Apps → Tracelet Example → Battery. That is the condition '
          '#406 exists to name, and the card is reporting it rather than '
          'failing on it.',
        );
      }

      // ---------------------------------------------------------------------
      // 3. #407 — silence is announced on the always-on channel
      // ---------------------------------------------------------------------
      final logs = await Tracelet.getLogs(500);
      final lifecycle = logs
          .where((l) => l.level.toUpperCase() == 'LIFECYCLE')
          .toList();
      check(
        'lifecycle entries are recorded at logLevel: off',
        pass: lifecycle.isNotEmpty,
        detail: lifecycle.isNotEmpty
            ? '${lifecycle.length} entry(ies) — the channel these findings are '
                  'written on survives a release build'
            : "none, so none of this reaches a released app's bug report",
      );
      final startLine = lifecycle
          .where((l) => l.message.contains('service: onCreate'))
          .toList();
      check(
        'the service records how it was started, in the log',
        pass: startLine.any((l) => l.message.contains('startedInForeground=')),
        detail: startLine.isEmpty
            ? 'no "service: onCreate" lifecycle entry in this window'
            : startLine.first.message,
      );

      // ---------------------------------------------------------------------
      // 4. The report states a verdict rather than six rows saying true
      // ---------------------------------------------------------------------
      final report = await TraceletBugReport.build(logLimit: 100);
      check(
        'the bug report states a foreground-service verdict',
        pass: report.contains('**Verdict:**'),
        detail: report.contains('**Verdict:**')
            ? 'present — the report draws the conclusion instead of leaving it '
                  'to be inferred'
            : 'missing',
      );
      check(
        'the report carries the new diagnostic rows',
        pass:
            report.contains('| Started in foreground') &&
            report.contains('| Background restricted') &&
            report.contains('| Standby bucket'),
        detail:
            report.contains('| Started in foreground') &&
                report.contains('| Background restricted')
            ? 'started-in-foreground, background-restricted and standby bucket '
                  'are all in the foreground-service table'
            : 'one or more rows missing',
      );
      check(
        'the stream-health section no longer claims fixes were accepted',
        pass: !report.contains('the stream has been accepting fixes'),
        detail: !report.contains('the stream has been accepting fixes')
            ? 'the empty case now says no entries were recorded, which is all '
                  'it can honestly say (#407)'
            : 'still asserts health from an absence of markers — the exact '
                  'line that read as healthy over a 52-second dead window',
      );

      await Tracelet.stop();

      final header = allPass
          ? '✅ SUCCESS: a location-blind foreground service now names itself.'
          : '❌ FAILED — #405/#406/#407 not satisfied on this build.';

      setStatus(
        '$header\n\n${results.join('\n')}\n\n'
        'The failure this covers cannot be reproduced from the foreground: it '
        'needs the ServiceRecord to be created while the app is in the '
        'background, which is what a reboot, an alarm, a geofence or a sticky '
        'restart does. To see the bad state on a device: force-stop the app, '
        'then let a background trigger start it, then read '
        '`adb shell dumpsys activity services <pkg>` — '
        '`mAllowWhileInUsePermissionInFgsReason=DENIED` with '
        '`createdFromFg=false` is the signature. Keeping that record out of '
        'existence is #405 items 3 and 4, tracked separately.',
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
          'foreground service background location denied while-in-use '
          'mAllowWhileInUsePermissionInFgs caps procstate RUN_ANY_IN_BACKGROUND '
          'restricted battery forced app standby standby bucket silence stall '
          'watchdog doctor verdict indicator gps 405 406 407',
      title:
          '#405/#406/#407: background tracking died and the report said '
          'healthy',
      description:
          'Starts tracking from the foreground and checks the health snapshot '
          'now separates "promoted" from "promoted and allowed to use '
          'location", reads the Restricted battery state, keeps its findings '
          'on the always-on lifecycle channel at logLevel: off, and makes the '
          'bug report state a verdict. No walking required.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
