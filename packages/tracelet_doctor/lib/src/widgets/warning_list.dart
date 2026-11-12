// Not package:material_ui yet: it needs Flutter >= 3.47 and this package
// still supports older versions.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;

import 'package:tracelet_doctor/src/doctor_theme.dart';

/// Displays computed health warnings as expandable cards with descriptions.
class WarningList extends StatelessWidget {
  /// Creates a [WarningList].
  const WarningList({required this.warnings, super.key});

  /// The list of health warnings.
  final List<HealthWarning> warnings;

  @override
  Widget build(BuildContext context) {
    if (warnings.isEmpty) {
      return Container(
        decoration: DoctorTheme.cardDecoration.copyWith(
          border: Border.all(
            color: DoctorTheme.success.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
        padding: DoctorTheme.cardPadding,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: DoctorTheme.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: DoctorTheme.success,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'All Clear',
                    style: DoctorTheme.cardTitleStyle.copyWith(
                      color: DoctorTheme.success,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'No issues detected — tracking is healthy.',
                    style: DoctorTheme.cardBodyStyle,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: warnings.map((w) => _WarningTile(warning: w)).toList(),
    );
  }
}

class _WarningTile extends StatelessWidget {
  const _WarningTile({required this.warning});
  final HealthWarning warning;

  IconData get _icon => switch (warning) {
    HealthWarning.locationPermissionDenied => Icons.location_off_rounded,
    HealthWarning.locationPermissionDeniedForever => Icons.block_rounded,
    HealthWarning.locationServicesDisabled => Icons.gps_off_rounded,
    HealthWarning.powerSaveMode => Icons.battery_saver_rounded,
    HealthWarning.aggressiveOem => Icons.phonelink_erase_rounded,
    HealthWarning.batteryOptimizationsNotIgnored => Icons.battery_alert_rounded,
    HealthWarning.reducedAccuracy => Icons.adjust_rounded,
    HealthWarning.noAccelerometer => Icons.vibration_rounded,
    HealthWarning.noSignificantMotion => Icons.directions_walk_rounded,
    HealthWarning.motionPermissionDenied => Icons.do_not_step_rounded,
    HealthWarning.mockLocationsDetected => Icons.warning_amber_rounded,
    HealthWarning.locationPermissionOnlyWhenInUse =>
      Icons.location_searching_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: DoctorTheme.cardDecoration.copyWith(
        border: Border.all(
          color: DoctorTheme.warning.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: DoctorTheme.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_icon, color: DoctorTheme.warning, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              warning.description,
              style: DoctorTheme.cardBodyStyle.copyWith(
                color: DoctorTheme.textPrimary,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
