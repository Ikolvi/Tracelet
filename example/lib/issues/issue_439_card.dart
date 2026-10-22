import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #439 — a `prod` crash-model license never unlocked, on Android or
/// iOS: `401 missing_integrity_token` without a token, `401
/// attestation_unconfigured` with one. Every shipped app needed a hand-issued
/// key.
///
/// The prod gate was a device attestation that could not complete for a
/// third-party app: the SDK never supplied a token, and one the host app
/// requested could not be verified by the license server. iOS had no path at
/// all. Prod licenses are now bound to the app instead — the SDK reports its
/// platform, application id and (on Android) signing-cert SHA-256 on unlock,
/// and the server refuses a license issued for a different app.
///
/// **What this card proves:** that the crash model unlocks with the identity
/// the SDK now reports, using the example app's own key (bound to
/// `com.ikolvi.tracelet.example` on both platforms). A server that refused the
/// reported identity would answer `pkg_mismatch` or `cert_mismatch` here. The
/// prod-tier server rules (unlock with no token, refusal for another app) are
/// covered by the license server's own tests, not by this card — it holds no
/// prod key.
class Issue439Card extends StatefulWidget {
  const Issue439Card({super.key});

  @override
  State<Issue439Card> createState() => _Issue439CardState();
}

class _Issue439CardState extends State<Issue439Card>
    with IssueCardRun<Issue439Card> {
  @override
  IssueRunner? get cardRunner => _run;

  // The same key and endpoint as the Behavior page (behavior_page.dart);
  // the key expires 2027-10-22.
  static const _unlockUrl = 'https://unlock.ikolvi.com/unlock';
  static const _exampleLicenseKey =
      'eyJleHAiOjE4MjQxOTk3OTYsImlhdCI6MTc5MjY2Mzc5NiwibGljIjoiM2Q0NTdmYTctNDc2NC00Yjk4LTk5YzgtNDEwMmExYzk5ZjliIiwicGtnIjoiY29tLmlrb2x2aS50cmFjZWxldC5leGFtcGxlIiwicGxhbiI6InBybyIsInNjb3BlIjoiZGV2In0.99MzdeKRNEGs_Stwt1B_7zik_BjO2EsFfABUy_v5oLdwXNjDMV64D6A-izguoXqlfBFBacE02hVnx7qZyCNTCg';

  static const _unlocked = 'crash model: unlocked (';
  static const _bindingErrors = ['pkg_mismatch', 'cert_mismatch'];

  Future<void> _run() async {
    setRunning(running: true);
    final results = <String>[];
    var allPass = true;
    StreamSubscription<CrashModelStatusEvent>? sub;

    void check(String name, {required bool pass, required String detail}) {
      results.add('${pass ? '✅' : '❌'} $name — $detail');
      if (!pass) allPass = false;
    }

    try {
      final outcome = Completer<CrashModelStatusEvent>();
      sub = Tracelet.crashModelStatusStream.listen((e) {
        if (outcome.isCompleted) return;
        if (e.status == CrashModelStatus.ready ||
            e.status == CrashModelStatus.failed ||
            e.status == CrashModelStatus.disabled) {
          outcome.complete(e);
        }
      });

      await Tracelet.ready(
        const Config(
          // The unlock lines are debug lines.
          logger: LoggerConfig(logLevel: LogLevel.debug),
          http: HttpConfig(autoSync: false),
          impact: ImpactConfig(
            enableCrashDetection: true,
            crashModelUnlockUrl: _unlockUrl,
            crashModelLicenseKey: _exampleLicenseKey,
          ),
        ),
      );
      await Tracelet.destroyLog();
      setStatus('⏳ Unlocking the crash model (needs network)…');
      await Tracelet.start();

      final event = await outcome.future.timeout(
        const Duration(seconds: 90),
        onTimeout: () => const CrashModelStatusEvent(
          status: CrashModelStatus.unknown,
          detail: 'no ready/failed status within 90 s',
        ),
      );
      final logs = await Tracelet.getLogs(500);
      await Tracelet.stop();

      final unlockedLine = logs
          .where((l) => l.message.contains(_unlocked))
          .map((l) => l.message)
          .toList();
      final bindingRefusals = logs
          .where((l) => _bindingErrors.any(l.message.contains))
          .map((l) => l.message)
          .toList();

      check(
        'the license server accepts the identity the SDK reports',
        pass: bindingRefusals.isEmpty,
        detail: bindingRefusals.isEmpty
            ? 'no pkg_mismatch / cert_mismatch'
            : bindingRefusals.first,
      );
      check(
        'the crash model unlocked',
        pass: unlockedLine.isNotEmpty,
        detail: unlockedLine.isNotEmpty
            ? unlockedLine.first
            : 'no unlock line — check the network; the SDK falls back to '
                  'the rule engine',
      );
      check(
        'the model reached ready',
        pass: event.status == CrashModelStatus.ready,
        detail:
            'status=${event.status.name}'
            '${event.detail == null ? '' : ' (${event.detail})'}',
      );

      final header = allPass
          ? '✅ SUCCESS: the model unlocks with the app identity reported.'
          : '❌ FAILED — #439 not satisfied on this build.';
      setStatus(
        '$header\n\n${results.join('\n')}\n\n'
        'A prod key from the portal now unlocks a shipped app the same way, '
        'with no integrity token and no hand-issued key. The server-side '
        'rules are tested in the license server, not here.',
      );
    } catch (e) {
      setStatus('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      await sub?.cancel();
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'crash model license prod key unlock missing_integrity_token '
          'attestation_unconfigured play integrity app attest ml 439 183',
      title: '#439: prod crash-model licenses unlock',
      description:
          'A prod license required a device attestation that could never '
          'complete for a customer app, so it always failed with '
          'missing_integrity_token / attestation_unconfigured. Licenses are now '
          'bound to the app id (and Android signing cert) the SDK reports. '
          'Unlocks the example key and checks the server accepted it.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
