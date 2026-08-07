import 'dart:async';

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
/// machinery. `getCurrentLocationTuning()` returns non-null only once a tracking
/// session has built a native location processor, which is exactly what the
/// buggy restore paths were creating and the correct ones are not. The card
/// checks that entering standard geofence mode does not, and that high-accuracy
/// mode does — the same branch the restore paths now take.
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

      final lowPowerTuning = await Tracelet.getCurrentLocationTuning();
      check(
        '#316 standard geofence-only mode runs no continuous location processor',
        lowPowerTuning == null,
        lowPowerTuning == null
            ? 'no processor built — native region monitoring only, which is what '
                  'the reboot / task-removal / relaunch restore paths must also do'
            : 'REGRESSED — a location processor is active '
                  '(distanceFilter=${lowPowerTuning.distanceFilter}), so '
                  'continuous tracking is running for a low-power geofence-only '
                  'session',
      );

      // ── High-accuracy geofence mode genuinely needs the engine ──
      await Tracelet.setConfig(
        const Config(geofence: GeofenceConfig(geofenceModeHighAccuracy: true)),
      );
      await Tracelet.startGeofences();
      await Future<void>.delayed(const Duration(seconds: 3));

      final highAccuracyTuning = await Tracelet.getCurrentLocationTuning();
      check(
        '#316 high-accuracy geofence mode does start the location processor',
        highAccuracyTuning != null,
        highAccuracyTuning != null
            ? 'processor active (distanceFilter=${highAccuracyTuning.distanceFilter}) '
                  '— in-app proximity detection needs continuous GPS, so the fix '
                  'must not suppress this branch'
            : 'no processor — the fix over-corrected and broke high-accuracy '
                  'geofencing',
      );

      await Tracelet.stop();

      final header = allPass
          ? '✅ SUCCESS: geofence mode only builds a continuous location '
                'processor when high-accuracy mode asks for one.'
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
          'Checks that standard (low-power) geofence-only mode does not build a '
          'continuous location processor while high-accuracy mode does — the '
          'invariant the reboot, task-removal and killed-state restore paths '
          'were violating, silently converting geofence-only apps to continuous '
          'tracking. Also documents how to confirm the Android boot-retry fix by '
          'hand.',
      status: _status,
      running: _running,
      onRun: _run,
    );
  }
}
