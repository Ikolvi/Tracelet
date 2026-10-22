import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #432 — on Android, a continuous location request outlived `stop()`
/// and kept delivering fixes every few seconds until the process died.
///
/// `PlayLocationClient.requestLocationUpdates` wrapped the SDK's callback in a
/// *new* Play `LocationCallback` on every call and overwrote its map entry. The
/// engine re-requests in place with the same callback whenever the provider
/// options change — `updateLocationProviderOptions`, `setConfig` while
/// streaming, the GPS fallback, the battery-budget overlay — and the fused
/// client only replaces a request when it is handed the *same*
/// `LocationCallback`. So each in-place update left the previous wrapper
/// registered with nothing pointing at it, and `stop()` could only remove the
/// newest. The orphan fed the pipeline until process death, and
/// `changePace(false)` could not reach it because the engine already reported
/// not tracking. The reporter's battery ran flat over 4 h 40 m.
///
/// The wrapper is now reused per callback, a wrapper that is no longer current
/// unregisters itself, and a continuous callback the engine no longer holds
/// drops its fix and unregisters.
///
/// **What this card proves**, on Play-services devices: it drives the exact
/// sequence that orphaned a request — start moving, update the provider
/// options in place twice, park with `changePace(false)` — then watches for
/// 20 s. No location event may arrive, and the log must not contain the "fix
/// arrived while continuous updates are stopped" line the field report showed
/// after every park.
class Issue432Card extends StatefulWidget {
  const Issue432Card({super.key});

  @override
  State<Issue432Card> createState() => _Issue432CardState();
}

class _Issue432CardState extends State<Issue432Card>
    with IssueCardRun<Issue432Card> {
  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  @override
  IssueRunner? get cardRunner => _run;

  static const _strayFix = 'a fix arrived while continuous updates are stopped';
  static const _superseded = 'superseded continuous callback';

  Future<void> _run() async {
    setRunning(running: true);
    final results = <String>[];
    var allPass = true;
    StreamSubscription<Location>? sub;

    void check(String name, {required bool pass, required String detail}) {
      results.add('${pass ? '✅' : '❌'} $name — $detail');
      if (!pass) allPass = false;
    }

    try {
      if (!_isAndroid) {
        setStatus(
          'ℹ️ Android only. The orphan lived in the Play-services callback '
          'wrapper; iOS has a single CLLocationManager per engine.',
        );
        return;
      }

      await Tracelet.ready(
        const Config(
          geo: GeoConfig(
            distanceFilter: 0,
            desiredAccuracy: DesiredAccuracy.high,
          ),
          motion: MotionConfig(isMoving: true),
          android: AndroidConfig(
            locationUpdateInterval: 1000,
            fastestLocationUpdateInterval: 500,
          ),
          http: HttpConfig(autoSync: false),
          persistence: PersistenceConfig(persistMode: PersistMode.none),
        ),
      );
      await Tracelet.destroyLog();

      setStatus('⏳ Streaming, then updating the provider options in place…');
      await Tracelet.start();
      await Tracelet.changePace(true);
      await Future<void>.delayed(const Duration(seconds: 3));

      // Each of these re-requested with the same callback — the step that
      // orphaned a Play wrapper before the fix.
      final first = await Tracelet.updateLocationProviderOptions(
        desiredAccuracy: DesiredAccuracy.medium,
        distanceFilter: 0,
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      final second = await Tracelet.updateLocationProviderOptions();
      await Future<void>.delayed(const Duration(seconds: 2));
      check(
        'the provider options were updated in place while streaming',
        pass: first && second,
        detail: first && second
            ? 'two in-place re-requests on the live stream'
            : 'updateLocationProviderOptions returned false — tracking was '
                  'not live, so the orphaning step did not run',
      );

      setStatus('⏳ Parked with changePace(false) — watching for 20 s…');
      await Tracelet.changePace(false);
      await Future<void>.delayed(const Duration(seconds: 1));

      var strayEvents = 0;
      sub = Tracelet.onLocation((l) {
        if (l.event == null || l.event == 'location') strayEvents++;
      });
      await Future<void>.delayed(const Duration(seconds: 20));
      await sub.cancel();
      sub = null;

      final logs = await Tracelet.getLogs(500);
      final strayLines = logs
          .where((l) => l.message.contains(_strayFix))
          .toList();
      final supersededLines = logs
          .where((l) => l.message.contains(_superseded))
          .toList();

      check(
        'no continuous fix reaches the app after the park',
        pass: strayEvents == 0,
        detail: strayEvents == 0
            ? '0 location events in 20 s'
            : '$strayEvents location events after changePace(false) — a '
                  'request outlived the park',
      );
      check(
        'no "fix arrived while stopped" line',
        pass: strayLines.isEmpty,
        detail: strayLines.isEmpty
            ? 'the stream really stopped'
            : strayLines.first.message,
      );
      if (supersededLines.isNotEmpty) {
        results.add(
          'ℹ️ the engine guard caught and unregistered a stray callback: '
          '${supersededLines.first.message}',
        );
      }

      await Tracelet.stop();

      final header = allPass
          ? '✅ SUCCESS: nothing streams after the park.'
          : '❌ FAILED — #432 not satisfied on this build.';
      setStatus(
        '$header\n\n${results.join('\n')}\n\n'
        'On a build before the fix this reproduces on any Play-services '
        'device: fixes keep arriving every second after the park, the log '
        'shows "$_strayFix", and only killing the process stops them. '
        'Devices without Play services use the AOSP client, which already '
        'replaced its listener and was never affected.',
      );
    } catch (e) {
      setStatus('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      await sub?.cancel();
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'android location request outlives stop changePace orphan callback '
          'fused play services battery drain updateLocationProviderOptions 432',
      title: '#432: no location request outlives stop()',
      description:
          'Each in-place re-request (provider options, setConfig while '
          'streaming, GPS fallback) registered a new Play callback without '
          'removing the old one, so fixes kept arriving after stop() until the '
          'process died. Re-requests in place twice, parks, and watches 20 s '
          'for stray fixes.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
