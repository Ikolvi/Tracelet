import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #276 — tunable accuracy-aware geofence EXIT (`geofenceExitAccuracyMax`).
///
/// #274 made the high-accuracy EXIT decision accuracy-aware so a single
/// high-drift GPS fix can't fire a false EXIT while a device sits still inside
/// a small geofence. The tradeoff is that a *genuine* departure is delayed by
/// roughly the GPS uncertainty. `GeofenceConfig.geofenceExitAccuracyMax` lets
/// apps tune that:
///
///   • `-1` (default) — full gating (most drift-resistant).
///   • `0`            — gating off (fastest exit, drift-prone / pre-#274).
///   • `N > 0`        — clamp accuracy to N m (bounded delay, still absorbs
///                      drift up to N).
///
/// This card drives the REAL shipped [GeofenceEvaluator], applying the exact
/// clamp the native layer applies (`effectiveExitAccuracy`), and runs the same
/// scenario under all three settings for a 50 m geofence (exit threshold 70 m):
///
///   1. ENTER with a solid ±8 m fix ~10 m from center.
///   2. Stationary DRIFT spike: reported ~85 m out but with ±150 m accuracy
///      (device never moved).
///   3. GENUINE departure: ~120 m out with a tight ±10 m accuracy.
///
/// Expected — confirming the knob behaves as documented:
///   • `-1` and `N=20` → absorb the drift (no false EXIT) AND detect the real
///     departure. Ideal.
///   • `0` → fires a false EXIT on the drift (fast but drift-prone).
class Issue276Card extends StatefulWidget {
  const Issue276Card({super.key});

  @override
  State<Issue276Card> createState() => _Issue276CardState();
}

class _Issue276CardState extends State<Issue276Card> {
  String _status = 'Idle';
  bool _running = false;

  void _set(String s) {
    if (mounted) setState(() => _status = s);
  }

  /// Mirrors the native `GeofenceManager.effectiveExitAccuracy` clamp so the
  /// in-process demo matches on-device behavior:
  /// `-1` pass-through, `0` disables gating, `N>0` clamps to N.
  static double _effectiveExitAccuracy(double accuracy, int exitAccuracyMax) {
    if (exitAccuracyMax < 0) return accuracy;
    if (exitAccuracyMax == 0) return 0;
    return math.min(accuracy, exitAccuracyMax.toDouble());
  }

  /// Runs the enter → stationary-drift → genuine-departure sequence for one
  /// `geofenceExitAccuracyMax` setting. Returns whether the drift produced a
  /// (false) EXIT and whether the genuine departure produced an EXIT.
  ({bool driftExit, bool realExit}) _runScenario(int exitAccuracyMax) {
    const centerLat = 37.4219983;
    const centerLng = -122.084;
    final geofences = <Map<String, Object?>>[
      {
        'identifier': 'issue-276',
        'latitude': centerLat,
        'longitude': centerLng,
        'radius': 50.0, // exit threshold = 70 m
      },
    ];

    final evaluator = GeofenceEvaluator();

    ({double lat, double lng}) north(double d) =>
        (lat: centerLat + d / 111320.0, lng: centerLng);

    List<GeofenceTransition> eval(double d, double acc) {
      final p = north(d);
      return evaluator.evaluateProximity(
        latitude: p.lat,
        longitude: p.lng,
        accuracy: _effectiveExitAccuracy(acc, exitAccuracyMax),
        geofences: geofences,
      );
    }

    // 1. Enter well inside with good accuracy.
    eval(10, 8);

    // 2. Stationary drift spike (reported far out, but low-confidence).
    final drift = eval(85, 150);
    final driftExit = drift.any((t) => t.action == 'EXIT');

    // 3. Genuine, accurate departure.
    final real = eval(120, 10);
    final realExit = real.any((t) => t.action == 'EXIT');

    return (driftExit: driftExit, realExit: realExit);
  }

  Future<void> _run() async {
    setState(() => _running = true);
    try {
      const modes = <int>[-1, 0, 20];
      final log = StringBuffer();
      final results = <int, ({bool driftExit, bool realExit})>{};

      for (final m in modes) {
        final r = _runScenario(m);
        results[m] = r;
        final label = m == -1
            ? 'full gating'
            : m == 0
            ? 'gating off'
            : 'clamp ${m}m';
        log.writeln(
          'geofenceExitAccuracyMax=$m ($label): '
          'drift→${r.driftExit ? 'EXIT (false)' : 'held'}, '
          'departure→${r.realExit ? 'EXIT' : 'no exit'}',
        );
      }

      final full = results[-1]!;
      final off = results[0]!;
      final clamp = results[20]!;

      // Documented behavior:
      // • -1 (full) and 20 (clamp) absorb the stationary drift (no false EXIT)
      //   yet still fire EXIT on the genuine departure.
      // • 0 (off) fires a false EXIT on the drift spike. Once that EXIT fires
      //   the device is already "outside", so the later genuine departure is a
      //   no-op (there is no second EXIT to fire) — we therefore only assert
      //   that the drift itself exited for this mode.
      final ok =
          !full.driftExit &&
          full.realExit &&
          !clamp.driftExit &&
          clamp.realExit &&
          off.driftExit;

      if (ok) {
        _set(
          '✅ SUCCESS: geofenceExitAccuracyMax behaves as documented.\n\n'
          '$log\n'
          '• -1 (default) and 20 m absorbed the ±150 m stationary drift AND '
          'still fired EXIT on the genuine departure.\n'
          '• 0 fired a false EXIT on the drift — the eager, pre-#274 behavior '
          'you opt into for the fastest exits. (It already left the fence on '
          'the drift, so the later departure is a no-op.)',
        );
      } else {
        _set('❌ FAILED: unexpected behavior for one or more settings.\n\n$log');
      }
    } catch (e) {
      _set('❌ FAILED: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'geofence exit accuracy max geofenceExitAccuracyMax tunable gating '
          'gps drift false exit clamp high accuracy geofenceevaluator 276 274',
      title:
          '#276: Tunable accuracy-aware geofence EXIT (geofenceExitAccuracyMax)',
      description:
          'Drives the real GeofenceEvaluator under all three '
          'geofenceExitAccuracyMax settings (-1 full gating, 0 off, 20 m clamp) '
          'for a 50 m geofence, running the same enter → stationary-drift → '
          'genuine-departure sequence. Confirms full/clamp absorb a ±150 m '
          'drift spike while still detecting a real departure, and that '
          'disabling gating (0) reproduces the eager pre-#274 exit. Runs '
          'in-process; no permissions or movement required.',
      status: _status,
      running: _running,
      onRun: _run,
    );
  }
}
