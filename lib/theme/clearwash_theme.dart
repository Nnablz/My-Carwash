import 'package:flutter/material.dart';

import '../models/carwash_order.dart';

/// Apple-inspired clean light POS design tokens, shadows, and typography helpers.
abstract final class ClearWashTheme {
  // Core Surface & Ink Tokens (60% Grouped Canvas / 30% Label Ink / 10% System Blue)
  static const Color canvas = Color(0xFFF2F2F7);
  static const Color surfaceCard = Color(0xFFFFFFFF);
  static const Color surfaceSubtle = Color(0xFFEAF4FF);
  static const Color slateInk = Color(0xFF1C1C1E);
  static const Color slateSecondary = Color(0xFF3A3A3C);
  static const Color slateMuted = Color(0xFF636366);
  static const Color slateSubtleText = Color(0xFF8E8E93);
  static const Color actionCobalt = Color(0xFF007AFF);
  static const Color brightCobalt = Color(0xFF0A84FF);
  static const Color borderSlate = Color(0xFFD1D1D6);
  static const Color borderHairline = Color(0xFFE5E5EA);

  // Operational Status Tokens (Apple System Semantics)
  static const Color waitingBg = Color(0xFFFFF4E5);
  static const Color waitingAccent = Color(0xFFFF9500);
  static const Color waitingText = Color(0xFFB25E00);

  static const Color washingBg = Color(0xFFEAF4FF);
  static const Color washingAccent = Color(0xFF007AFF);
  static const Color washingText = Color(0xFF0055B3);

  static const Color readyBg = Color(0xFFEAF9EF);
  static const Color readyAccent = Color(0xFF34C759);
  static const Color readyText = Color(0xFF1D7F38);

  static const Color errorRed = Color(0xFFFF3B30);
  static const Color errorBg = Color(0xFFFFECEB);
  static const Color errorBorder = Color(0xFFFFB4AF);

  // Lean Ponytail motion defaults
  static const Duration motionDuration = Duration(milliseconds: 180);
  static const Curve motionCurve = Curves.easeOutCubic;

  /// Soft Apple-style ambient shadow tinted slightly toward neutral slate.
  static List<BoxShadow> get softShadow => const [
    BoxShadow(
      color: Color(0x0A0F172A),
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
    BoxShadow(
      color: Color(0x050F172A),
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];

  /// Shared grouped card decoration following 8pt grid & subtle hairline elevation.
  static BoxDecoration cardDecoration({
    Color color = surfaceCard,
    Color? borderColor,
    double borderWidth = 0.8,
    double radius = 16,
    bool elevated = true,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ?? borderHairline,
        width: borderWidth,
      ),
      boxShadow: elevated ? softShadow : null,
    );
  }

  /// Shared Cupertino bottom sheet surface decoration.
  static BoxDecoration sheetDecoration() => const BoxDecoration(
    color: surfaceCard,
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  );

  /// Standard iOS sheet grabber handle shared across modal sheets.
  static Widget sheetGrabber() {
    return Center(
      child: Container(
        width: 36,
        height: 5,
        decoration: BoxDecoration(
          color: borderSlate,
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }

  /// Tabular numeric typography (proportional SF-style by default, monospace when [fixedWidth]).
  static TextStyle monoStyle({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w700,
    Color color = slateInk,
    double? letterSpacing,
    double? height,
    bool fixedWidth = false,
  }) {
    return TextStyle(
      fontFamily: fixedWidth ? 'monospace' : null,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  /// Crisp Apple-style section headline typography.
  static TextStyle headingStyle({
    double fontSize = 15,
    FontWeight fontWeight = FontWeight.w700,
    Color color = slateInk,
    double letterSpacing = -0.3,
  }) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
    );
  }

  /// Clean uppercase micro-label for grouped section headers and tags.
  static TextStyle sectionLabelStyle({
    double fontSize = 11.5,
    FontWeight fontWeight = FontWeight.w600,
    Color color = slateMuted,
    double letterSpacing = 0.5,
  }) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
    );
  }

  /// Resolves the background, border accent, and text foreground for an [OrderStatus].
  static ({Color background, Color accent, Color foreground}) statusPalette(
    OrderStatus status,
  ) {
    return switch (status) {
      OrderStatus.waiting => (
        background: waitingBg,
        accent: waitingAccent,
        foreground: waitingText,
      ),
      OrderStatus.washing => (
        background: washingBg,
        accent: washingAccent,
        foreground: washingText,
      ),
      OrderStatus.ready => (
        background: readyBg,
        accent: readyAccent,
        foreground: readyText,
      ),
      OrderStatus.completed => (
        background: const Color(0xFFF1F5F9),
        accent: borderSlate,
        foreground: slateSecondary,
      ),
      OrderStatus.cancelled => (
        background: errorBg,
        accent: errorBorder,
        foreground: errorRed,
      ),
    };
  }
}
