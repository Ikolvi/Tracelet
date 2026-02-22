import 'package:meta/meta.dart';

import '_helpers.dart';

/// Information about the device's available sensors.
///
/// Reports which motion-related sensors are available on the device.
@immutable
class Sensors {
  /// Creates a new [Sensors].
  const Sensors({
    required this.platform,
    this.accelerometer = false,
    this.gyroscope = false,
    this.magnetometer = false,
    this.significantMotion = false,
  });

  /// The platform identifier (`'android'` or `'ios'`).
  final String platform;

  /// Whether an accelerometer is available.
  final bool accelerometer;

  /// Whether a gyroscope is available.
  final bool gyroscope;

  /// Whether a magnetometer is available.
  final bool magnetometer;

  /// Whether the significant motion sensor is available (Android only).
  final bool significantMotion;

  /// Creates [Sensors] from a platform map.
  factory Sensors.fromMap(Map<String, Object?> map) {
    return Sensors(
      platform: map['platform'] as String? ?? 'unknown',
      accelerometer: ensureBool(map['accelerometer'], fallback: false),
      gyroscope: ensureBool(map['gyroscope'], fallback: false),
      magnetometer: ensureBool(map['magnetometer'], fallback: false),
      significantMotion: ensureBool(map['significantMotion'], fallback: false),
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'platform': platform,
      'accelerometer': accelerometer,
      'gyroscope': gyroscope,
      'magnetometer': magnetometer,
      'significantMotion': significantMotion,
    };
  }

  @override
  String toString() =>
      'Sensors(platform: $platform, accel: $accelerometer, '
      'gyro: $gyroscope, mag: $magnetometer)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Sensors &&
          runtimeType == other.runtimeType &&
          platform == other.platform;

  @override
  int get hashCode => platform.hashCode;
}
