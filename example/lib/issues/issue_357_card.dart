import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #357 — a geofence added *after* `start()` must still get the fix
/// cadence it is decided from.
///
/// A fence the in-app evaluator owns (a polygon, or a circle under 100 m) is
/// decided from the raw fix stream, so #356 drops the OS distance filter to
/// give the evaluator a time-based cadence. That question was asked once, at
/// `start()` — and `start()` then `addGeofence()` is the ordinary order, so the
/// flag stayed false for the rest of the session. CoreLocation and the fused
/// provider kept gating deliveries at the configured `distanceFilter`, and the
/// evaluator was handed one fix per that many metres travelled. EXIT needs two
/// *consecutive* fixes beyond the hysteresis band, and a walker can cross that
/// band and be back inside between two deliveries — so EXIT fired late, or
/// never.
///
/// **This card measures the cadence directly, standing still.** It samples the
/// log twice over equal windows: once with no fence registered, and once with a
/// 10 m fence registered. A stationary device produces raw fixes only when the
/// distance gate is off, and every one of them is rejected for *persistence* by
/// the Rust processor's own filter — which is exactly the "filtered by Rust
/// processor" line each window counts. Before the fix both windows read zero;
/// after it, only the second fills up.
///
/// Nothing here needs you to walk: the bug is about which fixes the evaluator is
/// *offered*, and that is observable from a chair.
class Issue357Card extends StatefulWidget {
  const Issue357Card({super.key});

  @override
  State<Issue357Card> createState() => _Issue357CardState();
}

class _Issue357CardState extends State<Issue357Card> {
  String _status = 'Idle';
  bool _running = false;

  static const _fenceId = 'issue-357-cadence';
  static const _radiusMeters = 10.0;

  /// Long enough for a time-based cadence to produce several fixes, short
  /// enough that the card stays a card. Two of these windows run back to back.
  ///
  /// Sized for the slow side: Android's fused provider ramps from a cold GPS
  /// start — a device trace shows one fix every ~5 s for the first half-minute,
  /// reaching the requested 1 Hz only after that — so a 12 s window closed on
  /// two fixes and failed a run in which the stream had opened perfectly.
  static const _windowSeconds = 20;

  /// Fixes in the second window that count as "the stream is open".
  ///
  /// This is a presence check, not a rate measurement: the baseline window
  /// establishes what a gated stream looks like (zero), so any *sustained*
  /// delivery against that is the signal. Two rules out a lone heartbeat fix
  /// without assuming a cadence the provider does not promise while warming up.
  static const _minStreamFixes = 2;

  /// Emitted once per raw fix the persistence filter rejects — on both
  /// platforms, from the shared Rust processor.
  static const _rawFixMarker = 'filtered by Rust processor';

  /// Substring of the lifecycle line the SDK writes when the fence set changes
  /// what the location cadence has to be.
  static const _realignMarker = 'realigning the location cadence';

  void _set(String s) {
    if (mounted) setState(() => _status = s);
  }

  /// Highest log id currently stored — the window boundary.
  ///
  /// Ids rather than timestamps: they are monotonic and need no date parsing,
  /// so the count cannot be thrown off by a formatting difference between the
  /// two platforms.
  Future<int> _latestLogId() async {
    final logs = await Tracelet.getLogs(500);
    return logs.fold<int>(0, (max, e) => e.id > max ? e.id : max);
  }

  Future<int> _rawFixesSince(int sinceId) async {
    final logs = await Tracelet.getLogs(500);
    return logs
        .where((e) => e.id > sinceId && e.message.contains(_rawFixMarker))
        .length;
  }

  Future<bool> _logMatchesSince(int sinceId, String marker) async {
    final logs = await Tracelet.getLogs(500);
    return logs.any((e) => e.id > sinceId && e.message.contains(marker));
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
      await Tracelet.requestLocationAuthorization();
      await Tracelet.ready(
        const Config(
          // The measurement reads the log store, so the lines it counts have to
          // be written.
          logger: LoggerConfig(logLevel: LogLevel.verbose, debug: true),
        ),
      );
      // A fence left over from a previous run would make the first window
      // measure the wrong thing.
      await Tracelet.removeGeofences();
      await Tracelet.start();

      final startState = await Tracelet.getState();
      check(
        'tracking is running',
        startState.enabled,
        'enabled=${startState.enabled} trackingMode=${startState.trackingMode}',
      );

      // ── Window A: no fence registered ────────────────────────────────────
      _set(
        '1/2 — measuring the baseline cadence. Stand still for '
        '$_windowSeconds seconds…',
      );
      final beforeA = await _latestLogId();
      await Future<void>.delayed(const Duration(seconds: _windowSeconds));
      final windowA = await _rawFixesSince(beforeA);

      // ── Add the fence, then Window B ─────────────────────────────────────
      final here = await Tracelet.getCurrentPosition(
        desiredAccuracy: DesiredAccuracy.high,
        timeout: 30,
      );
      final beforeAdd = await _latestLogId();
      await Tracelet.addGeofence(
        Geofence(
          identifier: _fenceId,
          latitude: here.coords.latitude,
          longitude: here.coords.longitude,
          radius: _radiusMeters,
        ),
      );

      _set(
        '2/2 — a 10 m fence is registered. Keep standing still for '
        '$_windowSeconds more seconds…',
      );
      // The SDK announces the re-alignment on the always-on lifecycle channel.
      // Checking for it splits the two ways this card can fail: "the SDK never
      // re-asked who owns the fences" (the bug, or a build without the fix) from
      // "it re-asked and the platform still delivered nothing" (something else
      // is holding the stream down). Without this row a zero window means both.
      final realigned = await _logMatchesSince(beforeAdd, _realignMarker);

      final beforeB = await _latestLogId();
      await Future<void>.delayed(const Duration(seconds: _windowSeconds));
      final windowB = await _rawFixesSince(beforeB);

      final endState = await Tracelet.getState();

      // The stop-detector's own override also drops the distance gate, but only
      // while the SDK is in the *moving* state — and a fresh start() begins
      // stationary. If the device moved, the second window cannot be attributed
      // to the geofence path and the run proves nothing either way.
      final stayedStill = !startState.isMoving && !endState.isMoving;
      check(
        'the device stayed stationary, so the windows are comparable',
        stayedStill,
        stayedStill
            ? 'isMoving=false throughout — the only thing that can open the '
                  'stream here is the geofence cadence'
            : 'isMoving flipped to true, which lets the stop-timeout override '
                  'open the stream on its own — INCONCLUSIVE, re-run without '
                  'moving the device',
      );

      check(
        'with no fence, the configured distance filter gates the stream',
        windowA <= 2,
        '$windowA raw fixes in ${_windowSeconds}s — a stationary device should '
            'be delivered almost nothing while the filter is in force',
      );

      check(
        'the SDK re-asked who owns the fences when the fence was added',
        realigned,
        realigned
            ? 'the lifecycle channel carries the re-alignment for this add'
            : 'no "$_realignMarker" entry — the SDK never revisited the cadence. '
                  'Either this build predates the fix (rebuild the app), or the '
                  'fence is not evaluator-owned in this configuration',
      );

      check(
        'adding a 10 m fence opens the stream the evaluator is decided from',
        stayedStill && windowB >= _minStreamFixes && windowB > windowA,
        '$windowB raw fixes in ${_windowSeconds}s after the fence was added '
            '(baseline $windowA, need $_minStreamFixes). '
            '${realigned ? 'The cadence WAS re-aligned, so a zero here is not the '
                      '#357 bug — something else is holding the stream down '
                      '(check the provider and any power throttling).' : 'Before this fix the flag was only computed at start(), so this '
                      'window reads the same as the baseline and the evaluator '
                      'sees one fix per distanceFilter metres travelled.'}',
      );

      final header = allPass
          ? '✅ PASS: the fence set now drives the location cadence.'
          : '❌ FAILED — see the rows below.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'What this measures: a fence under ~100 m cannot be resolved by '
        'CoreLocation or Play Services, so Tracelet decides it in-app from the '
        'raw fix stream. That stream is only time-based while the SDK knows '
        'such a fence exists. It learned that at start() and never again, so a '
        'fence added afterwards — the ordinary order — was evaluated against a '
        'stream still gated at distanceFilter metres.\n\n'
        'Why it looked intermittent in the field: the stop-detector drops the '
        'same gate whenever it starts its countdown, so a device that stands '
        'still gets a healthy 1 Hz stream and crossings look fine. Walk, and '
        'the countdown is cancelled, the gate returns, and the evaluator goes '
        'blind exactly while the boundary is being crossed.\n\n'
        'Cleanup: the fence "$_fenceId" is left registered so you can walk the '
        'crossing manually if you want to; use "Remove Geofences" on the main '
        'tab to clear it.',
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
          'geofence cadence distance filter starvation addGeofence after start '
          'EXIT late in-app evaluator sub-100m small radius stop timeout '
          'override time-based delivery 357',
      title: '#357: a geofence added after start() still gets its fix stream',
      description:
          'Measures the raw fix cadence over two equal windows while you stand '
          'still — once with no fence, once with a 10 m fence — and shows that '
          'registering the fence is what opens the stream it is decided from. '
          'Previously the SDK settled that question at start() and never '
          'revisited it, so a fence added afterwards was judged from one fix '
          'per distanceFilter metres travelled and EXIT fired late or never.',
      status: _status,
      running: _running,
      onRun: _run,
    );
  }
}
