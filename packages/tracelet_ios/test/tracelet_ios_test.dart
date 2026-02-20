import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet_ios/tracelet_ios.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registerWith sets TraceletIos as platform instance', () {
    TraceletIos.registerWith();
    expect(TraceletPlatform.instance, isA<TraceletIos>());
  });

  test('TraceletIos extends MethodChannelTracelet', () {
    final ios = TraceletIos();
    expect(ios, isA<MethodChannelTracelet>());
  });
}
