import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;

import 'package:tracelet_doctor/src/doctor_theme.dart';
import 'package:tracelet_doctor/src/widgets/common.dart';

/// Shows the location-filter thresholds **actually in force** in the native
/// processor, read via `Tracelet.getCurrentLocationTuning()` (#303).
///
/// Every other card in the Doctor reads [Tracelet.activeConfig], which is a
/// Dart-side mirror of the last [Config] passed in — it says what was *asked
/// for*, not what the filter is using. Two things only this card can show:
///
/// - **A transport-mode auto-tune.** With
///   `ClassifierConfig.autoTuneFromTransportMode` on, a committed mode swaps
///   these thresholds out from under the configured values with no config call
///   at all, so `activeConfig` and the filter legitimately disagree.
/// - **Configuration that never landed.** If auto-tuning is off and the two
///   still disagree, the configured value did not reach the processor — the
///   #303 failure class, previously invisible from Dart.
///
/// [tuning] is `null` before a tracking session has built a location processor,
/// and always `null` on web (the browser Geolocation API has no equivalent
/// filter state).
class LocationTuningCard extends StatelessWidget {
  /// Creates a [LocationTuningCard] from the live tuning.
  const LocationTuningCard({
    required this.tuning,
    required this.platform,
    this.config,
    super.key,
  });

  /// The result of `Tracelet.getCurrentLocationTuning()`, or `null` if no
  /// processor exists yet / the platform has none.
  final LocationTuning? tuning;

  /// `android`, `ios`, or `web` — from the health check.
  final String platform;

  /// The configuration to compare [tuning] against. Defaults to
  /// [Tracelet.activeConfig]; injectable so tests can drive both sides of the
  /// comparison without a live plugin.
  final Config? config;

  Config get _config => config ?? Tracelet.activeConfig;

  bool get _autoTuneEnabled => _config.classifier.autoTuneFromTransportMode;

  /// The rows to render: configured value vs. the one in force.
  List<_TuningRow> get _rows {
    final live = tuning;
    if (live == null) return const [];
    final geo = _config.geo;
    final filter = geo.filter;
    return [
      _TuningRow(
        label: 'Distance filter',
        configured: geo.distanceFilter.toStringAsFixed(0),
        effective: live.distanceFilter.toStringAsFixed(0),
        unit: 'm',
      ),
      _TuningRow(
        label: 'Tracking accuracy',
        configured: '${filter.trackingAccuracyThreshold}',
        effective: '${live.trackingAccuracyThreshold}',
        unit: 'm',
      ),
      _TuningRow(
        label: 'Odometer accuracy',
        configured: '${filter.odometerAccuracyThreshold}',
        effective: '${live.odometerAccuracyThreshold}',
        unit: 'm',
      ),
      _TuningRow(
        label: 'Max implied speed',
        configured: '${filter.maxImpliedSpeed}',
        effective: '${live.maxImpliedSpeed}',
        unit: 'm/s',
      ),
    ];
  }

  ({String label, Color color}) get _status {
    if (tuning == null) {
      return (label: 'N/A', color: DoctorTheme.muted);
    }
    final drifted = _rows.any((r) => r.differs);
    if (!drifted) {
      return (label: 'As configured', color: DoctorTheme.success);
    }
    // A difference is expected while a committed transport mode owns the
    // thresholds, and a bug when nothing is supposed to be changing them.
    return _autoTuneEnabled
        ? (label: 'Auto-tuned', color: DoctorTheme.accent)
        : (label: 'Mismatch', color: DoctorTheme.error);
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final rows = _rows;
    final drifted = rows.any((r) => r.differs);

    return DiagnosticCard(
      icon: Icons.speed_rounded,
      title: 'Location Filter (in force)',
      trailing: StatusChip(label: status.label, color: status.color),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BoolRow(
            label: 'Auto-tune from transport mode',
            value: _autoTuneEnabled,
          ),
          const SizedBox(height: 4),
          if (tuning == null)
            Text(
              platform == 'web'
                  ? 'The browser Geolocation API exposes no filter state.'
                  : 'No location processor yet — start tracking and re-run to '
                        'see the thresholds actually in force.',
              style: DoctorTheme.cardBodyStyle,
            )
          else ...[
            ...rows,
            if (drifted) ...[
              const SizedBox(height: 10),
              _Note(
                color: status.color,
                icon: _autoTuneEnabled
                    ? Icons.auto_awesome_rounded
                    : Icons.error_outline_rounded,
                message: _autoTuneEnabled
                    ? 'A committed transport mode is overriding your configured '
                          'thresholds. Values on the right are what the filter is '
                          'using; disabling auto-tune restores the configured ones.'
                    : 'Auto-tuning is off, so these should match your '
                          'configuration — the configured value did not reach the '
                          'native processor. Re-apply it with setConfig(), and if '
                          'it still differs please file an issue.',
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// One threshold: what was configured, and what the processor is using.
class _TuningRow extends StatelessWidget {
  const _TuningRow({
    required this.label,
    required this.configured,
    required this.effective,
    required this.unit,
  });

  final String label;
  final String configured;
  final String effective;
  final String unit;

  bool get differs => configured != effective;

  @override
  Widget build(BuildContext context) {
    // Only spend the arrow when the two disagree — an unchanged threshold
    // reading `30 → 30 m` is noise.
    return InfoRow(
      label: label,
      value: differs ? '$configured → $effective $unit' : '$effective $unit',
      valueColor: differs ? DoctorTheme.accent : null,
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.color, required this.icon, required this.message});

  final Color color;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: DoctorTheme.cardBodyStyle.copyWith(
                color: DoctorTheme.textPrimary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
