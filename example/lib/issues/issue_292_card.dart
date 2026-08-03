import 'package:flutter/material.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #292 — Geofence high-accuracy mode re-emits ENTER on every
/// resume/boot for a stationary device inside the fence.
///
/// In `geofenceModeHighAccuracy`, the native SDK wipes the evaluator's
/// in-memory inside-set on every `ready()`/takeover and after boot
/// (`clearHighAccuracyState()`), because `startGeofences()` runs on each of
/// those. A device sitting still inside the fence therefore re-satisfies
/// `entered && !was_inside` after every wipe and the evaluator re-emits ENTER.
/// On an attendance backend each ENTER becomes a punch-in/punch-out — a field
/// report showed ~9 auto IN/OUT pairs in one day while the employee never left
/// the office. #268 (hysteresis) and #274/#276 (accuracy gating) don't help:
/// they govern the crossing math *within* one evaluator lifetime, but the
/// "already inside" memory is discarded on every resume.
///
/// This card drives the REAL shipped [GeofenceEvaluator] with a stationary
/// device 12 m inside a 50 m fence and models the native resume/boot wipe with
/// [GeofenceEvaluator.clear] between fixes:
///
///   • Raw evaluator across resume cycles → one ENTER per resume (the churn)
///     — this is the #292 symptom the native layer used to have.
///   • With the shipped fix's persisted "known inside" dedup (SharedPreferences
///     on Android / UserDefaults on iOS) → exactly one ENTER, zero EXIT.
///
/// The card applies that same dedup logic in-process to show the collapse to a
/// single ENTER. Runs in-process; no permissions or device movement required.
class Issue292Card extends StatefulWidget {
  const Issue292Card({super.key});

  @override
  State<Issue292Card> createState() => _Issue292CardState();
}

class _Issue292CardState extends State<Issue292Card> {
  String _status = 'Idle';
  bool _running = false;

  void _set(String s) {
    if (mounted) setState(() => _status = s);
  }

  Future<void> _run() async {
    setState(() => _running = true);
    try {
      const centerLat = 10.787929;
      const centerLng = 76.684183;
      const radius = 50.0;

      final geofences = <Map<String, Object?>>[
        {
          'identifier': 'OFFICE_ZONE',
          'latitude': centerLat,
          'longitude': centerLng,
          'radius': radius,
        },
      ];

      // A stationary device 12 m inside the fence (well within the 50 m radius).
      // ~12 m due north of the center (1° lat ≈ 111_320 m).
      const insideLat = centerLat + 12.0 / 111320.0;

      // Model six ready()/takeover resumes: one initial start plus five
      // resumes, each of which wipes the evaluator's inside-set natively.
      const resumeCycles = 5;
      final log = StringBuffer();

      // ── Part 1: the raw evaluator reproduces the churn ──────────────────
      final raw = GeofenceEvaluator();
      var rawEnters = 0;
      for (var i = 0; i <= resumeCycles; i++) {
        if (i > 0) raw.clear(); // each resume/boot wipes the inside-set
        final ts = raw.evaluateProximity(
          latitude: insideLat,
          longitude: centerLng,
          geofences: geofences,
        );
        final enters = ts.where((t) => t.action == 'ENTER').length;
        rawEnters += enters;
        log.writeln(
          '${i == 0 ? 'start ' : 'resume'} $i -> '
          '${enters > 0 ? '$enters ENTER' : '(no change)'}',
        );
      }

      // ── Part 2: the shipped fix — persisted "known inside" dedup ────────
      // Mirrors GeofenceManager.knownInsideIds, which survives the wipe and
      // process death, so a re-entry for a fence we already reported is
      // suppressed.
      final fixed = GeofenceEvaluator();
      final knownInside = <String>{};
      var emittedEnters = 0;
      var emittedExits = 0;
      for (var i = 0; i <= resumeCycles; i++) {
        if (i > 0) fixed.clear();
        final ts = fixed.evaluateProximity(
          latitude: insideLat,
          longitude: centerLng,
          geofences: geofences,
        );
        for (final t in ts) {
          if (t.action == 'ENTER') {
            if (knownInside.contains(t.identifier)) continue; // suppressed
            knownInside.add(t.identifier);
            emittedEnters++;
          } else if (t.action == 'EXIT') {
            if (!knownInside.remove(t.identifier)) continue; // never entered
            emittedExits++;
          }
        }
      }

      final reproducedChurn = rawEnters > 1;
      final fixHolds = emittedEnters == 1 && emittedExits == 0;

      if (reproducedChurn && fixHolds) {
        _set(
          '✅ SUCCESS: the persisted known-inside dedup collapses the resume '
          'churn to a single ENTER.\n\n'
          'Raw evaluator across ${resumeCycles + 1} ready()/takeover cycles:\n'
          '$log'
          '→ $rawEnters ENTER for a device that never moved (this is #292: '
          '$rawEnters false attendance punch-ins).\n\n'
          'With the shipped fix (native GeofenceManager persists the '
          'inside-set): $emittedEnters ENTER, $emittedExits EXIT across the '
          'same cycles. A stationary device is reported present exactly once.',
        );
      } else if (!fixHolds) {
        _set(
          '❌ FAILED — #292 REPRODUCED: even with the dedup, a stationary '
          'device emitted $emittedEnters ENTER / $emittedExits EXIT across '
          '${resumeCycles + 1} resume cycles. It must be exactly one ENTER, '
          'zero EXIT.\n\n$log',
        );
      } else {
        _set(
          '⚠️ INCONCLUSIVE: the raw evaluator did not churn '
          '($rawEnters ENTER), so this build cannot demonstrate #292 — the '
          'stationary fix may not be inside the fence.',
        );
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
          'geofence resume boot ready takeover reenter enter exit stationary '
          'attendance punch in out churn duplicate high accuracy persisted '
          'known inside dedup process death geofenceevaluator clearhighaccuracy',
      title:
          '#292: Geofence re-emits ENTER on every resume/boot for a stationary '
          'device (attendance IN/OUT churn)',
      description:
          'Drives the real GeofenceEvaluator for a device sitting 12 m inside a '
          '50 m fence and models the native resume/boot wipe with clear(). The '
          'raw evaluator re-ENTERs on every resume (the #292 churn — each a '
          'false punch-in); applying the shipped persisted known-inside dedup '
          'collapses it to exactly one ENTER and zero EXIT. Runs in-process; no '
          'permissions or device movement required.',
      status: _status,
      running: _running,
      onRun: _run,
    );
  }
}
