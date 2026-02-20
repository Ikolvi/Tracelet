import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tracelet Test',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const LocationTestPage(),
    );
  }
}

class LocationTestPage extends StatefulWidget {
  const LocationTestPage({super.key});

  @override
  State<LocationTestPage> createState() => _LocationTestPageState();
}

class _LocationTestPageState extends State<LocationTestPage> {
  static const _methodChannel = MethodChannel('com.tracelet/methods');
  static const _eventChannel = EventChannel('com.tracelet/events/location');

  String _status = 'Idle';
  String _permissionStatus = 'Unknown';
  Map<String, dynamic>? _currentLocation;
  final List<Map<String, dynamic>> _trackingLocations = [];
  bool _isTracking = false;
  StreamSubscription<dynamic>? _trackingSubscription;

  @override
  void dispose() {
    _trackingSubscription?.cancel();
    super.dispose();
  }

  Future<void> _requestPermission() async {
    setState(() => _status = 'Requesting permission...');
    try {
      final result = await _methodChannel.invokeMethod('requestPermission');
      setState(() {
        _permissionStatus = result['status'] ?? 'unknown';
        _status = 'Permission: $_permissionStatus';
      });
    } on PlatformException catch (e) {
      setState(() => _status = 'Permission error: ${e.message}');
    }
  }

  Future<void> _getProviderState() async {
    try {
      final result = await _methodChannel.invokeMethod('getProviderState');
      setState(() {
        _permissionStatus = result['hasPermission'] == true ? 'granted' : 'denied';
        _status = 'Platform: ${result['platform']}, API: ${result['apiLevel']}, '
            'Permission: $_permissionStatus';
      });
    } on PlatformException catch (e) {
      setState(() => _status = 'Error: ${e.message}');
    }
  }

  Future<void> _getCurrentPosition() async {
    setState(() => _status = 'Getting current position...');
    try {
      final result = await _methodChannel.invokeMethod('getCurrentPosition');
      final location = Map<String, dynamic>.from(result as Map);
      setState(() {
        _currentLocation = location;
        _status = 'Position received!';
      });
    } on PlatformException catch (e) {
      setState(() => _status = 'Error: ${e.code} - ${e.message}');
    }
  }

  Future<void> _toggleTracking() async {
    if (_isTracking) {
      // Stop tracking
      try {
        await _methodChannel.invokeMethod('stopTracking');
        _trackingSubscription?.cancel();
        _trackingSubscription = null;
        setState(() {
          _isTracking = false;
          _status = 'Tracking stopped. Got ${_trackingLocations.length} locations.';
        });
      } on PlatformException catch (e) {
        setState(() => _status = 'Stop error: ${e.message}');
      }
    } else {
      // Start tracking
      setState(() {
        _trackingLocations.clear();
        _status = 'Starting tracking...';
      });
      try {
        // Listen to event channel first
        _trackingSubscription = _eventChannel.receiveBroadcastStream().listen(
          (event) {
            if (event is Map) {
              final location = Map<String, dynamic>.from(event);
              setState(() {
                _trackingLocations.insert(0, location);
                _currentLocation = location;
                _status = 'Tracking... ${_trackingLocations.length} locations';
              });
            }
          },
          onError: (error) {
            setState(() => _status = 'Stream error: $error');
          },
        );

        await _methodChannel.invokeMethod('startTracking', {
          'interval': 3000,
          'distanceFilter': 5.0,
        });
        setState(() {
          _isTracking = true;
          _status = 'Tracking started (3s interval, 5m filter)';
        });
      } on PlatformException catch (e) {
        setState(() => _status = 'Start error: ${e.message}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tracelet Location Test'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status card
            Card(
              color: _isTracking ? Colors.green.shade50 : null,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(
                      _isTracking ? Icons.my_location : Icons.location_off,
                      size: 48,
                      color: _isTracking ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _status,
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Action buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _requestPermission,
                  icon: const Icon(Icons.shield),
                  label: const Text('Permission'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _getProviderState,
                  icon: const Icon(Icons.info_outline),
                  label: const Text('Provider'),
                ),
                FilledButton.icon(
                  onPressed: _getCurrentPosition,
                  icon: const Icon(Icons.gps_fixed),
                  label: const Text('Get Position'),
                ),
                FilledButton.icon(
                  onPressed: _toggleTracking,
                  icon: Icon(_isTracking ? Icons.stop : Icons.play_arrow),
                  label: Text(_isTracking ? 'Stop' : 'Track'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _isTracking ? Colors.red : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Current location
            if (_currentLocation != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Current Location',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      _locationRow('Lat', _currentLocation!['latitude']),
                      _locationRow('Lng', _currentLocation!['longitude']),
                      _locationRow('Alt', _currentLocation!['altitude']),
                      _locationRow('Accuracy', '${_currentLocation!['accuracy']}m'),
                      _locationRow('Speed', '${_currentLocation!['speed']} m/s'),
                      _locationRow('Heading', '${_currentLocation!['heading']}°'),
                      _locationRow('Provider', _currentLocation!['provider']),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Tracking history
            if (_trackingLocations.isNotEmpty) ...[
              Text('Tracking History (${_trackingLocations.length})',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _trackingLocations.length,
                  itemBuilder: (context, index) {
                    final loc = _trackingLocations[index];
                    return ListTile(
                      dense: true,
                      leading: Text('#${index + 1}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      title: Text(
                        '${(loc['latitude'] as num).toStringAsFixed(6)}, '
                        '${(loc['longitude'] as num).toStringAsFixed(6)}',
                      ),
                      subtitle: Text(
                        'Acc: ${(loc['accuracy'] as num).toStringAsFixed(1)}m  '
                        'Speed: ${(loc['speed'] as num).toStringAsFixed(1)} m/s',
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _locationRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text('$value')),
        ],
      ),
    );
  }
}
