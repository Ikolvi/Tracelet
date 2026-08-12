import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/test_server_endpoint.dart';

/// Issue #366 — a failed telematics sync deleted the events anyway.
///
/// With `syncTelematics: true`, the post-sync branch was entered whenever
/// telematics had been *attached* to the batch, not when the POST had
/// *succeeded*:
///
/// ```kotlin
/// val count = provider.syncBatchBlocking(configHttp, records)
/// if (count > 0L || hasTelematics) {      // ← true even on a failed POST
///     if (telematicsCleared) {
///         db.clearTelematicsEvents()      // ← DELETE FROM tracelet_telematics
///     }
/// }
/// ```
///
/// `syncBatchBlocking` returns `0` on HTTP failure, so an offline device ran
/// straight into an unpredicated `DELETE` and destroyed the driving events it
/// was supposed to be queueing. The exact scenario the reliability request in
/// #356 was asking to be protected from.
///
/// Two things were wrong and both are fixed. The events are now settled only
/// when the request that carried them actually succeeded, and settling means
/// `markTelematicsSynced(maxId)` over the range that was uploaded rather than a
/// table-wide delete — so an event recorded between the batch read and the POST
/// is no longer collateral. `markTelematicsSynced` already existed and the
/// custom-sync-body path already used it correctly; only the default payload
/// path took the destructive shortcut.
///
/// Marking instead of deleting also finally makes #313 hold: uploading an event
/// no longer removes it from the app's own history. That would leave the table
/// growing for the lifetime of the install, so the synced tail is trimmed to
/// the newest 1000 — unsynced rows are never touched by that trim, since they
/// are still owed to the server.
///
/// This card drives the failure path directly: it points the sync at a port
/// nothing is listening on, so the POST genuinely fails, and asserts the events
/// are still there afterwards. On the broken build they are gone.
class Issue366Card extends StatefulWidget {
  const Issue366Card({super.key});

  @override
  State<Issue366Card> createState() => _Issue366CardState();
}

class _Issue366CardState extends State<Issue366Card> {
  String _status = 'Idle';
  bool _running = false;

  /// A closed port on the loopback interface: the connection is refused
  /// immediately rather than hanging until a timeout, which keeps the card fast
  /// and makes the failure unambiguous.
  static const _deadUrl = 'http://127.0.0.1:9/telematics-sync';

  static const _eventCount = 3;

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
      await Tracelet.ready(
        const Config(
          http: HttpConfig(
            url: _deadUrl,
            // The sync under test is the explicit one below; auto-sync would
            // race it and could drain the table before the assertion runs.
            autoSync: false,
            syncTelematics: true,
            // One attempt per sync — the retry ladder only slows the card down,
            // since nothing is listening either way.
            maxRetries: 0,
          ),
          logger: LoggerConfig(logLevel: LogLevel.debug),
        ),
      );

      await Tracelet.destroyTelematicsEvents();

      for (var i = 0; i < _eventCount; i++) {
        await Tracelet.simulateTelematicsEvent(
          eventType: 'harsh_braking',
          severity: 0.8,
          latitude: 24.8607,
          longitude: 67.0011,
        );
      }

      final before = await Tracelet.getTelematicsEvents(50);
      check(
        'The events are stored to begin with',
        before.length == _eventCount,
        'stored ${before.length} of $_eventCount — if this row fails the rest '
            'of the card proves nothing',
      );

      // The sync itself is expected to fail. It must not throw: a refused
      // connection is an ordinary offline condition, not an error the app has
      // to handle.
      var threw = false;
      try {
        await Tracelet.sync();
      } catch (_) {
        threw = true;
      }
      check(
        'A refused sync is handled, not thrown',
        !threw,
        threw
            ? 'sync() threw on a connection failure'
            : 'sync() returned normally against a dead endpoint',
      );

      final after = await Tracelet.getTelematicsEvents(50);
      check(
        'A failed sync keeps the events',
        after.length == before.length,
        '${after.length} of ${before.length} event(s) survived the failed '
            'POST — the broken build deleted every one of them',
      );

      // Survival is only useful if they are still *sendable*: a row that stayed
      // in the table but got flagged synced would never be retried, which is
      // the same data loss with extra steps.
      final unsynced = after.where((TelematicsRecord e) => !e.synced).length;
      check(
        'The survivors are still queued for retry',
        unsynced == after.length,
        '$unsynced of ${after.length} still unsynced — a failed upload must '
            'not mark anything synced',
      );

      // A second failed attempt must be equally harmless. The bug deleted on
      // every failure, so repeated offline syncs compounded it.
      await Tracelet.sync();
      final afterSecond = await Tracelet.getTelematicsEvents(50);
      check(
        'Repeated failures stay non-destructive',
        afterSecond.length == before.length,
        '${afterSecond.length} event(s) after a second failed sync — offline '
            'retries must not erode the queue',
      );

      // -----------------------------------------------------------------------
      // The success path, which needs something that actually answers 200.
      // -----------------------------------------------------------------------
      final scanned = scannedSyncUrl();
      if (scanned != null) {
        await Tracelet.setConfig(Config(http: HttpConfig(url: scanned)));

        // With telematicsUrl unset the events ride the *location* payload, so
        // there has to be a location for them to ride. An empty batch would
        // leave them queued — correctly, but it would prove nothing here.
        await Tracelet.insertLocation(<String, Object?>{
          'uuid': 'issue-366-carrier',
          'coords': <String, Object?>{
            'latitude': 24.8607,
            'longitude': 67.0011,
            'accuracy': 8.0,
          },
        });

        await Tracelet.sync();
        await Future<void>.delayed(const Duration(milliseconds: 800));

        final delivered = await Tracelet.getTelematicsEvents(50);
        check(
          'A delivered event is marked synced, not deleted',
          delivered.length == before.length,
          '${delivered.length} of ${before.length} event(s) still readable '
              'after a successful sync — the old code deleted the table here, '
              'which is what made #313 fail in practice no matter how the '
              'history query was written',
        );
        check(
          'Delivered events are not re-sent',
          delivered.every((TelematicsRecord e) => e.synced),
          '${delivered.where((TelematicsRecord e) => e.synced).length} of '
              '${delivered.length} marked synced — settled over the uploaded '
              'id range, so the next batch does not ship them again',
        );
      }

      await Tracelet.destroyTelematicsEvents();
      await Tracelet.stop();

      final header = allPass
          ? '✅ SUCCESS: a failed telematics sync leaves the events queued.'
          : '❌ FAILED — #366 not satisfied on this build. See the failing rows.';

      final successPath = scanned == null
          ? 'The success path was skipped: it needs a reachable endpoint. Start '
                '`dart run example/test_server.dart`, scan its QR, and run this '
                'card again — it will then also assert that a delivered event '
                'is marked synced rather than deleted, which is the half that '
                'makes #313 hold in practice.'
          : 'The success path ran against $scanned: delivered events are marked '
                'synced over the uploaded id range instead of the table being '
                'cleared, so they stay readable through getTelematicsEvents() '
                '(#313) and are not re-sent.';

      _set(
        '$header\n\n${results.join('\n')}\n\n$successPath\n\n'
        'The synced tail is capped at the newest 1000 rows so retention cannot '
        'grow without bound; unsynced rows are exempt from the trim because '
        'they are still owed to the server.',
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
          'telematics syncTelematics driving events harsh braking sync failed '
          'offline clearTelematicsEvents markTelematicsSynced data loss '
          'deleted retry queue unsynced tracelet_telematics',
      title: '#366: a failed telematics sync deleted the events',
      description:
          'Stores driving events, points the sync at a refused port so the '
          'POST genuinely fails, and asserts the events are still present and '
          'still unsynced afterwards — twice over. The broken build ran an '
          'unpredicated DELETE whenever telematics had been attached, so an '
          'offline device destroyed exactly the data it was meant to be '
          'queueing.',
      status: _status,
      running: _running,
      onRun: _run,
    );
  }
}
