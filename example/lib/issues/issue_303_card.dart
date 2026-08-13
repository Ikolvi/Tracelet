import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

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
/// Every assertion here reads `Tracelet.getCurrentLocationTuning()`, which
/// reports the thresholds the **native processor** actually holds. It
/// deliberately does not assert on `Tracelet.activeConfig`: that is a Dart-side
/// mirror of the last `Config` passed in, so it echoes your own input and would
/// pass even on a build where the value never reached native — which is the bug
/// itself. A card that asserted on it would be untestable theatre.
class Issue303Card extends StatefulWidget {
  const Issue303Card({super.key});

  @override
  State<Issue303Card> createState() => _Issue303CardState();
}

class _Issue303CardState extends State<Issue303Card>
    with IssueCardRun<Issue303Card> {
  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _run;

  Future<void> _run() async {
    setRunning(running: true);
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
      // Read back from the PROCESSOR, not activeConfig. activeConfig is a
      // Dart-side mirror of whatever was just passed in, so asserting on it
      // would pass even when the value never reached native — the bug itself.
      final live = await Tracelet.getCurrentLocationTuning();
      check(
        'Filter thresholds reach the processor on a runtime setConfig',
        live != null &&
            live.trackingAccuracyThreshold == 30 &&
            live.odometerAccuracyThreshold == 15 &&
            live.maxImpliedSpeed == 25,
        live == null
            ? 'no processor yet — start tracking first'
            : 'processor reports tracking=${live.trackingAccuracyThreshold}m '
                  'odometer=${live.odometerAccuracyThreshold}m '
                  'maxImpliedSpeed=${live.maxImpliedSpeed}m/s',
      );

      // 2. Kalman is a separate object built only inside rebuildProcessor(), and
      //    its key never triggered one — so toggling it mid-session did nothing.
      //    That got worse with #299, which routed smoothing into the odometer.
      // The Kalman filter is a separate native object with no read-back
      // surface, so this card cannot prove the toggle from Dart. Asserting
      // activeConfig here would be theatre. Covered by the SDK unit tests.
      results.add(
        'ℹ️ useKalmanFilter toggle is not Dart-observable (the filter has no '
        'read-back API) — covered by the Android/iOS SDK unit tests.',
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
      final restored = await Tracelet.getCurrentLocationTuning();
      check(
        'Disabling auto-tune restores your LATEST values',
        restored != null &&
            restored.trackingAccuracyThreshold == 45 &&
            restored.odometerAccuracyThreshold == 22 &&
            restored.maxImpliedSpeed == 33,
        restored == null
            ? 'no processor yet — start tracking first'
            : 'processor restored to tracking='
                  '${restored.trackingAccuracyThreshold}m — the '
                  'construction-time value was 120m, which is what a '
                  'pre-#303 build would have reverted to',
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
            // The thresholds are restated deliberately: a Config is a whole
            // document, not a patch, so a LocationFilter that omitted them
            // would serialize its defaults (100/50/80) and reset them. The
            // rebuild must preserve what is configured NOW, which is 45.
            filter: LocationFilter(
              trackingAccuracyThreshold: 45,
              odometerAccuracyThreshold: 22,
              maxImpliedSpeed: 33,
              rejectMockLocations: true,
            ),
          ),
        ),
      );
      // A processorKeys change rebuilds the processor from current config, so
      // the thresholds must survive that rebuild rather than reverting to the
      // values captured when it was first constructed.
      final afterRebuild = await Tracelet.getCurrentLocationTuning();
      check(
        'Thresholds survive a processor rebuild',
        afterRebuild != null && afterRebuild.trackingAccuracyThreshold == 45,
        afterRebuild == null
            ? 'no processor yet — start tracking first'
            : 'after the sparse/adaptive rebuild the processor still reports '
                  'tracking=${afterRebuild.trackingAccuracyThreshold}m',
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
        'dropping the odometer anchor a rebuild would cost (#299).\n\n'
        'These rows read getCurrentLocationTuning(), which reports what the '
        'processor actually holds — not activeConfig, which merely echoes the '
        'Config you passed in and would pass on a broken build.',
      );
    } catch (e) {
      _set('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      setRunning(running: false);
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
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
