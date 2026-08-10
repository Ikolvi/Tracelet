import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #335 — iOS emitted the `speedmotion` event twice for most transitions.
///
/// `SpeedMotionManager.onLocation` snapshotted the state, delegated to a
/// handler, and then persisted-and-emitted if the state had changed. But three
/// of the four handlers already did that for themselves, so both fired with
/// identical payloads:
///
/// ```swift
/// private func handleMoving(speed: Double, now: TimeInterval) {
///     if speed < speedMovingThreshold {
///         state = .slowing
///         if state != previousState { persistState(); emitEvent(...) }   // (1)
///     }
/// }
/// // …then, back in onLocation:
/// if state != previousState { persistState(); emitEvent(...) }           // (2)
/// ```
///
/// `handleStationary` was the odd one out — it emitted nothing of its own and
/// relied solely on the outer block — which is why `STATIONARY -> MOVING` was
/// the only transition that emitted once. The contract was therefore
/// inconsistent with itself as well as with Android, whose single
/// `transitionTo` choke point had always emitted once.
///
/// Beyond the duplicate Dart events, this blocked #334: a doubled entry would
/// have misrepresented one transition as two in the diagnostic trace meant to
/// settle what happened during a trip. iOS now has the same single
/// `commitTransition` choke point, which persists, emits and records once.
///
/// **What this card can prove.** `changePace()` drives real transitions on
/// demand, so the one-event-per-transition contract is checkable without
/// waiting for GPS. It exercises the manual path specifically; the
/// location-driven path that carried the duplicate is pinned by the Swift unit
/// tests (`testEachTransitionEmitsExactlyOneEvent`), which is stated below
/// rather than implied.
class Issue335Card extends StatefulWidget {
  const Issue335Card({super.key});

  @override
  State<Issue335Card> createState() => _Issue335CardState();
}

class _Issue335CardState extends State<Issue335Card> {
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

    StreamSubscription<SpeedMotionEvent>? sub;

    try {
      // Speed mode so the machine under test is the one driving pace, rather
      // than the accelerometer.
      await Tracelet.setConfig(
        const Config(
          motion: MotionConfig(motionDetectionMode: MotionDetectionMode.speed),
        ),
      );

      final events = <SpeedMotionEvent>[];
      sub = Tracelet.onSpeedMotionChange(events.add);

      await Tracelet.start();
      await Future<void>.delayed(const Duration(seconds: 2));
      events.clear(); // ignore whatever start() settled into

      // Two forced transitions, each of which must produce exactly one event.
      await Tracelet.changePace(false);
      await Future<void>.delayed(const Duration(seconds: 2));
      final afterStationary = List<SpeedMotionEvent>.from(events);

      await Tracelet.changePace(true);
      await Future<void>.delayed(const Duration(seconds: 2));

      check(
        '#335 a forced stop emits one event, not two',
        afterStationary.length == 1,
        afterStationary.length == 1
            ? 'changePace(false) produced exactly one '
                  '${afterStationary.first.previousState.name} → '
                  '${afterStationary.first.state.name} event'
            : afterStationary.isEmpty
            ? 'no event at all — the machine may already have been stationary, '
                  'or the event stream is not wired. Nothing can be concluded '
                  'from the rows below.'
            : 'REGRESSED — ${afterStationary.length} events for one '
                  'transition: '
                  '${afterStationary.map((e) => '${e.previousState.name}→${e.state.name}').join(', ')}',
      );

      final afterMoving = events.length - afterStationary.length;
      check(
        'a forced resume emits one event, not two',
        afterMoving == 1,
        afterMoving == 1
            ? 'changePace(true) produced exactly one event'
            : 'REGRESSED — $afterMoving events for one transition',
      );

      // No transition can report itself as going nowhere. A duplicate emitted
      // after the state had already been committed would show up here.
      final degenerate = events
          .where((e) => e.state == e.previousState)
          .toList();
      check(
        'no event reports a transition to the state it came from',
        degenerate.isEmpty,
        degenerate.isEmpty
            ? 'every event names a genuine edge'
            : 'REGRESSED — ${degenerate.length} event(s) with '
                  'previousState == state, which is what a second emit after '
                  'the commit looks like',
      );

      await Tracelet.stop();

      final header = allPass
          ? '✅ SUCCESS: one event per transition on the manual path.'
          : '❌ FAILED — see the failing rows below.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'Scope: changePace() exercises the manual path. The duplicate itself '
        'was on the location-driven path — the inner handler emitted, then '
        'onLocation emitted again — which needs synthetic fixes to drive and '
        'is pinned by the Swift unit test '
        'testEachTransitionEmitsExactlyOneEvent, now that the suite is '
        'actually wired into Package.swift. This card checks the contract '
        'holds end to end through the bridge.\n\n'
        'Android was never affected: its transitionTo() has always been a '
        'single choke point. iOS now matches it.',
      );
    } catch (e) {
      _set('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      await sub?.cancel();
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'speedmotion event duplicate emit twice transition choke point '
          'commitTransition transitionTo ios android parity changePace 335',
      title: '#335: one speedmotion event per transition, not two',
      description:
          'Forces stop/resume transitions with changePace() and asserts each '
          'produces exactly one speedmotion event. iOS used to emit most '
          'transitions twice because both the handler and its caller emitted.',
      status: _status,
      running: _running,
      onRun: _run,
    );
  }
}
