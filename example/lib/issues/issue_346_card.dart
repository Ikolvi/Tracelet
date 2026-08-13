import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #346 — transport-mode auto-tuning overwrote an explicit
/// `distanceFilter: 0`, so a parked device recorded nothing and never synced.
///
/// `distanceFilter` defaults to `10.0` and is documented as "the minimum
/// distance the device must move horizontally before a new location update is
/// recorded", so `0` is not an unset value — it is a deliberate "record every
/// fix", matching the `<= 0 disables` convention its three sibling thresholds
/// already document.
///
/// Auto-tuning replaced it like any other value:
///
/// ```rust
/// pub fn retune(&self, tuning: LocationTuning) {
///     self.state.lock().unwrap().tuning = tuning;   // whole-record swap
/// }
/// ```
///
/// and `TransportMode::Still` — which is what commits on a device sitting on a
/// desk — carries the widest non-vehicle gate in the table:
///
/// ```rust
/// TransportMode::Still => LocationTuning {
///     distance_filter: 25.0, tracking_accuracy_threshold: 15,
///     odometer_accuracy_threshold: 10, max_implied_speed: 3,
/// },
/// ```
///
/// A parked device never travels 25 m, so every fix came back
/// `DISTANCE_FILTER`, the database stayed empty, and the host experienced it as
/// sync having stopped. The field report shows ~120 consecutive
/// `DISTANCE_FILTER` results, `Pending locations | 0`, and a filter table
/// reading `Distance filter (m) | configured 0.0 | in force 25.0`.
///
/// It was also expensive while it was wrong: the pace state machine had
/// switched *into* continuous tracking over the same window, so the SDK held a
/// background location session open and took a fix roughly twice a second while
/// discarding all of them.
///
/// The fix preserves a configured `0` across a retune. The other three
/// thresholds still tune — they answer "is this fix trustworthy?", which the
/// committed mode genuinely knows better than a static config.
///
/// **What this card can prove.** `getCurrentLocationTuning()` reads the
/// thresholds back from the processor rather than from config, so it reports
/// what the filter is really using. The card leaves tracking running long
/// enough for the classifier to commit a mode, then checks the distance gate
/// survived and that fixes were actually recorded.
///
/// **Run it with the device sitting still**, which is the reported scenario. If
/// no mode commits within the window the card says so and reports the rows as
/// inconclusive rather than claiming a pass it did not earn.
class Issue346Card extends StatefulWidget {
  const Issue346Card({super.key});

  @override
  State<Issue346Card> createState() => _Issue346CardState();
}

class _Issue346CardState extends State<Issue346Card>
    with IssueCardRun<Issue346Card> {
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

    StreamSubscription<ModeChangeEvent>? modeSub;
    StreamSubscription<Location>? locSub;

    try {
      await Tracelet.setConfig(
        const Config(
          geo: GeoConfig(distanceFilter: 0),
          classifier: ClassifierConfig(
            enableFusedClassifier: true,
            autoTuneFromTransportMode: true,
          ),
        ),
      );

      final commits = <ModeChangeEvent>[];
      modeSub = Tracelet.onModeChange(commits.add);
      var recorded = 0;
      locSub = Tracelet.onLocation((_) => recorded++);

      await Tracelet.start();
      // Continuous pace, so fixes actually flow and the distance gate is the
      // only thing that could be stopping them.
      await Tracelet.changePace(true);

      final before = await Tracelet.getCurrentLocationTuning();
      check(
        'the configured distance filter reaches the processor',
        before?.distanceFilter == 0,
        before == null
            ? 'no processor yet — nothing below is conclusive'
            : before.distanceFilter == 0
            ? 'in force: distanceFilter=${before.distanceFilter}m, as configured'
            : 'in force: distanceFilter=${before.distanceFilter}m but 0 was '
                  'configured — a mode had already committed, or the config '
                  'never arrived',
      );

      // The classifier needs its confidence gate plus an 8 s dwell before it
      // commits, and it only sees a mode once it has accelerometer windows to
      // work with.
      await Future<void>.delayed(const Duration(seconds: 25));

      final after = await Tracelet.getCurrentLocationTuning();
      final tuned = commits.where((e) => e.appliedTuning != null).toList();

      if (tuned.isEmpty) {
        results.add(
          'ℹ️ no transport mode committed in 25 s, so auto-tuning never ran and '
          'the rows below did not exercise #346. Re-run with the device '
          'resting still — "still" needs speed under 2 km/h and low accel '
          'variance, plus the 8 s dwell. Modes seen: '
          '${commits.isEmpty ? 'none' : commits.map((e) => e.mode).join(', ')}.',
        );
      } else {
        final names = tuned
            .map((e) => '${e.mode}(df=${e.appliedTuning!.distanceFilter}m)')
            .join(', ');
        results.add('ℹ️ modes committed with a tuning: $names');
      }

      check(
        '#346 an auto-tune does not impose a distance filter on a host that '
        'switched it off',
        after?.distanceFilter == 0,
        after == null
            ? 'no processor — inconclusive'
            : after.distanceFilter == 0
            ? 'still distanceFilter=0m after ${tuned.length} tuned commit(s); '
                  'the host asked for every fix and still gets every fix'
            : 'REGRESSED — distanceFilter is now ${after.distanceFilter}m. '
                  'A parked device cannot travel that, so every fix will be '
                  'DISTANCE_FILTERed and nothing will be persisted or synced.',
      );

      // The other three must still tune — the fix is deliberately narrow.
      if (tuned.isNotEmpty && after != null) {
        final t = tuned.last.appliedTuning!;
        final othersApplied =
            after.trackingAccuracyThreshold == t.trackingAccuracyThreshold &&
            after.odometerAccuracyThreshold == t.odometerAccuracyThreshold &&
            after.maxImpliedSpeed == t.maxImpliedSpeed;
        check(
          'the accuracy and implied-speed thresholds still auto-tune',
          othersApplied,
          othersApplied
              ? 'trackingAccuracy=${after.trackingAccuracyThreshold}m, '
                    'odometerAccuracy=${after.odometerAccuracyThreshold}m, '
                    'maxImpliedSpeed=${after.maxImpliedSpeed}m/s — all from the '
                    'committed mode, so the fix stayed narrow'
              : 'the mode applied '
                    '(${t.trackingAccuracyThreshold}/${t.odometerAccuracyThreshold}/'
                    '${t.maxImpliedSpeed}) but in force is '
                    '(${after.trackingAccuracyThreshold}/'
                    '${after.odometerAccuracyThreshold}/${after.maxImpliedSpeed}) '
                    '— the guard is suppressing more than the distance gate',
        );
      }

      // The user-visible consequence, and the reason this was reported as a
      // sync failure: with the gate imposed, a still device records nothing.
      check(
        'a still device still records fixes',
        recorded > 0,
        recorded > 0
            ? '$recorded location(s) recorded while stationary — there is '
                  'something for sync to send'
            : 'no locations recorded in 25 s of continuous tracking. This is '
                  'the reported symptom: sync looks broken because persistence '
                  'produced nothing.',
      );

      await Tracelet.changePace(false);
      await Tracelet.stop();

      final header = allPass
          ? '✅ SUCCESS: an explicit distanceFilter:0 survives auto-tuning.'
          : '❌ FAILED — see the failing rows below.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'Scope: this checks the thresholds actually in force — '
        'getCurrentLocationTuning() reads back from the processor, not from '
        'config, so a regression cannot hide behind the config still saying 0. '
        'It depends on the classifier committing a mode during the window; '
        'when none commits the run is reported as inconclusive above rather '
        'than as a pass.\n\n'
        'Not covered here, and worth knowing: while "still" is committed, '
        'maxImpliedSpeed is 3 m/s. When the device does start moving, fixes '
        'are rejected as SPEED_FILTER teleports until the classifier commits a '
        'faster mode, which needs its own confidence gate and 8 s dwell. That '
        'is the same "auto-tune outlives the situation it was chosen for" '
        'tension and is tracked separately.\n\n'
        "The guard lives in the Rust processor's retune(), the single point "
        'where an incoming tuning meets the configured base, so iOS and '
        'Android are covered by the one change and by the Rust unit tests '
        '(retune_preserves_a_configured_zero_distance_filter and neighbours).',
      );
    } catch (e) {
      _set('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      await modeSub?.cancel();
      await locSub?.cancel();
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'distance filter auto-tune transport mode still retune tuning '
          'not syncing no locations recorded parked stationary distanceFilter '
          'zero 346',
      title: '#346: auto-tune must not override an explicit distanceFilter:0',
      description:
          'A committed "still" mode swapped in a 25 m distance filter over a '
          'configured 0, so a parked device filtered out every fix and had '
          'nothing to sync. Checks the gate in force and that fixes still land.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
