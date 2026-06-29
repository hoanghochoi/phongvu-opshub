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

  // ── Design-system semantic colours (Figma Foundation/Color 2026) ─
  static const Color primary = Color(0xFF0A66C2);
  static const Color secondary = Color(0xFF0F766E);
  static const Color accent = Color(0xFF7C3AED);

  // ── Gradient (header / nav) ──────────────────────────────────────
  static const Color gradientStart = Color(0xFF07539F);
  static const Color gradientMid = primary;
  static const Color gradientEnd = Color(0xFF3B82F6);

  // ── Semantic ─────────────────────────────────────────────────────
  static const Color info = Color(0xFF2563EB);
  static const Color success = Color(0xFF12805C);
  static const Color warning = Color(0xFFB7791F);
  static const Color error = Color(0xFFC2410C);
  static const Color danger = error;
  static const Color teal600 = secondary; // VietQR
  static const Color violet600 = accent; // Payment monitor
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
  static const Color background = Color(0xFFF7F8FB);
  static const Color card = surface;
  static const Color transparent = Color(0x00000000);
  static const Color shadow = Color(0xFF000000);
  static const Color border = Color(0xFFD8DEE8);
  static const Color divider = Color(0xFFE6EAF0);
  static const Color hover = Color(0xFFEAF3FF);
  static const Color pressed = Color(0xFFD8EAFE);
  static const Color focus = info;
  static const Color disabled = neutral400;
  static const Color onSurface = Color(0xFF111827);
  static const Color onSurfaceVariant = Color(0xFF64748B);

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
  static const Color darkPrimary = Color(0xFF6EB6FF);
  static const Color darkSecondary = Color(0xFF5EEAD4);
  static const Color darkAccent = Color(0xFFC4B5FD);
  static const Color darkInfo = Color(0xFF93C5FD);
  static const Color darkSuccess = Color(0xFF34D399);
  static const Color darkWarning = Color(0xFFFBBF24);
  static const Color darkError = Color(0xFFFB7185);
  static const Color darkSurface = Color(0xFF111827);
  static const Color darkCard = Color(0xFF172033);
  static const Color darkScaffold = Color(0xFF0B1220);
  static const Color darkBorder = Color(0xFF334155);
  static const Color darkDivider = Color(0xFF1F2937);
  static const Color darkTextPrimary = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFFCBD5E1);
  static const Color darkChipBg = Color(0xFF2A2A2A);
  static const Color darkNeutral50 = Color(0xFF1A1A1A);
  static const Color darkNeutral100 = Color(0xFF2D2D2D);
  static const Color darkGradientStart = Color(0xFF0B1220);
  static const Color darkGradientMid = Color(0xFF1E3A5F);
  static const Color darkGradientEnd = Color(0xFF25476F);
}
