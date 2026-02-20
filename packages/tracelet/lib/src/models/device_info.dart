import 'package:meta/meta.dart';

/// Information about the device.
@immutable
class DeviceInfo {
  /// Creates a new [DeviceInfo].
  const DeviceInfo({
    required this.model,
    required this.manufacturer,
    required this.version,
    required this.platform,
    this.framework = 'Flutter',
  });

  /// Device model name (e.g. `'Pixel 8'`, `'iPhone 15,4'`).
  final String model;

  /// Device manufacturer (e.g. `'Google'`, `'Apple'`).
  final String manufacturer;

  /// OS version string (e.g. `'14'`, `'17.4'`).
  final String version;

  /// Platform identifier (`'android'` or `'ios'`).
  final String platform;

  /// Framework identifier. Always `'Flutter'`.
  final String framework;

  /// Creates [DeviceInfo] from a platform map.
  factory DeviceInfo.fromMap(Map<String, Object?> map) {
    return DeviceInfo(
      model: map['model'] as String? ?? 'unknown',
      manufacturer: map['manufacturer'] as String? ?? 'unknown',
      version: map['version'] as String? ?? 'unknown',
      platform: map['platform'] as String? ?? 'unknown',
      framework: map['framework'] as String? ?? 'Flutter',
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'model': model,
      'manufacturer': manufacturer,
      'version': version,
      'platform': platform,
      'framework': framework,
    };
  }

  @override
  String toString() =>
      'DeviceInfo(model: $model, manufacturer: $manufacturer, '
      'os: $platform $version)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceInfo &&
          runtimeType == other.runtimeType &&
          model == other.model &&
          platform == other.platform;

  @override
  int get hashCode => Object.hash(model, platform);
}
