import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet/tracelet.dart';

void main() {
  // ==========================================================================
  // AuditConfig
  // ==========================================================================
  group('AuditConfig', () {
    test('has sensible defaults', () {
      const config = AuditConfig();
      expect(config.enabled, false);
      expect(config.hashAlgorithm, HashAlgorithm.sha256);
      expect(config.includeExtrasInHash, false);
    });

    test('custom values', () {
      const config = AuditConfig(
        enabled: true,
        hashAlgorithm: HashAlgorithm.sha512,
        includeExtrasInHash: true,
      );
      expect(config.enabled, true);
      expect(config.hashAlgorithm, HashAlgorithm.sha512);
      expect(config.includeExtrasInHash, true);
    });

    test('round-trip serialization preserves all fields', () {
      const original = AuditConfig(
        enabled: true,
        hashAlgorithm: HashAlgorithm.sha256,
        includeExtrasInHash: true,
      );

      final map = original.toMap();
      final restored = AuditConfig.fromMap(map);

      expect(restored.enabled, true);
      expect(restored.hashAlgorithm, HashAlgorithm.sha256);
      expect(restored.includeExtrasInHash, true);
    });

    test('fromMap with defaults when keys missing', () {
      final restored = AuditConfig.fromMap(const <String, Object?>{});
      expect(restored.enabled, false);
      expect(restored.hashAlgorithm, HashAlgorithm.sha256);
      expect(restored.includeExtrasInHash, false);
    });

    test('toMap produces expected keys', () {
      const config = AuditConfig(enabled: true);
      final map = config.toMap();
      expect(map.containsKey('auditEnabled'), true);
      expect(map.containsKey('hashAlgorithm'), true);
      expect(map.containsKey('includeExtrasInHash'), true);
      expect(map['auditEnabled'], true);
    });

    test('equality', () {
      const a = AuditConfig(enabled: true, hashAlgorithm: HashAlgorithm.sha256);
      const b = AuditConfig(enabled: true, hashAlgorithm: HashAlgorithm.sha256);
      const c = AuditConfig(
        enabled: false,
        hashAlgorithm: HashAlgorithm.sha256,
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('hashCode consistent with equality', () {
      const a = AuditConfig(enabled: true);
      const b = AuditConfig(enabled: true);
      expect(a.hashCode, b.hashCode);
    });

    test('toString contains class name', () {
      const config = AuditConfig(enabled: true);
      expect(config.toString(), contains('AuditConfig'));
      expect(config.toString(), contains('enabled: true'));
    });
  });

  // ==========================================================================
  // AuditProof
  // ==========================================================================
  group('AuditProof', () {
    test('fromMap with snake_case keys', () {
      final proof = AuditProof.fromMap(const {
        'uuid': 'loc-uuid-1',
        'hash': 'abc123hash',
        'previous_hash': 'genesis_hash',
        'chain_index': 0,
        'timestamp': '2024-06-15T10:30:00.000Z',
      });

      expect(proof.uuid, 'loc-uuid-1');
      expect(proof.hash, 'abc123hash');
      expect(proof.previousHash, 'genesis_hash');
      expect(proof.chainIndex, 0);
      expect(proof.timestamp, '2024-06-15T10:30:00.000Z');
    });

    test('fromMap with camelCase keys', () {
      final proof = AuditProof.fromMap(const {
        'uuid': 'loc-uuid-2',
        'hash': 'def456hash',
        'previousHash': 'prev_hash',
        'chainIndex': 5,
        'timestamp': '2024-06-15T11:00:00.000Z',
      });

      expect(proof.previousHash, 'prev_hash');
      expect(proof.chainIndex, 5);
    });

    test('round-trip serialization', () {
      final original = AuditProof.fromMap(const {
        'uuid': 'rt-uuid',
        'hash': 'some_hash',
        'previous_hash': 'prev',
        'chain_index': 42,
        'timestamp': '2024-01-01T00:00:00Z',
      });

      final map = original.toMap();
      final restored = AuditProof.fromMap(map);

      expect(restored.uuid, 'rt-uuid');
      expect(restored.hash, 'some_hash');
      expect(restored.previousHash, 'prev');
      expect(restored.chainIndex, 42);
      expect(restored.timestamp, '2024-01-01T00:00:00Z');
    });

    test('toMap produces expected keys', () {
      final proof = AuditProof.fromMap(const {
        'uuid': 'keys-test',
        'hash': 'h',
        'previous_hash': 'ph',
        'chain_index': 1,
        'timestamp': 't',
      });
      final map = proof.toMap();
      expect(map.containsKey('uuid'), true);
      expect(map.containsKey('hash'), true);
      expect(map.containsKey('previous_hash'), true);
      expect(map.containsKey('chain_index'), true);
      expect(map.containsKey('timestamp'), true);
    });

    test('toString contains class name', () {
      final proof = AuditProof.fromMap(const {
        'uuid': 'str-test',
        'hash': 'h',
        'previous_hash': 'ph',
        'chain_index': 0,
        'timestamp': 't',
      });
      expect(proof.toString(), contains('AuditProof'));
    });
  });

  // ==========================================================================
  // AuditVerification
  // ==========================================================================
  group('AuditVerification', () {
    test('fromMap valid chain', () {
      final verification = AuditVerification.fromMap(const {
        'is_valid': true,
        'total_records': 100,
        'verified_records': 100,
      });

      expect(verification.isValid, true);
      expect(verification.totalRecords, 100);
      expect(verification.verifiedRecords, 100);
      expect(verification.brokenAtIndex, isNull);
      expect(verification.brokenAtUuid, isNull);
      expect(verification.error, isNull);
    });

    test('fromMap broken chain', () {
      final verification = AuditVerification.fromMap(const {
        'is_valid': false,
        'total_records': 50,
        'verified_records': 25,
        'broken_at_index': 25,
        'broken_at_uuid': 'corrupt-uuid',
        'error': 'Hash mismatch at index 25',
      });

      expect(verification.isValid, false);
      expect(verification.totalRecords, 50);
      expect(verification.verifiedRecords, 25);
      expect(verification.brokenAtIndex, 25);
      expect(verification.brokenAtUuid, 'corrupt-uuid');
      expect(verification.error, 'Hash mismatch at index 25');
    });

    test('fromMap with camelCase keys', () {
      final verification = AuditVerification.fromMap(const {
        'isValid': true,
        'totalRecords': 10,
        'verifiedRecords': 10,
      });

      expect(verification.isValid, true);
      expect(verification.totalRecords, 10);
    });

    test('fromMap broken chain with camelCase keys', () {
      final verification = AuditVerification.fromMap(const {
        'isValid': false,
        'totalRecords': 5,
        'verifiedRecords': 3,
        'brokenAtIndex': 3,
        'brokenAtUuid': 'broken-uuid',
        'error': 'Linkage failure',
      });

      expect(verification.brokenAtIndex, 3);
      expect(verification.brokenAtUuid, 'broken-uuid');
    });

    test('round-trip serialization valid', () {
      final original = AuditVerification.fromMap(const {
        'is_valid': true,
        'total_records': 200,
        'verified_records': 200,
      });

      final map = original.toMap();
      final restored = AuditVerification.fromMap(map);

      expect(restored.isValid, true);
      expect(restored.totalRecords, 200);
      expect(restored.verifiedRecords, 200);
    });

    test('round-trip serialization broken', () {
      final original = AuditVerification.fromMap(const {
        'is_valid': false,
        'total_records': 40,
        'verified_records': 20,
        'broken_at_index': 20,
        'broken_at_uuid': 'bad-uuid',
        'error': 'Chain linkage broken',
      });

      final map = original.toMap();
      final restored = AuditVerification.fromMap(map);

      expect(restored.isValid, false);
      expect(restored.brokenAtIndex, 20);
      expect(restored.brokenAtUuid, 'bad-uuid');
      expect(restored.error, 'Chain linkage broken');
    });

    test('toString contains class name', () {
      final v = AuditVerification.fromMap(const {
        'is_valid': true,
        'total_records': 0,
        'verified_records': 0,
      });
      expect(v.toString(), contains('AuditVerification'));
    });

    test('empty chain is valid', () {
      final v = AuditVerification.fromMap(const {
        'is_valid': true,
        'total_records': 0,
        'verified_records': 0,
      });
      expect(v.isValid, true);
      expect(v.totalRecords, 0);
    });
  });

  // ==========================================================================
  // Config.audit integration
  // ==========================================================================
  group('Config.audit', () {
    test('default Config has audit disabled', () {
      const config = Config();
      expect(config.audit.enabled, false);
      expect(config.audit.hashAlgorithm, HashAlgorithm.sha256);
    });

    test('Config with audit enabled round-trips', () {
      const config = Config(
        audit: AuditConfig(enabled: true, includeExtrasInHash: true),
      );

      final map = config.toMap();
      final restored = Config.fromMap(map);

      expect(restored.audit.enabled, true);
      expect(restored.audit.includeExtrasInHash, true);
      expect(restored.audit.hashAlgorithm, HashAlgorithm.sha256);
    });

    test('Config equality includes audit', () {
      const a = Config(audit: AuditConfig(enabled: true));
      const b = Config(audit: AuditConfig(enabled: true));
      const c = Config(audit: AuditConfig(enabled: false));
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('Config toMap includes audit section', () {
      const config = Config(audit: AuditConfig(enabled: true));
      final map = config.toMap();
      expect(map.containsKey('audit'), true);
      final auditMap = map['audit'] as Map<String, Object?>;
      expect(auditMap['auditEnabled'], true);
    });
  });

  // ==========================================================================
  // Location audit fields
  // ==========================================================================
  group('Location audit fields', () {
    test('audit fields default to null', () {
      final loc = Location.fromMap(const {
        'uuid': 'no-audit',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': false,
        'odometer': 0.0,
        'coords': {'latitude': 0.0, 'longitude': 0.0},
      });

      expect(loc.auditHash, isNull);
      expect(loc.auditPreviousHash, isNull);
      expect(loc.auditChainIndex, isNull);
    });

    test('audit fields parsed from snake_case keys', () {
      final loc = Location.fromMap(const {
        'uuid': 'audit-snake',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': false,
        'odometer': 0.0,
        'coords': {'latitude': 0.0, 'longitude': 0.0},
        'audit_hash': 'sha256_hash_value',
        'audit_previous_hash': 'previous_sha256',
        'audit_chain_index': 42,
      });

      expect(loc.auditHash, 'sha256_hash_value');
      expect(loc.auditPreviousHash, 'previous_sha256');
      expect(loc.auditChainIndex, 42);
    });

    test('audit fields parsed from camelCase keys', () {
      final loc = Location.fromMap(const {
        'uuid': 'audit-camel',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': false,
        'odometer': 0.0,
        'coords': {'latitude': 0.0, 'longitude': 0.0},
        'auditHash': 'hash_value',
        'auditPreviousHash': 'prev_value',
        'auditChainIndex': 10,
      });

      expect(loc.auditHash, 'hash_value');
      expect(loc.auditPreviousHash, 'prev_value');
      expect(loc.auditChainIndex, 10);
    });

    test('audit fields included in toMap when non-null', () {
      final loc = Location.fromMap(const {
        'uuid': 'audit-tomap',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': false,
        'odometer': 0.0,
        'coords': {'latitude': 0.0, 'longitude': 0.0},
        'audit_hash': 'hash123',
        'audit_previous_hash': 'prev123',
        'audit_chain_index': 7,
      });

      final map = loc.toMap();
      expect(map['audit_hash'], 'hash123');
      expect(map['audit_previous_hash'], 'prev123');
      expect(map['audit_chain_index'], 7);
    });

    test('audit fields omitted from toMap when null', () {
      final loc = Location.fromMap(const {
        'uuid': 'audit-null',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': false,
        'odometer': 0.0,
        'coords': {'latitude': 0.0, 'longitude': 0.0},
      });

      final map = loc.toMap();
      expect(map.containsKey('audit_hash'), false);
      expect(map.containsKey('audit_previous_hash'), false);
      expect(map.containsKey('audit_chain_index'), false);
    });

    test('audit fields round-trip through toMap/fromMap', () {
      final original = Location.fromMap(const {
        'uuid': 'audit-rt',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': true,
        'odometer': 500.0,
        'coords': {'latitude': 37.7749, 'longitude': -122.4194},
        'audit_hash': 'abcdef1234567890',
        'audit_previous_hash': 'genesis_hash_value',
        'audit_chain_index': 0,
      });

      final map = original.toMap();
      final restored = Location.fromMap(map);

      expect(restored.auditHash, 'abcdef1234567890');
      expect(restored.auditPreviousHash, 'genesis_hash_value');
      expect(restored.auditChainIndex, 0);
    });
  });
}
