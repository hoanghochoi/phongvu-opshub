import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/theme/app_colors.dart';
import 'package:phongvu_opshub/app/theme/app_radius.dart';
import 'package:phongvu_opshub/app/theme/app_text_styles.dart';
import 'package:phongvu_opshub/app/theme/app_theme.dart';
import 'package:phongvu_opshub/app/widgets/app_buttons.dart';
import 'package:phongvu_opshub/app/widgets/app_layout.dart';

void main() {
  test('AppTheme maps Figma Foundation tokens into the light theme', () {
    final theme = AppTheme.lightTheme;

    expect(theme.colorScheme.primary, AppColors.primary);
    expect(theme.colorScheme.secondary, AppColors.secondary);
    expect(theme.colorScheme.surface, AppColors.surface);
    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(
      theme.textTheme.headlineLarge?.fontFamily,
      AppTextStyles.headingXL.fontFamily,
    );
    expect(theme.textTheme.headlineLarge?.fontSize, 28);
    expect(theme.textTheme.headlineLarge?.fontWeight, FontWeight.w700);
    expect(theme.textTheme.labelLarge?.fontSize, AppTextStyles.labelL.fontSize);
    expect(
      theme.textTheme.labelLarge?.fontWeight,
      AppTextStyles.labelL.fontWeight,
    );

    final inputBorder =
        theme.inputDecorationTheme.border! as OutlineInputBorder;
    expect(inputBorder.borderRadius, AppRadius.allMd);

    final cardShape = theme.cardTheme.shape! as RoundedRectangleBorder;
    expect(cardShape.borderRadius, AppRadius.allSm);

    final buttonStyle = theme.elevatedButtonTheme.style!;
    expect(
      buttonStyle.backgroundColor?.resolve(<WidgetState>{}),
      AppColors.primary,
    );
    expect(
      buttonStyle.textStyle?.resolve(<WidgetState>{}),
      AppTextStyles.labelL,
    );
  });

  test('legacy AppTheme aliases stay mapped during incremental migration', () {
    expect(AppTheme.primaryBlue, AppColors.primary);
    expect(AppTheme.white, AppColors.surface);
    expect(AppTheme.buttonColor, AppColors.primary);
  });

  test('shared layout and button metrics use design-system tokens', () {
    expect(AppLayoutTokens.cardRadius, AppRadius.sm);
    expect(AppLayoutTokens.cardPadding, 16);
    expect(AppLayoutTokens.mobileActionHeight, 48);
    expect(AppLayoutTokens.compactActionHeight, 44);
    expect(AppLayoutTokens.iconTouchTarget, 48);
    expect(AppLayoutTokens.listItemTouchTarget, 56);
    expect(AppLayoutTokens.mobileStickyActionBottomInset, 80);
    expect(AppButtonMetrics.radius, AppRadius.lg);
    expect(AppButtonMetrics.height, 52);
    expect(AppButtonMetrics.mobileActionHeight, 48);
    expect(AppButtonMetrics.compactActionHeight, 44);
    expect(AppButtonMetrics.iconSize, 48);
  });

  test('dark theme keeps context-aware foundation colors', () {
    final theme = AppTheme.darkTheme;

    expect(theme.colorScheme.primary, AppColors.darkPrimary);
    expect(theme.colorScheme.secondary, AppColors.darkSecondary);
    expect(theme.colorScheme.surface, AppColors.darkSurface);
    expect(theme.scaffoldBackgroundColor, AppColors.darkScaffold);

    final inputBorder =
        theme.inputDecorationTheme.border! as OutlineInputBorder;
    expect(inputBorder.borderRadius, AppRadius.allMd);
  });
}
