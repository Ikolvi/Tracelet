import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #436 — after a background restart, opening the app did not recover
/// location.
///
/// Android grants a foreground service location only if its record was created
/// from the foreground, for the record's whole life (#405). A START_STICKY
/// restart after a low-memory kill creates it in the background. Opening the
/// app then sent `start` to that same record, so the notification stayed up
/// and no fix arrived.
///
/// **What this card checks**: with the app open, the running service reports
/// `serviceStartedInForeground: true` after `start()`. That is the state a
/// background restart breaks and this fix restores. To reproduce the restart
/// itself: start tracking, background the app, `adb shell am kill <pkg>`, wait
/// for the sticky restart, then reopen the app and run this card.
class Issue436Card extends StatefulWidget {
  const Issue436Card({super.key});

  @override
  State<Issue436Card> createState() => _Issue436CardState();
}

class _Issue436CardState extends State<Issue436Card>
    with IssueCardRun<Issue436Card> {
  @override
  IssueRunner? get cardRunner => _run;

  Future<void> _run() async {
    if (!Platform.isAndroid) {
      setStatus(
        'ℹ️ Android only — iOS has no foreground-service location rule.',
      );
      return;
    }
    setRunning(running: true);
    try {
      await Tracelet.requestLocationAuthorization();
      await Tracelet.ready(
        const Config(app: AppConfig(stopOnTerminate: false)),
      );
      await Tracelet.start();
      await Future<void>.delayed(const Duration(seconds: 2));
      final health = await Tracelet.getForegroundServiceHealth();
      final fg = health['serviceStartedInForeground'];
      setStatus(
        fg == true
            ? '✅ SUCCESS: the running service was created from the foreground, '
                  'so Android grants it location.'
            : '❌ FAILED — serviceStartedInForeground=$fg with the app open: the '
                  'service is location-blind (#436).',
      );
    } catch (e) {
      setStatus('❌ FAILED: $e');
    } finally {
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'low memory kill sticky restart foreground service location denied '
          'background started reopen recover 436 405',
      title: '#436: reopening the app recovers location',
      description:
          'A background-restarted foreground service is denied location, and '
          'opening the app reused it. Checks the service was created from the '
          'foreground. Leaves tracking running.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
