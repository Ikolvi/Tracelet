import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;

/// Remote Config → Dart `activeConfig` sync.
///
/// ## The bug this reproduces
/// Remote config (Enterprise `remoteConfigUrl`) is fetched and applied entirely
/// on the native side; the fetch never round-tripped through Dart. So while the
/// native tracking engine honoured a remote override, the Dart-facing
/// `Tracelet.activeConfig` (and tools like tracelet_doctor, plus the Dart-side
/// battery-budget engine) kept showing the last *locally*-set values. A remote
/// gist of `{"geo":{"batteryBudgetPerHour":1.0}}` therefore appeared to "not
/// work": Doctor never showed 1%.
///
/// ## The fix
/// Native now emits an `onRemoteConfig` event whenever it applies a remote
/// override; the Dart layer folds it into `activeConfig` and re-inits the
/// Dart-side battery-budget engine.
///
/// ## What this card verifies (real end-to-end)
/// 1. `ready()` with `batteryBudgetPerHour` OFF locally + a real
///    `remoteConfigUrl` that returns `{"geo":{"batteryBudgetPerHour":1.0}}`.
/// 2. `start()`, then waits for `Tracelet.onRemoteConfig` to fire.
/// 3. Asserts `Tracelet.activeConfig.geo.batteryBudgetPerHour == 1.0` — i.e. the
///    remotely fetched value is now reflected on the Dart side.
///
/// Requires network (it fetches the gist). Before the fix, the event never
/// fired and `activeConfig` stayed at 0.
class BatteryBudgetRemoteConfigCard extends StatefulWidget {
  const BatteryBudgetRemoteConfigCard({super.key});

  @override
  State<BatteryBudgetRemoteConfigCard> createState() =>
      _BatteryBudgetRemoteConfigCardState();
}

class _BatteryBudgetRemoteConfigCardState
    extends State<BatteryBudgetRemoteConfigCard> {
  /// Gist returning `{"geo":{"batteryBudgetPerHour":1.0}}`.
  static const _remoteUrl =
      'https://gist.githubusercontent.com/MuellerMoritz/'
      '28b9559f12f0a7da11d13874d6b7068a/raw';

  /// The value the gist should apply.
  static const double _expectedBudget = 1;

  String _status = 'Idle';
  bool _busy = false;
  StreamSubscription<Config>? _remoteSub;

  void _set(String s) {
    if (mounted) setState(() => _status = s);
  }

  @override
  void dispose() {
    _remoteSub?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    final completer = Completer<Config>();
    try {
      _set('Requesting permissions...');
      final auth = await Tracelet.requestLocationAuthorization();
      if (auth != AuthorizationStatus.always &&
          auth != AuthorizationStatus.whenInUse) {
        _set('❌ FAILED: location permission denied ($auth).');
        return;
      }

      // Listen BEFORE ready()/fetch so we catch the first onRemoteConfig event.
      await _remoteSub?.cancel();
      _remoteSub = Tracelet.onRemoteConfig((config) {
        if (!completer.isCompleted) completer.complete(config);
      });

      // 1. ready() with the budget OFF locally + a real remoteConfigUrl.
      _set('ready() with remoteConfigUrl (budget starts OFF locally)...');
      await Tracelet.ready(
        Config.balanced().copyWith(
          app: const AppConfig(
            remoteConfigUrl: _remoteUrl,
            remoteConfigRefreshInterval: 15,
          ),
          motion: const MotionConfig(
            isMoving: true,
            disableStopDetection: true,
          ),
          logger: const LoggerConfig(debug: true, logLevel: LogLevel.verbose),
        ),
      );

      final beforeBudget = Tracelet.activeConfig.geo.batteryBudgetPerHour;
      if (beforeBudget != 0) {
        _set(
          '⚠️ Expected local budget to start at 0 but activeConfig shows '
          '$beforeBudget. Reset the app and retry for a clean repro.',
        );
      }

      await Tracelet.start();
      _set(
        'Waiting for the remote config fetch to apply '
        '(onRemoteConfig)...\n(needs network)',
      );

      // 2. Wait for native to fetch + apply, then emit onRemoteConfig.
      final Config applied;
      try {
        applied = await completer.future.timeout(const Duration(seconds: 30));
      } on TimeoutException {
        _set(
          '❌ FAILED: onRemoteConfig never fired within 30s. The remote config '
          'was not fetched/applied (check connectivity and the verbose log for '
          '"remote config: fetched …").',
        );
        return;
      }

      // 3. Verify the Dart side now reflects the remote value.
      final eventBudget = applied.geo.batteryBudgetPerHour;
      final activeBudget = Tracelet.activeConfig.geo.batteryBudgetPerHour;

      if (activeBudget == _expectedBudget && eventBudget == _expectedBudget) {
        _set(
          '✅ PASS: remote config applied on the Dart side.\n'
          'onRemoteConfig delivered batteryBudgetPerHour=$eventBudget, and '
          'Tracelet.activeConfig now reports $activeBudget%/hr.\n'
          'tracelet_doctor will now show $activeBudget% too.',
        );
      } else {
        _set(
          '❌ FAILED: expected $_expectedBudget but onRemoteConfig gave '
          '$eventBudget and activeConfig shows $activeBudget. '
          '(If the gist changed, update _expectedBudget.)',
        );
      }
    } catch (e) {
      _set('❌ FAILED: $e');
    } finally {
      await _remoteSub?.cancel();
      _remoteSub = null;
      try {
        await Tracelet.stop();
      } catch (_) {
        // best-effort
      }
      if (mounted) setState(() => _busy = false);
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
              'Remote Config → activeConfig sync (batteryBudgetPerHour)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Starts with the battery budget OFF locally, fetches a remote '
              'config that sets batteryBudgetPerHour=1.0, and verifies the '
              'value now shows up in Tracelet.activeConfig via the new '
              'onRemoteConfig event. Before the fix, remote config was applied '
              'natively but never reflected in Dart (tracelet_doctor kept '
              'showing the local value). Requires network.',
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
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _run,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_sync),
              label: Text(_busy ? 'Running...' : 'Run remote config test'),
            ),
          ],
        ),
      ),
    );
  }
}
