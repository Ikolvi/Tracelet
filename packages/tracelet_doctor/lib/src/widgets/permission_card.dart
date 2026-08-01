import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;

import 'package:tracelet_doctor/src/doctor_theme.dart';
import 'package:tracelet_doctor/src/widgets/common.dart';

/// Displays permission statuses (location, motion, accuracy).
class PermissionCard extends StatelessWidget {
  /// Creates a [PermissionCard].
  const PermissionCard({required this.health, super.key});

  /// The health check data.
  final HealthCheck health;

  @override
  Widget build(BuildContext context) {
    final permColor = switch (health.locationPermission) {
      AuthorizationStatus.always => DoctorTheme.success,
      AuthorizationStatus.whenInUse => DoctorTheme.warning,
      _ => DoctorTheme.error,
    };
    final permLabel = switch (health.locationPermission) {
      AuthorizationStatus.always => 'Always',
      AuthorizationStatus.whenInUse => 'When In Use',
      AuthorizationStatus.denied => 'Denied',
      AuthorizationStatus.deniedForever => 'Denied Forever',
      AuthorizationStatus.notDetermined => 'Not Determined',
    };

    // Switch over the enum rather than raw indices: HealthCheck.motionPermission
    // carries a MotionAuthorizationStatus index, and decoding it against
    // CoreMotion's CMAuthorizationStatus scale reported `granted` (index 1) as a
    // red "Restricted". An exhaustive switch also means adding an enum case
    // fails to compile instead of silently falling through to "Unknown".
    final motionStatus = health.motionAuthorization;
    final motionLabel = switch (motionStatus) {
      MotionAuthorizationStatus.notDetermined => 'Not Determined',
      MotionAuthorizationStatus.granted => 'Granted',
      MotionAuthorizationStatus.deniedForever => 'Denied',
      null => 'Unknown',
    };
    final motionColor = switch (motionStatus) {
      MotionAuthorizationStatus.granted => DoctorTheme.success,
      MotionAuthorizationStatus.notDetermined => DoctorTheme.warning,
      MotionAuthorizationStatus.deniedForever => DoctorTheme.error,
      null => DoctorTheme.warning,
    };

    final accuracyLabel =
        health.accuracyAuthorization == AccuracyAuthorization.full
        ? 'Full'
        : 'Reduced';
    final accuracyColor =
        health.accuracyAuthorization == AccuracyAuthorization.full
        ? DoctorTheme.success
        : DoctorTheme.warning;

    return DiagnosticCard(
      icon: Icons.shield_rounded,
      title: 'Permissions',
      trailing: StatusChip(label: permLabel, color: permColor),
      child: Column(
        children: [
          InfoRow(label: 'Location', value: permLabel, valueColor: permColor),
          InfoRow(
            label: 'Motion Activity',
            value: motionLabel,
            valueColor: motionColor,
          ),
          InfoRow(
            label: 'Accuracy',
            value: accuracyLabel,
            valueColor: accuracyColor,
          ),
        ],
      ),
    );
  }
}
