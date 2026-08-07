import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issues #316 / #317 — background & killed-state tracking restore.
///
/// - **#316 (critical)** — standard (low-power) geofence-only tracking restored
///   as *continuous* tracking after a reboot, a task removal, or an iOS
///   killed-state relaunch. Every restore path started the full location engine
///   without consulting `geofenceModeHighAccuracy`, so a geofence-only app
///   silently converted to continuous GPS for the rest of the process lifetime:
///   on iOS the persistent blue location indicator #210 removed, on Android a
///   foreground service running solely for geofencing (prohibited by Google Play
///   as of 2026-10-28). Nothing converted it back until the app was reopened.
/// - **#317** — Android boot/task-removal tracking returned without retrying
///   when the SDK could not bootstrap, while leaving the foreground notification
///   posted. `START_STICKY` only redelivers after a process kill, so a service
///   that merely returned early was never called again.
///
/// Both bugs live in restore paths that only run when the app has been killed or
/// rebooted, which no in-process Dart test can enter — the app has to be alive to
/// run the assertion, and if it is alive the path is not taken. So this card does
/// not pretend to reproduce them.
///
/// What it *can* do is verify the invariant the fixes preserve on the live path:
/// that standard geofence-only mode does not hold the continuous-tracking
/// machinery. Two signals, both of which actually distinguish the modes:
///
/// 1. **No location updates are delivered.** In standard mode the engine is
///    stopped and crossings come from native region monitoring, so the location
///    stream must stay silent. This is the cross-platform signal.
/// 2. **No foreground service is promoted** (Android). This is the Play-policy
///    invariant #316 is about — an FGS running solely for geofencing.
///
/// Note `getCurrentLocationTuning()` is *not* usable here, which an earlier
/// version of this card got wrong: `LocationEngine.stop()` leaves the Rust
/// processor allocated (only `destroy()` clears it), so the tuning reads
/// non-null in both modes and distinguishes nothing.
class Issue316Card extends StatefulWidget {
  const Issue316Card({super.key});

  @override
  State<Issue316Card> createState() => _Issue316CardState();
}

class _Issue316CardState extends State<Issue316Card> {
  String _status = 'Idle';
  bool _running = false;

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
      await Tracelet.requestLocationAuthorization();

      // ── Standard (low-power) geofence-only mode ──
      // geofenceModeHighAccuracy defaults to false, which is the mode under
      // test; startOnBoot puts the session in the shape the boot restore path
      // would later resume.
      await Tracelet.ready(const Config(app: AppConfig(startOnBoot: true)));
      await Tracelet.startGeofences();
      // Give the native side a moment to settle into the mode.
      await Future<void>.delayed(const Duration(seconds: 2));

      final state = await Tracelet.getState();
      check(
        'standard geofence mode is enabled',
        state.enabled,
        'enabled=${state.enabled} trackingMode=${state.trackingMode}',
      );

      // The engine is stopped in this mode, so the location stream must stay
      // silent. Watch it for a window long enough to catch the ~1 Hz stream a
      // continuous session would produce.
      var lowPowerFixes = 0;
      final lowPowerSub = Tracelet.onLocation((_) => lowPowerFixes++);
      await Future<void>.delayed(const Duration(seconds: 8));
      await lowPowerSub.cancel();

      check(
        '#316 standard geofence-only mode delivers no continuous location updates',
        lowPowerFixes == 0,
        lowPowerFixes == 0
            ? 'no location updates in 8s — native region monitoring only, which '
                  'is what the reboot / task-removal / relaunch restore paths '
                  'must also do'
            : 'REGRESSED — $lowPowerFixes location update(s) arrived, so the '
                  'continuous engine is running for a low-power geofence-only '
                  'session',
      );

      if (!kIsWeb && Platform.isAndroid) {
        final health = await Tracelet.getForegroundServiceHealth();
        final promoted = health['serviceForeground'] == true;
        check(
          '#316 standard geofence-only mode runs no foreground service',
          !promoted,
          promoted
              ? 'REGRESSED — a foreground service is promoted solely for '
                    'geofencing, which Google Play prohibits as of 2026-10-28'
              : 'no foreground service promoted '
                    '(serviceRunning=${health['serviceRunning']})',
        );
      }

      // ── High-accuracy geofence mode genuinely needs the engine ──
      // Reported, not gated: this needs a real fix to arrive, and indoors the
      // GPS may legitimately produce none within the window. A zero here is
      // inconclusive rather than a failure, so it must not fail the card.
      await Tracelet.setConfig(
        const Config(geofence: GeofenceConfig(geofenceModeHighAccuracy: true)),
      );
      await Tracelet.startGeofences();

      var highAccuracyFixes = 0;
      final highAccuracySub = Tracelet.onLocation((_) => highAccuracyFixes++);
      await Future<void>.delayed(const Duration(seconds: 10));
      await highAccuracySub.cancel();

      results.add(
        highAccuracyFixes > 0
            ? 'ℹ️ #316 high-accuracy geofence mode is tracking — '
                  '$highAccuracyFixes location update(s) in 10s, so the fix did '
                  'not suppress the branch that genuinely needs continuous GPS'
            : 'ℹ️ #316 high-accuracy geofence mode produced no fix in 10s — '
                  'inconclusive indoors; not counted as a failure',
      );

      await Tracelet.stop();

      final header = allPass
          ? '✅ SUCCESS: standard geofence-only mode holds none of the '
                'continuous-tracking machinery.'
          : '❌ FAILED — see the failing rows below.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'Scope note: the actual #316/#317 failures only occur on restore paths '
        'that require the app to have been killed or the device rebooted, so '
        'they cannot be reproduced from a running Dart test. This card verifies '
        'the invariant those paths now share with the live path.\n\n'
        'To confirm #316 end-to-end by hand: start standard geofence-only '
        'tracking, force-stop or swipe away the app (Android) or wait for an '
        'iOS relaunch, then check that no foreground-service notification '
        '(Android) or blue location indicator (iOS) appears, and that geofence '
        'ENTER/EXIT events still arrive.\n\n'
        'To confirm #317: reboot with startOnBoot enabled. If the SDK cannot '
        'bootstrap, the service now retries with backoff (5s → 160s) and then '
        'stops instead of leaving a tracking notification over a session that '
        'never started.',
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
          'geofence geofenceModeHighAccuracy low power standard mode boot '
          'reboot BootReceiver task removal onTaskRemoved killed state '
          'autoResumeTracking foreground service background location indicator '
          'startBootTracking bootstrapForBackground retry START_STICKY 316 317',
      title: '#316–#317: geofence-only & boot restore paths',
      description:
          'Checks that standard (low-power) geofence-only mode delivers no '
          'location updates and promotes no foreground service — the invariant '
          'the reboot, task-removal and killed-state restore paths were '
          'violating, silently converting geofence-only apps to continuous '
          'tracking. Also documents how to confirm the Android boot-retry fix by '
          'hand.',
      status: _status,
      running: _running,
      onRun: _run,
    );
  }
}
