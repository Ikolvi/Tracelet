import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #238 — `setSyncBodyBuilder` fails with status=0 "Custom body sync failed"
///
/// This test spins up a local HttpServer, configures Tracelet to sync to it,
/// registers a custom sync body builder, and inserts a location.
/// It verifies if the custom body actually reaches the server, and what
/// status code is reported by `onHttp`.
class Issue238Card extends StatefulWidget {
  const Issue238Card({super.key});

  @override
  State<Issue238Card> createState() => _Issue238CardState();
}

class _Issue238CardState extends State<Issue238Card>
    with IssueCardRun<Issue238Card> {
  HttpServer? _server;
  StreamSubscription? _syncSub;

  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _test;

  Future<void> _test() async {
    if (running) return;
    setRunning(running: true);
    _set('Starting local server...');

    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = _server!.port;
      _set('Listening on port $port. Starting SDK...');

      var requestReceived = false;

      // Handle inbound requests.
      _server!.listen((HttpRequest request) async {
        requestReceived = true;
        // Read body to drain stream
        await utf8.decoder.bind(request).join();

        // Return 400 Bad Request to simulate the server rejecting it.
        request.response.statusCode = 400;
        request.response.write('Bad Request');
        await request.response.close();
      });

      // Listen to SDK HTTP sync events.
      final completer = Completer<HttpEvent>();
      _syncSub = Tracelet.onHttp((event) {
        if (!completer.isCompleted) completer.complete(event);
      });

      // Configure SDK to hit the local server.
      await Tracelet.ready(
        Config(
          http: HttpConfig(url: 'http://127.0.0.1:$port/sync', batchSync: true),
        ),
      );

      // Register the custom sync body builder. Expects Future<Map<String, Object?>>
      Tracelet.setSyncBodyBuilder((context) async {
        return {'custom_payload': true, 'locations': context.locations};
      });

      _set('Inserting location and forcing sync...');
      await Tracelet.insertLocation({'latitude': 12.34, 'longitude': 56.78});
      await Tracelet.sync();

      _set('Waiting for sync result...');
      final result = await completer.future.timeout(
        const Duration(seconds: 15),
      );

      if (!requestReceived) {
        _set(
          '❌ FAILED: Server received no request. SDK reported status: ${result.status}, responseText: "${result.responseText}"',
        );
      } else if (result.status == 0) {
        _set(
          '❌ FAILED: Server received request, but SDK masked status as 0. responseText: "${result.responseText}"',
        );
      } else if (result.status == 400) {
        _set('✅ SUCCESS: Server received request, SDK reported status: 400.');
      } else {
        _set(
          '⚠️ UNEXPECTED: Server received request, SDK reported status: ${result.status}',
        );
      }
    } catch (e) {
      if (e is TimeoutException) {
        _set('❌ ERROR: Timeout waiting for sync callback');
      } else {
        _set('❌ ERROR: $e');
      }
    } finally {
      await _server?.close(force: true);
      _server = null;
      await _syncSub?.cancel();
      _syncSub = null;
      await Tracelet.stop();
      Tracelet.setSyncBodyBuilder(null);
      setRunning(running: false);
    }
  }

  @override
  void dispose() {
    _server?.close(force: true);
    _syncSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      title: 'Issue #238: setSyncBodyBuilder fails with status=0',
      description:
          'Sets a custom sync body builder and configures the SDK to '
          'sync to a local HttpServer. The server intentionally returns '
          'a 400 Bad Request to simulate rejection. The test asserts that '
          'the SDK correctly reports status=400 instead of masking it as 0.',
      status: status,
      running: running,
      onRun: _test,
    );
  }
}
