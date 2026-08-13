import 'package:flutter/material.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #274 — GPS drift fires a false EXIT on small-radius geofences
/// (high-accuracy mode).
///
/// A device standing still WELL inside a small attendance geofence (e.g. 50 m)
/// occasionally receives a single high-drift GPS fix: the reported position
/// lands far outside the radius, but the fix also carries a correspondingly
/// large `horizontalAccuracy` (the OS is telling you "I'm not sure — could be
/// ±150 m"). The exit-hysteresis band from #268 absorbs small stationary
/// jitter, but a large single-fix drift spike sails right past it and fires a
/// bogus EXIT even though the user never moved.
///
/// The fix makes the EXIT decision accuracy-aware: a circular geofence only
/// EXITs once the ENTIRE error circle clears the fence
/// (`distance - accuracy > radius + exitBuffer`). ENTER stays accuracy-agnostic
/// so arrivals still trigger promptly.
///
/// This card drives the REAL shipped [GeofenceEvaluator] with a scripted
/// sequence for a 50 m geofence (exit threshold 70 m):
///
///   1. A solid ±8 m fix ~10 m from center → ENTER.
///   2. A drift spike reported ~160 m out but with ±150 m accuracy — the
///      nearest plausible position is `160 - 150 = 10 m`, still inside.
///   3. A recovered ±6 m fix ~12 m from center.
///   4. A GENUINE departure: ~120 m out with a tight ±10 m accuracy → EXIT.
///
///   • BUGGY build (no accuracy gating) → the drift spike at step 2 fires a
///     false EXIT → FAILED, which is how you manually confirm #274 exists.
///   • FIXED build → exactly one ENTER, no EXIT on the drift spike, and one
///     EXIT only on the real departure → SUCCESS.
class Issue274Card extends StatefulWidget {
  const Issue274Card({super.key});

  @override
  State<Issue274Card> createState() => _Issue274CardState();
}

class _Issue274CardState extends State<Issue274Card>
    with IssueCardRun<Issue274Card> {
  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _run;

  Future<void> _run() async {
    setRunning(running: true);
    try {
      const centerLat = 37.4219983;
      const centerLng = -122.084;
      const radius =
          50.0; // exit threshold = radius + max(radius*0.1, 20) = 70m

      final geofences = <Map<String, Object?>>[
        {
          'identifier': 'issue-274',
          'latitude': centerLat,
          'longitude': centerLng,
          'radius': radius,
        },
      ];

      // (distance from center in meters, reported horizontalAccuracy in meters)
      const fixes = <(double, double)>[
        (10, 8), // solid fix inside            → ENTER
        (160, 150), // high-drift, low-confidence  → must HOLD (no EXIT)
        (12, 6), // recovered accurate fix      → no change
        (120, 10), // genuine departure, accurate → EXIT
      ];

      final evaluator = GeofenceEvaluator();
      final log = StringBuffer();
      var enters = 0;
      var exits = 0;
      var driftFalseExit = false;

      for (var i = 0; i < fixes.length; i++) {
        final (d, acc) = fixes[i];
        // ~d meters due north of the center (1° lat ≈ 111_320 m).
        final pointLat = centerLat + d / 111320.0;
        final transitions = evaluator.evaluateProximity(
          latitude: pointLat,
          longitude: centerLng,
          accuracy: acc,
          geofences: geofences,
        );
        final actions = transitions.map((t) => t.action).join(', ');
        log.writeln(
          '~${d.toStringAsFixed(0)}m (±${acc.toStringAsFixed(0)}m) -> '
          '${actions.isEmpty ? '(no change)' : actions}',
        );
        for (final t in transitions) {
          if (t.action == 'ENTER') enters++;
          if (t.action == 'EXIT') {
            exits++;
            // Step index 1 (the drift spike) must NOT produce an EXIT.
            if (i == 1) driftFalseExit = true;
          }
        }
      }

      // Fixed behavior: exactly one ENTER, exactly one EXIT (the real
      // departure), and NO exit on the drift spike.
      final fixed = enters == 1 && exits == 1 && !driftFalseExit;

      if (fixed) {
        _set(
          '✅ SUCCESS (drift ignored): the real GeofenceEvaluator held INSIDE '
          'through the ±150 m drift spike and only EXITed on the genuine, '
          'accurate departure — $enters ENTER, $exits EXIT.\n\n'
          '$log\n'
          'The accuracy-aware exit condition '
          '(distance - accuracy > radius + buffer) absorbed the low-confidence '
          'fix. #274 is fixed on this build.',
        );
      } else if (driftFalseExit) {
        _set(
          '❌ FAILED — #274 REPRODUCED: the ±150 m drift spike fired a false '
          'EXIT while the device was standing still inside the fence '
          '($enters ENTER / $exits EXIT).\n\n'
          '$log\n'
          'A single high-drift, low-confidence fix should not trigger EXIT. '
          'This confirms the evaluator ignores horizontal accuracy.',
        );
      } else {
        _set(
          '❌ FAILED: unexpected transition counts — $enters ENTER / $exits '
          'EXIT.\n\n$log',
        );
      }
    } catch (e) {
      _set('❌ FAILED: $e');
    } finally {
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'geofence gps drift false exit accuracy horizontal accuracy small '
          'radius attendance stationary high accuracy geofenceevaluator '
          'proximity hysteresis exit gating 274',
      title: '#274: GPS drift fires a false EXIT on small-radius geofences',
      description:
          'Drives the real GeofenceEvaluator with a scripted sequence for a '
          '50 m geofence: a solid fix inside, a ±150 m drift spike reported far '
          'outside the radius, a recovery, then a genuine accurate departure. '
          'On a buggy build the drift spike fires a false EXIT so you can '
          'confirm #274 exists; on the fixed build the accuracy-aware exit '
          'holds through the drift and EXITs only on the real departure. Runs '
          'in-process; no permissions or device movement required.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
