import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #353 — Android: geofences added alongside continuous tracking (not
/// `startGeofences()`) were unregistered on task removal and never restored,
/// so ENTER/EXIT stopped firing forever.
///
/// `addGeofence()`/`addGeofences()` are a standalone feature — they never set
/// `trackingMode = GEOFENCES`, which is only the dedicated geofence-only
/// *session* started by `startGeofences()`. Two Android restore paths
/// conflated the two:
///
/// - `TraceletSdk.destroyAll()` only kept `GeofenceManager` alive when
///   `trackingMode == GEOFENCES`, so a `start()` (continuous) session with
///   standalone geofences had every fence unregistered from Play Services on
///   the very first task removal — even with `stopOnTerminate: false`.
/// - `LocationService.startBootTracking()` only called `reRegisterAll()` for
///   `trackingMode == GEOFENCES`, so nothing ever re-registered them
///   afterwards (Play Services also clears all geofences on reboot).
///
/// Continuous tracking itself kept working throughout, which is why the
/// geofence feature could die silently and go unnoticed.
///
/// Like #316, the actual failure lives in a restore path that only runs after
/// the app's task has been removed or the device rebooted — no in-process
/// Dart test can enter it, because the app has to be alive to run the
/// assertion, and if it is alive the path was never taken. So this card does
/// not pretend to reproduce the restore itself.
///
/// What it *can* verify on the live path: that `start()` (continuous,
/// `trackingMode` left at its default) plus `addGeofence()` is exactly the
/// combination the bug affected — `trackingMode` stays `location`, never
/// flips to `geofences`, and the fence is genuinely registered — which is the
/// precondition the manual repro below builds on.
class Issue353Card extends StatefulWidget {
  const Issue353Card({super.key});

  @override
  State<Issue353Card> createState() => _Issue353CardState();
}

class _Issue353CardState extends State<Issue353Card>
    with IssueCardRun<Issue353Card> {
  static const _fenceId = 'issue-353-office';

  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _run;

  Future<void> _run() async {
    setRunning(running: true);
    final results = <String>[];
    var allPass = true;

    void check(String name, bool pass, String detail) {
      results.add('${pass ? '✅' : '❌'} $name — $detail');
      if (!pass) allPass = false;
    }

    try {
      await Tracelet.requestLocationAuthorization();
      await Tracelet.removeGeofences();

      // Continuous tracking with stopOnTerminate=false — the `keepAlive`
      // condition destroyAll() otherwise honors for every other subsystem.
      // startOnBoot puts the session in the shape the reboot/task-removal
      // restore path would later resume.
      await Tracelet.ready(
        const Config(app: AppConfig(stopOnTerminate: false, startOnBoot: true)),
      );
      await Tracelet.start();
      await Tracelet.addGeofence(
        const Geofence(
          identifier: _fenceId,
          latitude: 10.787929,
          longitude: 76.684183,
          radius: 100,
        ),
      );
      // Give the native side a moment to settle.
      await Future<void>.delayed(const Duration(seconds: 1));

      final state = await Tracelet.getState();
      check(
        'addGeofence() does not force trackingMode into GEOFENCES',
        state.trackingMode == TrackingMode.location,
        'trackingMode=${state.trackingMode} enabled=${state.enabled} — this '
            'is exactly the combination #353 affected: a continuous session '
            'that also has standalone geofences',
      );

      final fences = await Tracelet.getGeofences();
      check(
        'the geofence is registered',
        fences.any((g) => g.identifier == _fenceId),
        '${fences.length} geofence(s): ${fences.map((g) => g.identifier).join(', ')}',
      );

      await Tracelet.removeGeofences();
      await Tracelet.stop();

      final header = allPass
          ? '✅ SUCCESS: continuous tracking + a standalone geofence is a live, '
                'valid combination — the precondition for #353.'
          : '❌ FAILED — see the failing rows below.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'Scope note: the actual #353 failure only occurs on Android restore '
        "paths that require the app's task to have been removed or the "
        'device rebooted, so it cannot be reproduced from a running Dart '
        'test — same limitation as #316. This card verifies the precondition '
        '(continuous tracking + standalone geofences is real and does not '
        'silently become geofence-only mode).\n\n'
        'To confirm #353 end-to-end by hand:\n'
        '1. Call start() (continuous, default trackingMode) then '
        'addGeofence() for a fence near you, with stopOnTerminate: false.\n'
        '2. Confirm getGeofences() lists it and crossing it ENTER/EXITs.\n'
        '3. Swipe the app away from recents (Android).\n'
        '4. Cross the geofence boundary again (or simulate via a mock '
        'location provider).\n'
        '5. Before the fix: no event ever arrives again, even though '
        'continuous location updates keep syncing normally. After the fix: '
        'ENTER/EXIT still fires.\n\n'
        'The fix also added always-on lifecycle logging for this decision '
        '(bypasses logLevel, so it survives in a release-build Doctor bug '
        'report): look for "geofences: unregistering N geofence(s) on '
        'destroyAll()" and "geofences: re-registered N geofence(s) after '
        'boot/task-removal" via getLogs() or the exported bug report.',
      );
    } catch (e) {
      _set('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'geofence addGeofence addGeofences standalone continuous tracking '
          'destroyAll keepGeofencesAlive reRegisterAll startBootTracking '
          'onTaskRemoved boot reboot task removal killed state '
          'GeofenceBroadcastReceiver Play Services unregister lifecycle log '
          '353',
      title: '#353: geofences alongside continuous tracking survive restore',
      description:
          'Checks that a continuous-tracking session (not startGeofences()) '
          'with a standalone geofence added is the live combination #353 '
          'affected — Android used to unregister such geofences on task '
          'removal and never restore them, so ENTER/EXIT silently stopped '
          'firing forever. Also documents the manual repro and the new '
          'always-on lifecycle logging.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
