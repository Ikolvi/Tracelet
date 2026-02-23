import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

void main() {
  test('TraceletPlatform instance defaults to MethodChannelTracelet', () {
    expect(TraceletPlatform.instance, isA<MethodChannelTracelet>());
  });

  test('TraceletEvents has correct base path', () {
    expect(TraceletEvents.location, 'com.tracelet/events/location');
  });

  test('DesiredAccuracy enum has expected values', () {
    expect(DesiredAccuracy.values.length, 5);
    expect(DesiredAccuracy.high.index, 0);
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
  });
}

/// A bare TraceletPlatform subclass for testing default behavior.
class _TestPlatform extends TraceletPlatform {}
