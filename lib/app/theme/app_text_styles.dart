import 'package:flutter/material.dart';

/// Named typography scale for PhongVu OpsHub.
///
/// The font family is SF Pro Display (Regular 400, Medium 500,
/// Semibold 600, Bold 700). Weight 800 (ExtraBold) is NOT shipped,
/// so all emphasis text uses w700 instead.
///
/// Usage: `style: AppTextStyles.headingM.copyWith(color: ...)`
class AppTextStyles {
  AppTextStyles._();

  static const String _fontFamily = 'SF Pro Display';

  // ── Headings ─────────────────────────────────────────────────────
  static const TextStyle headingXL = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle headingL = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle headingM = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle headingS = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w700,
  );

  // ── Body ─────────────────────────────────────────────────────────
  static const TextStyle bodyL = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle bodyM = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle bodyS = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
  );

  // ── Labels / Buttons ─────────────────────────────────────────────
  static const TextStyle labelL = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle labelM = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle labelS = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );

  // ── Caption / tiny ───────────────────────────────────────────────
  static const TextStyle caption = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
  );
  static const TextStyle captionBold = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w700,
  );

  // ── Emphasis (extra-bold normalized to w700) ─────────────────────
  /// Use for primary titles that need stronger emphasis.
  static const TextStyle titleEmphasis = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w700,
  );
}
