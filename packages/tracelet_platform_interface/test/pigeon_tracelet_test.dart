import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

/// Fake implementation of [TraceletHostApi] for testing [PigeonTracelet].
///
/// Extends the generated class so that the `pigeonVar_*` fields are satisfied.
/// Every method is overridden to avoid real platform channel calls.
class FakeHostApi extends TraceletHostApi {
  final _calls = <String, List<Object?>>{}; // method name → last args

  void _record(String method, [List<Object?> args = const []]) {
    _calls[method] = args;
  }

  bool wasCalled(String method) => _calls.containsKey(method);

  List<Object?>? lastCallArgs(String method) => _calls[method];

  static final _defaultState = TlState(
    enabled: true,
    isMoving: false,
    trackingMode: TlTrackingMode.geofences,
    schedulerEnabled: false,
    odometer: 123.4,
    lastLocationTimestamp: '2024-01-01T00:00:00Z',
  );

  static final _defaultLocation = TlLocation(
    coords: TlCoords(
      latitude: 37.4219983,
      longitude: -122.084,
      accuracy: 5,
      speed: 2.5,
      heading: 90,
      altitude: 10,
      altitudeAccuracy: 3,
      speedAccuracy: 1,
      headingAccuracy: 2,
    ),
    battery: TlBattery(level: 0.85, isCharging: true),
    timestamp: '2024-01-01T00:00:00Z',
    uuid: 'test-uuid-123',
    isMoving: true,
    odometer: 456.7,
    event: 'motionchange',
    activity: TlActivity(type: 'walking', confidence: 80),
  );

  static final _defaultGeofence = TlGeofence(
    identifier: 'home',
    latitude: 37.42,
    longitude: -122.08,
    radius: 200,
  );

  static final _defaultProvider = TlProviderChangeEvent(
    enabled: true,
    gps: true,
    network: true,
    status: 3,
    accuracyAuthorization: 0,
  );

  // Lifecycle
  @override
  Future<TlState> ready(TlConfig config) async {
    _record('ready', [config]);
    return _defaultState;
  }

  @override
  Future<TlState> start() async {
    _record('start');
    return _defaultState;
  }

  @override
  Future<TlState> stop() async {
    _record('stop');
    return _defaultState;
  }

  @override
  Future<TlState> startGeofences() async {
    _record('startGeofences');
    return _defaultState;
  }

  @override
  Future<TlState> startPeriodic() async {
    _record('startPeriodic');
    return _defaultState;
  }

  @override
  Future<TlState> getState() async {
    _record('getState');
    return _defaultState;
  }

  @override
  Future<TlState> setConfig(TlConfig config) async {
    _record('setConfig', [config]);
    return _defaultState;
  }

  @override
  Future<TlState> reset([TlConfig? config]) async {
    _record('reset', [config]);
    return _defaultState;
  }

  // Location
  @override
  Future<TlLocation> getCurrentPosition(
    TlCurrentPositionOptions options,
  ) async {
    _record('getCurrentPosition', [options]);
    return _defaultLocation;
  }

  @override
  Future<bool> cancelCurrentPosition(String requestId) async {
    _record('cancelCurrentPosition', [requestId]);
    return true;
  }

  @override
  Future<TlLocation?> getLastKnownLocation(
    TlCurrentPositionOptions? options,
  ) async {
    _record('getLastKnownLocation', [options]);
    return _defaultLocation;
  }

  @override
  Future<int> watchPosition(TlCurrentPositionOptions options) async {
    _record('watchPosition', [options]);
    return 42;
  }

  @override
  Future<bool> stopWatchPosition(int watchId) async {
    _record('stopWatchPosition', [watchId]);
    return true;
  }

  @override
  Future<bool> changePace(bool isMoving) async {
    _record('changePace', [isMoving]);
    return true;
  }

  @override
  Future<bool> updateLocationProviderOptions(
    TlDesiredAccuracy? desiredAccuracy,
    double? distanceFilter,
  ) async {
    _record('updateLocationProviderOptions', [desiredAccuracy, distanceFilter]);
    return true;
  }

  @override
  Future<double> getOdometer() async {
    _record('getOdometer');
    return 456.7;
  }

  @override
  Future<TlLocation> setOdometer(double value) async {
    _record('setOdometer', [value]);
    return _defaultLocation;
  }

  // Geofencing
  @override
  Future<bool> addGeofence(TlGeofence geofence) async {
    _record('addGeofence', [geofence]);
    return true;
  }

  @override
  Future<bool> addGeofences(List<TlGeofence> geofences) async {
    _record('addGeofences', [geofences]);
    return true;
  }

  @override
  Future<bool> removeGeofence(String identifier) async {
    _record('removeGeofence', [identifier]);
    return true;
  }

  @override
  Future<bool> removeGeofences() async {
    _record('removeGeofences');
    return true;
  }

  @override
  Future<List<TlGeofence>> getGeofences() async {
    _record('getGeofences');
    return [_defaultGeofence];
  }

  @override
  Future<TlGeofence?> getGeofence(String identifier) async {
    _record('getGeofence', [identifier]);
    return _defaultGeofence;
  }

  @override
  Future<bool> geofenceExists(String identifier) async {
    _record('geofenceExists', [identifier]);
    return true;
  }

  // Persistence
  @override
  Future<List<TlLocation?>> getLocations(Map<String?, Object?>? query) async {
    _record('getLocations', [query]);
    return [_defaultLocation];
  }

  @override
  Future<int> getCount(Map<String?, Object?>? query) async {
    _record('getCount', [query]);
    return 42;
  }

  @override
  Future<bool> destroyLocations() async {
    _record('destroyLocations');
    return true;
  }

  @override
  Future<int> destroySyncedLocations() async {
    _record('destroySyncedLocations');
    return 5;
  }

  @override
  Future<bool> destroyLocation(String uuid) async {
    _record('destroyLocation', [uuid]);
    return true;
  }

  @override
  Future<String> insertLocation(Map<String?, Object?> params) async {
    _record('insertLocation', [params]);
    return 'inserted-uuid';
  }

  // HTTP Sync
  @override
  Future<List<TlLocation?>> sync() async {
    _record('sync');
    return [_defaultLocation];
  }

  @override
  Future<bool> setDynamicHeaders(Map<String?, String?> headers) async {
    _record('setDynamicHeaders', [headers]);
    return true;
  }

  @override
  Future<bool> setRouteContext(Map<String?, Object?> context) async {
    _record('setRouteContext', [context]);
    return true;
  }

  @override
  Future<bool> clearRouteContext() async {
    _record('clearRouteContext');
    return true;
  }

  @override
  Future<bool> registerHeadlessHeadersCallback(List<int?> callbackIds) async {
    _record('registerHeadlessHeadersCallback', [callbackIds]);
    return true;
  }

  @override
  Future<bool> registerHeadlessSyncBodyBuilder(List<int?> callbackIds) async {
    _record('registerHeadlessSyncBodyBuilder', [callbackIds]);
    return true;
  }

  // Permissions
  @override
  Future<TlAuthorizationStatus> getPermissionStatus() async {
    _record('getPermissionStatus');
    return TlAuthorizationStatus.always;
  }

  @override
  Future<TlAuthorizationStatus> requestPermission() async {
    _record('requestPermission');
    return TlAuthorizationStatus.always;
  }

  @override
  Future<TlNotificationAuthorizationStatus>
  getNotificationPermissionStatus() async {
    _record('getNotificationPermissionStatus');
    return TlNotificationAuthorizationStatus.authorized;
  }

  @override
  Future<TlNotificationAuthorizationStatus>
  requestNotificationPermission() async {
    _record('requestNotificationPermission');
    return TlNotificationAuthorizationStatus.authorized;
  }

  @override
  Future<bool> canScheduleExactAlarms() async {
    _record('canScheduleExactAlarms');
    return true;
  }

  @override
  Future<bool> openExactAlarmSettings() async {
    _record('openExactAlarmSettings');
    return false;
  }

  @override
  Future<TlMotionAuthorizationStatus> getMotionPermissionStatus() async {
    _record('getMotionPermissionStatus');
    return TlMotionAuthorizationStatus.authorized;
  }

  @override
  Future<TlMotionAuthorizationStatus> requestMotionPermission() async {
    _record('requestMotionPermission');
    return TlMotionAuthorizationStatus.authorized;
  }

  @override
  Future<int> requestTemporaryFullAccuracy(String purpose) async {
    _record('requestTemporaryFullAccuracy', [purpose]);
    return 0;
  }

  // Utility
  @override
  Future<bool> isPowerSaveMode() async {
    _record('isPowerSaveMode');
    return false;
  }

  @override
  Future<TlProviderChangeEvent> getProviderState() async {
    _record('getProviderState');
    return _defaultProvider;
  }

  @override
  Future<Map<String?, Object?>> getDeviceInfo() async {
    _record('getDeviceInfo');
    return {'platform': 'test', 'framework': 'flutter'};
  }

  @override
  Future<Map<String?, Object?>> getSensors() async {
    _record('getSensors');
    return {'accelerometer': true};
  }

  @override
  Future<bool> playSound(String name) async {
    _record('playSound', [name]);
    return true;
  }

  @override
  Future<bool> isIgnoringBatteryOptimizations() async {
    _record('isIgnoringBatteryOptimizations');
    return true;
  }

  @override
  Future<bool> requestSettings(String action) async {
    _record('requestSettings', [action]);
    return true;
  }

  @override
  Future<bool> showSettings(String action) async {
    _record('showSettings', [action]);
    return true;
  }

  @override
  Future<Map<String?, Object?>> getSettingsHealth() async {
    _record('getSettingsHealth');
    return {'manufacturer': 'Test'};
  }

  @override
  Future<bool> openOemSettings(String label) async {
    _record('openOemSettings', [label]);
    return false;
  }

  // Logging
  @override
  Future<String> getLog(Map<String?, Object?>? query) async {
    _record('getLog', [query]);
    return 'test log content';
  }

  @override
  Future<bool> destroyLog() async {
    _record('destroyLog');
    return true;
  }

  @override
  Future<bool> emailLog(String email) async {
    _record('emailLog', [email]);
    return true;
  }

  @override
  Future<bool> log(String level, String message) async {
    _record('log', [level, message]);
    return true;
  }

  // Scheduling
  @override
  Future<TlState> startSchedule() async {
    _record('startSchedule');
    return _defaultState;
  }

  @override
  Future<TlState> stopSchedule() async {
    _record('stopSchedule');
    return _defaultState;
  }

  // Background Tasks
  @override
  Future<int> startBackgroundTask() async {
    _record('startBackgroundTask');
    return 1;
  }

  @override
  Future<int> stopBackgroundTask(int taskId) async {
    _record('stopBackgroundTask', [taskId]);
    return taskId;
  }

  // Headless
  @override
  Future<bool> registerHeadlessTask(List<int?> callbackIds) async {
    _record('registerHeadlessTask', [callbackIds]);
    return true;
  }

  // Enterprise: Audit
  @override
  Future<Map<String?, Object?>> verifyAuditTrail() async {
    _record('verifyAuditTrail');
    return {'valid': true, 'count': 10};
  }

  @override
  Future<Map<String?, Object?>?> getAuditProof(String uuid) async {
    _record('getAuditProof', [uuid]);
    return {'uuid': uuid, 'hash': 'abc123'};
  }

  // Enterprise: Privacy
  @override
  Future<bool> addPrivacyZone(Map<String?, Object?> zone) async {
    _record('addPrivacyZone', [zone]);
    return true;
  }

  @override
  Future<bool> addPrivacyZones(List<Map<String?, Object?>?> zones) async {
    _record('addPrivacyZones', [zones]);
    return true;
  }

  @override
  Future<bool> removePrivacyZone(String identifier) async {
    _record('removePrivacyZone', [identifier]);
    return true;
  }

  @override
  Future<bool> removePrivacyZones() async {
    _record('removePrivacyZones');
    return true;
  }

  @override
  Future<List<Map<String?, Object?>?>> getPrivacyZones() async {
    _record('getPrivacyZones');
    return [
      {'identifier': 'home', 'latitude': 37.42},
    ];
  }

  // Enterprise: Encryption
  @override
  Future<bool> isDatabaseEncrypted() async {
    _record('isDatabaseEncrypted');
    return false;
  }

  @override
  Future<bool> encryptDatabase() async {
    _record('encryptDatabase');
    return true;
  }

  // Enterprise: Attestation
  @override
  Future<Map<String?, Object?>?> getAttestationToken() async {
    _record('getAttestationToken');
    return {'token': 'test-token'};
  }

  // Enterprise: Carbon
  @override
  Future<Map<String, Object?>> getCarbonReport(
    Map<String, Object?>? query,
  ) async {
    _record('getCarbonReport', [query]);
    return {'co2_grams': 42.0};
  }

  // Enterprise: Dead Reckoning
  @override
  Future<Map<String?, Object?>?> getDeadReckoningState() async {
    _record('getDeadReckoningState');
    return {'active': true};
  }
}

/// A [FakeHostApi] whose [requestStateFlush] always fails, reproducing an
/// unreachable platform channel (a headless `flutter test`, or a temporarily
/// detached engine). This is the exact condition that made the lazy
/// event-channel registration in `ready()` surface an *uncaught* async error
/// before #262.
class ThrowingFlushHostApi extends FakeHostApi {
  @override
  Future<void> requestStateFlush() async {
    _record('requestStateFlush');
    throw PlatformException(
      code: 'channel-error',
      message: 'Unable to establish connection on channel.',
    );
  }
}

/// A [FakeHostApi] that records how many times [requestStateFlush] runs and
/// completes successfully, for asserting the flush is fired lazily and only
/// once regardless of how many event streams are accessed.
class RecordingFlushHostApi extends FakeHostApi {
  int flushCount = 0;

  @override
  Future<void> requestStateFlush() async {
    flushCount++;
    _record('requestStateFlush');
  }
}

void main() {
  // Event-stream getters register a Pigeon FlutterApi handler on the binary
  // messenger, which requires an initialized test binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHostApi fakeApi;
  late PigeonTracelet pigeon;

  setUp(() {
    fakeApi = FakeHostApi();
    pigeon = PigeonTracelet(api: fakeApi);
  });

  // Helper to create a dummy TlConfig
  TlConfig createMockConfig() {
    return TlConfig(
      geo: TlGeoConfig(
        desiredAccuracy: TlDesiredAccuracy.high,
        distanceFilter: 10,
        stationaryRadius: 25,
        locationTimeout: 60,
        disableElasticity: false,
        elasticityMultiplier: 1,
        stopAfterElapsedMinutes: -1,
        maxMonitoredGeofences: -1,
        enableTimestampMeta: false,
        enableAdaptiveMode: false,
        periodicLocationInterval: 900,
        periodicDesiredAccuracy: TlDesiredAccuracy.medium,
        enableSparseUpdates: false,
        sparseDistanceThreshold: 50,
        sparseMaxIdleSeconds: 300,
        enableDeadReckoning: false,
        deadReckoningActivationDelay: 10,
        deadReckoningMaxDuration: 120,
        batteryBudgetPerHour: 0,
        resolveAddress: false,
        filter: TlLocationFilter(
          trackingAccuracyThreshold: 100,
          maxImpliedSpeed: 50,
          odometerAccuracyThreshold: 100,
          policy: TlLocationFilterPolicy.adjust,
          rejectMockLocations: false,
          mockDetectionLevel: 0,
          useKalmanFilter: false,
        ),
      ),
      app: TlAppConfig(
        stopOnTerminate: true,
        startOnBoot: false,
        heartbeatInterval: 60,
        schedule: [],
        remoteConfigTimeout: 30,
        remoteConfigRefreshInterval: 3600,
      ),
      classifier: TlClassifierConfig(
        enableFusedClassifier: false,
        fusedClassifierAuthoritative: false,
        modeSwitchDwellMs: 1000,
        minModeConfidence: 50,
        autoTuneFromTransportMode: false,
      ),
      impact: TlImpactConfig(
        enableCrashDetection: false,
        enableFallDetection: false,
        crashGThreshold: 4,
        crashMinSpeedKmh: 20,
        fallGThreshold: 3,
        confirmWindowMs: 5000,
        minImpactConfidence: 50,
        crashModelThreshold: 0.5,
      ),
      telematics: TlTelematicsConfig(
        enableDrivingEvents: false,
        harshBrakingG: 0.5,
        harshAccelerationG: 0.5,
        harshCorneringG: 0.5,
        speedLimitKmh: 120,
        speedingToleranceKmh: 10,
        speedingMinDurationMs: 5000,
        minSpeedForEventsKmh: 20,
        eventDebounceMs: 1000,
      ),
      android: TlAndroidConfig(
        locationUpdateInterval: 1000,
        fastestLocationUpdateInterval: 500,
        deferTime: 0,
        allowIdenticalLocations: false,
        geofenceModeHighAccuracy: false,
        periodicUseForegroundService: false,
        periodicUseExactAlarms: false,
        scheduleUseAlarmManager: false,
        releaseWakelockWhenStationary: false,
        foregroundService: TlForegroundServiceConfig(
          enabled: true,
          channelId: 'tracelet',
          channelName: 'Tracelet',
          notificationTitle: 'Tracking',
          notificationText: 'Tracking active',
          notificationPriority: TlNotificationPriority.defaultPriority,
          notificationOngoing: true,
          showNotificationOnPauseOnly: false,
          actions: [],
        ),
      ),
      ios: TlIosConfig(
        activityType: TlIosActivityType.other,
        useSignificantChangesOnly: false,
        showsBackgroundLocationIndicator: false,
        pausesLocationUpdatesAutomatically: false,
        locationAuthorizationRequest: TlAuthorizationRequest.always,
        disableLocationAuthorizationAlert: false,
        preventSuspend: false,
        useBackgroundActivitySession: false,
      ),
      http: TlHttpConfig(
        syncTelematics: false,
        autoSync: true,
        batchSync: false,
        maxBatchSize: 250,
        method: TlHttpMethod.post,
        autoSyncThreshold: 0,
        syncInterval: 0,
        httpTimeout: 60000,
        locationsOrderDirection: TlLocationOrderDirection.ascending,
        disableAutoSyncOnCellular: false,
        maxRetries: 3,
        retryBackoffBase: 1,
        retryBackoffCap: 60,
        enableDeltaCompression: false,
        deltaCoordinatePrecision: 5,
      ),
      logger: TlLoggerConfig(
        logLevel: TlLogLevel.info,
        logMaxDays: 3,
        debug: false,
      ),
      motion: TlMotionConfig(
        stopTimeout: 5,
        motionTriggerDelay: 0,
        disableMotionActivityUpdates: false,
        isMoving: false,
        activityRecognitionInterval: 1000,
        minimumActivityRecognitionConfidence: 75,
        disableStopDetection: false,
        stopDetectionDelay: 0,
        stopOnStationary: false,
        stationaryRadius: 25,
        useSignificantChangesOnly: false,
        shakeThreshold: 2.5,
        stillThreshold: 0.4,
        stillSampleCount: 25,
        motionDetectionMode: TlMotionDetectionMode.accelerometer,
        speedMovingThreshold: 1.5,
        speedStationaryDelay: 180,
        stationaryTrackingMode: TlStationaryTrackingMode.periodic,
        stationaryPeriodicInterval: 120,
        stationaryPeriodicAccuracy: TlDesiredAccuracy.high,
        speedWakeConfirmCount: 1,
      ),
      geofence: TlGeofenceConfig(
        geofenceInitialTriggerEntry: true,
        geofenceProximityRadius: 1000,
        geofenceInitialTrigger: true,
        geofenceModeHighAccuracy: false,
        geofenceExitAccuracyMax: -1,
      ),
      persistence: TlPersistenceConfig(
        persistMode: TlPersistMode.all,
        maxDaysToPersist: 1,
        maxRecordsToPersist: -1,
        disableProviderChangeRecord: false,
      ),
      audit: TlAuditConfig(
        enabled: false,
        hashAlgorithm: TlHashAlgorithm.sha256,
      ),
      privacyZone: TlPrivacyZoneConfig(enabled: false),
      security: TlSecurityConfig(encryptDatabase: false),
      attestation: TlAttestationConfig(enabled: false, refreshInterval: 3600),
    );
  }

  // ===================== Lifecycle =====================

  group('Lifecycle', () {
    test('ready() returns state map', () async {
      final config = createMockConfig();
      final state = await pigeon.ready(config);
      expect(state['enabled'], true);
      expect(state['isMoving'], false);
      expect(state['trackingMode'], 1);
      expect(state['odometer'], 123.4);
      expect(fakeApi.wasCalled('ready'), true);
    });

    test('start() returns state map', () async {
      final state = await pigeon.start();
      expect(state['enabled'], true);
      expect(fakeApi.wasCalled('start'), true);
    });

    test('stop() returns state map', () async {
      final state = await pigeon.stop();
      expect(state, isA<Map<String, Object?>>());
      expect(fakeApi.wasCalled('stop'), true);
    });

    test('startGeofences() delegates and returns state', () async {
      final state = await pigeon.startGeofences();
      expect(state['enabled'], true);
      expect(fakeApi.wasCalled('startGeofences'), true);
    });

    test('startPeriodic() delegates and returns state', () async {
      final state = await pigeon.startPeriodic();
      expect(state['enabled'], true);
      expect(fakeApi.wasCalled('startPeriodic'), true);
    });

    test('getState() returns state map', () async {
      final state = await pigeon.getState();
      expect(state['schedulerEnabled'], false);
      expect(fakeApi.wasCalled('getState'), true);
    });

    test('setConfig() returns state map', () async {
      final config = createMockConfig();
      final state = await pigeon.setConfig(config);
      expect(state['enabled'], true);
      expect(fakeApi.wasCalled('setConfig'), true);
    });

    test('reset() returns state map', () async {
      final config = createMockConfig();
      final state = await pigeon.reset(config);
      expect(state['enabled'], true);
      expect(fakeApi.wasCalled('reset'), true);
    });
  });

  // ===================== Location =====================

  group('Location', () {
    test('getCurrentPosition() returns location map', () async {
      final loc = await pigeon.getCurrentPosition(TlCurrentPositionOptions());
      expect(loc['uuid'], 'test-uuid-123');
      expect((loc['coords']! as Map)['latitude'], 37.4219983);
      expect(loc['isMoving'], true);
      expect(fakeApi.wasCalled('getCurrentPosition'), true);
    });

    // Phase 2 (#206): options are passed as a typed Pigeon object straight
    // through to the HostApi, so per-call fields (#201) can never be dropped.
    test('getCurrentPosition() passes typed options through (#206)', () async {
      await pigeon.getCurrentPosition(
        TlCurrentPositionOptions(
          desiredAccuracy: TlDesiredAccuracy.high,
          accuracyTarget: 100,
          requestId: 'display-7',
          extras: {'event_type': 'sos'},
        ),
      );
      final opts =
          fakeApi.lastCallArgs('getCurrentPosition')!.first!
              as TlCurrentPositionOptions;
      expect(opts.desiredAccuracy, TlDesiredAccuracy.high);
      expect(opts.extras?['event_type'], 'sos');
      expect(opts.accuracyTarget, 100);
      expect(opts.requestId, 'display-7');
    });

    test('getLastKnownLocation() returns location map', () async {
      final loc = await pigeon.getLastKnownLocation();
      expect(loc['uuid'], 'test-uuid-123');
    });

    test('watchPosition() returns watch id', () async {
      final id = await pigeon.watchPosition(
        TlCurrentPositionOptions(persist: false),
      );
      expect(id, 42);
    });

    test('cancelCurrentPosition() delegates request id', () async {
      expect(await pigeon.cancelCurrentPosition('display-7'), true);
      expect(fakeApi.lastCallArgs('cancelCurrentPosition'), ['display-7']);
    });

    test('stopWatchPosition() returns true', () async {
      expect(await pigeon.stopWatchPosition(42), true);
    });

    test('changePace() delegates', () async {
      expect(await pigeon.changePace(true), true);
      expect(fakeApi.wasCalled('changePace'), true);
    });

    test('updateLocationProviderOptions() delegates typed values', () async {
      expect(
        await pigeon.updateLocationProviderOptions(
          TlDesiredAccuracy.medium,
          25,
        ),
        true,
      );
      expect(fakeApi.lastCallArgs('updateLocationProviderOptions'), [
        TlDesiredAccuracy.medium,
        25.0,
      ]);
    });

    test('getOdometer() returns value', () async {
      expect(await pigeon.getOdometer(), 456.7);
    });

    test('setOdometer() returns location map', () async {
      final loc = await pigeon.setOdometer(100);
      expect(loc['uuid'], 'test-uuid-123');
    });
  });

  // ===================== Geofencing =====================

  group('Geofencing', () {
    test('addGeofence() delegates with typed geofence', () async {
      expect(
        await pigeon.addGeofence(
          TlGeofence(
            identifier: 'test',
            latitude: 37.42,
            longitude: -122.08,
            radius: 100,
          ),
        ),
        true,
      );
      expect(fakeApi.wasCalled('addGeofence'), true);
    });

    test(
      'addGeofence() forwards extras and vertices to TlGeofence (#58)',
      () async {
        await pigeon.addGeofence(
          TlGeofence(
            identifier: 'with-extras',
            latitude: 12.9716,
            longitude: 77.5946,
            radius: 250,
            extras: <String?, Object?>{
              'demo_test': 'Hello from the geofence extras!',
              'Hello': 'World',
            },
            vertices: <List<double?>?>[
              [12.97, 77.59],
              [12.98, 77.60],
            ],
          ),
        );
        final args = fakeApi.lastCallArgs('addGeofence');
        final forwarded = args!.first! as TlGeofence;
        expect(forwarded.extras, <String?, Object?>{
          'demo_test': 'Hello from the geofence extras!',
          'Hello': 'World',
        });
        expect(forwarded.vertices, isNotNull);
        expect(forwarded.vertices!.length, 2);
        expect(forwarded.vertices![0], <double?>[12.97, 77.59]);
      },
    );

    test('addGeofences() delegates with list', () async {
      expect(
        await pigeon.addGeofences([
          TlGeofence(
            identifier: 'a',
            latitude: 37,
            longitude: -122,
            radius: 50,
          ),
        ]),
        true,
      );
    });

    test('removeGeofence() delegates', () async {
      expect(await pigeon.removeGeofence('home'), true);
    });

    test('removeGeofences() delegates', () async {
      expect(await pigeon.removeGeofences(), true);
    });

    test('getGeofences() returns list of maps', () async {
      final list = await pigeon.getGeofences();
      expect(list, hasLength(1));
      expect(list.first['identifier'], 'home');
      expect(list.first['radius'], 200.0);
    });

    test('getGeofence() returns map', () async {
      final g = await pigeon.getGeofence('home');
      expect(g, isNotNull);
      expect(g!['identifier'], 'home');
    });

    test('geofenceExists() delegates', () async {
      expect(await pigeon.geofenceExists('home'), true);
    });
  });

  // ===================== Persistence =====================

  group('Persistence', () {
    test('getLocations() returns list of location maps', () async {
      final locs = await pigeon.getLocations();
      expect(locs, hasLength(1));
      expect(locs.first['uuid'], 'test-uuid-123');
    });

    test('getCount() returns count', () async {
      expect(await pigeon.getCount(), 42);
    });

    test('destroyLocations() returns true', () async {
      expect(await pigeon.destroyLocations(), true);
    });

    test('destroySyncedLocations() returns count', () async {
      expect(await pigeon.destroySyncedLocations(), 5);
    });

    test('destroyLocation() delegates', () async {
      expect(await pigeon.destroyLocation('uuid-1'), true);
    });

    test('insertLocation() returns uuid', () async {
      expect(await pigeon.insertLocation({'lat': 37.0}), 'inserted-uuid');
    });
  });

  // ===================== HTTP Sync =====================

  group('HTTP Sync', () {
    test('sync() returns list of location maps', () async {
      final locs = await pigeon.sync();
      expect(locs, hasLength(1));
    });

    test('setDynamicHeaders() delegates', () async {
      expect(await pigeon.setDynamicHeaders({'X-Token': 'abc'}), true);
    });

    test('setRouteContext() delegates', () async {
      expect(await pigeon.setRouteContext({'taskId': '1'}), true);
    });

    test('clearRouteContext() delegates', () async {
      expect(await pigeon.clearRouteContext(), true);
    });
  });

  // ===================== Permissions =====================

  group('Permissions', () {
    test('getLocationAuthorization() returns enum', () async {
      final status = await pigeon.getLocationAuthorization();
      expect(status, AuthorizationStatus.always);
    });

    test('requestLocationAuthorization() returns enum', () async {
      final status = await pigeon.requestLocationAuthorization();
      expect(status, AuthorizationStatus.always);
    });

    test('getNotificationAuthorization() returns enum', () async {
      expect(
        await pigeon.getNotificationAuthorization(),
        NotificationAuthorizationStatus.granted,
      );
    });

    test('requestNotificationAuthorization() returns enum', () async {
      expect(
        await pigeon.requestNotificationAuthorization(),
        NotificationAuthorizationStatus.granted,
      );
    });

    test('canScheduleExactAlarms() returns bool', () async {
      expect(await pigeon.canScheduleExactAlarms(), true);
    });

    test('openExactAlarmSettings() returns bool', () async {
      expect(await pigeon.openExactAlarmSettings(), false);
    });

    test('getMotionAuthorization() returns enum', () async {
      expect(
        await pigeon.getMotionAuthorization(),
        MotionAuthorizationStatus.granted,
      );
    });

    test('requestMotionAuthorization() returns enum', () async {
      expect(
        await pigeon.requestMotionAuthorization(),
        MotionAuthorizationStatus.granted,
      );
    });

    test('requestTemporaryFullAccuracy() delegates', () async {
      expect(await pigeon.requestTemporaryFullAccuracy('navigation'), 0);
    });
  });

  // ===================== Utility =====================

  group('Utility', () {
    test('isPowerSaveMode() returns bool', () async {
      expect(await pigeon.isPowerSaveMode(), false);
    });

    test('getProviderState() returns map', () async {
      final p = await pigeon.getProviderState();
      expect(p['enabled'], true);
      expect(p['gps'], true);
      expect(p['status'], 3);
    });

    test('getDeviceInfo() delegates', () async {
      final info = await pigeon.getDeviceInfo();
      expect(info['platform'], 'test');
    });

    test('getSensors() delegates', () async {
      final s = await pigeon.getSensors();
      expect(s['accelerometer'], true);
    });

    test('playSound() delegates', () async {
      expect(await pigeon.playSound('click'), true);
    });

    test('isIgnoringBatteryOptimizations() returns bool', () async {
      expect(await pigeon.isIgnoringBatteryOptimizations(), true);
    });

    test('requestSettings() delegates', () async {
      expect(await pigeon.requestSettings('location'), true);
    });

    test('showSettings() delegates', () async {
      expect(await pigeon.showSettings('app'), true);
    });

    test('getSettingsHealth() returns map', () async {
      final h = await pigeon.getSettingsHealth();
      expect(h['manufacturer'], 'Test');
    });

    test('openOemSettings() delegates', () async {
      expect(await pigeon.openOemSettings('battery'), false);
    });
  });

  // ===================== Logging =====================

  group('Logging', () {
    test('getLog() returns string', () async {
      expect(await pigeon.getLog(), 'test log content');
    });

    test('destroyLog() returns bool', () async {
      expect(await pigeon.destroyLog(), true);
    });

    test('emailLog() delegates', () async {
      expect(await pigeon.emailLog('test@test.com'), true);
    });

    test('log() delegates', () async {
      expect(await pigeon.log('INFO', 'test msg'), true);
    });
  });

  // ===================== Scheduling =====================

  group('Scheduling', () {
    test('startSchedule() returns state', () async {
      final s = await pigeon.startSchedule();
      expect(s['enabled'], true);
    });

    test('stopSchedule() returns state', () async {
      final s = await pigeon.stopSchedule();
      expect(s['enabled'], true);
    });
  });

  // ===================== Background Tasks =====================

  group('Background Tasks', () {
    test('startBackgroundTask() returns task id', () async {
      expect(await pigeon.startBackgroundTask(), 1);
    });

    test('stopBackgroundTask() returns task id', () async {
      expect(await pigeon.stopBackgroundTask(1), 1);
    });
  });

  // ===================== Headless =====================

  group('Headless', () {
    test('registerHeadlessTask() delegates', () async {
      expect(await pigeon.registerHeadlessTask([1, 2]), true);
    });

    test('registerHeadlessHeadersCallback() delegates', () async {
      expect(await pigeon.registerHeadlessHeadersCallback([3, 4]), true);
    });

    test('registerHeadlessSyncBodyBuilder() delegates', () async {
      expect(await pigeon.registerHeadlessSyncBodyBuilder([5, 6]), true);
    });
  });

  // ===================== Enterprise =====================

  group('Enterprise', () {
    test('verifyAuditTrail() returns map', () async {
      final r = await pigeon.verifyAuditTrail();
      expect(r['valid'], true);
    });

    test('getAuditProof() returns map', () async {
      final r = await pigeon.getAuditProof('uuid-1');
      expect(r, isNotNull);
      expect(r!['hash'], 'abc123');
    });

    test('addPrivacyZone() delegates', () async {
      expect(await pigeon.addPrivacyZone({'id': 'home'}), true);
    });

    test('addPrivacyZones() delegates', () async {
      expect(
        await pigeon.addPrivacyZones([
          {'id': 'home'},
        ]),
        true,
      );
    });

    test('removePrivacyZone() delegates', () async {
      expect(await pigeon.removePrivacyZone('home'), true);
    });

    test('removePrivacyZones() delegates', () async {
      expect(await pigeon.removePrivacyZones(), true);
    });

    test('getPrivacyZones() returns list', () async {
      final zones = await pigeon.getPrivacyZones();
      expect(zones, hasLength(1));
    });

    test('isDatabaseEncrypted() returns bool', () async {
      expect(await pigeon.isDatabaseEncrypted(), false);
    });

    test('encryptDatabase() returns bool', () async {
      expect(await pigeon.encryptDatabase(), true);
    });

    test('getAttestationToken() returns map', () async {
      final t = await pigeon.getAttestationToken();
      expect(t, isNotNull);
      expect(t!['token'], 'test-token');
    });

    test('getCarbonReport() returns map', () async {
      final r = await pigeon.getCarbonReport();
      expect(r['co2_grams'], 42.0);
    });

    test('getDeadReckoningState() returns map', () async {
      final s = await pigeon.getDeadReckoningState();
      expect(s, isNotNull);
      expect(s!['active'], true);
    });
  });

  // ===================== Converter fidelity =====================

  group('Converter fidelity', () {
    test('location map includes all nested fields', () async {
      final loc = await pigeon.getCurrentPosition(
        TlCurrentPositionOptions(timeout: 10),
      );
      final coords = loc['coords']! as Map<String, Object?>;
      expect(coords['latitude'], 37.4219983);
      expect(coords['longitude'], -122.084);
      expect(coords['accuracy'], 5.0);
      expect(coords['speed'], 2.5);
      expect(coords['heading'], 90.0);
      expect(coords['altitude'], 10.0);
      expect(coords['altitudeAccuracy'], 3.0);
      expect(coords['speedAccuracy'], 1.0);
      expect(coords['headingAccuracy'], 2.0);

      final battery = loc['battery']! as Map<String, Object?>;
      expect(battery['level'], 0.85);
      expect(battery['isCharging'], true);

      final activity = loc['activity']! as Map<String, Object?>;
      expect(activity['type'], 'walking');
      expect(activity['confidence'], 80);
    });

    test('state map includes all fields', () async {
      final state = await pigeon.getState();
      expect(state['enabled'], true);
      expect(state['isMoving'], false);
      expect(state['trackingMode'], 1);
      expect(state['schedulerEnabled'], false);
      expect(state['odometer'], 123.4);
      expect(state['lastLocationTimestamp'], '2024-01-01T00:00:00Z');
    });

    test('provider state map includes all fields', () async {
      final p = await pigeon.getProviderState();
      expect(p['enabled'], true);
      expect(p['gps'], true);
      expect(p['network'], true);
      expect(p['status'], 3);
      expect(p['accuracyAuthorization'], 0);
    });
  });

  // ===================== Event channel registration (#262) =====================
  //
  // Regression coverage for #262: accessing an event stream lazily registers
  // the Pigeon event channel and fires a best-effort `requestStateFlush()`.
  // That flush is intentionally fire-and-forget, so if it fails (unreachable
  // channel) its rejection must be CONTAINED inside the platform interface. If
  // it ever escapes as an uncaught async error again, it takes down a caller
  // that merely awaited `ready()` (e.g. a ride-start path) — which is the exact
  // regression these tests guard against.

  group('Event channel registration (#262 regression)', () {
    test('accessing an event stream never leaks an uncaught async error when '
        'requestStateFlush() fails', () async {
      final throwingApi = ThrowingFlushHostApi();
      final localPigeon = PigeonTracelet(api: throwingApi);
      final uncaught = <Object>[];

      await runZonedGuarded(
        () async {
          // Accessing the stream registers the event channel and fires the
          // best-effort flush. It must NOT throw synchronously at the call
          // site...
          final stream = localPigeon.remoteConfigEvents;
          expect(stream, isNotNull);
          // ...and the failing fire-and-forget flush must settle without
          // reaching the zone error handler.
          await pumpEventQueue();
        },
        (error, stack) {
          uncaught.add(error);
        },
      );

      expect(
        throwingApi.wasCalled('requestStateFlush'),
        isTrue,
        reason: 'the best-effort flush should still be attempted',
      );
      expect(
        uncaught,
        isEmpty,
        reason:
            'a fire-and-forget requestStateFlush() failure must be swallowed '
            'inside the platform interface, never surfaced as an uncaught '
            'async error (#262)',
      );
    });

    test(
      'event channel registers lazily and only once across streams',
      () async {
        final api = RecordingFlushHostApi();
        final localPigeon = PigeonTracelet(api: api);

        expect(
          api.flushCount,
          0,
          reason: 'nothing registers until an event stream is accessed',
        );

        // First access registers + flushes; subsequent accesses (same or other
        // streams) must not re-register.
        expect(localPigeon.remoteConfigEvents, isNotNull);
        expect(localPigeon.remoteConfigEvents, isNotNull);
        expect(localPigeon.modeChangeEvents, isNotNull);
        expect(localPigeon.motionModeChangeEvents, isNotNull);
        await pumpEventQueue();

        expect(
          api.flushCount,
          1,
          reason: 'registration + state flush happen exactly once, lazily',
        );
      },
    );

    test(
      'every event stream getter is safe to access when the flush fails',
      () async {
        final throwingApi = ThrowingFlushHostApi();
        final localPigeon = PigeonTracelet(api: throwingApi);
        final uncaught = <Object>[];

        await runZonedGuarded(() async {
          // Whichever getter is touched first triggers registration; verify a
          // representative spread returns real streams without leaking.
          expect(localPigeon.remoteConfigEvents, isNotNull);
          expect(localPigeon.modeChangeEvents, isNotNull);
          expect(localPigeon.motionModeChangeEvents, isNotNull);
          expect(localPigeon.crashModelStatusEvents, isNotNull);
          await pumpEventQueue();
        }, (error, stack) => uncaught.add(error));

        expect(uncaught, isEmpty);
      },
    );
  });
}
