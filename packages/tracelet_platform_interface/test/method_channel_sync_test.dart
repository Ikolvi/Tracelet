import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannelTracelet channel;
  final log = <MethodCall>[];

  setUp(() {
    channel = MethodChannelTracelet();
    log.clear();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(TraceletPlatform.methodChannelName),
          (MethodCall call) async {
            log.add(call);
            switch (call.method) {
              case 'setDynamicHeaders':
              case 'setRouteContext':
              case 'clearRouteContext':
              case 'registerHeadlessHeadersCallback':
              case 'registerHeadlessSyncBodyBuilder':
                return true;
              default:
                return null;
            }
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(TraceletPlatform.methodChannelName),
          null,
        );
  });

  group('setDynamicHeaders', () {
    test('invokes correct method channel call', () async {
      final result = await channel.setDynamicHeaders({
        'X-Token': 'abc123',
        'X-Device': 'dev-1',
      });
      expect(result, true);
      expect(log, hasLength(1));
      expect(log.first.method, 'setDynamicHeaders');
      expect(log.first.arguments, {'X-Token': 'abc123', 'X-Device': 'dev-1'});
    });

    test('returns false when native returns null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(TraceletPlatform.methodChannelName),
            (MethodCall call) async => null,
          );
      final result = await channel.setDynamicHeaders({'key': 'val'});
      expect(result, false);
    });
  });

  group('setRouteContext', () {
    test('invokes correct method channel call', () async {
      final context = <String, Object?>{
        'taskId': 'delivery-42',
        'driverId': 'driver-7',
      };
      final result = await channel.setRouteContext(context);
      expect(result, true);
      expect(log, hasLength(1));
      expect(log.first.method, 'setRouteContext');
      expect(log.first.arguments, context);
    });
  });

  group('clearRouteContext', () {
    test('invokes correct method channel call', () async {
      final result = await channel.clearRouteContext();
      expect(result, true);
      expect(log, hasLength(1));
      expect(log.first.method, 'clearRouteContext');
      expect(log.first.arguments, isNull);
    });
  });

  group('registerHeadlessHeadersCallback', () {
    test('invokes correct method channel call with callback IDs', () async {
      final result = await channel.registerHeadlessHeadersCallback([100, 200]);
      expect(result, true);
      expect(log, hasLength(1));
      expect(log.first.method, 'registerHeadlessHeadersCallback');
      expect(log.first.arguments, [100, 200]);
    });
  });

  group('registerHeadlessSyncBodyBuilder', () {
    test('invokes correct method channel call with callback IDs', () async {
      final result = await channel.registerHeadlessSyncBodyBuilder([300, 400]);
      expect(result, true);
      expect(log, hasLength(1));
      expect(log.first.method, 'registerHeadlessSyncBodyBuilder');
      expect(log.first.arguments, [300, 400]);
    });
  });
}
