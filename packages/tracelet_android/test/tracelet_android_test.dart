import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet_android/tracelet_android.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registerWith sets TraceletAndroid as platform instance', () {
    TraceletAndroid.registerWith();
    expect(TraceletPlatform.instance, isA<TraceletAndroid>());
  });

  test('TraceletAndroid extends MethodChannelTracelet', () {
    final android = TraceletAndroid();
    expect(android, isA<MethodChannelTracelet>());
  });
}
