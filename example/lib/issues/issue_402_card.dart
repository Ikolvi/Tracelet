import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #402 — locations, driving events, and trips had no identifier in
/// common.
///
/// The SDK produced all three but nothing tied them together, so an app could
/// not answer "which driving events happened during this trip?" without
/// re-deriving trip boundaries itself. It could not do that reliably either:
/// `onTrip` fires only at trip *end*, so there was no moment at which to mint
/// an id, and trips begin while the app process is usually not alive.
///
/// The SDK now mints a UUIDv4 when a trip starts, keeps it for the trip's
/// lifetime, and discards it at the end so it is never handed to a second
/// journey. It is stamped onto `location_events` and `tracelet_telematics`
/// rows at INSERT — not at sync time, which is what makes the offline case
/// correct: a row queued during trip A still uploads as trip A's even when
/// trip B is what is running by the time the flush happens.
///
/// This card exercises the parts observable from Dart: that a trip start is
/// reported at all (it never was before), that the id is stable across the
/// trip, that the summary carries the same id, and that a second trip gets a
/// different one. The write-time stamping itself is asserted in the Rust
/// suite, where the database is reachable.
class Issue402Card extends StatefulWidget {
  const Issue402Card({super.key});

  @override
  State<Issue402Card> createState() => _Issue402CardState();
}

class _Issue402CardState extends State<Issue402Card>
    with IssueCardRun<Issue402Card> {
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

    final starts = <TripStartEvent>[];
    final ends = <TripEvent>[];
    StreamSubscription<TripStartEvent>? startSub;
    StreamSubscription<TripEvent>? endSub;

    try {
      await Tracelet.ready(
        const Config(
          telematics: TelematicsConfig(enableDrivingEvents: true),
          logger: LoggerConfig(logLevel: LogLevel.debug),
        ),
      );

      startSub = Tracelet.onTripStart(starts.add);
      endSub = Tracelet.onTrip(ends.add);

      // A trip opens on the stationary → moving transition. changePace drives
      // that transition directly rather than waiting on real motion.
      await Tracelet.changePace(true);
      await Future<void>.delayed(const Duration(milliseconds: 600));

      check(
        'A trip start is observable',
        starts.isNotEmpty,
        starts.isEmpty
            ? 'onTripStart never fired — before #402 a trip only became '
                  'visible once it had already ended'
            : 'onTripStart fired with tripId ${starts.first.tripId}',
      );

      final firstId = starts.isEmpty ? null : starts.first.tripId;

      check(
        'The id is a non-empty opaque identifier',
        firstId != null && firstId.isNotEmpty,
        firstId == null || firstId.isEmpty
            ? 'no trip id was delivered'
            : 'a ${firstId.length}-character id; treat it as opaque and order '
                  'trips by startedAt, never by the id itself',
      );

      check(
        'currentTripId reports the running trip',
        firstId != null && Tracelet.currentTripId == firstId,
        'currentTripId is ${Tracelet.currentTripId} — this is the value being '
            'stamped onto every location and driving event written right now',
      );

      // Anything recorded mid-trip must not rotate the id.
      await Tracelet.simulateTelematicsEvent(
        eventType: 'harsh_braking',
        severity: 0.8,
        latitude: 24.8607,
        longitude: 67.0011,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));

      check(
        'The id is stable for the whole trip',
        Tracelet.currentTripId == firstId,
        Tracelet.currentTripId == firstId
            ? 'unchanged after a driving event was recorded'
            : 'the id changed mid-trip, from $firstId to '
                  '${Tracelet.currentTripId}',
      );

      // Close the trip.
      await Tracelet.changePace(false);
      await Future<void>.delayed(const Duration(milliseconds: 800));

      check(
        'The summary carries the id minted at start',
        ends.isNotEmpty && ends.first.tripId == firstId,
        ends.isEmpty
            ? 'onTrip never fired, so there is no summary to join'
            : 'summary tripId is ${ends.first.tripId} — this is what makes it '
                  'joinable to the records written during the trip',
      );

      check(
        'The summary carries absolute bounds',
        ends.isNotEmpty &&
            ends.first.startedAt != null &&
            ends.first.endedAt != null,
        ends.isEmpty
            ? 'no summary'
            : 'startedAt ${ends.first.startedAt}, endedAt ${ends.first.endedAt} '
                  '— duration alone could not place a trip on a timeline',
      );

      check(
        'The id is cleared at trip end',
        Tracelet.currentTripId == null,
        'currentTripId is ${Tracelet.currentTripId} — records written between '
            "trips must carry no trip id rather than the previous trip's",
      );

      // A second journey must never reuse the first one's id.
      await Tracelet.changePace(true);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final secondId = Tracelet.currentTripId;
      await Tracelet.changePace(false);
      await Future<void>.delayed(const Duration(milliseconds: 600));

      check(
        'A second trip gets a new id',
        secondId != null && secondId != firstId,
        secondId == null
            ? 'the second trip did not open'
            : 'second trip is $secondId, first was $firstId',
      );

      final header = allPass
          ? '✅ PASS: trips carry an identity that records can be joined on.'
          : '⚠️ Some checks failed — see the rows below.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'What this card cannot show from Dart: the id is also written into the '
        'trip_id column of location_events and tracelet_telematics at INSERT, '
        'and emitted in the sync payload. Stamping at write time rather than '
        'at flush time is what keeps an offline backlog correct — those are '
        'asserted in the Rust suite, where the database is reachable.',
      );
    } catch (e) {
      _set('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      await startSub?.cancel();
      await endSub?.cancel();
      // Leave the SDK stationary: a card that exits mid-trip leaves an active
      // trip id stamped onto whatever the next card records.
      try {
        await Tracelet.changePace(false);
      } catch (_) {
        // Best-effort cleanup; never turn it into the card's result.
      }
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'trip id tripId trip_id correlation onTripStart currentTripId uuid '
          'uuidv4 trip identity join key telematics locations trip summary '
          'startedAt endedAt offline backlog',
      title: '#402: trips, locations, and driving events share a trip id',
      description:
          'Opens a trip, checks that the start is observable at all (it never '
          'was before — onTrip fires only at the end), that the minted id is '
          'stable across the trip and reported by currentTripId, that the '
          'summary carries the same id plus absolute bounds, that the id is '
          'cleared at trip end, and that a second trip never reuses it.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
