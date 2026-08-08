import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet/tracelet.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

void main() {
  test('Config has sensible defaults', () {
    const config = Config();
    expect(config.geo.desiredAccuracy, DesiredAccuracy.high);
    expect(config.geo.distanceFilter, 10.0);
    expect(config.app.stopOnTerminate, true);
    expect(config.http.autoSync, true);
  });

  test('Config round-trip serialization', () {
    const config = Config(
      geo: GeoConfig(distanceFilter: 50),
      app: AppConfig(heartbeatInterval: 120),
    );
    final map = config.toMap();
    final restored = Config.fromMap(map);
    expect(restored.geo.distanceFilter, 50.0);
    expect(restored.app.heartbeatInterval, 120);
  });

  group('Tracelet runtime provider options', () {
    late MockTraceletPlatform mockPlatform;

    setUp(() {
      mockPlatform = MockTraceletPlatform();
      TraceletPlatform.instance = mockPlatform;
    });

    test(
      'delegates temporary provider options without changing config',
      () async {
        final config = Tracelet.activeConfig;

        final updated = await Tracelet.updateLocationProviderOptions(
          desiredAccuracy: DesiredAccuracy.medium,
          distanceFilter: 25,
        );

        expect(updated, isTrue);
        expect(
          mockPlatform.lastProviderDesiredAccuracy,
          TlDesiredAccuracy.medium,
        );
        expect(mockPlatform.lastProviderDistanceFilter, 25);
        expect(Tracelet.activeConfig, same(config));
      },
    );

    test('no arguments clear the provider override', () async {
      final updated = await Tracelet.updateLocationProviderOptions();

      expect(updated, isTrue);
      expect(mockPlatform.lastProviderDesiredAccuracy, isNull);
      expect(mockPlatform.lastProviderDistanceFilter, isNull);
    });

    test('rejects invalid distance filters before calling the platform', () {
      expect(
        () => Tracelet.updateLocationProviderOptions(distanceFilter: -1),
        throwsRangeError,
      );
      expect(
        () =>
            Tracelet.updateLocationProviderOptions(distanceFilter: double.nan),
        throwsRangeError,
      );
      expect(mockPlatform.providerOptionsCallCount, 0);
    });
  });

  group('Tracelet Kalman Filter integration', () {
    late MockTraceletPlatform mockPlatform;

    setUp(() {
      mockPlatform = MockTraceletPlatform();
      TraceletPlatform.instance = mockPlatform;
    });

    test('ready with useKalmanFilter: true enables filter', () async {
      const config = Config(
        geo: GeoConfig(filter: LocationFilter(useKalmanFilter: true)),
      );

      expect(Tracelet.isKalmanFilterEnabled, isFalse);

      await Tracelet.ready(config);

      expect(Tracelet.isKalmanFilterEnabled, isTrue);
    });

    test('ready with useKalmanFilter: false disables filter', () async {
      const config = Config();

      await Tracelet.ready(config);

      expect(Tracelet.isKalmanFilterEnabled, isFalse);
    });

    test('setConfig updates useKalmanFilter setting', () async {
      const configWithFilter = Config(
        geo: GeoConfig(filter: LocationFilter(useKalmanFilter: true)),
      );

      const configWithoutFilter = Config();

      await Tracelet.ready(configWithoutFilter);
      expect(Tracelet.isKalmanFilterEnabled, isFalse);

      await Tracelet.setConfig(configWithFilter);
      expect(Tracelet.isKalmanFilterEnabled, isTrue);

      // #321: setConfig() is a partial update. An empty Config says nothing
      // about the filter, so it must NOT switch it back off — that silent
      // reset is the bug. Turning it off takes an explicit `false`.
      await Tracelet.setConfig(configWithoutFilter);
      expect(Tracelet.isKalmanFilterEnabled, isTrue);

      await Tracelet.setConfig(
        const Config(
          geo: GeoConfig(filter: LocationFilter(useKalmanFilter: false)),
        ),
      );
      expect(Tracelet.isKalmanFilterEnabled, isFalse);
    });
  });
}

class MockTraceletPlatform extends TraceletPlatform
    with EmptyEventStreamsMixin {
  TlDesiredAccuracy? lastProviderDesiredAccuracy;
  double? lastProviderDistanceFilter;
  int providerOptionsCallCount = 0;

  final Map<String, Object?> stateResult = {
    'enabled': false,
    'trackingMode': 0,
    'isMoving': false,
    'schedulerEnabled': false,
    'odometer': 0.0,
  };

  @override
  Future<Map<String, Object?>> ready(TlConfig config) async {
    return Map<String, Object?>.from(stateResult);
  }

  @override
  Future<Map<String, Object?>> setConfig(TlConfig config) async {
    return Map<String, Object?>.from(stateResult);
  }

  @override
  Future<bool> updateLocationProviderOptions(
    TlDesiredAccuracy? desiredAccuracy,
    double? distanceFilter,
  ) async {
    providerOptionsCallCount++;
    lastProviderDesiredAccuracy = desiredAccuracy;
    lastProviderDistanceFilter = distanceFilter;
    return true;
  }
}

mixin EmptyEventStreamsMixin on TraceletPlatform {
  @override
  Stream<TlLocation> get locationEvents => const Stream.empty();
  @override
  Stream<TlLocation> get motionChangeEvents => const Stream.empty();
  @override
  Stream<TlActivityChangeEvent> get activityChangeEvents =>
      const Stream.empty();
  @override
  Stream<TlProviderChangeEvent> get providerChangeEvents =>
      const Stream.empty();
  @override
  Stream<TlGeofenceEvent> get geofenceEvents => const Stream.empty();
  @override
  Stream<TlGeofencesChangeEvent> get geofencesChangeEvents =>
      const Stream.empty();
  @override
  Stream<TlHeartbeatEvent> get heartbeatEvents => const Stream.empty();
  @override
  Stream<TlHttpEvent> get httpEvents => const Stream.empty();
  @override
  Stream<TlState> get scheduleEvents => const Stream.empty();
  @override
  Stream<bool> get powerSaveChangeEvents => const Stream.empty();
  @override
  Stream<TlConnectivityChangeEvent> get connectivityChangeEvents =>
      const Stream.empty();
  @override
  Stream<bool> get enabledChangeEvents => const Stream.empty();
  @override
  Stream<String> get notificationActionEvents => const Stream.empty();
  @override
  Stream<TlAuthorizationEvent> get authorizationEvents => const Stream.empty();
  @override
  Stream<TlLocation> get watchPositionEvents => const Stream.empty();
  @override
  Stream<Map<String?, Object?>> get remoteConfigEvents => const Stream.empty();
}
