import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tracelet/tracelet.dart' as tl;
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #288 — the pace never leaves MOVING in smart motion mode.
///
/// Three defects combined to strand a still device in MOVING:
///
/// 1. `SpeedMotionManager` treated a *single* GPS fix at or above
///    `speedMovingThreshold` as "moving again", cancelling the SLOWING countdown
///    and restarting the whole `speedStationaryDelay` window. GPS speed is noisy
///    on a stationary device — an isolated `1.56 m/s` blip amid a stream of
///    `0.00 m/s` fixes was enough — so the countdown could restart forever.
/// 2. The Rust coordinator starts with `is_accel_moving = false` and ignores an
///    unchanged flag, and `start()` never seeded it, so the accelerometer's
///    stop-timeout could not contribute to a stationary decision and could not
///    compensate for (1).
/// 3. (Android) the coordinator's tracking mode was only synced in
///    `initialize()` from the *persisted* mode, so a session that ended
///    stationary left it unable to switch again at all.
///
/// Manual `changePace(false)` always worked because it sets both coordinator
/// flags — which is exactly why this looked like a dead automatic path.
///
/// This card observes the real pipeline rather than poking at internals: it
/// watches the speed state machine (`onSpeedMotionChange`) and the pace
/// (`onMotionChange`) and times how long a still device takes to reach
/// STATIONARY. That is the user-visible symptom, and the transition timeline it
/// prints distinguishes the three defects from each other.
///
/// **Put the phone on a desk and do not touch it while this runs.** The example
/// app sets `shakeThreshold: 2` (below Android's 2.5 default), so picking it up
/// re-declares MOVING and restarts the countdown — correctly, since the device
/// really moved.
class Issue288Card extends StatefulWidget {
  const Issue288Card({super.key});

  @override
  State<Issue288Card> createState() => _Issue288CardState();
}

class _Issue288CardState extends State<Issue288Card> {
  static const _debug = MethodChannel('com.tracelet/debug');

  String _status = 'Idle';
  bool _running = false;

  StreamSubscription<tl.SpeedMotionEvent>? _speedSub;
  StreamSubscription<tl.Location>? _paceSub;
  Timer? _ticker;

  void _set(String s) {
    if (mounted) setState(() => _status = s);
  }

  @override
  void dispose() {
    _speedSub?.cancel();
    _paceSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _test() async {
    if (_running) return;
    setState(() => _running = true);

    final timeline = <String>[];
    var slowingToMovingFlips = 0;
    var enteredSlowing = false;
    var speedReachedStationary = false;
    final stopwatch = Stopwatch()..start();
    final done = Completer<bool>();

    String at() =>
        '${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s';

    try {
      final state = await tl.Tracelet.getState();
      if (!state.enabled) {
        _set(
          'ℹ️ Tracking is not running. Press Start first, let the pace settle '
          'into MOVING, put the phone down, then run this again.',
        );
        return;
      }

      final motion = tl.Tracelet.activeConfig.motion;
      final delaySeconds = motion.speedStationaryDelay;
      // The speed machine needs its countdown plus a margin for fix cadence; the
      // accelerometer path needs stopTimeout minutes. Budget the shorter of the
      // two paths, since either one reaching STATIONARY is a pass.
      final budget = Duration(seconds: (delaySeconds + 20).clamp(20, 150));

      if (!state.isMoving) {
        _set(
          'ℹ️ The pace is already STATIONARY, so there is nothing to observe. '
          'Move around (or tap "Pace → Move") until it reports MOVING, put the '
          'phone down, then run this again.',
        );
        return;
      }

      timeline.add(
        '0.0s  start — pace MOVING, mode ${motion.motionDetectionMode.name}',
      );

      _speedSub = tl.Tracelet.onSpeedMotionChange((event) {
        timeline.add(
          '${at()}  speed machine ${event.previousState.name} → ${event.state.name}',
        );
        if (event.state == tl.SpeedMotionState.slowing) enteredSlowing = true;
        if (event.previousState == tl.SpeedMotionState.slowing &&
            event.state == tl.SpeedMotionState.moving) {
          slowingToMovingFlips++;
        }
        if (event.state == tl.SpeedMotionState.stationary) {
          speedReachedStationary = true;
        }
      });

      _paceSub = tl.Tracelet.onMotionChange((location) {
        timeline.add(
          '${at()}  pace → ${location.isMoving ? "MOVING" : "STATIONARY"}',
        );
        if (!location.isMoving && !done.isCompleted) done.complete(true);
      });

      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        final left = budget - stopwatch.elapsed;
        if (left.isNegative) return;
        _set(
          'Watching the pace… ${left.inSeconds}s left of a '
          '${budget.inSeconds}s budget (speedStationaryDelay '
          '${delaySeconds}s).\nKeep the phone still.\n\n'
          '${timeline.join('\n')}',
        );
      });

      final reached = await done.future
          .timeout(budget, onTimeout: () => false)
          .catchError((_) => false);

      _ticker?.cancel();
      await _speedSub?.cancel();
      await _paceSub?.cancel();
      stopwatch.stop();

      final elapsed = (stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1);

      // Defect: MotionDetector used to write isMoving itself in smart mode, where
      // the coordinator owns it — so the reported state could disagree with the
      // last event. Whatever the pace ended up as, the two must agree.
      final finalState = await tl.Tracelet.getState();
      final ownershipConsistent = reached
          ? !finalState.isMoving
          : finalState.isMoving;

      final thresholds = await _effectiveThresholds();

      final facts = StringBuffer()
        ..writeln(
          'motionDetectionMode:      ${motion.motionDetectionMode.name}',
        )
        ..writeln('speedStationaryDelay:     ${delaySeconds}s')
        ..writeln('stopTimeout:              ${motion.stopTimeout} min')
        ..writeln('entered SLOWING:          $enteredSlowing')
        ..writeln('SLOWING → MOVING flips:   $slowingToMovingFlips')
        ..writeln('speed machine STATIONARY: $speedReachedStationary')
        ..writeln('pace STATIONARY:          $reached  (after ${elapsed}s)')
        ..writeln(
          'getState() agrees w/ event: $ownershipConsistent  '
          '(isMoving=${finalState.isMoving})',
        )
        ..writeln()
        ..writeln(thresholds)
        ..writeln(timeline.join('\n'));

      final String verdict;
      if (reached && !ownershipConsistent) {
        verdict =
            '🔴 REPRODUCED — the pace reported STATIONARY but getState() still '
            'says moving. In smart mode the coordinator owns isMoving; something '
            'is writing it independently again.';
      } else if (reached && slowingToMovingFlips == 0) {
        verdict =
            '🟢 PASSED — the pace reached STATIONARY after ${elapsed}s with no '
            'countdown restarts, and getState() agrees with the event. Isolated '
            'GPS speed blips are being absorbed: SLOWING now needs three '
            'consecutive above-threshold fixes to give up, and the countdown '
            'keeps its original start time.';
      } else if (reached && slowingToMovingFlips > 0) {
        verdict =
            '🟠 PASSED LATE — the pace did reach STATIONARY after ${elapsed}s, '
            'but the speed machine bounced SLOWING → MOVING '
            '$slowingToMovingFlips time(s) on the way, each restarting the '
            '${delaySeconds}s countdown. With the fix that needs three '
            'consecutive above-threshold fixes, so either the device genuinely '
            'moved (did you touch it?) or the noise is sustained here.';
      } else if (!enteredSlowing) {
        verdict =
            '⚠️ INCONCLUSIVE — the speed machine never entered SLOWING in '
            '${elapsed}s, so no fix was below speedMovingThreshold '
            '(${motion.speedMovingThreshold} m/s). The device is being reported '
            'as moving; retry with the phone stationary and a GPS fix.';
      } else if (slowingToMovingFlips > 0) {
        verdict =
            '🔴 REPRODUCED — #288 defect 1 is present. The countdown was '
            'restarted $slowingToMovingFlips time(s) by SLOWING → MOVING flips '
            'and the pace never reached STATIONARY within ${elapsed}s. A single '
            'noisy GPS speed sample is still discarding the whole '
            '${delaySeconds}s window.';
      } else if (speedReachedStationary) {
        verdict =
            '🔴 REPRODUCED — #288 defect 2/3. The speed machine did reach '
            'STATIONARY but no pace change followed, so the coordinator '
            'swallowed it: either its accelerometer flag was never seeded, or '
            '(Android) its tracking mode is stale because it was only synced in '
            'initialize() from the persisted mode. Restarting the app and '
            'starting a fresh session usually clears the stale mode.';
      } else {
        verdict =
            '🔴 FAILED — the pace stayed MOVING for ${elapsed}s. The speed '
            'machine reached SLOWING and stayed there without completing its '
            '${delaySeconds}s countdown; check the timeline below and the '
            'native log for "SLOWING:" lines.';
      }

      _set('$verdict\n\n$facts');
    } catch (e) {
      _set('❌ ERROR: $e');
    } finally {
      _ticker?.cancel();
      await _speedSub?.cancel();
      await _paceSub?.cancel();
      _speedSub = null;
      _paceSub = null;
      if (mounted) setState(() => _running = false);
    }
  }

  /// Reports what the native SDK is actually using for the sensor thresholds.
  ///
  /// Dart's defaults are the Android-tuned numbers and used to be transmitted
  /// unconditionally, so each platform's own tuned default was unreachable for
  /// any app that configured *any* motion field. The example sets
  /// `shakeThreshold: 2` explicitly and leaves the other two alone, so this is a
  /// direct check of both halves: the explicit value must be honoured, the unset
  /// ones must fall back to the platform's tuning.
  Future<String> _effectiveThresholds() async {
    try {
      final res = await _debug.invokeMapMethod<String, dynamic>(
        'debugIssue288EffectiveThresholds',
      );
      if (res == null) return 'effective thresholds: unavailable\n';

      final unit = res['unit'];
      final motion = tl.Tracelet.activeConfig.motion;
      final shake = (res['shakeThreshold'] as num?)?.toDouble();
      final still = (res['stillThreshold'] as num?)?.toDouble();
      final count = res['stillSampleCount'] as int?;
      final tunedShake = (res['tunedShakeThreshold'] as num?)?.toDouble();
      final tunedStill = (res['tunedStillThreshold'] as num?)?.toDouble();
      final tunedCount = res['tunedStillSampleCount'] as int?;

      String line(
        String name,
        Object? effective,
        Object? tuned,
        bool explicit,
      ) {
        final String note;
        if (explicit) {
          note = 'app-set (honoured)';
        } else if (effective == tuned) {
          note = 'platform default ✓';
        } else {
          note = 'NOT the platform default ($tuned) ✗';
        }
        return '  $name: $effective $unit — $note';
      }

      final buffer = StringBuffer()
        ..writeln('effective native thresholds (${res['platform']}):')
        ..writeln(
          line(
            'shakeThreshold ',
            shake,
            tunedShake,
            motion.hasExplicitShakeThreshold,
          ),
        )
        ..writeln(
          line(
            'stillThreshold ',
            still,
            tunedStill,
            motion.hasExplicitStillThreshold,
          ),
        )
        ..writeln(
          line(
            'stillSampleCount',
            count,
            tunedCount,
            motion.hasExplicitStillSampleCount,
          ),
        );

      final leaked = <String>[
        if (!motion.hasExplicitStillThreshold && still != tunedStill)
          'stillThreshold',
        if (!motion.hasExplicitStillSampleCount && count != tunedCount)
          'stillSampleCount',
        if (!motion.hasExplicitShakeThreshold && shake != tunedShake)
          'shakeThreshold',
      ];
      if (leaked.isNotEmpty) {
        buffer.writeln(
          '  ⚠️ ${leaked.join(", ")} was never set in Dart but the native side '
          'is not using its own default — a cross-platform scalar is still being '
          'pushed down (#288).',
        );
      }
      return buffer.toString();
    } on PlatformException catch (e) {
      return 'effective thresholds: ${e.code} — ${e.message}\n';
    } on MissingPluginException {
      return 'effective thresholds: no debug handler in this build '
          '(rebuild the example app)\n';
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'motion smart pace stationary moving speedmotionmanager slowing '
          'countdown speedstationarydelay stoptimeout gps speed noise blip '
          'coordinator accel seed syncCurrentMode changePace isMoving 288',
      title: '#288: pace never leaves MOVING in smart mode',
      description:
          'A still device could stay MOVING forever: one noisy GPS speed fix '
          "discarded the whole SLOWING countdown, the coordinator's "
          'accelerometer flag was never seeded so the stop-timeout could not '
          'compensate, and on Android a stale coordinator mode could block the '
          'switch entirely. This card watches the real speed machine and pace '
          'events and times how long a still device takes to reach STATIONARY, '
          'then checks that getState() agrees with the event (the coordinator '
          'owns isMoving in smart mode) and reports the thresholds the native '
          'SDK is actually using, so an unset one must show its platform '
          'default. Start tracking first, put the phone on a desk, and do not '
          'touch it while it runs.',
      status: _status,
      running: _running,
      runLabel: 'Verify',
      onRun: _test,
    );
  }
}
