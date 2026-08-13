import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #204 — `requestSyncBody` (the custom sync-body builder) must be invoked
/// exactly ONCE per batch. The bug caused two sync providers to fire
/// independently for the same batch, producing duplicate uploads.
///
/// This test registers a counting sync-body builder, seeds a couple of
/// locations, enables auto-sync with a short delay, and reports how many times
/// the builder was invoked for the batch. Expected: 1 invocation per batch.
class Issue204Card extends StatefulWidget {
  const Issue204Card({super.key});

  @override
  State<Issue204Card> createState() => _Issue204CardState();
}

class _Issue204CardState extends State<Issue204Card>
    with IssueCardRun<Issue204Card> {
  int _invocations = 0;

  void _setStatus(String text) => setStatus(text);

  @override
  IssueRunner? get cardRunner => _test;

  Future<void> _test() async {
    setRunning(running: true);
    setState(() => _invocations = 0);
    try {
      // Count every requestSyncBody invocation for ONE batch.
      await Tracelet.setSyncBodyBuilder((ctx) async {
        _invocations++;
        if (mounted) setState(() {});
        return {'records': ctx.locations};
      });

      // Deterministic, single-batch repro: no continuous tracking (which would
      // produce several legitimate batches), seed via insertLocation, then sync
      // ONCE. A correct SDK invokes the builder exactly once for the batch.
      _setStatus('Configuring (batch sync, no auto-sync)...');
      await Tracelet.ready(
        Config.passive().copyWith(
          http: const HttpConfig(
            url: 'https://httpbin.org/post',
            batchSync: true,
            autoSync: false,
          ),
          logger: const LoggerConfig(debug: true, logLevel: LogLevel.verbose),
        ),
      );

      _setStatus('Seeding 3 locations...');
      await Tracelet.destroyLocations();
      for (var i = 0; i < 3; i++) {
        await Tracelet.insertLocation({
          'uuid': 'issue-204-card-$i',
          'timestamp': DateTime.now().toIso8601String(),
          'latitude': 19.16 + i * 0.001,
          'longitude': 73.00 + i * 0.001,
          'accuracy': 10.0,
          'speed': 0.0,
          'heading': 0.0,
          'altitude': 0.0,
          'is_moving': true,
          'event': 'location',
        });
      }

      _setStatus('Syncing the batch once...');
      await Tracelet.sync();
      await Future<void>.delayed(const Duration(seconds: 2));

      await Tracelet.setSyncBodyBuilder(null);

      if (_invocations == 0) {
        _setStatus(
          '⚠️ No sync fired (check network/url). invocations = $_invocations',
        );
      } else if (_invocations == 1) {
        _setStatus(
          '✅ SUCCESS: requestSyncBody fired exactly once for the batch '
          '(invocations = $_invocations). No duplicate sync.',
        );
      } else {
        _setStatus(
          '❌ FAILED: requestSyncBody fired $_invocations times for the same '
          'batch — duplicate sync (Issue #204).',
        );
      }
    } catch (e) {
      _setStatus('❌ FAILED: $e');
    } finally {
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '#204: Duplicate requestSyncBody per batch',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Counts how many times the custom sync-body builder is invoked for '
              'one batch. Expected exactly 1 (duplicate providers would fire 2).',
            ),
            const SizedBox(height: 12),
            IssueStatusBox(
              // The count is repeated live while the test runs; the final
              // message names it too, which is the copy that survives a scroll.
              status: running
                  ? '$status\n\nrequestSyncBody invocations: $_invocations'
                  : status,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: running ? null : _test,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Run Test'),
            ),
          ],
        ),
      ),
    );
  }
}
