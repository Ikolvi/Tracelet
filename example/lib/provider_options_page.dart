import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:tracelet/tracelet.dart' as tl;

/// Demo page for `Tracelet.updateLocationProviderOptions()` (PR #241).
///
/// Temporarily overrides the active OS provider's `desiredAccuracy` and
/// `distanceFilter` without restarting the tracking pipeline — unlike
/// `setConfig`, which persists and does a clean full-pipeline restart when
/// tracking-relevant keys change. The override is ephemeral: it never touches
/// the persisted config or the accepted-point filter, and it is cleared by
/// `stop()`. Currently live on iOS only; Android and web return `false`.
class ProviderOptionsPage extends StatefulWidget {
  const ProviderOptionsPage({super.key});

  @override
  State<ProviderOptionsPage> createState() => _ProviderOptionsPageState();
}

class _ProviderOptionsPageState extends State<ProviderOptionsPage> {
  bool _ready = false;
  bool _tracking = false;
  bool _busy = false;

  /// null ⇒ keep the configured value.
  tl.DesiredAccuracy? _accuracy;
  final TextEditingController _filterCtrl = TextEditingController();

  final List<String> _log = [];
  StreamSubscription<tl.Location>? _locationSub;
  int _fixCount = 0;

  @override
  void initState() {
    super.initState();
    _locationSub = tl.Tracelet.onLocation((loc) {
      _fixCount++;
      final acc = loc.coords.accuracy.toStringAsFixed(1);
      _logLine('fix #$_fixCount  accuracy ${acc}m');
    });
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _filterCtrl.dispose();
    super.dispose();
  }

  void _logLine(String s) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, '${TimeOfDay.now().format(context)}  $s');
      if (_log.length > 40) _log.removeLast();
    });
  }

  /// Ensures the SDK is initialized so the buttons work even if the user
  /// opened this page before pressing Initialize on the main screen.
  /// (Same non-clobbering pattern as BehaviorPage.)
  Future<void> _ensureReady() async {
    if (_ready) return;
    try {
      await tl.Tracelet.setConfig(tl.Tracelet.activeConfig);
    } on PlatformException catch (e) {
      if (e.code == 'NOT_READY') {
        await tl.Tracelet.ready(tl.Tracelet.activeConfig);
      } else {
        rethrow;
      }
    }
    _ready = true;
  }

  Future<void> _run(String label, Future<void> Function() body) async {
    setState(() => _busy = true);
    try {
      await _ensureReady();
      await body();
    } on Object catch (e) {
      _logLine('$label failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() => _run('start', () async {
    final state = await tl.Tracelet.start();
    setState(() => _tracking = state.enabled);
    _logLine('start → enabled=${state.enabled}');
  });

  Future<void> _stop() => _run('stop', () async {
    final state = await tl.Tracelet.stop();
    setState(() => _tracking = state.enabled);
    _logLine('stop → enabled=${state.enabled} (override cleared)');
  });

  Future<void> _apply({tl.DesiredAccuracy? accuracy, double? filter}) =>
      _run('updateLocationProviderOptions', () async {
        final ok = await tl.Tracelet.updateLocationProviderOptions(
          desiredAccuracy: accuracy,
          distanceFilter: filter,
        );
        final args = [
          if (accuracy != null) 'accuracy=${accuracy.name}',
          if (filter != null) 'filter=${filter}m',
        ];
        final desc = args.isEmpty ? 'restore configured' : args.join(', ');
        _logLine('override($desc) → $ok');
        if (!ok) {
          _logLine(
            _tracking
                ? 'returned false — periodic mode active or platform '
                      'has no live provider updates (iOS only)'
                : 'returned false — start continuous tracking first',
          );
        }
      });

  Future<void> _applyFromForm() {
    final text = _filterCtrl.text.trim();
    final filter = text.isEmpty ? null : double.tryParse(text);
    if (text.isNotEmpty && (filter == null || filter < 0)) {
      _logLine('invalid distance filter "$text" — must be a number ≥ 0');
      return Future.value();
    }
    return _apply(accuracy: _accuracy, filter: filter);
  }

  @override
  Widget build(BuildContext context) {
    final geo = tl.Tracelet.activeConfig.geo;
    final liveSupported = !kIsWeb && Platform.isIOS;

    return Scaffold(
      appBar: AppBar(title: const Text('Live Provider Options')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Overrides the running location provider without a pipeline '
            'restart. Persisted config stays '
            '${geo.desiredAccuracy.name}/${geo.distanceFilter}m; stop() '
            'clears the override.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (!liveSupported)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Live updates are iOS-only for now — this platform always '
                'returns false.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),

          // ── Tracking control ──
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy || _tracking ? null : _start,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Tracking'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy || !_tracking ? null : _stop,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Override form ──
          DropdownButtonFormField<tl.DesiredAccuracy?>(
            initialValue: _accuracy,
            decoration: const InputDecoration(
              labelText: 'Desired accuracy',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(child: Text('Keep configured')),
              for (final a in tl.DesiredAccuracy.values)
                DropdownMenuItem(value: a, child: Text(a.name)),
            ],
            onChanged: (v) => setState(() => _accuracy = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _filterCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Distance filter (m) — empty keeps configured',
              hintText: '0 delivers every fix',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _applyFromForm,
            icon: const Icon(Icons.tune),
            label: const Text('Apply Override'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _busy
                ? null
                : () => _apply(
                    accuracy: tl.DesiredAccuracy.medium,
                    filter: 25,
                  ),
            icon: const Icon(Icons.battery_saver),
            label: const Text('Stationary preset (medium / 25 m)'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _apply,
            icon: const Icon(Icons.settings_backup_restore),
            label: const Text('Restore Configured Options'),
          ),
          const SizedBox(height: 24),

          // ── Log ──
          Text('Log', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(minHeight: 120),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Text(
              _log.isEmpty
                  ? 'Start tracking, apply an override, and watch the '
                        'accuracy of incoming fixes change — with no gap in '
                        'the fix stream.'
                  : _log.join('\n'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
