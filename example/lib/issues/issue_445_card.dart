import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #445 — stored locations lost `altitudeAccuracy`, `speedAccuracy` and
/// `headingAccuracy`.
///
/// The live `onLocation` map carried them, but the database had no column for
/// them, so `getLocations()`, the custom sync body builder and the default
/// payload never did. Dart then filled the gap with `0`, a "perfect" accuracy.
///
/// **What this card proves**: one recorded fix, read back with
/// `getLocations()`, carries the same three accuracies as the live event for
/// the same uuid. A platform that reports no value gives `-1` on both sides.
class Issue445Card extends StatefulWidget {
  const Issue445Card({super.key});

  @override
  State<Issue445Card> createState() => _Issue445CardState();
}

class _Issue445CardState extends State<Issue445Card>
    with IssueCardRun<Issue445Card> {
  @override
  IssueRunner? get cardRunner => _run;

  Future<void> _run() async {
    setRunning(running: true);
    StreamSubscription<Location>? sub;
    try {
      await Tracelet.requestLocationAuthorization();
      await Tracelet.ready(
        const Config(
          geo: GeoConfig(distanceFilter: 0),
          http: HttpConfig(autoSync: false),
        ),
      );
      final live = Completer<Location>();
      sub = Tracelet.onLocation((l) {
        if (!live.isCompleted) live.complete(l);
      });
      await Tracelet.start();
      await Tracelet.changePace(true);
      setStatus('⏳ Waiting for a live fix…');
      final fix = await live.future.timeout(const Duration(seconds: 60));
      await Future<void>.delayed(const Duration(seconds: 1));

      final stored = (await Tracelet.getLocations()).where(
        (l) => l.uuid == fix.uuid,
      );
      if (stored.isEmpty) {
        setStatus('❌ FAILED: the live fix ${fix.uuid} was not stored.');
        return;
      }
      String fmt(Coords c) =>
          'alt ${c.altitudeAccuracy}, speed ${c.speedAccuracy}, '
          'heading ${c.headingAccuracy}';
      final a = fix.coords;
      final b = stored.first.coords;
      final same =
          a.altitudeAccuracy == b.altitudeAccuracy &&
          a.speedAccuracy == b.speedAccuracy &&
          a.headingAccuracy == b.headingAccuracy;
      setStatus(
        '${same ? '✅ SUCCESS: stored accuracies match the live fix.' : '❌ FAILED — #445 not satisfied on this build.'}\n\n'
        'live:   ${fmt(a)}\nstored: ${fmt(b)}\n\n'
        '-1 means the platform reported no value; 0.0 on the stored side with '
        'a real live value is the bug.',
      );
    } on TimeoutException {
      setStatus('❌ No live fix within 60 s — nothing to compare.');
    } catch (e) {
      setStatus('❌ FAILED: $e');
    } finally {
      await sub?.cancel();
      await Tracelet.stop();
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'altitudeAccuracy speedAccuracy headingAccuracy vertical accuracy '
          'stored getLocations sync payload 445',
      title: '#445: stored locations keep their accuracies',
      description:
          'altitude/speed/heading accuracy were dropped when a fix was stored, '
          'and Dart read the gap as 0. Compares one live fix with its stored '
          'copy.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
