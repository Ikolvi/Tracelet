import 'package:meta/meta.dart';

import '_helpers.dart';

// ---------------------------------------------------------------------------
// SecurityConfig
// ---------------------------------------------------------------------------

/// **Enterprise** — At-rest database encryption configuration.
///
/// When enabled, the plugin encrypts the SQLite database using AES-256
/// via SQLCipher, protecting all stored location history, geofence state,
/// audit trail, and log records at rest.
///
/// ## Key Management
///
/// By default, a secure random key is generated and stored in
/// platform-secure storage:
/// - **Android**: Android Keystore via EncryptedSharedPreferences
/// - **iOS**: iOS Keychain via SecItemAdd / SecItemCopyMatching
/// - **Web**: Not applicable (in-memory storage)
///
/// You can optionally provide your own [encryptionKey] if your app manages
/// its own key material. This is advanced usage — the platform-managed key
/// is recommended for most applications.
///
/// ## Migration
///
/// Existing unencrypted databases are automatically migrated to encrypted
/// when [encryptDatabase] is set to `true`. This is a one-time operation
/// that preserves all existing data.
///
/// ## Compliance
///
/// Satisfies GDPR Art. 32 (encryption of personal data), HIPAA §164.312
/// (encryption at rest), and SOC2 CC6.1 (logical access controls).
///
/// ```dart
/// Config(
///   security: SecurityConfig(
///     encryptDatabase: true,
///   ),
/// )
/// ```
///
/// See the [Compliance Report Guide](../../help/COMPLIANCE-REPORT.md) for
/// how encryption status appears in automated compliance reports.
@immutable
class SecurityConfig {
  /// Creates a new [SecurityConfig].
  const SecurityConfig({this.encryptDatabase = false, this.encryptionKey});

  /// Enable at-rest database encryption.
  ///
  /// When `true`, the SQLite database is encrypted using AES-256 via
  /// SQLCipher. A secure random key is generated and stored in
  /// platform-secure storage (Android Keystore / iOS Keychain) unless
  /// a custom [encryptionKey] is provided.
  ///
  /// Defaults to `false` (plain SQLite for backward compatibility).
  final bool encryptDatabase;

  /// Custom encryption key.
  ///
  /// If `null`, a secure random key is generated and stored in
  /// platform-secure storage (Android Keystore / iOS Keychain).
  ///
  /// Provide this only if your app manages its own key material.
  /// The key must be a non-empty string. It is passed directly to
  /// SQLCipher as the `PRAGMA key`.
  final String? encryptionKey;

  /// Creates a [SecurityConfig] from a map.
  factory SecurityConfig.fromMap(Map<String, Object?> map) {
    return SecurityConfig(
      encryptDatabase: ensureBool(
        map['encryptDatabase'] ?? map['encrypt_database'],
        fallback: false,
      ),
      encryptionKey: map['encryptionKey'] as String?,
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'encryptDatabase': encryptDatabase,
      'encryptionKey': encryptionKey,
    };
  }

  @override
  String toString() =>
      'SecurityConfig(encryptDatabase: $encryptDatabase, '
      'encryptionKey: ${encryptionKey != null ? "***" : "null"})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SecurityConfig &&
          runtimeType == other.runtimeType &&
          encryptDatabase == other.encryptDatabase &&
          encryptionKey == other.encryptionKey;

  @override
  int get hashCode => Object.hash(encryptDatabase, encryptionKey);
}
