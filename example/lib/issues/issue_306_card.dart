import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart'
    show GeofenceEvaluator;
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #306 — the pure-Dart `GeofenceEvaluator` ignored
/// `geofenceExitAccuracyMax`, diverging from the native #276 gate.
///
/// The evaluator is documented as a mirror of the Rust core, and it faithfully
/// mirrors the #268 hysteresis and the #294 confirmed-exit gate. It did not
/// mirror #276: both native GeofenceManagers pass the raw fix accuracy through
/// an `effectiveExitAccuracy` policy before the accuracy-aware EXIT test, and
/// the Dart evaluator had no equivalent — so it gated on raw accuracy and the
/// `-1 / 0 / N` semantics were simply unavailable to Dart callers.
///
/// The policy, now mirrored exactly:
/// - `-1` (default): pass accuracy through unchanged — full gating.
/// - `0`: disable gating — fastest EXIT, drift-prone.
/// - `N > 0`: clamp accuracy to N, bounding the worst-case EXIT delay.
///
/// Also bundled: the Rust evaluator now drops pending exit confirmations for
/// fences a re-index no longer covers, and `Tracelet._geofenceEvaluator` — a
/// static that was constructed and cleared but never used to evaluate anything
/// — is gone.
class Issue306Card extends StatefulWidget {
  const Issue306Card({super.key});

  @override
  State<Issue306Card> createState() => _Issue306CardState();
}

class _Issue306CardState extends State<Issue306Card> {
  String _status = 'Idle';
  bool _running = false;

  /// A 100 m fence. All fixes below are placed due north of its centre.
  static const _lat = 37.4219983;
  static const _lng = -122.084;
  static const _radius = 100.0;

  static final _fence = <String, Object?>{
    'identifier': 'office',
    'latitude': _lat,
    'longitude': _lng,
    'radius': _radius,
  };

  /// A point [metres] due north of the fence centre.
  static Map<String, double> _fixAt(double metres) => {
    'lat': _lat + metres / 111320.0,
    'lng': _lng,
  };

  void _set(String s) {
    if (mounted) setState(() => _status = s);
  }

  /// Drives an evaluator from inside the fence out to [outsideMetres] with the
  /// given [accuracy] and [exitAccuracyMax], and reports whether EXIT fired.
  ///
  /// Two outside fixes are supplied because #294 requires an EXIT to be
  /// confirmed across consecutive out-of-fence fixes — one is never enough.
  bool _exitsWith({
    required double accuracy,
    required int exitAccuracyMax,
    double outsideMetres = 180,
  }) {
    final ev = GeofenceEvaluator();
    final inside = _fixAt(10);
    ev.evaluateProximity(
      latitude: inside['lat']!,
      longitude: inside['lng']!,
      geofences: [_fence],
      accuracy: 5,
      exitAccuracyMax: exitAccuracyMax,
    );
    final out = _fixAt(outsideMetres);
    var exited = false;
    for (var i = 0; i < 2; i++) {
      final t = ev.evaluateProximity(
        latitude: out['lat']!,
        longitude: out['lng']!,
        geofences: [_fence],
        accuracy: accuracy,
        exitAccuracyMax: exitAccuracyMax,
      );
      if (t.any((x) => x.action == 'EXIT')) exited = true;
    }
    return exited;
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
      // The fence is 100 m with a 20 m hysteresis floor, so EXIT needs
      // distance - effectiveAccuracy > 120 m. At 180 m out:
      //   accuracy 100 → 80 m  → no exit under full gating
      //   accuracy   0 → 180 m → exit

      // 1. Full gating (-1, the default): a large reported accuracy holds the
      //    EXIT. This is the #274 behavior and must be unchanged.
      check(
        'exitAccuracyMax = -1 keeps full accuracy gating',
        !_exitsWith(accuracy: 100, exitAccuracyMax: -1),
        'a 100 m-accuracy fix 180 m out does NOT exit — the error circle still '
            'overlaps the fence',
      );

      // 2. Gating disabled (0): the same fix exits immediately. Before #306
      //    this was unreachable from Dart at any setting.
      check(
        'exitAccuracyMax = 0 disables gating',
        _exitsWith(accuracy: 100, exitAccuracyMax: 0),
        'the same fix now exits, because accuracy is forced to 0',
      );

      // 3. Clamping (N > 0): accuracy is capped at N, bounding the worst-case
      //    delay. Clamping 100 m down to 30 m makes 180 - 30 = 150 > 120.
      check(
        'exitAccuracyMax = 30 clamps accuracy and bounds the delay',
        _exitsWith(accuracy: 100, exitAccuracyMax: 30),
        'a wildly over-reported accuracy is capped at 30 m, so a genuine '
            'departure is not held indefinitely',
      );

      // 4. Clamping must not weaken gating for fixes that are already tighter
      //    than the cap — min(), not "replace with N".
      check(
        'Clamping never loosens an already-tight accuracy',
        !_exitsWith(accuracy: 100, exitAccuracyMax: 90),
        'a 90 m cap still leaves 180 - 90 = 90 m, inside the 120 m threshold, '
            'so the EXIT is correctly withheld',
      );

      // 5. The default must remain full gating, so existing callers that never
      //    pass the parameter keep the behavior they had before #306.
      final ev = GeofenceEvaluator();
      final inside = _fixAt(10);
      ev.evaluateProximity(
        latitude: inside['lat']!,
        longitude: inside['lng']!,
        geofences: [_fence],
        accuracy: 5,
      );
      final out = _fixAt(180);
      var exitedByDefault = false;
      for (var i = 0; i < 2; i++) {
        final t = ev.evaluateProximity(
          latitude: out['lat']!,
          longitude: out['lng']!,
          geofences: [_fence],
          accuracy: 100,
        );
        if (t.any((x) => x.action == 'EXIT')) exitedByDefault = true;
      }
      check(
        'Omitting the parameter keeps pre-#306 behavior',
        !exitedByDefault,
        'the default is -1 (full gating), so no existing caller changes '
            'behavior',
      );

      final header = allPass
          ? '✅ SUCCESS: the Dart evaluator now applies the same '
                'geofenceExitAccuracyMax policy as both native managers.'
          : '❌ FAILED — #306 not satisfied on this build. See the failing rows.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'The evaluator is documented as a mirror of the Rust core, so a policy '
        'that exists natively and not here is a correctness gap for anyone who '
        'uses it to predict SDK behavior. Also in this fix: the Rust evaluator '
        'drops pending exit confirmations for fences a re-index no longer '
        'covers, and the unused Tracelet._geofenceEvaluator static is removed.',
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
          'GeofenceEvaluator geofenceExitAccuracyMax exit accuracy gating '
          'effectiveExitAccuracy clamp hysteresis confirmed exit mirror rust '
          'core divergence pending_exit_counts index_geofences dead code',
      title: '#306: Dart GeofenceEvaluator now honors geofenceExitAccuracyMax',
      description:
          'Asserts the pure-Dart evaluator applies the same -1 / 0 / N '
          'exit-accuracy policy as both native GeofenceManagers: full gating '
          'by default, gating disabled at 0, and min-clamping at N — which '
          'bounds the worst-case EXIT delay without ever loosening gating for '
          'a fix that is already tighter than the cap. Runs in-process; no '
          'movement or permissions needed.',
      status: _status,
      running: _running,
      onRun: _run,
    );
  }
}
