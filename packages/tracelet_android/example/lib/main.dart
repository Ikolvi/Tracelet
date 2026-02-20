import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' as tl;

// ─────────────────────────────────────────────────────────────────────────────
// Headless background callback — MUST be a top-level function.
//
// When the app UI is killed (swiped away) or the device reboots, the native
// side spins up a minimal Dart isolate and dispatches events here.
// This runs WITHOUT any Flutter UI, so you cannot use setState/context/etc.
// Typical use: persist to local DB, forward to server, update a notification.
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
void headlessTask(tl.HeadlessEvent event) {
  debugPrint('[Headless] ${event.name}: ${event.event}');
  // Example: handle specific events
  // switch (event.name) {
  //   case 'location':
  //     final loc = tl.Location.fromMap(event.event);
  //     // persist / upload
  //   case 'motionchange':
  //     // ...
  //   case 'geofence':
  //     // ...
  // }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Register headless task BEFORE runApp — this stores the callback handle
  // so the native side can invoke it even when the UI is dead.
  tl.Tracelet.registerHeadlessTask(headlessTask);

  runApp(const TraceletApp());
}

class TraceletApp extends StatelessWidget {
  const TraceletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tracelet Android Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const DashboardPage(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard
// ─────────────────────────────────────────────────────────────────────────────

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // State
  bool _isReady = false;
  bool _isTracking = false;
  bool _isMoving = false;
  tl.Location? _lastLocation;
  tl.State? _pluginState;
  final List<_LogEntry> _log = [];

  // Subscriptions
  final List<StreamSubscription<Object?>> _subs = [];

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  void _addLog(String tag, String message) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    setState(() {
      _log.insert(0, _LogEntry(ts, tag, message));
      if (_log.length > 200) _log.removeLast();
    });
  }

  // ── Event Subscriptions ─────────────────────────────────────────────────

  void _subscribeEvents() {
    _subs.add(tl.Tracelet.onLocation((loc) {
      setState(() => _lastLocation = loc);
      _addLog('LOCATION',
          '${loc.coords.latitude.toStringAsFixed(6)}, ${loc.coords.longitude.toStringAsFixed(6)}  '
          'acc=${loc.coords.accuracy.toStringAsFixed(1)}m  spd=${loc.coords.speed.toStringAsFixed(1)}m/s');
    }));

    _subs.add(tl.Tracelet.onMotionChange((loc) {
      setState(() {
        _isMoving = loc.isMoving;
        _lastLocation = loc;
      });
      _addLog('MOTION', loc.isMoving ? 'MOVING' : 'STATIONARY');
    }));

    _subs.add(tl.Tracelet.onActivityChange((evt) {
      _addLog('ACTIVITY', '${evt.activity.name} (${evt.confidence.name})');
    }));

    _subs.add(tl.Tracelet.onProviderChange((evt) {
      _addLog('PROVIDER',
          'enabled=${evt.enabled}  status=${evt.status.name}  gps=${evt.gps}  network=${evt.network}');
    }));

    _subs.add(tl.Tracelet.onGeofence((evt) {
      _addLog('GEOFENCE', '${evt.action.name} → ${evt.identifier}');
    }));

    _subs.add(tl.Tracelet.onGeofencesChange((evt) {
      _addLog('GEOFENCES_CHANGE', 'on=${evt.on.length}, off=${evt.off.length}');
    }));

    _subs.add(tl.Tracelet.onHeartbeat((evt) {
      _addLog('HEARTBEAT',
          '${evt.location.coords.latitude.toStringAsFixed(4)}, ${evt.location.coords.longitude.toStringAsFixed(4)}');
    }));

    _subs.add(tl.Tracelet.onHttp((evt) {
      _addLog('HTTP', 'status=${evt.status}  success=${evt.success}');
    }));

    _subs.add(tl.Tracelet.onSchedule((state) {
      _addLog('SCHEDULE', 'enabled=${state.enabled}');
    }));

    _subs.add(tl.Tracelet.onPowerSaveChange((on) {
      _addLog('POWER_SAVE', on ? 'ON' : 'OFF');
    }));

    _subs.add(tl.Tracelet.onConnectivityChange((evt) {
      _addLog('CONNECTIVITY', 'connected=${evt.connected}');
    }));

    _subs.add(tl.Tracelet.onEnabledChange((on) {
      setState(() => _isTracking = on);
      _addLog('ENABLED', on ? 'ON' : 'OFF');
    }));

    _subs.add(tl.Tracelet.onNotificationAction((action) {
      _addLog('NOTIF_ACTION', action);
    }));

    _subs.add(tl.Tracelet.onAuthorization((evt) {
      _addLog('AUTH', 'success=${evt.success}  response=${evt.response}');
    }));
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────

  Future<void> _initialize() async {
    try {
      _subscribeEvents();

      final state = await tl.Tracelet.ready(tl.Config(
        geo: const tl.GeoConfig(
          desiredAccuracy: tl.DesiredAccuracy.high,
          distanceFilter: 10,
          stationaryRadius: 25,
          locationTimeout: 60,
        ),
        app: const tl.AppConfig(
          stopOnTerminate: false,
          startOnBoot: true,
          heartbeatInterval: 60,
          foregroundService: tl.ForegroundServiceConfig(
            notificationTitle: 'Tracelet Demo',
            notificationText: 'Tracking in background',
          ),
        ),
        motion: const tl.MotionConfig(
          stopTimeout: 5,
        ),
        logger: const tl.LoggerConfig(
          logLevel: tl.LogLevel.verbose,
          debug: true,
        ),
      ));

      setState(() {
        _isReady = true;
        _isTracking = state.enabled;
        _pluginState = state;
      });
      _addLog('READY',
          'enabled=${state.enabled}  mode=${state.trackingMode.name}  odometer=${state.odometer.toStringAsFixed(0)}m');
    } catch (e) {
      _addLog('ERROR', 'ready() failed: $e');
    }
  }

  Future<void> _start() async {
    try {
      // Ensure location permission is granted before starting — Android 14+
      // requires it BEFORE starting a foreground service with location type.
      final authStatus = await tl.Tracelet.requestPermission();
      if (authStatus < 2) {
        _addLog('WARN', 'Location permission denied (status=$authStatus). Cannot start.');
        return;
      }

      final state = await tl.Tracelet.start();
      setState(() {
        _isTracking = state.enabled;
        _pluginState = state;
      });
      _addLog('START', 'enabled=${state.enabled}');
    } catch (e) {
      _addLog('ERROR', 'start() failed: $e');
    }
  }

  Future<void> _stop() async {
    try {
      final state = await tl.Tracelet.stop();
      setState(() {
        _isTracking = state.enabled;
        _pluginState = state;
      });
      _addLog('STOP', 'enabled=${state.enabled}');
    } catch (e) {
      _addLog('ERROR', 'stop() failed: $e');
    }
  }

  Future<void> _startGeofences() async {
    try {
      final state = await tl.Tracelet.startGeofences();
      setState(() {
        _isTracking = state.enabled;
        _pluginState = state;
      });
      _addLog('GEOFENCES_ONLY', 'started  mode=${state.trackingMode.name}');
    } catch (e) {
      _addLog('ERROR', 'startGeofences() failed: $e');
    }
  }

  // ── Location ────────────────────────────────────────────────────────────

  Future<void> _getCurrentPosition() async {
    try {
      final loc = await tl.Tracelet.getCurrentPosition(
        desiredAccuracy: tl.DesiredAccuracy.high,
        timeout: 30,
      );
      setState(() => _lastLocation = loc);
      _addLog('POSITION',
          '${loc.coords.latitude.toStringAsFixed(6)}, ${loc.coords.longitude.toStringAsFixed(6)}  '
          'acc=${loc.coords.accuracy.toStringAsFixed(1)}m');
    } catch (e) {
      _addLog('ERROR', 'getCurrentPosition() failed: $e');
    }
  }

  Future<void> _changePace() async {
    try {
      final newPace = !_isMoving;
      await tl.Tracelet.changePace(newPace);
      setState(() => _isMoving = newPace);
      _addLog('PACE', newPace ? 'forced MOVING' : 'forced STATIONARY');
    } catch (e) {
      _addLog('ERROR', 'changePace() failed: $e');
    }
  }

  Future<void> _getOdometer() async {
    try {
      final meters = await tl.Tracelet.getOdometer();
      _addLog('ODOMETER', '${meters.toStringAsFixed(1)} m');
    } catch (e) {
      _addLog('ERROR', 'getOdometer() failed: $e');
    }
  }

  Future<void> _resetOdometer() async {
    try {
      final loc = await tl.Tracelet.setOdometer(0);
      _addLog('ODOMETER', 'reset at ${loc.coords.latitude.toStringAsFixed(4)}, ${loc.coords.longitude.toStringAsFixed(4)}');
    } catch (e) {
      _addLog('ERROR', 'setOdometer() failed: $e');
    }
  }

  // ── Geofencing ──────────────────────────────────────────────────────────

  Future<void> _addGeofenceAtCurrentLocation() async {
    if (_lastLocation == null) {
      _addLog('WARN', 'No location yet — get a position first');
      return;
    }
    try {
      final loc = _lastLocation!;
      final id = 'geo_${DateTime.now().millisecondsSinceEpoch}';
      await tl.Tracelet.addGeofence(tl.Geofence(
        identifier: id,
        latitude: loc.coords.latitude,
        longitude: loc.coords.longitude,
        radius: 200,
        notifyOnEntry: true,
        notifyOnExit: true,
        notifyOnDwell: true,
        loiteringDelay: 30000,
      ));
      _addLog('GEOFENCE+', '$id  r=200m  at ${loc.coords.latitude.toStringAsFixed(4)}, ${loc.coords.longitude.toStringAsFixed(4)}');
    } catch (e) {
      _addLog('ERROR', 'addGeofence() failed: $e');
    }
  }

  Future<void> _listGeofences() async {
    try {
      final fences = await tl.Tracelet.getGeofences();
      _addLog('GEOFENCES', '${fences.length} registered');
      for (final f in fences) {
        _addLog('  FENCE', '${f.identifier}  (${f.latitude.toStringAsFixed(4)}, ${f.longitude.toStringAsFixed(4)})  r=${f.radius}m');
      }
    } catch (e) {
      _addLog('ERROR', 'getGeofences() failed: $e');
    }
  }

  Future<void> _removeAllGeofences() async {
    try {
      await tl.Tracelet.removeGeofences();
      _addLog('GEOFENCES', 'all removed');
    } catch (e) {
      _addLog('ERROR', 'removeGeofences() failed: $e');
    }
  }

  // ── Persistence ─────────────────────────────────────────────────────────

  Future<void> _getCount() async {
    try {
      final count = await tl.Tracelet.getCount();
      _addLog('DB', '$count locations stored');
    } catch (e) {
      _addLog('ERROR', 'getCount() failed: $e');
    }
  }

  Future<void> _getLocations() async {
    try {
      final locs = await tl.Tracelet.getLocations();
      _addLog('DB', '${locs.length} locations retrieved');
      for (final l in locs.take(5)) {
        _addLog('  LOC', '${l.coords.latitude.toStringAsFixed(4)}, ${l.coords.longitude.toStringAsFixed(4)} @ ${l.timestamp}');
      }
      if (locs.length > 5) {
        _addLog('  ...', '${locs.length - 5} more');
      }
    } catch (e) {
      _addLog('ERROR', 'getLocations() failed: $e');
    }
  }

  Future<void> _destroyLocations() async {
    try {
      await tl.Tracelet.destroyLocations();
      _addLog('DB', 'all locations destroyed');
    } catch (e) {
      _addLog('ERROR', 'destroyLocations() failed: $e');
    }
  }

  // ── Utility ─────────────────────────────────────────────────────────────

  Future<void> _getState() async {
    try {
      final state = await tl.Tracelet.getState();
      setState(() => _pluginState = state);
      _addLog('STATE',
          'enabled=${state.enabled}  mode=${state.trackingMode.name}  '
          'odometer=${state.odometer.toStringAsFixed(0)}m  scheduler=${state.schedulerEnabled}');
    } catch (e) {
      _addLog('ERROR', 'getState() failed: $e');
    }
  }

  Future<void> _getProviderState() async {
    try {
      final p = await tl.Tracelet.getProviderState();
      _addLog('PROVIDER',
          'enabled=${p.enabled}  status=${p.status.name}  gps=${p.gps}  network=${p.network}');
    } catch (e) {
      _addLog('ERROR', 'getProviderState() failed: $e');
    }
  }

  Future<void> _requestPermission() async {
    try {
      final result = await tl.Tracelet.requestPermission();
      _addLog('PERMISSION', 'result=$result');
    } catch (e) {
      _addLog('ERROR', 'requestPermission() failed: $e');
    }
  }

  Future<void> _getSensors() async {
    try {
      final s = await tl.Tracelet.getSensors();
      _addLog('SENSORS', 'platform=${s.platform}  accelerometer=${s.accelerometer}  gyroscope=${s.gyroscope}  magnetometer=${s.magnetometer}  significantMotion=${s.significantMotion}');
    } catch (e) {
      _addLog('ERROR', 'getSensors() failed: $e');
    }
  }

  Future<void> _getDeviceInfo() async {
    try {
      final d = await tl.Tracelet.getDeviceInfo();
      _addLog('DEVICE', 'model=${d.model}  platform=${d.platform}  version=${d.version}  manufacturer=${d.manufacturer}');
    } catch (e) {
      _addLog('ERROR', 'getDeviceInfo() failed: $e');
    }
  }

  Future<void> _isPowerSaveMode() async {
    try {
      final on = await tl.Tracelet.isPowerSaveMode;
      _addLog('BATTERY', 'power save mode: ${on ? "ON" : "OFF"}');
    } catch (e) {
      _addLog('ERROR', 'isPowerSaveMode failed: $e');
    }
  }

  Future<void> _isIgnoringBatteryOptimizations() async {
    try {
      final ok = await tl.Tracelet.isIgnoringBatteryOptimizations();
      _addLog('BATTERY', 'ignoring battery optimizations: ${ok ? "YES" : "NO"}');
    } catch (e) {
      _addLog('ERROR', 'isIgnoringBatteryOptimizations() failed: $e');
    }
  }

  // ── Logging ─────────────────────────────────────────────────────────────

  Future<void> _getLog() async {
    try {
      final log = await tl.Tracelet.getLog();
      _addLog('LOG', '${log.length} chars  (last 200): ${log.substring(log.length > 200 ? log.length - 200 : 0)}');
    } catch (e) {
      _addLog('ERROR', 'getLog() failed: $e');
    }
  }

  Future<void> _destroyLog() async {
    try {
      await tl.Tracelet.destroyLog();
      _addLog('LOG', 'destroyed');
    } catch (e) {
      _addLog('ERROR', 'destroyLog() failed: $e');
    }
  }

  Future<void> _emailLog() async {
    try {
      await tl.Tracelet.emailLog('test@example.com');
      _addLog('LOG', 'email sent');
    } catch (e) {
      _addLog('ERROR', 'emailLog() failed: $e');
    }
  }

  Future<void> _httpSync() async {
    try {
      final locs = await tl.Tracelet.sync();
      _addLog('SYNC', '${locs.length} locations synced');
    } catch (e) {
      _addLog('ERROR', 'sync() failed: $e');
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tracelet Android'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Clear log',
            onPressed: () => setState(() => _log.clear()),
            icon: const Icon(Icons.delete_sweep),
          ),
        ],
      ),
      body: Column(
        children: [
          // ─── Status Card ───────────────────────────────────────────────
          _StatusCard(
            isReady: _isReady,
            isTracking: _isTracking,
            isMoving: _isMoving,
            location: _lastLocation,
            state: _pluginState,
          ),

          // ─── Action Sections ───────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: [
                // ── Init ──
                if (!_isReady)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: FilledButton.icon(
                      onPressed: _initialize,
                      icon: const Icon(Icons.power_settings_new),
                      label: const Text('Initialize Tracelet'),
                    ),
                  ),

                if (_isReady) ...[
                  // ── Lifecycle ──
                  _Section(title: 'Lifecycle', color: cs.primary, children: [
                    _Chip('Start', Icons.play_arrow, _start),
                    _Chip('Stop', Icons.stop, _stop),
                    _Chip('Geofences Only', Icons.fence, _startGeofences),
                    _Chip('Get State', Icons.info_outline, _getState),
                  ]),

                  // ── Permissions ──
                  _Section(title: 'Permissions', color: cs.tertiary, children: [
                    _Chip('Request Perm', Icons.shield, _requestPermission),
                    _Chip('Provider State', Icons.settings_input_antenna, _getProviderState),
                  ]),

                  // ── Location ──
                  _Section(title: 'Location', color: cs.secondary, children: [
                    _Chip('Get Position', Icons.my_location, _getCurrentPosition),
                    _Chip(_isMoving ? 'Pace → Still' : 'Pace → Move', Icons.directions_walk, _changePace),
                    _Chip('Odometer', Icons.speed, _getOdometer),
                    _Chip('Reset Odo', Icons.restart_alt, _resetOdometer),
                  ]),

                  // ── Geofencing ──
                  _Section(title: 'Geofencing', color: Colors.orange, children: [
                    _Chip('+ Geofence Here', Icons.add_location_alt, _addGeofenceAtCurrentLocation),
                    _Chip('List Geofences', Icons.list, _listGeofences),
                    _Chip('Remove All', Icons.delete_forever, _removeAllGeofences),
                  ]),

                  // ── Persistence ──
                  _Section(title: 'Persistence', color: Colors.teal, children: [
                    _Chip('Count', Icons.numbers, _getCount),
                    _Chip('List Locations', Icons.storage, _getLocations),
                    _Chip('Destroy All', Icons.delete, _destroyLocations),
                    _Chip('HTTP Sync', Icons.cloud_upload, _httpSync),
                  ]),

                  // ── Utility ──
                  _Section(title: 'Utility', color: Colors.purple, children: [
                    _Chip('Sensors', Icons.sensors, _getSensors),
                    _Chip('Device Info', Icons.phone_android, _getDeviceInfo),
                    _Chip('Power Save?', Icons.battery_saver, _isPowerSaveMode),
                    _Chip('Battery Opt?', Icons.battery_full, _isIgnoringBatteryOptimizations),
                  ]),

                  // ── Logging ──
                  _Section(title: 'Logging', color: Colors.brown, children: [
                    _Chip('Get Log', Icons.article, _getLog),
                    _Chip('Destroy Log', Icons.delete_outline, _destroyLog),
                    _Chip('Email Log', Icons.email, _emailLog),
                  ]),

                  const Divider(),

                  // ── Event Log ──
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('Event Log (${_log.length})',
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  ..._log.map((entry) => _LogTile(entry: entry)),
                  const SizedBox(height: 80),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status Card widget
// ─────────────────────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.isReady,
    required this.isTracking,
    required this.isMoving,
    this.location,
    this.state,
  });

  final bool isReady;
  final bool isTracking;
  final bool isMoving;
  final tl.Location? location;
  final tl.State? state;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = isTracking
        ? (isMoving ? cs.primaryContainer : cs.tertiaryContainer)
        : cs.surfaceContainerHighest;

    return Card(
      margin: const EdgeInsets.all(12),
      color: bg,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isTracking
                      ? (isMoving ? Icons.directions_run : Icons.accessibility_new)
                      : Icons.location_off,
                  size: 32,
                ),
                const SizedBox(width: 8),
                Text(
                  !isReady
                      ? 'Not Initialized'
                      : isTracking
                          ? (isMoving ? 'MOVING' : 'STATIONARY')
                          : 'STOPPED',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            if (location != null) ...[
              const SizedBox(height: 8),
              Text(
                '${location!.coords.latitude.toStringAsFixed(6)}, '
                '${location!.coords.longitude.toStringAsFixed(6)}',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontFamily: 'monospace',
                    ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 16,
                children: [
                  Text('Acc: ${location!.coords.accuracy.toStringAsFixed(1)}m'),
                  Text('Spd: ${location!.coords.speed.toStringAsFixed(1)} m/s'),
                  Text('Alt: ${location!.coords.altitude.toStringAsFixed(0)}m'),
                  if (state != null) Text('Odo: ${state!.odometer.toStringAsFixed(0)}m'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section header with chips
// ─────────────────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.color,
    required this.children,
  });

  final String title;
  final Color color;
  final List<_Chip> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: color, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: children.map((c) {
              return ActionChip(
                avatar: Icon(c.icon, size: 18),
                label: Text(c.label),
                onPressed: c.onPressed,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _Chip {
  const _Chip(this.label, this.icon, this.onPressed);
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}

// ─────────────────────────────────────────────────────────────────────────────
// Log entry model & tile
// ─────────────────────────────────────────────────────────────────────────────

class _LogEntry {
  const _LogEntry(this.time, this.tag, this.message);
  final String time;
  final String tag;
  final String message;
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});
  final _LogEntry entry;

  Color _tagColor(String tag) {
    return switch (tag) {
      'LOCATION' => Colors.blue,
      'MOTION' => Colors.deepOrange,
      'ACTIVITY' => Colors.purple,
      'PROVIDER' => Colors.teal,
      'GEOFENCE' || 'GEOFENCES_CHANGE' || 'GEOFENCE+' => Colors.orange,
      'HTTP' || 'SYNC' => Colors.cyan,
      'HEARTBEAT' => Colors.pink,
      'ERROR' || 'WARN' => Colors.red,
      'READY' || 'START' || 'STOP' => Colors.green,
      _ => Colors.grey,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(entry.time,
                style: const TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'monospace')),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: _tagColor(entry.tag).withAlpha(30),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(entry.tag,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _tagColor(entry.tag))),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(entry.message,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }
}
