import 'package:meta/meta.dart';
import 'package:tracelet/src/models/_helpers.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

// ---------------------------------------------------------------------------
// AttestationConfig
// ---------------------------------------------------------------------------

/// **Enterprise** — Device integrity attestation configuration.
///
/// When enabled, the plugin generates a signed attestation token from the
/// device's hardware-backed security module. The token proves the location
/// data came from a genuine, non-rooted/jailbroken device and can be sent
/// alongside HTTP sync payloads for server-side verification.
///
/// ## Trust Layers (Cumulative)
///
/// 1. **Mock detection** (existing) — Rejects spoofed GPS coordinates.
/// 2. **Device attestation** (this feature) — Proves the device
///    hardware/software is genuine.
/// 3. **Audit trail** (existing) — Proves the location chain hasn't been
///    tampered with.
///
/// ## Platform Support
///
/// - **Android**: Google Play Integrity API (replaces deprecated SafetyNet).
/// - **iOS**: App Attest (iOS 14+) with DeviceCheck (iOS 11+) fallback.
/// - **Web**: Not supported — `getAttestationToken()` returns `null`.
///
/// ## Rate Limits
///
/// Google Play Integrity allows ~10,000 requests/day (free tier). The
/// default 1-hour refresh yields 24 requests/day per device.
///
/// ```dart
/// Config(
///   attestation: AttestationConfig(
///     enabled: true,
///     refreshInterval: 3600,
///   ),
/// )
/// ```
@immutable
class AttestationConfig {
  /// Creates a new [AttestationConfig].
  /// Omitting a parameter leaves it *unset*: the getter reports the documented
  /// default, and [toMap]/[toTlConfig] skip the field so a partial
  /// `setConfig()` does not overwrite the persisted value (#321).
  const AttestationConfig({
    bool? enabled,
    int? refreshInterval,
    @Deprecated(
      'Never implemented — no platform reads this value and the token is not '
      'sent anywhere for verification. Verify it on your backend instead. '
      'Will be removed in a future major version (#304).',
    )
    this.verificationUrl,
  }) : _enabled = enabled,
       _refreshInterval = refreshInterval;

  /// Creates an [AttestationConfig] from a map.
  ///
  /// An absent key stays unset, so a `toMap()`/`fromMap()` round trip preserves
  /// which fields were supplied (#321).
  factory AttestationConfig.fromMap(Map<String, Object?> map) {
    final hasEnabled =
        map.containsKey('attestationEnabled') || map.containsKey('enabled');
    final hasInterval =
        map.containsKey('attestationRefreshInterval') ||
        map.containsKey('refreshInterval');
    return AttestationConfig(
      enabled: hasEnabled
          ? ensureBool(
              map['attestationEnabled'] ?? map['enabled'],
              fallback: false,
            )
          : null,
      refreshInterval: hasInterval
          ? ensureInt(
              map['attestationRefreshInterval'] ?? map['refreshInterval'],
              fallback: 3600,
            )
          : null,
      verificationUrl:
          map['attestationVerificationUrl'] as String? ??
          map['verificationUrl'] as String?,
    );
  }

  /// Enable device attestation.
  ///
  /// When `true`, an attestation token is generated periodically and
  /// attached to HTTP sync payloads as the `X-Attestation-Token` header.
  ///
  /// Defaults to `false`.
  bool get enabled => _enabled ?? false;

  /// How often to refresh the attestation token (seconds).
  ///
  /// Attestation API calls have rate limits — don't set below 60s.
  /// Defaults to `3600` (1 hour).
  int get refreshInterval => _refreshInterval ?? 3600;

  // Backing fields. `null` means "not supplied by the caller", which is what
  // keeps the field out of the wire payload (#321).
  final bool? _enabled;
  final int? _refreshInterval;

  /// Server URL to verify the attestation token (optional).
  ///
  /// **Not implemented.** The value is validated, serialized and stored, but no
  /// platform ever reads it: nothing sends the token anywhere for server-side
  /// verification, on Android, iOS or in the Rust core (#304). Setting it has
  /// never had any effect. Verify the token on your own backend instead — it is
  /// already included in sync payloads.
  ///
  /// Only HTTPS URLs are accepted. Defaults to `null`.
  @Deprecated(
    'Never implemented — no platform reads this value and the token is not '
    'sent anywhere for verification. Verify it on your backend instead. '
    'Will be removed in a future major version (#304).',
  )
  final String? verificationUrl;

  /// Applies every field [other] explicitly supplied on top of this one (#321).
  AttestationConfig mergedWith(AttestationConfig other) => AttestationConfig(
    enabled: other._enabled ?? _enabled,
    refreshInterval: other._refreshInterval ?? _refreshInterval,
    // ignore: deprecated_member_use_from_same_package
    verificationUrl: other.verificationUrl ?? verificationUrl,
  );

  /// Returns this config with every field pinned to its effective value, for
  /// the complete baseline `ready()` sends (#321).
  AttestationConfig resolved() => AttestationConfig(
    enabled: enabled,
    refreshInterval: refreshInterval,
    // ignore: deprecated_member_use_from_same_package
    verificationUrl: verificationUrl,
  );

  /// Serializes to a map, omitting fields that were never supplied (#321).
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (_enabled != null) 'attestationEnabled': _enabled,
      if (_refreshInterval != null)
        'attestationRefreshInterval': _refreshInterval,
      if (verificationUrl != null)
        'attestationVerificationUrl': verificationUrl,
    };
  }

  /// Converts to Pigeon [TlAttestationConfig].
  ///
  /// Unset fields cross as `null` so the platform leaves the persisted value
  /// alone (#321).
  TlAttestationConfig toTlConfig() =>
      TlAttestationConfig(enabled: _enabled, refreshInterval: _refreshInterval);

  @override
  String toString() =>
      'AttestationConfig(enabled: $enabled, '
      'refreshInterval: $refreshInterval, '
      'verificationUrl: $verificationUrl)';

  // Compares the backing fields so unset stays distinguishable from an
  // explicit default (#321).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttestationConfig &&
          runtimeType == other.runtimeType &&
          _enabled == other._enabled &&
          _refreshInterval == other._refreshInterval &&
          verificationUrl == other.verificationUrl;

  @override
  int get hashCode => Object.hash(_enabled, _refreshInterval, verificationUrl);
}

/// Represents an attestation token from the device's integrity API.
///
/// This token can be verified server-side to confirm the location data
/// came from a genuine device.
@immutable
class AttestationToken {
  /// Creates a new [AttestationToken].
  const AttestationToken({
    required this.token,
    required this.timestamp,
    required this.provider,
    this.verified,
  });

  /// Creates an [AttestationToken] from a map.
  factory AttestationToken.fromMap(Map<String, Object?> map) {
    return AttestationToken(
      token: map['token'] as String? ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        map['timestamp'] as int? ?? 0,
      ),
      provider: map['provider'] as String? ?? 'unknown',
      verified: map['verified'] as bool?,
    );
  }

  /// Platform-specific token string.
  ///
  /// - **Android**: Play Integrity API verdict token (JWT).
  /// - **iOS**: App Attest assertion (CBOR, base64-encoded).
  final String token;

  /// When this token was generated.
  final DateTime timestamp;

  /// Platform attestation provider.
  ///
  /// One of: `"play_integrity"`, `"app_attest"`, `"device_check"`.
  final String provider;

  /// Whether the device passed integrity checks.
  ///
  /// `null` if server-side verification hasn't been performed yet.
  final bool? verified;

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    // A token is a *result*, not a partial configuration: #321's omit-unset
    // rule does not apply here, and `token`/`timestamp`/`provider` are
    // non-nullable, so guarding them was dead code (the analyzer said so) that
    // implied a token could arrive without one. Only `verified` is genuinely
    // absent until a server verifies it (#326).
    return <String, Object?>{
      'token': token,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'provider': provider,
      if (verified != null) 'verified': verified,
    };
  }

  @override
  String toString() =>
      'AttestationToken(provider: $provider, '
      'timestamp: $timestamp, '
      'verified: $verified)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttestationToken &&
          runtimeType == other.runtimeType &&
          token == other.token &&
          timestamp == other.timestamp &&
          provider == other.provider;

  @override
  int get hashCode => Object.hash(token, timestamp, provider);
}
