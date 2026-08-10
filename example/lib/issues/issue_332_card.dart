import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #332 — a location the Rust processor rejected reported
/// `effectiveSpeed: 0.0`, so the GPS-speed motion machine was told the device
/// had stopped once per rejected fix.
///
/// Both hosts feed *every* fix into `SpeedMotionManager`, accepted or not —
/// deliberately, because a parked device's fixes are all distance-filtered and
/// the machine would otherwise never leave MOVING. They feed it
/// `result.effectiveSpeed`, which `LocationProcessorResult::filtered()`
/// hardcoded to zero.
///
/// In a vehicle that is the common case, not a corner case: at the `vehicle`
/// auto-tune's 30 m distance filter and ~1 Hz fixes, most of a 10 m/s drive is
/// rejected. The machine saw a stream of zeros on a motorway, dropped
/// MOVING → SLOWING, could never collect the three *consecutive* above-threshold
/// fixes needed to abort (each fabricated zero reset the streak), and ran its
/// countdown out to STATIONARY. The accelerometer had independently declared
/// stillness — a phone held still in a smooth-riding car reads near-zero, which
/// is the exact scenario the speed machine exists to cover — so the
/// coordinator's logical OR collapsed and tracking downgraded to periodic
/// mid-drive. Shaking the phone was the only way back.
///
/// **What this card can prove, and what it cannot.** The processor is not
/// exposed to Dart, so the fix itself is pinned by Rust unit tests
/// (`a_drive_never_reports_a_fabricated_zero_speed`). What this card does is
/// observe the live consequence: it watches real fixes and the speed machine
/// side by side, and fails if the machine leaves MOVING while the device is
/// demonstrably above the speed threshold. That is only exercised while
/// actually moving, so a stationary run reports **inconclusive** rather than
/// green — see the run output.
class Issue332Card extends StatefulWidget {
  const Issue332Card({super.key});

  @override
  State<Issue332Card> createState() => _Issue332CardState();
}

class _Issue332CardState extends State<Issue332Card> {
  static const _observeWindow = Duration(seconds: 45);

  /// The SDK default for `speedMovingThreshold` (m/s). Fixes at or above this
  /// are what the machine must treat as motion.
  static const _movingThreshold = 1.5;

  String _status = 'Idle';
  bool _running = false;

  void _set(String s) {
    if (mounted) setState(() => _status = s);
  }

  Future<void> _run() async {
    setState(() => _running = true);
    final results = <String>[];
    var allPass = true;

    void check(String name, bool pass, String detail) {
      results.add('${pass ? '✅' : '❌'} $name — $detail');
      if (!pass) allPass = false;
    }

    StreamSubscription<Location>? locSub;
    StreamSubscription<SpeedMotionEvent>? smSub;

    try {
      final speeds = <double>[];
      final transitions = <SpeedMotionEvent>[];
      // Speed at the moment each transition landed, so a downgrade can be
      // attributed to the reading that caused it rather than to the run as a
      // whole.
      final speedAtTransition = <double>[];

      locSub = Tracelet.onLocation((l) => speeds.add(l.coords.speed));
      smSub = Tracelet.onSpeedMotionChange((e) {
        transitions.add(e);
        speedAtTransition.add(speeds.isEmpty ? -1 : speeds.last);
      });

      await Tracelet.start();
      _set(
        'Observing for ${_observeWindow.inSeconds}s…\n\n'
        'To exercise the regression, run this while travelling with the phone '
        'held still or resting on a seat. Standing still can only confirm the '
        'plumbing.',
      );
      await Future<void>.delayed(_observeWindow);

      final moving = speeds.where((s) => s >= _movingThreshold).length;
      final maxSpeed = speeds.isEmpty
          ? 0.0
          : speeds.reduce((a, b) => a > b ? a : b);

      // Row 1: did anything arrive at all? Without this a silent location
      // pipeline would make every row below vacuously green.
      check(
        'fixes were delivered',
        speeds.isNotEmpty,
        speeds.isNotEmpty
            ? '${speeds.length} fix(es), peak ${maxSpeed.toStringAsFixed(2)} m/s'
            : 'no fixes in ${_observeWindow.inSeconds}s — check location '
                  'permission and that GPS has a sky view. Nothing below can be '
                  'concluded.',
      );

      // Row 2: the actual regression. A downgrade out of MOVING is only a bug
      // when the device was above the threshold at the time.
      final downgrades = <String>[];
      for (var i = 0; i < transitions.length; i++) {
        final t = transitions[i];
        final at = speedAtTransition[i];
        if (t.state != SpeedMotionState.moving && at >= _movingThreshold) {
          downgrades.add(
            '${t.previousState.name} → ${t.state.name} at '
            '${at.toStringAsFixed(2)} m/s',
          );
        }
      }

      if (moving == 0) {
        results.add(
          '⏭️ #332 the speed machine holds MOVING while the device moves — '
          'INCONCLUSIVE. No fix reached the '
          '${_movingThreshold.toStringAsFixed(1)} m/s threshold in this run '
          '(peak ${maxSpeed.toStringAsFixed(2)} m/s), so the regression was '
          'never given a chance to fire. Re-run while travelling. This is '
          'reported as a skip, not a pass: a stationary device legitimately '
          'goes STATIONARY, and calling that green would hide the bug.',
        );
      } else {
        check(
          '#332 the speed machine holds MOVING while the device moves',
          downgrades.isEmpty,
          downgrades.isEmpty
              ? '$moving of ${speeds.length} fixes were at or above '
                    '${_movingThreshold.toStringAsFixed(1)} m/s (peak '
                    '${maxSpeed.toStringAsFixed(2)}) and the machine never left '
                    'MOVING on one of them'
              : 'REGRESSED — left MOVING while above the threshold: '
                    '${downgrades.join('; ')}. A rejected fix is reporting a '
                    'fabricated speed again.',
        );
      }

      // Row 3: the diagnostic that makes the next report readable without a
      // debug build (#334). Cheap to assert here and it shares this bug's
      // subject, so a regression in either shows up on the same card.
      final logs = await Tracelet.getLogs(300);
      final speedMotionTrace = logs
          .where((e) => e.level.toUpperCase() == 'LIFECYCLE')
          .where((e) => e.message.contains('speed-motion:'))
          .toList();
      check(
        'the speed machine leaves an always-on trace',
        speedMotionTrace.isNotEmpty,
        speedMotionTrace.isNotEmpty
            ? '${speedMotionTrace.length} `speed-motion:` lifecycle entr'
                  '${speedMotionTrace.length == 1 ? 'y' : 'ies'}, each carrying '
                  'the speed it decided on — e.g. "'
                  '${speedMotionTrace.last.message}"'
            : 'no `speed-motion:` lifecycle entries. The machine records one on '
                  'start and one per transition, so a run that stayed in a '
                  'single state and was already started may legitimately show '
                  'none; a run that changed state and shows none is a #334 '
                  'regression.',
      );

      await Tracelet.stop();

      final header = allPass
          ? '✅ SUCCESS: no fix caused the speed machine to declare a stop '
                'while the device was moving.'
          : '❌ FAILED — see the failing rows below.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'Mechanism: LocationProcessorResult::filtered() returned '
        'effective_speed: 0.0 for every rejected fix, and both hosts feed that '
        'value into SpeedMotionManager on every fix by design. A 30 m distance '
        'filter rejects most of a 10 m/s drive, so the machine was told '
        '"stopped" two times out of three on a motorway.\n\n'
        'Why the accelerometer did not save it: a phone held still in a '
        'smooth-riding car reads near-zero, which is precisely why the '
        'GPS-speed machine exists. Once it was fooled too, the coordinator OR '
        'had two false inputs and downgraded to periodic tracking.\n\n'
        'Coverage note: the processor has no Dart entry point, so the fix '
        'itself is pinned by Rust unit tests. This card observes the live '
        'consequence and is only conclusive while actually moving.',
      );
    } catch (e) {
      _set('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      await locSub?.cancel();
      await smSub?.cancel();
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'speed motion stationary moving vehicle drive filtered distance '
          'filter effective speed rust processor slowing countdown periodic '
          'downgrade smart coordinator 332',
      title: '#332: a filtered fix no longer reports a fabricated 0 m/s',
      description:
          'Watches live fixes and the GPS-speed motion machine together and '
          'fails if the machine declares a stop while the device is above the '
          'moving threshold. Run it while travelling — a stationary run is '
          'reported as inconclusive rather than green.',
      status: _status,
      running: _running,
      onRun: _run,
    );
  }
}
