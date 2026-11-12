// Not package:material_ui yet: it needs Flutter >= 3.47 and this package
// still supports older versions.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

/// Visual theme constants for the TraceletDoctor overlay.
///
/// Uses a dark, glassmorphic aesthetic with semantic status colors.
class DoctorTheme {
  DoctorTheme._();

  // ---------------------------------------------------------------------------
  // Colors
  // ---------------------------------------------------------------------------

  /// Background of the bottom sheet.
  static const Color sheetBackground = Color(0xFF1A1A2E);

  /// Surface color for cards.
  static const Color cardSurface = Color(0xFF16213E);

  /// Card border color.
  static const Color cardBorder = Color(0xFF1E3A5F);

  /// Primary accent (Tracelet blue).
  static const Color accent = Color(0xFF4FC3F7);

  /// Healthy / success state.
  static const Color success = Color(0xFF66BB6A);

  /// Warning state.
  static const Color warning = Color(0xFFFFA726);

  /// Error / critical state.
  static const Color error = Color(0xFFEF5350);

  /// Muted / inactive text.
  static const Color muted = Color(0xFF90A4AE);

  /// Primary text.
  static const Color textPrimary = Color(0xFFF5F5F5);

  /// Secondary text.
  static const Color textSecondary = Color(0xFFB0BEC5);

  // ---------------------------------------------------------------------------
  // Typography
  // ---------------------------------------------------------------------------

  /// Title style.
  static const TextStyle titleStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: 0.5,
  );

  /// Section header style.
  static const TextStyle sectionStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: muted,
    letterSpacing: 1.2,
  );

  /// Card title style.
  static const TextStyle cardTitleStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  /// Card body style.
  static const TextStyle cardBodyStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: textSecondary,
    height: 1.4,
  );

  /// Status chip style.
  static const TextStyle chipStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
  );

  // ---------------------------------------------------------------------------
  // Decorations
  // ---------------------------------------------------------------------------

  /// Standard card decoration.
  static BoxDecoration cardDecoration = BoxDecoration(
    color: cardSurface,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: cardBorder, width: 0.5),
  );

  /// Sheet border radius.
  static const BorderRadius sheetRadius = BorderRadius.only(
    topLeft: Radius.circular(24),
    topRight: Radius.circular(24),
  );

  // ---------------------------------------------------------------------------
  // Spacing
  // ---------------------------------------------------------------------------

  /// Default content padding.
  static const EdgeInsets contentPadding = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 12,
  );

  /// Card internal padding.
  static const EdgeInsets cardPadding = EdgeInsets.all(16);

  /// Spacing between cards.
  static const double cardSpacing = 12;
}
