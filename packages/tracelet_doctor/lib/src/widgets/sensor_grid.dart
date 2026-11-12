// Not package:material_ui yet: it needs Flutter >= 3.47 and this package
// still supports older versions.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;

import 'package:tracelet_doctor/src/doctor_theme.dart';
import 'package:tracelet_doctor/src/widgets/common.dart';

/// Displays available hardware sensors in a compact grid.
class SensorGrid extends StatelessWidget {
  /// Creates a [SensorGrid].
  const SensorGrid({required this.health, super.key});

  /// The health check data.
  final HealthCheck health;

  @override
  Widget build(BuildContext context) {
    final sensors = [
      _SensorInfo(
        'Accelerometer',
        Icons.vibration_rounded,
        health.hasAccelerometer,
      ),
      _SensorInfo('Gyroscope', Icons.threesixty_rounded, health.hasGyroscope),
      _SensorInfo(
        'Magnetometer',
        Icons.explore_rounded,
        health.hasMagnetometer,
      ),
      _SensorInfo(
        'Sig. Motion',
        Icons.directions_walk_rounded,
        health.hasSignificantMotion,
      ),
    ];

    return DiagnosticCard(
      icon: Icons.sensors_rounded,
      title: 'Sensors',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: sensors.map((s) => _SensorTile(sensor: s)).toList(),
      ),
    );
  }
}

class _SensorInfo {
  const _SensorInfo(this.label, this.icon, this.available);
  final String label;
  final IconData icon;
  final bool available;
}

class _SensorTile extends StatelessWidget {
  const _SensorTile({required this.sensor});
  final _SensorInfo sensor;

  @override
  Widget build(BuildContext context) {
    final color = sensor.available ? DoctorTheme.success : DoctorTheme.error;

    return Container(
      width: 80,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 0.5),
      ),
      child: Column(
        children: [
          Icon(sensor.icon, size: 22, color: color),
          const SizedBox(height: 6),
          Text(
            sensor.label,
            textAlign: TextAlign.center,
            style: DoctorTheme.chipStyle.copyWith(color: color, fontSize: 9),
          ),
        ],
      ),
    );
  }
}
