import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #352 — geofence ENTER/EXIT stop firing because proximity
/// registration rode the persistence-filtered location stream.
///
/// In standard (OS) geofence mode the SDK detects nothing itself — Play
/// Services / CoreLocation does — so *which* fences are registered with the
/// platform is the entire feature. `GeofenceManager.updateProximity()` is what
/// registers them, and it was driven by `LocationEngine.onLocationUpdate`,
/// which fires only for fixes the Rust `LocationProcessor` **accepts**. The
/// persistence filter therefore silently decided whether geofencing worked.
///
/// 3.8.0's transport-mode auto-tune (#299) made that fatal. A committed `still`
/// mode retunes the filter to `maxImpliedSpeed = 3 m/s` and
/// `trackingAccuracy = 15 m`, so the moment the device starts moving every fix
/// is rejected — registration freezes, fences coming into
/// `geofenceProximityRadius` are never registered, and no crossing is ever
/// reported again.
///
/// This is the same starvation #297 fixed for crossing *detection*; proximity
/// *scope* was left behind. Both duties now ride the raw stream.
///
/// What this card can prove without moving the device: that auto-tune really
/// does clamp the in-force filter to values that used to freeze registration,
/// and that geofences stay registered anyway. The crossing itself needs
/// physical movement — use the Map tab (long-press to drop a circular geofence
/// with a custom radius, then open the collapsible **SDK Logs** panel and
/// filter to `geofence`).
class Issue352Card extends StatefulWidget {
  const Issue352Card({super.key});

  @override
  State<Issue352Card> createState() => _Issue352CardState();
}

class _Issue352CardState extends State<Issue352Card>
    with IssueCardRun<Issue352Card> {
  static const _fenceId = 'issue-352-fence';

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

      // The exact configuration from the field report: continuous tracking,
      // standard (non-high-accuracy) geofences, auto-tune ON.
      await Tracelet.ready(
        const Config(
          geo: GeoConfig(distanceFilter: 0),
          geofence: GeofenceConfig(geofenceModeHighAccuracy: false),
          classifier: ClassifierConfig(
            enableFusedClassifier: true,
            autoTuneFromTransportMode: true,
          ),
          logger: LoggerConfig(logLevel: LogLevel.info),
        ),
      );
      await Tracelet.start();

      await Tracelet.addGeofence(
        const Geofence(
          identifier: _fenceId,
          latitude: 10.787929,
          longitude: 76.684183,
          radius: 150,
        ),
      );

      // Give the classifier a chance to commit a mode and retune the filter.
      await Future<void>.delayed(const Duration(seconds: 10));

      final state = await Tracelet.getState();
      check(
        'continuous tracking with standard geofences is active',
        state.enabled && state.trackingMode == TrackingMode.location,
        'enabled=${state.enabled} trackingMode=${state.trackingMode}',
      );

      // The in-force thresholds, read back from the native processor rather
      // than from config — the whole point of getCurrentLocationTuning().
      final tuning = await Tracelet.getCurrentLocationTuning();
      if (tuning == null) {
        results.add(
          'ℹ️ getCurrentLocationTuning() returned null — no processor built '
          'yet (or Web). Cannot show the auto-tune clamp on this run.',
        );
      } else {
        final tightened =
            tuning.maxImpliedSpeed <= 5 ||
            tuning.trackingAccuracyThreshold <= 20;
        results.add(
          '${tightened ? '⚠️' : 'ℹ️'} in-force filter: '
          'distanceFilter=${tuning.distanceFilter}m '
          'trackingAccuracy=${tuning.trackingAccuracyThreshold}m '
          'odometerAccuracy=${tuning.odometerAccuracyThreshold}m '
          'maxImpliedSpeed=${tuning.maxImpliedSpeed}m/s'
          '${tightened ? ' — auto-tune has clamped the filter. Before the fix '
                    'this is the state in which geofence registration froze: every '
                    'fix above the implied-speed gate was rejected and '
                    'updateProximity() stopped being called.' : ''}',
        );
      }

      // The invariant the fix guarantees: whatever the filter is doing, the
      // fence stays registered.
      final fences = await Tracelet.getGeofences();
      check(
        'the geofence survives a clamped filter',
        fences.any((g) => g.identifier == _fenceId),
        '${fences.length} geofence(s): '
            '${fences.map((g) => g.identifier).join(', ')}',
      );

      // Crossings are now recorded on the always-on lifecycle channel, so they
      // are present in an exported report regardless of logLevel.
      final logs = await Tracelet.getLogs(2000);
      final geofenceLines = logs
          .where((l) => l.message.contains('[geofence]'))
          .toList();
      results.add(
        geofenceLines.isEmpty
            ? 'ℹ️ no [geofence] log lines yet — expected until you actually '
                  'cross a boundary. After the fix these are written on the '
                  'always-on lifecycle channel, so they appear even at '
                  'logLevel off/error.'
            : 'ℹ️ ${geofenceLines.length} [geofence] log line(s), most recent: '
                  '${geofenceLines.last.message}',
      );

      await Tracelet.removeGeofences();
      await Tracelet.stop();

      final header = allPass
          ? '✅ SUCCESS: geofence registration is independent of the location '
                'filter.'
          : '❌ FAILED — see the failing rows below.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'Scope note: a real ENTER/EXIT needs physical movement, so this card '
        'verifies the precondition (auto-tune clamps the filter, the fence '
        'stays registered anyway) rather than faking a crossing.\n\n'
        'To confirm #352 end-to-end by hand:\n'
        '1. Open the Map tab and long-press to drop a circular geofence — '
        'pick a radius of 100-200m so GPS noise cannot cross it by itself.\n'
        '2. Leave the device still ~10s so the classifier commits "still" and '
        'auto-tune clamps maxImpliedSpeed to 3 m/s.\n'
        '3. Walk or drive across the boundary.\n'
        '4. Open the collapsible SDK Logs panel on the map and keep the '
        '"geofence" filter on.\n'
        '5. Before the fix: no ENTER/EXIT ever arrives, while ordinary '
        'location updates keep flowing. After the fix: the crossing is '
        'logged and the event fires.',
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
          'geofence enter exit updateProximity proximity scope raw stream '
          'onRawGeofenceLocation onLocationUpdate autoTuneFromTransportMode '
          'auto-tune maxImpliedSpeed trackingAccuracyThreshold still '
          'LocationProcessor filtered starvation Play Services registration '
          'lifecycle log release logLevel 352 297 299',
      title: '#352: geofence ENTER/EXIT starved by the location filter',
      description:
          'Geofence proximity registration rode the persistence-filtered '
          'location stream, so 3.8.0 auto-tune clamping the filter to '
          'maxImpliedSpeed=3m/s froze Play Services registration and '
          'ENTER/EXIT stopped firing for good. Checks that the filter is '
          'clamped and the fence survives it anyway.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
