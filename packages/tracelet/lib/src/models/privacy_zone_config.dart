import 'package:meta/meta.dart';
import 'package:tracelet/src/models/_helpers.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

/// **Enterprise** — Configuration for Privacy Zones.
///
/// Controls whether privacy zone evaluation is active. Individual zones
/// are managed via `Tracelet.addPrivacyZone()` / `removePrivacyZone()`.
///
/// ```dart
/// Config(
///   privacyZone: PrivacyZoneConfig(enabled: true),
/// )
/// ```
///
/// Omitting [enabled] leaves it unset, so a partial `setConfig()` does not
/// overwrite the persisted value (#321).
@immutable
class PrivacyZoneConfig {
  /// Creates a new [PrivacyZoneConfig].
  ///
  /// Omitting [enabled] leaves it *unset*: the getter reports the documented
  /// default, and [toMap]/[toTlConfig] skip the field (#321).
  const PrivacyZoneConfig({bool? enabled}) : _enabled = enabled;

  /// Creates a [PrivacyZoneConfig] from a platform map.
  ///
  /// An absent key stays unset, so a `toMap()`/`fromMap()` round trip preserves
  /// whether the field was supplied (#321).
  factory PrivacyZoneConfig.fromMap(Map<String, Object?> map) {
    final has =
        map.containsKey('privacyZoneEnabled') || map.containsKey('enabled');
    return PrivacyZoneConfig(
      enabled: has
          ? ensureBool(
              map['privacyZoneEnabled'] ?? map['enabled'],
              fallback: false,
            )
          : null,
    );
  }

  /// Backing field. `null` means the caller did not provide it, which is what
  /// keeps it out of the wire payload (#321).
  final bool? _enabled;

  /// Master toggle for privacy zone evaluation.
  ///
  /// When `false` (default), all registered privacy zones are ignored and
  /// locations flow through the normal dispatch pipeline unchanged.
  bool get enabled => _enabled ?? false;

  /// Applies [other]'s explicitly supplied field on top of this config (#321).
  PrivacyZoneConfig mergedWith(PrivacyZoneConfig other) =>
      PrivacyZoneConfig(enabled: other._enabled ?? _enabled);

  /// Returns this config with every field pinned to its effective value,
  /// for the complete baseline `ready()` sends (#321).
  PrivacyZoneConfig resolved() => PrivacyZoneConfig(enabled: enabled);

  /// Serializes to a map, omitting the field when it was never supplied (#321).
  ///
  /// Uses `privacyZoneEnabled` as the key (rather than plain `enabled`) to
  /// avoid collisions when native platforms flatten all config sections into
  /// a single key-value store.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (_enabled != null) 'privacyZoneEnabled': _enabled,
    };
  }

  /// Converts to Pigeon [TlPrivacyZoneConfig].
  TlPrivacyZoneConfig toTlConfig() => TlPrivacyZoneConfig(enabled: _enabled);

  @override
  String toString() => 'PrivacyZoneConfig(enabled: $enabled)';

  // Compares the backing field so unset stays distinguishable from an explicit
  // default (#321).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrivacyZoneConfig &&
          runtimeType == other.runtimeType &&
          _enabled == other._enabled;

  @override
  int get hashCode => _enabled.hashCode;
}
