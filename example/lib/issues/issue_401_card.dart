import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';
import 'package:tracelet_example/issues/test_server_endpoint.dart';

/// Issue #401 — trip summaries never reached a backend.
///
/// `trip_id` (#402) joined locations and driving events, but the trip summary
/// itself only existed as the `onTrip()` event: never stored, never synced, and
/// lost if the Dart isolate was gone when the trip ended. Each completed trip is
/// now stored natively, once, under its `trip_id`, and sent with the next sync
/// as a root `trips` array (custom builders: `context.trips`). It is marked sent
/// only when the request carrying it succeeds.
///
/// **What this card proves**, without a server: it drives a real trip with
/// `changePace(true)` / `changePace(false)`, then calls `sync()` against an
/// unreachable URL with a custom body builder that records `context.trips`.
///  * the builder receives the trip that just ended, under the id `onTrip`
///    reported, with its bounds and distance;
///  * the request fails, so a second `sync()` offers the **same** trip again —
///    a failed flush does not mark it sent.
/// The success half (marked sent once a request succeeds) is covered by the SDK
/// unit tests; it needs a server answering 200.
class Issue401Card extends StatefulWidget {
  const Issue401Card({super.key});

  @override
  State<Issue401Card> createState() => _Issue401CardState();
}

class _Issue401CardState extends State<Issue401Card>
    with IssueCardRun<Issue401Card> {
  static const _settle = Duration(seconds: 8);

  @override
  IssueRunner? get cardRunner => _run;

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

    final ends = <TripEvent>[];
    final offered = <List<Map<String, Object?>>>[];
    StreamSubscription<TripEvent>? endSub;

    try {
      await Tracelet.requestLocationAuthorization();
      await Tracelet.ready(
        Config(
          motion: const MotionConfig(
            motionDetectionMode: MotionDetectionMode.smart,
            stopTimeout: 1,
          ),
          // Unreachable on purpose: the request must fail, quickly.
          http: HttpConfig(
            url: deadUrl('locations'),
            autoSync: false,
            batchSync: true,
            maxRetries: 0,
          ),
          logger: const LoggerConfig(logLevel: LogLevel.debug),
        ),
      );
      Tracelet.setSyncBodyBuilder((context) async {
        offered.add(context.trips);
        return <String, Object?>{
          'location': context.locations,
          'trips': context.trips,
        };
      });
      endSub = Tracelet.onTrip(ends.add);

      // Trip detection is wired by start(), not ready() (#402).
      await Tracelet.start();
      setStatus('⏳ Driving one trip with changePace…');
      await Tracelet.changePace(true);
      await Future<void>.delayed(const Duration(seconds: 2));
      await Tracelet.changePace(false);
      final ended = await _waitFor(() => ends.isNotEmpty);
      final tripId = ended ? ends.last.tripId : null;
      check(
        'a trip ended',
        pass: ended && tripId != null,
        detail: ended
            ? 'onTrip reported $tripId'
            : 'no trip ended, so there is no summary to look for — the rows '
                  'below prove nothing',
      );
      if (!ended || tripId == null) {
        throw StateError('no trip to check');
      }

      setStatus('⏳ First sync (will fail)…');
      await Tracelet.sync();
      await _waitFor(() => offered.isNotEmpty);
      final first = offered.isEmpty
          ? const <Map<String, Object?>>[]
          : offered.last;
      final trip = first.where((t) => t['trip_id'] == tripId).firstOrNull;
      check(
        'the ended trip is offered to the sync',
        pass: trip != null,
        detail: trip != null
            ? 'context.trips carries $tripId'
            : 'context.trips had ${first.length} trip(s), none with $tripId',
      );
      check(
        'the summary carries bounds and distance',
        pass:
            trip != null &&
            trip['started_at'] != null &&
            trip['ended_at'] != null &&
            trip['distance'] is num,
        detail: trip == null
            ? 'no summary'
            : 'started_at ${trip['started_at']}, ended_at ${trip['ended_at']}, '
                  'distance ${trip['distance']} m',
      );

      setStatus('⏳ Second sync — the failed trip must be offered again…');
      final before = offered.length;
      await Tracelet.sync();
      await _waitFor(() => offered.length > before);
      final again =
          offered.length > before &&
          offered.last.any((t) => t['trip_id'] == tripId);
      check(
        'a failed flush does not mark it sent',
        pass: again,
        detail: again
            ? 'offered again after the request failed'
            : 'not offered again — a failed request settled it',
      );

      final header = allPass
          ? '✅ SUCCESS: the trip summary is stored and rides the sync.'
          : '❌ FAILED — #401 not satisfied on this build.';
      setStatus(
        '$header\n\n${results.join('\n')}\n\n'
        'With the default payload the same objects go out as a root `trips` '
        'array beside `location`. Before #401 the summary existed only as the '
        'onTrip event and context.trips did not exist.',
      );
    } catch (e) {
      setStatus('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      Tracelet.setSyncBodyBuilder(null);
      await endSub?.cancel();
      await Tracelet.stop();
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'trip summary trips sync payload backend trip_id persisted offline '
          'onTrip context.trips 401 402',
      title: '#401: trip summaries are stored and synced',
      description:
          'The trip summary only existed as the onTrip event and never reached '
          'a backend. Drives one trip, then syncs twice against an unreachable '
          'URL and checks the trip is offered both times.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
