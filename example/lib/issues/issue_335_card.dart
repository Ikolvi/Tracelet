import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

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

class _Issue335CardState extends State<Issue335Card>
    with IssueCardRun<Issue335Card> {
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

      // Seed a known state. Without this the first changePace() below lands on
      // whatever the machine happened to settle into, and "one event" cannot be
      // distinguished from "one *no-op* event" — which is exactly how the first
      // run of this card surfaced #337: it reported a green
      // `stationary → stationary`.
      await Tracelet.changePace(true);
      await Future<void>.delayed(const Duration(seconds: 2));
      events.clear();

      // A real edge: MOVING → STATIONARY.
      await Tracelet.changePace(false);
      await Future<void>.delayed(const Duration(seconds: 2));
      final afterStationary = List<SpeedMotionEvent>.from(events);

      // The same call again. It changes nothing, so it must report nothing.
      await Tracelet.changePace(false);
      await Future<void>.delayed(const Duration(seconds: 2));
      final afterRepeat = events.length - afterStationary.length;

      final repeatWindow = events.sublist(afterStationary.length);

      // Back the other way: another real edge.
      await Tracelet.changePace(true);
      await Future<void>.delayed(const Duration(seconds: 2));
      final movingWindow = events.sublist(afterStationary.length + afterRepeat);

      // Counting *everything* that lands in the window is wrong, and produced a
      // false red on the first device run of this card. The machine is fed real
      // fixes throughout: once changePace(true) puts it in MOVING, a stationary
      // device's next fix reports ~0 m/s and legitimately slides it
      // MOVING → SLOWING within a second. That is a second event, and a
      // perfectly genuine one.
      //
      // The forced edge is identified by its destination instead. Within a 2 s
      // window only the slide to SLOWING can happen spontaneously — reaching
      // STATIONARY on its own needs the whole speedStationaryDelay (180 s by
      // default) — so exactly one event may name each forced destination, and a
      // true duplicate (the same payload twice, which is what #335 was) still
      // fails this.
      int arrivingAt(List<SpeedMotionEvent> evs, SpeedMotionState to) =>
          evs.where((e) => e.state == to).length;
      String describe(List<SpeedMotionEvent> evs) => evs.isEmpty
          ? 'none'
          : evs
                .map((e) => '${e.previousState.name}→${e.state.name}')
                .join(', ');

      final stops = arrivingAt(afterStationary, SpeedMotionState.stationary);
      check(
        '#335 a forced stop emits one event, not two',
        stops == 1,
        stops == 1
            ? 'changePace(false) produced exactly one event arriving at '
                  'STATIONARY — observed: ${describe(afterStationary)}'
            : stops == 0
            ? 'no event arrived at STATIONARY — observed: '
                  '${describe(afterStationary)}. Nothing can be concluded from '
                  'the rows below.'
            : 'REGRESSED — $stops events arrived at STATIONARY for one '
                  'changePace(false) — observed: ${describe(afterStationary)}',
      );

      check(
        '#337 a repeat of the same changePace emits nothing',
        afterRepeat == 0,
        afterRepeat == 0
            ? 'the second changePace(false) agreed with the current state, so '
                  'no edge was reported'
            : 'REGRESSED — $afterRepeat event(s) for a transition that changed '
                  'nothing — observed: ${describe(repeatWindow)}. Android used '
                  'to emit these; iOS always suppressed them.',
      );

      final resumes = arrivingAt(movingWindow, SpeedMotionState.moving);
      final onward = movingWindow.length - resumes;
      check(
        'a forced resume emits one event, not two',
        resumes == 1,
        resumes == 1
            ? 'changePace(true) produced exactly one event arriving at MOVING'
                  '${onward == 0 ? '' : ', plus $onward onward transition(s) '
                            'the fix stream drove afterwards'} — observed: '
                  '${describe(movingWindow)}'
            : 'REGRESSED — $resumes events arrived at MOVING for one '
                  'changePace(true) — observed: ${describe(movingWindow)}',
      );

      // A stationary device sliding MOVING → SLOWING after the resume is
      // expected, not a defect. Reported so the row above is readable rather
      // than looking like a suppressed failure.
      if (onward > 0) {
        results.add(
          'ℹ️ $onward onward transition(s) after the resume: '
          '${describe(movingWindow.where((e) => e.state != SpeedMotionState.moving).toList())}. '
          'This device is stationary, so its next fix reports ~0 m/s and the '
          'machine correctly begins its SLOWING countdown. Not attributable to '
          'changePace().',
        );
      }

      // No event may report itself as going nowhere. This catches a no-op
      // transition (#337) but NOT a #335-style duplicate, whose two copies each
      // name a genuine edge — the rows above are what cover that.
      final degenerate = events
          .where((e) => e.state == e.previousState)
          .toList();
      check(
        'no event reports a transition to the state it came from',
        degenerate.isEmpty,
        degenerate.isEmpty
            ? 'every event names a genuine edge (note: a duplicate would too, '
                  'so this row alone does not rule one out)'
            : 'REGRESSED — ${degenerate.length} event(s) with '
                  'previousState == state, a no-op transition (#337)',
      );

      // The whole sequence, so a failure above can be read without re-running.
      results.add('ℹ️ full event sequence: ${describe(events)}');

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
        'Android was never affected by the duplicate: its transitionTo() has '
        'always been a single choke point, and iOS now matches it.\n\n'
        'It was affected by the converse, which the first run of this card '
        'found on a device (#337): transitionTo() had no "did the state '
        'actually change" guard, so a changePace() that agreed with the '
        'current state emitted a stationary → stationary event and wrote a '
        'fabricated `speed-motion: STATIONARY -> STATIONARY` line into the '
        '#334 trace. iOS commitTransition() had always guarded it. All five '
        'iOS commit sites were checked; the four location-driven ones are real '
        'edges by construction and onManualPaceChange is the one the guard '
        'absorbs.',
      );
    } catch (e) {
      _set('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      await sub?.cancel();
      setRunning(running: false);
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
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
