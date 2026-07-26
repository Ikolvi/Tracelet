import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;

import 'package:tracelet_doctor/src/doctor_theme.dart';
import 'package:tracelet_doctor/src/widgets/common.dart';

/// Displays pending database queue count, mock location status, and a
/// purge button with confirmation dialog.
class DatabaseCard extends StatelessWidget {
  /// Creates a [DatabaseCard].
  const DatabaseCard({
    required this.health,
    this.onLocationsCleared,
    super.key,
  });

  /// The health check data.
  final HealthCheck health;

  /// Called after locations have been successfully cleared.
  final VoidCallback? onLocationsCleared;

  Future<void> _confirmAndClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DoctorTheme.sheetBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: DoctorTheme.cardBorder, width: 0.5),
        ),
        icon: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: DoctorTheme.error.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.delete_forever_rounded,
            color: DoctorTheme.error,
            size: 32,
          ),
        ),
        title: const Text(
          'Clear Pending Locations?',
          style: DoctorTheme.cardTitleStyle,
          textAlign: TextAlign.center,
        ),
        content: Text(
          'This will permanently delete all ${health.locationCount} '
          'pending location records from the local database.\n\n'
          'Unsynced locations will be lost and cannot be recovered.',
          style: DoctorTheme.cardBodyStyle,
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: DoctorTheme.textSecondary,
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: DoctorTheme.error,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.delete_rounded, size: 18),
            label: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    try {
      await Tracelet.destroyLocations();
      onLocationsCleared?.call();

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${health.locationCount} location(s) cleared',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: DoctorTheme.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to clear: $e',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: DoctorTheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final queueColor = health.locationCount == 0
        ? DoctorTheme.success
        : health.locationCount < 100
        ? DoctorTheme.accent
        : health.locationCount < 500
        ? DoctorTheme.warning
        : DoctorTheme.error;

    return DiagnosticCard(
      icon: Icons.storage_rounded,
      title: 'Database',
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Pending Locations', style: DoctorTheme.cardBodyStyle),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: queueColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${health.locationCount}',
                  style: DoctorTheme.cardTitleStyle.copyWith(
                    color: queueColor,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          if (health.locationCount > 0) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _confirmAndClear(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: DoctorTheme.error,
                  side: BorderSide(
                    color: DoctorTheme.error.withValues(alpha: 0.4),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                label: Text(
                  'Clear ${health.locationCount} Pending Location${health.locationCount == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
          BoolRow(
            label: 'Mock Locations',
            value: health.mockLocationsDetected,
            invertColor: true,
          ),
          InfoRow(
            label: 'Platform',
            value: health.platform.isNotEmpty ? health.platform : '—',
          ),
          InfoRow(
            label: 'OS Version',
            value: health.osVersion.isNotEmpty ? health.osVersion : '—',
          ),
          const SizedBox(height: 12),
          const Divider(color: DoctorTheme.cardBorder, height: 1),
          const SizedBox(height: 12),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Lifetime Stats', style: DoctorTheme.sectionStyle),
          ),
          const SizedBox(height: 8),
          FutureBuilder<Map<String?, Object?>?>(
            future: Tracelet.getCarbonReport(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: DoctorTheme.accent,
                      ),
                    ),
                  ),
                );
              }
              if (snapshot.hasError) {
                return const InfoRow(
                  label: 'Error',
                  value: 'Could not load stats',
                );
              }
              final data = snapshot.data;
              if (data == null || data.isEmpty) {
                return const InfoRow(label: 'No stats available', value: '—');
              }
              return _LifetimeStats(report: data);
            },
          ),
        ],
      ),
    );
  }
}

/// Renders the carbon report as a compact, human-readable summary.
///
/// The raw report contains huge unformatted doubles (grams, meters) and
/// per-mode maps; dumping them verbatim overflowed the card and was unreadable.
/// This shows totals in friendly units (CO₂ in g/kg, distance in km, trips).
class _LifetimeStats extends StatelessWidget {
  const _LifetimeStats({required this.report});

  final Map<String?, Object?> report;

  static double _asDouble(Object? v) => v is num ? v.toDouble() : 0.0;
  static int _asInt(Object? v) => v is num ? v.toInt() : 0;

  static double _sumValues(Object? map) {
    if (map is! Map) return 0;
    var total = 0.0;
    for (final v in map.values) {
      total += _asDouble(v);
    }
    return total;
  }

  static String _formatCarbon(double grams) {
    if (grams >= 1000) return '${(grams / 1000).toStringAsFixed(2)} kg';
    return '${grams.toStringAsFixed(1)} g';
  }

  static String _formatDistance(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(2)} km';
    return '${meters.toStringAsFixed(0)} m';
  }

  @override
  Widget build(BuildContext context) {
    final carbonGrams = _asDouble(report['totalCarbonGrams']);
    final distanceMeters = _sumValues(report['distanceByMode']);
    final trips = _asInt(report['totalTrips']);

    return Column(
      children: [
        InfoRow(label: 'Total CO₂', value: _formatCarbon(carbonGrams)),
        InfoRow(
          label: 'Total Distance',
          value: _formatDistance(distanceMeters),
        ),
        InfoRow(label: 'Total Trips', value: '$trips'),
      ],
    );
  }
}
