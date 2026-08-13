import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

class Issue198Card extends StatefulWidget {
  const Issue198Card({super.key});

  @override
  State<Issue198Card> createState() => _Issue198CardState();
}

class _Issue198CardState extends State<Issue198Card>
    with IssueCardRun<Issue198Card> {
  bool _isTracking = false;
  StreamSubscription? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _setStatus(String text) => setStatus(text);

  // Start/stop tracking by hand: a sweep would leave the SDK tracking.
  @override
  IssueRunner? get cardRunner => null;

  Future<void> _start() async {
    _setStatus('Requesting permissions...');
    final authStatus = await Tracelet.requestLocationAuthorization();
    if (authStatus != AuthorizationStatus.always &&
        authStatus != AuthorizationStatus.whenInUse) {
      _setStatus('❌ FAILED: Permission denied');
      return;
    }

    _setStatus('Starting Tracelet with Issue 198 Config...');

    await Tracelet.ready(
      Config.passive().copyWith(
        app: const AppConfig(stopOnTerminate: false),
        logger: const LoggerConfig(debug: true, logLevel: LogLevel.verbose),
        ios: const IosConfig(
          useBackgroundActivitySession: true, // THE NEW FEATURE
        ),
      ),
    );

    _sub?.cancel();
    _sub = Tracelet.onLocation((loc) {
      _setStatus(
        '📍 Got location: ${loc.coords.latitude}, ${loc.coords.longitude}',
      );
    });

    final state = await Tracelet.start();
    setState(() {
      _isTracking = state.enabled;
    });

    if (state.enabled) {
      _setStatus(
        '✅ Tracking Started. Put app in background, you should see the Dynamic Island / Status Bar pill indicating active background session.',
      );
    }
  }

  Future<void> _stop() async {
    final state = await Tracelet.stop();
    setState(() {
      _isTracking = state.enabled;
    });
    _setStatus('🛑 Tracking Stopped.');
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
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '#198: Passive Profile Battery Optimization (iOS 17+)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Icon(
                  _isTracking ? Icons.gps_fixed : Icons.gps_not_fixed,
                  color: _isTracking ? Colors.green : Colors.grey,
                ),
              ],
            ),
            const SizedBox(height: 8),
            IssueStatusBox(status: status),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isTracking ? _stop : _start,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isTracking
                    ? Colors.red.shade600
                    : Colors.blue.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: Icon(_isTracking ? Icons.stop : Icons.play_arrow),
              label: Text(_isTracking ? 'STOP TRACKING' : 'START TRACKING'),
            ),
          ],
        ),
      ),
    );
  }
}
