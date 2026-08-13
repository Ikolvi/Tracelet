import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #214 (part 2) — telematics/crash events were omitted from the custom
/// sync body builder; the builder only received `location_events`, never the
/// `tracelet_telematics` table.
///
/// This test enables `syncTelematics`, simulates a telematics event, registers a
/// custom body builder, syncs, and asserts the builder's `context.telematics`
/// contains the simulated event.
class Issue214Card extends StatefulWidget {
  const Issue214Card({super.key});

  @override
  State<Issue214Card> createState() => _Issue214CardState();
}

class _Issue214CardState extends State<Issue214Card>
    with IssueCardRun<Issue214Card> {
  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _test;

  Future<void> _test() async {
    setRunning(running: true);
    HttpServer? server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        await req.cast<List<int>>().drain<void>();
        req.response.statusCode = 200;
        req.response.write('{"ok":true}');
        await req.response.close();
      });

      // Capture what the builder actually receives.
      final captured = Completer<SyncBodyContext>();
      await Tracelet.setSyncBodyBuilder((ctx) async {
        if (!captured.isCompleted) captured.complete(ctx);
        return {'points': ctx.locations, 'events': ctx.telematics};
      });

      _set('Configuring with syncTelematics: true...');
      await Tracelet.ready(
        Config.passive().copyWith(
          http: HttpConfig(
            url: 'http://127.0.0.1:${server.port}/sync',
            autoSync: false,
            batchSync: true,
            syncTelematics: true,
          ),
          logger: const LoggerConfig(debug: true, logLevel: LogLevel.verbose),
        ),
      );

      await Tracelet.destroyLocations();
      // A location is required for the batch to sync (and thus call the builder).
      await Tracelet.insertLocation({
        'uuid': 'issue-214',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'latitude': 12.97,
        'longitude': 77.59,
        'accuracy': 5.0,
      });
      // Seed a telematics event into the tracelet_telematics table.
      await Tracelet.simulateTelematicsEvent(
        eventType: 'harsh_braking',
        severity: 0.85,
        latitude: 12.97,
        longitude: 77.59,
      );

      _set('Syncing (custom builder)...');
      await Tracelet.sync();
      final ctx = await captured.future.timeout(const Duration(seconds: 15));
      await Tracelet.setSyncBodyBuilder(null);

      if (ctx.telematics.isNotEmpty &&
          ctx.telematics.first['event_type'] == 'harsh_braking') {
        _set(
          '✅ SUCCESS: custom builder received telematics → '
          '${ctx.telematics.length} event(s), first=${ctx.telematics.first}',
        );
      } else {
        _set(
          '❌ FAILED: context.telematics empty — telematics not delivered to the '
          'custom builder (Issue #214). locations=${ctx.locations.length}',
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
      title: '#214: telematics in custom sync body builder',
      description:
          'Enables syncTelematics, simulates a telematics event, and asserts the '
          'custom body builder receives it via context.telematics (was bypassed). '
          'Set syncTelematics:false to confirm nothing is passed.',
      status: status,
      running: running,
      onRun: _test,
    );
  }
}
