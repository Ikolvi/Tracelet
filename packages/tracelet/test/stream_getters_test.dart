import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet/tracelet.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

TlCoords _coords({double lat = 37.0, double lng = -122.0}) => TlCoords(
  latitude: lat,
  longitude: lng,
  accuracy: 5,
  speed: 1,
  heading: 90,
  altitude: 50,
  altitudeAccuracy: 3,
  speedAccuracy: 0.5,
  headingAccuracy: 10,
);

TlBattery _battery() => TlBattery(level: 0.85, isCharging: false);

TlLocation _tlLocation({double lat = 37.0, double lng = -122.0}) => TlLocation(
  coords: _coords(lat: lat, lng: lng),
  battery: _battery(),
  timestamp: '2025-01-01T00:00:00.000Z',
  uuid: 'test-uuid',
  isMoving: true,
  odometer: 100.0,
);

// ---------------------------------------------------------------------------
// Mock platform with controllable stream controllers
// ---------------------------------------------------------------------------

class StreamTestPlatform extends TraceletPlatform {
  final locationCtrl = StreamController<TlLocation>.broadcast();
  final motionChangeCtrl = StreamController<TlLocation>.broadcast();
  final activityChangeCtrl =
      StreamController<TlActivityChangeEvent>.broadcast();
  final providerChangeCtrl =
      StreamController<TlProviderChangeEvent>.broadcast();
  final geofenceCtrl = StreamController<TlGeofenceEvent>.broadcast();
  final geofencesChangeCtrl =
      StreamController<TlGeofencesChangeEvent>.broadcast();
  final heartbeatCtrl = StreamController<TlHeartbeatEvent>.broadcast();
  final httpCtrl = StreamController<TlHttpEvent>.broadcast();
  final scheduleCtrl = StreamController<TlState>.broadcast();
  final powerSaveChangeCtrl = StreamController<bool>.broadcast();
  final connectivityChangeCtrl =
      StreamController<TlConnectivityChangeEvent>.broadcast();
  final enabledChangeCtrl = StreamController<bool>.broadcast();
  final notificationActionCtrl = StreamController<String>.broadcast();
  final authorizationCtrl = StreamController<TlAuthorizationEvent>.broadcast();
  final watchPositionCtrl = StreamController<TlLocation>.broadcast();

  @override
  Stream<TlLocation> get locationEvents => locationCtrl.stream;
  @override
  Stream<TlLocation> get motionChangeEvents => motionChangeCtrl.stream;
  @override
  Stream<TlActivityChangeEvent> get activityChangeEvents =>
      activityChangeCtrl.stream;
  @override
  Stream<TlProviderChangeEvent> get providerChangeEvents =>
      providerChangeCtrl.stream;
  @override
  Stream<TlGeofenceEvent> get geofenceEvents => geofenceCtrl.stream;
  @override
  Stream<TlGeofencesChangeEvent> get geofencesChangeEvents =>
      geofencesChangeCtrl.stream;
  @override
  Stream<TlHeartbeatEvent> get heartbeatEvents => heartbeatCtrl.stream;
  @override
  Stream<TlHttpEvent> get httpEvents => httpCtrl.stream;
  @override
  Stream<TlState> get scheduleEvents => scheduleCtrl.stream;
  @override
  Stream<bool> get powerSaveChangeEvents => powerSaveChangeCtrl.stream;
  @override
  Stream<TlConnectivityChangeEvent> get connectivityChangeEvents =>
      connectivityChangeCtrl.stream;
  @override
  Stream<bool> get enabledChangeEvents => enabledChangeCtrl.stream;
  @override
  Stream<String> get notificationActionEvents => notificationActionCtrl.stream;
  @override
  Stream<TlAuthorizationEvent> get authorizationEvents =>
      authorizationCtrl.stream;
  @override
  Stream<TlLocation> get watchPositionEvents => watchPositionCtrl.stream;

  @override
  Future<Map<String, Object?>> ready(Map<String, Object?> config) async => {
    'enabled': false,
    'trackingMode': TlTrackingMode.location.index,
    'isMoving': false,
    'odometer': 0.0,
  };

  void closeAll() {
    locationCtrl.close();
    motionChangeCtrl.close();
    activityChangeCtrl.close();
    providerChangeCtrl.close();
    geofenceCtrl.close();
    geofencesChangeCtrl.close();
    heartbeatCtrl.close();
    httpCtrl.close();
    scheduleCtrl.close();
    powerSaveChangeCtrl.close();
    connectivityChangeCtrl.close();
    enabledChangeCtrl.close();
    notificationActionCtrl.close();
    authorizationCtrl.close();
    watchPositionCtrl.close();
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late StreamTestPlatform mock;

  setUp(() {
    mock = StreamTestPlatform();
    TraceletPlatform.instance = mock;
  });

  tearDown(() {
    Tracelet.removeListeners();
    mock.closeAll();
  });

  // =========================================================================
  // locationStream
  // =========================================================================
  group('locationStream', () {
    test('emits Location objects from platform events', () async {
      // Initialize processor so _shouldAcceptLocation works.
      await Tracelet.ready(Config());

      final locations = <Location>[];
      final sub = Tracelet.locationStream.listen(locations.add);

      mock.locationCtrl.add(_tlLocation());
      await Future<void>.delayed(Duration.zero);

      expect(locations, hasLength(1));
      expect(locations.first.coords.latitude, 37.0);
      await sub.cancel();
    });

    test('supports multiple listeners (broadcast)', () async {
      await Tracelet.ready(Config());

      final list1 = <Location>[];
      final list2 = <Location>[];
      final sub1 = Tracelet.locationStream.listen(list1.add);
      final sub2 = Tracelet.locationStream.listen(list2.add);

      mock.locationCtrl.add(_tlLocation());
      await Future<void>.delayed(Duration.zero);

      expect(list1, hasLength(1));
      expect(list2, hasLength(1));
      await sub1.cancel();
      await sub2.cancel();
    });
  });

  // =========================================================================
  // motionChangeStream
  // =========================================================================
  group('motionChangeStream', () {
    test('emits Location on motion change', () async {
      final events = <Location>[];
      final sub = Tracelet.motionChangeStream.listen(events.add);

      mock.motionChangeCtrl.add(_tlLocation());
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.first.isMoving, isTrue);
      await sub.cancel();
    });

    test('supports multiple listeners', () async {
      final a = <Location>[];
      final b = <Location>[];
      final s1 = Tracelet.motionChangeStream.listen(a.add);
      final s2 = Tracelet.motionChangeStream.listen(b.add);

      mock.motionChangeCtrl.add(_tlLocation());
      await Future<void>.delayed(Duration.zero);

      expect(a, hasLength(1));
      expect(b, hasLength(1));
      await s1.cancel();
      await s2.cancel();
    });
  });

  // =========================================================================
  // activityChangeStream
  // =========================================================================
  group('activityChangeStream', () {
    test('emits ActivityChangeEvent', () async {
      final events = <ActivityChangeEvent>[];
      final sub = Tracelet.activityChangeStream.listen(events.add);

      mock.activityChangeCtrl.add(
        TlActivityChangeEvent(activity: 'walking', confidence: 85),
      );
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.first.activity, ActivityType.walking);
      expect(events.first.confidence, ActivityConfidence.high);
      await sub.cancel();
    });
  });

  // =========================================================================
  // providerChangeStream
  // =========================================================================
  group('providerChangeStream', () {
    test('emits ProviderChangeEvent', () async {
      final events = <ProviderChangeEvent>[];
      final sub = Tracelet.providerChangeStream.listen(events.add);

      mock.providerChangeCtrl.add(
        TlProviderChangeEvent(
          enabled: true,
          gps: true,
          network: false,
          status: 3,
          accuracyAuthorization: 0,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.first.enabled, isTrue);
      expect(events.first.gps, isTrue);
      await sub.cancel();
    });
  });

  // =========================================================================
  // geofenceStream
  // =========================================================================
  group('geofenceStream', () {
    test('emits GeofenceEvent', () async {
      final events = <GeofenceEvent>[];
      final sub = Tracelet.geofenceStream.listen(events.add);

      mock.geofenceCtrl.add(
        TlGeofenceEvent(
          identifier: 'office',
          action: TlGeofenceAction.enter,
          location: _tlLocation(),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.first.identifier, 'office');
      expect(events.first.action, GeofenceAction.enter);
      await sub.cancel();
    });
  });

  // =========================================================================
  // geofencesChangeStream
  // =========================================================================
  group('geofencesChangeStream', () {
    test('emits GeofencesChangeEvent', () async {
      final events = <GeofencesChangeEvent>[];
      final sub = Tracelet.geofencesChangeStream.listen(events.add);

      mock.geofencesChangeCtrl.add(
        TlGeofencesChangeEvent(
          on: [
            TlGeofence(
              identifier: 'gf1',
              latitude: 37.0,
              longitude: -122.0,
              radius: 200.0,
            ),
          ],
          off: [],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.first.on, hasLength(1));
      await sub.cancel();
    });
  });

  // =========================================================================
  // heartbeatStream
  // =========================================================================
  group('heartbeatStream', () {
    test('emits HeartbeatEvent', () async {
      final events = <HeartbeatEvent>[];
      final sub = Tracelet.heartbeatStream.listen(events.add);

      mock.heartbeatCtrl.add(TlHeartbeatEvent(location: _tlLocation()));
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.first.location.coords.latitude, 37.0);
      await sub.cancel();
    });
  });

  // =========================================================================
  // httpStream
  // =========================================================================
  group('httpStream', () {
    test('emits HttpEvent', () async {
      final events = <HttpEvent>[];
      final sub = Tracelet.httpStream.listen(events.add);

      mock.httpCtrl.add(
        TlHttpEvent(isSuccess: true, status: 200, responseText: 'OK'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.first.success, isTrue);
      expect(events.first.status, 200);
      await sub.cancel();
    });
  });

  // =========================================================================
  // scheduleStream
  // =========================================================================
  group('scheduleStream', () {
    test('emits State', () async {
      final events = <State>[];
      final sub = Tracelet.scheduleStream.listen(events.add);

      mock.scheduleCtrl.add(
        TlState(
          enabled: true,
          isMoving: false,
          trackingMode: TlTrackingMode.location,
          schedulerEnabled: true,
          odometer: 0,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.first.enabled, isTrue);
      expect(events.first.schedulerEnabled, isTrue);
      await sub.cancel();
    });
  });

  // =========================================================================
  // powerSaveChangeStream
  // =========================================================================
  group('powerSaveChangeStream', () {
    test('emits bool', () async {
      final events = <bool>[];
      final sub = Tracelet.powerSaveChangeStream.listen(events.add);

      mock.powerSaveChangeCtrl.add(true);
      await Future<void>.delayed(Duration.zero);

      expect(events, [true]);
      await sub.cancel();
    });
  });

  // =========================================================================
  // connectivityChangeStream
  // =========================================================================
  group('connectivityChangeStream', () {
    test('emits ConnectivityChangeEvent', () async {
      final events = <ConnectivityChangeEvent>[];
      final sub = Tracelet.connectivityChangeStream.listen(events.add);

      mock.connectivityChangeCtrl.add(
        TlConnectivityChangeEvent(connected: false),
      );
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.first.connected, isFalse);
      await sub.cancel();
    });
  });

  // =========================================================================
  // enabledChangeStream
  // =========================================================================
  group('enabledChangeStream', () {
    test('emits bool', () async {
      final events = <bool>[];
      final sub = Tracelet.enabledChangeStream.listen(events.add);

      mock.enabledChangeCtrl.add(true);
      await Future<void>.delayed(Duration.zero);

      expect(events, [true]);
      await sub.cancel();
    });
  });

  // =========================================================================
  // notificationActionStream
  // =========================================================================
  group('notificationActionStream', () {
    test('emits String', () async {
      final events = <String>[];
      final sub = Tracelet.notificationActionStream.listen(events.add);

      mock.notificationActionCtrl.add('custom_action');
      await Future<void>.delayed(Duration.zero);

      expect(events, ['custom_action']);
      await sub.cancel();
    });
  });

  // =========================================================================
  // Cache invalidation via removeListeners()
  // =========================================================================
  group('removeListeners() clears cached streams', () {
    test('new stream after removeListeners still works', () async {
      // Listen once
      final first = <Location>[];
      final sub1 = Tracelet.motionChangeStream.listen(first.add);
      mock.motionChangeCtrl.add(_tlLocation());
      await Future<void>.delayed(Duration.zero);
      expect(first, hasLength(1));
      await sub1.cancel();

      // Clear caches
      Tracelet.removeListeners();

      // Listen again — should create a fresh stream
      final second = <Location>[];
      final sub2 = Tracelet.motionChangeStream.listen(second.add);
      mock.motionChangeCtrl.add(_tlLocation(lat: 38.0));
      await Future<void>.delayed(Duration.zero);
      expect(second, hasLength(1));
      expect(second.first.coords.latitude, 38.0);
      await sub2.cancel();
    });
  });
}
