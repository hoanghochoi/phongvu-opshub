import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/theme/app_colors.dart';
import 'package:phongvu_opshub/app/theme/app_radius.dart';
import 'package:phongvu_opshub/app/theme/app_text_styles.dart';
import 'package:phongvu_opshub/app/theme/app_theme.dart';
import 'package:phongvu_opshub/app/widgets/app_buttons.dart';
import 'package:phongvu_opshub/app/widgets/app_feature_grid.dart';
import 'package:phongvu_opshub/app/widgets/app_layout.dart';
import 'package:phongvu_opshub/app/widgets/app_inputs.dart';

void main() {
  testWidgets('mobile typography density leaves tablet and desktop unchanged', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const markerKey = Key('responsive-typography-marker');
    const app = MaterialApp(
      home: AppMobileTypographyDensity(child: SizedBox(key: markerKey)),
    );

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpWidget(app);
    expect(
      MediaQuery.textScalerOf(tester.element(find.byKey(markerKey))).scale(16),
      closeTo(16 * AppMobileTypographyDensity.scale, 0.01),
    );

    tester.view.physicalSize = const Size(834, 1112);
    await tester.pumpWidget(app);
    expect(
      MediaQuery.textScalerOf(tester.element(find.byKey(markerKey))).scale(16),
      16,
    );
  });

  test('AppTheme maps Figma Foundation tokens into the light theme', () {
    final theme = AppTheme.lightTheme;

    expect(theme.textTheme.bodyMedium?.fontFamily, 'Be Vietnam Pro');
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
    expect(theme.inputDecorationTheme.errorBorder!.borderSide.width, 2);

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

  test('shared layout and button metrics use design-system tokens', () {
    expect(AppLayoutTokens.cardRadius, AppRadius.sm);
    expect(AppLayoutTokens.cardPadding, 16);
    expect(AppLayoutTokens.mobileActionHeight, 48);
    expect(AppLayoutTokens.compactActionHeight, 44);
    expect(AppLayoutTokens.iconTouchTarget, 48);
    expect(AppLayoutTokens.listItemTouchTarget, 56);
    expect(AppLayoutTokens.mobileBottomNavHeight, 76);
    expect(AppLayoutTokens.compactMobileBottomNavHeight, 76);
    expect(AppLayoutTokens.mobileStickyActionBottomInset, 72);
    expect(AppLayoutTokens.authMaxWidth, 360);
    expect(AppLayoutTokens.authCardPadding, 16);
    expect(AppLayoutTokens.authMobileCardPadding, 16);
    expect(AppButtonMetrics.radius, AppRadius.md);
    expect(AppButtonMetrics.height, 52);
    expect(AppButtonMetrics.smallHeight, 40);
    expect(AppButtonMetrics.mediumHeight, 48);
    expect(AppButtonMetrics.largeHeight, 52);
    expect(
      AppButtonMetrics.horizontalPadding,
      const EdgeInsets.symmetric(horizontal: 20),
    );
    expect(AppButtonMetrics.gap, 8);
    expect(
      AppInputMetrics.contentPadding,
      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
    expect(AppButtonMetrics.mobileActionHeight, 48);
    expect(AppButtonMetrics.compactActionHeight, 44);
    expect(AppButtonMetrics.iconSize, 48);
  });

  test('dark theme keeps context-aware foundation colors', () {
    final theme = AppTheme.darkTheme;

    expect(theme.textTheme.bodyMedium?.fontFamily, 'Be Vietnam Pro');
    expect(theme.colorScheme.primary, AppColors.darkPrimary);
    expect(theme.colorScheme.secondary, AppColors.darkSecondary);
    expect(theme.colorScheme.surface, AppColors.darkSurface);
    expect(theme.scaffoldBackgroundColor, AppColors.darkScaffold);

    final inputBorder =
        theme.inputDecorationTheme.border! as OutlineInputBorder;
    expect(inputBorder.borderRadius, AppRadius.allMd);
    final errorBorder = theme.inputDecorationTheme.errorBorder!;
    expect(errorBorder.borderSide.width, 2);
    expect(theme.dialogTheme.backgroundColor, AppColors.darkCard);
    expect(theme.dialogTheme.titleTextStyle?.color, AppColors.darkTextPrimary);
    expect(
      theme.dialogTheme.contentTextStyle?.color,
      AppColors.darkTextSecondary,
    );
  });

  testWidgets('status tokens resolve to the Figma dark semantic mode', (
    tester,
  ) async {
    BuildContext? captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(
      AppColors.statusColorOf(captured!, 'success'),
      AppColors.darkSuccess,
    );
    expect(
      AppColors.statusSurfaceOf(captured!, 'success'),
      AppColors.darkSuccessSurface,
    );
    expect(AppColors.statusColorOf(captured!, 'error'), AppColors.darkError);
    expect(
      AppColors.statusSurfaceOf(captured!, 'error'),
      AppColors.darkErrorSurface,
    );
  });

  testWidgets('shared dark widgets use semantic Figma surfaces and text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: AppFeatureSection(
            title: 'Chức năng',
            actions: [
              AppFeatureAction(
                icon: Icons.apps_outlined,
                title: 'Công cụ',
                description: 'Mô tả',
                color: AppColors.darkPrimary,
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );

    final title = tester.widget<Text>(find.text('Chức năng'));
    expect(title.style?.color, AppColors.darkTextPrimary);

    final tileMaterial = tester.widget<Material>(
      find.descendant(
        of: find.byType(AppFeatureTile),
        matching: find.byType(Material),
      ),
    );
    expect(tileMaterial.color, AppColors.darkCard);

    final actionDescription = tester.widget<Text>(find.text('Mô tả'));
    expect(actionDescription.style?.color, AppColors.darkTextSecondary);
  });
}
