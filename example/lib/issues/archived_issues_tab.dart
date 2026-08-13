import 'dart:async';
import 'dart:io';
// ignore_for_file: unused_element, unused_field
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';
import 'package:tracelet_example/issues/issue_sweep.dart';

@pragma('vm:entry-point')
void headlessSyncBodyBuilder136(HeadlessEvent event) {
  final locations = event.event['locations'];
  Tracelet.setSyncBodyResponse({
    'issue_136_test': 'success',
    'points': locations,
  });
}

class ArchivedIssuesTab extends StatefulWidget {
  const ArchivedIssuesTab({super.key});

  @override
  State<ArchivedIssuesTab> createState() => _ArchivedIssuesTabState();
}

class _ArchivedIssuesTabState extends State<ArchivedIssuesTab> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  static const _scope = 'archived';
  late final IssueSweep _sweep = IssueSweep(
    scrollController: _scrollController,
    scope: _scope,
  );
  String _searchQuery = '';

  bool _isTracking = false;
  final Map<int, String> _statuses = {};
  final Map<int, GlobalKey> _keys = {};

  final List<int> _allIssues = [
    115,
    117,
    118,
    119,
    120,
    124,
    125,
    126,
    134,
    136,
    137,
    138,
    139,
    140,
    141,
    148,
    150,
    151,
    152,
    155,
    156,
    157,
  ];

  bool _isIssue134Tracking = false;
  bool _isIssue140Tracking = false;
  Timer? _issue140Timer;
  int _issue140ElapsedSeconds = 0;
  StreamSubscription? _issue140MotionSub;
  bool _issue140IsMoving = false;

  bool _isIssue141Tracking = false;
  StreamSubscription? _issue141LocationSub;

  // Issue #155 — live activity propagation
  bool _isIssue155Tracking = false;
  StreamSubscription? _issue155Sub;

  // Issue #157 — live fixes with distanceFilter:0
  bool _isIssue157Tracking = false;
  StreamSubscription? _issue157Sub;
  int _issue157Count = 0;

  @override
  void initState() {
    super.initState();
    for (final issue in _allIssues) {
      _keys[issue] = GlobalKey();
      _statuses[issue] = 'Idle';
    }
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
    _sweep.addListener(_onSweepChanged);
  }

  void _onSweepChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _sweep
      ..removeListener(_onSweepChanged)
      ..dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _issue140Timer?.cancel();
    _issue140MotionSub?.cancel();
    _issue155Sub?.cancel();
    _issue157Sub?.cancel();
    _issue162Sub?.cancel();

    super.dispose();
  }

  void _setStatus(int issue, String status) {
    if (mounted) {
      setState(() {
        _statuses[issue] = status;
      });
    }
  }

  // ==== ISSUE 115 ====
  Future<void> _startIssue115Tracking() async {
    try {
      _setStatus(115, 'Requesting permissions...');
      await Tracelet.requestLocationAuthorization();
      _setStatus(115, 'Starting Tracelet with Issue 115 Config...');

      await Tracelet.ready(
        Config(
          motion: MotionConfig(
            motionDetectionMode: MotionDetectionMode.smart,
            stopTimeout: 1,
            speedStationaryDelay: 15,
            activityRecognitionInterval: 5000,
            shakeThreshold: Platform.isIOS ? 0.95 : 2.5,
            stillThreshold: Platform.isIOS ? 0.2 : 0.4,
            stillSampleCount: Platform.isIOS ? 50 : 25,
            speedMovingThreshold: 1.2,
            speedWakeConfirmCount: 2,
            stationaryPeriodicInterval: 900,
            stationaryPeriodicAccuracy: DesiredAccuracy.low,
          ),
        ),
      );

      final state = await Tracelet.start();
      setState(() {
        _isTracking = state.enabled;
        _setStatus(
          115,
          'Tracking Started. Put app in background and check Energy Impact.',
        );
      });
    } catch (e) {
      _setStatus(115, 'Error: $e');
    }
  }

  Future<void> _stopTracking() async {
    try {
      final state = await Tracelet.stop();
      setState(() {
        _isTracking = state.enabled;
        _setStatus(115, 'Tracking Stopped.');
      });
    } catch (e) {
      _setStatus(115, 'Error stopping: $e');
    }
  }

  // ==== ISSUE 117 ====
  Future<void> _testIssue117() async {
    _setStatus(117, 'Testing Issue 117 (Custom Sync Body)...');
    try {
      await Tracelet.destroyLocations();
      final server = await HttpServer.bind('127.0.0.1', 8080);
      server.listen((req) async {
        final content = await utf8.decoder.bind(req).join();
        if (content.contains('"custom_payload_test":"success"')) {
          _setStatus(117, '✅ SUCCESS: Issue 117 Passed! Custom body received.');
        } else {
          _setStatus(117, '❌ FAILED: Issue 117 Failed! Wrong payload.');
        }
        req.response.statusCode = 200;
        req.response.write('{"success":true}');
        await req.response.close();
        await server.close(force: true);
      });

      Tracelet.setSyncBodyBuilder((context) async {
        return {'custom_payload_test': 'success', 'points': context.locations};
      });

      await Tracelet.ready(
        const Config(
          http: HttpConfig(url: 'http://127.0.0.1:8080/sync', autoSync: false),
        ),
      );

      await Tracelet.insertLocation(
        const Location(
          uuid: 'test-issue-117-uuid',
          timestamp: '2026-06-06T11:27:54.443591+00:00',
          isMoving: false,
          odometer: 0,
          coords: Coords(latitude: 37.7749, longitude: -122.4194, accuracy: 10),
        ).toMap(),
      );

      await Tracelet.sync();
      Tracelet.setSyncBodyBuilder(null);
    } catch (e) {
      _setStatus(117, '❌ FAILED: Issue 117 Error: $e');
    }
  }

  // ==== ISSUE 118 ====
  Future<void> _testIssue118Valid() async {
    _setStatus(118, 'Testing Issue 118 (Valid SSL Pinning)...');
    try {
      await Tracelet.destroyLocations();
      final socket = await SecureSocket.connect(
        'jsonplaceholder.typicode.com',
        443,
      );
      final cert = socket.peerCertificate;
      if (cert == null) {
        _setStatus(118, '❌ FAILED: Could not get peer certificate');
        return;
      }
      final validFingerprint = sha256
          .convert(cert.der)
          .toString()
          .toUpperCase();
      socket.destroy();

      await Tracelet.ready(
        Config(
          http: HttpConfig(
            url: 'https://jsonplaceholder.typicode.com/posts',
            autoSync: false,
            sslPinningFingerprints: [validFingerprint],
          ),
        ),
      );

      await Tracelet.insertLocation(
        const Location(
          uuid: 'test-issue-118-valid',
          timestamp: '2026-06-06T11:27:54.443591+00:00',
          isMoving: false,
          odometer: 0,
          coords: Coords(latitude: 37.7749, longitude: -122.4194, accuracy: 10),
        ).toMap(),
      );

      await Tracelet.sync();

      final count = await Tracelet.getCount();
      if (count == 0) {
        _setStatus(
          118,
          '✅ SUCCESS: Valid fingerprint allowed sync ($validFingerprint).',
        );
      } else {
        _setStatus(
          118,
          '❌ FAILED: Valid fingerprint was blocked! (sync failed)',
        );
      }
    } catch (e) {
      _setStatus(118, '❌ FAILED: Unexpected error: $e');
    }
  }

  Future<void> _testIssue118Invalid() async {
    _setStatus(118, 'Testing Issue 118 (Invalid SSL Pinning)...');
    try {
      await Tracelet.destroyLocations();
      await Tracelet.ready(
        const Config(
          http: HttpConfig(
            url: 'https://jsonplaceholder.typicode.com/posts',
            autoSync: false,
            // Completely fake fingerprint
            sslPinningFingerprints: [
              'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55',
            ],
          ),
        ),
      );

      await Tracelet.insertLocation(
        const Location(
          uuid: 'test-issue-118-invalid',
          timestamp: '2026-06-06T11:27:54.443591+00:00',
          isMoving: false,
          odometer: 0,
          coords: Coords(latitude: 37.7749, longitude: -122.4194, accuracy: 10),
        ).toMap(),
      );

      await Tracelet.sync();

      final count = await Tracelet.getCount();
      if (count > 0) {
        _setStatus(
          118,
          '✅ SUCCESS: Invalid fingerprint successfully blocked sync!',
        );
      } else {
        _setStatus(118, '❌ FAILED: Invalid fingerprint somehow allowed sync!');
      }
    } catch (e) {
      _setStatus(118, '❌ FAILED: Unexpected error: $e');
    }
  }

  Future<void> _runIssue118All() async {
    await _testIssue118Valid();
    await Future.delayed(const Duration(seconds: 3));
    await _testIssue118Invalid();
  }

  // ==== ISSUE 120 ====
  Future<void> _testIssue120() async {
    _setStatus(120, 'Testing Issue 120 (Rust Parity)...');
    try {
      const channel = MethodChannel('com.tracelet/debug');
      final result = await channel.invokeMapMethod<String, dynamic>(
        'debugVerifyRustParity',
      );

      if (result == null) {
        _setStatus(120, '❌ FAILED: Null result from debug channel.');
        return;
      }

      final missingGeo = List<String>.from(result['missingGeo'] as List);
      final missingMotion = List<String>.from(result['missingMotion'] as List);

      if (missingGeo.isEmpty && missingMotion.isEmpty) {
        _setStatus(
          120,
          '✅ SUCCESS: All configuration properties are aligned with the Rust Core.',
        );
      } else {
        _setStatus(
          120,
          '❌ FAILED: Missing properties.\nGeo: $missingGeo\nMotion: $missingMotion',
        );
      }
    } on PlatformException catch (e) {
      _setStatus(120, '❌ FAILED: Issue 120 Error: ${e.message}');
    } catch (e) {
      _setStatus(120, '❌ FAILED: Issue 120 Error: $e');
    }
  }

  // ==== ISSUE 119 ====
  Future<void> _testIssue119() async {
    _setStatus(119, 'Testing Issue 119 (Timestamp Integer Filter)...');
    try {
      await Tracelet.destroyLocations();

      final t1 = DateTime.now().millisecondsSinceEpoch - 5000;
      await Tracelet.insertLocation({
        'latitude': 10.0,
        'longitude': 10.0,
        'timestamp': t1,
      });

      final t2 = DateTime.now().millisecondsSinceEpoch;
      await Tracelet.insertLocation({
        'latitude': 20.0,
        'longitude': 20.0,
        'timestamp': t2,
      });

      final t3 = DateTime.now().millisecondsSinceEpoch + 5000;
      await Tracelet.insertLocation({
        'latitude': 30.0,
        'longitude': 30.0,
        'timestamp': t3,
      });

      final locations = await Tracelet.getLocations(
        SQLQuery(
          start: DateTime.fromMillisecondsSinceEpoch(t2 - 50),
          end: DateTime.fromMillisecondsSinceEpoch(t2 + 50),
        ),
      );

      if (locations.length == 1 && locations.first.coords.latitude == 20.0) {
        _setStatus(
          119,
          '✅ SUCCESS: Query correctly filtered using integer timestamp index. Found exactly 1 location in range.',
        );
      } else {
        _setStatus(
          119,
          '❌ FAILED: Expected 1 location but got ${locations.length}. Time filtering failed.',
        );
      }
    } catch (e) {
      _setStatus(119, '❌ FAILED: Issue 119 Error: $e');
    }
  }

  // ==== ISSUE 124: Timeout Bug ====
  Future<void> _testIssue124Timeout() async {
    _setStatus(124, 'Testing Issue 124 (Timeout Bug)...');
    try {
      final currentUrl = Tracelet.activeConfig.http.url;
      if (currentUrl == null || currentUrl.isEmpty) {
        _setStatus(124, '❌ FAILED: Please scan a Test Server QR code first.');
        return;
      }

      await Tracelet.destroyLocations();

      // Register the custom body builder
      Tracelet.setSyncBodyBuilder((context) async {
        return {'issue_124_test': true, 'points': context.locations};
      });

      // Enable autoSync with a short delay, preserving background settings
      final newConfig = Tracelet.activeConfig.copyWith(
        http: Tracelet.activeConfig.http.copyWith(
          url: currentUrl,
          autoSyncDelay: 2000,
          headers: const {'X-Test-Header': 'issue124-value'},
        ),
      );
      await Tracelet.ready(newConfig);

      await Tracelet.insertLocation(
        const Location(
          uuid: 'test-timeout-124',
          timestamp: '2026-06-06T11:27:54.443591+00:00',
          isMoving: false,
          odometer: 0,
          coords: Coords(latitude: 37.7749, longitude: -122.4194, accuracy: 10),
        ).toMap(),
      );

      _setStatus(
        124,
        '✅ Location inserted! The app will now exit to detach the UI. Check Logcat in 10-15 seconds for the TIMEOUT error!',
      );

      // Programmatically exit the app (like pressing the Back button).
      // This detaches the Flutter Engine but keeps the Background Service alive!
      await Future.delayed(const Duration(seconds: 2));
      SystemNavigator.pop();
    } catch (e) {
      _setStatus(124, '❌ FAILED: Issue 124 Error: $e');
    }
  }

  // ==== ISSUE 124: Header Parse Crash ====
  Future<void> _testIssue124HeaderCrash() async {
    _setStatus(124, 'Testing Issue 124 (Header Parse Crash)...');
    try {
      final currentUrl = Tracelet.activeConfig.http.url;
      if (currentUrl == null || currentUrl.isEmpty) {
        _setStatus(124, '❌ FAILED: Please scan a Test Server QR code first.');
        return;
      }

      await Tracelet.destroyLocations();

      // Register the custom body builder
      Tracelet.setSyncBodyBuilder((context) async {
        return {'issue_124_test': true, 'points': context.locations};
      });

      // We trigger sync manually while the app is in the FOREGROUND.
      // This will successfully get the body, but then crash when parsing the header
      // (Note: Modern Android devices might not crash, but you'll see the headers missing in the server).
      await Tracelet.ready(
        Config(
          http: HttpConfig(
            url: currentUrl,
            autoSync: false,
            headers: const {'X-Test-Header': 'issue124-value'},
          ),
        ),
      );

      await Tracelet.insertLocation(
        const Location(
          uuid: 'test-header-crash-124',
          timestamp: '2026-06-06T11:27:54.443591+00:00',
          isMoving: false,
          odometer: 0,
          coords: Coords(latitude: 37.7749, longitude: -122.4194, accuracy: 10),
        ).toMap(),
      );

      _setStatus(
        124,
        '✅ Location inserted! Triggering foreground sync in 2 seconds...',
      );

      await Future.delayed(const Duration(seconds: 2));
      await Tracelet.sync();

      _setStatus(
        124,
        '✅ Sync completed! Check your test server logs to see if the custom header was received.',
      );
    } catch (e) {
      _setStatus(124, '❌ FAILED: Issue 124 Error: $e');
    }
  }

  // ==== ISSUE 125 ====
  Future<void> _testIssue125() async {
    _setStatus(125, 'Testing Issue 125 (Timeout Payload Abort)...');
    try {
      await Tracelet.stop();
      await Tracelet.destroyLocations();

      // Register a custom body builder that intentionally hangs to force a native timeout
      Tracelet.setSyncBodyBuilder((context) async {
        await Future.delayed(const Duration(seconds: 15));
        return {'custom': true};
      });

      await Tracelet.ready(
        const Config(
          http: HttpConfig(
            url: 'http://127.0.0.1:8125/issue125',
            autoSyncDelay: 1000,
          ),
        ),
      );

      await Tracelet.insertLocation({
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'coords': {'latitude': 10.0, 'longitude': 20.0, 'accuracy': 5.0},
      });

      _setStatus(
        125,
        'Mock location inserted. Check logs — sync should abort after ~10s timeout with no error payload posted.',
      );
    } catch (e) {
      _setStatus(125, '❌ FAILED: Issue 125 Error: $e');
    }
  }

  // ==== ISSUE 126 ====
  // Verifies DB-sourced locations passed to setSyncBodyBuilder use the SAME
  // nested schema as live onLocation events (nested coords/activity/battery)
  // and preserve route_context — instead of a flat map with a String activity.
  Future<void> _testIssue126() async {
    _setStatus(126, 'Testing Issue 126 (Schema alignment)...');
    try {
      await Tracelet.destroyLocations();
      await Tracelet.clearRouteContext();
      await Tracelet.setRouteContext(const RouteContext(taskId: 'task-126'));

      final captured = Completer<List<Map<String, Object?>>>();
      Tracelet.setSyncBodyBuilder((context) async {
        if (!captured.isCompleted) captured.complete(context.locations);
        return {'status': 'intercepted'};
      });

      await Tracelet.ready(
        const Config(
          http: HttpConfig(url: 'http://127.0.0.1:8126/sync', autoSync: false),
        ),
      );

      await Tracelet.insertLocation({
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'coords': {'latitude': 48.8566, 'longitude': 2.3522, 'accuracy': 5.0},
        'activity': {'type': 'walking', 'confidence': 100},
      });

      await Tracelet.sync();
      final locations = await captured.future.timeout(
        const Duration(seconds: 10),
      );
      Tracelet.setSyncBodyBuilder(null);

      if (locations.isEmpty) {
        _setStatus(126, '❌ FAILED: no locations passed to the sync builder.');
        return;
      }
      final first = locations.first;
      final coordsNested = first['coords'] is Map;
      final activityNested = first['activity'] is Map;
      final flatLatitude = first.containsKey('latitude');
      final stringActivity = first['activity'] is String;
      final extras = first['extras'] as Map?;
      final routeContext = extras?['route_context'] as Map?;
      final routeOk =
          routeContext != null && routeContext['taskId'] == 'task-126';

      if (coordsNested &&
          activityNested &&
          !flatLatitude &&
          !stringActivity &&
          routeOk) {
        _setStatus(
          126,
          '✅ SUCCESS: nested coords/activity + route_context preserved.',
        );
      } else {
        _setStatus(
          126,
          '❌ FAILED: coordsNested=$coordsNested activityNested=$activityNested '
          'flatLatitude=$flatLatitude stringActivity=$stringActivity '
          'routeContextPreserved=$routeOk',
        );
      }
    } catch (e) {
      _setStatus(126, '❌ FAILED: Issue 126 Error: $e');
    }
  }

  // ==== ISSUE 134: Background auto-sync stalls while moving ====
  // Reproduces the reporter's setup: continuous real-GPS tracking + autoSync to
  // the scanned backend, with a custom sync-body builder that mirrors their
  // shape ({ location: [...], is_live_ping: false, extras }). The point is to
  // observe whether on-the-fly background sync keeps firing while moving, or
  // stalls / emits "synced 0 locations" once the app is backgrounded.
  Future<void> _startIssue134Repro() async {
    _setStatus(134, 'Starting Issue 134 repro...');
    try {
      final scannedUrl = Tracelet.activeConfig.http.url;
      if (scannedUrl == null || scannedUrl.isEmpty) {
        _setStatus(134, '❌ FAILED: Please scan a Test Server QR code first.');
        return;
      }

      await Tracelet.requestLocationAuthorization();

      // Reporter's custom body shape (3.2.8). If this builder ever throws, the
      // native side returns null → aborts the sync → "synced 0 locations".
      //
      // IMPORTANT: await it. setSyncBodyBuilder() notifies the native side that a
      // foreground builder exists (setHasCustomSyncBodyBuilder); if you don't
      // await it, the first auto-sync can fire before that flag propagates and
      // the sync silently falls back to the DEFAULT body (no custom shape, no
      // custom headers) — exactly what the server logs showed.
      await Tracelet.setSyncBodyBuilder((context) async {
        return {
          'location': context.locations,
          'is_live_ping': false,
          'extras': {'source': 'issue134-repro'},
        };
      });

      await Tracelet.ready(
        Config(
          // distanceFilter: 0 so a stationary device still records fixes during
          // the repro (otherwise the Rust distance filter drops them and you see
          // only ONE sync — that's the filter, not a sync bug).
          geo: const GeoConfig(distanceFilter: 0),
          motion: const MotionConfig(
            motionDetectionMode: MotionDetectionMode.smart,
          ),
          http: HttpConfig(
            url: scannedUrl,
            autoSyncDelay: 5000,
            // Sample auth headers so you can confirm headers actually reach the
            // server. Replace with your real headers.
            headers: const {
              'Authorization': 'Bearer issue134-token',
              'x-account-id': 'demo-account',
            },
          ),
        ),
      );

      final state = await Tracelet.start();
      setState(() {
        _isIssue134Tracking = state.enabled;
      });
      _setStatus(
        134,
        '✅ Tracking started with autoSync → $scannedUrl.\n'
        'Now BACKGROUND the app (do NOT kill it) and move/drive.\n'
        'Watch your test server: locations should keep arriving every few '
        'seconds. If they stop after a couple of minutes — or you see '
        '"synced 0 locations" in the logs — the bug reproduced.',
      );
    } catch (e) {
      _setStatus(134, '❌ FAILED: Issue 134 Error: $e');
    }
  }

  Future<void> _stopIssue134Repro() async {
    try {
      await Tracelet.stop();
      await Tracelet.setSyncBodyBuilder(null);
      setState(() {
        _isIssue134Tracking = false;
      });
      _setStatus(134, 'Tracking stopped.');
    } catch (e) {
      _setStatus(134, '❌ Error stopping: $e');
    }
  }

  Future<void> _verifyIssue134() async {
    _setStatus(134, 'Verifying Issue 134 Fix...');
    try {
      // 1. Ensure NO custom sync body builder is registered
      await Tracelet.setSyncBodyBuilder(null);

      // 2. Set up local server
      final server = await HttpServer.bind('127.0.0.1', 8084);
      server.listen((req) async {
        req.response.statusCode = 200;
        req.response.write('{"success":true}');
        await req.response.close();
        await server.close(force: true);
      });

      await Tracelet.ready(
        const Config(
          http: HttpConfig(url: 'http://127.0.0.1:8084/sync', autoSync: false),
        ),
      );

      // 3. Insert mock location
      await Tracelet.insertLocation(
        const Location(
          uuid: 'verify-134',
          timestamp: '2026-06-06T11:27:54.443591+00:00',
          isMoving: false,
          odometer: 0,
          coords: Coords(latitude: 0, longitude: 0, accuracy: 10),
        ).toMap(),
      );

      // 4. Measure sync time
      final stopwatch = Stopwatch()..start();
      await Tracelet.sync();
      stopwatch.stop();

      // If the bug exists, it will take 10 seconds (dart callback timeout).
      // If fixed, it bypasses the timeout and finishes almost instantly.
      if (stopwatch.elapsedMilliseconds < 2000) {
        _setStatus(
          134,
          '✅ SUCCESS: Issue 134 Fixed! Sync took ${stopwatch.elapsedMilliseconds}ms (no timeout).',
        );
      } else {
        _setStatus(
          134,
          '❌ FAILED: Issue 134 Bug Present! Sync timed out, took ${stopwatch.elapsedMilliseconds}ms.',
        );
      }
    } catch (e) {
      _setStatus(134, '❌ FAILED: Issue 134 Error: $e');
    }
  }

  // ==== ISSUE 136: Background sync body interceptor ====
  Future<void> _testIssue136() async {
    _setStatus(136, 'Testing Issue 136 (Background Custom Sync Body)...');
    try {
      final currentUrl = Tracelet.activeConfig.http.url;
      if (currentUrl == null || currentUrl.isEmpty) {
        _setStatus(136, '❌ FAILED: Please scan a Test Server QR code first.');
        return;
      }

      await Tracelet.destroyLocations();

      // Register the headless body builder
      Tracelet.registerHeadlessSyncBodyBuilder(headlessSyncBodyBuilder136);

      // Enable autoSync with a short delay
      final newConfig = Tracelet.activeConfig.copyWith(
        http: Tracelet.activeConfig.http.copyWith(
          url: currentUrl,
          autoSyncDelay: 2000,
        ),
      );
      await Tracelet.ready(newConfig);

      await Tracelet.insertLocation(
        const Location(
          uuid: 'test-headless-136',
          timestamp: '2026-06-06T11:27:54.443591+00:00',
          isMoving: false,
          odometer: 0,
          coords: Coords(latitude: 37.7749, longitude: -122.4194, accuracy: 10),
        ).toMap(),
      );

      _setStatus(
        136,
        '✅ Location inserted & Headless Builder registered! Swipe/kill the app NOW from recent apps. Wait 5-10s and check your test server logs for multiple sync payloads. They should contain "issue_136_test": "success"!',
      );
    } catch (e) {
      _setStatus(136, '❌ FAILED: Issue 136 Error: $e');
    }
  }

  /// Runs every card on the tab (#372).
  ///
  /// This used to be a hand-maintained `if` ladder over [_allIssues] that
  /// scrolled with [Scrollable.ensureVisible] on off-screen cards — which does
  /// nothing, because a lazy list has not built them — and awaited each test
  /// with no timeout, so one card that never returned hung the whole run with no
  /// way to stop it. [IssueSweep] walks the list instead, running whatever has
  /// mounted, bounding each card and staying cancellable.
  Future<void> _executeAll() async {
    // Sweeping means "run everything", so a filter left in the search box would
    // silently make it a lie.
    _searchController.clear();
    await _sweep.start();
  }

  /// Issue #115 in one call, for the sweep: its card drives tracking with
  /// separate Start and Stop buttons, so the sweep needs the pair plus the
  /// window in between that the old ladder hard-coded.
  Future<void> _sweepIssue115() async {
    await _startIssue115Tracking();
    await Future<void>.delayed(const Duration(seconds: 3));
    await _stopTracking();
  }

  // ==== ISSUE 137: deltaCoordinatePrecision default ====
  Future<void> _testIssue137() async {
    _setStatus(137, 'Testing Issue 137 (delta precision default)...');
    try {
      await Tracelet.ready(
        Config(
          http: HttpConfig(
            url: Tracelet.activeConfig.http.url ?? 'https://example.com/loc',
            enableDeltaCompression: true,
            // deltaCoordinatePrecision intentionally NOT set → must default to 5.
          ),
        ),
      );
      final precision = Tracelet.activeConfig.http.deltaCoordinatePrecision;
      if (precision == 5) {
        _setStatus(
          137,
          '✅ SUCCESS: default deltaCoordinatePrecision = 5 (aligned across '
          'Dart and native; native previously defaulted to 6).',
        );
      } else {
        _setStatus(137, '❌ FAILED: expected 5 but got $precision.');
      }
    } catch (e) {
      _setStatus(137, '❌ FAILED: $e');
    }
  }

  // ==== ISSUE 138: locationsOrderDirection honored on sync ====
  Future<void> _testIssue138() async {
    _setStatus(138, 'Testing Issue 138 (descending sync order)...');
    try {
      await Tracelet.destroyLocations();
      final base = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < 3; i++) {
        await Tracelet.insertLocation({
          'latitude': 10.0 + i,
          'longitude': 20.0,
          'timestamp': base + i * 1000,
        });
      }
      await Tracelet.ready(
        Config(
          http: HttpConfig(
            url: Tracelet.activeConfig.http.url ?? 'https://example.com/loc',
            batchSync: true,
            locationsOrderDirection: LocationOrderDirection.descending,
          ),
        ),
      );
      await Tracelet.sync();
      _setStatus(
        138,
        '✅ Synced 3 points with locationsOrderDirection=descending. '
        'Verify your backend received them newest-first (was always ascending).',
      );
    } catch (e) {
      _setStatus(138, '❌ FAILED: $e');
    }
  }

  // ==== ISSUE 139: unbounded getLocations() (no 1000 cap) ====
  Future<void> _testIssue139() async {
    _setStatus(139, 'Testing Issue 139 (inserting 1100 rows)...');
    try {
      await Tracelet.destroyLocations();
      final base = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < 1100; i++) {
        await Tracelet.insertLocation({
          'latitude': 10.0 + i * 0.0001,
          'longitude': 20.0,
          'timestamp': base + i,
        });
      }
      final all = await Tracelet.getLocations();
      if (all.length == 1100) {
        _setStatus(
          139,
          '✅ SUCCESS: getLocations() returned all ${all.length} rows '
          '(no implicit 1000 cap).',
        );
      } else {
        _setStatus(
          139,
          '❌ FAILED: expected 1100 but got ${all.length} '
          '(query was capped).',
        );
      }
    } catch (e) {
      _setStatus(139, '❌ FAILED: $e');
    }
  }

  // ==== ISSUE 140: motion resumes during stop-timeout ====
  Future<void> _startIssue140() async {
    setState(() {
      _isIssue140Tracking = true;
      _issue140ElapsedSeconds = 0;
      _issue140IsMoving = true; // Default to moving on start
    });

    _issue140MotionSub?.cancel();
    _issue140MotionSub = Tracelet.onMotionChange((location) {
      if (mounted) {
        setState(() {
          _issue140IsMoving = location.isMoving;
        });
      }
    });

    _issue140Timer?.cancel();
    _issue140Timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _issue140ElapsedSeconds++);
      }
    });

    _setStatus(140, 'Starting smart-motion tracking (short stop-timeout)...');
    try {
      await Tracelet.requestLocationAuthorization();
      await Tracelet.ready(
        const Config(
          motion: MotionConfig(
            motionDetectionMode: MotionDetectionMode.smart,
            disableMotionActivityUpdates:
                true, // Disable AR to test raw accelerometer
            stopTimeout: 1, // minutes — keep short for the repro
            speedStationaryDelay: 60, // seconds — keep short for the repro
          ),
        ),
      );
      await Tracelet.start();
      _setStatus(
        140,
        'Tracking. Stay still until the stop-timeout countdown begins, then '
        'move again before it elapses — you should stay in the moving state.',
      );
    } catch (e) {
      setState(() => _isIssue140Tracking = false);
      _setStatus(140, '❌ FAILED: $e');
    }
  }

  Future<void> _stopIssue140() async {
    try {
      await Tracelet.stop();
    } finally {
      if (mounted) {
        _issue140Timer?.cancel();
        _issue140MotionSub?.cancel();
        setState(() => _isIssue140Tracking = false);
        _setStatus(140, 'Stopped.');
      }
    }
  }

  // ==== ISSUE 141: encryptDatabase: true silently breaks events ====
  Future<void> _startIssue141() async {
    _setStatus(
      141,
      'Testing Issue 141: encryptDatabase = true. Waiting for location...',
    );
    try {
      await Tracelet.stop();
      await Tracelet.ready(
        const Config(
          security: SecurityConfig(encryptDatabase: true),
          motion: MotionConfig(isMoving: true),
        ),
      );

      _issue141LocationSub = Tracelet.onLocation((loc) {
        _setStatus(
          141,
          '✅ SUCCESS: Received location with encryption enabled!',
        );
        _stopIssue141();
      });

      await Tracelet.start();
      setState(() => _isIssue141Tracking = true);
    } catch (e) {
      _setStatus(141, '❌ FAILED: $e');
    }
  }

  Future<void> _stopIssue141() async {
    await Tracelet.stop();
    _issue141LocationSub?.cancel();
    if (mounted) {
      setState(() => _isIssue141Tracking = false);
      if (_statuses[141] != null && !_statuses[141]!.contains('SUCCESS')) {
        _setStatus(141, 'Stopped.');
      }
    }
  }

  // ==== ISSUE 148: useKalmanFilter key mismatch (EKF silently disabled) ====
  Future<void> _testIssue148() async {
    _setStatus(148, 'Testing Issue 148 (Kalman key)...');
    try {
      await Tracelet.ready(
        const Config(
          geo: GeoConfig(filter: LocationFilter(useKalmanFilter: true)),
        ),
      );
      _setStatus(
        148,
        '✅ Configured useKalmanFilter:true. Native now reads the correct key '
        '(was silently disabled by reading "enableKalmanFilter"). Move with live '
        'GPS and observe smoother tracks / native logs to confirm the EKF is active.',
      );
    } catch (e) {
      _setStatus(148, '❌ FAILED: $e');
    }
  }

  // ==== ISSUE 150: AuditConfig sha384/sha512 fatal RangeError ====
  Future<void> _testIssue150() async {
    _setStatus(150, 'Testing Issue 150 (AuditConfig sha512 crash)...');
    try {
      await Tracelet.ready(
        const Config(
          audit: AuditConfig(
            enabled: true,
            hashAlgorithm: HashAlgorithm.sha512,
          ),
        ),
      );
      _setStatus(
        150,
        '✅ SUCCESS: ready() with HashAlgorithm.sha512 did NOT crash '
        '(previously threw a fatal RangeError). Unsupported variants fall back to sha256.',
      );
      // ignore: avoid_catching_errors — the regression under test IS a RangeError
    } on RangeError catch (e) {
      _setStatus(150, '❌ FAILED: RangeError still thrown: $e');
    } catch (e) {
      _setStatus(150, '❌ FAILED: $e');
    }
  }

  // ==== ISSUE 152: getCount ignores query filters ====
  Future<void> _testIssue152() async {
    _setStatus(152, 'Testing Issue 152 (getCount honors query)...');
    try {
      await Tracelet.ready(const Config());
      await Tracelet.destroyLocations();
      final now = DateTime.now().millisecondsSinceEpoch;
      await Tracelet.insertLocation({
        'latitude': 48.8566,
        'longitude': 2.3522,
        'timestamp': now - 2 * 3600 * 1000, // 2h ago
      });
      await Tracelet.insertLocation({
        'latitude': 48.8567,
        'longitude': 2.3523,
        'timestamp': now,
      });
      final total = await Tracelet.getCount();
      final lastHour = await Tracelet.getCount(
        SQLQuery(start: DateTime.fromMillisecondsSinceEpoch(now - 3600 * 1000)),
      );
      if (total == 2 && lastHour == 1) {
        _setStatus(
          152,
          '✅ SUCCESS: total=2, filtered (last hour)=1 — getCount() honors the '
          'time bounds (previously returned the whole-DB total).',
        );
      } else {
        _setStatus(
          152,
          '❌ FAILED: expected total=2, filtered=1 but got total=$total, '
          'filtered=$lastHour.',
        );
      }
    } catch (e) {
      _setStatus(152, '❌ FAILED: $e');
    }
  }

  // ==== ISSUE 155: activity never propagated (permanent "unknown") ====
  Future<void> _startIssue155() async {
    _setStatus(155, 'Starting Issue 155 (activity propagation)...');
    try {
      await Tracelet.ready(
        const Config(
          motion: MotionConfig(motionDetectionMode: MotionDetectionMode.smart),
        ),
      );
      _issue155Sub = Tracelet.onLocation((loc) {
        final act = loc.activity.type.name;
        _setStatus(
          155,
          act == 'unknown'
              ? '⏳ Live activity = "unknown" — keep moving (needs '
                    'ACTIVITY_RECOGNITION permission + real motion to classify).'
              : '✅ Live activity = "$act" — propagated into the location '
                    '(was permanently stuck at "unknown").',
        );
      });
      await Tracelet.start();
      setState(() => _isIssue155Tracking = true);
    } catch (e) {
      _setStatus(155, '❌ FAILED: $e');
    }
  }

  Future<void> _stopIssue155() async {
    await _issue155Sub?.cancel();
    _issue155Sub = null;
    try {
      await Tracelet.stop();
    } catch (_) {}
    setState(() => _isIssue155Tracking = false);
  }

  // ==== ISSUE 157: LocationEngine not rebuilt on ready() (stale distanceFilter) ====
  Future<void> _startIssue157() async {
    _setStatus(157, 'Starting Issue 157 (distanceFilter:0 rebuild)...');
    try {
      await Tracelet.ready(const Config(geo: GeoConfig(distanceFilter: 0)));
      setState(() => _issue157Count = 0);
      _issue157Sub = Tracelet.onLocation((loc) {
        setState(() => _issue157Count++);
        _setStatus(
          157,
          '✅ Received $_issue157Count fix(es) with distanceFilter:0 — the native '
          'processor was rebuilt on ready(). A stale 20m filter would suppress '
          'closely-spaced fixes.',
        );
      });
      await Tracelet.start();
      setState(() => _isIssue157Tracking = true);
    } catch (e) {
      _setStatus(157, '❌ FAILED: $e');
    }
  }

  Future<void> _stopIssue157() async {
    await _issue157Sub?.cancel();
    _issue157Sub = null;
    try {
      await Tracelet.stop();
    } catch (_) {}
    setState(() => _isIssue157Tracking = false);
  }

  // ==== ISSUE 151 + 156: is_moving / event missing from sync payload ====
  Future<void> _testIssue151156() async {
    _setStatus(151, 'Testing #151/#156 (sync payload)...');
    _setStatus(156, 'Testing #151/#156 (sync payload)...');
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final completer = Completer<Map<String, dynamic>>();
      server.listen((req) async {
        final content = await utf8.decoder.bind(req).join();
        req.response.statusCode = 200;
        req.response.write('{"success":true}');
        await req.response.close();
        if (!completer.isCompleted) {
          completer.complete(jsonDecode(content) as Map<String, dynamic>);
        }
      });
      await Tracelet.ready(
        Config(
          http: HttpConfig(
            url: 'http://127.0.0.1:${server.port}/sync',
            batchSync: true,
            maxBatchSize: 10,
          ),
        ),
      );
      await Tracelet.destroyLocations();
      await Tracelet.insertLocation({
        'uuid': 'issue-151-156',
        'timestamp': DateTime.now().toIso8601String(),
        'latitude': 37.7749,
        'longitude': -122.4194,
        'accuracy': 10.0,
        'speed': 1.2,
        'heading': 0.0,
        'altitude': 0.0,
        'is_moving': true,
        'event': 'motionchange',
      });
      await Tracelet.sync();
      final body = await completer.future.timeout(const Duration(seconds: 20));
      await server.close();
      final rec = (body['location'] as List).first as Map<String, dynamic>;
      final hasMoving = rec.containsKey('is_moving');
      final hasEvent = rec.containsKey('event');
      final msg = hasMoving && hasEvent
          ? '✅ SUCCESS: payload has is_moving=${rec['is_moving']} (#151) and '
                'event="${rec['event']}" (#156).'
          : '❌ FAILED: is_moving present=$hasMoving, event present=$hasEvent.';
      _setStatus(151, msg);
      _setStatus(156, msg);
    } catch (e) {
      _setStatus(151, '❌ FAILED: $e');
      _setStatus(156, '❌ FAILED: $e');
    }
  }

  // ==== ISSUE 147: TlState/getState() drops active config ====
  Future<void> _testIssue147() async {
    _setStatus(147, 'Testing #147 (state.config populated)...');
    try {
      final url = Tracelet.activeConfig.http.url;
      if (url == null || url.isEmpty) {
        _setStatus(147, '❌ FAILED: Please scan a Test Server QR code first.');
        return;
      }
      final state = await Tracelet.ready(
        Config(http: HttpConfig(url: url, maxBatchSize: 77)),
      );
      final fetched = await Tracelet.getState();
      if (state.config != null &&
          state.config!.http.url == url &&
          state.config!.http.maxBatchSize == 77 &&
          fetched.config != null) {
        _setStatus(
          147,
          '✅ SUCCESS: state.config is populated (url + maxBatchSize match) '
          'from both ready() and getState() — was permanently null.',
        );
      } else {
        _setStatus(
          147,
          '❌ FAILED: state.config=${state.config}, '
          'getState.config=${fetched.config}.',
        );
      }
      await Tracelet.stop();
    } catch (e) {
      _setStatus(147, '❌ FAILED: $e');
    }
  }

  // ==== ISSUE 149: missing syncInterval in HttpConfig ====
  Future<void> _testIssue149() async {
    _setStatus(149, 'Testing #149 (syncInterval)...');
    try {
      final url = Tracelet.activeConfig.http.url;
      if (url == null || url.isEmpty) {
        _setStatus(149, '❌ FAILED: Please scan a Test Server QR code first.');
        return;
      }
      const config = HttpConfig(syncInterval: 45);
      final hasKey = config.toMap().containsKey('syncInterval');
      final state = await Tracelet.ready(
        Config(http: HttpConfig(url: url, syncInterval: 30)),
      );
      final roundTrip = state.config?.http.syncInterval;
      if (hasKey && config.toMap()['syncInterval'] == 45 && roundTrip == 30) {
        _setStatus(
          149,
          '✅ SUCCESS: syncInterval exists in HttpConfig.toMap() and round-trips '
          'through native state (got $roundTrip).',
        );
      } else {
        _setStatus(
          149,
          '❌ FAILED: toMap has key=$hasKey, native round-trip=$roundTrip.',
        );
      }
      await Tracelet.stop();
    } catch (e) {
      _setStatus(149, '❌ FAILED: $e');
    }
  }

  // ==== ISSUE 154: dummy destroySyncedLocations stub ====
  Future<void> _testIssue154() async {
    _setStatus(154, 'Testing #154 (destroySyncedLocations)...');
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        await utf8.decoder.bind(req).join();
        req.response.statusCode = 200;
        req.response.write('{"success":true}');
        await req.response.close();
      });
      await Tracelet.ready(
        Config(
          http: HttpConfig(
            url: 'http://127.0.0.1:${server.port}/sync',
            autoSync: false,
            batchSync: true,
            maxBatchSize: 50,
          ),
        ),
      );
      await Tracelet.destroyLocations();
      await Tracelet.destroySyncedLocations(); // drain
      const count = 3;
      final base = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < count; i++) {
        await Tracelet.insertLocation({
          'uuid': 'issue-154-$i',
          'timestamp': base + i,
          'latitude': 48.8566 + i * 0.0001,
          'longitude': 2.3522,
          'accuracy': 10.0,
        });
      }
      await Tracelet.sync();
      final deleted = await Tracelet.destroySyncedLocations();
      await server.close(force: true);
      if (deleted == count) {
        _setStatus(
          154,
          '✅ SUCCESS: destroySyncedLocations() returned the real count '
          '($deleted) — no longer a hardcoded 0 stub.',
        );
      } else {
        _setStatus(154, '❌ FAILED: expected $count but got $deleted.');
      }
    } catch (e) {
      _setStatus(154, '❌ FAILED: $e');
    }
  }

  // ==== ISSUE 159: pending-queue metrics ====
  Future<void> _testIssue159() async {
    _setStatus(159, 'Testing #159 (pending-queue metrics)...');
    try {
      await Tracelet.ready(const Config());
      await Tracelet.destroyLocations();
      const count = 4;
      final base = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < count; i++) {
        await Tracelet.insertLocation({
          'uuid': 'issue-159-$i',
          'timestamp': base + i,
          'latitude': 12.9716 + i * 0.0001,
          'longitude': 77.5946,
          'accuracy': 5.0,
        });
      }
      final pendingCount = await Tracelet.getPendingLocationCount();
      final pending = await Tracelet.getPendingLocations();
      if (pendingCount == count && pending.length == count) {
        _setStatus(
          159,
          '✅ SUCCESS: getPendingLocationCount()=$pendingCount and '
          'getPendingLocations().length=${pending.length} expose the offline queue.',
        );
      } else {
        _setStatus(
          159,
          '❌ FAILED: count=$pendingCount, list=${pending.length} (expected $count).',
        );
      }
    } catch (e) {
      _setStatus(159, '❌ FAILED: $e');
    }
  }

  // ==== ISSUE 162: Battery Budget & Wakelock ====
  bool _isIssue162Tracking = false;
  StreamSubscription? _issue162Sub;
  String _issue162Details = '';

  // ==== ISSUE 175 ====
  Future<void> _testIssue175() async {
    _setStatus(175, 'Testing Issue 175 (Battery & Extras DB Persistence)...');
    try {
      await Tracelet.destroyLocations();

      await Tracelet.ready(
        const Config(
          http: HttpConfig(
            url: 'http://127.0.0.1:8175',
            autoSync: false,
            extras: {'issue175_test': 'global_extra_value'},
          ),
        ),
      );

      // Fetch a real location from the OS and persist it directly.
      await Tracelet.getCurrentPosition(maximumAge: 0, persist: true);

      final locations = await Tracelet.getLocations();
      if (locations.isEmpty) {
        _setStatus(175, '❌ FAILED: No locations found in DB.');
        return;
      }
      final loc = locations.first;
      final batLevel = loc.battery.level;
      final isCharging = loc.battery.isCharging;
      final extras = loc.extras;

      if (batLevel >= 0.0 && extras['issue175_test'] == 'global_extra_value') {
        _setStatus(
          175,
          '✅ SUCCESS: E2E Battery & Extras saved! Level: $batLevel, Charging: $isCharging',
        );
      } else {
        _setStatus(
          175,
          '❌ FAILED: Data lost. Battery: $batLevel, Extras: $extras',
        );
      }
    } catch (e) {
      _setStatus(175, '❌ FAILED: Issue 175 Error: $e');
    }
  }

  // ==== ISSUE 185: high-accuracy geofence transitions after reboot ====

  Future<void> _toggleIssue162() async {
    if (_isIssue162Tracking) {
      await Tracelet.stop();
      _issue162Sub?.cancel();
      setState(() {
        _isIssue162Tracking = false;
        _issue162Details = '';
        _statuses[162] = 'Idle';
      });
      return;
    }

    _setStatus(162, 'Requesting permissions...');
    await Tracelet.requestLocationAuthorization();
    await Tracelet.requestMotionAuthorization();

    _setStatus(162, 'Starting Tracelet with BatteryBudget (5%/hr)...');
    try {
      await Tracelet.ready(
        const Config(
          android: AndroidConfig(releaseWakelockWhenStationary: true),
          motion: MotionConfig(
            motionDetectionMode: MotionDetectionMode.smart,
            stationaryPeriodicInterval: 60,
          ),
          geo: GeoConfig(batteryBudgetPerHour: 5),
        ),
      );

      _issue162Sub = Tracelet.onBudgetAdjustment((event) {
        if (mounted) {
          setState(() {
            _issue162Details =
                'Drain: ${event.currentBatteryDrain.toStringAsFixed(2)}%/hr\n'
                'Target: ${event.targetBudget}%/hr\n'
                'New DF: ${event.newDistanceFilter}m\n'
                'New Acc: ${event.newDesiredAccuracy}\n'
                'New Interval: ${event.newPeriodicInterval}s';
          });
        }
      });

      await Tracelet.start();
      setState(() {
        _isIssue162Tracking = true;
        _statuses[162] = 'Tracking (Budget Active)';
      });
    } catch (e) {
      _setStatus(162, '❌ FAILED: $e');
    }
  }

  // ==== ISSUE 198: Passive Profile Testing ====

  Widget _buildIssueCard({
    required int issueNumber,
    required String title,
    required String description,
    required List<Widget> actions,
    IssueRunner? sweepAction,
  }) {
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      final matchesNumber = issueNumber.toString().contains(query);
      final matchesTitle = title.toLowerCase().contains(query);
      final matchesDescription = description.toLowerCase().contains(query);

      if (!matchesNumber && !matchesTitle && !matchesDescription) {
        return const SizedBox.shrink();
      }
    }

    final status = _statuses[issueNumber] ?? 'Idle';
    final isSuccess = status.contains('✅ SUCCESS');
    final isFailure = status.contains('❌ FAILED') || status.contains('Error');
    final isRunning =
        status.contains('Testing') ||
        status.contains('Requesting') ||
        status.contains('Starting');

    var statusColor = Colors.grey.shade700;
    if (isSuccess) statusColor = Colors.green.shade700;
    if (isFailure) statusColor = Colors.red.shade700;
    if (isRunning) statusColor = Colors.blue.shade700;

    // Enlists the card in Execute All for as long as it is mounted, the same
    // deal the card widgets get from IssueCardRun. A null [sweepAction] keeps a
    // card manual — a start/stop toggle, or a repro that needs the app killed.
    return IssueRunnerScope(
      id: 'issue-$issueNumber',
      run: sweepAction,
      child: Card(
        key: _keys[issueNumber],
        margin: const EdgeInsets.only(bottom: 16),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Issue #$issueNumber: $title',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(description),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SelectableText(
                        'Status: $status',
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IssueCopyButton(
                      text: status,
                      label: 'Issue #$issueNumber',
                      color: statusColor,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Search by Issue Number',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _sweep.active ? _sweep.cancel : _executeAll,
                  icon: Icon(_sweep.active ? Icons.stop : Icons.play_arrow),
                  label: Text(_sweep.active ? 'Stop' : 'Execute All'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          IssueSweepBanner(sweep: _sweep),
          Expanded(
            child: IssueCardScope(
              name: _scope,
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildIssueCard(
                    issueNumber: 115,
                    sweepAction: _sweepIssue115,
                    title: 'Battery Drain Test',
                    description:
                        'Tests iOS SDK with pausesLocationUpdatesAutomatically = false.',
                    actions: [
                      FilledButton.icon(
                        onPressed: _isTracking ? null : _startIssue115Tracking,
                        icon: const Icon(Icons.battery_alert),
                        label: const Text('Start Tracking'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _isTracking ? _stopTracking : null,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop Tracking'),
                      ),
                    ],
                  ),
                  _buildIssueCard(
                    issueNumber: 117,
                    sweepAction: _testIssue117,
                    title: 'Custom Sync Body Bypass',
                    description:
                        'Tests that TraceletSync intercepts the batch correctly and uses the custom body builder instead of the default structure.',
                    actions: [
                      FilledButton.icon(
                        onPressed: _testIssue117,
                        icon: const Icon(Icons.cloud_sync),
                        label: const Text('Test Custom Sync Body'),
                      ),
                    ],
                  ),
                  _buildIssueCard(
                    issueNumber: 118,
                    sweepAction: _runIssue118All,
                    title: 'SSL Pinning Fingerprints',
                    description:
                        'Verifies that sync correctly validates against SHA-256 certificate fingerprints and blocks invalid connections natively.',
                    actions: [
                      FilledButton.icon(
                        onPressed: _testIssue118Valid,
                        icon: const Icon(Icons.lock_open),
                        label: const Text('Test Valid Fingerprint'),
                      ),
                      FilledButton.icon(
                        onPressed: _testIssue118Invalid,
                        icon: const Icon(Icons.lock),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        label: const Text('Test Invalid Fingerprint'),
                      ),
                    ],
                  ),
                  _buildIssueCard(
                    issueNumber: 120,
                    sweepAction: _testIssue120,
                    title: 'Rust Core Parity',
                    description:
                        'Verifies that UniFFI Rust classes have all properties required by the Dart Config models to prevent silent dropping during serialization.',
                    actions: [
                      FilledButton.icon(
                        onPressed: _testIssue120,
                        icon: const Icon(Icons.sync_problem),
                        label: const Text('Test Config Parity'),
                      ),
                    ],
                  ),
                  _buildIssueCard(
                    issueNumber: 119,
                    sweepAction: _testIssue119,
                    title: 'Database Timestamp Optimization',
                    description:
                        'Verifies that timestamp_ms filters properly constrain results for O(log N) DB query performance.',
                    actions: [
                      FilledButton.icon(
                        onPressed: _testIssue119,
                        icon: const Icon(Icons.timer),
                        label: const Text('Test Timestamp Filter'),
                      ),
                    ],
                  ),
                  _buildIssueCard(
                    issueNumber: 124,
                    sweepAction: _testIssue124HeaderCrash,
                    title: 'Header Parsing & Fallback',
                    description:
                        'Reproduces the Header Parse Crash and Headless Timeout bugs.',
                    actions: [
                      FilledButton.icon(
                        onPressed: _testIssue124HeaderCrash,
                        icon: const Icon(Icons.http),
                        label: const Text('Reproduce Header Crash'),
                      ),
                      FilledButton.icon(
                        onPressed: _testIssue124Timeout,
                        icon: const Icon(Icons.timer_off),
                        label: const Text('Reproduce Timeout Bug'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                      ),
                    ],
                  ),
                  _buildIssueCard(
                    issueNumber: 125,
                    sweepAction: _testIssue125,
                    title: 'Timeout Payload Abort',
                    description:
                        'Verifies that if the custom sync body builder times out, the native SDK aborts the sync and does NOT post an error payload to the backend.',
                    actions: [
                      FilledButton.icon(
                        onPressed: _testIssue125,
                        icon: const Icon(Icons.timer_off),
                        label: const Text('Test Timeout Abort'),
                      ),
                    ],
                  ),
                  _buildIssueCard(
                    issueNumber: 134,
                    title: 'Background Auto-Sync Stalls',
                    description:
                        'Reproduces the reporter setup: continuous GPS tracking + '
                        'autoSync to the scanned backend with a custom sync-body '
                        'builder. Start, then background the app (do NOT kill it) '
                        'and move — watch the test server to see if on-the-fly '
                        'sync keeps firing or stalls ("synced 0 locations").',
                    actions: [
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: _isIssue134Tracking
                                ? null
                                : _startIssue134Repro,
                            icon: const Icon(Icons.directions_car),
                            label: const Text('Start Repro'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: _verifyIssue134,
                            child: const Text('Verify Auto'),
                          ),
                        ],
                      ),
                      OutlinedButton.icon(
                        onPressed: _isIssue134Tracking
                            ? _stopIssue134Repro
                            : null,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                      ),
                    ],
                  ),
                  _buildIssueCard(
                    issueNumber: 136,
                    title: 'Background Sync Body Interceptor',
                    description:
                        'Verifies that when the app UI is killed, background syncs still correctly call the headless sync body builder instead of falling back to the default payload. Click test, then kill the app from recents.',
                    actions: [
                      FilledButton.icon(
                        onPressed: _testIssue136,
                        icon: const Icon(Icons.sync_problem),
                        label: const Text('Test Headless Sync'),
                      ),
                    ],
                  ),
                  _buildIssueCard(
                    issueNumber: 126,
                    sweepAction: _testIssue126,
                    title: 'Sync Payload Schema Alignment',
                    description:
                        'Verifies DB-sourced locations passed to setSyncBodyBuilder '
                        'use the same nested schema as live onLocation events '
                        '(nested coords/activity/battery) and preserve route_context.',
                    actions: [
                      FilledButton.icon(
                        onPressed: _testIssue126,
                        icon: const Icon(Icons.schema),
                        label: const Text('Test Schema Alignment'),
                      ),
                    ],
                  ),
                  _buildIssueCard(
                    issueNumber: 137,
                    sweepAction: _testIssue137,
                    title: 'deltaCoordinatePrecision Default',
                    description:
                        'Verifies the delta-compression precision default matches the '
                        'Dart layer (5). A native fallback of 6 produced a finer grid '
                        'and larger payloads when the value was not set.',
                    actions: [
                      FilledButton.icon(
                        onPressed: _testIssue137,
                        icon: const Icon(Icons.compress),
                        label: const Text('Verify Default (5)'),
                      ),
                    ],
                  ),
                  _buildIssueCard(
                    issueNumber: 138,
                    sweepAction: _testIssue138,
                    title: 'locationsOrderDirection Honored on Sync',
                    description:
                        'Configures descending sync order, records 3 points and syncs. '
                        'Verify your backend receives the batch in descending order '
                        '(the sync path previously always uploaded ascending).',
                    actions: [
                      FilledButton.icon(
                        onPressed: _testIssue138,
                        icon: const Icon(Icons.sort),
                        label: const Text('Sync Descending'),
                      ),
                    ],
                  ),
                  _buildIssueCard(
                    issueNumber: 139,
                    sweepAction: _testIssue139,
                    title: 'Unbounded getLocations() (no 1000 cap)',
                    description:
                        'Inserts 1100 rows and reads them back with getLocations(). '
                        'Previously an unspecified limit silently capped reads at 1000, '
                        'truncating full-history reads and getCarbonReport().',
                    actions: [
                      FilledButton.icon(
                        onPressed: _testIssue139,
                        icon: const Icon(Icons.all_inbox),
                        label: const Text('Read 1100 Rows'),
                      ),
                    ],
                  ),
                  _buildIssueCard(
                    issueNumber: 140,
                    title: 'Motion Resumes During Stop-Timeout',
                    description:
                        'Starts smart-motion tracking with a short stop-timeout. '
                        'Walk for a few seconds, stay still until the countdown starts, '
                        'then move again BEFORE it elapses — tracking should stay in the '
                        'moving state (iOS keeps the accelerometer active during the '
                        'countdown; see issue for the Android behavior).',
                    actions: [
                      FilledButton.icon(
                        onPressed: _isIssue140Tracking ? null : _startIssue140,
                        icon: const Icon(Icons.directions_walk),
                        label: const Text('Start'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _isIssue140Tracking ? _stopIssue140 : null,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                      ),
                      if (_isIssue140Tracking)
                        Padding(
                          padding: const EdgeInsets.only(top: 8, left: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '⏱️ Stopwatch: $_issue140ElapsedSeconds s (Test your stop-timeout!)',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _issue140IsMoving
                                      ? Colors.green.shade100
                                      : Colors.red.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _issue140IsMoving
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                ),
                                child: Text(
                                  'Current State: ${_issue140IsMoving ? 'Moving 🏃' : 'Stationary 🛑'}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _issue140IsMoving
                                        ? Colors.green.shade900
                                        : Colors.red.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  _buildIssueCard(
                    issueNumber: 141,
                    title: 'encryptDatabase: true breaks events',
                    description:
                        'When encryptDatabase is set to true without an explicit key, '
                        'the internal DB correctly falls back to unencrypted storage, '
                        'but the Dart event bridge breaks silently due to Native config bypass. '
                        'This test ensures we receive location events successfully.',
                    actions: [
                      FilledButton.icon(
                        onPressed: _isIssue141Tracking ? null : _startIssue141,
                        icon: const Icon(Icons.security),
                        label: const Text('Start (Encrypted)'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _isIssue141Tracking ? _stopIssue141 : null,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                      ),
                    ],
                  ),
                  _buildIssueCard(
                    issueNumber: 148,
                    title: 'Kalman Filter silently disabled (key mismatch)',
                    description:
                        'Dart writes "useKalmanFilter" but native ConfigManager read '
                        '"enableKalmanFilter", so the Extended Kalman Filter never '
                        'initialized. Configures useKalmanFilter:true to confirm it is '
                        'now wired (observe smoother tracks / native logs while moving).',
                    actions: [
                      FilledButton.icon(
                        onPressed: _testIssue148,
                        icon: const Icon(Icons.timeline),
                        label: const Text('Configure & Verify'),
                      ),
                    ],
                  ),
                  _buildIssueCard(
                    issueNumber: 150,
                    title: 'AuditConfig sha384/sha512 fatal RangeError',
                    description:
                        'ready() with HashAlgorithm.sha512 crashed with a fatal '
                        'RangeError (Pigeon enum mismatch). This test confirms ready() '
                        'no longer crashes (falls back to sha256). Deterministic.',
                    actions: [
                      FilledButton.icon(
                        onPressed: _testIssue150,
                        icon: const Icon(Icons.lock_outline),
                        label: const Text('Run Test'),
                      ),
                    ],
                  ),
                  _buildIssueCard(
                    issueNumber: 152,
                    title: 'getCount ignores query filters',
                    description:
                        'getCount(SQLQuery) ignored time bounds and returned the '
                        'whole-DB total. Inserts 2 points (2h ago + now) and asserts a '
                        'last-hour query counts 1. Deterministic.',
                    actions: [
                      FilledButton.icon(
                        onPressed: _testIssue152,
                        icon: const Icon(Icons.numbers),
                        label: const Text('Run Test'),
                      ),
                    ],
                  ),
                  _buildIssueCard(
                    issueNumber: 155,
                    title: 'Activity permanently "unknown"',
                    description:
                        'Detected activity was never propagated to the LocationEngine, '
                        'so every record had "activity":"unknown". Start tracking and '
                        'move around — the live activity (in Status) should classify '
                        '(walking / still / in_vehicle). Needs ACTIVITY_RECOGNITION '
                        'permission + real motion.',
                    actions: [
                      FilledButton.icon(
                        onPressed: _isIssue155Tracking ? null : _startIssue155,
                        icon: const Icon(Icons.directions_walk),
                        label: const Text('Start'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _isIssue155Tracking ? _stopIssue155 : null,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                      ),
                    ],
                  ),
                  _buildIssueCard(
                    issueNumber: 157,
                    title: 'LocationEngine not rebuilt on ready()',
                    description:
                        'ready() with distanceFilter:0 kept the stale default processor, '
                        'filtering closely-spaced fixes. Start tracking and move slightly '
                        '— fixes should flow with no distance filtering (live counter in '
                        'Status).',
                    actions: [
                      FilledButton.icon(
                        onPressed: _isIssue157Tracking ? null : _startIssue157,
                        icon: const Icon(Icons.filter_alt_off),
                        label: const Text('Start (df:0)'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _isIssue157Tracking ? _stopIssue157 : null,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                      ),
                    ],
                  ),
                  _buildIssueCard(
                    issueNumber: 151,
                    title: 'is_moving missing from sync payload',
                    description:
                        'The native SyncLocationRecord omitted the motion state, so '
                        'the HTTP payload never carried "is_moving". This test syncs a '
                        'record (is_moving:true) to a loopback server and asserts the '
                        'payload contains it. Deterministic. (Same test as #156.)',
                    actions: [
                      FilledButton.icon(
                        onPressed: _testIssue151156,
                        icon: const Icon(Icons.directions_run),
                        label: const Text('Run Test'),
                      ),
                    ],
                  ),
                  _buildIssueCard(
                    issueNumber: 156,
                    title: 'event key missing from sync payload',
                    description:
                        'The native SyncLocationRecord omitted the trigger event, so '
                        'the HTTP payload never carried "event" (location / motionchange '
                        '/ heartbeat / geofence). This test syncs a record '
                        '(event:"motionchange") and asserts the payload contains it. '
                        'Deterministic. (Same test as #151.)',
                    actions: [
                      FilledButton.icon(
                        onPressed: _testIssue151156,
                        icon: const Icon(Icons.bolt),
                        label: const Text('Run Test'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
