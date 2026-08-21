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
/// correct.
///
/// This card exercises the parts observable from Dart. Note that trip
/// detection is wired by `start()`, not `ready()`: the Dart-side manager
/// listens to the motionchange stream, so nothing happens until tracking is
/// running. The first row below checks that the motion transition actually
/// reached Dart, so a failure further down cannot be misread as a trip-identity
/// defect when the real cause was that the pace never changed.
class Issue402Card extends StatefulWidget {
  const Issue402Card({super.key});

  @override
  State<Issue402Card> createState() => _Issue402CardState();
}

class _Issue402CardState extends State<Issue402Card>
    with IssueCardRun<Issue402Card> {
  /// How long to wait for a native motion transition to reach Dart. Generous:
  /// the event crosses the platform channel after the motion managers settle.
  static const _settle = Duration(seconds: 8);

  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _run;

  /// Polls [condition] until it holds or [timeout] elapses.
  ///
  /// A fixed delay would either flake on a slow device or pad every run; this
  /// returns as soon as the event lands.
  Future<bool> _waitFor(
    bool Function() condition, {
    Duration timeout = _settle,
  }) async {
    final deadline = DateTime.now().add(timeout);
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

    final starts = <TripStartEvent>[];
    final ends = <TripEvent>[];
    final motionChanges = <bool>[];
    StreamSubscription<TripStartEvent>? startSub;
    StreamSubscription<TripEvent>? endSub;
    StreamSubscription<Location>? motionSub;

    try {
      await Tracelet.requestLocationAuthorization();
      await Tracelet.ready(
        const Config(
          motion: MotionConfig(
            motionDetectionMode: MotionDetectionMode.smart,
            stopTimeout: 1,
          ),
          telematics: TelematicsConfig(enableDrivingEvents: true),
          http: HttpConfig(autoSync: false),
          logger: LoggerConfig(logLevel: LogLevel.debug),
        ),
      );

      motionSub = Tracelet.onMotionChange(
        (location) => motionChanges.add(location.isMoving),
      );
      startSub = Tracelet.onTripStart(starts.add);
      endSub = Tracelet.onTrip(ends.add);

      // Trip detection is wired by start(), not ready() — the Dart-side manager
      // subscribes to the motionchange stream there. Without this the card
      // proves nothing, which is exactly how its first revision failed.
      await Tracelet.start();

      // ---------------------------------------------------------------------
      // Open a trip
      // ---------------------------------------------------------------------
      await Tracelet.changePace(true);
      final movedReached = await _waitFor(() => motionChanges.contains(true));

      check(
        'the moving transition reached Dart',
        pass: movedReached,
        detail: movedReached
            ? 'onMotionChange delivered isMoving=true, so trip detection had '
                  'something to act on'
            : 'no moving motionchange arrived within ${_settle.inSeconds}s — '
                  'the rows below cannot say anything about trip identity, '
                  'because no trip could have started. Check the pace machine, '
                  'not #402.',
      );

      final started = await _waitFor(() => starts.isNotEmpty);
      check(
        'a trip start is observable',
        pass: started,
        detail: started
            ? 'onTripStart fired with tripId ${starts.first.tripId}'
            : 'onTripStart never fired — before #402 a trip only became '
                  'visible once it had already ended',
      );

      final firstId = starts.isEmpty ? null : starts.first.tripId;

      check(
        'the id is a non-empty opaque identifier',
        pass: firstId != null && firstId.isNotEmpty,
        detail: firstId == null || firstId.isEmpty
            ? 'no trip id was delivered'
            : 'a ${firstId.length}-character id; treat it as opaque and order '
                  'trips by startedAt, never by the id itself',
      );

      check(
        'currentTripId reports the running trip',
        pass: firstId != null && Tracelet.currentTripId == firstId,
        detail: firstId == null
            ? 'no trip is running, so there is nothing to report'
            : 'currentTripId is ${Tracelet.currentTripId} — this is the value '
                  'being stamped onto every location and driving event written '
                  'right now',
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
        'the id is stable for the whole trip',
        // Guarded on firstId: without it this passes vacuously when no trip
        // ever started, which is precisely the false green this card had.
        pass: firstId != null && Tracelet.currentTripId == firstId,
        detail: firstId == null
            ? 'no trip started, so stability was never exercised'
            : Tracelet.currentTripId == firstId
            ? 'unchanged after a driving event was recorded'
            : 'the id changed mid-trip, from $firstId to '
                  '${Tracelet.currentTripId}',
      );

      // ---------------------------------------------------------------------
      // Close it
      // ---------------------------------------------------------------------
      await Tracelet.changePace(false);
      final ended = await _waitFor(() => ends.isNotEmpty);

      check(
        'the summary carries the id minted at start',
        pass: ended && firstId != null && ends.first.tripId == firstId,
        detail: !ended
            ? 'onTrip never fired, so there is no summary to join'
            : 'summary tripId is ${ends.first.tripId} — this is what makes it '
                  'joinable to the records written during the trip',
      );

      check(
        'the summary carries absolute bounds',
        pass:
            ended && ends.first.startedAt != null && ends.first.endedAt != null,
        detail: !ended
            ? 'no summary'
            : 'startedAt ${ends.first.startedAt}, endedAt ${ends.first.endedAt}'
                  ' — duration alone could not place a trip on a timeline',
      );

      check(
        'the id is cleared at trip end',
        // Also guarded: "null after a trip that never ran" proves nothing.
        pass: ended && Tracelet.currentTripId == null,
        detail: !ended
            ? 'no trip ended, so clearing was never exercised'
            : 'currentTripId is ${Tracelet.currentTripId} — records written '
                  'between trips must carry no trip id rather than the '
                  'previous trip’s',
      );

      // ---------------------------------------------------------------------
      // A second journey must never reuse the first one's id
      // ---------------------------------------------------------------------
      await Tracelet.changePace(true);
      final secondStarted = await _waitFor(() => starts.length >= 2);
      final secondId = starts.length >= 2 ? starts[1].tripId : null;
      await Tracelet.changePace(false);
      await _waitFor(() => ends.length >= 2);

      check(
        'a second trip gets a new id',
        pass: secondStarted && secondId != null && secondId != firstId,
        detail: !secondStarted
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
      await motionSub?.cancel();
      // stop() also resets the trip manager, so the next card does not inherit
      // an active trip id stamped onto whatever it records.
      try {
        await Tracelet.stop();
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
          'Starts tracking, opens a trip with changePace, and checks that the '
          'start is observable at all (it never was before — onTrip fires only '
          'at the end), that the minted id is stable across the trip and '
          'reported by currentTripId, that the summary carries the same id '
          'plus absolute bounds, that the id is cleared at trip end, and that '
          'a second trip never reuses it.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
