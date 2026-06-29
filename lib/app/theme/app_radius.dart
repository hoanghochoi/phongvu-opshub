import 'package:flutter/material.dart';

/// Standardised border-radius scale for PhongVu OpsHub.
///
/// | Token | Value | Typical usage                        |
/// |-------|-------|--------------------------------------|
/// | xs    |  4    | message bubbles, tiny chips          |
/// | sm    |  8    | cards, feature tiles, CardTheme      |
/// | md    | 12    | inputs, chat bubbles, tabs           |
/// | lg    | 16    | buttons, logo                        |
/// | xl    | 20    | large elements                       |
/// | xxl   | 24    | large dialogs and auth screens       |
/// | pill  | 9999  | pill shapes                          |
class AppRadius {
  AppRadius._();

  // ── Raw values ───────────────────────────────────────────────────
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double pill = 9999;

  // ── Pre-built BorderRadius (all-corners) ─────────────────────────
  static final BorderRadius allXs = BorderRadius.circular(xs);
  static final BorderRadius allSm = BorderRadius.circular(sm);
  static final BorderRadius allMd = BorderRadius.circular(md);
  static final BorderRadius allLg = BorderRadius.circular(lg);
  static final BorderRadius allXl = BorderRadius.circular(xl);
  static final BorderRadius allXxl = BorderRadius.circular(xxl);
  static final BorderRadius allPill = BorderRadius.circular(pill);
}
