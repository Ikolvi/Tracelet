import 'package:flutter/material.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #297 — high-accuracy geofence ENTER/EXIT intermittently not firing
/// (location starvation on stable providers).
///
/// In `geofenceModeHighAccuracy` the crossing evaluator is fed from the location
/// stream. But the tracking **distance filter** — which exists to keep
/// *persistence* volume down — was also gating the fixes that reached the
/// evaluator. A device standing still on a stable provider (GMS Fused / iOS
/// CoreLocation with a distance filter) produces fixes the filter drops, so the
/// evaluator was starved and transitions were silently missed. The #294 two-fix
/// EXIT confirmation makes this strictly worse: it needs two consecutive
/// out-of-fence fixes, and the second (a stationary duplicate) is exactly what
/// the distance filter throws away.
///
/// The fix decouples crossing evaluation from persistence: crossings evaluate on
/// the **raw** fix stream, while persistence keeps its distance filter (so
/// stored/synced volume is unchanged).
///
/// This card can't drive the native LocationEngine in-process, so it models the
/// persistence distance filter in Dart and runs the SAME raw fix stream through
/// the REAL shipped [GeofenceEvaluator] two ways — **starved** (old: evaluate
/// only fixes that survive the filter) vs **fed** (new: evaluate every raw fix)
/// — and shows the starved path misses the EXIT the fed path catches, while the
/// set of *persisted* fixes is identical either way.
class Issue297Card extends StatefulWidget {
  const Issue297Card({super.key});

  @override
  State<Issue297Card> createState() => _Issue297CardState();
}

class _Issue297CardState extends State<Issue297Card> {
  String _status = 'Idle';
  bool _running = false;

  void _set(String s) {
    if (mounted) setState(() => _status = s);
  }

  static const _lat = 10.787929;
  static const _lng = 76.684183;
  static const _radius =
      50.0; // exit threshold = radius + max(radius*0.1, 20) = 70 m
  static const _distanceFilter = 10.0; // tracking/persistence distance filter

  final _geofences = <Map<String, Object?>>[
    {
      'identifier': 'OFFICE',
      'latitude': _lat,
      'longitude': _lng,
      'radius': _radius,
    },
  ];

  /// ~[meters] north of the office centre (1° lat ≈ 111_320 m).
  double _north(double meters) => _lat + meters / 111320.0;

  /// Approx. metres between two north-offset fixes.
  double _gap(double a, double b) => (a - b).abs();

  /// Runs a raw stream of (metresNorth, accuracy) fixes and returns
  /// (enters, exits, persistedCount).
  ///
  /// When [feedEveryRawFix] is false this models the pre-fix behaviour: the
  /// evaluator only sees fixes that survive the persistence distance filter.
  /// When true it models the fix: every raw fix is evaluated, while persistence
  /// still applies the filter (so [persistedCount] is identical either way).
  (int, int, int) _run1({
    required List<(double, double)> raw,
    required bool feedEveryRawFix,
  }) {
    final ev = GeofenceEvaluator();
    var enters = 0, exits = 0, persisted = 0;
    double? lastPersistedMeters;

    for (final (meters, acc) in raw) {
      // The persistence distance filter: accept the first fix, then only fixes
      // that moved at least the distance filter from the last accepted one.
      final accepted =
          lastPersistedMeters == null ||
          _gap(meters, lastPersistedMeters) >= _distanceFilter;
      if (accepted) {
        persisted++;
        lastPersistedMeters = meters;
      }

      // Crossing evaluation: every raw fix (fixed) vs accepted-only (starved).
      if (feedEveryRawFix || accepted) {
        final ts = ev.evaluateProximity(
          latitude: _north(meters),
          longitude: _lng,
          accuracy: acc,
          geofences: _geofences,
        );
        enters += ts.where((t) => t.action == 'ENTER').length;
        exits += ts.where((t) => t.action == 'EXIT').length;
      }
    }
    return (enters, exits, persisted);
  }

  Future<void> _run() async {
    setState(() => _running = true);
    try {
      final results = <String>[];
      var allPass = true;

      void check(String name, bool pass, String detail) {
        results.add('${pass ? '✅' : '❌'} $name — $detail');
        if (!pass) allPass = false;
      }

      // Scenario: arrive at the office, then walk out and stand still. The two
      // trailing out-of-fence fixes are a stationary duplicate — the second is
      // exactly what a distance filter drops, and exactly what the #294
      // confirmation needs to fire the EXIT.
      const raw = <(double, double)>[
        (8, 5), // arrival — ENTER
        (120, 8), // walked out (moved >10 m → persisted)
        (120, 8), // standing still outside (duplicate → filtered)
        (121, 8), // standing still outside (duplicate → filtered)
      ];

      final (starvedEnter, starvedExit, starvedPersist) = _run1(
        raw: raw,
        feedEveryRawFix: false,
      );
      final (fedEnter, fedExit, fedPersist) = _run1(
        raw: raw,
        feedEveryRawFix: true,
      );

      // 1. Reproduce the bug: the starved (old) path never confirms the EXIT,
      //    because the stationary duplicate that would confirm it was filtered.
      check(
        'Old (starved) path reproduces the miss',
        starvedEnter == 1 && starvedExit == 0,
        '$starvedEnter ENTER / $starvedExit EXIT (want 1/0 — EXIT missed)',
      );

      // 2. The fix: feeding every raw fix confirms the departure — exactly one
      //    EXIT.
      check(
        'New (raw-stream) path fires the EXIT',
        fedEnter == 1 && fedExit == 1,
        '$fedEnter ENTER / $fedExit EXIT (want 1/1)',
      );

      // 3. Persistence is unchanged: the distance filter still gates what gets
      //    stored/synced, so the persisted count is identical either way — the
      //    fix does not inflate location volume.
      check(
        'Persistence volume unchanged',
        starvedPersist == fedPersist && fedPersist == 2,
        'persisted old=$starvedPersist / new=$fedPersist (want equal, =2)',
      );

      final header = allPass
          ? '✅ SUCCESS: the raw-stream evaluation catches the EXIT the distance '
                'filter used to starve, and persisted volume is unchanged.'
          : '❌ FAILED — #297 not satisfied on this build. See the failing rows.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'In high-accuracy geofence mode the crossing evaluator is now fed every '
        'raw fix (and the provider is requested with time-based delivery), so a '
        'stationary device is no longer starved of ENTER/EXIT transitions. The '
        'tracking distance filter still applies to persistence, so stored/synced '
        'volume is unchanged. Runs in-process against the real GeofenceEvaluator; '
        'no permissions or device movement required.',
      );
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
          'geofence enter exit not firing missing starvation stationary '
          'distance filter fused location provider corelocation high accuracy '
          'time based delivery raw stream attendance geofenceevaluator',
      title:
          '#297: High-accuracy geofence ENTER/EXIT intermittently not firing',
      description:
          'Models the tracking distance filter and runs the same raw fix stream '
          'through the real GeofenceEvaluator two ways: the old starved path '
          '(evaluate only filtered fixes) misses the EXIT, while the fixed '
          'raw-stream path fires exactly one EXIT — and the persisted fix count '
          'is identical, so location volume is unchanged. Runs in-process; no '
          'permissions or device movement required.',
      status: _status,
      running: _running,
      onRun: _run,
    );
  }
}
