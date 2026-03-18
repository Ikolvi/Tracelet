import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet/tracelet.dart';

void main() {
  // ==========================================================================
  // SecurityConfig
  // ==========================================================================
  group('SecurityConfig', () {
    test('has sensible defaults', () {
      const config = SecurityConfig();
      expect(config.encryptDatabase, false);
      expect(config.encryptionKey, isNull);
    });

    test('round-trip serialization preserves all fields', () {
      const config = SecurityConfig(
        encryptDatabase: true,
        encryptionKey: 'my-secret-key',
      );
      final map = config.toMap();
      final restored = SecurityConfig.fromMap(map);
      expect(restored, equals(config));
      expect(restored.encryptDatabase, true);
      expect(restored.encryptionKey, 'my-secret-key');
    });

    test('fromMap with empty map uses defaults', () {
      final config = SecurityConfig.fromMap({});
      expect(config.encryptDatabase, false);
      expect(config.encryptionKey, isNull);
    });

    test('fromMap accepts snake_case keys', () {
      final config = SecurityConfig.fromMap({'encrypt_database': true});
      expect(config.encryptDatabase, true);
    });

    test('equality and hashCode', () {
      const a = SecurityConfig(encryptDatabase: true);
      const b = SecurityConfig(encryptDatabase: true);
      const c = SecurityConfig(encryptDatabase: false);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('toString masks encryption key', () {
      const config = SecurityConfig(
        encryptDatabase: true,
        encryptionKey: 'secret',
      );
      expect(config.toString(), contains('***'));
      expect(config.toString(), isNot(contains('secret')));
    });
  });

  // ==========================================================================
  // AttestationConfig
  // ==========================================================================
  group('AttestationConfig', () {
    test('has sensible defaults', () {
      const config = AttestationConfig();
      expect(config.enabled, false);
      expect(config.refreshInterval, 3600);
      expect(config.verificationUrl, isNull);
    });

    test('round-trip serialization preserves all fields', () {
      const config = AttestationConfig(
        enabled: true,
        refreshInterval: 1800,
        verificationUrl: 'https://verify.example.com',
      );
      final map = config.toMap();
      final restored = AttestationConfig.fromMap(map);
      expect(restored, equals(config));
      expect(restored.enabled, true);
      expect(restored.refreshInterval, 1800);
      expect(restored.verificationUrl, 'https://verify.example.com');
    });

    test('fromMap with empty map uses defaults', () {
      final config = AttestationConfig.fromMap({});
      expect(config.enabled, false);
      expect(config.refreshInterval, 3600);
      expect(config.verificationUrl, isNull);
    });

    test('fromMap accepts prefixed keys', () {
      final config = AttestationConfig.fromMap({
        'attestationEnabled': true,
        'attestationRefreshInterval': 900,
        'attestationVerificationUrl': 'https://attest.example.com',
      });
      expect(config.enabled, true);
      expect(config.refreshInterval, 900);
      expect(config.verificationUrl, 'https://attest.example.com');
    });

    test('fromMap accepts short keys', () {
      final config = AttestationConfig.fromMap({
        'enabled': true,
        'refreshInterval': 600,
        'verificationUrl': 'https://short.example.com',
      });
      expect(config.enabled, true);
      expect(config.refreshInterval, 600);
      expect(config.verificationUrl, 'https://short.example.com');
    });

    test('equality and hashCode', () {
      const a = AttestationConfig(enabled: true, refreshInterval: 1800);
      const b = AttestationConfig(enabled: true, refreshInterval: 1800);
      const c = AttestationConfig(enabled: false, refreshInterval: 1800);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  // ==========================================================================
  // AttestationToken
  // ==========================================================================
  group('AttestationToken', () {
    test('round-trip serialization preserves all fields', () {
      final token = AttestationToken(
        token: 'eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        provider: 'play_integrity',
        verified: true,
      );
      final map = token.toMap();
      final restored = AttestationToken.fromMap(map);
      expect(restored, equals(token));
      expect(restored.token, token.token);
      expect(restored.provider, 'play_integrity');
      expect(restored.verified, true);
    });

    test('fromMap handles null verified', () {
      final token = AttestationToken.fromMap({
        'token': 'abc',
        'timestamp': 1700000000000,
        'provider': 'app_attest',
      });
      expect(token.verified, isNull);
      expect(token.provider, 'app_attest');
    });

    test('fromMap handles missing fields', () {
      final token = AttestationToken.fromMap({});
      expect(token.token, '');
      expect(token.provider, 'unknown');
      expect(token.verified, isNull);
    });

    test('equality compares token, timestamp, provider', () {
      final ts = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final a = AttestationToken(
        token: 'abc',
        timestamp: ts,
        provider: 'play_integrity',
      );
      final b = AttestationToken(
        token: 'abc',
        timestamp: ts,
        provider: 'play_integrity',
        verified: true,
      );
      // verified is NOT part of equality (per the implementation)
      expect(a, equals(b));
    });
  });

  // ==========================================================================
  // Config integration with SecurityConfig & AttestationConfig
  // ==========================================================================
  group('Config with enterprise features', () {
    test('Config includes security and attestation defaults', () {
      const config = Config();
      expect(config.security.encryptDatabase, false);
      expect(config.security.encryptionKey, isNull);
      expect(config.attestation.enabled, false);
      expect(config.attestation.refreshInterval, 3600);
    });

    test('Config round-trip preserves security and attestation', () {
      const config = Config(
        security: SecurityConfig(encryptDatabase: true),
        attestation: AttestationConfig(
          enabled: true,
          refreshInterval: 1800,
          verificationUrl: 'https://verify.example.com',
        ),
      );
      final map = config.toMap();
      final restored = Config.fromMap(map);
      expect(restored.security.encryptDatabase, true);
      expect(restored.attestation.enabled, true);
      expect(restored.attestation.refreshInterval, 1800);
      expect(
        restored.attestation.verificationUrl,
        'https://verify.example.com',
      );
    });

    test('Config equality includes security and attestation', () {
      const a = Config(security: SecurityConfig(encryptDatabase: true));
      const b = Config(security: SecurityConfig(encryptDatabase: true));
      const c = Config(security: SecurityConfig(encryptDatabase: false));
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
