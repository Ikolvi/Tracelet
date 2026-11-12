// Not package:material_ui yet: it needs Flutter >= 3.47 and this package
// still supports older versions.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_doctor/src/doctor_theme.dart';

/// A bottom sheet that displays the Tracelet SDK logs.
class LogViewerSheet extends StatefulWidget {
  /// Creates a [LogViewerSheet].
  const LogViewerSheet({super.key});

  /// Shows the log viewer sheet.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const LogViewerSheet(),
    );
  }

  @override
  State<LogViewerSheet> createState() => _LogViewerSheetState();
}

class _LogViewerSheetState extends State<LogViewerSheet> {
  List<LogEntry>? _logs;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  Future<void> _fetchLogs() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final logs = await Tracelet.getLogs(500); // fetch last 500 logs
      if (mounted) {
        setState(() {
          _logs = logs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _copyLogs() async {
    final logs = _logs;
    if (logs == null || logs.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No logs to copy')));
      return;
    }
    final text = logs
        .map((l) => '${l.timestamp} [${l.level.toUpperCase()}] ${l.message}')
        .join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${logs.length} log line(s) copied to clipboard'),
          backgroundColor: DoctorTheme.accent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DoctorTheme.sheetBackground,
        title: const Text('Clear Logs?', style: DoctorTheme.cardTitleStyle),
        content: const Text(
          'This will permanently delete all logs from the database.',
          style: DoctorTheme.cardBodyStyle,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: DoctorTheme.error),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await Tracelet.clearLogs();
      await _fetchLogs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to clear logs: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    return Container(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.9),
      decoration: const BoxDecoration(
        color: DoctorTheme.sheetBackground,
        borderRadius: DoctorTheme.sheetRadius,
      ),
      child: Column(
        children: [
          _buildHandle(),
          _buildHeader(),
          const Divider(color: DoctorTheme.cardBorder, height: 1),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: DoctorTheme.accent),
                  )
                : _error != null
                ? Center(
                    child: Text(
                      'Error: $_error',
                      style: DoctorTheme.cardBodyStyle,
                    ),
                  )
                : _buildLogList(),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: DoctorTheme.accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.list_alt_rounded,
              color: DoctorTheme.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Device Logs', style: DoctorTheme.titleStyle),
                Text('Last 500 entries', style: DoctorTheme.cardBodyStyle),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, color: DoctorTheme.accent),
            tooltip: 'Copy logs',
            onPressed: _copyLogs,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: DoctorTheme.accent),
            tooltip: 'Refresh',
            onPressed: _fetchLogs,
          ),
          IconButton(
            icon: const Icon(
              Icons.delete_sweep_rounded,
              color: DoctorTheme.error,
            ),
            tooltip: 'Clear',
            onPressed: _clearLogs,
          ),
        ],
      ),
    );
  }

  Widget _buildLogList() {
    final logs = _logs;
    if (logs == null || logs.isEmpty) {
      return const Center(
        child: Text('No logs found', style: DoctorTheme.cardBodyStyle),
      );
    }
    return ListView.separated(
      padding: DoctorTheme.contentPadding,
      itemCount: logs.length,
      separatorBuilder: (_, __) =>
          const Divider(color: DoctorTheme.cardBorder, height: 1),
      itemBuilder: (context, index) {
        final log = logs[index];
        final isError = log.level.toUpperCase() == 'ERROR';
        final isWarn = log.level.toUpperCase() == 'WARN';
        final color = isError
            ? DoctorTheme.error
            : isWarn
            ? DoctorTheme.warning
            : DoctorTheme.textPrimary;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      log.level.toUpperCase(),
                      style: DoctorTheme.chipStyle.copyWith(
                        color: color,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    log.timestamp,
                    style: DoctorTheme.cardBodyStyle.copyWith(
                      fontSize: 10,
                      color: DoctorTheme.muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                log.message,
                style: DoctorTheme.cardBodyStyle.copyWith(fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}
