import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_logo.dart';
import '../../../../core/config/app_brand.dart';

class AuthScreenShell extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final List<AuthShellHighlight> highlights;

  const AuthScreenShell({
    super.key,
    required this.child,
    this.maxWidth = AppLayoutTokens.authMaxWidth,
    this.highlights = const [
      AuthShellHighlight(
        icon: Icons.qr_code_2_rounded,
        title: 'VietQR realtime',
        description: 'Theo dõi QR, đối soát và thông báo theo quyền.',
      ),
      AuthShellHighlight(
        icon: Icons.inventory_2_outlined,
        title: 'FIFO và BH/SC',
        description: 'Tác vụ vận hành gọn trong một workspace.',
      ),
      AuthShellHighlight(
        icon: Icons.admin_panel_settings_outlined,
        title: 'Phân quyền rõ',
        description: 'Truy cập theo cây tổ chức và feature được gán.',
      ),
    ],
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvasOf(context),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop =
                constraints.maxWidth >= AppLayoutTokens.desktopBreakpoint;
            if (!isDesktop) {
              return AppResponsiveScrollView(
                maxWidth: maxWidth,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const AuthBrandHeader(compact: true),
                    const SizedBox(height: AppLayoutTokens.sectionGap),
                    child,
                    const SizedBox(height: AppLayoutTokens.formSectionGap),
                    Text(
                      '© 2026 ${AppBrand.title}',
                      style: AppTextStyles.labelS.copyWith(
                        color: AppColors.textMutedOf(context),
                      ),
                    ),
                  ],
                ),
              );
            }

            return Row(
              children: [
                Expanded(
                  flex: 5,
                  child: AuthBrandPanel(highlights: highlights),
                ),
                Expanded(
                  flex: 4,
                  child: AppResponsiveScrollView(
                    maxWidth: maxWidth,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 56,
                      vertical: 40,
                    ),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: child,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class AuthCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  const AuthCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: const EdgeInsets.all(24),
      borderColor: AppColors.borderOf(context),
      backgroundColor: AppColors.cardOf(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.primarySurfaceOf(context),
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(icon, color: AppColors.primaryOf(context)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(title, style: AppTextStyles.headingM),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: AppTextStyles.bodyM.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: AppLayoutTokens.formSectionGap),
          child,
        ],
      ),
    );
  }
}

class AuthBrandHeader extends StatelessWidget {
  final bool compact;

  const AuthBrandHeader({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final textColor = compact
        ? AppColors.textPrimaryOf(context)
        : AppColors.sidebarTextOf(context);
    final mutedColor = compact
        ? AppColors.textSecondaryOf(context)
        : AppColors.sidebarMutedOf(context);
    return Column(
      children: [
        AppLogo(size: compact ? 72 : 88, borderRadius: AppRadius.xxl),
        const SizedBox(height: 16),
        Text(
          AppBrand.title,
          style: (compact ? AppTextStyles.headingL : AppTextStyles.headingXL)
              .copyWith(color: textColor),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Trung tâm tác vụ vận hành nội bộ',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyM.copyWith(color: mutedColor),
        ),
      ],
    );
  }
}

class AuthBrandPanel extends StatelessWidget {
  final List<AuthShellHighlight> highlights;

  const AuthBrandPanel({super.key, required this.highlights});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.sidebarSurfaceOf(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AuthBrandHeader(),
            const Spacer(),
            Text(
              'Một tài khoản cho FIFO, BH/SC, VietQR, sao kê, cấn trừ và báo cáo sale.',
              style: AppTextStyles.headingS.copyWith(
                color: AppColors.sidebarTextOf(context),
              ),
            ),
            const SizedBox(height: AppLayoutTokens.sectionGap),
            AppFormColumn(
              spacing: AppLayoutTokens.cardGap,
              children: [
                for (final highlight in highlights)
                  _AuthHighlightTile(highlight: highlight),
              ],
            ),
            const Spacer(),
            Text(
              'Bảo mật bằng phân quyền và session nội bộ OpsHub.',
              style: AppTextStyles.labelM.copyWith(
                color: AppColors.sidebarMutedOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthHighlightTile extends StatelessWidget {
  final AuthShellHighlight highlight;

  const _AuthHighlightTile({required this.highlight});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.sidebarSelectedOf(context).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
        border: Border.all(
          color: AppColors.sidebarMutedOf(context).withValues(alpha: 0.24),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(highlight.icon, color: AppColors.sidebarTextOf(context)),
            const SizedBox(width: AppLayoutTokens.formInlineGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    highlight.title,
                    style: AppTextStyles.labelM.copyWith(
                      color: AppColors.sidebarTextOf(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    highlight.description,
                    style: AppTextStyles.bodyS.copyWith(
                      color: AppColors.sidebarMutedOf(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthShellHighlight {
  final IconData icon;
  final String title;
  final String description;

  const AuthShellHighlight({
    required this.icon,
    required this.title,
    required this.description,
  });
}
