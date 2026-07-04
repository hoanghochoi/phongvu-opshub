import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_text_styles.dart';
import '../widgets/app_inputs.dart';

class AppTheme {
  AppTheme._();

  // ── Legacy accessors (kept for incremental migration) ────────────
  static const Color primaryBlue = AppColors.primary;
  static const Color white = AppColors.surface;
  static const Color buttonColor = primaryBlue;

  // ── Light theme ──────────────────────────────────────────────────
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'SF Pro Display',
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.surface,
        error: AppColors.error,
      ),
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.surface,
        surfaceTintColor: AppColors.primary,
        titleTextStyle: AppTextStyles.headingM.copyWith(
          color: AppColors.surface,
        ),
        iconTheme: const IconThemeData(color: AppColors.surface),
      ),
      textTheme: const TextTheme(
        headlineLarge: AppTextStyles.headingXL,
        headlineMedium: AppTextStyles.headingL,
        headlineSmall: AppTextStyles.headingM,
        titleLarge: AppTextStyles.headingS,
        titleMedium: AppTextStyles.labelL,
        titleSmall: AppTextStyles.labelM,
        bodyLarge: AppTextStyles.bodyL,
        bodyMedium: AppTextStyles.bodyM,
        bodySmall: AppTextStyles.bodyS,
        labelLarge: AppTextStyles.labelL,
        labelMedium: AppTextStyles.labelM,
        labelSmall: AppTextStyles.labelS,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: AppRadius.allMd,
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.allMd,
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.allMd,
          borderSide: const BorderSide(color: AppColors.focus, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.allMd,
          borderSide: const BorderSide(color: AppColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.allMd,
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        prefixIconConstraints: const BoxConstraints.tightFor(
          width: AppInputMetrics.iconBoxSize,
          height: AppInputMetrics.iconBoxSize,
        ),
        suffixIconConstraints: const BoxConstraints.tightFor(
          width: AppInputMetrics.iconBoxSize,
          height: AppInputMetrics.iconBoxSize,
        ),
        contentPadding: AppInputMetrics.contentPadding,
        constraints: const BoxConstraints(minHeight: AppInputMetrics.height),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.surface,
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.allLg),
          elevation: 0,
          textStyle: AppTextStyles.labelL,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.allLg),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(48, 48),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shadowColor: AppColors.shadow.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.allSm),
      ),
      dividerColor: AppColors.divider,
    );
  }

  // ── Dark theme ─────────────────────────────────────────────────
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'SF Pro Display',
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.darkPrimary,
        brightness: Brightness.dark,
        primary: AppColors.darkPrimary,
        secondary: AppColors.darkSecondary,
        surface: AppColors.darkSurface,
        error: AppColors.darkError,
      ),
      scaffoldBackgroundColor: AppColors.darkScaffold,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: AppColors.transparent,
        foregroundColor: AppColors.surface,
        surfaceTintColor: AppColors.transparent,
        titleTextStyle: AppTextStyles.headingM.copyWith(
          color: AppColors.surface,
        ),
        iconTheme: const IconThemeData(color: AppColors.surface),
      ),
      textTheme: TextTheme(
        headlineLarge: AppTextStyles.headingXL.copyWith(
          color: AppColors.darkTextPrimary,
        ),
        headlineMedium: AppTextStyles.headingL.copyWith(
          color: AppColors.darkTextPrimary,
        ),
        headlineSmall: AppTextStyles.headingM.copyWith(
          color: AppColors.darkTextPrimary,
        ),
        titleLarge: AppTextStyles.headingS.copyWith(
          color: AppColors.darkTextPrimary,
        ),
        titleMedium: AppTextStyles.labelL.copyWith(
          color: AppColors.darkTextSecondary,
        ),
        titleSmall: AppTextStyles.labelM.copyWith(
          color: AppColors.darkTextSecondary,
        ),
        bodyLarge: AppTextStyles.bodyL.copyWith(
          color: AppColors.darkTextSecondary,
        ),
        bodyMedium: AppTextStyles.bodyM.copyWith(
          color: AppColors.darkTextSecondary,
        ),
        bodySmall: AppTextStyles.bodyS.copyWith(color: AppColors.neutral300),
        labelLarge: AppTextStyles.labelL.copyWith(
          color: AppColors.darkTextSecondary,
        ),
        labelMedium: AppTextStyles.labelM.copyWith(
          color: AppColors.darkTextSecondary,
        ),
        labelSmall: AppTextStyles.labelS.copyWith(color: AppColors.neutral300),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkNeutral50,
        border: OutlineInputBorder(
          borderRadius: AppRadius.allMd,
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.allMd,
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.allMd,
          borderSide: const BorderSide(color: AppColors.darkPrimary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.allMd,
          borderSide: const BorderSide(color: AppColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.allMd,
          borderSide: const BorderSide(color: AppColors.darkError, width: 2),
        ),
        prefixIconConstraints: const BoxConstraints.tightFor(
          width: AppInputMetrics.iconBoxSize,
          height: AppInputMetrics.iconBoxSize,
        ),
        suffixIconConstraints: const BoxConstraints.tightFor(
          width: AppInputMetrics.iconBoxSize,
          height: AppInputMetrics.iconBoxSize,
        ),
        contentPadding: AppInputMetrics.contentPadding,
        constraints: const BoxConstraints(minHeight: AppInputMetrics.height),
        labelStyle: const TextStyle(color: AppColors.neutral400),
        hintStyle: const TextStyle(color: AppColors.neutral500),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.darkPrimary,
          foregroundColor: AppColors.darkScaffold,
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.allLg),
          elevation: 0,
          textStyle: AppTextStyles.labelL,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.darkPrimary,
          side: const BorderSide(color: AppColors.darkPrimary),
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.allLg),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.darkPrimary,
          minimumSize: const Size(48, 48),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkCard,
        elevation: 0,
        shadowColor: AppColors.shadow.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.allSm),
      ),
      dividerColor: AppColors.darkDivider,
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.neutral800,
        contentTextStyle: AppTextStyles.bodyM.copyWith(
          color: AppColors.neutral100,
        ),
      ),
    );
  }
}
