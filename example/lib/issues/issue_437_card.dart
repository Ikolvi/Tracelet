import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';
import 'package:tracelet_example/issues/test_server_endpoint.dart';

/// Issue #437 — auto-sync never drained the location queue.
///
/// Each trigger uploaded exactly one batch and returned, and a location stored
/// while a sync was in flight scheduled nothing, because the "already
/// running" check covered the debounce *and* the HTTP request with its
/// retries. With `maxBatchSize: 1` the queue could not shrink at all: the
/// server replayed the route one point per new fix, and a parked device, which
/// stores nothing, never caught up. `autoSyncThreshold` was never read, the
/// custom-body path ignored `httpTimeout` and the backoff settings and retried
/// a read timeout (sending the batch twice), and a manual `sync()` could race
/// the auto-sync over the same rows. Reading the newest rows when
/// `locationsOrderDirection` was descending also deleted older rows that had
/// never been sent.
///
/// Every trigger now drains batch after batch until the queue is empty or a
/// batch fails; a request made during a sync is picked up before the run ends;
/// a manual sync shares the auto-sync lock and hands a full batch's remainder
/// to the drain.
///
/// **What this card proves**, against the paired example test server: five
/// rows, `maxBatchSize: 1`, one `sync()` — the queue must reach zero without
/// any further insert. Before the fix four rows stayed queued. Without a
/// paired server it says so and claims nothing.
class Issue437Card extends StatefulWidget {
  const Issue437Card({super.key});

  @override
  State<Issue437Card> createState() => _Issue437CardState();
}

class _Issue437CardState extends State<Issue437Card>
    with IssueCardRun<Issue437Card> {
  @override
  IssueRunner? get cardRunner => _run;

  static const _rows = 5;

  Future<void> _run() async {
    setRunning(running: true);
    final results = <String>[];
    var allPass = true;

    void check(String name, {required bool pass, required String detail}) {
      results.add('${pass ? '✅' : '❌'} $name — $detail');
      if (!pass) allPass = false;
    }

    try {
      final url = scannedSyncUrl();
      if (url == null) {
        setStatus(
          'ℹ️ Not verified — needs a server that answers 200. Run '
          '`dart run example/test_server.dart` and pair by scanning its QR '
          'code, then run again.',
        );
        return;
      }

      await Tracelet.ready(
        Config(
          http: HttpConfig(
            url: url,
            autoSync: true,
            batchSync: true,
            // The reporter's "real-time" profile: the worst case.
            maxBatchSize: 1,
            autoSyncDelay: 0,
          ),
        ),
      );
      await Tracelet.destroyLocations();

      for (var i = 0; i < _rows; i++) {
        await Tracelet.insertLocation({
          'uuid': 'issue-437-$i',
          'timestamp': DateTime.now()
              .toUtc()
              .add(Duration(seconds: i))
              .toIso8601String(),
          'latitude': 48.8566 + i * 0.001,
          'longitude': 2.3522,
          'accuracy': 5.0,
        });
      }
      final queued = await Tracelet.getCount();
      check(
        'the backlog is in place',
        pass: queued == _rows,
        detail: '$queued rows queued',
      );

      setStatus('⏳ One sync() with maxBatchSize: 1 — waiting for the drain…');
      await Tracelet.sync();

      var remaining = await Tracelet.getCount();
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (remaining > 0 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        remaining = await Tracelet.getCount();
      }

      check(
        'the whole queue drains from one trigger',
        pass: remaining == 0,
        detail: remaining == 0
            ? 'all $_rows rows uploaded, one per batch, with no new insert'
            : '$remaining of $_rows rows still queued — one batch per trigger '
                  '(the bug), or the server stopped answering',
      );

      final header = allPass
          ? '✅ SUCCESS: a single trigger drains the backlog.'
          : '❌ FAILED — #437 not satisfied on this build.';
      setStatus(
        '$header\n\n${results.join('\n')}\n\n'
        'Before the fix, one sync() removed exactly one row here and the rest '
        'waited for later inserts — none come from a parked device, so the '
        'server stayed behind indefinitely. A request made while a sync is in '
        'flight is also kept now; that half is covered by the SDK unit tests '
        '(AutoSyncDrainerTest), since timing it from here would be flaky.',
      );
    } catch (e) {
      setStatus('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'auto sync queue backlog drain maxBatchSize batch stale position '
          'server autoSyncThreshold httpTimeout retry duplicate 437',
      title: '#437: auto-sync drains the whole queue',
      description:
          'Each trigger uploaded one batch, and a fix stored during a sync '
          'scheduled nothing, so with maxBatchSize: 1 the server replayed the '
          'route one point per new fix. Inserts five rows, syncs once, and '
          'checks the queue reaches zero. Needs the paired test server.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
