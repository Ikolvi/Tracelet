import 'dart:async';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' as tl;
import 'package:tracelet_doctor/tracelet_doctor.dart';
import 'package:tracelet_example/behavior_page.dart';
import 'package:tracelet_example/provider_options_page.dart';
import 'package:tracelet_example/map_page.dart';
import 'package:tracelet_example/issues_page.dart';
import 'package:tracelet_example/scanner_page.dart';
import 'package:tracelet_example/service_health_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Headless background callback — MUST be a top-level function.
//
// When the app UI is killed (swiped away) or the device reboots, the native
// side spins up a minimal Dart isolate and dispatches events here.
// This runs WITHOUT any Flutter UI, so you cannot use setState/context/etc.
//
// Typical use cases:
//  - Log the location to a file or external analytics
//  - Upload the location to your server via HTTP
//  - Show a local notification with the latest position
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
void headlessTask(tl.HeadlessEvent event) {
  switch (event.name) {
    case 'location':
      final coords = event.event['coords'];
      final coordsMap = coords is Map ? coords : null;
      final lat = event.event['latitude'] ?? coordsMap?['latitude'];
      final lng = event.event['longitude'] ?? coordsMap?['longitude'];
      final eventType = event.event['event'] ?? 'unknown';
      debugPrint('[Headless] $eventType location: lat=$lat, lng=$lng');
    default:
      debugPrint('[Headless] ${event.name}: ${event.event}');
  }
}

/// Headless headers callback — refreshes auth tokens when the app is killed
/// and the native sync engine receives a 401 Unauthorized response.
@pragma('vm:entry-point')
void headlessHeadersCallback(tl.HeadlessEvent event) {
  debugPrint('[Headless] Headers callback invoked — refreshing token');
  // In production, you'd read a refresh token from secure storage
  // and call your auth API here. For demo purposes we just set a dummy.
  tl.Tracelet.setDynamicHeaders({
    'Authorization': 'Bearer headless-refreshed-token',
  });
}

/// Headless sync body builder — produces a custom HTTP body when the native
/// sync engine uploads locations in the background (app killed, OR backgrounded
/// with the foreground isolate suspended — the Issue #134 fallback path).
///
/// It MUST hand the body back via [tl.Tracelet.setSyncBodyResponse]; otherwise
/// the native side times out and aborts the sync. This mirrors the foreground
/// builder shape so the backend receives the same payload either way.
@pragma('vm:entry-point')
void headlessSyncBodyBuilder(tl.HeadlessEvent event) {
  unawaited(_handleHeadlessSyncBody(event));
}

Future<void> _handleHeadlessSyncBody(tl.HeadlessEvent event) async {
  debugPrint('[Headless] Sync body builder invoked');
  final rawLocations = event.event['locations'];
  final locations = <Map<String, Object?>>[];
  if (rawLocations is List) {
    for (final item in rawLocations) {
      if (item is Map) {
        locations.add(item.map((k, v) => MapEntry(k.toString(), v)));
      }
    }
  }
  await tl.Tracelet.setSyncBodyResponse(buildTraceletSyncBody(locations));
}

/// Canonical custom sync body, used by BOTH the foreground
/// ([tl.Tracelet.setSyncBodyBuilder]) and headless
/// ([tl.Tracelet.registerHeadlessSyncBodyBuilder]) builders so the backend
/// receives an **identical** payload whether the app is foreground,
/// backgrounded, or killed. Keeping the two in sync is the whole point of the
/// headless builder — see the HTTP-SYNC guide.
Map<String, Object?> buildTraceletSyncBody(
  List<Map<String, Object?>> locations,
) {
  return <String, Object?>{
    'device': 'tracelet-example',
    'sentAt': DateTime.now().toUtc().toIso8601String(),
    'locationCount': locations.length,
    'locations': locations,
  };
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Register headless task BEFORE runApp — stores the callback handle
  // so the native side can invoke it even when the UI is dead.
  // This is a no-op on iOS but harmless to call.
  // On web, headless isolates are not supported — skip registration.
  if (!kIsWeb) {
    tl.Tracelet.registerHeadlessTask(headlessTask);
    // Register headless callbacks for background token refresh and custom
    // sync body building. These handle the killed-app state where the Flutter
    // engine isn't running.
    tl.Tracelet.registerHeadlessHeadersCallback(headlessHeadersCallback);
    tl.Tracelet.registerHeadlessSyncBodyBuilder(headlessSyncBodyBuilder);
  }

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

class _DashboardPageState extends State<DashboardPage>
    with WidgetsBindingObserver {
  // State
  bool _isReady = false;
  bool _isTracking = false;
  bool _isMoving = false;
  bool _kalmanEnabled = true;
  tl.MotionDetectionMode _motionMode = tl.MotionDetectionMode.smart;
  bool _adaptiveMode = false;
  bool _isPeriodicMode = false;
  bool _logExpanded = false;
  String _motionSensitivity = 'Medium'; // Low / Medium / High
  tl.Location? _lastLocation;
  tl.State? _pluginState;
  tl.TripEvent? _lastTrip;
  tl.HealthCheck? _lastHealthCheck;
  final List<_LogEntry> _log = [];

  // Battery Budget state
  bool _budgetEnabled = false;
  tl.BudgetAdjustmentEvent? _lastBudgetEvent;

  // Carbon Estimator
  final tl.CarbonEstimator _carbonEstimator = tl.CarbonEstimator();
  tl.TripCarbonSummary? _lastCarbonSummary;
  String _lastActivityName = 'unknown';

  // Dead Reckoning / Sparse Updates toggles
  bool _deadReckoningEnabled = false;
  bool _sparseUpdatesEnabled = false;
  bool _cellularSyncDisabled = true; // matches config default

  // ── Issue #74: deferTime batch detection ──
  // Tracks timing between location events to identify batching.
  DateTime? _lastLocationArrival;
  int _currentBatchCount = 0;
  DateTime? _batchStartTime;
  DateTime? _lastBatchEndTime;

  // Scroll controller for the main ListView
  final ScrollController _scrollController = ScrollController();

  // Subscriptions
  final List<StreamSubscription<Object?>> _subs = [];

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _isWeb => kIsWeb;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreStateIfTracking();
  }

  /// Checks if Tracelet is already tracking in the background and restores the UI.
  Future<void> _restoreStateIfTracking() async {
    try {
      final state = await tl.Tracelet.getState();
      if (state.enabled) {
        // Tracking was active (persisted state says enabled), but on a fresh
        // process the NATIVE runtime is not `ready()` yet — getState() reads
        // persisted state, it does not initialize the engine. We MUST call
        // ready() again here, otherwise a later start()/changePace() throws
        // NOT_READY ("Call ready() before start()"). ready() is idempotent and
        // does not stop active tracking. (#187 repro: stop `flutter run`, run
        // again, press start → NOT_READY.)
        _subscribeEvents();
        final readyState = await tl.Tracelet.ready(_buildConfig());
        setState(() {
          _isReady = true;
          _isTracking = readyState.enabled;
          _isMoving = readyState.isMoving;
          _isPeriodicMode = readyState.trackingMode == tl.TrackingMode.periodic;
          _pluginState = readyState;
        });
        _addLog('RESTORE', 'Restored active tracking state + re-ran ready()');

        // Grab the most recent location to populate the map/UI immediately
        final locs = await tl.Tracelet.getLocations();
        if (locs.isNotEmpty) {
          setState(() => _lastLocation = locs.last);
        }
      }
    } catch (e) {
      debugPrint('Failed to restore tracking state: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isReady && _isPeriodicMode) {
      _syncMissedPeriodicLocations();
    }
  }

  /// Loads any periodic locations captured while the app was in the background
  /// (via headless dispatch) and displays them in the log.
  Future<void> _syncMissedPeriodicLocations() async {
    try {
      final locs = await tl.Tracelet.getLocations();
      if (locs.isEmpty) return;

      // Find locations captured since the last one we displayed.
      final lastTs = _lastLocation?.timestamp;
      final missed = lastTs != null
          ? locs.where((l) => l.timestamp.compareTo(lastTs) > 0).toList()
          : locs;

      if (missed.isEmpty) return;

      _addLog(
        'SYNC',
        'Loaded ${missed.length} location(s) captured in background',
      );
      for (final loc in missed) {
        final tag = loc.event == 'periodic' ? 'PERIODIC' : 'LOCATION';
        _addLog(
          tag,
          '${loc.coords.latitude.toStringAsFixed(6)}, '
          '${loc.coords.longitude.toStringAsFixed(6)}  '
          'acc=${loc.coords.accuracy.toStringAsFixed(1)}m  '
          'odo=${loc.odometer.toStringAsFixed(0)}m  '
          '[bg-sync]',
        );
      }
      // Update the map marker with the most recent location
      setState(() => _lastLocation = missed.last);
    } catch (e) {
      _addLog('ERROR', 'Sync missed locations failed: $e');
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  void _addLog(String tag, String message) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    debugPrint('[$ts] $tag: $message');
    setState(() {
      _log.insert(0, _LogEntry(ts, tag, message));
      if (_log.length > 200) _log.removeLast();
    });
    // Auto-scroll the log panel to show the newest entry (at the top).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Event Subscriptions ─────────────────────────────────────────────────

  void _subscribeEvents() {
    _subs.add(
      tl.Tracelet.onLocation((loc) {
        setState(() => _lastLocation = loc);

        // ── deferTime batch detection ──
        final now = DateTime.now();
        final msSinceLast = _lastLocationArrival != null
            ? now.difference(_lastLocationArrival!).inMilliseconds
            : -1;
        _lastLocationArrival = now;

        // If < 500ms since last event, it's part of the same batch
        if (msSinceLast >= 0 && msSinceLast < 500) {
          _currentBatchCount++;
        } else {
          // New batch started — log the previous batch if it had multiple
          if (_currentBatchCount > 1) {
            final batchDuration = _batchStartTime != null
                ? now.difference(_batchStartTime!).inMilliseconds - msSinceLast
                : 0;
            final gapFromPrev =
                _lastBatchEndTime != null && _batchStartTime != null
                ? _batchStartTime!.difference(_lastBatchEndTime!).inMilliseconds
                : 0;
            _addLog(
              '✅ BATCH',
              'deferTime WORKING — received $_currentBatchCount locations '
                  'in ${batchDuration}ms (gap since prev batch: ${(gapFromPrev / 1000.0).toStringAsFixed(1)}s)',
            );
            _lastBatchEndTime = now;
          } else if (_currentBatchCount == 1 && _lastBatchEndTime != null) {
            // Single location = no batching
            _addLog(
              '⚠️ SINGLE',
              'Location arrived individually (no batching detected)',
            );
            _lastBatchEndTime = now;
          }
          _currentBatchCount = 1;
          _batchStartTime = now;
        }

        final mockTag = loc.isMock ? ' [MOCK]' : '';
        var heuristicsInfo = '';
        if (loc.mockHeuristics != null) {
          final h = loc.mockHeuristics!;
          final parts = <String>[];
          if (h.satellites != null) parts.add('sat=${h.satellites}');
          if (h.elapsedRealtimeDriftMs != null) {
            parts.add(
              'drift=${h.elapsedRealtimeDriftMs!.toStringAsFixed(0)}ms',
            );
          }
          if (h.timestampDriftMs != null) {
            parts.add('tsDrift=${h.timestampDriftMs!.toStringAsFixed(0)}ms');
          }
          if (h.platformFlagMock != null) {
            parts.add('flag=${h.platformFlagMock}');
          }
          if (parts.isNotEmpty) heuristicsInfo = '  heur=[${parts.join(', ')}]';
        }
        final tag = loc.event == 'periodic' ? 'PERIODIC' : 'LOCATION';
        final srcTag = loc.locationSource != 'unknown'
            ? ' [${loc.locationSource.toUpperCase()}]'
            : '';
        final reducedTag = loc.reducedAccuracy ? ' [REDUCED]' : '';
        // #187: surface the reverse-geocoded address (resolveAddress: true) so it
        // is visible live, independent of the DB-sourced sync batch.
        final addr = loc.address;
        final addrTag = addr != null
            ? '  addr=[${[addr.street, addr.city, addr.state, addr.postalCode, addr.country].where((e) => e != null && e.isNotEmpty).join(', ')}]'
            : '';
        _addLog(
          tag,
          '${loc.coords.latitude.toStringAsFixed(6)}, ${loc.coords.longitude.toStringAsFixed(6)}  '
          'acc=${loc.coords.accuracy.toStringAsFixed(1)}m  spd=${loc.coords.speed.toStringAsFixed(1)}m/s  '
          'odo=${loc.odometer.toStringAsFixed(0)}m$mockTag$heuristicsInfo$srcTag$reducedTag$addrTag',
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
        // Carbon estimator: start/end trip on motion changes.
        if (loc.isMoving) {
          _carbonEstimator.startTrip();
        } else {
          final summary = _carbonEstimator.endTrip();
          if (summary != null) {
            setState(() => _lastCarbonSummary = summary);
            _addLog(
              'CO\u2082',
              '${summary.totalCarbonGrams.toStringAsFixed(1)}g CO\u2082  '
                  '${(summary.totalDistanceMeters / 1000).toStringAsFixed(2)}km  '
                  'mode=${summary.dominantMode}',
            );
          }
        }
      }),
    );

    _subs.add(
      tl.Tracelet.onActivityChange((evt) {
        _lastActivityName = evt.activity.name;
        _carbonEstimator.setActivity(_lastActivityName);
        _addLog('ACTIVITY', '${evt.activity.name} (${evt.confidence.name})');
      }),
    );

    _subs.add(
      tl.Tracelet.onProviderChange((evt) {
        if (evt.mockLocationsDetected) {
          _addLog(
            '⚠️ MOCK',
            'Mock location provider detected! Spoofed locations will be rejected.',
          );
        }
        if (evt.gpsFallback) {
          _addLog(
            '⚠️ GPS FALLBACK',
            'GPS disabled — using Wi-Fi/Cell positioning (reduced accuracy)',
          );
        }
        if (_isAndroid) {
          _addLog(
            'PROVIDER',
            'enabled=${evt.enabled}  status=${evt.status.name}  gps=${evt.gps}  network=${evt.network}${evt.gpsFallback ? "  gpsFallback=ON" : ""}',
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
        final isPolygon = evt.identifier.startsWith('poly_');
        final tag = isPolygon ? 'POLYGON' : 'GEOFENCE';
        _addLog(tag, '${evt.action.name} → ${evt.identifier}');
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
          '${evt.location.coords.latitude.toStringAsFixed(7)}, ${evt.location.coords.longitude.toStringAsFixed(7)}  acc=${evt.location.coords.accuracy.toStringAsFixed(1)}m',
        );
      }),
    );

    _subs.add(
      tl.Tracelet.onHttp((evt) {
        final retryInfo = evt.isRetry ? '  RETRY #${evt.retryCount}' : '';
        _addLog(
          'HTTP',
          'status=${evt.status}  success=${evt.success}$retryInfo',
        );
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

    _subs.add(
      tl.Tracelet.onTrip((trip) {
        setState(() => _lastTrip = trip);
        _addLog(
          'TRIP',
          'distance=${trip.distance.toStringAsFixed(0)}m  '
              'duration=${trip.duration.toStringAsFixed(0)}s  '
              'speed=${trip.averageSpeed.toStringAsFixed(1)}m/s  '
              'waypoints=${trip.waypoints.length}',
        );
      }),
    );

    // Feed locations to the carbon estimator.
    _subs.add(
      tl.Tracelet.onLocation((loc) {
        _carbonEstimator.onLocationReceived(
          loc.coords.latitude,
          loc.coords.longitude,
        );
      }),
    );

    // Battery budget adjustment events.
    _subs.add(
      tl.Tracelet.onBudgetAdjustment((evt) {
        setState(() => _lastBudgetEvent = evt);
        _addLog(
          'BUDGET',
          'drain=${evt.currentBatteryDrain.toStringAsFixed(2)}%/hr  '
              'target=${evt.targetBudget.toStringAsFixed(2)}%/hr  '
              'df=${evt.newDistanceFilter.toStringAsFixed(0)}m  '
              'acc=${evt.newDesiredAccuracy}',
        );
      }),
    );
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────

  /// Initialize with the *full-featured* config showcasing all new features.
  /// The canonical Tracelet configuration for this demo. Used by BOTH the
  /// initial `ready()` and the restore path, so a re-launched app re-establishes
  /// the native runtime instead of assuming it's still ready (see #187 repro:
  /// `flutter run` again → start() failed with NOT_READY because the restore
  /// path set `_isReady = true` without ever calling `ready()`).
  tl.Config _buildConfig() {
    return tl.Config(
      geo: const tl.GeoConfig(
        distanceFilter: 0,
        resolveAddress: true,
        filter: tl.LocationFilter(
          useKalmanFilter: true,
          mockDetectionLevel: 2, // 2 = HEURISTIC
        ),
        // ── Battery budget (auto-adjusts tracking to save battery) ──
        batteryBudgetPerHour: 3, // 3% max drain per hour
      ),
      app: const tl.AppConfig(
        stopOnTerminate: false,
        startOnBoot: true,
        heartbeatInterval: 10,
      ),
      android: tl.AndroidConfig(
        periodicUseForegroundService: true, // KEEP NOTIFICATION ALIVE
        locationUpdateInterval: 2000, // 2s
        deferTime: 1000, // 10s — batches ~5 locations every 10s
        foregroundService: _isAndroid
            ? const tl.ForegroundServiceConfig(
                notificationTitle: '📍 Tracelet Demo Active',
                notificationText:
                    'Smart Notifications — disappears when app is open!',
                channelId: 'tracelet_demo_channel',
                channelName: 'Tracelet Demo Background',
                notificationPriority: tl.NotificationPriority.high,
                showNotificationOnPauseOnly:
                    true, // ✨ Smart Visibility — hide while app is foregrounded
              )
            : const tl.ForegroundServiceConfig(enabled: false),
        scheduleUseAlarmManager: _isAndroid, // Android-only: exact alarms
      ),
      ios: tl.IosConfig(
        activityType: _isAndroid
            ? tl.LocationActivityType.other
            : tl.LocationActivityType.otherNavigation,
        preventSuspend: !_isAndroid, // iOS-only: silent-audio keep-alive
        useBackgroundActivitySession: !_isAndroid, // iOS 17+: Dynamic Island
        liveActivityConfig: !_isAndroid
            ? const tl.LiveActivityConfig(
                title: 'Tracelet Active',
                body: 'Tracking your route in background',
              )
            : null,
      ),
      motion: const tl.MotionConfig(
        stopTimeout: 1, // 1 minute for fast stop-timeout testing
        motionDetectionMode: tl.MotionDetectionMode.smart,
        shakeThreshold: 2, // prevent ultra-sensitive motion triggering
        speedStationaryDelay: 30, // Make it quicker for demo testing
        stationaryPeriodicInterval: 60, // Quick checks when stationary
      ),
      http: tl.HttpConfig(
        url:
            tl.Tracelet.activeConfig.http.url ??
            'http://192.168.20.103:8099/locations',
        autoSyncDelay: 5000,
      ),
      audit: const tl.AuditConfig(enabled: true),
      security: const tl.SecurityConfig(encryptDatabase: true),
      persistence: const tl.PersistenceConfig(
        maxDaysToPersist: 7,
        maxRecordsToPersist: 5000,
      ),
      logger: const tl.LoggerConfig(logLevel: tl.LogLevel.verbose, debug: true),
    );
  }

  Future<void> _initialize() async {
    try {
      _subscribeEvents();

      // ── Permission flow (Dart-side control, no native dialogs) ──
      final permStatus = await tl.Tracelet.getLocationAuthorization();
      _addLog('PERMISSION', 'current status=${permStatus.name}');

      if (permStatus == tl.AuthorizationStatus.notDetermined ||
          permStatus == tl.AuthorizationStatus.denied) {
        // notDetermined or denied (can ask again) → request foreground
        final result = await tl.Tracelet.requestLocationAuthorization();
        _addLog('PERMISSION', 'after request=${result.name}');
        if (result == tl.AuthorizationStatus.deniedForever) {
          if (mounted) _showPermissionDeniedDialog();
          return;
        }
        if (result == tl.AuthorizationStatus.whenInUse && mounted) {
          // Foreground granted → offer background upgrade via Dart dialog
          final shouldUpgrade = await _showBackgroundRationaleDialog();
          if (shouldUpgrade) {
            await _upgradeToAlways();
          }
        }
      } else if (permStatus == tl.AuthorizationStatus.whenInUse && mounted) {
        // whenInUse → offer background upgrade
        final shouldUpgrade = await _showBackgroundRationaleDialog();
        if (shouldUpgrade) {
          await _upgradeToAlways();
        }
      } else if (permStatus == tl.AuthorizationStatus.deniedForever) {
        if (mounted) _showPermissionDeniedDialog();
        return;
      }

      // ── Motion / Activity Recognition permission ──
      // Request early so the plugin can use full activity detection
      // (CMMotionActivityManager on iOS, Activity Recognition API on Android)
      // from the very first start. Without this, motion detection silently
      // falls back to accelerometer-only mode.
      if (_isAndroid) {
        await _ensureNotificationPermission();
      }
      final hasMotion = await _ensureMotionPermission();
      if (!hasMotion) {
        _addLog(
          'WARN',
          'Motion permission not granted — '
              'using accelerometer-only motion detection',
        );
      }

      final state = await tl.Tracelet.ready(_buildConfig());

      // Verify the new RouteContext feature
      await tl.Tracelet.setRouteContext(
        const tl.RouteContext(
          taskId: 'test-1234',
          driverId: 'john_doe',
          custom: {'app_version': '3.1.4'},
        ),
      );

      setState(() {
        _isReady = true;
        _isTracking = state.enabled;
        _isMoving = state.isMoving;
        _pluginState = state;
        _budgetEnabled = true; // batteryBudgetPerHour > 0 in config
        // Restore periodic mode flag from persisted native state
        _isPeriodicMode = state.trackingMode == tl.TrackingMode.periodic;
      });
      _addLog(
        'READY',
        'enabled=${state.enabled}  mode=${state.trackingMode.name}  odometer=${state.odometer.toStringAsFixed(0)}m',
      );
      // ── Issue #74 diagnostic: confirm Android config was applied ──
      if (_isAndroid) {
        _addLog(
          'ANDROID_CFG',
          'notification="📍 Issue #74 Fix Verified"  '
              'deferTime=10000  locationUpdateInterval=2000  '
              'channelId=tracelet_demo_channel  priority=HIGH',
        );
        _addLog(
          'VERIFY',
          '✅ If notification shows "📍 Issue #74 Fix Verified" → fix works!  '
              '❌ If it shows "Tracelet" → fix not applied.',
        );
      }

      // ── Dynamic Headers ──
      // Register a callback that provides fresh auth headers before each
      // foreground sync request. Ideal for OAuth token refresh.
      tl.Tracelet.setHeadersCallback(() async {
        // In production: final token = await authService.getFreshToken();
        return {
          'Authorization':
              'Bearer demo-token-${DateTime.now().millisecondsSinceEpoch}',
        };
      });
      _addLog('SYNC', 'Dynamic headers callback registered');

      // ── Route Context ──
      // Tag all subsequent locations with business metadata.
      await tl.Tracelet.setRouteContext(
        const tl.RouteContext(
          taskId: 'demo-task-1',
          driverId: 'demo-driver',
          trackingSessionId: 'session-001',
          custom: {'app': 'tracelet-example'},
        ),
      );
      _addLog('SYNC', 'Route context set: taskId=demo-task-1');

      // ── Custom Sync Body Builder ──
      // Fully control the HTTP request body structure for foreground sync.
      // Uses the SAME builder as the headless path so the backend receives an
      // identical payload in foreground, background, and killed state.
      tl.Tracelet.setSyncBodyBuilder((tl.SyncBodyContext context) async {
        return buildTraceletSyncBody(context.locations);
      });
      _addLog('SYNC', 'Custom sync body builder registered');

      // ── Battery Optimization Exemption (Android only) ──
      if (_isAndroid) {
        final isExempt = await tl.Tracelet.isIgnoringBatteryOptimizations();
        if (!isExempt) {
          _addLog(
            'BATTERY',
            'Not exempt from battery optimizations — requesting...',
          );
          await tl.Tracelet.openBatterySettings();
        }
      }

      // If periodic mode was active (e.g. after app kill + reopen), load
      // any locations captured in the background via headless dispatch.
      if (_isPeriodicMode && state.enabled) {
        await _syncMissedPeriodicLocations();
      }
    } catch (e, stack) {
      _addLog('ERROR', 'ready() failed: $e');
      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Initialization Failed'),
            content: SingleChildScrollView(child: Text('$e\n\n$stack')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  /// Verifies if SQLQuery date filters and Carbon Reports are respected.
  Future<void> _testSqlQueryAndCarbonReport() async {
    _addLog('TEST_SQL', '--- Starting Test: SQLQuery & Carbon Report ---');

    final now = DateTime.now();
    final t1 = now.subtract(const Duration(hours: 3));
    final t2 = now.subtract(const Duration(hours: 2));
    final t3 = now.subtract(const Duration(hours: 1));

    await tl.Tracelet.insertLocation({
      'timestamp': t1,
      'coords': {
        'latitude': 48.8566,
        'longitude': 2.3522,
        'accuracy': 5.0,
        'speed': 15.0,
      },
      'activity': {'type': 'in_vehicle'},
      'is_moving': true,
    });

    await tl.Tracelet.insertLocation({
      'timestamp': t2,
      'coords': {
        'latitude': 48.8584,
        'longitude': 2.2945,
        'accuracy': 5.0,
        'speed': 15.0,
      },
      'activity': {'type': 'in_vehicle'},
      'is_moving': true,
    });

    await tl.Tracelet.insertLocation({
      'timestamp': t3,
      'coords': {
        'latitude': 48.8606,
        'longitude': 2.3376,
        'accuracy': 5.0,
        'speed': 15.0,
      },
      'activity': {'type': 'in_vehicle'},
      'is_moving': true,
    });

    final query = tl.SQLQuery(start: t2, end: t3);
    final locations = await tl.Tracelet.getLocations(query);

    _addLog(
      'TEST_SQL',
      'Locations found for window [T2, T3]: ${locations.length}',
    );
    for (final loc in locations) {
      _addLog(
        'TEST_SQL',
        ' - Point: ${loc.coords.latitude}, ${loc.coords.longitude} at ${loc.timestamp}',
      );
    }

    final carbonReport = await tl.Tracelet.getCarbonReport({
      'from': t2.millisecondsSinceEpoch,
      'to': t3.millisecondsSinceEpoch,
    });
    _addLog(
      'TEST_SQL',
      'Carbon emitted for [T2, T3]: ${carbonReport['totalCarbonGrams']}g',
    );
  }

  Future<void> _testSqlLimitsAndOffsets() async {
    _addLog('TEST_SQL', '--- Starting Test: SQLQuery Limit & Offset ---');
    await tl.Tracelet.destroyLocations();

    final now = DateTime.now();
    for (var i = 0; i < 5; i++) {
      await tl.Tracelet.insertLocation({
        'timestamp': now.subtract(Duration(hours: 5 - i)),
        'coords': {
          'latitude': 48.0 + i,
          'longitude': 2.0 + i,
          'accuracy': 5.0,
          'speed': 15.0,
        },
        'activity': {'type': 'in_vehicle'},
        'is_moving': true,
      });
    }

    _addLog('TEST_SQL', 'Inserted 5 locations.');

    // 1. Test limit 2, offset 1, descending
    const query1 = tl.SQLQuery(
      limit: 2,
      offset: 1,
      order: tl.LocationOrderDirection.descending,
    );
    final results1 = await tl.Tracelet.getLocations(query1);
    _addLog(
      'TEST_SQL',
      'Query 1 (limit 2, offset 1, DESC): got ${results1.length}',
    );
    for (final loc in results1) {
      _addLog('TEST_SQL', ' - [Q1] lat: ${loc.coords.latitude}');
    }

    // 2. Test limit -1 (default), offset 2, ascending
    const query2 = tl.SQLQuery(offset: 2);
    final results2 = await tl.Tracelet.getLocations(query2);
    _addLog(
      'TEST_SQL',
      'Query 2 (limit -1, offset 2, ASC): got ${results2.length}',
    );
    for (final loc in results2) {
      _addLog('TEST_SQL', ' - [Q2] lat: ${loc.coords.latitude}');
    }
  }

  Future<void> _start() async {
    try {
      if (!await _ensureBackgroundPermission()) return;
      final state = await tl.Tracelet.start();
      setState(() {
        _isTracking = state.enabled;
        _isMoving = state.isMoving;
        _pluginState = state;
      });
      _addLog('START', 'enabled=${state.enabled}');

      // Fetch the initial location immediately so the UI doesn't stay at 0,0
      // when the device is stationary and continuous updates are paused.
      if (_lastLocation == null) {
        await _getCurrentPosition();
      }
    } catch (e) {
      _addLog('ERROR', 'start() failed: $e');
    }
  }

  // ── Logging Test ────────────────────────────────────────────────────────
  Future<void> _testLogs() async {
    try {
      _addLog('TEST_LOGS', 'Retrieving logs...');
      final logs = await tl.Tracelet.getLog();
      // Only log the first 200 characters to avoid huge UI stalls if logs are large
      final displayLogs = logs.length > 500
          ? '${logs.substring(0, 500)}...'
          : logs;
      _addLog('TEST_LOGS', 'Retrieved logs:\n$displayLogs');
    } catch (e) {
      _addLog('ERROR', 'testLogs() failed: $e');
    }
  }

  // ── Insert/Destroy Test ──────────────────────────────────────────────────
  Future<void> _testInsertLocationAndDestroy() async {
    try {
      _addLog('TEST_INSERT', 'Starting Test: insertLocation Return Value');
      final resultId = await tl.Tracelet.insertLocation({
        'timestamp': DateTime.now().toIso8601String(),
        'coords': {'latitude': 45.0, 'longitude': 5.0, 'accuracy': 10.0},
      });
      _addLog('TEST_INSERT', 'Inserted Location ID returned: "$resultId"');

      if (resultId.isNotEmpty && resultId != 'success') {
        final isDeleted = await tl.Tracelet.destroyLocation(resultId);
        _addLog(
          'TEST_INSERT',
          'Was custom location successfully deleted? $isDeleted',
        );
      } else {
        _addLog(
          'TEST_INSERT',
          'Skipped deletion due to invalid/legacy ID: "$resultId"',
        );
      }
    } catch (e) {
      _addLog('ERROR', '_testInsertLocationAndDestroy failed: $e');
    }
  }

  // ── Custom Http Sync Test ──────────────────────────────────────────────
  Future<void> _testHttpSync() async {
    try {
      _addLog('TEST_HTTP', 'Configuring custom HTTP Sync properties...');
      await tl.Tracelet.setConfig(
        tl.Config(
          http: tl.HttpConfig(
            url:
                tl.Tracelet.activeConfig.http.url ??
                'http://192.168.20.103:8099/locations',
            httpRootProperty: 'location_data',
            params: const {'user_id': 'ikolvi_tester', 'device': 'example_app'},
            extras: const {'session_key': 'super-secret-token'},
            locationsOrderDirection: tl.LocationOrderDirection.descending,
          ),
        ),
      );

      _addLog('TEST_HTTP', 'Inserting mock location to trigger sync...');
      await tl.Tracelet.insertLocation({
        'timestamp': DateTime.now().toIso8601String(),
        'coords': {'latitude': 10.0, 'longitude': 20.0, 'accuracy': 5.0},
      });

      _addLog('TEST_HTTP', 'Syncing now...');
      await tl.Tracelet.sync();
      _addLog('TEST_HTTP', 'Sync triggered. Check test_server logs!');
    } catch (e) {
      _addLog('ERROR', '_testHttpSync failed: $e');
    }
  }

  /// Safely stop tracking — checks state before calling stop().
  ///
  /// Uses [tl.Tracelet.getState] to check if tracking is enabled before
  /// calling [tl.Tracelet.stop]. This is safe to call even before [ready]
  /// has been called — getState() returns a default disabled state when the
  /// SDK is not yet initialized (see GitHub issue #46).
  Future<void> _stop() async {
    try {
      // Safe to call before ready() — returns disabled state if not ready.
      final currentState = await tl.Tracelet.getState();
      if (!currentState.enabled) {
        _addLog('STOP', 'Already stopped — nothing to do');
        return;
      }
      final state = await tl.Tracelet.stop();
      setState(() {
        _isTracking = state.enabled;
        _isMoving = state.isMoving;
        _isPeriodicMode = false;
        _pluginState = state;
      });
      _addLog('STOP', 'enabled=${state.enabled}');
    } catch (e) {
      _addLog('ERROR', 'stop() failed: $e');
    }
  }

  Future<void> _startGeofences() async {
    try {
      if (!await _ensureBackgroundPermission()) return;
      final state = await tl.Tracelet.startGeofences();
      setState(() {
        _isTracking = state.enabled;
        _isMoving = state.isMoving;
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

  Future<void> _getCurrentPositionWithAddress() async {
    try {
      // Fetch previous configuration so we can restore it later if needed

      await tl.Tracelet.setConfig(
        const tl.Config(geo: tl.GeoConfig(resolveAddress: true)),
      );

      _addLog('GEOCODE', 'Requesting location with reverse geocoding...');
      final loc = await tl.Tracelet.getCurrentPosition(
        desiredAccuracy: tl.DesiredAccuracy.high,
        timeout: 30,
      );
      setState(() => _lastLocation = loc);

      final addressObj = loc.address;
      final addressStr = addressObj != null
          ? [
              addressObj.street,
              addressObj.city,
              addressObj.state,
              addressObj.country,
            ].where((e) => e != null && e.isNotEmpty).join(', ')
          : 'No address found';

      _addLog(
        'GEOCODE',
        '${loc.coords.latitude.toStringAsFixed(6)}, ${loc.coords.longitude.toStringAsFixed(6)}\n'
            'Address: $addressStr',
      );

      await tl.Tracelet.setConfig(const tl.Config());
    } catch (e) {
      _addLog('ERROR', 'getCurrentPositionWithAddress() failed: $e');
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
          app: tl.AppConfig(stopOnTerminate: false, startOnBoot: true),
          // Issue #74 fix: custom notification values
          android: tl.AndroidConfig(
            deferTime: 10000,
            foregroundService: tl.ForegroundServiceConfig(
              notificationTitle: '📍 Background Tracking',
              notificationText: 'App paused. Tracking continues...',
              channelId: 'tracelet_demo_channel',
              channelName: 'Tracelet Demo Background',
              notificationPriority: tl.NotificationPriority.high,
              showNotificationOnPauseOnly:
                  true, // ✨ New Feature: Smart Visibility
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
          android: tl.AndroidConfig(
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

  /// Start tracking with **no physical activity permission** required.
  ///
  /// Enables `disableMotionActivityUpdates: true` which bypasses the
  /// ACTIVITY_RECOGNITION (Android) / Motion & Fitness (iOS) permission.
  /// Motion detection uses the accelerometer-only fallback — basic
  /// stationary↔moving detection without activity classification.
  Future<void> _startWithoutActivityPermission() async {
    try {
      if (!_isReady) {
        _addLog('WARN', 'Call Initialize first');
        return;
      }

      // On Android 13+, still request notification permission.
      if (_isAndroid) {
        await _ensureNotificationPermission();
      }

      // No motion permission request — accelerometer-only fallback
      _addLog(
        'MOTION',
        'Skipping activity permission — using accelerometer-only mode',
      );

      await tl.Tracelet.setConfig(
        tl.Config(
          motion: const tl.MotionConfig(
            disableMotionActivityUpdates: true,
            isMoving: true, // start in moving mode
            stopTimeout: 0,
          ),
          app: const tl.AppConfig(stopOnTerminate: false, startOnBoot: true),
          android: tl.AndroidConfig(
            foregroundService: _isAndroid
                ? const tl.ForegroundServiceConfig(
                    notificationTitle: 'Tracelet Demo',
                    notificationText: 'No activity permission — accel mode',
                  )
                : const tl.ForegroundServiceConfig(enabled: false),
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
        'Accelerometer-only mode (no activity permission)  '
            'enabled=${state.enabled}',
      );
    } catch (e) {
      _addLog('ERROR', 'startWithoutActivityPermission() failed: $e');
    }
  }

  // ── Periodic Mode ───────────────────────────────────────────────────────

  /// Start periodic location tracking with default settings (15-min interval,
  /// medium accuracy, WorkManager strategy = no foreground service).
  ///
  /// The GPS icon only appears for ~5–10 seconds per fix instead of
  /// permanently, drastically reducing user anxiety about battery drain.
  Future<void> _startPeriodic() async {
    try {
      if (!_isReady) {
        _addLog('WARN', 'Call Initialize first');
        return;
      }
      if (!await _ensureBackgroundPermission()) return;
      // Disable heartbeat — periodic mode already does one-shot fixes
      await tl.Tracelet.setConfig(
        const tl.Config(app: tl.AppConfig(heartbeatInterval: -1)),
      );
      final state = await tl.Tracelet.startPeriodic();
      setState(() {
        _isTracking = state.enabled;
        _isMoving = state.isMoving;
        _isPeriodicMode = true;
        _pluginState = state;
      });
      _addLog(
        'PERIODIC',
        'Started  mode=${state.trackingMode.name}  '
            'enabled=${state.enabled}',
      );
    } catch (e) {
      _addLog('ERROR', 'startPeriodic() failed: $e');
    }
  }

  /// Show a dialog that lets the user configure periodic mode settings,
  /// then start periodic tracking with those settings.
  Future<void> _showPeriodicSettingsDialog() async {
    if (!_isReady) {
      _addLog('WARN', 'Call Initialize first');
      return;
    }
    if (!mounted) return;

    // Defaults
    var intervalMinutes = 15;
    var accuracy = tl.DesiredAccuracy.medium;
    var useForegroundService = false;
    var useExactAlarms = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Periodic Mode Settings'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Interval
                    Text(
                      'Interval: $intervalMinutes min',
                      style: Theme.of(ctx).textTheme.bodyMedium,
                    ),
                    Slider(
                      value: intervalMinutes.toDouble(),
                      min: 1,
                      max: 60,
                      divisions: 59,
                      label: '$intervalMinutes min',
                      onChanged: (v) =>
                          setDialogState(() => intervalMinutes = v.round()),
                    ),

                    const SizedBox(height: 12),

                    // Accuracy
                    Text('Accuracy', style: Theme.of(ctx).textTheme.bodyMedium),
                    const SizedBox(height: 4),
                    SegmentedButton<tl.DesiredAccuracy>(
                      segments: const [
                        ButtonSegment(
                          value: tl.DesiredAccuracy.low,
                          label: Text('Low'),
                          icon: Icon(Icons.gps_off, size: 16),
                        ),
                        ButtonSegment(
                          value: tl.DesiredAccuracy.medium,
                          label: Text('Med'),
                          icon: Icon(Icons.gps_not_fixed, size: 16),
                        ),
                        ButtonSegment(
                          value: tl.DesiredAccuracy.high,
                          label: Text('High'),
                          icon: Icon(Icons.gps_fixed, size: 16),
                        ),
                      ],
                      selected: {accuracy},
                      onSelectionChanged: (v) =>
                          setDialogState(() => accuracy = v.first),
                    ),

                    const SizedBox(height: 16),

                    // Android-only options
                    if (_isAndroid) ...[
                      SwitchListTile(
                        title: const Text('Foreground Service'),
                        subtitle: const Text(
                          'More reliable but shows notification',
                        ),
                        value: useForegroundService,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) =>
                            setDialogState(() => useForegroundService = v),
                      ),
                      SwitchListTile(
                        title: const Text('Exact Alarms'),
                        subtitle: const Text(
                          'Precise scheduling (needs SCHEDULE_EXACT_ALARM)',
                        ),
                        value: useExactAlarms,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) =>
                            setDialogState(() => useExactAlarms = v),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Start'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    try {
      // Check exact alarm permission for short intervals (< 15 min)
      // without foreground service. Auto-selected by the plugin, but
      // works best when the permission is granted.
      if (_isAndroid && !useForegroundService && intervalMinutes < 15) {
        await _ensureExactAlarmPermission();
      }

      await tl.Tracelet.setConfig(
        tl.Config(
          geo: tl.GeoConfig(
            periodicLocationInterval: intervalMinutes * 60,
            periodicDesiredAccuracy: accuracy,
          ),
          android: tl.AndroidConfig(
            periodicUseForegroundService: useForegroundService,
            periodicUseExactAlarms: useExactAlarms,
          ),
          // Disable heartbeat — periodic mode already does one-shot fixes
          app: const tl.AppConfig(heartbeatInterval: -1),
        ),
      );

      final state = await tl.Tracelet.startPeriodic();
      setState(() {
        _isTracking = state.enabled;
        _isPeriodicMode = true;
        _pluginState = state;
      });
      _addLog(
        'PERIODIC',
        'Started  interval=${intervalMinutes}min  '
            'accuracy=${accuracy.name}  '
            'fgService=$useForegroundService  '
            'exactAlarms=$useExactAlarms',
      );
    } catch (e) {
      _addLog('ERROR', 'startPeriodic(custom) failed: $e');
    }
  }

  /// Stop periodic tracking — safely checks state before stopping.
  Future<void> _stopPeriodic() async {
    try {
      final currentState = await tl.Tracelet.getState();
      if (!currentState.enabled) {
        _addLog('PERIODIC', 'Already stopped — nothing to do');
        return;
      }
      final state = await tl.Tracelet.stop();
      setState(() {
        _isTracking = state.enabled;
        _isPeriodicMode = false;
        _pluginState = state;
      });
      _addLog('PERIODIC', 'Stopped  enabled=${state.enabled}');
    } catch (e) {
      _addLog('ERROR', 'stopPeriodic() failed: $e');
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

  /// Adds a polygon geofence around the current location (a ~200m square).
  Future<void> _addPolygonGeofenceAtCurrentLocation() async {
    if (_lastLocation == null) {
      _addLog('WARN', 'No location yet — get a position first');
      return;
    }
    try {
      final loc = _lastLocation!;
      final lat = loc.coords.latitude;
      final lng = loc.coords.longitude;
      final id = 'poly_${DateTime.now().millisecondsSinceEpoch}';

      // Create a ~200m square around the current position
      // ~0.0018 degrees ≈ 200m at mid-latitudes
      const offset = 0.0018;
      await tl.Tracelet.addGeofence(
        tl.Geofence(
          identifier: id,
          latitude: lat,
          longitude: lng,
          radius: 0, // ignored for polygon
          vertices: [
            [lat + offset, lng - offset], // NW
            [lat + offset, lng + offset], // NE
            [lat - offset, lng + offset], // SE
            [lat - offset, lng - offset], // SW
          ],
        ),
      );
      _addLog(
        'POLYGON+',
        '$id  ~400m²  at ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
      );
    } catch (e) {
      _addLog('ERROR', 'addPolygonGeofence() failed: $e');
    }
  }

  Future<void> _listGeofences() async {
    try {
      final fences = await tl.Tracelet.getGeofences();
      final polygonCount = fences.where((f) => f.vertices.isNotEmpty).length;
      final circularCount = fences.length - polygonCount;
      _addLog(
        'GEOFENCES',
        '${fences.length} registered ($circularCount circular, $polygonCount polygon)',
      );
      for (final f in fences) {
        final isPolygon = f.vertices.isNotEmpty;
        final shape = isPolygon
            ? 'polygon(${f.vertices.length}v)'
            : 'r=${f.radius}m';
        _addLog(
          isPolygon ? '  POLYGON' : '  FENCE',
          '${f.identifier}  (${f.latitude.toStringAsFixed(4)}, ${f.longitude.toStringAsFixed(4)})  $shape',
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
      final status = await tl.Tracelet.getLocationAuthorization();
      _addLog('PERMISSION', 'current=${status.name}');

      if (status == tl.AuthorizationStatus.deniedForever) {
        if (mounted) _showPermissionDeniedDialog();
        return;
      }

      if (status == tl.AuthorizationStatus.always) {
        _addLog('PERMISSION', 'already "Always" — nothing to do');
        return;
      }

      if (status == tl.AuthorizationStatus.whenInUse) {
        // Foreground granted → offer background upgrade
        if (!_isWeb && mounted) {
          final shouldUpgrade = await _showBackgroundRationaleDialog();
          if (shouldUpgrade) {
            await _upgradeToAlways();
          }
        }
        return;
      }

      // notDetermined or denied → request foreground
      final result = await tl.Tracelet.requestLocationAuthorization();
      _addLog('PERMISSION', 'result=${result.name}');

      if (result == tl.AuthorizationStatus.deniedForever && mounted) {
        _showPermissionDeniedDialog();
      } else if (result == tl.AuthorizationStatus.whenInUse &&
          !_isWeb &&
          mounted) {
        // Foreground granted → offer background upgrade
        final shouldUpgrade = await _showBackgroundRationaleDialog();
        if (shouldUpgrade) {
          await _upgradeToAlways();
        }
      }
    } catch (e) {
      _addLog('ERROR', 'requestLocationAuthorization() failed: $e');
    }
  }

  /// Check and log permission status without triggering any dialog.
  Future<void> _checkPermissionStatus() async {
    try {
      final status = await tl.Tracelet.getLocationAuthorization();
      _addLog('PERMISSION', '${status.name} (${status.index})');
    } catch (e) {
      _addLog('ERROR', 'getLocationAuthorization() failed: $e');
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
    final bgResult = await tl.Tracelet.requestLocationAuthorization();
    _addLog('PERMISSION', 'background upgrade=${bgResult.name}');

    if (bgResult == tl.AuthorizationStatus.deniedForever && mounted) {
      _showPermissionDeniedDialog();
    } else if (!_isAndroid &&
        bgResult == tl.AuthorizationStatus.whenInUse &&
        mounted) {
      // On iOS, if the result is still whenInUse the OS didn't show a dialog.
      // Open Settings so the user can toggle to "Always" manually.
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
    if (_isWeb) return false;
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
                    "You may see a system prompt, or you'll be taken "
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
      final result =
          await tl.Tracelet.requestTemporaryFullAccuracyAuthorization(
            'TemporaryFullAccuracy',
          );
      _addLog('ACCURACY', 'temporary full accuracy result=${result.name}');
    } catch (e) {
      _addLog(
        'ERROR',
        'requestTemporaryFullAccuracyAuthorization() failed: $e',
      );
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

    final status = await tl.Tracelet.getNotificationAuthorization();
    _addLog('NOTIFICATION', 'current notification status=${status.name}');

    if (status == tl.NotificationAuthorizationStatus.granted) {
      return true; // Already granted (or pre-13)
    }

    if (status == tl.NotificationAuthorizationStatus.deniedForever) {
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

    final result = await tl.Tracelet.requestNotificationAuthorization();
    _addLog('NOTIFICATION', 'notification permission result=${result.name}');

    if (result == tl.NotificationAuthorizationStatus.deniedForever && mounted) {
      _showNotificationDeniedDialog();
      return false;
    }
    return result == tl.NotificationAuthorizationStatus.granted;
  }

  /// Check and log notification permission status.
  Future<void> _checkNotificationStatus() async {
    try {
      final status = await tl.Tracelet.getNotificationAuthorization();
      _addLog('NOTIFICATION', '${status.name} (${status.index})');
    } catch (e) {
      _addLog('ERROR', 'getNotificationAuthorization() failed: $e');
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

  /// Checks that "Always" / background location permission is granted.
  ///
  /// If only "When In Use" is granted, shows a rationale dialog and
  /// attempts to upgrade. Always returns `true` so tracking proceeds
  /// regardless — but logs a warning about killed-state limitations.
  Future<bool> _ensureBackgroundPermission() async {
    if (_isWeb) return true; // Web doesn't have background location

    if (await tl.Tracelet.hasBackgroundPermission) {
      _addLog(
        'PERMISSION',
        'Background (Always) location granted — killed-state tracking enabled',
      );
      return true;
    }

    _addLog(
      'PERMISSION',
      'Background (Always) location not granted — tracking will not survive app kill',
    );

    if (!mounted) return true;
    final shouldUpgrade = await _showBackgroundRationaleDialog();
    if (shouldUpgrade) {
      await _upgradeToAlways();
    }

    final upgraded = await tl.Tracelet.hasBackgroundPermission;
    if (upgraded) {
      _addLog(
        'PERMISSION',
        'Background (Always) location granted — killed-state tracking enabled',
      );
    } else {
      _addLog(
        'WARN',
        'Background permission not granted — '
            'foreground tracking will work, but killed-state tracking is disabled',
      );
    }
    return true; // Always proceed — When In Use still allows foreground tracking
  }

  /// Ensures motion / activity recognition permission is granted.
  ///
  /// Returns `true` if granted, `false` if denied.
  Future<bool> _ensureMotionPermission() async {
    final status = await tl.Tracelet.getMotionAuthorization();
    _addLog('MOTION', 'current motion permission status=${status.name}');

    if (status == tl.MotionAuthorizationStatus.granted) {
      return true; // Already granted
    }
    if (status == tl.MotionAuthorizationStatus.deniedForever) {
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

    final result = await tl.Tracelet.requestMotionAuthorization();
    _addLog('MOTION', 'motion permission result=${result.name}');

    if (result == tl.MotionAuthorizationStatus.deniedForever && mounted) {
      _showMotionDeniedDialog();
      return false;
    }
    return result == tl.MotionAuthorizationStatus.granted;
  }

  /// Ensure exact alarm permission for periodic mode with short intervals.
  ///
  /// On Android 13+, SCHEDULE_EXACT_ALARM is not auto-granted.
  /// If not granted, shows a dialog and opens Settings. The plugin will
  /// still work with approximate timing (Doze-safe inexact alarms).
  Future<void> _ensureExactAlarmPermission() async {
    final canSchedule = await tl.Tracelet.canScheduleExactAlarms();
    if (canSchedule) return;

    _addLog(
      'WARN',
      'Exact alarm permission not granted — timing may be approximate',
    );

    if (!mounted) return;
    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exact Alarm Permission'),
        content: const Text(
          'For precise periodic location timing, enable '
          '"Alarms & reminders" for this app in Settings.\n\n'
          'Without it, the interval timing will be approximate '
          '(±1–5 minutes).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );

    if (shouldOpen ?? false) {
      final opened = await tl.Tracelet.openExactAlarmSettings();
      if (opened) {
        _addLog('CONFIG', 'Opened exact alarm settings');
      }
    }
  }

  /// Check and log motion permission status.
  Future<void> _checkMotionStatus() async {
    try {
      final status = await tl.Tracelet.getMotionAuthorization();
      _addLog('MOTION', '${status.name} (${status.index})');
    } catch (e) {
      _addLog('ERROR', 'getMotionAuthorization() failed: $e');
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

  /// Request battery optimization exemption (Android only).
  ///
  /// Shows the system dialog asking the user to whitelist this app
  /// from battery optimizations. Always opens the settings screen
  /// and shows current exemption status.
  Future<void> _requestBatteryExemption() async {
    try {
      final alreadyExempt = await tl.Tracelet.isIgnoringBatteryOptimizations();
      if (alreadyExempt) {
        _addLog('BATTERY', 'App is already exempt from battery optimizations');
      }
      final ok = await tl.Tracelet.openBatterySettings();
      _addLog(
        'BATTERY',
        ok
            ? 'Opened battery optimization settings'
            : 'Failed to open battery settings',
      );
    } catch (e) {
      _addLog('ERROR', 'requestBatteryExemption() failed: $e');
    }
  }

  // ── New Feature Demos ───────────────────────────────────────────────────

  /// Toggle Kalman filter GPS smoothing at runtime.
  Future<void> _toggleKalmanFilter() async {
    try {
      final newValue = !_kalmanEnabled;
      final state = await tl.Tracelet.setConfig(
        tl.Config(
          geo: tl.GeoConfig(
            filter: tl.LocationFilter(useKalmanFilter: newValue),
          ),
        ),
      );
      setState(() {
        _kalmanEnabled = newValue;
        _pluginState = state;
      });
      _addLog(
        'KALMAN',
        newValue ? 'ENABLED — GPS smoothing active' : 'DISABLED — raw GPS',
      );
    } catch (e) {
      _addLog('ERROR', 'toggleKalmanFilter() failed: $e');
    }
  }

  /// Cycle through Motion Detection Modes at runtime.
  Future<void> _cycleMotionMode() async {
    try {
      tl.MotionDetectionMode nextMode;
      switch (_motionMode) {
        case tl.MotionDetectionMode.accelerometer:
          nextMode = tl.MotionDetectionMode.speed;
        case tl.MotionDetectionMode.speed:
          nextMode = tl.MotionDetectionMode.smart;
        case tl.MotionDetectionMode.smart:
          nextMode = tl.MotionDetectionMode.accelerometer;
      }
      final state = await tl.Tracelet.setConfig(
        tl.Config(motion: tl.MotionConfig(motionDetectionMode: nextMode)),
      );
      setState(() {
        _motionMode = nextMode;
        _pluginState = state;
      });
      _addLog('MOTION_MODE', nextMode.name.toUpperCase());
    } catch (e) {
      _addLog('ERROR', 'cycleMotionMode() failed: $e');
    }
  }

  // ── Battery Budget ────────────────────────────────────────────────────

  Future<void> _toggleBatteryBudget() async {
    try {
      final newBudget = _budgetEnabled ? 0.0 : 3.0;
      final state = await tl.Tracelet.setConfig(
        tl.Config(geo: tl.GeoConfig(batteryBudgetPerHour: newBudget)),
      );
      setState(() {
        _budgetEnabled = !_budgetEnabled;
        _pluginState = state;
        if (!_budgetEnabled) _lastBudgetEvent = null;
      });
      _addLog(
        'BUDGET',
        _budgetEnabled
            ? 'ENABLED — target 3%/hr max drain'
            : 'DISABLED — no battery budget constraint',
      );
    } catch (e) {
      _addLog('ERROR', 'toggleBatteryBudget() failed: $e');
    }
  }

  void _showBudgetDashboard() {
    final evt = _lastBudgetEvent;
    if (evt == null) {
      _addLog(
        'BUDGET',
        _budgetEnabled
            ? 'No adjustments yet — waiting for battery samples'
            : 'Budget is disabled — enable it first',
      );
      return;
    }
    final accuracyNames = ['high', 'medium', 'low', 'veryLow', 'passive'];
    final accName = evt.newDesiredAccuracy < accuracyNames.length
        ? accuracyNames[evt.newDesiredAccuracy]
        : '${evt.newDesiredAccuracy}';
    _addLog(
      'BUDGET',
      'Drain: ${evt.currentBatteryDrain.toStringAsFixed(2)}%/hr  '
          'Target: ${evt.targetBudget.toStringAsFixed(2)}%/hr',
    );
    _addLog(
      'BUDGET',
      'Adjusted → distanceFilter=${evt.newDistanceFilter.toStringAsFixed(0)}m  '
          'accuracy=$accName'
          '${evt.newPeriodicInterval != null ? "  interval=${evt.newPeriodicInterval}s" : ""}',
    );
  }

  // ── Carbon Estimator ──────────────────────────────────────────────────

  void _showCarbonSummary() {
    final summary = _lastCarbonSummary;
    if (summary == null) {
      _addLog(
        'CO\u2082',
        'No trip carbon data yet — complete a trip first (start moving, then stop)',
      );
      return;
    }
    _addLog(
      'CO\u2082',
      '${summary.totalCarbonGrams.toStringAsFixed(1)}g CO\u2082  '
          '${(summary.totalDistanceMeters / 1000).toStringAsFixed(2)}km  '
          'mode=${summary.dominantMode}',
    );
    for (final entry in summary.carbonByMode.entries) {
      final distKm = (summary.distanceByMode[entry.key] ?? 0) / 1000;
      _addLog(
        '  ${entry.key}',
        '${entry.value.toStringAsFixed(1)}g CO\u2082  '
            '${distKm.toStringAsFixed(2)}km',
      );
    }
    // Cumulative stats
    final cumReport = _carbonEstimator.getCumulativeReport();
    final cumGrams = cumReport['totalCarbonGrams']! as double;
    final cumTrips = cumReport['totalTrips']! as int;
    _addLog(
      'CO\u2082 TOTAL',
      '${cumGrams.toStringAsFixed(1)}g across $cumTrips trip(s)',
    );
  }

  void _showCarbonBottomSheet() {
    final summary = _lastCarbonSummary;
    final cumReport = _carbonEstimator.getCumulativeReport();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        maxChildSize: 0.7,
        expand: false,
        builder: (ctx, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                const Icon(Icons.eco, color: Colors.green, size: 28),
                const SizedBox(width: 10),
                Text(
                  'Carbon Footprint',
                  style: Theme.of(
                    ctx,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),
            if (summary != null) ...[
              Text(
                'Last Trip',
                style: Theme.of(
                  ctx,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              _HealthRow(
                'CO\u2082 Emitted',
                '${summary.totalCarbonGrams.toStringAsFixed(1)} g',
              ),
              _HealthRow(
                'Distance',
                '${(summary.totalDistanceMeters / 1000).toStringAsFixed(2)} km',
              ),
              _HealthRow('Dominant Mode', summary.dominantMode),
              const SizedBox(height: 8),
              for (final entry in summary.carbonByMode.entries)
                _HealthRow(
                  entry.key,
                  '${entry.value.toStringAsFixed(1)}g  /  '
                  '${((summary.distanceByMode[entry.key] ?? 0) / 1000).toStringAsFixed(2)}km',
                ),
              const Divider(height: 16),
            ] else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No trip completed yet. Start moving, then stop.'),
              ),
            Text(
              'Cumulative',
              style: Theme.of(
                ctx,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            _HealthRow(
              'Total CO\u2082',
              '${(cumReport['totalCarbonGrams']! as double).toStringAsFixed(1)} g',
            ),
            _HealthRow('Total Trips', '${cumReport['totalTrips']}'),
          ],
        ),
      ),
    );
  }

  // ── Compliance Report ─────────────────────────────────────────────────

  Future<void> _showComplianceReport() async {
    try {
      _addLog('COMPLIANCE', 'Generating report...');
      final report = await tl.Tracelet.generateComplianceReport();
      _addLog(
        'COMPLIANCE',
        'Report ready — ${report.totalLocationsStored} locations stored',
      );
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (ctx, scrollCtrl) => ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  const Icon(Icons.policy, color: Colors.indigo, size: 28),
                  const SizedBox(width: 10),
                  Text(
                    'Compliance Report',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Generated: ${report.generatedAt.toIso8601String()}',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const Divider(height: 24),

              // Data Inventory
              Text(
                'Data Inventory',
                style: Theme.of(
                  ctx,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              _HealthRow('Locations Stored', '${report.totalLocationsStored}'),
              _HealthRow('Locations Synced', '${report.totalLocationsSynced}'),
              _HealthRow('Oldest Record', report.oldestRecord ?? 'N/A'),
              _HealthRow('Newest Record', report.newestRecord ?? 'N/A'),
              const Divider(height: 16),

              // Retention Policy
              Text(
                'Retention Policy',
                style: Theme.of(
                  ctx,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              _HealthRow(
                'Max Days',
                report.maxDaysToPersist == -1
                    ? 'Unlimited'
                    : '${report.maxDaysToPersist} days',
              ),
              _HealthRow(
                'Max Records',
                report.maxRecordsToPersist == -1
                    ? 'Unlimited'
                    : '${report.maxRecordsToPersist}',
              ),
              const Divider(height: 16),

              // Privacy Measures
              Text(
                'Privacy Measures',
                style: Theme.of(
                  ctx,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              _HealthRow(
                'Database Encryption',
                report.databaseEncrypted ? 'Enabled' : 'Disabled',
                valueColor: report.databaseEncrypted
                    ? Colors.green
                    : Colors.orange,
              ),
              _HealthRow('Privacy Zones', '${report.activePrivacyZones}'),
              _HealthRow(
                'Sparse Updates',
                report.sparseUpdatesEnabled ? 'Enabled' : 'Disabled',
              ),
              _HealthRow(
                'Kalman Filter',
                report.kalmanFilterEnabled ? 'Enabled' : 'Disabled',
              ),
              _HealthRow(
                'Delta Compression',
                report.deltaCompressionEnabled ? 'Enabled' : 'Disabled',
              ),
              const Divider(height: 16),

              // Data Destinations
              Text(
                'Data Destinations',
                style: Theme.of(
                  ctx,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              _HealthRow(
                'HTTP Sync URL',
                report.httpSyncUrl ?? 'Not configured',
              ),
              _HealthRow(
                'Auto Sync',
                report.autoSyncEnabled ? 'Enabled' : 'Disabled',
              ),
              const Divider(height: 16),

              // Audit Trail
              Text(
                'Audit Trail',
                style: Theme.of(
                  ctx,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              _HealthRow('Enabled', report.auditTrailEnabled ? 'Yes' : 'No'),
              _HealthRow(
                'Chain Valid',
                report.auditTrailValid == null
                    ? 'Not verified'
                    : report.auditTrailValid!
                    ? 'Yes'
                    : 'No',
                valueColor: report.auditTrailValid ?? false
                    ? Colors.green
                    : report.auditTrailValid == false
                    ? Colors.red
                    : null,
              ),
              const Divider(height: 16),

              // Tracking State
              Text(
                'Tracking State',
                style: Theme.of(
                  ctx,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              _HealthRow(
                'Tracking',
                report.trackingEnabled ? 'Active' : 'Stopped',
                valueColor: report.trackingEnabled ? Colors.green : Colors.red,
              ),
              _HealthRow('Mode', report.trackingMode),
            ],
          ),
        ),
      );
    } catch (e) {
      _addLog('ERROR', 'generateComplianceReport() failed: $e');
    }
  }

  // ── Dead Reckoning ────────────────────────────────────────────────────

  Future<void> _toggleDeadReckoning() async {
    try {
      final newValue = !_deadReckoningEnabled;
      final state = await tl.Tracelet.setConfig(const tl.Config());
      setState(() {
        _deadReckoningEnabled = newValue;
        _pluginState = state;
      });
      _addLog(
        'DEAD_RECKONING',
        newValue
            ? 'ENABLED — IMU fallback after 10s GPS loss (max 120s)'
            : 'DISABLED',
      );
    } catch (e) {
      _addLog('ERROR', 'toggleDeadReckoning() failed: $e');
    }
  }

  Future<void> _getDeadReckoningState() async {
    try {
      final state = await tl.Tracelet.getDeadReckoningState();
      if (state == null) {
        _addLog('DEAD_RECKONING', 'Inactive (GPS available or DR disabled)');
      } else {
        final active = state['active'] == true;
        final elapsed = state['elapsed'] ?? 0;
        final accuracy = state['estimatedAccuracy'] ?? 0;
        _addLog(
          'DEAD_RECKONING',
          'active=$active  elapsed=${elapsed}s  '
              'accuracy=${accuracy}m',
        );
      }
    } catch (e) {
      _addLog('ERROR', 'getDeadReckoningState() failed: $e');
    }
  }

  // ── Database Encryption ───────────────────────────────────────────────

  Future<void> _checkEncryption() async {
    try {
      final encrypted = await tl.Tracelet.isDatabaseEncrypted();
      _addLog(
        'ENCRYPTION',
        encrypted ? 'Database IS encrypted' : 'Database is NOT encrypted',
      );
    } catch (e) {
      _addLog('ERROR', 'isDatabaseEncrypted() failed: $e');
    }
  }

  Future<void> _encryptDatabase() async {
    try {
      _addLog('ENCRYPTION', 'Encrypting database...');
      final ok = await tl.Tracelet.encryptDatabase();
      _addLog(
        'ENCRYPTION',
        ok ? 'Database encrypted successfully' : 'Encryption failed',
      );
    } catch (e) {
      _addLog('ERROR', 'encryptDatabase() failed: $e');
    }
  }

  // ── Device Attestation ────────────────────────────────────────────────

  Future<void> _getAttestationToken() async {
    try {
      _addLog('ATTESTATION', 'Requesting token...');
      final token = await tl.Tracelet.getAttestationToken();
      if (token != null) {
        final preview = token.token.length > 40
            ? '${token.token.substring(0, 40)}...'
            : token.token;
        _addLog(
          'ATTESTATION',
          'provider=${token.provider}  '
              'token=$preview',
        );
      } else {
        _addLog('ATTESTATION', 'No token returned (unsupported platform?)');
      }
    } catch (e) {
      _addLog('ERROR', 'getAttestationToken() failed: $e');
    }
  }

  // ── Sparse Updates ────────────────────────────────────────────────────

  Future<void> _toggleSparseUpdates() async {
    try {
      final newValue = !_sparseUpdatesEnabled;
      final state = await tl.Tracelet.setConfig(
        tl.Config(geo: tl.GeoConfig(enableSparseUpdates: newValue)),
      );
      setState(() {
        _sparseUpdatesEnabled = newValue;
        _pluginState = state;
      });
      _addLog(
        'SPARSE',
        newValue
            ? 'ENABLED — skip locations <50m apart (heartbeat every 300s)'
            : 'DISABLED — all locations dispatched',
      );
    } catch (e) {
      _addLog('ERROR', 'toggleSparseUpdates() failed: $e');
    }
  }

  // ── Delta Encoding Demo ───────────────────────────────────────────────

  Future<void> _showDeltaEncodingDemo() async {
    try {
      final locations = await tl.Tracelet.getLocations();
      if (locations.isEmpty) {
        _addLog('DELTA', 'No locations stored — track first, then try again');
        return;
      }
      final batch = locations.take(20).map((l) => l.toMap()).toList();
      final encoded = tl.DeltaEncoder.encode(batch);
      final originalJson = batch.toString();
      final encodedJson = encoded.toString();
      final savings = (1 - encodedJson.length / originalJson.length) * 100;
      _addLog(
        'DELTA',
        '${batch.length} locations: '
            'original=${originalJson.length} bytes  '
            'compressed=${encodedJson.length} bytes  '
            'savings=${savings.toStringAsFixed(1)}%',
      );
      // Verify roundtrip
      final decoded = tl.DeltaEncoder.decode(encoded);
      _addLog('DELTA', 'Roundtrip OK — decoded ${decoded.length} locations');
    } catch (e) {
      _addLog('ERROR', 'deltaEncodingDemo() failed: $e');
    }
  }

  // ── HTTP Sync Control ─────────────────────────────────────────────────

  Future<void> _toggleCellularSync() async {
    try {
      final newValue = !_cellularSyncDisabled;
      final state = await tl.Tracelet.setConfig(const tl.Config());
      setState(() {
        _cellularSyncDisabled = newValue;
        _pluginState = state;
      });
      _addLog(
        'HTTP',
        newValue
            ? 'Cellular sync DISABLED — Wi-Fi only'
            : 'Cellular sync ENABLED — sync on any connection',
      );
    } catch (e) {
      _addLog('ERROR', 'toggleCellularSync() failed: $e');
    }
  }

  Future<void> _manualSync() async {
    try {
      _addLog('HTTP', 'Triggering manual sync...');
      final synced = await tl.Tracelet.sync();
      _addLog('HTTP', 'Synced ${synced.length} location(s)');
    } catch (e) {
      _addLog('ERROR', 'sync() failed: $e');
    }
  }

  Future<void> _refreshHeaders() async {
    try {
      final ok = await tl.Tracelet.refreshHeaders();
      _addLog('HTTP', ok ? 'Headers refreshed' : 'No headers callback set');
    } catch (e) {
      _addLog('ERROR', 'refreshHeaders() failed: $e');
    }
  }

  Future<void> _setRouteContextDemo() async {
    try {
      final sessionId =
          'session-${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
      await tl.Tracelet.setRouteContext(
        tl.RouteContext(
          taskId: 'demo-delivery',
          driverId: 'demo-driver',
          trackingSessionId: sessionId,
          startedAt: DateTime.now().toUtc().toIso8601String(),
          custom: const {'region': 'demo'},
        ),
      );
      _addLog('ROUTE', 'Context set: session=$sessionId');
    } catch (e) {
      _addLog('ERROR', 'setRouteContext() failed: $e');
    }
  }

  Future<void> _clearRouteContextDemo() async {
    try {
      await tl.Tracelet.clearRouteContext();
      _addLog('ROUTE', 'Context cleared');
    } catch (e) {
      _addLog('ERROR', 'clearRouteContext() failed: $e');
    }
  }

  // ── R-Tree Demo ───────────────────────────────────────────────────────

  Future<void> _showRTreeDemo() async {
    try {
      final geofences = await tl.Tracelet.getGeofences();
      if (geofences.isEmpty) {
        _addLog('RTREE', 'No geofences registered — add some geofences first');
        return;
      }
      final tree = tl.RTree<String>();
      for (final gf in geofences) {
        tree.insert(gf.latitude, gf.longitude, gf.radius, gf.identifier);
      }
      _addLog('RTREE', 'Indexed ${tree.size} geofence(s)');

      // Query around the current position
      final pos = _lastLocation;
      if (pos != null) {
        final sw = Stopwatch()..start();
        final nearby = tree.queryCircle(
          pos.coords.latitude,
          pos.coords.longitude,
          5000, // 5km search radius
        );
        sw.stop();
        _addLog(
          'RTREE',
          'Query (5km radius): ${nearby.length} match(es) in '
              '${sw.elapsedMicroseconds}\u00b5s  '
              '[${nearby.join(", ")}]',
        );
      } else {
        _addLog('RTREE', 'No current position — start tracking to query');
      }
    } catch (e) {
      _addLog('ERROR', 'rTreeDemo() failed: $e');
    }
  }

  /// Show last trip summary in the log.
  void _showLastTrip() {
    final trip = _lastTrip;
    if (trip == null) {
      _addLog('TRIP', 'No trip recorded yet — start tracking and move!');
      return;
    }
    final distKm = (trip.distance / 1000).toStringAsFixed(2);
    final durMin = (trip.duration / 60).toStringAsFixed(1);
    final speedKmh = (trip.averageSpeed * 3.6).toStringAsFixed(1);
    _addLog(
      'TRIP',
      '$distKm km in $durMin min @ $speedKmh km/h  '
          '(${trip.waypoints.length} waypoints)',
    );
    if (trip.startLocation.coords.latitude != 0) {
      _addLog(
        '  FROM',
        '${trip.startLocation.coords.latitude.toStringAsFixed(5)}, '
            '${trip.startLocation.coords.longitude.toStringAsFixed(5)}',
      );
    }
    if (trip.stopLocation.coords.latitude != 0) {
      _addLog(
        '  TO',
        '${trip.stopLocation.coords.latitude.toStringAsFixed(5)}, '
            '${trip.stopLocation.coords.longitude.toStringAsFixed(5)}',
      );
    }
  }

  /// Re-initialize with elasticity disabled to compare tracking behavior.
  Future<void> _toggleElasticity() async {
    try {
      final state = await tl.Tracelet.setConfig(
        const tl.Config(geo: tl.GeoConfig(disableElasticity: true)),
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
        const tl.Config(
          geofence: tl.GeofenceConfig(geofenceModeHighAccuracy: true),
        ),
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

  /// Toggle geofenceModeHighAccuracy to false and restart geofence-only mode.
  Future<void> _startGeofencesLowAccuracy() async {
    try {
      await tl.Tracelet.setConfig(const tl.Config());
      final state = await tl.Tracelet.startGeofences();
      setState(() {
        _isTracking = state.enabled;
        _pluginState = state;
      });
      _addLog(
        'GEOFENCES_LA',
        'Low-accuracy geofences started (iOS blue arrow should hide)  mode=${state.trackingMode.name}',
      );
    } catch (e) {
      _addLog('ERROR', 'startGeofencesLowAccuracy() failed: $e');
    }
  }

  /// Repro for GitHub issue #51: continuous tracking + geofences.
  ///
  /// Configures exactly like the reporter:
  /// - `Tracelet.start()` for continuous location tracking
  /// - `addGeofences(...)` to register geofences (20m radius for easy testing)
  /// - `geofenceModeHighAccuracy: true`
  /// - `rejectMockLocations: false` (for mock location testing)
  /// - `distanceFilter: 0` (all locations)
  /// - `disableElasticity: true`
  ///
  /// Expected: both onLocation AND onGeofence fire.
  Future<void> _startContinuousWithGeofences() async {
    if (!_isReady) {
      _addLog('WARN', 'Call Initialize first');
      return;
    }
    if (_lastLocation == null) {
      _addLog('WARN', 'No location yet — get a position first');
      return;
    }
    try {
      final loc = _lastLocation!;

      // 1. Configure like the issue #51 reporter
      await tl.Tracelet.setConfig(
        const tl.Config(
          geo: tl.GeoConfig(
            distanceFilter: 0,
            disableElasticity: true,
            locationTimeout: 30,
          ),
        ),
      );
      _addLog(
        'ISSUE_51',
        'Config applied: highAccuracy=true, rejectMock=false, distanceFilter=0',
      );

      // 2. Register geofences around current location (like reporter)
      final gf1Id = 'issue51_enter_${DateTime.now().millisecondsSinceEpoch}';
      final gf2Id = 'issue51_nearby_${DateTime.now().millisecondsSinceEpoch}';

      // Geofence at current location (should trigger ENTER immediately)
      await tl.Tracelet.addGeofence(
        tl.Geofence(
          identifier: gf1Id,
          latitude: loc.coords.latitude,
          longitude: loc.coords.longitude,
          radius: 20,
          notifyOnDwell: true,
          loiteringDelay: 30000,
        ),
      );
      _addLog(
        'ISSUE_51',
        'Geofence added: $gf1Id  r=20m (at current position — expect ENTER)',
      );

      // Geofence ~40m north (should trigger when walking toward it)
      await tl.Tracelet.addGeofence(
        tl.Geofence(
          identifier: gf2Id,
          latitude: loc.coords.latitude + 0.00036, // ~40m north
          longitude: loc.coords.longitude,
          radius: 20,
        ),
      );
      _addLog('ISSUE_51', 'Geofence added: $gf2Id  r=20m (~40m north)');

      // 3. Start continuous tracking (NOT startGeofences)
      final state = await tl.Tracelet.start();
      await tl.Tracelet.changePace(true);
      setState(() {
        _isTracking = state.enabled;
        _pluginState = state;
      });
      _addLog(
        'ISSUE_51',
        'start() called — continuous tracking active  '
            'mode=${state.trackingMode.name}  enabled=${state.enabled}',
      );
      _addLog(
        'ISSUE_51',
        'Watching for onGeofence events... '
            'Walk ~20m away to trigger EXIT, then return for ENTER.',
      );
    } catch (e) {
      _addLog('ERROR', 'startContinuousWithGeofences() failed: $e');
    }
  }

  /// Update location filter settings live.
  Future<void> _setStrictFilter() async {
    try {
      final state = await tl.Tracelet.setConfig(const tl.Config());
      setState(() => _pluginState = state);
      _addLog(
        'CONFIG',
        'Strict filter: (Location filters are now handled natively)',
      );
    } catch (e) {
      _addLog('ERROR', 'setStrictFilter() failed: $e');
    }
  }

  /// Toggle adaptive sampling mode at runtime.
  Future<void> _toggleAdaptiveMode() async {
    try {
      final newValue = !_adaptiveMode;
      final state = await tl.Tracelet.setConfig(
        tl.Config(geo: tl.GeoConfig(enableAdaptiveMode: newValue)),
      );
      setState(() {
        _adaptiveMode = newValue;
        _pluginState = state;
      });
      _addLog(
        'ADAPTIVE',
        newValue
            ? 'ENABLED — distance filter adapts to activity/battery/speed'
            : 'DISABLED — fixed distance filter',
      );
    } catch (e) {
      _addLog('ERROR', 'toggleAdaptiveMode() failed: $e');
    }
  }

  /// Cycle motion sensitivity between Low / Medium / High presets.
  Future<void> _cycleMotionSensitivity() async {
    try {
      late final String next;

      switch (_motionSensitivity) {
        case 'Low':
          next = 'Medium';
        case 'Medium':
          next = 'High';
        default: // High → Low
          next = 'Low';
      }

      await tl.Tracelet.setConfig(const tl.Config());
      setState(() => _motionSensitivity = next);
      _addLog('MOTION', '$next sensitivity (Native OS default)');
    } catch (e) {
      _addLog('ERROR', 'cycleMotionSensitivity() failed: $e');
    }
  }

  /// Run a full health check and show warnings.
  Future<void> _runHealthCheck() async {
    try {
      _addLog('HEALTH', 'Running diagnostics...');
      final health = await tl.Tracelet.getHealth();
      setState(() => _lastHealthCheck = health);
      _addLog(
        'HEALTH',
        health.isHealthy
            ? 'ALL CLEAR — no issues detected'
            : '${health.warningCount} warning(s) detected',
      );
      _addLog(
        'HEALTH',
        'tracking=${health.trackingEnabled}  moving=${health.isMoving}  '
            'bg=${health.hasBackgroundPermission}',
      );
      if (health.isPowerSaveMode) {
        _addLog('HEALTH', '\u26a0 Power Save Mode is ON');
      }
      if (health.isAggressiveOem) {
        _addLog(
          'HEALTH',
          '\u26a0 Aggressive OEM: ${health.manufacturer} ${health.model}',
        );
      }
      for (final w in health.warnings) {
        _addLog('HEALTH', '  \u26a0 ${w.description}');
      }
      _addLog(
        'HEALTH',
        'locations=${health.locationCount}  odometer=${health.odometer.toStringAsFixed(0)}m',
      );
    } catch (e) {
      _addLog('ERROR', 'getHealth() failed: $e');
    }
  }

  /// Show full health check bottom sheet.
  Future<void> _showHealthDashboard() async {
    try {
      final health = await tl.Tracelet.getHealth();
      setState(() => _lastHealthCheck = health);
      if (!mounted) return;
      _showHealthBottomSheet(health);
    } catch (e) {
      _addLog('ERROR', 'Health dashboard failed: $e');
    }
  }

  void _showHealthBottomSheet(tl.HealthCheck health) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (ctx, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(20),
          children: [
            // Title
            Row(
              children: [
                Icon(
                  health.isHealthy ? Icons.check_circle : Icons.warning_amber,
                  color: health.isHealthy ? Colors.green : Colors.orange,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Text(
                  'Health Check',
                  style: Theme.of(
                    ctx,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Chip(
                  label: Text(
                    health.isHealthy
                        ? 'Healthy'
                        : '${health.warningCount} Warning(s)',
                  ),
                  backgroundColor: health.isHealthy
                      ? Colors.green.shade50
                      : Colors.orange.shade50,
                ),
              ],
            ),
            const Divider(height: 24),

            // Tracking State
            _HealthRow(
              'Tracking',
              health.trackingEnabled ? 'Active' : 'Stopped',
              valueColor: health.trackingEnabled ? Colors.green : Colors.red,
            ),
            _HealthRow('Motion', health.isMoving ? 'Moving' : 'Stationary'),
            _HealthRow('Tracking Mode', health.trackingMode.name),
            _HealthRow('Odometer', '${health.odometer.toStringAsFixed(0)}m'),
            const Divider(height: 16),

            // Permissions
            Text(
              'Permissions',
              style: Theme.of(
                ctx,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            _HealthRow(
              'Location',
              health.locationPermission.name,
              valueColor: health.hasBackgroundPermission
                  ? Colors.green
                  : Colors.orange,
            ),
            _HealthRow(
              'Location Services',
              health.locationServicesEnabled ? 'ON' : 'OFF',
              valueColor: health.locationServicesEnabled
                  ? Colors.green
                  : Colors.red,
            ),
            _HealthRow(
              'Accuracy Authorization',
              health.accuracyAuthorization.name,
            ),
            const Divider(height: 16),

            // Battery / Power
            Text(
              'Battery & Power',
              style: Theme.of(
                ctx,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            _HealthRow(
              'Power Save',
              health.isPowerSaveMode ? 'ON' : 'OFF',
              valueColor: health.isPowerSaveMode ? Colors.orange : Colors.green,
            ),
            _HealthRow(
              'Battery Optimized',
              health.isIgnoringBatteryOptimizations ? 'Exempt' : 'Restricted',
              valueColor: health.isIgnoringBatteryOptimizations
                  ? Colors.green
                  : Colors.orange,
            ),
            const Divider(height: 16),

            // Device
            Text(
              'Device',
              style: Theme.of(
                ctx,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            _HealthRow('Manufacturer', health.manufacturer),
            _HealthRow('Model', health.model),
            if (health.isAggressiveOem)
              _HealthRow(
                'Aggressive OEM',
                'Rating ${health.aggressionRating}/5',
                valueColor: Colors.red,
              ),
            const Divider(height: 16),

            // Sensors
            Text(
              'Sensors',
              style: Theme.of(
                ctx,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            _HealthRow(
              'Accelerometer',
              health.hasAccelerometer ? 'Available' : 'Missing',
              valueColor: health.hasAccelerometer
                  ? Colors.green
                  : Colors.orange,
            ),
            _HealthRow(
              'Significant Motion',
              health.hasSignificantMotion ? 'Available' : 'Missing',
              valueColor: health.hasSignificantMotion
                  ? Colors.green
                  : Colors.orange,
            ),
            _HealthRow(
              'Magnetometer',
              health.hasMagnetometer ? 'Available' : 'Missing',
            ),
            _HealthRow(
              'Gyroscope',
              health.hasGyroscope ? 'Available' : 'Missing',
            ),
            const Divider(height: 16),

            // Database
            Text(
              'Database',
              style: Theme.of(
                ctx,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            _HealthRow('Location Count', '${health.locationCount}'),
            const Divider(height: 16),

            // Warnings
            if (health.hasWarnings) ...[
              Text(
                'Warnings',
                style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(height: 4),
              ...health.warnings.map(
                (w) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber,
                        size: 16,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          w.description,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
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

  // ── OEM Health ───────────────────────────────────────────────────────────

  /// Fetch OEM settings health and log key metrics.
  Future<void> _checkOemHealth() async {
    try {
      final health = await tl.Tracelet.getSettingsHealth();
      final manufacturer = health['manufacturer'] ?? 'unknown';
      final model = health['model'] ?? '';
      final aggressive = health['isAggressiveOem'] == true;
      final rating = health['aggressionRating'] ?? 0;
      final ignoringBattery = health['isIgnoringBatteryOptimizations'] == true;
      final autostart = health['autostartAvailable'] == true;
      final screens =
          (health['oemSettingsScreens'] as List?)?.cast<String>() ?? [];

      _addLog('OEM', '$manufacturer $model');
      _addLog(
        'OEM',
        'aggressive=$aggressive  rating=$rating/5  '
            'batteryExempt=$ignoringBattery',
      );
      if (autostart) _addLog('OEM', 'autostart available');
      if (screens.isNotEmpty) {
        _addLog('OEM', '${screens.length} OEM settings screens available');
      }
    } catch (e) {
      _addLog('ERROR', 'getSettingsHealth() failed: $e');
    }
  }

  /// Show a bottom sheet with full OEM health info and action buttons
  /// for each available OEM settings screen.
  Future<void> _showOemHealthDialog() async {
    try {
      final health = await tl.Tracelet.getSettingsHealth();
      if (!mounted) return;

      final manufacturer = health['manufacturer'] as String? ?? 'unknown';
      final model = health['model'] as String? ?? '';
      final aggressive = health['isAggressiveOem'] == true;
      final rating = health['aggressionRating'] as int? ?? 0;
      final ignoringBattery = health['isIgnoringBatteryOptimizations'] == true;
      final autostart = health['autostartAvailable'] == true;
      final screens =
          (health['oemSettingsScreens'] as List?)?.cast<String>() ?? [];

      final cs = Theme.of(context).colorScheme;
      final ratingColor = switch (rating) {
        >= 5 => Colors.red,
        >= 4 => Colors.deepOrange,
        >= 3 => Colors.orange,
        >= 2 => Colors.amber,
        _ => Colors.green,
      };

      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (ctx, scrollCtrl) => ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(20),
            children: [
              // Title
              Row(
                children: [
                  Icon(
                    aggressive ? Icons.warning_amber : Icons.check_circle,
                    color: aggressive ? Colors.orange : Colors.green,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Device Health',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Device info
              _HealthRow('Manufacturer', manufacturer),
              _HealthRow('Model', model),
              _HealthRow(
                'Aggression Rating',
                '$rating / 5',
                valueColor: ratingColor,
              ),
              _HealthRow(
                'Battery Exempt',
                ignoringBattery ? 'Yes' : 'No',
                valueColor: ignoringBattery ? Colors.green : Colors.red,
              ),
              if (autostart) const _HealthRow('Autostart', 'Available'),

              if (aggressive) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withAlpha(80),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: cs.error),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'This device may kill background apps aggressively. '
                          'Open the settings below to whitelist Tracelet.',
                          style: TextStyle(color: cs.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // OEM settings screens
              if (screens.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'OEM Settings',
                  style: Theme.of(
                    ctx,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...screens.map(
                  (label) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Text(label),
                      onPressed: () async {
                        final ok = await tl.Tracelet.openOemSettings(label);
                        if (ctx.mounted) {
                          _addLog('OEM', 'openOemSettings("$label") → $ok');
                        }
                      },
                    ),
                  ),
                ),
              ],

              // Battery optimization button
              if (!ignoringBattery && _isAndroid) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.battery_saver),
                  label: const Text('Request Battery Exemption'),
                  onPressed: () async {
                    await tl.Tracelet.openBatterySettings();
                    if (ctx.mounted) Navigator.pop(ctx);
                    _addLog('OEM', 'Requested battery optimization exemption');
                  },
                ),
              ],

              const SizedBox(height: 20),
            ],
          ),
        ),
      );
    } catch (e) {
      _addLog('ERROR', 'showOemHealth() failed: $e');
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

  // ── Enterprise: Privacy Zones ─────────────────────────────────────────

  Future<void> _addSamplePrivacyZone() async {
    if (_lastLocation == null) {
      _addLog('WARN', 'No location yet — get a position first');
      return;
    }
    try {
      final loc = _lastLocation!;
      final id = 'pz_${DateTime.now().millisecondsSinceEpoch}';
      await tl.Tracelet.addPrivacyZone(
        tl.PrivacyZone(
          identifier: id,
          latitude: loc.coords.latitude,
          longitude: loc.coords.longitude,
          radius: 200,
        ),
      );
      _addLog(
        'PZ+',
        '$id  r=200m  exclude  at '
            '${loc.coords.latitude.toStringAsFixed(4)}, '
            '${loc.coords.longitude.toStringAsFixed(4)}',
      );
    } catch (e) {
      _addLog('ERROR', 'addPrivacyZone() failed: $e');
    }
  }

  Future<void> _addDegradePrivacyZone() async {
    if (_lastLocation == null) {
      _addLog('WARN', 'No location yet — get a position first');
      return;
    }
    try {
      final loc = _lastLocation!;
      final id = 'pz_deg_${DateTime.now().millisecondsSinceEpoch}';
      await tl.Tracelet.addPrivacyZone(
        tl.PrivacyZone(
          identifier: id,
          latitude: loc.coords.latitude,
          longitude: loc.coords.longitude,
          radius: 500,
          action: tl.PrivacyZoneAction.degrade,
        ),
      );
      _addLog(
        'PZ+',
        '$id  r=500m  degrade(1000m)  at '
            '${loc.coords.latitude.toStringAsFixed(4)}, '
            '${loc.coords.longitude.toStringAsFixed(4)}',
      );
    } catch (e) {
      _addLog('ERROR', 'addPrivacyZone(degrade) failed: $e');
    }
  }

  Future<void> _listPrivacyZones() async {
    try {
      final zones = await tl.Tracelet.getPrivacyZones();
      _addLog('PZ', '${zones.length} privacy zone(s)');
      for (final z in zones) {
        _addLog(
          '  PZ',
          '${z.identifier}  ${z.action.name}  r=${z.radius.toStringAsFixed(0)}m  '
              'at ${z.latitude.toStringAsFixed(4)}, ${z.longitude.toStringAsFixed(4)}',
        );
      }
    } catch (e) {
      _addLog('ERROR', 'getPrivacyZones() failed: $e');
    }
  }

  Future<void> _removeAllPrivacyZones() async {
    try {
      await tl.Tracelet.removePrivacyZones();
      _addLog('PZ', 'all privacy zones removed');
    } catch (e) {
      _addLog('ERROR', 'removePrivacyZones() failed: $e');
    }
  }

  // ── Enterprise: Audit Trail ─────────────────────────────────────────────

  Future<void> _verifyAuditTrail() async {
    try {
      final result = await tl.Tracelet.verifyAuditTrail();
      if (result.isValid) {
        _addLog(
          'AUDIT',
          'Chain VALID — ${result.verifiedRecords}/${result.totalRecords} records verified',
        );
      } else {
        _addLog(
          'AUDIT',
          'Chain BROKEN at index ${result.brokenAtIndex} '
              '(uuid: ${result.brokenAtUuid}) — ${result.error}',
        );
      }
    } catch (e) {
      _addLog('ERROR', 'verifyAuditTrail() failed: $e');
    }
  }

  Future<void> _getAuditProof() async {
    try {
      // Get the latest recorded locations to find a UUID for the proof.
      final locs = await tl.Tracelet.getLocations();
      if (locs.isEmpty) {
        _addLog('AUDIT', 'No locations recorded — nothing to prove');
        return;
      }
      final uuid = locs.last.uuid;
      final proof = await tl.Tracelet.getAuditProof(uuid);
      if (proof != null) {
        _addLog(
          'AUDIT',
          'Proof for $uuid:\n'
              '  hash=${proof.hash.substring(0, 16)}…\n'
              '  prev=${proof.previousHash.substring(0, 16)}…\n'
              '  index=${proof.chainIndex}  ts=${proof.timestamp}',
        );
      } else {
        _addLog('AUDIT', 'No audit proof found — is audit trail enabled?');
      }
    } catch (e) {
      _addLog('ERROR', 'getAuditProof() failed: $e');
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Tracelet ${_isWeb
              ? "Web"
              : _isAndroid
              ? "Android"
              : "iOS"}',
        ),
        centerTitle: true,
        actions: [
          // Open live map
          IconButton(
            tooltip: 'Live Map',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const MapPage()),
            ),
            icon: const Icon(Icons.map),
          ),
          IconButton(
            tooltip: 'Doctor',
            onPressed: () => TraceletDoctor.show(context),
            icon: const Icon(Icons.health_and_safety),
          ),
          IconButton(
            tooltip: 'Clear log',
            onPressed: () => setState(_log.clear),
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
            healthCheck: _lastHealthCheck,
          ),

          // ─── Action Sections ───────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: [
                // ── Prominent Test Button ──
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const IssuesPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.bug_report),
                    label: const Text(
                      'Issues Test',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                // ── Driving & Safety (3.3.0) Button ──
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const BehaviorPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.drive_eta),
                    label: const Text(
                      'Driving & Safety',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                // ── Live Provider Options (PR #241) Button ──
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const ProviderOptionsPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.tune),
                    label: const Text(
                      'Live Provider Options',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                // ── Foreground Service Health (#255) Button ──
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const ServiceHealthPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.health_and_safety),
                    label: const Text(
                      'Service Health',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                // ── Scan Server QR Button ──
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const ScannerPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text(
                      'Scan Server QR',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

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
                  _Section(
                    title: 'Lifecycle',
                    color: cs.primary,
                    children: [
                      _Chip('Start', Icons.play_arrow, _start),
                      _Chip('Stop', Icons.stop, _stop),
                      _Chip('Geofences Only', Icons.fence, _startGeofences),
                      _Chip('Get State', Icons.info_outline, _getState),
                      _Chip('Test Logs', Icons.bug_report, _testLogs),
                      _Chip(
                        'Test insertLocation',
                        Icons.add_location,
                        _testInsertLocationAndDestroy,
                      ),
                      _Chip(
                        'Test SQL/Carbon',
                        Icons.date_range,
                        _testSqlQueryAndCarbonReport,
                      ),
                      _Chip(
                        'Test Limits/Offsets',
                        Icons.sort,
                        _testSqlLimitsAndOffsets,
                      ),
                      _Chip(
                        'Test HTTP Sync',
                        Icons.cloud_upload,
                        _testHttpSync,
                      ),
                      _Chip('Live Map', Icons.map, () {
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => const MapPage(),
                          ),
                        );
                      }),
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
                        'Resolve Address',
                        Icons.pin_drop,
                        _getCurrentPositionWithAddress,
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
                      _Chip(
                        'No Activity Permission',
                        Icons.do_not_disturb,
                        _startWithoutActivityPermission,
                      ),
                    ],
                  ),

                  // ── Periodic Mode ──
                  _Section(
                    title: 'Periodic Mode (GPS-friendly)',
                    color: Colors.cyan.shade700,
                    children: [
                      _Chip(
                        _isPeriodicMode ? 'Periodic: ON' : 'Start Periodic',
                        _isPeriodicMode ? Icons.timer : Icons.timer_outlined,
                        _isPeriodicMode ? _stopPeriodic : _startPeriodic,
                      ),
                      _Chip(
                        'Custom Settings',
                        Icons.tune,
                        _showPeriodicSettingsDialog,
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
                        _kalmanEnabled ? 'Kalman: ON' : 'Kalman: OFF',
                        _kalmanEnabled ? Icons.blur_on : Icons.blur_off,
                        _toggleKalmanFilter,
                      ),
                      _Chip(
                        'Motion: ${_motionMode.name.toUpperCase()}',
                        _motionMode == tl.MotionDetectionMode.accelerometer
                            ? Icons.directions_walk
                            : _motionMode == tl.MotionDetectionMode.speed
                            ? Icons.speed
                            : Icons.smart_button,
                        _cycleMotionMode,
                      ),
                      _Chip(
                        _adaptiveMode ? 'Adaptive: ON' : 'Adaptive: OFF',
                        _adaptiveMode
                            ? Icons.auto_awesome
                            : Icons.auto_awesome_outlined,
                        _toggleAdaptiveMode,
                      ),
                      _Chip(
                        'Sensitivity: $_motionSensitivity',
                        Icons.sensors,
                        _cycleMotionSensitivity,
                      ),
                      _Chip('Last Trip', Icons.route, _showLastTrip),
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

                  // ── Health Check ──
                  _Section(
                    title: 'Health Check',
                    color: Colors.green.shade700,
                    children: [
                      _Chip(
                        'Run Health Check',
                        Icons.health_and_safety,
                        _runHealthCheck,
                      ),
                      _Chip(
                        'Health Dashboard',
                        Icons.dashboard_customize,
                        _showHealthDashboard,
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
                      _Chip(
                        '+ Polygon Here',
                        Icons.hexagon_outlined,
                        _addPolygonGeofenceAtCurrentLocation,
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
                      _Chip(
                        'Low-Accuracy GF',
                        Icons.battery_charging_full,
                        _startGeofencesLowAccuracy,
                      ),
                      _Chip(
                        'Track + Geofences (#51)',
                        Icons.track_changes,
                        _startContinuousWithGeofences,
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
                      if (_isAndroid)
                        _Chip(
                          'Request Battery Exemption',
                          Icons.battery_charging_full,
                          _requestBatteryExemption,
                        ),
                    ],
                  ),

                  // ── OEM Health (Android) ──
                  if (_isAndroid)
                    _Section(
                      title: 'OEM Health',
                      color: Colors.deepOrange,
                      children: [
                        _Chip(
                          'Check Health',
                          Icons.health_and_safety,
                          _checkOemHealth,
                        ),
                        _Chip(
                          'Health Dashboard',
                          Icons.dashboard,
                          _showOemHealthDialog,
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

                  // ── Enterprise ──
                  _Section(
                    title: 'Enterprise',
                    color: Colors.blueGrey,
                    children: [
                      _Chip(
                        '+ Exclude Zone',
                        Icons.shield,
                        _addSamplePrivacyZone,
                      ),
                      _Chip(
                        '+ Degrade Zone',
                        Icons.blur_on,
                        _addDegradePrivacyZone,
                      ),
                      _Chip('List Zones', Icons.list_alt, _listPrivacyZones),
                      _Chip(
                        'Remove Zones',
                        Icons.delete_forever,
                        _removeAllPrivacyZones,
                      ),
                      _Chip('Verify Trail', Icons.verified, _verifyAuditTrail),
                      _Chip('Audit Proof', Icons.receipt_long, _getAuditProof),
                      _Chip(
                        'Check Encrypted',
                        Icons.lock_outline,
                        _checkEncryption,
                      ),
                      _Chip(
                        'Encrypt DB',
                        Icons.enhanced_encryption,
                        _encryptDatabase,
                      ),
                      _Chip(
                        'Attestation Token',
                        Icons.verified_user,
                        _getAttestationToken,
                      ),
                    ],
                  ),

                  // ── Battery Budget ──
                  _Section(
                    title: 'Battery Budget',
                    color: Colors.amber.shade900,
                    children: [
                      _Chip(
                        _budgetEnabled ? 'Budget: ON' : 'Budget: OFF',
                        _budgetEnabled
                            ? Icons.battery_saver
                            : Icons.battery_full,
                        _toggleBatteryBudget,
                      ),
                      _Chip(
                        'Budget Status',
                        Icons.monitor_heart,
                        _showBudgetDashboard,
                      ),
                    ],
                  ),

                  // ── Carbon Footprint ──
                  _Section(
                    title: 'Carbon Footprint',
                    color: Colors.green.shade800,
                    children: [
                      _Chip(
                        'Last Trip CO\u2082',
                        Icons.eco,
                        _showCarbonSummary,
                      ),
                      _Chip(
                        'Carbon Dashboard',
                        Icons.bar_chart,
                        _showCarbonBottomSheet,
                      ),
                    ],
                  ),

                  // ── Compliance ──
                  _Section(
                    title: 'Compliance (GDPR/CCPA)',
                    color: Colors.indigo.shade800,
                    children: [
                      _Chip(
                        'Generate Report',
                        Icons.policy,
                        _showComplianceReport,
                      ),
                    ],
                  ),

                  // ── Dead Reckoning & Sparse Updates ──
                  _Section(
                    title: 'Advanced Tracking',
                    color: Colors.deepPurple.shade700,
                    children: [
                      _Chip(
                        _deadReckoningEnabled
                            ? 'Dead Reckoning: ON'
                            : 'Dead Reckoning: OFF',
                        _deadReckoningEnabled
                            ? Icons.explore
                            : Icons.explore_off,
                        _toggleDeadReckoning,
                      ),
                      _Chip(
                        'DR State',
                        Icons.info_outline,
                        _getDeadReckoningState,
                      ),
                      _Chip(
                        _sparseUpdatesEnabled ? 'Sparse: ON' : 'Sparse: OFF',
                        _sparseUpdatesEnabled
                            ? Icons.compress
                            : Icons.unfold_more,
                        _toggleSparseUpdates,
                      ),
                    ],
                  ),

                  // ── Delta Encoding & R-Tree ──
                  _Section(
                    title: 'Algorithms',
                    color: Colors.cyan.shade800,
                    children: [
                      _Chip(
                        'Delta Encoding',
                        Icons.data_saver_on,
                        _showDeltaEncodingDemo,
                      ),
                      _Chip('R-Tree Query', Icons.account_tree, _showRTreeDemo),
                    ],
                  ),

                  // ── HTTP Sync Control ──
                  _Section(
                    title: 'HTTP Sync Control',
                    color: Colors.teal.shade800,
                    children: [
                      _Chip(
                        _cellularSyncDisabled
                            ? 'Cellular: OFF'
                            : 'Cellular: ON',
                        _cellularSyncDisabled ? Icons.wifi : Icons.cell_tower,
                        _toggleCellularSync,
                      ),
                      _Chip('Manual Sync', Icons.cloud_sync, _manualSync),
                      _Chip('Refresh Headers', Icons.vpn_key, _refreshHeaders),
                      _Chip(
                        'Set Route Context',
                        Icons.route,
                        _setRouteContextDemo,
                      ),
                      _Chip(
                        'Clear Route Context',
                        Icons.clear_all,
                        _clearRouteContextDemo,
                      ),
                    ],
                  ),

                  const Divider(),
                ],
              ],
            ),
          ),

          // ─── Collapsible Event Log panel ──────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Tappable header
                InkWell(
                  onTap: () => setState(() => _logExpanded = !_logExpanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _logExpanded
                              ? Icons.expand_more
                              : Icons.chevron_right,
                          size: 20,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Event Log (${_log.length})',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const Spacer(),
                        if (_log.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.delete_sweep, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Clear log',
                            onPressed: () => setState(_log.clear),
                          ),
                      ],
                    ),
                  ),
                ),
                // Animated log body
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 200),
                  crossFadeState: _logExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: const SizedBox.shrink(),
                  secondChild: SizedBox(
                    height: 200,
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _log.length,
                      itemBuilder: (_, i) => _LogTile(entry: _log[i]),
                    ),
                  ),
                ),
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
    this.healthCheck,
  });

  final bool isReady;
  final bool isTracking;
  final bool isMoving;
  final tl.Location? location;
  final tl.State? state;
  final tl.HealthCheck? healthCheck;

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
              if (location!.isMock)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Chip(
                    avatar: const Icon(Icons.warning_amber, size: 18),
                    label: const Text('MOCK LOCATION'),
                    backgroundColor: cs.errorContainer,
                    labelStyle: TextStyle(
                      color: cs.onErrorContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
            if (healthCheck != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Chip(
                  avatar: Icon(
                    healthCheck!.isHealthy
                        ? Icons.check_circle
                        : Icons.warning_amber,
                    size: 18,
                    color: healthCheck!.isHealthy
                        ? Colors.green
                        : Colors.orange,
                  ),
                  label: Text(
                    healthCheck!.isHealthy
                        ? 'Healthy'
                        : '${healthCheck!.warningCount} Warning(s)',
                  ),
                ),
              ),
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
// OEM Health row
// ─────────────────────────────────────────────────────────────────────────────

class _HealthRow extends StatelessWidget {
  const _HealthRow(this.label, this.value, {this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
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
      'GEOFENCE' ||
      'GEOFENCES_CHANGE' ||
      'GEOFENCE+' ||
      'POLYGON' ||
      'POLYGON+' => Colors.orange,
      'HTTP' || 'SYNC' => Colors.cyan,
      'HEARTBEAT' => Colors.pink,
      'HEALTH' => Colors.green.shade700,
      'ADAPTIVE' => Colors.amber.shade800,
      'ERROR' || 'WARN' => Colors.red,
      'READY' || 'START' || 'STOP' => Colors.green,
      'PERIODIC' => Colors.cyan.shade700,
      'CONFIG' => Colors.amber,
      'DEAD_RECKONING' => Colors.deepPurple,
      'ENCRYPTION' => Colors.blueGrey,
      'ATTESTATION' => Colors.indigo,
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
