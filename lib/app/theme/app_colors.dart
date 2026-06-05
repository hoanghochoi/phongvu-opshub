import 'package:flutter/material.dart';

/// Centralised colour palette for PhongVu OpsHub.
///
/// Every colour used in the app MUST come from this class.
/// When adding dark-mode support, add a `darkX` variant or use
/// [ThemeExtension] to expose context-aware colours.
class AppColors {
  AppColors._();

  // ── Primary scale ────────────────────────────────────────────────
  static const Color primary50 = Color(0xFFEEF0FB);
  static const Color primary100 = Color(0xFFCCD3F4);
  static const Color primary200 = Color(0xFF99A7E9);
  static const Color primary300 = Color(0xFF667BDE);
  static const Color primary400 = Color(0xFF334FD3);
  static const Color primary500 = Color(0xFF1435C3); // brand blue
  static const Color primary600 = Color(0xFF102A9C);
  static const Color primary700 = Color(0xFF0D1F75);
  static const Color primary800 = Color(0xFF091550);
  static const Color primary900 = Color(0xFF050A28);

  // ── Gradient (header / nav) ──────────────────────────────────────
  static const Color gradientStart = Color(0xFF0D1B6F);
  static const Color gradientMid = Color(0xFF1E3A8A);
  static const Color gradientEnd = Color(0xFF3B5FCC);

  // ── Semantic ─────────────────────────────────────────────────────
  static const Color info = Color(0xFF2563EB);
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFD97706);
  static const Color error = Color(0xFFDC2626);
  static const Color teal600 = Color(0xFF0F766E); // VietQR
  static const Color violet600 = Color(0xFF7C3AED); // Payment monitor
  static const Color indigo600 = Color(0xFF4F46E5);
  static const Color purple600 = Color(0xFF9333EA);
  static const Color emerald600 = Color(0xFF059669);
  static const Color sky500 = Color(0xFF0EA5E9);
  static const Color amber500 = Color(0xFFF59E0B);

  // ── Neutral / Grey scale ─────────────────────────────────────────
  static const Color neutral50 = Color(0xFFF5F7FB); // scaffold bg
  static const Color neutral100 = Color(0xFFE5E7EB);
  static const Color neutral200 = Color(0xFFD1D5DB);
  static const Color neutral300 = Color(0xFFB6BCC5);
  static const Color neutral400 = Color(0xFF9CA3AF);
  static const Color neutral500 = Color(0xFF6B7280);
  static const Color neutral600 = Color(0xFF4B5563);
  static const Color neutral700 = Color(0xFF374151);
  static const Color neutral800 = Color(0xFF1F2937);
  static const Color neutral900 = Color(0xFF111827);

  // ── Surface ──────────────────────────────────────────────────────
  static const Color surface = Color(0xFFFFFFFF);
  static const Color onSurface = neutral900;
  static const Color onSurfaceVariant = neutral500;

  // ── Chip / tag background ────────────────────────────────────────
  static const Color chipBackground = Color(0xFFF1F5F9);

  // ── Helpers ──────────────────────────────────────────────────────

  /// Maps an [AppStateTone]-like keyword to a colour.
  /// Used by [AppStatePanel], [AppStatusBanner], and shared chips.
  static Color toneColor(String tone) {
    return switch (tone) {
      'info' => info,
      'success' => success,
      'warning' => warning,
      'error' => error,
      _ => neutral500,
    };
  }

  // ── Dark-mode variants ────────────────────────────────────────────
  static const Color darkSurface = Color(0xFF121212);
  static const Color darkCard = Color(0xFF1E1E1E);
  static const Color darkScaffold = Color(0xFF0F0F0F);
  static const Color darkChipBg = Color(0xFF2A2A2A);
  static const Color darkNeutral50 = Color(0xFF1A1A1A);
  static const Color darkNeutral100 = Color(0xFF2D2D2D);
  static const Color darkGradientStart = Color(0xFF080E30);
  static const Color darkGradientMid = Color(0xFF0F1D4D);
  static const Color darkGradientEnd = Color(0xFF1E3070);
}
