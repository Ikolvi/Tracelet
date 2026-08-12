import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #361 — `maxDaysToPersist` / `maxRecordsToPersist` accepted but never
/// enforced.
///
/// Both keys round-tripped correctly — `ready()` took them, `State.config` read
/// them back — and then nothing on any platform ever scoped a `DELETE` against
/// `location_events`. The local queue grew without bound however they were set,
/// which for an app offline for a long stretch is a storage problem rather than
/// a correctness nitpick.
///
/// The feature was real up to 3.0, implemented as `pruneOldLocations` /
/// `enforceMaxRecords` on the platform-native `TraceletDatabase` classes. It was
/// not removed deliberately: `2afc926f` ("prepare for 3.1.0") migrated the
/// persist path on both platforms off those classes and onto the shared Rust
/// core, replacing the function body with a sink fan-out — and the retention
/// calls, which lived in the same body and hung off the same `db` object, went
/// with it. The Rust core never gained an equivalent, so there was nothing left
/// to point them at. What survived was the amortization counter, the
/// `PRUNE_EVERY_N_INSERTS` constant, and a docstring claiming the function
/// "also runs retention pruning" — which is why the gap read as implemented.
///
/// The caps are now applied at the DB insert itself, which is the single funnel
/// every persisted location passes through. Deliberately not back in
/// `LocationEngine`, where the leftover counter sat: the engine's persist path
/// is only one caller, and the public `insertLocation()` API this card uses —
/// the same one the reporter used — does not go through it.
///
/// **Pruning is amortized over 100 inserts, not run on every insert**, so that a
/// COUNT-and-DELETE is not attached to every GPS fix. That is what this card
/// measures: not "the count never exceeds the cap", which is not the promise,
/// but "the count is repeatedly cut back to the cap, and is bounded by
/// cap + window". A build with the bug never returns to the cap at all.
class Issue361Card extends StatefulWidget {
  const Issue361Card({super.key});

  @override
  State<Issue361Card> createState() => _Issue361CardState();
}

class _Issue361CardState extends State<Issue361Card> {
  String _status = 'Idle';
  bool _running = false;

  /// The record cap under test — the reporter's own value.
  static const _maxRecords = 3;

  /// Must match `PRUNE_EVERY_N_INSERTS` in the native SDKs.
  static const _pruneWindow = 100;

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

    try {
      // autoSync: false is essential — a successful sync prunes synced records
      // on its own, which would drain the queue and make an unenforced cap look
      // enforced. The queue must only ever shrink because retention shrank it.
      await Tracelet.ready(
        const Config(
          http: HttpConfig(autoSync: false),
          persistence: PersistenceConfig(
            maxRecordsToPersist: _maxRecords,
            maxDaysToPersist: -1,
          ),
          logger: LoggerConfig(logLevel: LogLevel.debug),
        ),
      );

      final state = await Tracelet.getState();
      final reportedCap = state.config?.persistence.maxRecordsToPersist;
      check(
        'The cap is accepted and read back',
        reportedCap == _maxRecords,
        'State.config reports $reportedCap — this much always passed, '
            'including on the broken build',
      );

      // ---------------------------------------------------------------------
      // 1. maxRecordsToPersist
      // ---------------------------------------------------------------------
      await Tracelet.destroyLocations();

      // The amortization counter is process-scoped and this card cannot reset
      // it, so which insert prunes is unknown here. Walking a full window plus
      // one guarantees at least one prune, whatever the phase — and tracking the
      // low-water mark makes the assertion independent of where it landed.
      var lowWater = 1 << 30;
      var peak = 0;
      for (var i = 0; i <= _pruneWindow; i++) {
        await Tracelet.insertLocation(<String, Object?>{
          'uuid': 'issue-361-cap-$i',
          'coords': <String, Object?>{
            'latitude': 37.7749,
            'longitude': -122.4194,
            'accuracy': 8.0,
          },
        });
        final count = await Tracelet.getPendingLocationCount();
        if (count < lowWater) lowWater = count;
        if (count > peak) peak = count;
      }

      check(
        'The record cap is actually applied',
        lowWater <= _maxRecords,
        'the queue was cut back to $lowWater record(s) against a cap of '
            '$_maxRecords across ${_pruneWindow + 1} inserts — on the broken '
            'build it only ever grew',
      );
      check(
        'The queue stays bounded by cap + window',
        peak <= _maxRecords + _pruneWindow,
        'peaked at $peak record(s), ceiling '
            '${_maxRecords + _pruneWindow} — the reporter saw it pass 106 and '
            'keep going',
      );

      final kept = await Tracelet.getLocations();
      final keptIds = kept.map((Location l) => l.uuid).toSet();
      check(
        'The oldest records are the ones evicted',
        !keptIds.contains('issue-361-cap-0'),
        'the first insert is gone and ${keptIds.length} newer record(s) '
            'remain — retention keeps the freshest data, not an arbitrary slice',
      );

      // ---------------------------------------------------------------------
      // 2. maxDaysToPersist
      // ---------------------------------------------------------------------
      await Tracelet.destroyLocations();
      await Tracelet.setConfig(
        const Config(
          persistence: PersistenceConfig(
            maxDaysToPersist: 1,
            maxRecordsToPersist: -1,
          ),
        ),
      );

      // A fixture two days old against a one-day window, plus a fresh record
      // that must survive it — an age prune that took both would be no better
      // than one that took neither.
      const agedId = 'issue-361-aged';
      const freshId = 'issue-361-fresh';
      await Tracelet.insertLocation(<String, Object?>{
        'uuid': agedId,
        'timestamp': DateTime.now()
            .toUtc()
            .subtract(const Duration(days: 2))
            .toIso8601String(),
        'coords': <String, Object?>{
          'latitude': 37.0,
          'longitude': -122.0,
          'accuracy': 8.0,
        },
      });
      await Tracelet.insertLocation(<String, Object?>{
        'uuid': freshId,
        'coords': <String, Object?>{
          'latitude': 37.1,
          'longitude': -122.1,
          'accuracy': 8.0,
        },
      });

      // Walk to the next prune, again without assuming the counter's phase.
      var agedSurvived = true;
      for (var i = 0; i <= _pruneWindow; i++) {
        final ids = (await Tracelet.getLocations())
            .map((Location l) => l.uuid)
            .toSet();
        if (!ids.contains(agedId)) {
          agedSurvived = false;
          break;
        }
        await Tracelet.insertLocation(<String, Object?>{
          'uuid': 'issue-361-age-pad-$i',
          'coords': <String, Object?>{
            'latitude': 37.2,
            'longitude': -122.2,
            'accuracy': 8.0,
          },
        });
      }

      final afterAge = (await Tracelet.getLocations())
          .map((Location l) => l.uuid)
          .toSet();
      check(
        'A record older than maxDaysToPersist is purged',
        !agedSurvived,
        'the two-day-old fixture is gone under a one-day window — the reporter '
            'watched it survive indefinitely',
      );
      check(
        'A record inside the window is kept',
        afterAge.contains(freshId),
        'the fresh record is still there, so the age prune scoped its DELETE '
            'rather than clearing the table',
      );

      await Tracelet.destroyLocations();
      await Tracelet.stop();

      final header = allPass
          ? '✅ SUCCESS: both persistence caps are enforced against the local '
                'queue.'
          : '❌ FAILED — #361 not satisfied on this build. See the failing rows.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'Enforcement lives in the Rust core '
        '(prune_locations_older_than / enforce_max_location_records), so both '
        'platforms share one implementation instead of the two hand-written '
        'SQL copies that were lost in the 3.1.0 migration. Age is read from '
        'timestamp_ms, which is indexed; rows written before that column '
        'existed fall back to the text timestamp, and a row whose timestamp '
        'cannot be parsed is kept rather than treated as ancient — retention '
        'must never be the reason data disappears on a guess. The audit-chain '
        'rows go with the locations they belong to, so pruning cannot move the '
        'unbounded growth into audit_trail.',
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
          'maxDaysToPersist maxRecordsToPersist PersistenceConfig retention '
          'prune pruning location_events unbounded queue storage growth '
          'getPendingLocationCount config accepted never enforced offline',
      title: '#361: maxDaysToPersist / maxRecordsToPersist never enforced',
      description:
          'Inserts a full prune window of locations under a 3-record cap and '
          'asserts the queue is cut back to it, then ages a two-day-old '
          'fixture out under a one-day window while a fresh record survives. '
          'Pruning is amortized over 100 inserts, so this measures the queue '
          'returning to the cap and staying bounded by cap + window — not a '
          'per-insert ceiling, which was never the promise.',
      status: _status,
      running: _running,
      onRun: _run,
    );
  }
}
