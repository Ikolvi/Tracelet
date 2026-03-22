import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tracelet/tracelet.dart';

/// Integration tests for the 401-aware retry mechanism.
///
/// Validates:
/// - [HttpEvent] correctly serializes `isRetry` for 401 retry scenarios
/// - [HttpConfig] retry settings are serialized/deserialized properly
/// - `setDynamicHeaders` API is callable and returns successfully
///
/// Full end-to-end 401 retry flow requires a real server and background
/// execution — see the Android and iOS native unit tests for those paths.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('HttpEvent — 401 retry metadata', () {
    testWidgets('HttpEvent parses isRetry=true for auth retry', (tester) async {
      final event = HttpEvent.fromMap(const {
        'success': true,
        'status': 200,
        'responseText': '{"ok":true}',
        'isRetry': true,
        'retryCount': 0,
      });

      expect(event.success, isTrue);
      expect(event.status, 200);
      expect(event.isRetry, isTrue);
      expect(event.retryCount, 0);
    });

    testWidgets('HttpEvent 401 failure round-trips through toMap/fromMap', (
      tester,
    ) async {
      const original = HttpEvent(
        success: false,
        status: 401,
        responseText: '{"error":"unauthorized"}',
        isRetry: false,
        retryCount: 0,
      );

      final map = original.toMap();
      expect(map['success'], isFalse);
      expect(map['status'], 401);
      expect(map['isRetry'], isFalse);

      final restored = HttpEvent.fromMap(map);
      expect(restored, original);
    });

    testWidgets('HttpEvent distinguishes initial 401 from retry success', (
      tester,
    ) async {
      // First event: the 401 failure
      const failure = HttpEvent(
        success: false,
        status: 401,
        responseText: '{"error":"token expired"}',
        isRetry: false,
        retryCount: 0,
      );

      // Second event: successful retry after headers refresh
      const retrySuccess = HttpEvent(
        success: true,
        status: 200,
        responseText: '{"ok":true}',
        isRetry: true,
        retryCount: 0,
      );

      expect(failure.success, isFalse);
      expect(failure.isRetry, isFalse);
      expect(retrySuccess.success, isTrue);
      expect(retrySuccess.isRetry, isTrue);
      expect(failure, isNot(retrySuccess));
    });
  });

  group('HttpConfig — retry settings serialization', () {
    testWidgets('maxRetries defaults to 10', (tester) async {
      const config = HttpConfig();
      expect(config.maxRetries, 10);
    });

    testWidgets('retry backoff settings serialize correctly', (tester) async {
      const config = HttpConfig(
        maxRetries: 5,
        retryBackoffBase: 2000,
        retryBackoffCap: 120000,
      );
      final map = config.toMap();

      expect(map['maxRetries'], 5);
      expect(map['retryBackoffBase'], 2000);
      expect(map['retryBackoffCap'], 120000);
    });

    testWidgets('zero maxRetries disables retry', (tester) async {
      const config = HttpConfig(maxRetries: 0);
      expect(config.maxRetries, 0);
      expect(config.toMap()['maxRetries'], 0);
    });
  });

  group('setDynamicHeaders — API contract', () {
    testWidgets('setDynamicHeaders accepts token map', (tester) async {
      // This calls through to the platform channel, verifying the
      // Dart→Native round-trip doesn't throw
      final result = await Tracelet.setDynamicHeaders({
        'Authorization': 'Bearer test-jwt-token-abc123',
      });
      expect(result, isTrue);
    });

    testWidgets('setDynamicHeaders accepts empty map to clear', (tester) async {
      final result = await Tracelet.setDynamicHeaders({});
      expect(result, isTrue);
    });

    testWidgets('setDynamicHeaders accepts multiple headers', (tester) async {
      final result = await Tracelet.setDynamicHeaders({
        'Authorization': 'Bearer refreshed-token',
        'X-Request-ID': 'req-12345',
        'X-Custom-Header': 'custom-value',
      });
      expect(result, isTrue);
    });
  });
}
