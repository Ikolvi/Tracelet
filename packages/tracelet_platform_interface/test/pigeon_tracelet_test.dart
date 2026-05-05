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
      accuracy: 5.0,
      speed: 2.5,
      heading: 90.0,
      altitude: 10.0,
      altitudeAccuracy: 3.0,
      speedAccuracy: 1.0,
      headingAccuracy: 2.0,
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
    radius: 200.0,
    notifyOnEntry: true,
    notifyOnExit: true,
    notifyOnDwell: false,
    loiteringDelay: 0,
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
  Future<TlState> ready(Map<String?, Object?> config) async {
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
  Future<TlState> setConfig(Map<String?, Object?> config) async {
    _record('setConfig', [config]);
    return _defaultState;
  }

  @override
  Future<TlState> reset(Map<String?, Object?>? config) async {
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
  Future<TlLocation?> getLastKnownLocation(
    Map<String?, Object?>? options,
  ) async {
    _record('getLastKnownLocation', [options]);
    return _defaultLocation;
  }

  @override
  Future<int> watchPosition(Map<String?, Object?> options) async {
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
  Future<List<TlLocation>> getLocations(Map<String?, Object?>? query) async {
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
  Future<List<TlLocation>> sync() async {
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
  Future<int> getNotificationPermissionStatus() async {
    _record('getNotificationPermissionStatus');
    return 3;
  }

  @override
  Future<int> requestNotificationPermission() async {
    _record('requestNotificationPermission');
    return 3;
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
  Future<int> getMotionPermissionStatus() async {
    _record('getMotionPermissionStatus');
    return 3;
  }

  @override
  Future<int> requestMotionPermission() async {
    _record('requestMotionPermission');
    return 3;
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
  Future<Map<String, Object?>> getDeviceInfo() async {
    _record('getDeviceInfo');
    return {'platform': 'test', 'framework': 'flutter'};
  }

  @override
  Future<Map<String, Object?>> getSensors() async {
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
  Future<Map<String, Object?>> getSettingsHealth() async {
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
  Future<bool> registerHeadlessTask(List<int> callbackIds) async {
    _record('registerHeadlessTask', [callbackIds]);
    return true;
  }

  @override
  Future<bool> registerHeadlessHeadersCallback(List<int> callbackIds) async {
    _record('registerHeadlessHeadersCallback', [callbackIds]);
    return true;
  }

  @override
  Future<bool> registerHeadlessSyncBodyBuilder(List<int> callbackIds) async {
    _record('registerHeadlessSyncBodyBuilder', [callbackIds]);
    return true;
  }

  // Enterprise: Audit
  @override
  Future<Map<String, Object?>> verifyAuditTrail() async {
    _record('verifyAuditTrail');
    return {'valid': true, 'count': 10};
  }

  @override
  Future<Map<String, Object?>?> getAuditProof(String uuid) async {
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
  Future<bool> addPrivacyZones(List<Map<String?, Object?>> zones) async {
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
  Future<List<Map<String, Object?>>> getPrivacyZones() async {
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
  Future<Map<String, Object?>?> getAttestationToken() async {
    _record('getAttestationToken');
    return {'token': 'test-token'};
  }

  // Enterprise: Carbon
  @override
  Future<Map<String, Object?>> getCarbonReport(
    Map<String?, Object?>? query,
  ) async {
    _record('getCarbonReport', [query]);
    return {'co2_grams': 42.0};
  }

  // Enterprise: Dead Reckoning
  @override
  Future<Map<String, Object?>?> getDeadReckoningState() async {
    _record('getDeadReckoningState');
    return {'active': true};
  }
}

void main() {
  late FakeHostApi fakeApi;
  late PigeonTracelet pigeon;

  setUp(() {
    fakeApi = FakeHostApi();
    pigeon = PigeonTracelet(api: fakeApi);
  });

  // ===================== Lifecycle =====================

  group('Lifecycle', () {
    test('ready() returns state map', () async {
      final state = await pigeon.ready({'debug': true});
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
      final state = await pigeon.setConfig({'distanceFilter': 50});
      expect(state['enabled'], true);
      expect(fakeApi.wasCalled('setConfig'), true);
    });

    test('reset() returns state map', () async {
      final state = await pigeon.reset({'debug': false});
      expect(state['enabled'], true);
      expect(fakeApi.wasCalled('reset'), true);
    });
  });

  // ===================== Location =====================

  group('Location', () {
    test('getCurrentPosition() returns location map', () async {
      final loc = await pigeon.getCurrentPosition({'timeout': 30});
      expect(loc['uuid'], 'test-uuid-123');
      expect((loc['coords'] as Map)['latitude'], 37.4219983);
      expect(loc['isMoving'], true);
      expect(fakeApi.wasCalled('getCurrentPosition'), true);
    });

    test('getLastKnownLocation() returns location map', () async {
      final loc = await pigeon.getLastKnownLocation();
      expect(loc['uuid'], 'test-uuid-123');
    });

    test('watchPosition() returns watch id', () async {
      final id = await pigeon.watchPosition({'persist': false});
      expect(id, 42);
    });

    test('stopWatchPosition() returns true', () async {
      expect(await pigeon.stopWatchPosition(42), true);
    });

    test('changePace() delegates', () async {
      expect(await pigeon.changePace(true), true);
      expect(fakeApi.wasCalled('changePace'), true);
    });

    test('getOdometer() returns value', () async {
      expect(await pigeon.getOdometer(), 456.7);
    });

    test('setOdometer() returns location map', () async {
      final loc = await pigeon.setOdometer(100.0);
      expect(loc['uuid'], 'test-uuid-123');
    });
  });

  // ===================== Geofencing =====================

  group('Geofencing', () {
    test('addGeofence() delegates with typed geofence', () async {
      expect(
        await pigeon.addGeofence({
          'identifier': 'test',
          'latitude': 37.42,
          'longitude': -122.08,
          'radius': 100.0,
        }),
        true,
      );
      expect(fakeApi.wasCalled('addGeofence'), true);
    });

    test(
      'addGeofence() forwards extras and vertices to TlGeofence (#58)',
      () async {
        await pigeon.addGeofence({
          'identifier': 'with-extras',
          'latitude': 12.9716,
          'longitude': 77.5946,
          'radius': 250.0,
          'extras': <String, Object?>{
            'demo_test': 'Hello from the geofence extras!',
            'Hello': 'World',
          },
          'vertices': <List<double>>[
            [12.97, 77.59],
            [12.98, 77.60],
          ],
        });
        final args = fakeApi.lastCallArgs('addGeofence');
        final TlGeofence forwarded = args!.first as TlGeofence;
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
          {
            'identifier': 'a',
            'latitude': 37.0,
            'longitude': -122.0,
            'radius': 50.0,
          },
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
    test('getPermissionStatus() returns index', () async {
      final status = await pigeon.getPermissionStatus();
      expect(status, TlAuthorizationStatus.always.index);
    });

    test('requestPermission() returns index', () async {
      final status = await pigeon.requestPermission();
      expect(status, TlAuthorizationStatus.always.index);
    });

    test('getNotificationPermissionStatus() returns value', () async {
      expect(await pigeon.getNotificationPermissionStatus(), 3);
    });

    test('requestNotificationPermission() returns value', () async {
      expect(await pigeon.requestNotificationPermission(), 3);
    });

    test('canScheduleExactAlarms() returns bool', () async {
      expect(await pigeon.canScheduleExactAlarms(), true);
    });

    test('openExactAlarmSettings() returns bool', () async {
      expect(await pigeon.openExactAlarmSettings(), false);
    });

    test('getMotionPermissionStatus() returns value', () async {
      expect(await pigeon.getMotionPermissionStatus(), 3);
    });

    test('requestMotionPermission() returns value', () async {
      expect(await pigeon.requestMotionPermission(), 3);
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
      final loc = await pigeon.getCurrentPosition({'timeout': 10});
      final coords = loc['coords'] as Map<String, Object?>;
      expect(coords['latitude'], 37.4219983);
      expect(coords['longitude'], -122.084);
      expect(coords['accuracy'], 5.0);
      expect(coords['speed'], 2.5);
      expect(coords['heading'], 90.0);
      expect(coords['altitude'], 10.0);
      expect(coords['altitudeAccuracy'], 3.0);
      expect(coords['speedAccuracy'], 1.0);
      expect(coords['headingAccuracy'], 2.0);

      final battery = loc['battery'] as Map<String, Object?>;
      expect(battery['level'], 0.85);
      expect(battery['isCharging'], true);

      final activity = loc['activity'] as Map<String, Object?>;
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
}
