import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #442 — the native trip manager missed SMART/SPEED transitions and
/// every `changePace()`.
///
/// The native trip manager stamps `trip_id` onto stored locations and driving
/// events (#402) and stores trip summaries (#401). It was fed only from the
/// sensor-driven motion handler: on Android SMART mode left it early, SPEED
/// transitions never reached it, and `changePace()` bypassed it in every mode;
/// on iOS `changePace` sent its event before the trip manager saw the
/// transition. Dart's `onTrip` still fired, under an id Dart minted itself, so
/// the stored rows carried `trip_id: null` and no summary was stored.
///
/// **What this card proves**, in SMART mode with `changePace()` — the exact
/// combination found on a device:
///  * the moving motion change carries a **native** trip id
///    (`extras['tripId']`), which is what the database stamps rows with;
///  * the trip `onTrip` reports ends under that same id, so Dart did not mint
///    its own.
class Issue442Card extends StatefulWidget {
  const Issue442Card({super.key});

  @override
  State<Issue442Card> createState() => _Issue442CardState();
}

class _Issue442CardState extends State<Issue442Card>
    with IssueCardRun<Issue442Card> {
  static const _settle = Duration(seconds: 8);

  @override
  IssueRunner? get cardRunner => _run;

  Future<bool> _waitFor(bool Function() condition) async {
    final deadline = DateTime.now().add(_settle);
    while (DateTime.now().isBefore(deadline)) {
      if (condition()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return condition();
  }

  Future<void> _run() async {
    setRunning(running: true);
    final results = <String>[];
    var allPass = true;

    void check(String name, {required bool pass, required String detail}) {
      results.add('${pass ? '✅' : '❌'} $name — $detail');
      if (!pass) allPass = false;
    }

    final moving = <Location>[];
    final ends = <TripEvent>[];
    StreamSubscription<Location>? motionSub;
    StreamSubscription<TripEvent>? endSub;

    try {
      await Tracelet.requestLocationAuthorization();
      await Tracelet.ready(
        const Config(
          motion: MotionConfig(
            motionDetectionMode: MotionDetectionMode.smart,
            stopTimeout: 1,
          ),
          http: HttpConfig(autoSync: false),
        ),
      );
      motionSub = Tracelet.onMotionChange((l) {
        if (l.isMoving) moving.add(l);
      });
      endSub = Tracelet.onTrip(ends.add);
      await Tracelet.start();

      setStatus('⏳ SMART mode: changePace(true)…');
      await Tracelet.changePace(true);
      final movedSeen = await _waitFor(() => moving.isNotEmpty);
      final nativeId = movedSeen
          ? moving.last.extras['tripId'] as String?
          : null;
      check(
        'the moving motion change carries a native trip id',
        pass: nativeId != null,
        detail: !movedSeen
            ? 'no moving motion change arrived — nothing to check'
            : nativeId != null
            ? 'extras.tripId = $nativeId'
            : 'no tripId on the event: the native trip manager never saw the '
                  'transition (the bug)',
      );

      await Future<void>.delayed(const Duration(seconds: 2));
      setStatus('⏳ changePace(false)…');
      await Tracelet.changePace(false);
      final ended = await _waitFor(() => ends.isNotEmpty);
      check(
        'onTrip ends under the native id',
        pass: ended && nativeId != null && ends.last.tripId == nativeId,
        detail: !ended
            ? 'onTrip never fired'
            : 'onTrip tripId ${ends.last.tripId}'
                  '${ends.last.tripId == nativeId ? ' — matches' : ' — Dart minted its own'}',
      );

      final header = allPass
          ? '✅ SUCCESS: SMART-mode changePace produces a native trip.'
          : '❌ FAILED — #442 not satisfied on this build.';
      setStatus(
        '$header\n\n${results.join('\n')}\n\n'
        'A native trip is what stamps trip_id on stored rows (#402) and stores '
        'the summary that syncs as `trips` (#401) — run the #401 card for '
        'that half.',
      );
    } catch (e) {
      setStatus('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      await motionSub?.cancel();
      await endSub?.cancel();
      await Tracelet.stop();
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'trip id smart speed changePace native trip manager trip_id null '
          'onTrip summary 442 401 402',
      title: '#442: native trips in every motion mode',
      description:
          'In SMART/SPEED mode and from changePace(), the native trip manager '
          'never saw the transition, so rows had no trip_id and no trip summary '
          'was stored. Drives a SMART-mode trip with changePace and checks the '
          'ids are native.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
