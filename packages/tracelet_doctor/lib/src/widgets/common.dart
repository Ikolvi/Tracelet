import 'package:flutter/material.dart';

import 'package:tracelet_doctor/src/doctor_theme.dart';

/// A reusable status chip showing a colored dot and label.
class StatusChip extends StatelessWidget {
  /// Creates a [StatusChip].
  const StatusChip({required this.label, required this.color, super.key});

  /// The text label to display.
  final String label;

  /// The status color (dot + text tint).
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: DoctorTheme.chipStyle.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// A diagnostic card container with header icon, title, and child content.
class DiagnosticCard extends StatelessWidget {
  /// Creates a [DiagnosticCard].
  const DiagnosticCard({
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
    super.key,
  });

  /// Leading icon.
  final IconData icon;

  /// Card title.
  final String title;

  /// Trailing widget (e.g. a [StatusChip]).
  final Widget? trailing;

  /// Card body content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: DoctorTheme.cardDecoration,
      padding: DoctorTheme.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: DoctorTheme.accent),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: DoctorTheme.cardTitleStyle)),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// A key-value row inside a [DiagnosticCard].
class InfoRow extends StatelessWidget {
  /// Creates an [InfoRow].
  const InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
    super.key,
  });

  /// The label text.
  final String label;

  /// The value text.
  final String value;

  /// Optional override color for the value text.
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      // Both label and value are Flexible so a long value (e.g. lifetime
      // stats) wraps or shrinks instead of overflowing the card (fixes the
      // RenderFlex right-overflow seen in the Database card's stats).
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(child: Text(label, style: DoctorTheme.cardBodyStyle)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: DoctorTheme.cardBodyStyle.copyWith(
                color: valueColor ?? DoctorTheme.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A boolean indicator row with a ✓ or ✗ icon.
class BoolRow extends StatelessWidget {
  /// Creates a [BoolRow].
  const BoolRow({
    required this.label,
    required this.value,
    this.invertColor = false,
    super.key,
  });

  /// The label text.
  final String label;

  /// The boolean value.
  final bool value;

  /// If true, `true` shows red and `false` shows green (inverted semantics).
  final bool invertColor;

  @override
  Widget build(BuildContext context) {
    final isGood = invertColor ? !value : value;
    final color = isGood ? DoctorTheme.success : DoctorTheme.error;
    final icon = isGood ? Icons.check_circle_rounded : Icons.cancel_rounded;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: DoctorTheme.cardBodyStyle),
          Icon(icon, size: 16, color: color),
        ],
      ),
    );
  }
}
