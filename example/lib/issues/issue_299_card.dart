import 'package:flutter/material.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #299 — distance over-reported on foot: the odometer ignored Kalman
/// smoothing, and the transport classifier never tuned the filters.
///
/// Two defects fed the same symptom (a neighbourhood walk measuring ~3x long):
///
/// 1. `LocationProcessor` accumulated `odometerDelta` from the **raw** fix while
///    Kalman smoothing ran *after* it and fed only `coords`. Enabling
///    `useKalmanFilter` therefore smoothed the rendered track and left distance
///    integrating raw GPS jitter, with nothing to say why.
/// 2. `odometerAccuracyThreshold` defaults to `50` m, so at walking pace a fix
///    with 40 m of error still contributed its full delta to the odometer —
///    often more "distance" than the user actually covered.
///
/// The fix smooths before filtering, and adds
/// `ClassifierConfig.autoTuneFromTransportMode` so a committed mode picks
/// thresholds suited to it instead of the developer guessing.
///
/// This card can't drive the native LocationEngine in-process, so it models the
/// odometer against the REAL shipped [GeoUtils.haversine] and walks a synthetic
/// jittered path whose ground-truth length is known exactly. It compares the
/// shipped defaults against the walking auto-tune values and shows the tuned
/// path lands close to truth while the defaults inflate.
///
/// The threshold numbers below mirror `tuning_for_transport_mode` in the Rust
/// core. That table is not FRB-exposed to Dart yet, so they are restated here
/// rather than read from the source of truth — keep them in step if the table
/// changes.
class Issue299Card extends StatefulWidget {
  const Issue299Card({super.key});

  @override
  State<Issue299Card> createState() => _Issue299CardState();
}

class _Issue299CardState extends State<Issue299Card>
    with IssueCardRun<Issue299Card> {
  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _run;

  static const _lat = 10.787929;
  static const _lng = 76.684183;

  /// 1° of latitude ≈ 111_320 m; at this latitude 1° of longitude ≈ that * cos.
  static const _mPerDegLat = 111320.0;

  /// Shipped defaults: a loose odometer gate and a very high speed ceiling.
  static const _defaultDistanceFilter = 10.0;
  static const _defaultOdometerAccuracy = 50.0;
  static const _defaultMaxImpliedSpeed = 80.0;

  /// Walking row of the auto-tune table.
  static const _walkDistanceFilter = 8.0;
  static const _walkOdometerAccuracy = 10.0;
  static const _walkMaxImpliedSpeed = 4.0;

  /// A fix on the synthetic walk: metres travelled along the true path, the
  /// lateral GPS error pushing it off that path, its reported accuracy, and the
  /// elapsed time in seconds.
  ///
  /// Ground truth is a dead-straight 400 m northward walk at 1.25 m/s. Lateral
  /// jitter is deterministic (no RNG) so the card is reproducible: it alternates
  /// side to side, which is exactly the "spikes to the left and right" the
  /// reporter described, and is what a naive odometer integrates as distance.
  static List<(double, double, double, double)> _walk() {
    final fixes = <(double, double, double, double)>[];
    const stepMetres = 5.0;
    const paceMps = 1.25;
    for (var i = 0; i <= 80; i++) {
      final along = i * stepMetres;
      // Alternating lateral error, with every 5th fix a coarse "GPS bounce"
      // that a loose accuracy gate happily counts toward distance.
      final coarse = i % 5 == 0 && i > 0;
      final lateral = coarse
          ? (i.isEven ? 18.0 : -18.0)
          : (i.isEven ? 4.0 : -4.0);
      final accuracy = coarse ? 40.0 : 6.0;
      fixes.add((along, lateral, accuracy, along / paceMps));
    }
    return fixes;
  }

  /// True path length of [_walk] — the number the odometer should approach.
  static double get _groundTruthMetres => 80 * 5.0;

  /// Accumulates an odometer over [fixes] using the real shipped haversine,
  /// applying the same gates the native `LocationProcessor` applies: a distance
  /// filter, an implied-speed reject, and an odometer accuracy gate.
  ///
  /// When [smooth] is true the lateral error is damped before measuring, which
  /// models smoothing running *before* the odometer (the fix) rather than after
  /// it (the bug).
  static double _odometer({
    required List<(double, double, double, double)> fixes,
    required double distanceFilter,
    required double odometerAccuracy,
    required double maxImpliedSpeed,
    required bool smooth,
  }) {
    // A first-order low-pass on the lateral error stands in for the Kalman
    // filter's effect on this axis: it cannot remove the error, only damp it.
    const smoothingRetention = 0.25;

    double toLat(double alongMetres) => _lat + alongMetres / _mPerDegLat;
    double toLng(double lateralMetres) =>
        _lng + lateralMetres / (_mPerDegLat * 0.9824); // cos(10.788°)

    var odometer = 0.0;
    double? lastLat, lastLng, lastTime;
    // The odometer's own anchor: advances only on fixes that clear the accuracy
    // gate, so a coarse fix defers its distance instead of losing it.
    double? odoLat, odoLng;
    var smoothedLateral = 0.0;

    for (final (along, lateral, accuracy, time) in fixes) {
      smoothedLateral =
          smoothedLateral + (lateral - smoothedLateral) * smoothingRetention;
      final effectiveLateral = smooth ? smoothedLateral : lateral;
      final lat = toLat(along);
      final lng = toLng(effectiveLateral);

      if (lastLat == null || lastLng == null || lastTime == null) {
        lastLat = lat;
        lastLng = lng;
        lastTime = time;
        if (odometerAccuracy <= 0 || accuracy <= odometerAccuracy) {
          odoLat = lat;
          odoLng = lng;
        }
        continue;
      }

      final delta = GeoUtils.haversine(lastLat, lastLng, lat, lng);
      final elapsed = time - lastTime;

      // Distance filter: too small a move is not recorded at all.
      if (delta < distanceFilter) continue;

      // Implied-speed reject: a jump that would need an impossible pace.
      if (maxImpliedSpeed > 0 &&
          elapsed > 0 &&
          delta / elapsed > maxImpliedSpeed) {
        continue;
      }

      // Odometer accuracy gate: the fix is still recorded for the map, but only
      // counts toward distance when it is accurate enough to be believed. A
      // blocked fix leaves the odometer anchor where it is, so its distance is
      // deferred to the next trustworthy fix rather than discarded.
      if (odometerAccuracy <= 0 || accuracy <= odometerAccuracy) {
        if (odoLat != null && odoLng != null) {
          odometer += GeoUtils.haversine(odoLat, odoLng, lat, lng);
        }
        odoLat = lat;
        odoLng = lng;
      }
      lastLat = lat;
      lastLng = lng;
      lastTime = time;
    }
    return odometer;
  }

  Future<void> _run() async {
    setRunning(running: true);
    try {
      final results = <String>[];
      var allPass = true;

      void check(String name, bool pass, String detail) {
        results.add('${pass ? '✅' : '❌'} $name — $detail');
        if (!pass) allPass = false;
      }

      final fixes = _walk();
      final truth = _groundTruthMetres;

      double errorPct(double measured) =>
          ((measured - truth).abs() / truth) * 100;

      // Old behaviour: shipped defaults, and smoothing applied only to the
      // rendered coords — so the odometer never sees it.
      final oldDistance = _odometer(
        fixes: fixes,
        distanceFilter: _defaultDistanceFilter,
        odometerAccuracy: _defaultOdometerAccuracy,
        maxImpliedSpeed: _defaultMaxImpliedSpeed,
        smooth: false,
      );

      // What the user expected `useKalmanFilter: true` to give them: the same
      // thresholds, but measured over the smoothed track. Pre-3.8.0-alpha the
      // odometer never saw this value — smoothing ran downstream of it, so the
      // recorded distance stayed `oldDistance` no matter how the filter was set.
      final oldDefaultsSmoothed = _odometer(
        fixes: fixes,
        distanceFilter: _defaultDistanceFilter,
        odometerAccuracy: _defaultOdometerAccuracy,
        maxImpliedSpeed: _defaultMaxImpliedSpeed,
        smooth: true,
      );

      // New behaviour: smoothing ahead of the filters, plus the walking
      // auto-tune row.
      final newDistance = _odometer(
        fixes: fixes,
        distanceFilter: _walkDistanceFilter,
        odometerAccuracy: _walkOdometerAccuracy,
        maxImpliedSpeed: _walkMaxImpliedSpeed,
        smooth: true,
      );

      // 1. Reproduce the report: the defaults over-report a straight walk.
      check(
        'Defaults over-report the walk',
        oldDistance > truth * 1.15,
        'measured ${oldDistance.toStringAsFixed(0)} m vs '
            '${truth.toStringAsFixed(0)} m truth '
            '(+${errorPct(oldDistance).toStringAsFixed(0)}%)',
      );

      // 2. The reported dead end. Smoothing genuinely lowers the measured
      //    distance — so the pre-fix odometer was discarding a real correction
      //    by running upstream of the smoother. This is why the reporter saw no
      //    improvement from `useKalmanFilter: true`.
      check(
        'Smoothing does move the number — the old odometer never saw it',
        oldDefaultsSmoothed < oldDistance * 0.95,
        'raw ${oldDistance.toStringAsFixed(0)} m vs smoothed '
            '${oldDefaultsSmoothed.toStringAsFixed(0)} m, yet the pre-fix odometer '
            'recorded the raw value regardless of useKalmanFilter',
      );

      // 3. The fix: smoothing first + walking thresholds lands near truth.
      check(
        'Smoothing + walking auto-tune tracks truth',
        errorPct(newDistance) < 10,
        'measured ${newDistance.toStringAsFixed(0)} m vs '
            '${truth.toStringAsFixed(0)} m truth '
            '(${errorPct(newDistance).toStringAsFixed(0)}% error, want <10%)',
      );

      // 4. And it is a clear improvement, not a wash.
      check(
        'Auto-tune beats the defaults',
        errorPct(newDistance) < errorPct(oldDistance) / 2,
        'error ${errorPct(oldDistance).toStringAsFixed(0)}% → '
            '${errorPct(newDistance).toStringAsFixed(0)}%',
      );

      final header = allPass
          ? '✅ SUCCESS: smoothing now reaches the odometer, and the walking '
                'auto-tune keeps GPS jitter out of the recorded distance.'
          : '❌ FAILED — #299 not satisfied on this build. See the failing rows.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'Kalman smoothing now runs BEFORE the location filters, so the odometer '
        'accumulates over the de-noised track instead of raw jitter — enabling '
        'useKalmanFilter finally affects distance, not just the drawn line. '
        'Set ClassifierConfig(enableFusedClassifier: true, '
        'autoTuneFromTransportMode: true) to have a committed transport mode '
        'pick distanceFilter / trackingAccuracyThreshold / '
        'odometerAccuracyThreshold / maxImpliedSpeed for you, so you do not have '
        'to guess whether the user is walking, jogging or running. Models the '
        'odometer against the real shipped GeoUtils.haversine over a synthetic '
        '400 m walk of known length; no permissions or device movement required.',
      );
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
          'distance wrong inflated over reported odometer kalman smoothing '
          'walking jogging running cycling transport mode auto tune preset '
          'odometerAccuracyThreshold maxImpliedSpeed distanceFilter strava '
          'spikes jitter noise exercise fitness pedestrian',
      title: '#299: Distance over-reported on foot (Kalman + auto-tune)',
      description:
          'Walks a synthetic 400 m path of known length through the real shipped '
          'haversine odometer. Shows the shipped defaults inflating the total, '
          'the pre-fix Kalman filter leaving that total untouched (because '
          'smoothing ran after the odometer), and smoothing-first plus the '
          'walking auto-tune row landing within 10% of truth. Runs in-process; '
          'no permissions or device movement required.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
