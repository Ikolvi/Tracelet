import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #231 — geofence transition events were emitted with hardcoded zero
/// coordinate metrics (accuracy/speed/heading/altitude) and no `battery` key,
/// so backends received geofence crossings with no usable telemetry.
///
/// The fix enriches the geofence payload from the last GPS fix and attaches the
/// current battery snapshot. This test starts high-accuracy geofencing anchored
/// at the current location, triggers an ENTER, and asserts the event carries a
/// real (non-zero) accuracy and a valid battery level.
class Issue231Card extends StatefulWidget {
  const Issue231Card({super.key});

  @override
  State<Issue231Card> createState() => _Issue231CardState();
}

class _Issue231CardState extends State<Issue231Card>
    with IssueCardRun<Issue231Card> {
  static const _geofenceId = 'issue-231-here';

  StreamSubscription<GeofenceEvent>? _sub;

  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _test;

  Future<void> _test() async {
    setRunning(running: true);
    final completer = Completer<String>();
    try {
      _set('Requesting permissions...');
      final auth = await Tracelet.requestLocationAuthorization();
      if (auth != AuthorizationStatus.always &&
          auth != AuthorizationStatus.whenInUse) {
        _set('❌ FAILED: location permission denied ($auth).');
        return;
      }

      _set('Configuring high-accuracy geofencing...');
      await Tracelet.ready(
        const Config(
          geo: GeoConfig(
            // ignore: avoid_redundant_argument_values
            desiredAccuracy: DesiredAccuracy.high,
            distanceFilter: 0,
          ),
          geofence: GeofenceConfig(
            geofenceModeHighAccuracy: true,
            // ignore: avoid_redundant_argument_values
            geofenceInitialTriggerEntry: true,
          ),
          logger: LoggerConfig(debug: true, logLevel: LogLevel.verbose),
        ),
      );

      _set('Acquiring a GPS fix to anchor the geofence...');
      final here = await Tracelet.getCurrentPosition(
        desiredAccuracy: DesiredAccuracy.high,
      );

      _sub?.cancel();
      _sub = Tracelet.onGeofence((event) {
        if (event.identifier != _geofenceId) return;
        final coords = event.location.coords;
        final battery = event.location.battery;
        if (event.action == GeofenceAction.enter) {
          if (coords.accuracy > 0.0 && battery.level >= 0.0) {
            if (!completer.isCompleted) {
              completer.complete(
                '✅ SUCCESS: enriched geofence event! '
                'accuracy=${coords.accuracy.toStringAsFixed(1)}m, '
                'speed=${coords.speed.toStringAsFixed(1)}m/s, '
                'heading=${coords.heading.toStringAsFixed(0)}°, '
                'battery=${(battery.level * 100).toStringAsFixed(0)}%.',
              );
            }
          } else {
            if (!completer.isCompleted) {
              completer.complete(
                '❌ FAILED: mock values — accuracy=${coords.accuracy}, '
                'speed=${coords.speed}, battery=${battery.level}.',
              );
            }
          }
        }
      });

      _set(
        'Registering geofence at ${here.coords.latitude.toStringAsFixed(5)}, '
        '${here.coords.longitude.toStringAsFixed(5)}...',
      );
      await Tracelet.addGeofence(
        Geofence(
          identifier: _geofenceId,
          latitude: here.coords.latitude,
          longitude: here.coords.longitude,
          radius: 200,
        ),
      );

      await Tracelet.startGeofences();
      _set('Waiting for ENTER event...');

      final result = await completer.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () =>
            '❌ FAILED: timed out waiting for the geofence ENTER event.',
      );
      _set(result);
    } catch (e) {
      _set('❌ FAILED: $e');
    } finally {
      await _sub?.cancel();
      _sub = null;
      try {
        await Tracelet.removeGeofence(_geofenceId);
        await Tracelet.stop();
      } catch (_) {}
      setRunning(running: false);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      title: '#231: geofence events missing coords & battery',
      description:
          'Starts high-accuracy geofencing anchored at your current location, '
          'triggers an ENTER, and asserts the event carries a real accuracy and '
          'a valid battery level (previously hardcoded 0.0 / -1.0). Needs a live '
          'GPS fix — run outdoors or with a mock location set.',
      status: status,
      running: running,
      onRun: _test,
    );
  }
}
