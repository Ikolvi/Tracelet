import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// PR #270 — Android boot/broadcast init race: geofence transitions and
/// confirmed crash/fall deliveries can be silently dropped right after a cold
/// boot (regression from #260, completing the #264 fix on the receiver paths).
///
/// #260 moved the heavy `TraceletSdk.initialize()` setup — opening the Rust DB
/// and wiring the `lateinit` managers (`geofenceManager`, engines) — onto a
/// background `tracelet-init` thread, so `initialize()` now returns before those
/// managers exist. #264 guarded the synchronous entry points that go through
/// `ready()` / `bootstrapForBackground()` (so `LocationService.startBootTracking`
/// no longer crashes). But two **native broadcast** entry points still ran
/// unguarded:
///
///  - `GeofenceBroadcastReceiver.onReceive`: on a cold boot it called
///    `initialize()` and then immediately read `geofenceManager`. That read
///    raced the init thread, threw `UninitializedPropertyAccessException`, was
///    swallowed, and the geofence manager came back `null` — so the transition
///    (a cold-boot ENTER/EXIT, i.e. a trip start) was **silently dropped**.
///  - `CrashConfirmReceiver.onReceive`: same shape — `initialize()` then
///    `deliverConfirmedImpact()` on not-yet-wired state, so a process-death
///    crash/fall confirmation could be lost.
///
/// The fix routes both receivers through `TraceletSdk.awaitInit()`, which blocks
/// until the background init finishes (or reports failure/timeout) before the
/// managers are touched — so the transition / impact is delivered instead of
/// dropped, and never crashes.
///
/// This is a MANUAL, reboot-based reproduction: the receiver fires in the native
/// boot process before the Flutter/Dart engine runs, so no in-app try/catch can
/// observe it. This card persists the exact triggering state, then asks you to
/// reboot and cross the geofence in the first seconds after boot.
///
/// How to run:
///   1. Tap "Arm reboot repro" (grant "Allow all the time" location).
///   2. Confirm the status shows enabled=true, mode=geofences with a geofence
///      registered around your current location.
///   3. Fully REBOOT the device (a cold boot, not just a relaunch).
///   4. Immediately after boot, cross the geofence boundary (enter/exit).
///      - Pre-fix: the first post-boot transition is dropped (nothing logged by
///        GeofenceManager, no onGeofence event) because the receiver read a
///        null manager while init was still running.
///      - Post-fix: the transition is delivered — awaitInit() made the receiver
///        wait for geofenceManager before handling it.
///   5. Re-open the app and tap "Check delivered transitions" to read how many
///      geofence events the SDK recorded since boot.
class Issue270Card extends StatefulWidget {
  const Issue270Card({super.key});

  @override
  State<Issue270Card> createState() => _Issue270CardState();
}

class _Issue270CardState extends State<Issue270Card>
    with IssueCardRun<Issue270Card> {
  StreamSubscription<GeofenceEvent>? _geofenceSub;
  int _liveTransitions = 0;

  void _set(String s) => setStatus(s);

  // Two-phase: arm, reboot the device, then check. Not sweepable.
  @override
  IssueRunner? get cardRunner => null;

  @override
  void dispose() {
    _geofenceSub?.cancel();
    super.dispose();
  }

  /// Persist the exact state that makes a cold boot exercise the native
  /// `GeofenceBroadcastReceiver.onReceive` → `awaitInit()` → `geofenceManager`
  /// path.
  Future<void> _arm() async {
    setRunning(running: true);
    try {
      if (!Platform.isAndroid) {
        _set(
          'ℹ️ PR #270 targets the native Android broadcast paths '
          '(GeofenceBroadcastReceiver / CrashConfirmReceiver) that fire in the '
          'boot process before Dart runs. Not applicable on this platform. '
          'iOS is unaffected: its initialize() is synchronous and geofences run '
          'in-process via CLLocationManager, not a separate receiver.',
        );
        return;
      }

      _set('Requesting location permission (needs "Allow all the time")...');
      final auth = await Tracelet.requestLocationAuthorization();
      if (auth != AuthorizationStatus.always) {
        _set(
          '❌ Cannot arm: background location is required for the cold-boot '
          'geofence transition. Got "$auth" but need '
          '"AuthorizationStatus.always" (grant "Allow all the time").',
        );
        return;
      }

      // ready() must be called before any location API (getCurrentPosition
      // throws NOT_READY otherwise), so configure the SDK first, then anchor
      // the geofence on the current position.
      _set('Configuring startOnBoot + stopOnTerminate:false + geofences...');
      await Tracelet.ready(
        Config.balanced().copyWith(
          app: const AppConfig(stopOnTerminate: false, startOnBoot: true),
        ),
      );

      _set('Reading current position to anchor the geofence...');
      final pos = await Tracelet.getCurrentPosition(maximumAge: 0);
      final lat = pos.coords.latitude;
      final lng = pos.coords.longitude;

      // Register a geofence around the current location with a small radius so
      // walking a short distance crosses the boundary and fires a transition
      // into GeofenceBroadcastReceiver on the boot process.
      await Tracelet.removeGeofences();
      await Tracelet.addGeofence(
        Geofence(
          identifier: 'issue-270-repro',
          latitude: lat,
          longitude: lng,
          radius: 100,
        ),
      );

      final state = await Tracelet.startGeofences();
      final isGeofenceMode = state.trackingMode == TrackingMode.geofences;
      if (!state.enabled || !isGeofenceMode) {
        _set(
          '❌ Could not arm: expected enabled=true and '
          'mode=TrackingMode.geofences, but got enabled=${state.enabled}, '
          'mode=${state.trackingMode.name}.',
        );
        return;
      }

      final geofences = await Tracelet.getGeofences();
      _set(
        '✅ Armed. Persisted native state: enabled=${state.enabled}, '
        'mode=${state.trackingMode.name}, ${geofences.length} geofence(s) '
        'around ($lat, $lng) r=100m, startOnBoot=true, stopOnTerminate=false.\n\n'
        'NOW: fully REBOOT the device (cold boot). Immediately after boot, '
        'cross the 100m geofence boundary (walk out and back in).\n'
        '• Pre-fix: the first post-boot ENTER/EXIT is silently dropped '
        '(GeofenceBroadcastReceiver read a null manager while init was still '
        'running) — nothing recorded.\n'
        '• Post-fix: the transition is delivered — the receiver awaited '
        'geofenceManager before handling it.\n\n'
        'After crossing, re-open the app and tap "Check delivered transitions".',
      );
    } catch (e) {
      _set('❌ FAILED to arm the repro: $e');
    } finally {
      setRunning(running: false);
    }
  }

  /// Secondary signal: subscribe to live geofence events and report how many
  /// arrive. After a reboot + boundary crossing, a delivered transition proves
  /// the receiver waited for init (fixed); zero (with a confirmed crossing)
  /// points at the dropped-transition regression.
  Future<void> _checkTransitions() async {
    setRunning(running: true);
    try {
      if (!Platform.isAndroid) {
        _set('ℹ️ PR #270 is Android-only.');
        return;
      }
      await _geofenceSub?.cancel();
      _liveTransitions = 0;
      _geofenceSub = Tracelet.onGeofence((event) {
        _liveTransitions++;
        _set(
          '✅ Geofence transition delivered: ${event.action} '
          '${event.identifier} (total this session: $_liveTransitions).\n\n'
          'If this fired right after a cold boot + boundary crossing, the '
          'GeofenceBroadcastReceiver correctly awaited geofenceManager before '
          'handling the transition (PR #270 fix). Pre-fix it would have been '
          'dropped.',
        );
      });
      final geofences = await Tracelet.getGeofences();
      final state = await Tracelet.getState();
      _set(
        'Listening for geofence transitions...\n'
        '• enabled=${state.enabled}\n'
        '• mode=${state.trackingMode.name}\n'
        '• ${geofences.length} geofence(s) registered\n'
        '• didDeviceReboot=${state.didDeviceReboot}\n\n'
        'Cross the geofence boundary now. A delivered ENTER/EXIT (above) means '
        'the fix works. If you cross and nothing arrives, the transition was '
        'dropped (the pre-fix regression).',
      );
    } catch (e) {
      _set('❌ FAILED to read state: $e');
    } finally {
      setRunning(running: false);
    }
  }

  static const String _title =
      '#270: boot/broadcast init race drops geofence transitions & crash '
      'confirmations (Android)';
  static const String _description =
      'Manual reboot repro. Regression from #260 (async initialize()), '
      'completing #264 on the native broadcast receivers. On a cold boot, '
      'GeofenceBroadcastReceiver / CrashConfirmReceiver called initialize() and '
      'immediately dereferenced not-yet-wired lateinit managers, so the '
      'exception was swallowed and the geofence transition (a trip start) or '
      'confirmed crash/fall was silently dropped. Fix routes both receivers '
      'through awaitInit(). Arm the state, reboot, then cross the geofence right '
      'after boot. Android-only (iOS initialize() is synchronous).';
  static const String _keywords =
      'android boot reboot geofence transition dropped silently '
      'geofencebroadcastreceiver crashconfirmreceiver awaitinit initialize '
      'race tracelet-init lateinit geofencemanager uninitialized deliver '
      'confirmed impact crash fall startonboot stoponterminate #260 #264 #270';

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
            IssueStatusBox(status: status),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: running ? null : _arm,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Arm reboot repro'),
                ),
                OutlinedButton.icon(
                  onPressed: running ? null : _checkTransitions,
                  icon: const Icon(Icons.sensors),
                  label: const Text('Check delivered transitions'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
