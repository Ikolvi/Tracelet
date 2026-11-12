// Not package:material_ui yet: it needs Flutter >= 3.47 and this package
// still supports older versions.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;

import 'package:tracelet_doctor/src/doctor_theme.dart';
import 'package:tracelet_doctor/src/widgets/common.dart';

/// Displays battery, power-save mode, OEM compatibility, and aggression rating.
class BatteryOemCard extends StatelessWidget {
  /// Creates a [BatteryOemCard].
  const BatteryOemCard({required this.health, super.key});

  /// The health check data.
  final HealthCheck health;

  @override
  Widget build(BuildContext context) {
    final oemColor = health.isAggressiveOem
        ? DoctorTheme.error
        : DoctorTheme.success;
    final oemLabel = health.isAggressiveOem ? 'Aggressive' : 'Normal';

    return DiagnosticCard(
      icon: Icons.battery_alert_rounded,
      title: 'Battery & OEM',
      trailing: StatusChip(label: oemLabel, color: oemColor),
      child: Column(
        children: [
          InfoRow(
            label: 'Manufacturer',
            value: health.manufacturer.isNotEmpty
                ? health.manufacturer
                : 'Unknown',
          ),
          InfoRow(
            label: 'Model',
            value: health.model.isNotEmpty ? health.model : 'Unknown',
          ),
          BoolRow(
            label: 'Power Save Mode',
            value: health.isPowerSaveMode,
            invertColor: true,
          ),
          BoolRow(
            label: 'Battery Opt Exempt',
            value: health.isIgnoringBatteryOptimizations,
          ),
          InfoRow(
            label: 'Battery Budget',
            value: Tracelet.activeConfig.geo.batteryBudgetPerHour > 0
                ? '${Tracelet.activeConfig.geo.batteryBudgetPerHour}% / hour'
                : 'Disabled',
          ),
          if (health.isAggressiveOem) ...[
            const SizedBox(height: 8),
            _AggressionMeter(rating: health.aggressionRating),
          ],
        ],
      ),
    );
  }
}

class _AggressionMeter extends StatelessWidget {
  const _AggressionMeter({required this.rating});

  final int rating;

  @override
  Widget build(BuildContext context) {
    final clampedRating = rating.clamp(0, 5);
    final color = clampedRating <= 1
        ? DoctorTheme.success
        : clampedRating <= 3
        ? DoctorTheme.warning
        : DoctorTheme.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'OEM AGGRESSION',
              style: DoctorTheme.sectionStyle.copyWith(fontSize: 11),
            ),
            Text(
              '$clampedRating / 5',
              style: DoctorTheme.cardBodyStyle.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: clampedRating / 5.0,
            backgroundColor: DoctorTheme.cardBorder,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}
