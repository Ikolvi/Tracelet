import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #212 — the reverse-geocoded `address` is saved to SQLite but was dropped
/// from the **default** (non-custom-builder) sync payload because the Rust
/// `SyncLocationRecord` omitted it.
///
/// This test inserts a location carrying an `address`, runs a **default** sync
/// (no custom body builder) to a loopback server, and asserts the captured
/// payload contains the address as a nested object.
class Issue212Card extends StatefulWidget {
  const Issue212Card({super.key});

  @override
  State<Issue212Card> createState() => _Issue212CardState();
}

class _Issue212CardState extends State<Issue212Card>
    with IssueCardRun<Issue212Card> {
  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _test;

  Future<void> _test() async {
    setRunning(running: true);
    HttpServer? server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final captured = Completer<Map<String, dynamic>>();
      server.listen((req) async {
        final content = await utf8.decoder.bind(req).join();
        req.response.statusCode = 200;
        req.response.write('{"ok":true}');
        await req.response.close();
        if (!captured.isCompleted) {
          captured.complete(jsonDecode(content) as Map<String, dynamic>);
        }
      });

      // Default payload path — make sure no custom builder is registered.
      await Tracelet.setSyncBodyBuilder(null);
      _set('Configuring default sync...');
      await Tracelet.ready(
        Config.passive().copyWith(
          http: HttpConfig(
            url: 'http://127.0.0.1:${server.port}/sync',
            autoSync: false,
            batchSync: true,
          ),
          logger: const LoggerConfig(debug: true, logLevel: LogLevel.verbose),
        ),
      );

      await Tracelet.destroyLocations();
      await Tracelet.insertLocation({
        'uuid': 'issue-212',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'latitude': 48.8566,
        'longitude': 2.3522,
        'accuracy': 5.0,
        // Persisted into the SQLite `address` column.
        'address': {'city': 'Paris', 'country': 'FR'},
      });

      _set('Syncing default payload...');
      await Tracelet.sync();
      final body = await captured.future.timeout(const Duration(seconds: 15));

      final list = body['location'];
      final loc = (list is List && list.isNotEmpty)
          ? list.first as Map<String, dynamic>
          : <String, dynamic>{};
      final addr = loc['address'];
      if (addr is Map && addr['city'] == 'Paris') {
        _set('✅ SUCCESS: default payload includes address → $addr');
      } else {
        _set(
          '❌ FAILED: address missing from default payload. '
          'location keys = ${loc.keys.toList()}',
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
      title: '#212: address missing from default payload',
      description:
          'Inserts a location with an address, runs a DEFAULT sync (no custom '
          'builder) to a loopback server, and asserts the payload contains the '
          'address as a nested object.',
      status: status,
      running: running,
      onRun: _test,
    );
  }
}
