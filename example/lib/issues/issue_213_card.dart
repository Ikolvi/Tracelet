import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #213 — a debounced auto-sync that was already waiting out its
/// `autoSyncDelay` kept firing up to ~10s after `Tracelet.stop()`, because the
/// active sync provider never cancelled the pending job.
///
/// This test enables auto-sync with a short delay, queues a sync (insertLocation
/// schedules the debounce), immediately calls `stop()`, then waits past the
/// delay and asserts the loopback server received **no** request.
class Issue213Card extends StatefulWidget {
  const Issue213Card({super.key});

  @override
  State<Issue213Card> createState() => _Issue213CardState();
}

class _Issue213CardState extends State<Issue213Card>
    with IssueCardRun<Issue213Card> {
  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _test;

  Future<void> _test() async {
    setRunning(running: true);
    HttpServer? server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requestCount = 0;
      server.listen((req) async {
        requestCount++;
        await utf8.decoder.bind(req).join();
        req.response.statusCode = 200;
        req.response.write('{"ok":true}');
        await req.response.close();
      });

      const delayMs = 4000;
      _set('Configuring auto-sync (delay ${delayMs}ms)...');
      await Tracelet.setSyncBodyBuilder(null);
      await Tracelet.ready(
        Config.passive().copyWith(
          http: HttpConfig(
            url: 'http://127.0.0.1:${server.port}/sync',
            autoSyncDelay: delayMs,
            batchSync: true,
          ),
          logger: const LoggerConfig(debug: true, logLevel: LogLevel.verbose),
        ),
      );

      await Tracelet.destroyLocations();
      // Queues the debounced sync (insertLocation notifies the sync provider).
      await Tracelet.insertLocation({
        'uuid': 'issue-213',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'latitude': 12.97,
        'longitude': 77.59,
        'accuracy': 5.0,
      });

      // Stop immediately — this must cancel the pending debounce.
      _set('Inserted a location; calling stop() before the delay elapses...');
      await Tracelet.stop();

      // Wait well past the delay; a correct SDK fires nothing.
      _set('Stopped. Waiting ${delayMs + 3000}ms to confirm no sync fires...');
      await Future<void>.delayed(const Duration(milliseconds: delayMs + 3000));

      if (requestCount == 0) {
        _set(
          '✅ SUCCESS: no sync fired after stop() — the pending debounce was '
          'cancelled (requests = 0).',
        );
      } else {
        _set(
          '❌ FAILED: $requestCount request(s) hit the server after stop() — '
          'the debounced sync was not cancelled (Issue #213).',
        );
      }
    } catch (e) {
      _set('❌ FAILED: $e');
    } finally {
      await server?.close(force: true);
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      title: '#213: background sync fires after stop()',
      description:
          'Queues a debounced auto-sync, calls stop() before the delay elapses, '
          'then waits past the delay and asserts the loopback server received '
          'NO request. Takes ~7s.',
      status: status,
      running: running,
      onRun: _test,
    );
  }
}
