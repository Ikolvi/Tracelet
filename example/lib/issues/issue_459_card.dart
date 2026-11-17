import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

class Issue459Card extends StatefulWidget {
  const Issue459Card({super.key});

  @override
  State<Issue459Card> createState() => _Issue459CardState();
}

class _Issue459CardState extends State<Issue459Card>
    with IssueCardRun<Issue459Card> {
  static const _debug = MethodChannel('com.tracelet/debug');

  @override
  IssueRunner? get cardRunner => _run;

  Future<void> _run() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      setStatus('Android probe. iOS exercises the same inputs in XCTest.');
      return;
    }
    setRunning(running: true);
    try {
      final speeds = await _debug.invokeMapMethod<String, List<Object?>>(
        'debugIssue459ReportedSpeed',
      );
      final raw = speeds?['raw'];
      final pace = speeds?['pace'];
      bool matches(List<Object?>? samples) =>
          samples != null &&
          samples.length == 3 &&
          samples[1] == 0 &&
          samples[2] is num &&
          ((samples[2]! as num) - 3).abs() < 0.1;
      final pass = matches(raw) && matches(pace);
      setStatus(
        '${pass ? 'PASS' : 'FAIL'} — expected [anchor, 0, ~3] m/s.\n'
        'Raw classifier input: $raw\n'
        'Pace input: $pace',
      );
    } on PlatformException catch (error, stack) {
      debugPrint('Issue #459 running the native speed probe: $error\n$stack');
      setStatus('Could not run the native speed probe. $error');
    } finally {
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) => IssueCardShell(
    title: '#459 — Preserve a measured stop',
    description:
        'Sends three synthetic fixes through the Android location engine. '
        'With the same coordinate drift, a measured stop should feed '
        '0 m/s to motion detection and a missing speed should use the '
        'position estimate. No GPS movement is required.',
    status: status,
    running: running,
    onRun: _run,
  );
}
