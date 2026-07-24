import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;

/// Battery Budget via Remote Config — verifies that `batteryBudgetPerHour`
/// delivered *after* `ready()` (i.e. through a runtime `setConfig()`, which is
/// exactly how a fetched remote config is applied) actually activates the
/// battery-budget engine.
///
/// ## The bug this reproduces
/// The battery-budget engine used to be built **only** inside `ready()`. A
/// remote-config push such as `{"geo":{"batteryBudgetPerHour":1.0}}` is applied
/// at runtime via `setConfig()` — a path that rebuilt the location/motion
/// pipeline and the crash/telematics engines when their keys changed, but never
/// touched the battery-budget engine. So the value landed in the config cache
/// yet had **no effect**: no throttling, no `onBudgetAdjustment` events. It only
/// appeared to work after a cold restart, because the cached remote config is
/// applied *before* `ready()` builds the engine.
///
/// ## What this card does
/// 1. `ready()` with the budget **off** (`batteryBudgetPerHour` unset), then
///    `start()` — mirroring `Config.balanced()` used by the Remote Config card.
/// 2. Applies `geo.batteryBudgetPerHour` at runtime via `setConfig()` — the same
///    nested shape a remote endpoint returns. The motion config is kept
///    identical to `ready()` so this is a budget-only change and does **not**
///    restart the tracking pipeline.
/// 3. Subscribes to `Tracelet.onBudgetAdjustment`.
///
/// After the fix the engine is (re)built on that runtime change and starts
/// sampling, so `onBudgetAdjustment` events begin to arrive and the native log
/// shows `BatteryBudget adjusted: …`. Before the fix, nothing ever fired no
/// matter how long you waited.
///
/// Sampling is periodic (every few minutes, and skipped while charging — unplug
/// the device), so leave tracking running to observe adjustments. The card
/// confirms up-front that the runtime apply is accepted, that the budget is
/// reflected in the effective config, and that tracking stays enabled (no
/// pipeline restart); the live counter then proves the engine is actually
/// running.
class BatteryBudgetRemoteConfigCard extends StatefulWidget {
  const BatteryBudgetRemoteConfigCard({super.key});

  @override
  State<BatteryBudgetRemoteConfigCard> createState() =>
      _BatteryBudgetRemoteConfigCardState();
}

class _BatteryBudgetRemoteConfigCardState
    extends State<BatteryBudgetRemoteConfigCard> {
  /// Target battery budget applied at runtime (percent per hour).
  static const double _budgetPerHour = 5;

  String _status = 'Idle';
  bool _tracking = false;
  bool _busy = false;
  int _adjustmentCount = 0;
  String _latestAdjustment = '';
  StreamSubscription<BudgetAdjustmentEvent>? _budgetSub;

  void _set(String s) {
    if (mounted) setState(() => _status = s);
  }

  @override
  void dispose() {
    _budgetSub?.cancel();
    super.dispose();
  }

  /// Motion config shared by `ready()` and the runtime `setConfig()`.
  ///
  /// Kept identical between the two calls so the runtime apply is a budget-only
  /// change: motion keys are restart-sensitive, and any diff would restart the
  /// whole pipeline instead of exercising the battery-budget rebuild path.
  /// `isMoving`/`disableStopDetection` also keep the session in the moving state
  /// so sampling keeps running instead of the device dropping to stationary.
  static const _motion = MotionConfig(
    isMoving: true,
    disableStopDetection: true,
  );

  Future<void> _start() async {
    if (_busy || _tracking) return;
    setState(() {
      _busy = true;
      _adjustmentCount = 0;
      _latestAdjustment = '';
    });
    try {
      _set('Requesting permissions...');
      final auth = await Tracelet.requestLocationAuthorization();
      if (auth != AuthorizationStatus.always &&
          auth != AuthorizationStatus.whenInUse) {
        _set('❌ FAILED: location permission denied ($auth).');
        return;
      }

      // 1. Start with the budget OFF — the reported starting point.
      _set('ready() with battery budget OFF, then start()...');
      await Tracelet.ready(
        const Config(
          motion: _motion,
          logger: LoggerConfig(debug: true, logLevel: LogLevel.verbose),
        ),
      );

      // Wire the listener before the budget is enabled so we capture the very
      // first adjustment the engine emits once it starts sampling.
      await _budgetSub?.cancel();
      _budgetSub = Tracelet.onBudgetAdjustment((event) {
        if (!mounted) return;
        setState(() {
          _adjustmentCount++;
          _latestAdjustment =
              'drain: ${event.currentBatteryDrain.toStringAsFixed(2)}%/hr → '
              'target ${event.targetBudget}%/hr\n'
              'df=${event.newDistanceFilter}m  acc=${event.newDesiredAccuracy}'
              '  interval=${event.newPeriodicInterval}s';
          _status =
              '✅ onBudgetAdjustment fired ($_adjustmentCount) — the engine '
              'applied at runtime is ACTIVE.\n$_latestAdjustment';
        });
      });

      final started = await Tracelet.start();
      if (!started.enabled) {
        _set('❌ FAILED: tracking did not start (enabled=false).');
        return;
      }

      final before = await Tracelet.getState();
      final budgetBefore = before.config?.geo.batteryBudgetPerHour ?? 0;
      if (budgetBefore > 0) {
        _set(
          '⚠️ Expected the budget to start at 0 but it is $budgetBefore. '
          'Reset the SDK and retry for a clean repro.',
        );
      }

      // 2. Deliver batteryBudgetPerHour at RUNTIME — the remote-config path.
      //    Nested `{geo:{batteryBudgetPerHour:…}}`, exactly what an endpoint
      //    returns. Motion is unchanged, so this must NOT restart the pipeline.
      _set(
        'Applying batteryBudgetPerHour=$_budgetPerHour at runtime via '
        'setConfig() (the remote-config path)...',
      );
      await Tracelet.setConfig(
        const Config(
          geo: GeoConfig(batteryBudgetPerHour: _budgetPerHour),
          motion: _motion,
        ),
      );

      // Let the write settle, then confirm the mechanical guarantees.
      await Future<void>.delayed(const Duration(seconds: 1));
      final after = await Tracelet.getState();
      final budgetAfter = after.config?.geo.batteryBudgetPerHour ?? 0;

      if (!after.enabled) {
        _set(
          '❌ FAILED: tracking is no longer enabled — a budget-only setConfig() '
          'must not restart or stop the pipeline.',
        );
        return;
      }
      if (budgetAfter != _budgetPerHour) {
        _set(
          '❌ FAILED: effective config shows batteryBudgetPerHour=$budgetAfter '
          'after the runtime apply (expected $_budgetPerHour).',
        );
        return;
      }

      setState(() {
        _tracking = true;
        _status =
            '✅ Runtime apply accepted: batteryBudgetPerHour=$budgetAfter, '
            'tracking still enabled (no restart).\n\n'
            'The battery-budget engine is now running. Keep tracking (device '
            'UNPLUGGED — sampling is skipped while charging); onBudgetAdjustment '
            'events will arrive over the next few minutes and the count below '
            'will climb. Watch the native log for "BatteryBudget adjusted: …".\n'
            'Before the fix, no adjustment ever fired from a runtime-only '
            'batteryBudgetPerHour.\n\nAdjustments so far: 0';
      });
    } catch (e) {
      _set('❌ FAILED: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _budgetSub?.cancel();
      _budgetSub = null;
      await Tracelet.stop();
    } catch (_) {
      // stopping is best-effort
    } finally {
      if (mounted) {
        setState(() {
          _tracking = false;
          _busy = false;
          _status = _adjustmentCount > 0
              ? '✅ Stopped. Saw $_adjustmentCount budget adjustment(s) from a '
                    'runtime-applied budget — the fix works.'
              : 'Stopped. No adjustments observed yet (sampling is periodic and '
                    'skipped while charging) — leave it running longer next time.';
        });
      }
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
              'Battery Budget via Remote Config: runtime batteryBudgetPerHour',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Starts with the battery budget OFF, then delivers '
              'geo.batteryBudgetPerHour at runtime via setConfig() — the same '
              'path a fetched remote config uses. Confirms the runtime apply is '
              'accepted without restarting tracking, then listens for '
              'onBudgetAdjustment events (which never fired before the fix). '
              'Keep the device unplugged and leave tracking running to observe '
              'adjustments.',
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
                _tracking && _adjustmentCount > 0
                    ? '$_status\n\nAdjustments so far: $_adjustmentCount'
                    : _status,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : (_tracking ? _stop : _start),
              icon: Icon(_tracking ? Icons.stop : Icons.battery_saver),
              label: Text(
                _tracking ? 'Stop' : 'Start (apply budget at runtime)',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
