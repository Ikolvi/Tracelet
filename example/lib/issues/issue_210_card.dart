import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;

/// Issue #210 — In geofence mode the iOS blue "location in use" status-bar
/// indicator was ALWAYS visible (foreground and background), even with
/// `IosConfig(showsBackgroundLocationIndicator: false)`.
///
/// Root cause: the iOS plugin was reading the Android-only
/// `geofenceModeHighAccuracy` flag, which pushed iOS into the high-accuracy
/// geofence branch (continuous GPS + `CLBackgroundActivitySession`, which
/// *forces* the indicator). The fix makes iOS ignore that flag and use native
/// region monitoring (no continuous GPS → no indicator).
///
/// This is a VISUAL/manual test — the blue indicator can't be read
/// programmatically. The card registers a geofence around your current location
/// and streams ENTER/EXIT events into the log while you watch the status bar.
///
/// The "High-accuracy mode" toggle flips the cross-platform
/// [GeofenceConfig.geofenceModeHighAccuracy]:
///  * OFF (default) → standard OS region monitoring: ~100m radius, no iOS blue
///    indicator (the #210 fix).
///  * ON → continuous-GPS proximity: tight 5m radius and reliable EXIT, but the
///    iOS blue indicator is expected (the documented tradeoff).
class Issue210Card extends StatefulWidget {
  const Issue210Card({super.key});

  @override
  State<Issue210Card> createState() => _Issue210CardState();
}

class _Issue210CardState extends State<Issue210Card> {
  String _status = 'Idle';
  bool _running = false;
  bool _tracking = false;
  bool _highAccuracy = false;
  final List<String> _log = [];
  StreamSubscription<GeofenceEvent>? _geofenceSub;

  void _setStatus(String text) {
    if (mounted) setState(() => _status = text);
  }

  void _appendLog(String line) {
    final stamp = TimeOfDay.now().format(context);
    if (mounted) {
      setState(() {
        _log.insert(0, '[$stamp] $line');
        if (_log.length > 40) _log.removeLast();
      });
    }
  }

  Future<void> _start() async {
    setState(() {
      _running = true;
      _log.clear();
    });
    try {
      _setStatus('Requesting permissions...');
      final auth = await Tracelet.requestLocationAuthorization();
      _appendLog('Authorization: ${auth.name}');
      if (auth != AuthorizationStatus.always &&
          auth != AuthorizationStatus.whenInUse) {
        _setStatus(
          '❌ Permission denied — "Always" is recommended for geofences.',
        );
        return;
      }

      _setStatus(
        'Configuring geofence mode (${_highAccuracy ? "HIGH-ACCURACY" : "standard"})...',
      );
      await Tracelet.ready(
        Config(
          ios: const IosConfig(
            // The repro config: prevent suspension + REQUEST that the OS hide
            // the background-location indicator. In STANDARD mode iOS uses region
            // monitoring so the indicator stays hidden; in HIGH-ACCURACY mode iOS
            // runs continuous GPS and the indicator is expected (Issue #210).
            preventSuspend: true,
            // ignore: avoid_redundant_argument_values
            showsBackgroundLocationIndicator: false,
          ),
          // Cross-platform high-accuracy geofencing toggle. true → continuous
          // GPS, reliable tight radii / EXIT, but the iOS blue indicator shows.
          geofence: GeofenceConfig(geofenceModeHighAccuracy: _highAccuracy),
          logger: const LoggerConfig(debug: true, logLevel: LogLevel.verbose),
        ),
      );

      _setStatus('Getting current position to anchor the geofence...');
      final here = await Tracelet.getCurrentPosition();
      final lat = here.coords.latitude;
      final lng = here.coords.longitude;
      _appendLog('Current position: $lat, $lng');

      // Drop a geofence centred on the current location. In standard mode iOS
      // needs ~100m for reliable EXIT; in high-accuracy mode a tight 5m radius
      // works because transitions are computed from continuous GPS in-app.
      final radius = _highAccuracy ? 5.0 : 100.0;
      await Tracelet.addGeofence(
        Geofence(
          identifier: 'issue-210-here',
          latitude: lat,
          longitude: lng,
          radius: radius,
        ),
      );
      _appendLog('Geofence "issue-210-here" added (r=${radius.toInt()}m).');

      _geofenceSub?.cancel();
      _geofenceSub = Tracelet.onGeofence((event) {
        _appendLog(
          'GEOFENCE ${event.action.name.toUpperCase()} → ${event.identifier}',
        );
      });

      await Tracelet.startGeofences();
      setState(() => _tracking = true);

      final String platformNote;
      if (Platform.isIOS) {
        platformNote = _highAccuracy
            ? 'iOS HIGH-ACCURACY: the blue indicator IS expected (continuous '
                  'GPS). Tight 5m enter/exit should be reliable.'
            : 'iOS STANDARD: the blue indicator should NOT appear — foreground '
                  'OR background. Region monitoring, ~100m radius.';
      } else {
        platformNote =
            'Android: a foreground-service notification is expected (that is '
            'NOT the blue pill); geofence transitions should fire in either '
            'mode.';
      }
      _setStatus(
        '✅ Geofencing started (r=${radius.toInt()}m, '
        '${_highAccuracy ? "high-accuracy" : "standard"}). $platformNote\n\n'
        'Walk past the boundary to trigger an EXIT, then back for an ENTER '
        '(logged below). Geofences only fire on boundary crossings — not '
        'continuously. Watch the status bar the whole time.',
      );
    } catch (e) {
      _setStatus('❌ FAILED: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _stop() async {
    setState(() => _running = true);
    try {
      await _geofenceSub?.cancel();
      _geofenceSub = null;
      await Tracelet.removeGeofence('issue-210-here');
      await Tracelet.stop();
      _appendLog('Stopped. Geofence removed.');
      _setStatus('Stopped. The blue indicator (if any) should now be gone.');
    } catch (e) {
      _setStatus('❌ Error stopping: $e');
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _tracking = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _geofenceSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '#210: iOS blue indicator always on in geofence mode',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Standard mode (toggle OFF): iOS monitors regions WITHOUT the blue '
              'status-bar indicator (the #210 fix). High-accuracy mode (toggle '
              'ON): continuous GPS for reliable tight/EXIT geofences — the iOS '
              'indicator is expected. Visual test — watch the status bar; events '
              'stream into the log.',
            ),
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
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('High-accuracy mode (continuous GPS)'),
              subtitle: Text(
                _highAccuracy
                    ? 'ON: 5m radius, reliable EXIT — iOS blue indicator WILL show.'
                    : 'OFF: 100m region monitoring — no iOS indicator.',
              ),
              value: _highAccuracy,
              onChanged: (_running || _tracking)
                  ? null
                  : (v) => setState(() => _highAccuracy = v),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (_running || _tracking) ? null : _start,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start geofencing'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_running || !_tracking) ? null : _stop,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                  ),
                ),
              ],
            ),
            if (_log.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Event log',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: Text(
                    _log.join('\n'),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.greenAccent,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
