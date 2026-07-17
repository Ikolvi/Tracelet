import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #247 — startGeofences() posts the foreground notification even though
/// `GeofenceConfig(geofenceModeHighAccuracy: false)` is set.
///
/// Root cause: on aggressive OEMs (Samsung/Xiaomi/Huawei/OnePlus/Oppo/Vivo)
/// the native ConfigManager silently forced geofenceModeHighAccuracy back to
/// true, so startGeofences() took the high-accuracy branch — starting the
/// location engine AND LocationService as a foreground service with its
/// persistent notification, which low-accuracy geofences-only mode exists to
/// avoid (and which Google Play prohibits solely for geofencing from
/// 2026-10-28). The explicit config is now authoritative (same pattern as the
/// #243 fix); the SDK logs a reliability warning instead.
///
/// This test runs the reporter's exact repro. The deterministic part asserts
/// geofences-only mode started with the intended config; the notification
/// check is visual — confirm NO Tracelet notification appears, especially on
/// an aggressive-OEM device.
class Issue247Card extends StatefulWidget {
  const Issue247Card({super.key});

  @override
  State<Issue247Card> createState() => _Issue247CardState();
}

class _Issue247CardState extends State<Issue247Card> {
  String _status = 'Idle';
  bool _running = false;

  void _set(String s) {
    if (mounted) setState(() => _status = s);
  }

  Future<void> _test() async {
    if (_running) return;
    setState(() => _running = true);

    try {
      if (!Platform.isAndroid) {
        _set('N/A: this is an Android OEM config-override issue.');
        return;
      }

      _set('Stopping any existing tracking...');
      await Tracelet.stop();

      _set("Applying the reporter's low-accuracy geofences config...");
      await Tracelet.ready(
        Config.balanced().copyWith(
          // false is the default, but the reporter set it explicitly and the
          // old code ignored it — keep it explicit here.
          // ignore: avoid_redundant_argument_values
          geofence: const GeofenceConfig(geofenceModeHighAccuracy: false),
          app: const AppConfig(stopOnTerminate: false, startOnBoot: true),
        ),
      );

      _set('Adding a test geofence...');
      await Tracelet.addGeofence(
        const Geofence(
          identifier: 'issue-247-geofence',
          latitude: 37.7749,
          longitude: -122.4194,
          radius: 200,
        ),
      );

      final state = await Tracelet.startGeofences();

      final config = Tracelet.activeConfig;
      final lowAccuracyKept = !config.geofence.geofenceModeHighAccuracy;

      if (!state.enabled) {
        _set('❌ FAILED: startGeofences() did not enable tracking.');
      } else if (!lowAccuracyKept) {
        _set(
          '❌ FAILED: active config lost the low-accuracy opt-out '
          '(geofenceModeHighAccuracy='
          '${config.geofence.geofenceModeHighAccuracy}).',
        );
      } else {
        _set(
          '✅ Geofences-only mode started with geofenceModeHighAccuracy: '
          'false honored.\n'
          'Now check the notification shade: no "Tracelet — Tracking '
          'location in background" notification may appear — especially on '
          'Samsung/Xiaomi/Huawei/OnePlus/Oppo/Vivo, where the old code '
          'silently forced high-accuracy mode (and its foreground service) '
          'back on. Native logs must show '
          'startGeofences() (highAccuracy=false).\n'
          'Press Stop on the dashboard to stop.',
        );
      }
    } catch (e) {
      _set('❌ ERROR: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      title: 'Issue #247: geofences-only mode forces FGS on aggressive OEMs',
      description:
          'Runs startGeofences() with GeofenceConfig(geofenceModeHighAccuracy: '
          "false) — the reporter's exact config. On aggressive OEMs the old "
          'native config layer silently forced high-accuracy mode, starting '
          'the location engine and the foreground-service notification that '
          'low-accuracy geofences-only mode exists to avoid. Explicit config '
          'is now honored (native GeofencingClient only, no service).',
      status: _status,
      running: _running,
      onRun: _test,
    );
  }
}
