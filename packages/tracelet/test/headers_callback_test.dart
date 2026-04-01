import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet/tracelet.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

import 'permission_degradation_test.dart' show EmptyEventStreamsMixin;

/// Mock platform that records setDynamicHeaders calls.
class _MockPlatform extends TraceletPlatform with EmptyEventStreamsMixin {
  final List<Map<String, String>> dynamicHeaderCalls = [];

  @override
  Future<bool> setDynamicHeaders(Map<String, String> headers) async {
    dynamicHeaderCalls.add(Map<String, String>.from(headers));
    return true;
  }

  @override
  Future<Map<String, Object?>> ready(Map<String, Object?> config) async {
    return {'enabled': false, 'trackingMode': 0};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const syncBodyChannel = MethodChannel('com.tracelet/sync_body');

  late _MockPlatform mockPlatform;

  setUp(() {
    mockPlatform = _MockPlatform();
    TraceletPlatform.instance = mockPlatform;

    // Ensure the MethodChannel handler is set up before each test.
    // Setting a non-null headers callback triggers _ensureSyncBodyChannel.
    Tracelet.setHeadersCallback(null);
    Tracelet.setTokenRefreshCallback(null);
    Tracelet.setSyncBodyBuilder(null);
  });

  tearDown(() {
    Tracelet.setHeadersCallback(null);
    Tracelet.setTokenRefreshCallback(null);
    Tracelet.setSyncBodyBuilder(null);
  });

  // ==========================================================================
  // requestFreshHeaders — MethodChannel flow
  // ==========================================================================
  group('requestFreshHeaders (foreground MethodChannel)', () {
    test('invokes headersCallback and pushes headers to native', () async {
      Tracelet.setHeadersCallback(() async {
        return {'Authorization': 'Bearer token-123', 'X-Device': 'dev-1'};
      });

      final result = await _invokeMethod(
        syncBodyChannel,
        'requestFreshHeaders',
        null,
      );

      expect(result, true);
      expect(mockPlatform.dynamicHeaderCalls, hasLength(1));
      expect(
        mockPlatform.dynamicHeaderCalls.first['Authorization'],
        'Bearer token-123',
      );
      expect(mockPlatform.dynamicHeaderCalls.first['X-Device'], 'dev-1');
    });

    test('returns false when no headersCallback is registered', () async {
      // Ensure channel is set up (via another callback)
      Tracelet.setSyncBodyBuilder(
        (SyncBodyContext ctx) async => <String, Object?>{},
      );

      final result = await _invokeMethod(
        syncBodyChannel,
        'requestFreshHeaders',
        null,
      );

      expect(result, false);
      expect(mockPlatform.dynamicHeaderCalls, isEmpty);
    });

    test('clears callback returns false on subsequent calls', () async {
      Tracelet.setHeadersCallback(() async {
        return {'Authorization': 'Bearer active'};
      });

      // First call should succeed
      var result = await _invokeMethod(
        syncBodyChannel,
        'requestFreshHeaders',
        null,
      );
      expect(result, true);

      // Clear the callback
      Tracelet.setHeadersCallback(null);
      // Must set another callback to keep the channel alive
      Tracelet.setSyncBodyBuilder(
        (SyncBodyContext ctx) async => <String, Object?>{},
      );

      // Second call should return false
      result = await _invokeMethod(
        syncBodyChannel,
        'requestFreshHeaders',
        null,
      );
      expect(result, false);
    });

    test('callback can return different headers on each invocation', () async {
      var callCount = 0;
      Tracelet.setHeadersCallback(() async {
        callCount++;
        return {'Authorization': 'Bearer token-$callCount'};
      });

      await _invokeMethod(syncBodyChannel, 'requestFreshHeaders', null);
      await _invokeMethod(syncBodyChannel, 'requestFreshHeaders', null);

      expect(mockPlatform.dynamicHeaderCalls, hasLength(2));
      expect(
        mockPlatform.dynamicHeaderCalls[0]['Authorization'],
        'Bearer token-1',
      );
      expect(
        mockPlatform.dynamicHeaderCalls[1]['Authorization'],
        'Bearer token-2',
      );
    });
  });

  // ==========================================================================
  // requestTokenRefresh — MethodChannel flow (401 recovery)
  // ==========================================================================
  group('requestTokenRefresh (foreground MethodChannel)', () {
    test('invokes tokenRefreshCallback and pushes headers to native', () async {
      Tracelet.setTokenRefreshCallback(() async {
        return {'Authorization': 'Bearer refreshed-token', 'X-Retry': 'true'};
      });

      final result = await _invokeMethod(
        syncBodyChannel,
        'requestTokenRefresh',
        null,
      );

      expect(result, true);
      expect(mockPlatform.dynamicHeaderCalls, hasLength(1));
      expect(
        mockPlatform.dynamicHeaderCalls.first['Authorization'],
        'Bearer refreshed-token',
      );
    });

    test('returns false when no tokenRefreshCallback is registered', () async {
      // Ensure channel is set up (via headers callback)
      Tracelet.setHeadersCallback(() async => <String, String>{});

      final result = await _invokeMethod(
        syncBodyChannel,
        'requestTokenRefresh',
        null,
      );

      expect(result, false);
      // Only the headers callback should be in dynamic calls, not token refresh
    });

    test(
      'token refresh callback works independently from headers callback',
      () async {
        Tracelet.setHeadersCallback(() async {
          return {'Authorization': 'Bearer original'};
        });
        Tracelet.setTokenRefreshCallback(() async {
          return {'Authorization': 'Bearer refreshed'};
        });

        // Call headers first
        await _invokeMethod(syncBodyChannel, 'requestFreshHeaders', null);
        expect(mockPlatform.dynamicHeaderCalls, hasLength(1));
        expect(
          mockPlatform.dynamicHeaderCalls.last['Authorization'],
          'Bearer original',
        );

        // Then token refresh
        await _invokeMethod(syncBodyChannel, 'requestTokenRefresh', null);
        expect(mockPlatform.dynamicHeaderCalls, hasLength(2));
        expect(
          mockPlatform.dynamicHeaderCalls.last['Authorization'],
          'Bearer refreshed',
        );
      },
    );
  });
}

// =============================================================================
// Helpers
// =============================================================================

/// Simulate native → Dart MethodChannel call.
Future<Object?> _invokeMethod(
  MethodChannel channel,
  String method,
  Object? arguments,
) async {
  Object? result;

  final encoded = channel.codec.encodeMethodCall(MethodCall(method, arguments));

  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(channel.name, encoded, (ByteData? response) {
        if (response != null) {
          try {
            result = channel.codec.decodeEnvelope(response);
          } catch (_) {
            result = null;
          }
        }
      });

  // Give async handler time to complete
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);

  return result;
}
