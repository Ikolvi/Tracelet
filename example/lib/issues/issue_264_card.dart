import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #264 — Android `startOnBoot` geofence restart crashes with an
/// uninitialized `geofenceManager`.
///
/// With geofence tracking persisted as enabled, `startOnBoot: true`, and
/// `stopOnTerminate: false`, the app process can crash while Android starts
/// `LocationService` after a reboot / process restart:
///
/// ```
/// java.lang.RuntimeException: Unable to start service
///   com.ikolvi.tracelet.sdk.service.LocationService
/// Caused by: kotlin.UninitializedPropertyAccessException:
///   lateinit property geofenceManager has not been initialized
///     at com.ikolvi.tracelet.sdk.TraceletSdk.getGeofenceManager(TraceletSdk.kt:101)
///     at ...service.LocationService.startBootTracking(LocationService.kt:1152)
///     at ...service.LocationService.onStartCommand(LocationService.kt:630)
/// ```
///
/// Root cause (native): `TraceletSdk.initialize()` runs `initializeInternal()`
/// on a separate `tracelet-init` thread and only then counts down
/// `initCompleteLatch`. `ready()` waits on that latch before touching the DB or
/// managers — but `bootstrapForBackground()` does NOT. On a cold boot,
/// `LocationService.startBootTracking()` calls `bootstrapForBackground()` and
/// then immediately reads `sdk.geofenceManager`, a `lateinit` that is assigned
/// inside `initializeInternal()`. If the init thread has not reached that
/// assignment yet, the getter throws and the service (and process) crashes.
///
/// This is a MANUAL, reboot-based reproduction: the crash happens in the native
/// boot path BEFORE the Flutter/Dart engine runs, so no in-app try/catch can
/// observe or prevent it. This card just persists the exact triggering state
/// (`startOnBoot: true`, `stopOnTerminate: false`, geofences mode, one geofence
/// registered) and then asks you to reboot the device and watch Logcat.
///
/// How to run:
///   1. Tap "Arm reboot repro" below (grant "Allow all the time" location).
///   2. Confirm the status shows enabled=true, mode=geofences.
///   3. Fully reboot the device / emulator (a cold boot, not just relaunch).
///   4. Watch Logcat for `LocationService` / `UninitializedPropertyAccessException`.
///      - CRASH on boot  → bug reproduced (pre-fix behaviour).
///      - No crash, service stays alive → fixed.
///   5. Re-open the app and tap "Check post-reboot state" to read the persisted
///      native state (didDeviceReboot / enabled / mode) as a secondary signal.
class Issue264Card extends StatefulWidget {
  const Issue264Card({super.key});

  @override
  State<Issue264Card> createState() => _Issue264CardState();
}

class _Issue264CardState extends State<Issue264Card> {
  String _status = 'Idle';
  bool _running = false;

  void _set(String s) {
    if (mounted) setState(() => _status = s);
  }

  /// Persist the exact state described in #264 so a reboot exercises the native
  /// `startBootTracking()` → `geofenceManager` path.
  Future<void> _arm() async {
    setState(() => _running = true);
    try {
      if (!Platform.isAndroid) {
        _set(
          'ℹ️ #264 is Android-only. It targets the native Android boot restart '
          'path (LocationService.startBootTracking → geofenceManager). Not '
          'applicable on this platform.',
        );
        return;
      }

      _set('Requesting location permission (needs "Allow all the time")...');
      final auth = await Tracelet.requestLocationAuthorization();
      if (auth != AuthorizationStatus.always) {
        _set(
          '❌ Cannot arm the repro: background location is required for the '
          'startOnBoot geofence restart. Got "$auth" but need '
          '"AuthorizationStatus.always" (grant "Allow all the time"). '
          'Boot restart only fires when ACCESS_BACKGROUND_LOCATION is granted.',
        );
        return;
      }

      _set('Configuring startOnBoot + stopOnTerminate:false + geofences...');
      // The exact triggering config from the report: survive termination and
      // restart tracking on boot.
      await Tracelet.ready(
        Config.balanced().copyWith(
          app: const AppConfig(stopOnTerminate: false, startOnBoot: true),
        ),
      );

      // Register a geofence so the persisted tracking mode is GEOFENCES and the
      // boot path enters the geofence-specific branch that touches
      // geofenceManager. A location near the device is fine — presence is what
      // matters, not entry/exit.
      await Tracelet.removeGeofences();
      await Tracelet.addGeofence(
        const Geofence(
          identifier: 'issue-264-repro',
          latitude: 37.4219983,
          longitude: -122.084,
          radius: 200,
        ),
      );

      // Start geofences-only mode and persist it as the active tracking mode.
      final state = await Tracelet.startGeofences();

      final isGeofenceMode = state.trackingMode == TrackingMode.geofences;
      if (!state.enabled || !isGeofenceMode) {
        _set(
          '❌ Could not arm: expected enabled=true and '
          'mode=TrackingMode.geofences, but got enabled=${state.enabled}, '
          'mode=${state.trackingMode.name}. Boot restart keys off this '
          'persisted state.',
        );
        return;
      }

      final geofences = await Tracelet.getGeofences();
      _set(
        '✅ Armed. Persisted native state: enabled=${state.enabled}, '
        'mode=${state.trackingMode.name} (index '
        '${TrackingMode.values.indexOf(state.trackingMode)}), '
        '${geofences.length} geofence(s) registered, startOnBoot=true, '
        'stopOnTerminate=false.\n\n'
        'NOW: fully REBOOT the device/emulator (cold boot). Watch Logcat for '
        'LocationService starting.\n'
        '• CRASH with "UninitializedPropertyAccessException: lateinit property '
        'geofenceManager has not been initialized" during startBootTracking() '
        '→ #264 reproduced.\n'
        '• Service starts and stays alive, no crash → fixed.\n\n'
        'After rebooting and re-opening the app, tap "Check post-reboot state".',
      );
    } catch (e) {
      _set('❌ FAILED to arm the repro: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  /// Secondary signal after a reboot: read the persisted native state. The
  /// primary evidence is Logcat (the crash happens before Dart runs), but if
  /// the process survived boot the SDK marks `didDeviceReboot` and keeps the
  /// geofence mode enabled.
  Future<void> _checkPostReboot() async {
    setState(() => _running = true);
    try {
      if (!Platform.isAndroid) {
        _set('ℹ️ #264 is Android-only.');
        return;
      }
      final state = await Tracelet.getState();
      _set(
        'Post-reboot native state:\n'
        '• enabled=${state.enabled}\n'
        '• mode=${state.trackingMode.name} '
        '(index ${TrackingMode.values.indexOf(state.trackingMode)})\n'
        '• didDeviceReboot=${state.didDeviceReboot}\n'
        '• didLaunchInBackground=${state.didLaunchInBackground}\n\n'
        'If you rebooted and the app/service did NOT crash (check Logcat for '
        'the absence of UninitializedPropertyAccessException), the boot restart '
        'survived. The definitive signal for #264 is always Logcat during '
        'LocationService startup on boot.',
      );
    } catch (e) {
      _set('❌ FAILED to read state: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  static const String _title =
      '#264: startOnBoot geofence restart crashes with uninitialized '
      'geofenceManager (Android)';
  static const String _description =
      'Manual reboot repro. Persists the exact triggering state '
      '(startOnBoot: true, stopOnTerminate: false, geofences mode with a '
      'registered geofence, background location granted), then asks you to '
      'reboot the device. On a cold boot, LocationService.startBootTracking() '
      'calls bootstrapForBackground() (which does NOT wait for the async '
      'tracelet-init thread) and then reads the lateinit geofenceManager, '
      'crashing with UninitializedPropertyAccessException. Watch Logcat on '
      'boot. Android-only.';
  static const String _keywords =
      'android startonboot boot reboot geofence geofencemanager '
      'lateinit uninitialized property locationservice startboottracking '
      'bootstrapforbackground initcompletelatch crash race stoponterminate';

  @override
  Widget build(BuildContext context) {
    // Self-filter against the issue search query exactly like IssueCardShell.
    final query = IssueSearchScope.of(context);
    if (query.isNotEmpty) {
      final haystack = '$_title $_description $_keywords'.toLowerCase();
      if (!haystack.contains(query)) return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              _title,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(_description),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Text(
                _status,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _running ? null : _arm,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Arm reboot repro'),
                ),
                OutlinedButton.icon(
                  onPressed: _running ? null : _checkPostReboot,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Check post-reboot state'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
