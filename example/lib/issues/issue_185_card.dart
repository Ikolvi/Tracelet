import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

class Issue185Card extends StatefulWidget {
  const Issue185Card({super.key});

  @override
  State<Issue185Card> createState() => _Issue185CardState();
}

class _Issue185CardState extends State<Issue185Card>
    with IssueCardRun<Issue185Card> {
  bool _isTracking = false;
  StreamSubscription? _sub;

  final TextEditingController _latController = TextEditingController(
    text: '37.33233141',
  );
  final TextEditingController _lngController = TextEditingController(
    text: '-122.03121860',
  );
  final TextEditingController _radiusController = TextEditingController(
    text: '200',
  );

  @override
  void dispose() {
    _sub?.cancel();
    _latController.dispose();
    _lngController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  void _setStatus(String text) => setStatus(text);

  // Start/stop tracking by hand: a sweep would leave the SDK tracking.
  @override
  IssueRunner? get cardRunner => null;

  Future<void> _start() async {
    _setStatus('Requesting permissions...');
    await Tracelet.requestLocationAuthorization();

    _setStatus('Starting Tracelet for Geofences (Issue 185)...');

    await Tracelet.ready(
      const Config(
        app: AppConfig(startOnBoot: true),
        geofence: GeofenceConfig(geofenceModeHighAccuracy: true),
      ),
    );

    _sub?.cancel();
    _sub = Tracelet.onGeofence((event) {
      _setStatus('📍 Geofence Event: ${event.action} ${event.identifier}');
    });

    final state = await Tracelet.startGeofences();
    setState(() {
      _isTracking = state.enabled;
    });

    if (state.enabled) {
      _setStatus('✅ Geofence Tracking Started.');
    }
  }

  Future<void> _stop() async {
    final state = await Tracelet.stop();
    setState(() {
      _isTracking = state.enabled;
    });
    _setStatus('🛑 Tracking Stopped.');
  }

  Future<void> _addGeofence() async {
    try {
      final lat = double.parse(_latController.text);
      final lng = double.parse(_lngController.text);
      final radius = double.parse(_radiusController.text);

      await Tracelet.addGeofence(
        Geofence(
          identifier: 'ISSUE_185_TEST',
          latitude: lat,
          longitude: lng,
          radius: radius,
          notifyOnDwell: true,
          loiteringDelay: 10000,
        ),
      );
      _setStatus('✅ Added Geofence at $lat, $lng');
    } catch (e) {
      _setStatus('❌ FAILED adding geofence: $e');
    }
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
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '#185: High-Accuracy Geofence Transitions',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Icon(
                  _isTracking ? Icons.gps_fixed : Icons.gps_not_fixed,
                  color: _isTracking ? Colors.green : Colors.grey,
                ),
              ],
            ),
            const SizedBox(height: 8),
            IssueStatusBox(status: status),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _latController,
                    decoration: const InputDecoration(
                      labelText: 'Lat',
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _lngController,
                    decoration: const InputDecoration(
                      labelText: 'Lng',
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _radiusController,
                    decoration: const InputDecoration(
                      labelText: 'Radius (m)',
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isTracking ? _stop : _start,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isTracking
                          ? Colors.red.shade600
                          : Colors.blue.shade600,
                      foregroundColor: Colors.white,
                    ),
                    icon: Icon(_isTracking ? Icons.stop : Icons.play_arrow),
                    label: Text(_isTracking ? 'STOP' : 'START'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _addGeofence,
                    icon: const Icon(Icons.add_location_alt),
                    label: const Text('ADD FENCE'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
