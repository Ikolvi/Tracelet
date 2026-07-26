import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;

/// Issue #201 — Local extras passed to `getCurrentPosition(extras: ...)` must
/// survive into the location payload alongside the globally-configured
/// `HttpConfig.extras`.
///
/// The test configures a GLOBAL extra (`device_id`) and then requests a single
/// position with a LOCAL extra (`event_type: sos`). The returned location's
/// `extras` should contain BOTH keys (local merged on top of global), proving
/// the per-call extras are no longer dropped.
class Issue201Card extends StatefulWidget {
  const Issue201Card({super.key});

  @override
  State<Issue201Card> createState() => _Issue201CardState();
}

class _Issue201CardState extends State<Issue201Card> {
  String _status = 'Idle';
  bool _running = false;

  void _setStatus(String text) {
    if (mounted) setState(() => _status = text);
  }

  Future<void> _test() async {
    setState(() => _running = true);
    try {
      _setStatus('Requesting permissions...');
      final auth = await Tracelet.requestLocationAuthorization();
      if (auth != AuthorizationStatus.always &&
          auth != AuthorizationStatus.whenInUse) {
        _setStatus('❌ FAILED: Permission denied');
        return;
      }

      _setStatus('Configuring with GLOBAL extras {device_id}...');
      await Tracelet.ready(
        Config.passive().copyWith(
          http: const HttpConfig(
            // autoSync off — this test inspects the persisted location locally,
            // it does not need a server.
            autoSync: false,
            extras: {'device_id': 'global-123'},
          ),
          logger: const LoggerConfig(debug: true, logLevel: LogLevel.verbose),
        ),
      );

      _setStatus(
        'Calling getCurrentPosition with LOCAL extras {event_type}...',
      );
      final loc = await Tracelet.getCurrentPosition(
        persist: true,
        samples: 1,
        extras: const {'event_type': 'sos'},
      );

      final extras = loc.extras;
      final hasLocal = extras['event_type'] == 'sos';
      final hasGlobal = extras['device_id'] == 'global-123';

      if (hasLocal && hasGlobal) {
        _setStatus(
          '✅ SUCCESS: both local + global extras present.\nextras = $extras',
        );
      } else if (hasLocal) {
        _setStatus(
          '⚠️ Local extra present but global missing.\nextras = $extras',
        );
      } else {
        _setStatus(
          '❌ FAILED: local extra "event_type" missing from payload.\nextras = $extras',
        );
      }
    } catch (e) {
      _setStatus('❌ FAILED: $e');
    } finally {
      if (mounted) setState(() => _running = false);
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
              '#201: Local extras from getCurrentPosition',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Verifies per-call extras passed to getCurrentPosition are merged '
              'with global HttpConfig.extras instead of being dropped.',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Text(
                _status,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _running ? null : _test,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Run Test'),
            ),
          ],
        ),
      ),
    );
  }
}
