import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' as tl;

// ─────────────────────────────────────────────────────────────────────────────
// Headless background callback — MUST be a top-level function.
//
// When the app UI is killed (swiped away) or the device reboots, the native
// side spins up a minimal Dart isolate and dispatches events here.
// This runs WITHOUT any Flutter UI, so you cannot use setState/context/etc.
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
void headlessTask(tl.HeadlessEvent event) {
  debugPrint('[Headless] ${event.name}: ${event.event}');
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Register headless task BEFORE runApp — stores the callback handle
  // so the native side can invoke it even when the UI is dead.
  // This is a no-op on iOS but harmless to call.
  tl.Tracelet.registerHeadlessTask(headlessTask);

  runApp(const TraceletApp());
}

class TraceletApp extends StatelessWidget {
  const TraceletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tracelet Example',
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

  bool get _isAndroid => Platform.isAndroid;

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
    _subs.add(
      tl.Tracelet.onLocation((loc) {
        setState(() => _lastLocation = loc);
        _addLog(
          'LOCATION',
          '${loc.coords.latitude.toStringAsFixed(6)}, ${loc.coords.longitude.toStringAsFixed(6)}  '
              'acc=${loc.coords.accuracy.toStringAsFixed(1)}m  spd=${loc.coords.speed.toStringAsFixed(1)}m/s  '
              'odo=${loc.odometer.toStringAsFixed(0)}m',
        );
      }),
    );

    _subs.add(
      tl.Tracelet.onMotionChange((loc) {
        setState(() {
          _isMoving = loc.isMoving;
          _lastLocation = loc;
        });
        _addLog('MOTION', loc.isMoving ? 'MOVING' : 'STATIONARY');
      }),
    );

    _subs.add(
      tl.Tracelet.onActivityChange((evt) {
        _addLog('ACTIVITY', '${evt.activity.name} (${evt.confidence.name})');
      }),
    );

    _subs.add(
      tl.Tracelet.onProviderChange((evt) {
        if (_isAndroid) {
          _addLog(
            'PROVIDER',
            'enabled=${evt.enabled}  status=${evt.status.name}  gps=${evt.gps}  network=${evt.network}',
          );
        } else {
          _addLog(
            'PROVIDER',
            'enabled=${evt.enabled}  status=${evt.status.name}  accuracy=${evt.accuracyAuthorization.name}',
          );
        }
      }),
    );

    _subs.add(
      tl.Tracelet.onGeofence((evt) {
        _addLog('GEOFENCE', '${evt.action.name} → ${evt.identifier}');
      }),
    );

    _subs.add(
      tl.Tracelet.onGeofencesChange((evt) {
        _addLog(
          'GEOFENCES_CHANGE',
          'on=${evt.on.length}, off=${evt.off.length}',
        );
      }),
    );

    _subs.add(
      tl.Tracelet.onHeartbeat((evt) {
        _addLog(
          'HEARTBEAT',
          '${evt.location.coords.latitude.toStringAsFixed(4)}, ${evt.location.coords.longitude.toStringAsFixed(4)}',
        );
      }),
    );

    _subs.add(
      tl.Tracelet.onHttp((evt) {
        _addLog('HTTP', 'status=${evt.status}  success=${evt.success}');
      }),
    );

    _subs.add(
      tl.Tracelet.onSchedule((state) {
        _addLog('SCHEDULE', 'enabled=${state.enabled}');
      }),
    );

    _subs.add(
      tl.Tracelet.onPowerSaveChange((on) {
        _addLog('POWER_SAVE', on ? 'ON' : 'OFF');
      }),
    );

    _subs.add(
      tl.Tracelet.onConnectivityChange((evt) {
        _addLog('CONNECTIVITY', 'connected=${evt.connected}');
      }),
    );

    _subs.add(
      tl.Tracelet.onEnabledChange((on) {
        setState(() => _isTracking = on);
        _addLog('ENABLED', on ? 'ON' : 'OFF');
      }),
    );

    if (_isAndroid) {
      _subs.add(
        tl.Tracelet.onNotificationAction((action) {
          _addLog('NOTIF_ACTION', action);
        }),
      );
    }

    _subs.add(
      tl.Tracelet.onAuthorization((evt) {
        _addLog('AUTH', 'success=${evt.success}  response=${evt.response}');
      }),
    );
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────

  /// Initialize with the *full-featured* config showcasing all new features.
  Future<void> _initialize() async {
    try {
      _subscribeEvents();

      // ── Permission flow (Dart-side control, no native dialogs) ──
      final permStatus = await tl.Tracelet.getPermissionStatus();
      _addLog('PERMISSION', 'current status=$permStatus');

      if (permStatus == 0 || permStatus == 1) {
        // notDetermined or denied (can ask again) → request foreground
        final result = await tl.Tracelet.requestPermission();
        _addLog('PERMISSION', 'after request=$result');
        if (result == 4) {
          if (mounted) _showPermissionDeniedDialog();
          return;
        }
        if (result == 2 && mounted) {
          // Foreground granted → offer background upgrade via Dart dialog
          final shouldUpgrade = await _showBackgroundRationaleDialog();
          if (shouldUpgrade) {
            await _upgradeToAlways();
          }
        }
      } else if (permStatus == 2 && mounted) {
        // whenInUse → offer background upgrade
        final shouldUpgrade = await _showBackgroundRationaleDialog();
        if (shouldUpgrade) {
          await _upgradeToAlways();
        }
      } else if (permStatus == 4) {
        if (mounted) _showPermissionDeniedDialog();
        return;
      }

      final state = await tl.Tracelet.ready(
        tl.Config(
          geo: tl.GeoConfig(
            desiredAccuracy: tl.DesiredAccuracy.high,
            distanceFilter: 10,
            stationaryRadius: 25,
            locationTimeout: 60,
            // ── New features ──
            disableElasticity: false,
            elasticityMultiplier: 1.0,
            enableTimestampMeta: true,
            stopAfterElapsedMinutes: -1, // disabled by default
            geofenceModeHighAccuracy: false,
            // ── Location filter (denoising) ──
            filter: tl.LocationFilter(
              trackingAccuracyThreshold: 100,
              maxImpliedSpeed: 80,
              odometerAccuracyThreshold: 50,
            ),
            // iOS-specific
            activityType: _isAndroid
                ? tl.LocationActivityType.other
                : tl.LocationActivityType.otherNavigation,
          ),
          app: tl.AppConfig(
            stopOnTerminate: false,
            startOnBoot: true,
            heartbeatInterval: 60,
            // Android foreground service
            foregroundService: _isAndroid
                ? const tl.ForegroundServiceConfig(
                    notificationTitle: 'Tracelet Demo',
                    notificationText: 'Tracking in background',
                  )
                : const tl.ForegroundServiceConfig(enabled: false),
            // ── New features ──
            preventSuspend: !_isAndroid, // iOS-only: silent-audio keep-alive
            scheduleUseAlarmManager: _isAndroid, // Android-only: exact alarms
          ),
          motion: const tl.MotionConfig(
            stopTimeout: 5,
            // ── New features ──
            minimumActivityRecognitionConfidence: 75,
            disableStopDetection: false,
            stopDetectionDelay: 0,
            stopOnStationary: false,
          ),
          http: const tl.HttpConfig(
            // ── New feature ──
            disableAutoSyncOnCellular: true,
          ),
          persistence: const tl.PersistenceConfig(
            // ── New features ──
            persistMode: tl.PersistMode.all,
            maxDaysToPersist: 7,
            maxRecordsToPersist: 5000,
            disableProviderChangeRecord: false,
          ),
          geofence: const tl.GeofenceConfig(
            geofenceProximityRadius: 1000,
            geofenceInitialTriggerEntry: true,
          ),
          logger: const tl.LoggerConfig(
            logLevel: tl.LogLevel.verbose,
            debug: true,
          ),
        ),
      );

      setState(() {
        _isReady = true;
        _isTracking = state.enabled;
        _pluginState = state;
      });
      _addLog(
        'READY',
        'enabled=${state.enabled}  mode=${state.trackingMode.name}  odometer=${state.odometer.toStringAsFixed(0)}m',
      );
    } catch (e) {
      _addLog('ERROR', 'ready() failed: $e');
    }
  }

  Future<void> _start() async {
    try {
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
      _addLog(
        'POSITION',
        '${loc.coords.latitude.toStringAsFixed(6)}, ${loc.coords.longitude.toStringAsFixed(6)}  '
            'acc=${loc.coords.accuracy.toStringAsFixed(1)}m',
      );
    } catch (e) {
      _addLog('ERROR', 'getCurrentPosition() failed: $e');
    }
  }

  // ── One-Shot Location ───────────────────────────────────────────────────

  Future<void> _singleFetchBestOfThree() async {
    try {
      _addLog('ONE-SHOT', 'Requesting best-of-3 samples...');
      final loc = await tl.Tracelet.getCurrentPosition(
        desiredAccuracy: tl.DesiredAccuracy.high,
        timeout: 30,
        samples: 3,
        persist: false,
      );
      setState(() => _lastLocation = loc);
      _addLog(
        'ONE-SHOT',
        '${loc.coords.latitude.toStringAsFixed(6)}, ${loc.coords.longitude.toStringAsFixed(6)}  '
            'acc=${loc.coords.accuracy.toStringAsFixed(1)}m  (best of 3)',
      );
    } catch (e) {
      _addLog('ERROR', 'singleFetchBestOfThree() failed: $e');
    }
  }

  Future<void> _getLastKnownLocation() async {
    try {
      final loc = await tl.Tracelet.getLastKnownLocation();
      if (loc == null) {
        _addLog('LAST_KNOWN', 'No cached location available');
        return;
      }
      setState(() => _lastLocation = loc);
      _addLog(
        'LAST_KNOWN',
        '${loc.coords.latitude.toStringAsFixed(6)}, ${loc.coords.longitude.toStringAsFixed(6)}  '
            'acc=${loc.coords.accuracy.toStringAsFixed(1)}m',
      );
    } catch (e) {
      _addLog('ERROR', 'getLastKnownLocation() failed: $e');
    }
  }

  /// Start background tracking WITH a foreground-service notification.
  ///
  /// This keeps the app alive reliably in the background on Android.
  /// On iOS the foreground service config is ignored (iOS uses its own
  /// background-mode mechanisms).
  Future<void> _startWithNotification() async {
    try {
      if (!_isReady) {
        _addLog('WARN', 'Call Initialize first');
        return;
      }

      // On Android 13+, request notification permission first so the
      // foreground service notification is actually visible.
      if (_isAndroid) {
        final hasNotification = await _ensureNotificationPermission();
        if (!hasNotification) {
          _addLog(
            'WARN',
            'Notification permission not granted — '
                'starting anyway (notification may be hidden)',
          );
        }
      }

      // Request motion / activity recognition permission so the plugin can
      // automatically detect when the device starts or stops moving.
      final hasMotion = await _ensureMotionPermission();
      if (!hasMotion) {
        _addLog(
          'WARN',
          'Motion permission not granted — '
              'automatic motion detection may not work',
        );
      }

      await tl.Tracelet.setConfig(
        const tl.Config(
          app: tl.AppConfig(
            stopOnTerminate: false,
            startOnBoot: true,
            foregroundService: tl.ForegroundServiceConfig(
              notificationTitle: 'Tracelet Demo',
              notificationText: 'Background tracking active',
            ),
          ),
        ),
      );
      final state = await tl.Tracelet.start();
      setState(() {
        _isTracking = state.enabled;
        _pluginState = state;
      });
      _addLog('START', 'Background + notification  enabled=${state.enabled}');
    } catch (e) {
      _addLog('ERROR', 'startWithNotification() failed: $e');
    }
  }

  /// Start tracking WITHOUT a foreground-service notification.
  ///
  /// The OS may kill the app at any time when it is in the background.
  /// Useful for short-lived tasks (check-in, one-shot, foreground-only use).
  Future<void> _startWithoutNotification() async {
    try {
      if (!_isReady) {
        _addLog('WARN', 'Call Initialize first');
        return;
      }
      await tl.Tracelet.setConfig(
        const tl.Config(
          app: tl.AppConfig(
            stopOnTerminate: true,
            foregroundService: tl.ForegroundServiceConfig(enabled: false),
          ),
        ),
      );
      final state = await tl.Tracelet.start();
      setState(() {
        _isTracking = state.enabled;
        _pluginState = state;
      });
      _addLog(
        'START',
        'No notification (foreground only)  enabled=${state.enabled}',
      );
    } catch (e) {
      _addLog('ERROR', 'startWithoutNotification() failed: $e');
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
      _addLog(
        'ODOMETER',
        'reset at ${loc.coords.latitude.toStringAsFixed(4)}, ${loc.coords.longitude.toStringAsFixed(4)}',
      );
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
      await tl.Tracelet.addGeofence(
        tl.Geofence(
          identifier: id,
          latitude: loc.coords.latitude,
          longitude: loc.coords.longitude,
          radius: 200,
          notifyOnEntry: true,
          notifyOnExit: true,
          notifyOnDwell: true,
          loiteringDelay: 30000,
        ),
      );
      _addLog(
        'GEOFENCE+',
        '$id  r=200m  at ${loc.coords.latitude.toStringAsFixed(4)}, ${loc.coords.longitude.toStringAsFixed(4)}',
      );
    } catch (e) {
      _addLog('ERROR', 'addGeofence() failed: $e');
    }
  }

  Future<void> _listGeofences() async {
    try {
      final fences = await tl.Tracelet.getGeofences();
      _addLog('GEOFENCES', '${fences.length} registered');
      for (final f in fences) {
        _addLog(
          '  FENCE',
          '${f.identifier}  (${f.latitude.toStringAsFixed(4)}, ${f.longitude.toStringAsFixed(4)})  r=${f.radius}m',
        );
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
        _addLog(
          '  LOC',
          '${l.coords.latitude.toStringAsFixed(4)}, ${l.coords.longitude.toStringAsFixed(4)} @ ${l.timestamp}',
        );
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
      _addLog(
        'STATE',
        'enabled=${state.enabled}  mode=${state.trackingMode.name}  '
            'odometer=${state.odometer.toStringAsFixed(0)}m  scheduler=${state.schedulerEnabled}',
      );
    } catch (e) {
      _addLog('ERROR', 'getState() failed: $e');
    }
  }

  Future<void> _getProviderState() async {
    try {
      final p = await tl.Tracelet.getProviderState();
      if (_isAndroid) {
        _addLog(
          'PROVIDER',
          'enabled=${p.enabled}  status=${p.status.name}  gps=${p.gps}  network=${p.network}',
        );
      } else {
        _addLog(
          'PROVIDER',
          'enabled=${p.enabled}  status=${p.status.name}  accuracy=${p.accuracyAuthorization.name}',
        );
      }
    } catch (e) {
      _addLog('ERROR', 'getProviderState() failed: $e');
    }
  }

  Future<void> _requestPermission() async {
    try {
      final status = await tl.Tracelet.getPermissionStatus();
      _addLog('PERMISSION', 'current=$status');

      if (status == 4) {
        if (mounted) _showPermissionDeniedDialog();
        return;
      }

      if (status == 3) {
        _addLog('PERMISSION', 'already "Always" — nothing to do');
        return;
      }

      if (status == 2) {
        // Foreground granted → offer background upgrade
        if (mounted) {
          final shouldUpgrade = await _showBackgroundRationaleDialog();
          if (shouldUpgrade) {
            final result = await tl.Tracelet.requestPermission();
            _addLog('PERMISSION', 'background upgrade=$result');
            if (result == 4 && mounted) _showPermissionDeniedDialog();
          }
        }
        return;
      }

      // notDetermined or denied → request foreground
      final result = await tl.Tracelet.requestPermission();
      _addLog('PERMISSION', 'result=$result');

      if (result == 4 && mounted) {
        _showPermissionDeniedDialog();
      } else if (result == 2 && mounted) {
        // Foreground granted → offer background upgrade
        final shouldUpgrade = await _showBackgroundRationaleDialog();
        if (shouldUpgrade) {
          final bgResult = await tl.Tracelet.requestPermission();
          _addLog('PERMISSION', 'background upgrade=$bgResult');
          if (bgResult == 4 && mounted) _showPermissionDeniedDialog();
        }
      }
    } catch (e) {
      _addLog('ERROR', 'requestPermission() failed: $e');
    }
  }

  /// Check and log permission status without triggering any dialog.
  Future<void> _checkPermissionStatus() async {
    try {
      final status = await tl.Tracelet.getPermissionStatus();
      final label = switch (status) {
        0 => 'notDetermined',
        1 => 'denied',
        2 => 'whenInUse',
        3 => 'always',
        4 => 'deniedForever',
        _ => 'unknown($status)',
      };
      _addLog('PERMISSION', '$label ($status)');
    } catch (e) {
      _addLog('ERROR', 'getPermissionStatus() failed: $e');
    }
  }

  /// Open app settings page.
  Future<void> _openAppSettings() async {
    final ok = await tl.Tracelet.openAppSettings();
    _addLog('SETTINGS', 'openAppSettings → $ok');
  }

  /// Open device location settings.
  Future<void> _openLocationSettings() async {
    final ok = await tl.Tracelet.openLocationSettings();
    _addLog('SETTINGS', 'openLocationSettings → $ok');
  }

  // ── Dart-side Permission Dialogs ────────────────────────────────────────
  //
  // These are fully customizable Flutter dialogs that replace any native
  // permission rationale dialogs. Clients can style, translate, animate
  // or replace these with their own widgets.

  /// Attempts to upgrade from whenInUse → always.
  ///
  /// On Android, `requestPermission()` will show the system dialog.
  /// On iOS 13+, `requestAlwaysAuthorization()` often does nothing
  /// visible — the system may grant "provisional Always" silently or
  /// simply not show a prompt. When the result is still `whenInUse`,
  /// this method falls back to opening App Settings so the user can
  /// toggle "Always" manually.
  Future<void> _upgradeToAlways() async {
    final bgResult = await tl.Tracelet.requestPermission();
    _addLog('PERMISSION', 'background upgrade=$bgResult');

    // On iOS, if the result is still whenInUse the OS didn't show a dialog.
    // Open Settings so the user can toggle to "Always" manually.
    if (!_isAndroid && bgResult == 2 && mounted) {
      _addLog(
        'PERMISSION',
        'iOS did not show Always prompt — opening Settings',
      );
      await tl.Tracelet.openAppSettings();
    }
  }

  /// Shown when permission is permanently denied (deniedForever).
  ///
  /// Explains the situation and offers to open the device Settings app
  /// where the user can manually re-enable location permission.
  void _showPermissionDeniedDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.location_off, color: Colors.red, size: 48),
        title: const Text('Location Permission Required'),
        content: const Text(
          'Location permission has been permanently denied. '
          'Tracelet cannot track your location without it.\n\n'
          'Please open Settings and enable location access '
          'for this app to resume tracking.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not Now'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              tl.Tracelet.openAppSettings();
            },
            icon: const Icon(Icons.settings),
            label: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Shown before requesting background ("Always") location permission.
  ///
  /// Explains WHY background access is needed so the user understands the
  /// OS prompt. Returns `true` if the user wants to proceed.
  Future<bool> _showBackgroundRationaleDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.share_location, color: Colors.indigo, size: 48),
        title: const Text('Background Location Access'),
        content: Text(
          _isAndroid
              ? 'Tracelet needs "Allow all the time" permission to '
                    'continue recording your location when the app is in '
                    'the background or the device is locked.\n\n'
                    'On the next screen, select '
                    '"Allow all the time" to enable background tracking.'
              : 'Tracelet needs "Always" location access to '
                    'continue recording your location when the app is '
                    'not in the foreground.\n\n'
                    'You may see a system prompt, or you\'ll be taken '
                    'to Settings where you can change Location to '
                    '"Always".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Foreground Only'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.upgrade),
            label: Text(
              _isAndroid
                  ? 'Change to "Allow all the time"'
                  : 'Upgrade to Always',
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _requestTempFullAccuracy() async {
    try {
      final result = await tl.Tracelet.requestTemporaryFullAccuracy(
        'TemporaryFullAccuracy',
      );
      _addLog('ACCURACY', 'temporary full accuracy result=$result');
    } catch (e) {
      _addLog('ERROR', 'requestTemporaryFullAccuracy() failed: $e');
    }
  }

  // ── Notification Permission (Android 13+) ──────────────────────────

  /// Dart-side rationale dialog explaining why notification permission
  /// is needed. Shown BEFORE the OS POST_NOTIFICATIONS prompt on
  /// Android 13+.
  ///
  /// Fully customizable — replace with your own bottom sheet,
  /// animated dialog, or localized widget.
  Future<bool> _showNotificationRationaleDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.notifications_active,
          color: Colors.deepOrange,
          size: 48,
        ),
        title: const Text('Enable Notifications'),
        content: const Text(
          'Tracelet uses a persistent notification to keep background '
          'tracking alive on Android.\n\n'
          'Without notification permission, the foreground service '
          'still runs but the notification will be hidden — some '
          'Android versions may then kill the background process.\n\n'
          'Allow notifications for the most reliable tracking.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Skip'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.notifications),
            label: const Text('Allow Notifications'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Shown when notification permission is permanently denied.
  void _showNotificationDeniedDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.notifications_off, color: Colors.red, size: 48),
        title: const Text('Notifications Blocked'),
        content: const Text(
          'Notification permission has been permanently denied.\n\n'
          'The foreground service will still run, but without a '
          'visible notification some Android versions may kill '
          'background tracking.\n\n'
          'To fix this, open Settings and enable notifications '
          'for this app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not Now'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              tl.Tracelet.openAppSettings();
            },
            icon: const Icon(Icons.settings),
            label: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Ensures notification permission is granted before starting a
  /// foreground service with notification (Android 13+ only).
  ///
  /// Returns `true` if either:
  /// - Android < 13 (no runtime permission needed)
  /// - iOS (notifications not needed for background location)
  /// - User granted notification permission
  /// - User already has permission
  ///
  /// Returns `false` if the user declined.
  Future<bool> _ensureNotificationPermission() async {
    if (!_isAndroid) return true; // iOS doesn't need this

    final status = await tl.Tracelet.getNotificationPermissionStatus();
    _addLog('NOTIFICATION', 'current notification status=$status');

    if (status == 3) return true; // Already granted (or pre-13)

    if (status == 4) {
      // Permanently denied — show denied dialog
      if (mounted) _showNotificationDeniedDialog();
      return false;
    }

    // Show rationale dialog first
    if (!mounted) return false;
    final shouldRequest = await _showNotificationRationaleDialog();
    if (!shouldRequest) {
      _addLog('NOTIFICATION', 'user skipped notification permission');
      return false;
    }

    final result = await tl.Tracelet.requestNotificationPermission();
    _addLog('NOTIFICATION', 'notification permission result=$result');

    if (result == 4 && mounted) {
      _showNotificationDeniedDialog();
      return false;
    }
    return result == 3;
  }

  /// Check and log notification permission status.
  Future<void> _checkNotificationStatus() async {
    try {
      final status = await tl.Tracelet.getNotificationPermissionStatus();
      final label = switch (status) {
        0 => 'notDetermined',
        1 => 'denied',
        3 => 'granted',
        4 => 'deniedForever',
        _ => 'unknown($status)',
      };
      _addLog('NOTIFICATION', '$label ($status)');
    } catch (e) {
      _addLog('ERROR', 'getNotificationPermissionStatus() failed: $e');
    }
  }

  // ── Motion / Activity Recognition Permission ──

  /// Shows a rationale dialog explaining why motion permission is needed.
  Future<bool> _showMotionRationaleDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.directions_walk,
          color: Colors.deepOrange,
          size: 48,
        ),
        title: const Text('Enable Motion Detection'),
        content: Text(
          _isAndroid
              ? 'Tracelet uses activity recognition to automatically detect '
                    'when you start or stop moving.\n\n'
                    'Without this permission, the plugin cannot detect motion '
                    'transitions — you would need to manually call changePace().\n\n'
                    'Allow activity recognition for automatic motion detection.'
              : 'Tracelet uses Motion & Fitness data to automatically detect '
                    'when you start or stop moving.\n\n'
                    'Without this permission, automatic motion detection will not '
                    'work — you would need to manually call changePace().\n\n'
                    'Allow Motion & Fitness access for the best experience.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Skip'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.directions_walk),
            label: const Text('Allow Motion'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Shown when motion permission is permanently denied.
  void _showMotionDeniedDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.do_not_disturb, color: Colors.red, size: 48),
        title: const Text('Motion Detection Blocked'),
        content: Text(
          _isAndroid
              ? 'Activity recognition permission has been permanently denied.\n\n'
                    'Without this, the plugin cannot automatically detect motion '
                    'transitions.\n\n'
                    'To fix this, open Settings and enable "Physical activity" '
                    'permission for this app.'
              : 'Motion & Fitness permission has been denied.\n\n'
                    'Without this, the plugin cannot automatically detect motion '
                    'transitions.\n\n'
                    'To fix this, open Settings > Privacy > Motion & Fitness '
                    'and enable access for this app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not Now'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              tl.Tracelet.openAppSettings();
            },
            icon: const Icon(Icons.settings),
            label: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Ensures motion / activity recognition permission is granted.
  ///
  /// Returns `true` if granted, `false` if denied.
  Future<bool> _ensureMotionPermission() async {
    final status = await tl.Tracelet.getMotionPermissionStatus();
    _addLog('MOTION', 'current motion permission status=$status');

    if (status == 3) return true; // Already granted

    if (status == 4) {
      // Permanently denied — show denied dialog
      if (mounted) _showMotionDeniedDialog();
      return false;
    }

    // Show rationale dialog first
    if (!mounted) return false;
    final shouldRequest = await _showMotionRationaleDialog();
    if (!shouldRequest) {
      _addLog('MOTION', 'user skipped motion permission');
      return false;
    }

    final result = await tl.Tracelet.requestMotionPermission();
    _addLog('MOTION', 'motion permission result=$result');

    if (result == 4 && mounted) {
      _showMotionDeniedDialog();
      return false;
    }
    return result == 3;
  }

  /// Check and log motion permission status.
  Future<void> _checkMotionStatus() async {
    try {
      final status = await tl.Tracelet.getMotionPermissionStatus();
      final label = switch (status) {
        0 => 'notDetermined',
        1 => 'denied',
        3 => 'granted',
        4 => 'deniedForever',
        _ => 'unknown($status)',
      };
      _addLog('MOTION', '$label ($status)');
    } catch (e) {
      _addLog('ERROR', 'getMotionPermissionStatus() failed: $e');
    }
  }

  Future<void> _getSensors() async {
    try {
      final s = await tl.Tracelet.getSensors();
      _addLog(
        'SENSORS',
        'platform=${s.platform}  accelerometer=${s.accelerometer}  gyroscope=${s.gyroscope}  magnetometer=${s.magnetometer}  significantMotion=${s.significantMotion}',
      );
    } catch (e) {
      _addLog('ERROR', 'getSensors() failed: $e');
    }
  }

  Future<void> _getDeviceInfo() async {
    try {
      final d = await tl.Tracelet.getDeviceInfo();
      _addLog(
        'DEVICE',
        'model=${d.model}  platform=${d.platform}  version=${d.version}  manufacturer=${d.manufacturer}',
      );
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
      _addLog(
        'BATTERY',
        'ignoring battery optimizations: ${ok ? "YES" : "NO"}',
      );
    } catch (e) {
      _addLog('ERROR', 'isIgnoringBatteryOptimizations() failed: $e');
    }
  }

  // ── New Feature Demos ───────────────────────────────────────────────────

  /// Re-initialize with elasticity disabled to compare tracking behavior.
  Future<void> _toggleElasticity() async {
    try {
      final state = await tl.Tracelet.setConfig(
        tl.Config(
          geo: const tl.GeoConfig(
            disableElasticity: true,
            elasticityMultiplier: 1.0,
          ),
        ),
      );
      setState(() => _pluginState = state);
      _addLog('CONFIG', 'Elasticity DISABLED (fixed distanceFilter)');
    } catch (e) {
      _addLog('ERROR', 'toggleElasticity() failed: $e');
    }
  }

  /// Re-initialize with stopAfterElapsedMinutes = 2 for a quick test.
  Future<void> _startWithAutoStop() async {
    try {
      await tl.Tracelet.setConfig(
        const tl.Config(geo: tl.GeoConfig(stopAfterElapsedMinutes: 2)),
      );
      final state = await tl.Tracelet.start();
      setState(() {
        _isTracking = state.enabled;
        _pluginState = state;
      });
      _addLog('START', 'Auto-stop in 2 minutes  enabled=${state.enabled}');
    } catch (e) {
      _addLog('ERROR', 'startWithAutoStop() failed: $e');
    }
  }

  /// Toggle geofenceModeHighAccuracy and restart geofence-only mode.
  Future<void> _startGeofencesHighAccuracy() async {
    try {
      await tl.Tracelet.setConfig(
        const tl.Config(geo: tl.GeoConfig(geofenceModeHighAccuracy: true)),
      );
      final state = await tl.Tracelet.startGeofences();
      setState(() {
        _isTracking = state.enabled;
        _pluginState = state;
      });
      _addLog(
        'GEOFENCES_HA',
        'High-accuracy geofences started  mode=${state.trackingMode.name}',
      );
    } catch (e) {
      _addLog('ERROR', 'startGeofencesHighAccuracy() failed: $e');
    }
  }

  /// Update location filter settings live.
  Future<void> _setStrictFilter() async {
    try {
      final state = await tl.Tracelet.setConfig(
        const tl.Config(
          geo: tl.GeoConfig(
            filter: tl.LocationFilter(
              trackingAccuracyThreshold: 50,
              maxImpliedSpeed: 30,
              odometerAccuracyThreshold: 20,
              policy: tl.LocationFilterPolicy.discard,
            ),
          ),
        ),
      );
      setState(() => _pluginState = state);
      _addLog(
        'CONFIG',
        'Strict filter: accuracy<50m, speed<30m/s, odometer<20m, policy=discard',
      );
    } catch (e) {
      _addLog('ERROR', 'setStrictFilter() failed: $e');
    }
  }

  /// Set persistence to geofence-only mode (location events NOT persisted).
  Future<void> _setPersistGeofenceOnly() async {
    try {
      final state = await tl.Tracelet.setConfig(
        const tl.Config(
          persistence: tl.PersistenceConfig(
            persistMode: tl.PersistMode.geofence,
            maxDaysToPersist: 3,
            maxRecordsToPersist: 1000,
          ),
        ),
      );
      setState(() => _pluginState = state);
      _addLog(
        'CONFIG',
        'Persist mode: GEOFENCE only, max 3 days / 1000 records',
      );
    } catch (e) {
      _addLog('ERROR', 'setPersistGeofenceOnly() failed: $e');
    }
  }

  // ── Logging ─────────────────────────────────────────────────────────────

  Future<void> _getLog() async {
    try {
      final log = await tl.Tracelet.getLog();
      _addLog(
        'LOG',
        '${log.length} chars  (last 200): ${log.substring(log.length > 200 ? log.length - 200 : 0)}',
      );
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
        title: Text('Tracelet ${_isAndroid ? "Android" : "iOS"}'),
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
                  _Section(
                    title: 'Lifecycle',
                    color: cs.primary,
                    children: [
                      _Chip('Start', Icons.play_arrow, _start),
                      _Chip('Stop', Icons.stop, _stop),
                      _Chip('Geofences Only', Icons.fence, _startGeofences),
                      _Chip('Get State', Icons.info_outline, _getState),
                    ],
                  ),

                  // ── Permissions ──
                  _Section(
                    title: 'Permissions',
                    color: cs.tertiary,
                    children: [
                      _Chip(
                        'Check Status',
                        Icons.policy,
                        _checkPermissionStatus,
                      ),
                      _Chip('Request Perm', Icons.shield, _requestPermission),
                      if (!_isAndroid)
                        _Chip(
                          'Temp Full Accuracy',
                          Icons.gps_fixed,
                          _requestTempFullAccuracy,
                        ),
                      if (_isAndroid)
                        _Chip(
                          'Notif Status',
                          Icons.notifications,
                          _checkNotificationStatus,
                        ),
                      _Chip(
                        'Motion Status',
                        Icons.directions_walk,
                        _checkMotionStatus,
                      ),
                      _Chip(
                        'Provider State',
                        Icons.settings_input_antenna,
                        _getProviderState,
                      ),
                      _Chip('App Settings', Icons.settings, _openAppSettings),
                      _Chip(
                        'Location Settings',
                        Icons.location_on,
                        _openLocationSettings,
                      ),
                    ],
                  ),

                  // ── Location ──
                  _Section(
                    title: 'Location',
                    color: cs.secondary,
                    children: [
                      _Chip(
                        'Get Position',
                        Icons.my_location,
                        _getCurrentPosition,
                      ),
                      _Chip(
                        _isMoving ? 'Pace → Still' : 'Pace → Move',
                        Icons.directions_walk,
                        _changePace,
                      ),
                      _Chip('Odometer', Icons.speed, _getOdometer),
                      _Chip('Reset Odo', Icons.restart_alt, _resetOdometer),
                    ],
                  ),

                  // ── Background Tracking ──
                  _Section(
                    title: 'Background Tracking',
                    color: Colors.indigo,
                    children: [
                      _Chip(
                        'Start + Notification',
                        Icons.notifications_active,
                        _startWithNotification,
                      ),
                      _Chip(
                        'Start No Notification',
                        Icons.notifications_off,
                        _startWithoutNotification,
                      ),
                    ],
                  ),

                  // ── One-Shot Location ──
                  _Section(
                    title: 'One-Shot Location',
                    color: Colors.deepPurple,
                    children: [
                      _Chip(
                        'Best of 3',
                        Icons.gps_fixed,
                        _singleFetchBestOfThree,
                      ),
                      _Chip('Last Known', Icons.history, _getLastKnownLocation),
                    ],
                  ),

                  // ── New Features ──
                  _Section(
                    title: 'New Features',
                    color: Colors.amber.shade800,
                    children: [
                      _Chip(
                        'Disable Elasticity',
                        Icons.straighten,
                        _toggleElasticity,
                      ),
                      _Chip('Auto-Stop 2min', Icons.timer, _startWithAutoStop),
                      _Chip(
                        'Strict Filter',
                        Icons.filter_alt,
                        _setStrictFilter,
                      ),
                      _Chip(
                        'Persist: GeoOnly',
                        Icons.sd_storage,
                        _setPersistGeofenceOnly,
                      ),
                    ],
                  ),

                  // ── Geofencing ──
                  _Section(
                    title: 'Geofencing',
                    color: Colors.orange,
                    children: [
                      _Chip(
                        '+ Geofence Here',
                        Icons.add_location_alt,
                        _addGeofenceAtCurrentLocation,
                      ),
                      _Chip('List Geofences', Icons.list, _listGeofences),
                      _Chip(
                        'Remove All',
                        Icons.delete_forever,
                        _removeAllGeofences,
                      ),
                      _Chip(
                        'High-Accuracy GF',
                        Icons.gps_fixed,
                        _startGeofencesHighAccuracy,
                      ),
                    ],
                  ),

                  // ── Persistence ──
                  _Section(
                    title: 'Persistence',
                    color: Colors.teal,
                    children: [
                      _Chip('Count', Icons.numbers, _getCount),
                      _Chip('List Locations', Icons.storage, _getLocations),
                      _Chip('Destroy All', Icons.delete, _destroyLocations),
                      _Chip('HTTP Sync', Icons.cloud_upload, _httpSync),
                    ],
                  ),

                  // ── Utility ──
                  _Section(
                    title: 'Utility',
                    color: Colors.purple,
                    children: [
                      _Chip('Sensors', Icons.sensors, _getSensors),
                      _Chip('Device Info', Icons.phone_android, _getDeviceInfo),
                      _Chip(
                        'Power Save?',
                        Icons.battery_saver,
                        _isPowerSaveMode,
                      ),
                      if (_isAndroid)
                        _Chip(
                          'Battery Opt?',
                          Icons.battery_full,
                          _isIgnoringBatteryOptimizations,
                        ),
                    ],
                  ),

                  // ── Logging ──
                  _Section(
                    title: 'Logging',
                    color: Colors.brown,
                    children: [
                      _Chip('Get Log', Icons.article, _getLog),
                      _Chip('Destroy Log', Icons.delete_outline, _destroyLog),
                      _Chip('Email Log', Icons.email, _emailLog),
                    ],
                  ),

                  const Divider(),

                  // ── Event Log ──
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Event Log (${_log.length})',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
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
                      ? (isMoving
                            ? Icons.directions_run
                            : Icons.accessibility_new)
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
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 16,
                children: [
                  Text('Acc: ${location!.coords.accuracy.toStringAsFixed(1)}m'),
                  Text('Spd: ${location!.coords.speed.toStringAsFixed(1)} m/s'),
                  Text('Alt: ${location!.coords.altitude.toStringAsFixed(0)}m'),
                  Text('Odo: ${location!.odometer.toStringAsFixed(0)}m'),
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
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
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
      'CONFIG' => Colors.amber,
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
            child: Text(
              entry.time,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: _tagColor(entry.tag).withAlpha(30),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              entry.tag,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: _tagColor(entry.tag),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              entry.message,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}
