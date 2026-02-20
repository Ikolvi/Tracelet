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
}
