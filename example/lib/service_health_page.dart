import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:tracelet/tracelet.dart' as tl;

/// Demo page for `Tracelet.getForegroundServiceHealth()` (issue #255).
///
/// `Tracelet.getState().enabled` is the *desired* tracking state — but on
/// Android 12+ a foreground-service start can be deferred or rejected by the OS
/// even while `enabled == true`, so it is not proof that background tracking is
/// actually operational. This page surfaces the *authoritative* native
/// foreground-service state (service running / promoted, and the last
/// promotion result — `success` / `deferred` / `failed` — with the failure
/// class + message) so you can build tracking-health indicators, diagnostics,
/// and recovery behavior.
///
/// Android reports live data; iOS has no foreground service (the promotion
/// fields are null/false); web returns a minimal disabled map.
class ServiceHealthPage extends StatefulWidget {
  const ServiceHealthPage({super.key});

  @override
  State<ServiceHealthPage> createState() => _ServiceHealthPageState();
}

class _ServiceHealthPageState extends State<ServiceHealthPage> {
  bool _busy = false;
  bool _tracking = false;
  Map<String, Object?> _health = const {};
  String? _error;
  Timer? _pollTimer;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  /// Ensures the SDK is initialized so the buttons work even if the user opened
  /// this page before pressing Initialize on the main screen. Non-clobbering:
  /// re-applies the active config, falling back to ready() only if NOT_READY.
  Future<void> _ensureReady() async {
    try {
      await tl.Tracelet.setConfig(tl.Tracelet.activeConfig);
    } on PlatformException catch (e) {
      if (e.code == 'NOT_READY') {
        await tl.Tracelet.ready(tl.Tracelet.activeConfig);
      } else {
        rethrow;
      }
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final health = await tl.Tracelet.getForegroundServiceHealth();
      if (mounted) setState(() => _health = health);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startTracking() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await tl.Tracelet.requestLocationAuthorization();
      await _ensureReady();
      final state = await tl.Tracelet.start();
      if (mounted) setState(() => _tracking = state.enabled);
      await _refresh();
      // Poll briefly so the promotion result (which lands a beat after the
      // service is dispatched) shows up without a manual refresh.
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (t) {
        if (!mounted || t.tick > 5) {
          t.cancel();
          return;
        }
        _refresh();
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopTracking() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final state = await tl.Tracelet.stop();
      if (mounted) setState(() => _tracking = state.enabled);
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Interprets the health map into a one-line human verdict.
  ({String text, Color color, IconData icon}) _verdict() {
    if (_health.isEmpty) {
      return (
        text: 'No data yet — tap Refresh.',
        color: Colors.grey,
        icon: Icons.help_outline,
      );
    }
    final desired = _health['desiredEnabled'] == true;
    final fgEnabled = _health['foregroundServiceEnabled'] == true;
    final foreground = _health['serviceForeground'] == true;
    final result = _health['lastForegroundPromotionResult'] as String?;

    if (!desired) {
      return (
        text: 'Tracking disabled (desiredEnabled = false).',
        color: Colors.grey,
        icon: Icons.pause_circle,
      );
    }
    if (!fgEnabled) {
      return (
        text: 'Tracking enabled without a foreground service.',
        color: Colors.blueGrey,
        icon: Icons.info_outline,
      );
    }
    if (foreground) {
      return (
        text: 'Healthy — foreground service is running and promoted.',
        color: Colors.green,
        icon: Icons.check_circle,
      );
    }
    if (result == 'deferred') {
      return (
        text:
            'Foreground promotion DEFERRED — will retry when app is foregrounded.',
        color: Colors.orange,
        icon: Icons.hourglass_bottom,
      );
    }
    if (result == 'failed') {
      return (
        text:
            'Foreground promotion FAILED — background tracking is NOT operational.',
        color: Colors.red,
        icon: Icons.error,
      );
    }
    return (
      text: 'Tracking requested but foreground service not confirmed yet.',
      color: Colors.orange,
      icon: Icons.sync_problem,
    );
  }

  @override
  Widget build(BuildContext context) {
    final verdict = _verdict();
    return Scaffold(
      appBar: AppBar(title: const Text('Foreground Service Health')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'getForegroundServiceHealth() (#255)',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'getState().enabled is the DESIRED tracking state. On Android 12+ a '
            'foreground-service start can be deferred or rejected even while '
            'enabled = true, so it does not prove background tracking is '
            'operational. This API exposes the ACTUAL native service state and '
            'the last promotion result. iOS has no foreground service; web '
            'returns a minimal map.',
          ),
          const SizedBox(height: 16),
          Card(
            color: verdict.color.withValues(alpha: 0.1),
            child: ListTile(
              leading: Icon(verdict.icon, color: verdict.color),
              title: Text(
                verdict.text,
                style: TextStyle(
                  color: verdict.color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
              FilledButton.icon(
                onPressed: _busy || _tracking ? null : _startTracking,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start (foreground service)'),
              ),
              FilledButton.icon(
                onPressed: _busy || !_tracking ? null : _stopTracking,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
            ],
          ),
          if (kIsWeb)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Web has no foreground service — values are placeholders.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text('Error: $_error', style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          const Text(
            'Raw health map',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Text(
              _health.isEmpty
                  ? '(empty)'
                  : _health.entries
                        .map((e) => '${e.key}: ${e.value}')
                        .join('\n'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
