import 'package:meta/meta.dart';
import 'package:tracelet/src/models/_helpers.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

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
  ///
  /// Omitting a parameter leaves it *unset*: the getter reports the documented
  /// default, and [toMap]/[toTlConfig] skip the field so a partial
  /// `setConfig()` does not overwrite the persisted value (#321).
  const SecurityConfig({bool? encryptDatabase, this.encryptionKey})
    : _encryptDatabase = encryptDatabase;

  /// Creates a [SecurityConfig] from a map.
  ///
  /// A key absent from [map] stays unset, so a `toMap()`/`fromMap()` round trip
  /// preserves which fields were supplied (#321).
  factory SecurityConfig.fromMap(Map<String, Object?> map) {
    final hasEncrypt =
        map.containsKey('encryptDatabase') || map.containsKey('encrypt_database');
    return SecurityConfig(
      encryptDatabase: hasEncrypt
          ? ensureBool(
              map['encryptDatabase'] ?? map['encrypt_database'],
              fallback: false,
            )
          : null,
      encryptionKey: map['encryptionKey'] as String?,
    );
  }

  /// Enable at-rest database encryption.
  ///
  /// When `true`, the SQLite database is encrypted using AES-256 via
  /// SQLCipher. A secure random key is generated and stored in
  /// platform-secure storage (Android Keystore / iOS Keychain) unless
  /// a custom [encryptionKey] is provided.
  ///
  /// Defaults to `false` (plain SQLite for backward compatibility).
  bool get encryptDatabase => _encryptDatabase ?? false;

  /// Backing field. `null` means the caller did not supply it, which is what
  /// keeps it out of the wire payload (#321).
  final bool? _encryptDatabase;

  /// Custom encryption key.
  ///
  /// If `null`, a secure random key is generated and stored in
  /// platform-secure storage (Android Keystore / iOS Keychain).
  ///
  /// Provide this only if your app manages its own key material.
  /// The key must be a non-empty string. It is passed directly to
  /// SQLCipher as the `PRAGMA key`.
  final String? encryptionKey;

  /// Applies every field [other] explicitly supplied on top of this config,
  /// leaving fields [other] left unset as they are here (#321).
  SecurityConfig mergedWith(SecurityConfig other) => SecurityConfig(
    encryptDatabase: other._encryptDatabase ?? _encryptDatabase,
    encryptionKey: other.encryptionKey ?? encryptionKey,
  );

  /// Returns this config with every field pinned to its effective value.
  ///
  /// Used by `ready()`, which establishes a complete baseline rather than a
  /// partial update (#321).
  SecurityConfig resolved() => SecurityConfig(
    encryptDatabase: encryptDatabase,
    encryptionKey: encryptionKey,
  );

  /// Serializes to a map, omitting fields that were never supplied (#321).
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (_encryptDatabase != null) 'encryptDatabase': _encryptDatabase,
      if (encryptionKey != null) 'encryptionKey': encryptionKey,
    };
  }

  /// Converts to Pigeon [TlSecurityConfig].
  TlSecurityConfig toTlConfig() =>
      TlSecurityConfig(encryptDatabase: _encryptDatabase);

  @override
  String toString() =>
      'SecurityConfig(encryptDatabase: $encryptDatabase, '
      'encryptionKey: ${encryptionKey != null ? "***" : "null"})';

  // Equality compares the backing fields, not the resolved values: an unset
  // field and one explicitly set to its default behave identically but
  // serialise differently, and collapsing them would lose the distinction the
  // fix depends on (#321).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SecurityConfig &&
          runtimeType == other.runtimeType &&
          _encryptDatabase == other._encryptDatabase &&
          encryptionKey == other.encryptionKey;

  @override
  int get hashCode => Object.hash(_encryptDatabase, encryptionKey);
}
