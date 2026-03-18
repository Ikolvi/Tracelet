import 'package:meta/meta.dart';

import '_helpers.dart';

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
  const AttestationConfig({
    this.enabled = false,
    this.refreshInterval = 3600,
    this.verificationUrl,
  });

  /// Enable device attestation.
  ///
  /// When `true`, an attestation token is generated periodically and
  /// attached to HTTP sync payloads as the `X-Attestation-Token` header.
  ///
  /// Defaults to `false`.
  final bool enabled;

  /// How often to refresh the attestation token (seconds).
  ///
  /// Attestation API calls have rate limits — don't set below 60s.
  /// Defaults to `3600` (1 hour).
  final int refreshInterval;

  /// Server URL to verify the attestation token (optional).
  ///
  /// If set, the plugin sends the token to this URL for server-side
  /// verification before including it in sync payloads.
  ///
  /// Only HTTPS URLs are accepted. Defaults to `null`.
  final String? verificationUrl;

  /// Creates an [AttestationConfig] from a map.
  factory AttestationConfig.fromMap(Map<String, Object?> map) {
    return AttestationConfig(
      enabled: ensureBool(
        map['attestationEnabled'] ?? map['enabled'],
        fallback: false,
      ),
      refreshInterval: ensureInt(
        map['attestationRefreshInterval'] ?? map['refreshInterval'],
        fallback: 3600,
      ),
      verificationUrl:
          map['attestationVerificationUrl'] as String? ??
          map['verificationUrl'] as String?,
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'attestationEnabled': enabled,
      'attestationRefreshInterval': refreshInterval,
      'attestationVerificationUrl': verificationUrl,
    };
  }

  @override
  String toString() =>
      'AttestationConfig(enabled: $enabled, '
      'refreshInterval: $refreshInterval, '
      'verificationUrl: $verificationUrl)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttestationConfig &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          refreshInterval == other.refreshInterval &&
          verificationUrl == other.verificationUrl;

  @override
  int get hashCode => Object.hash(enabled, refreshInterval, verificationUrl);
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

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'token': token,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'provider': provider,
      'verified': verified,
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
