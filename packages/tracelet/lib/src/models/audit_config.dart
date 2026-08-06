import 'package:meta/meta.dart';
import 'package:tracelet/src/models/_helpers.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

// ---------------------------------------------------------------------------
// AuditConfig
// ---------------------------------------------------------------------------

/// **Enterprise** — Tamper-proof location audit trail configuration.
///
/// When enabled, every persisted location record is hashed with SHA-256
/// and chained to the previous record's hash — creating a blockchain-like
/// chain of custody that cryptographically proves no records were inserted,
/// deleted, or modified.
///
/// ## How It Works
///
/// 1. Each location record produces a **canonical string** from its key
///    fields (lat, lng, timestamp, accuracy, speed, heading, altitude,
///    odometer, uuid, isMoving).
/// 2. The canonical string is prepended with the **previous record's hash**
///    and fed into SHA-256.
/// 3. The resulting hash is stored alongside the location in the database.
/// 4. The first record in the chain uses a **genesis hash** derived from
///    a device-specific identifier.
///
/// ## Verification
///
/// Call [Tracelet.verifyAuditTrail()] to walk the entire chain and verify
/// every link. If any record has been inserted, deleted, or modified, the
/// chain breaks at the tampered record.
///
/// ## Use Cases
///
/// - **Delivery proof**: Prove a driver was at a location at a specific time.
/// - **Employee tracking compliance**: Tamper-proof attendance trails.
/// - **Insurance claims**: Verifiable location evidence.
/// - **Regulatory audits**: Chain-of-custody for HIPAA, SOX, GDPR.
/// - **Legal evidence**: Cryptographic proof of data integrity.
///
/// ## HTTP Sync
///
/// When audit trail is enabled, HTTP sync payloads automatically include
/// `audit_hash`, `audit_previous_hash`, and `audit_chain_index` fields,
/// enabling server-side verification.
///
/// ```dart
/// Config(
///   audit: AuditConfig(
///     enabled: true,
///     hashAlgorithm: HashAlgorithm.sha256,
///   ),
/// )
/// ```
///
/// See the [Audit Trail Guide](../../help/AUDIT-TRAIL.md) for full details.
@immutable
class AuditConfig {
  /// Creates a new [AuditConfig].
  const AuditConfig({
    this.enabled = false,
    this.hashAlgorithm = HashAlgorithm.sha256,
    @Deprecated(
      'Never implemented — the audit chain always hashes core location fields '
      'only, so this flag changes nothing. Enabling it needs a versioned chain '
      'migration. Will be removed in a future major version (#304).',
    )
    this.includeExtrasInHash = false,
  });

  /// Creates an [AuditConfig] from a map.
  factory AuditConfig.fromMap(Map<String, Object?> map) {
    return AuditConfig(
      enabled: ensureBool(
        map['auditEnabled'] ?? map['enabled'],
        fallback: false,
      ),
      hashAlgorithm: _parseHashAlgorithm(map['hashAlgorithm']),
      includeExtrasInHash: ensureBool(
        map['includeExtrasInHash'],
        fallback: false,
      ),
    );
  }

  /// Whether the tamper-proof audit trail is enabled.
  ///
  /// When `true`, every persisted location is hashed and chained.
  /// Defaults to `false`.
  final bool enabled;

  /// The hash algorithm used for the audit chain.
  ///
  /// Currently only [HashAlgorithm.sha256] is supported. This field exists
  /// for future extensibility (SHA-384, SHA-512).
  ///
  /// Defaults to [HashAlgorithm.sha256].
  final HashAlgorithm hashAlgorithm;

  /// Whether to include the `extras` map in the hash computation.
  ///
  /// **Not implemented.** The flag is serialized and stored but no platform
  /// reads it (#304): the audit chain always hashes the core location fields
  /// only, so `true` and `false` produce identical chains. Setting it has never
  /// had any effect.
  ///
  /// Wiring it up is not a pure bug fix — changing what goes into the hash
  /// invalidates every previously computed chain, so it needs a chain version
  /// and a migration path rather than a silent behavior change.
  @Deprecated(
    'Never implemented — the audit chain always hashes core location fields '
    'only, so this flag changes nothing. Enabling it needs a versioned chain '
    'migration. Will be removed in a future major version (#304).',
  )
  final bool includeExtrasInHash;

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'auditEnabled': enabled,
      'hashAlgorithm': _hashAlgorithmToString(hashAlgorithm),
      'includeExtrasInHash': includeExtrasInHash,
    };
  }

  /// Converts to Pigeon [TlAuditConfig].
  TlAuditConfig toTlConfig() => TlAuditConfig(
    enabled: enabled,
    // The public [HashAlgorithm] enum has more variants (sha256/sha384/sha512)
    // than the Pigeon [TlHashAlgorithm] currently carries, so indexing it
    // directly threw a fatal RangeError on sha384/sha512 during ready() (#150).
    // Guard the index; unsupported variants fall back to sha256.
    hashAlgorithm: hashAlgorithm.index < TlHashAlgorithm.values.length
        ? TlHashAlgorithm.values[hashAlgorithm.index]
        : TlHashAlgorithm.sha256,
  );

  @override
  String toString() =>
      'AuditConfig(enabled: $enabled, hashAlgorithm: $hashAlgorithm, '
      'includeExtrasInHash: $includeExtrasInHash)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuditConfig &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          hashAlgorithm == other.hashAlgorithm &&
          includeExtrasInHash == other.includeExtrasInHash;

  @override
  int get hashCode => Object.hash(enabled, hashAlgorithm, includeExtrasInHash);
}

/// Parse a hash algorithm value from a native map.
///
/// Accepts the string forms (`'SHA-256'`, `'SHA-384'`, `'SHA-512'`) sent
/// over platform channels and the enum itself.
HashAlgorithm _parseHashAlgorithm(Object? value) {
  if (value is HashAlgorithm) return value;
  if (value is String) {
    switch (value) {
      case 'SHA-384':
        return HashAlgorithm.sha384;
      case 'SHA-512':
        return HashAlgorithm.sha512;
      case 'SHA-256':
      default:
        return HashAlgorithm.sha256;
    }
  }
  return HashAlgorithm.sha256;
}

/// Serialize a [HashAlgorithm] to the string format expected by native code.
String _hashAlgorithmToString(HashAlgorithm algorithm) {
  switch (algorithm) {
    case HashAlgorithm.sha256:
      return 'SHA-256';
    case HashAlgorithm.sha384:
      return 'SHA-384';
    case HashAlgorithm.sha512:
      return 'SHA-512';
  }
}
