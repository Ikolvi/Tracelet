import 'package:flutter/material.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #268 — Geofence ENTER/EXIT flapping for a stationary device inside
/// the radius (high-accuracy mode).
///
/// A device sitting well inside a geofence emits repeated ENTER/EXIT events —
/// classic geofence "flapping"/dithering. The high-accuracy path evaluates
/// every raw GPS fix through the pure-Dart [GeofenceEvaluator]. The buggy
/// implementation used a single `distance <= radius` threshold for BOTH entry
/// and exit, so a stationary device whose fixes jitter across the boundary
/// toggled inside/outside on every update.
///
/// This card drives the REAL shipped [GeofenceEvaluator] with a scripted
/// sequence of fixes near the edge of a 100 m geofence (distances ~40, 96,
/// 104, 95, 106, 97, 103 m from the center — a motionless device with GPS
/// noise straddling the boundary). It reports what the actual SDK code does:
///
///   • BUGGY build → multiple ENTER/EXIT transitions (flapping) → FAILED,
///     which is how you manually confirm #268 exists.
///   • FIXED build → exactly one ENTER, zero EXIT → SUCCESS.
///
/// The fix adds exit hysteresis: the device ENTERs at the true radius but only
/// EXITs once it is farther than `radius + max(radius * 0.1, 20 m)`, so
/// boundary jitter no longer flips the state.
class Issue268Card extends StatefulWidget {
  const Issue268Card({super.key});

  @override
  State<Issue268Card> createState() => _Issue268CardState();
}

class _Issue268CardState extends State<Issue268Card>
    with IssueCardRun<Issue268Card> {
  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _run;

  Future<void> _run() async {
    setRunning(running: true);
    try {
      const centerLat = 37.4219983;
      const centerLng = -122.084;
      const radius = 100.0;

      final geofences = <Map<String, Object?>>[
        {
          'identifier': 'issue-268',
          'latitude': centerLat,
          'longitude': centerLng,
          'radius': radius,
        },
      ];

      // A stationary device near the edge with GPS jitter: an initial solid fix
      // inside, then fixes oscillating across the 100 m boundary but staying
      // within the fixed evaluator's hysteresis band (radius + 20 m = 120 m).
      const distances = <double>[40, 96, 104, 95, 106, 97, 103];

      final evaluator = GeofenceEvaluator();
      final log = StringBuffer();
      var enters = 0;
      var exits = 0;

      for (final d in distances) {
        // ~d meters due north of the center (1° lat ≈ 111_320 m).
        final pointLat = centerLat + d / 111320.0;
        final transitions = evaluator.evaluateProximity(
          latitude: pointLat,
          longitude: centerLng,
          geofences: geofences,
        );
        final actions = transitions.map((t) => t.action).join(', ');
        log.writeln(
          '~${d.toStringAsFixed(0)}m -> ${actions.isEmpty ? '(no change)' : actions}',
        );
        for (final t in transitions) {
          if (t.action == 'ENTER') enters++;
          if (t.action == 'EXIT') exits++;
        }
      }

      final total = enters + exits;
      final fixed = enters == 1 && exits == 0;

      if (fixed) {
        _set(
          '✅ SUCCESS (no flapping): a stationary device stayed INSIDE across '
          'all boundary jitter — $enters ENTER, $exits EXIT over '
          '${distances.length} fixes.\n\n'
          '$log\n'
          'The real GeofenceEvaluator held state via exit hysteresis. #268 is '
          'fixed on this build.',
        );
      } else {
        _set(
          '❌ FAILED — #268 REPRODUCED: the real GeofenceEvaluator flapped for '
          'a STATIONARY device: $enters ENTER / $exits EXIT ($total '
          'transitions) over ${distances.length} fixes.\n\n'
          '$log\n'
          'A device inside the radius should ENTER once and hold. Repeated '
          'ENTER/EXIT confirms the single-threshold check has no exit '
          'hysteresis.',
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
          'geofence flapping dithering enter exit stationary radius boundary '
          'hysteresis jitter high accuracy geofenceevaluator proximity',
      title:
          '#268: Geofence ENTER/EXIT flapping for a stationary device inside '
          'the radius',
      description:
          'Drives the real GeofenceEvaluator with a scripted sequence of fixes '
          'near the edge of a 100 m geofence (a motionless device with GPS '
          'noise straddling the boundary). On a buggy build it flaps (multiple '
          'ENTER/EXIT) so you can confirm #268 exists; on the fixed build it '
          'reports exactly one ENTER and no EXIT. Runs in-process; no '
          'permissions or device movement required.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
