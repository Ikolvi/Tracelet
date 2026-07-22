import 'package:flutter/material.dart';

import 'package:tracelet_doctor/src/doctor_theme.dart';
import 'package:tracelet_doctor/src/widgets/common.dart';

/// Displays authoritative foreground-service health (#255).
///
/// [Tracelet.getState] reports the *desired* tracking state, but on Android 12+
/// a foreground-service start can be deferred or rejected by the OS even while
/// tracking is enabled — so it is not proof that background tracking is
/// actually operational. This card renders the map returned by
/// `Tracelet.getForegroundServiceHealth()`, surfacing whether the service is
/// running and promoted, and the last promotion result (`success` / `deferred`
/// / `failed`) with its failure class and message.
///
/// On iOS and web there is no foreground service; the card reflects that.
class ForegroundServiceCard extends StatelessWidget {
  /// Creates a [ForegroundServiceCard] from the health map.
  const ForegroundServiceCard({required this.health, super.key});

  /// The map returned by `Tracelet.getForegroundServiceHealth()`.
  final Map<String, Object?> health;

  bool get _desiredEnabled => health['desiredEnabled'] == true;
  bool get _fgEnabled => health['foregroundServiceEnabled'] == true;
  bool get _serviceRunning => health['serviceRunning'] == true;
  bool get _serviceForeground => health['serviceForeground'] == true;
  String? get _result => health['lastForegroundPromotionResult'] as String?;
  String get _platform => (health['platform'] as String?) ?? 'unknown';

  ({String label, Color color}) get _status {
    if (!_desiredEnabled) {
      return (label: 'Inactive', color: DoctorTheme.muted);
    }
    // iOS / web have no foreground service — enabled tracking is "as good as
    // it gets" there, so report it as healthy rather than a false alarm.
    if (_platform != 'android') {
      return (label: 'Active', color: DoctorTheme.success);
    }
    if (!_fgEnabled) {
      return (label: 'No FGS', color: DoctorTheme.accent);
    }
    if (_serviceForeground) {
      return (label: 'Healthy', color: DoctorTheme.success);
    }
    if (_result == 'deferred') {
      return (label: 'Deferred', color: DoctorTheme.warning);
    }
    if (_result == 'failed') {
      return (label: 'Failed', color: DoctorTheme.error);
    }
    return (label: 'Pending', color: DoctorTheme.warning);
  }

  String _formatTransition(Object? raw) {
    final ms = raw is num ? raw.toInt() : null;
    if (ms == null || ms <= 0) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final isAndroid = _platform == 'android';
    final failureClass =
        health['lastForegroundPromotionFailureClass'] as String?;
    final failureMessage =
        health['lastForegroundPromotionFailureMessage'] as String?;

    return DiagnosticCard(
      icon: Icons.dvr_rounded,
      title: 'Foreground Service',
      trailing: StatusChip(label: status.label, color: status.color),
      child: Column(
        children: [
          BoolRow(label: 'Desired (enabled)', value: _desiredEnabled),
          if (isAndroid) ...[
            BoolRow(label: 'Configured to run FGS', value: _fgEnabled),
            BoolRow(label: 'Service running', value: _serviceRunning),
            BoolRow(label: 'Promoted to foreground', value: _serviceForeground),
            InfoRow(
              label: 'Last promotion',
              value: _result ?? '—',
              valueColor: switch (_result) {
                'success' => DoctorTheme.success,
                'deferred' => DoctorTheme.warning,
                'failed' => DoctorTheme.error,
                _ => DoctorTheme.textSecondary,
              },
            ),
            InfoRow(
              label: 'Last transition',
              value: _formatTransition(health['lastForegroundTransitionAt']),
            ),
            if (failureClass != null)
              InfoRow(label: 'Failure', value: failureClass),
            if (failureMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    failureMessage,
                    style: DoctorTheme.cardBodyStyle.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: DoctorTheme.error,
                    ),
                  ),
                ),
              ),
            if (_desiredEnabled && _fgEnabled && !_serviceForeground)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _result == 'deferred'
                      ? 'Promotion deferred — Android will retry when the app '
                            'returns to the foreground.'
                      : _result == 'failed'
                      ? 'Foreground promotion failed — background tracking is '
                            'NOT operational. Check permissions and Android 12+ '
                            'foreground-service start restrictions.'
                      : 'Tracking requested but the foreground service is not '
                            'confirmed yet.',
                  style: DoctorTheme.cardBodyStyle.copyWith(
                    color: status.color,
                  ),
                ),
              ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _platform == 'ios'
                      ? 'iOS has no foreground service — there is no promotion '
                            'that can fail after the fact.'
                      : 'This platform has no foreground service.',
                  style: DoctorTheme.cardBodyStyle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
