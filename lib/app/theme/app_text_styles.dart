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
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 36 / 28,
  );
  static const TextStyle headingL = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 32 / 24,
  );
  static const TextStyle headingM = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 28 / 20,
  );
  static const TextStyle headingS = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 24 / 18,
  );

  // ── Body ─────────────────────────────────────────────────────────
  static const TextStyle bodyL = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 24 / 16,
  );
  static const TextStyle bodyM = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 20 / 14,
  );
  static const TextStyle bodyS = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 20 / 13,
  );

  // ── Labels / Buttons ─────────────────────────────────────────────
  static const TextStyle labelL = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 20 / 16,
  );
  static const TextStyle labelM = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 20 / 14,
  );
  static const TextStyle labelS = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 16 / 12,
  );

  // ── Caption / tiny ───────────────────────────────────────────────
  static const TextStyle caption = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 16 / 11,
  );
  static const TextStyle captionBold = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 16 / 11,
  );

  // ── Emphasis (extra-bold normalized to w700) ─────────────────────
  /// Use for primary titles that need stronger emphasis.
  static const TextStyle titleEmphasis = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w700,
    height: 24 / 17,
  );
}
