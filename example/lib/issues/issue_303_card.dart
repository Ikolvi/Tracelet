import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #303 — location-filter config never reached the Rust processor.
///
/// `setConfig()` rebuilt the processor only for a short `locationKeys` list.
/// Everything else the processor is constructed from — `trackingAccuracyThreshold`,
/// `odometerAccuracyThreshold`, `maxImpliedSpeed`, `filterPolicy`,
/// `enableAdaptiveMode`, the mock-detection pair, the sparse-update trio and
/// `useKalmanFilter` — was accepted, cached in ConfigManager, and then ignored
/// until the next cold start.
///
/// The sharpest consequence was in #301: `LocationProcessor.base_tuning` is
/// captured at construction, so "disabling auto-tune restores the thresholds you
/// configured" restored *construction-time* values. Change a threshold with
/// `setConfig`, disable auto-tuning, and you got the old number back.
///
/// The fix adds `set_base_tuning` to the Rust processor — deliberately not a
/// rebuild, because a rebuild drops the positional anchor and forfeits an
/// odometer delta (the whole reason `retune` exists, #299).
///
/// This card asserts the Dart-observable half: that the values you set are the
/// values `activeConfig` reports back after a runtime `setConfig`, including
/// across an auto-tune enable/disable cycle. The native threshold swap itself
/// has no Dart getter; it is covered by the Rust and SDK unit tests and by the
/// INFO log line this fix added to `syncTransportModeTuning`.
class Issue303Card extends StatefulWidget {
  const Issue303Card({super.key});

  @override
  State<Issue303Card> createState() => _Issue303CardState();
}

class _Issue303CardState extends State<Issue303Card> {
  String _status = 'Idle';
  bool _running = false;

  void _set(String s) {
    if (mounted) setState(() => _status = s);
  }

  Future<void> _run() async {
    setState(() => _running = true);
    final results = <String>[];
    var allPass = true;

    void check(String name, bool pass, String detail) {
      results.add('${pass ? '✅' : '❌'} $name — $detail');
      if (!pass) allPass = false;
    }

    try {
      await Tracelet.ready(
        const Config(
          geo: GeoConfig(
            distanceFilter: 12,
            filter: LocationFilter(
              trackingAccuracyThreshold: 120,
              odometerAccuracyThreshold: 60,
              maxImpliedSpeed: 90,
            ),
          ),
        ),
      );

      // 1. The regression itself. Every one of these keys used to stop at
      //    ConfigManager; only distanceFilter was ever in `locationKeys`.
      await Tracelet.setConfig(
        const Config(
          geo: GeoConfig(
            distanceFilter: 12,
            filter: LocationFilter(
              trackingAccuracyThreshold: 30,
              odometerAccuracyThreshold: 15,
              maxImpliedSpeed: 25,
              useKalmanFilter: true,
            ),
          ),
        ),
      );
      final f = Tracelet.activeConfig.geo.filter;
      check(
        'Filter thresholds survive a runtime setConfig',
        f.trackingAccuracyThreshold == 30 &&
            f.odometerAccuracyThreshold == 15 &&
            f.maxImpliedSpeed == 25,
        'tracking=${f.trackingAccuracyThreshold}m '
            'odometer=${f.odometerAccuracyThreshold}m '
            'maxImpliedSpeed=${f.maxImpliedSpeed}m/s',
      );

      // 2. Kalman is a separate object built only inside rebuildProcessor(), and
      //    its key never triggered one — so toggling it mid-session did nothing.
      //    That got worse with #299, which routed smoothing into the odometer.
      check(
        'useKalmanFilter toggles at runtime',
        f.useKalmanFilter,
        'smoothing is on, so it now feeds the odometer as #299 intended',
      );

      // 3. The #301 interaction: with auto-tuning on, a committed mode owns the
      //    live thresholds — but the restore target must be YOUR latest values,
      //    not the ones captured when the processor was built.
      await Tracelet.setConfig(
        const Config(
          geo: GeoConfig(
            distanceFilter: 12,
            filter: LocationFilter(
              trackingAccuracyThreshold: 45,
              odometerAccuracyThreshold: 22,
              maxImpliedSpeed: 33,
            ),
          ),
          classifier: ClassifierConfig(
            enableFusedClassifier: true,
            autoTuneFromTransportMode: true,
          ),
        ),
      );
      // Now switch auto-tuning back off. Pre-#303 this restored the ORIGINAL
      // construction-time thresholds (120/60/90), discarding both setConfigs.
      await Tracelet.setConfig(
        const Config(
          geo: GeoConfig(
            distanceFilter: 12,
            filter: LocationFilter(
              trackingAccuracyThreshold: 45,
              odometerAccuracyThreshold: 22,
              maxImpliedSpeed: 33,
            ),
          ),
          classifier: ClassifierConfig(enableFusedClassifier: true),
        ),
      );
      final r = Tracelet.activeConfig.geo.filter;
      check(
        'Disabling auto-tune restores your LATEST values',
        r.trackingAccuracyThreshold == 45 &&
            r.odometerAccuracyThreshold == 22 &&
            r.maxImpliedSpeed == 33,
        'restored tracking=${r.trackingAccuracyThreshold}m '
            '(the construction-time value was 120m)',
      );

      // 4. The remaining constructor-only processor parameters, which now
      //    trigger a targeted rebuild rather than being dropped.
      await Tracelet.setConfig(
        const Config(
          geo: GeoConfig(
            distanceFilter: 12,
            enableAdaptiveMode: true,
            enableSparseUpdates: true,
            sparseDistanceThreshold: 75,
            filter: LocationFilter(rejectMockLocations: true),
          ),
        ),
      );
      final g = Tracelet.activeConfig.geo;
      check(
        'Adaptive / sparse / mock-rejection parameters apply',
        g.enableAdaptiveMode &&
            g.enableSparseUpdates &&
            g.sparseDistanceThreshold == 75 &&
            g.filter.rejectMockLocations,
        'sparseDistanceThreshold=${g.sparseDistanceThreshold}m, '
            'adaptive=${g.enableAdaptiveMode}, '
            'rejectMock=${g.filter.rejectMockLocations}',
      );

      await Tracelet.stop();

      final header = allPass
          ? '✅ SUCCESS: the location-filter config you set now reaches the '
                'processor that uses it, and survives an auto-tune cycle.'
          : '❌ FAILED — #303 not satisfied on this build. See the failing rows.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'The Rust processor holds its own copies of these thresholds. Before '
        '#303 the only route in was rebuildProcessor(), gated on a short key '
        'list, so most of the filter config was accepted and ignored until a '
        'cold start — and restore_base_tuning() reverted to values the host had '
        'already replaced. set_base_tuning() now carries them in without '
        'dropping the odometer anchor a rebuild would cost (#299).',
      );
    } catch (e) {
      _set('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'trackingAccuracyThreshold odometerAccuracyThreshold maxImpliedSpeed '
          'useKalmanFilter setConfig locationKeys rebuildProcessor '
          'set_base_tuning restore base tuning stranded config sparse adaptive '
          'rejectMockLocations filterPolicy autoTuneFromTransportMode',
      title: '#303: Filter config reaches the Rust processor at runtime',
      description:
          'Asserts that trackingAccuracyThreshold, odometerAccuracyThreshold, '
          'maxImpliedSpeed, useKalmanFilter and the sparse/adaptive/mock '
          'parameters take effect from a runtime setConfig() instead of being '
          'ignored until the next cold start — and that disabling auto-tuning '
          'restores the values you most recently set, not the ones captured '
          'when the processor was first built.',
      status: _status,
      running: _running,
      onRun: _run,
    );
  }
}
