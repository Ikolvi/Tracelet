import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tracelet/tracelet.dart' hide State;

import 'package:tracelet_doctor/src/bug_report.dart';
import 'package:tracelet_doctor/src/doctor_theme.dart';
import 'package:tracelet_doctor/src/widgets/battery_oem_card.dart';
import 'package:tracelet_doctor/src/widgets/config_review_card.dart';
import 'package:tracelet_doctor/src/widgets/database_card.dart';
import 'package:tracelet_doctor/src/widgets/foreground_service_card.dart';
import 'package:tracelet_doctor/src/widgets/location_tuning_card.dart';
import 'package:tracelet_doctor/src/widgets/log_viewer_sheet.dart';
import 'package:tracelet_doctor/src/widgets/permission_card.dart';
import 'package:tracelet_doctor/src/widgets/sensor_grid.dart';
import 'package:tracelet_doctor/src/widgets/tracking_card.dart';
import 'package:tracelet_doctor/src/widgets/warning_list.dart';

/// A drop-in diagnostic overlay for Tracelet.
///
/// Shows a detailed health check of the plugin's operational state including
/// permissions, tracking state, battery/OEM health, sensor availability,
/// database queue, and actionable warnings.
///
/// ## Usage
///
/// ```dart
/// // Show as a modal bottom sheet:
/// TraceletDoctor.show(context);
/// ```
///
/// The overlay calls [Tracelet.getHealth] internally to gather all diagnostic
/// data. No additional setup is required — just call [show].
class TraceletDoctor {
  TraceletDoctor._();

  /// Shows the Tracelet Doctor diagnostic sheet as a modal bottom sheet.
  ///
  /// This is the primary entry point. Call this from a button, debug menu,
  /// or shake gesture handler.
  ///
  /// ```dart
  /// ElevatedButton(
  ///   onPressed: () => TraceletDoctor.show(context),
  ///   child: const Text('Run Diagnostics'),
  /// );
  /// ```
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _DoctorSheetContent(),
    );
  }
}

class _DoctorSheetContent extends StatefulWidget {
  const _DoctorSheetContent();

  @override
  State<_DoctorSheetContent> createState() => _DoctorSheetContentState();
}

class _DoctorSheetContentState extends State<_DoctorSheetContent>
    with SingleTickerProviderStateMixin {
  HealthCheck? _health;

  /// Authoritative foreground-service health (#255). Fetched alongside the
  /// main health check; null if it could not be read (e.g. not initialized).
  Map<String, Object?>? _fgHealth;

  /// The location-filter thresholds actually in force (#303). Null before a
  /// tracking session has built a processor, and always null on web.
  LocationTuning? _tuning;
  bool _loading = true;
  String? _error;
  bool _notInitialized = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _runCheck();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  /// Heuristic to determine if the error means Tracelet is not initialized.
  static bool _isNotInitializedError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('missingpluginexception') ||
        msg.contains('not ready') ||
        msg.contains('not initialized') ||
        msg.contains('no implementation found') ||
        msg.contains('channel') && msg.contains('null');
  }

  Future<void> _runCheck() async {
    setState(() {
      _loading = true;
      _error = null;
      _notInitialized = false;
    });
    try {
      final health = await Tracelet.getHealth();
      // Foreground-service health (#255) is a separate, best-effort call — a
      // failure here must not fail the whole diagnostic run.
      Map<String, Object?>? fgHealth;
      try {
        fgHealth = await Tracelet.getForegroundServiceHealth();
      } catch (_) {
        fgHealth = null;
      }
      // Live filter thresholds (#303) — also best-effort. Null is a normal
      // answer here (no processor yet, or web), not a failure.
      LocationTuning? tuning;
      try {
        tuning = await Tracelet.getCurrentLocationTuning();
      } catch (_) {
        tuning = null;
      }
      if (mounted) {
        setState(() {
          _health = health;
          _fgHealth = fgHealth;
          _tuning = tuning;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _notInitialized = _isNotInitializedError(e);
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  bool _busyReport = false;

  /// Builds the full bug report (health + foreground-service health + config +
  /// telematics + geofence decision trace + logs).
  Future<String?> _buildReport() async {
    setState(() => _busyReport = true);
    try {
      return await TraceletBugReport.build();
    } catch (e) {
      if (mounted) _toast('Could not build report: $e', error: true);
      return null;
    } finally {
      if (mounted) setState(() => _busyReport = false);
    }
  }

  /// Copies the complete bug report to the clipboard — ready to paste into a
  /// GitHub issue alongside any app logs.
  Future<void> _copyReport() async {
    final report = await _buildReport();
    if (report == null) return;
    await Clipboard.setData(ClipboardData(text: report));
    if (mounted) {
      _toast('Full bug report copied — paste it into your issue');
    }
  }

  /// Shares / downloads the complete bug report as a `.md` file (email, chat,
  /// save to Files).
  Future<void> _shareReport() async {
    final report = await _buildReport();
    if (report == null) return;
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final fileName = 'tracelet-bug-report-$stamp.md';
    final file = XFile.fromData(
      Uint8List.fromList(utf8.encode(report)),
      mimeType: 'text/markdown',
      name: fileName,
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [file],
        fileNameOverrides: [fileName],
        subject: 'Tracelet bug report',
      ),
    );
  }

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? DoctorTheme.error : DoctorTheme.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;

    return Container(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.88),
      decoration: const BoxDecoration(
        color: DoctorTheme.sheetBackground,
        borderRadius: DoctorTheme.sheetRadius,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHandle(),
          _buildHeader(),
          const Divider(color: DoctorTheme.cardBorder, height: 1),
          Expanded(
            child: _loading
                ? _buildLoading()
                : _error != null
                ? _buildError()
                : _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: DoctorTheme.muted.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final health = _health;
    final warningCount = health?.warningCount ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4FC3F7), Color(0xFF0288D1)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.health_and_safety_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tracelet Doctor', style: DoctorTheme.titleStyle),
                if (_notInitialized)
                  Text(
                    'Plugin not initialized',
                    style: DoctorTheme.cardBodyStyle.copyWith(
                      color: DoctorTheme.warning,
                    ),
                  )
                else if (health != null)
                  Text(
                    warningCount == 0
                        ? 'All systems healthy'
                        : '$warningCount warning${warningCount > 1 ? 's' : ''} detected',
                    style: DoctorTheme.cardBodyStyle.copyWith(
                      color: warningCount == 0
                          ? DoctorTheme.success
                          : DoctorTheme.warning,
                    ),
                  ),
              ],
            ),
          ),
          if (health != null) ...[
            _HeaderButton(
              icon: Icons.list_alt_rounded,
              tooltip: 'View Logs',
              onPressed: () => LogViewerSheet.show(context),
            ),
            const SizedBox(width: 6),
            _HeaderButton(
              icon: Icons.copy_rounded,
              tooltip: 'Copy Bug Report',
              onPressed: _busyReport ? null : _copyReport,
              busy: _busyReport,
            ),
            const SizedBox(width: 6),
            _HeaderButton(
              icon: Icons.ios_share_rounded,
              tooltip: 'Share Bug Report',
              onPressed: _busyReport ? null : _shareReport,
            ),
            const SizedBox(width: 6),
            _HeaderButton(
              icon: Icons.refresh_rounded,
              tooltip: 'Re-run',
              onPressed: _runCheck,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (_, __) => Opacity(
          opacity: 0.4 + _pulseController.value * 0.6,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.health_and_safety_rounded,
                color: DoctorTheme.accent,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                'Running diagnostics…',
                style: DoctorTheme.cardBodyStyle.copyWith(
                  color: DoctorTheme.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    if (_notInitialized) return _buildNotAvailable();
    return _buildGenericError();
  }

  Widget _buildNotAvailable() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: DoctorTheme.warning.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.power_off_rounded,
                color: DoctorTheme.warning,
                size: 44,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Tracelet Not Available',
              style: DoctorTheme.cardTitleStyle.copyWith(
                color: DoctorTheme.warning,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'The Tracelet plugin has not been initialized yet.\n'
              'Call Tracelet.ready() before opening the Doctor.',
              textAlign: TextAlign.center,
              style: DoctorTheme.cardBodyStyle,
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: DoctorTheme.cardDecoration,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('QUICK FIX', style: DoctorTheme.sectionStyle),
                  const SizedBox(height: 8),
                  Text(
                    'await Tracelet.ready(Config.balanced(\n'
                    "  overrides: {'geo': ...}\n"
                    '));\n\n'
                    '// Then open the Doctor:\n'
                    'TraceletDoctor.show(context);',
                    style: DoctorTheme.cardBodyStyle.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: DoctorTheme.accent,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: _runCheck,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: TextButton.styleFrom(foregroundColor: DoctorTheme.accent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenericError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: DoctorTheme.error,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              'Diagnostics failed',
              style: DoctorTheme.cardTitleStyle.copyWith(
                color: DoctorTheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: DoctorTheme.cardBodyStyle,
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: _runCheck,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: TextButton.styleFrom(foregroundColor: DoctorTheme.accent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final health = _health!;

    return ListView(
      padding: DoctorTheme.contentPadding,
      children: [
        // Warnings section
        _SectionLabel(label: 'WARNINGS', count: health.warningCount),
        const SizedBox(height: 8),
        WarningList(warnings: health.warnings),
        const SizedBox(height: DoctorTheme.cardSpacing + 8),

        // Permissions
        const _SectionLabel(label: 'PERMISSIONS'),
        const SizedBox(height: 8),
        PermissionCard(health: health),
        const SizedBox(height: DoctorTheme.cardSpacing),

        // Tracking
        const _SectionLabel(label: 'TRACKING STATE'),
        const SizedBox(height: 8),
        TrackingCard(health: health),
        const SizedBox(height: DoctorTheme.cardSpacing),

        // Foreground service health (#255)
        if (_fgHealth != null) ...[
          const _SectionLabel(label: 'FOREGROUND SERVICE'),
          const SizedBox(height: 8),
          ForegroundServiceCard(health: _fgHealth!),
          const SizedBox(height: DoctorTheme.cardSpacing),
        ],

        // Battery & OEM
        const _SectionLabel(label: 'BATTERY & OEM'),
        const SizedBox(height: 8),
        BatteryOemCard(health: health),
        const SizedBox(height: DoctorTheme.cardSpacing),

        // Configuration Review
        const _SectionLabel(label: 'CONFIGURATION'),
        const SizedBox(height: 8),
        ConfigReviewCard(health: health),
        const SizedBox(height: DoctorTheme.cardSpacing),

        // Location filter thresholds actually in force (#303) — the only
        // place a transport-mode auto-tune, or config that never reached the
        // native processor, is visible.
        const _SectionLabel(label: 'LOCATION FILTER'),
        const SizedBox(height: 8),
        LocationTuningCard(tuning: _tuning, platform: health.platform),
        const SizedBox(height: DoctorTheme.cardSpacing),

        // Sensors
        const _SectionLabel(label: 'SENSORS'),
        const SizedBox(height: 8),
        SensorGrid(health: health),
        const SizedBox(height: DoctorTheme.cardSpacing),

        // Database
        const _SectionLabel(label: 'DATABASE & DEVICE'),
        const SizedBox(height: 8),
        DatabaseCard(health: health, onLocationsCleared: _runCheck),
        const SizedBox(height: DoctorTheme.cardSpacing),

        // Timestamp footer
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Checked at ${_formatTimestamp(health.timestamp)}',
              style: DoctorTheme.cardBodyStyle.copyWith(
                fontSize: 11,
                color: DoctorTheme.muted,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  String _formatTimestamp(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    final s = local.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, this.count});
  final String label;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: DoctorTheme.sectionStyle),
        if (count != null && count! > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: DoctorTheme.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: DoctorTheme.chipStyle.copyWith(
                color: DoctorTheme.warning,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.busy = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: DoctorTheme.cardSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: DoctorTheme.cardBorder, width: 0.5),
          ),
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: DoctorTheme.accent,
                  ),
                )
              : Icon(
                  icon,
                  size: 18,
                  color: disabled
                      ? DoctorTheme.accent.withValues(alpha: 0.4)
                      : DoctorTheme.accent,
                ),
        ),
      ),
    );
  }
}
