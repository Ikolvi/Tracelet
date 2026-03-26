import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('TraceletPlatform instance defaults to PigeonTracelet', () {
    expect(TraceletPlatform.instance, isA<PigeonTracelet>());
  });

  test('TraceletEvents has correct base path', () {
    expect(TraceletEvents.location, 'com.tracelet/events/location');
  });

  test('DesiredAccuracy enum has expected values', () {
    expect(DesiredAccuracy.values.length, 5);
    expect(DesiredAccuracy.high.index, 0);
  });

  test('TrackingMode enum includes periodic', () {
    expect(TrackingMode.values.length, 3);
    expect(TrackingMode.location.index, 0);
    expect(TrackingMode.geofences.index, 1);
    expect(TrackingMode.periodic.index, 2);
  });

  group('TraceletPlatform abstract methods', () {
    test('getCurrentPosition throws UnimplementedError by default', () {
      final platform = _TestPlatform();
      expect(
        () => platform.getCurrentPosition({}),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('getLastKnownLocation throws UnimplementedError by default', () {
      final platform = _TestPlatform();
      expect(
        () => platform.getLastKnownLocation(),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('getLastKnownLocation with options throws UnimplementedError', () {
      final platform = _TestPlatform();
      expect(
        () => platform.getLastKnownLocation({'persist': true}),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('startPeriodic throws UnimplementedError by default', () {
      final platform = _TestPlatform();
      expect(
        () => platform.startPeriodic(),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('getLocations throws UnimplementedError by default', () {
      final platform = _TestPlatform();
      expect(() => platform.getLocations(), throwsA(isA<UnimplementedError>()));
    });

    test('getLocations accepts optional query map', () {
      final platform = _TestPlatform();
      expect(
        () => platform.getLocations({'start': 1000, 'end': 2000, 'limit': 10}),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('getCount throws UnimplementedError by default', () {
      final platform = _TestPlatform();
      expect(() => platform.getCount(), throwsA(isA<UnimplementedError>()));
    });

    test('getCount accepts optional query map', () {
      final platform = _TestPlatform();
      expect(
        () => platform.getCount({'start': 1000, 'end': 2000}),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('setDynamicHeaders throws UnimplementedError by default', () {
      final platform = _TestPlatform();
      expect(
        () => platform.setDynamicHeaders({'X-Token': 'abc'}),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('setRouteContext throws UnimplementedError by default', () {
      final platform = _TestPlatform();
      expect(
        () => platform.setRouteContext({'taskId': 'task-1'}),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('clearRouteContext throws UnimplementedError by default', () {
      final platform = _TestPlatform();
      expect(
        () => platform.clearRouteContext(),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test(
      'registerHeadlessHeadersCallback throws UnimplementedError by default',
      () {
        final platform = _TestPlatform();
        expect(
          () => platform.registerHeadlessHeadersCallback([1, 2]),
          throwsA(isA<UnimplementedError>()),
        );
      },
    );

    test(
      'registerHeadlessSyncBodyBuilder throws UnimplementedError by default',
      () {
        final platform = _TestPlatform();
        expect(
          () => platform.registerHeadlessSyncBodyBuilder([1, 2]),
          throwsA(isA<UnimplementedError>()),
        );
      },
    );
  });
}

/// A bare TraceletPlatform subclass for testing default behavior.
class _TestPlatform extends TraceletPlatform {}
