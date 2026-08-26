import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #415 — Activity detach could orphan the foreground-permission reply.
///
/// This card proves the public permission Future completes instead of waiting
/// forever. Its strongest run is a clean install where Android must display the
/// foreground-location dialog; when permission is already decided, it only
/// proves the synchronous status path. Activity detach itself is covered by the
/// native plugin lifecycle regression test.
class Issue415Card extends StatefulWidget {
  const Issue415Card({super.key});

  @override
  State<Issue415Card> createState() => _Issue415CardState();
}

class _Issue415CardState extends State<Issue415Card>
    with IssueCardRun<Issue415Card> {
  @override
  IssueRunner? get cardRunner => _run;

  Future<void> _run() async {
    setRunning(running: true);
    setStatus('Waiting for the Android location-permission result…');
    final stopwatch = Stopwatch()..start();

    try {
      // The shell's normal preparation is disabled so this card owns the
      // first permission request on a clean install.
      await Tracelet.ready(
        const Config(
          app: AppConfig(stopOnTerminate: true, startOnBoot: false),
          motion: MotionConfig(disableMotionActivityUpdates: true),
          http: HttpConfig(autoSync: false),
        ),
      );
      // Turn an orphaned Pigeon reply into an observable card failure.
      await Tracelet.requestLocationAuthorization().timeout(
        const Duration(seconds: 15),
      );
      final authorization = await Tracelet.getLocationAuthorization();
      stopwatch.stop();
      setStatus(
        '✅ PASS: the permission Future completed once in '
        '${stopwatch.elapsedMilliseconds} ms.\n\n'
        'Authorization: ${authorization.name}\n\n'
        'A clean-install run exercises the #415 failure path. If permission '
        'was already decided, this run proves only the synchronous path; the '
        'native detach regression test covers forced Activity detach.',
      );
    } catch (error) {
      stopwatch.stop();
      setStatus(
        '❌ FAILED: the permission request did not complete safely.\n\n'
        'Elapsed: ${stopwatch.elapsedMilliseconds} ms\n$error',
      );
    } finally {
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      title: '#415: permission reply orphaned on Activity detach',
      description:
          'Requests foreground location with a 15-second bound and proves the '
          'public Future completes. Run after a clean install for the strongest '
          'real-device evidence.',
      keywords:
          '415 android permission activity detach pigeon future pending callback '
          'requestLocationAuthorization clean install timeout',
      status: status,
      running: running,
      onRun: _run,
      prepare: false,
    );
  }
}
