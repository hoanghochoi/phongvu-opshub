import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
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
        title: 'FIFO và bảo hành',
        description: 'Tác vụ vận hành gọn trong một workspace.',
      ),
      AuthShellHighlight(
        icon: Icons.admin_panel_settings_outlined,
        title: 'Phân quyền rõ',
        description: 'Truy cập theo cây tổ chức và tính năng được gán.',
      ),
    ],
  });

  @override
  Widget build(BuildContext context) {
    return AuthPage(maxWidth: maxWidth, highlights: highlights, child: child);
  }
}

class AuthPage extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final List<AuthShellHighlight> highlights;

  const AuthPage({
    super.key,
    required this.child,
    required this.highlights,
    this.maxWidth = AppLayoutTokens.authMaxWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvasOf(context),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop =
                constraints.maxWidth >= AppLayoutTokens.authDesktopBreakpoint;
            if (!isDesktop) {
              return AuthFormPanel(
                maxWidth: maxWidth,
                mobile: true,
                child: child,
              );
            }

            final preferredFormWidth = math.max(
              AppLayoutTokens.authFormPanelMinWidth,
              constraints.maxWidth * 0.44,
            );
            final maxFormWidth =
                constraints.maxWidth - AppLayoutTokens.authBrandPanelMinWidth;
            final formPanelWidth = math.min(preferredFormWidth, maxFormWidth);
            final brandPanelWidth = constraints.maxWidth - formPanelWidth;

            return Row(
              children: [
                SizedBox(
                  width: brandPanelWidth,
                  child: AuthBrandPanel(highlights: highlights),
                ),
                SizedBox(
                  width: formPanelWidth,
                  child: AuthFormPanel(maxWidth: maxWidth, child: child),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class AuthBrandPanel extends StatelessWidget {
  final List<AuthShellHighlight> highlights;

  const AuthBrandPanel({super.key, required this.highlights});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dense = constraints.maxHeight < 820;
        final padding = EdgeInsets.symmetric(
          horizontal: dense ? 40 : 56,
          vertical: dense ? 36 : 52,
        );
        return ColoredBox(
          color: AppColors.sidebarSurfaceOf(context),
          child: Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BrandHeader(dense: dense),
                SizedBox(height: dense ? 24 : 42),
                AuthBenefitList(highlights: highlights, dense: dense),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_rounded,
                      size: 18,
                      color: AppColors.sidebarMutedOf(context),
                    ),
                    const SizedBox(width: AppLayoutTokens.formInlineGap),
                    Expanded(
                      child: Text(
                        'Bảo mật bằng phân quyền và session nội bộ OpsHub.',
                        style:
                            (dense ? AppTextStyles.bodyS : AppTextStyles.labelM)
                                .copyWith(
                                  color: AppColors.sidebarMutedOf(context),
                                ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class BrandHeader extends StatelessWidget {
  final bool centered;
  final bool compact;
  final bool dense;

  const BrandHeader({
    super.key,
    this.centered = false,
    this.compact = false,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = compact
        ? AppColors.textPrimaryOf(context)
        : AppColors.sidebarTextOf(context);
    final mutedColor = compact
        ? AppColors.textSecondaryOf(context)
        : AppColors.sidebarMutedOf(context);
    final alignment = centered
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: alignment,
      children: [
        AppLogo(
          size: dense ? 64 : (compact ? 72 : 88),
          borderRadius: AppRadius.xxl,
        ),
        SizedBox(height: dense ? 12 : 16),
        Text(
          AppBrand.title,
          style:
              (dense
                      ? AppTextStyles.headingM
                      : compact
                      ? AppTextStyles.headingM
                      : AppTextStyles.headingXL)
                  .copyWith(color: textColor),
          textAlign: centered ? TextAlign.center : TextAlign.start,
        ),
        SizedBox(height: dense ? 4 : 8),
        Text(
          AppBrand.slogan,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: (dense ? AppTextStyles.bodyS : AppTextStyles.bodyM).copyWith(
            color: mutedColor,
          ),
        ),
        SizedBox(height: dense ? 12 : 18),
        Container(
          width: 52,
          height: 3,
          decoration: BoxDecoration(
            color: AppColors.primaryOf(context),
            borderRadius: AppRadius.allPill,
          ),
        ),
      ],
    );
  }
}

class MobileBrandHeader extends StatelessWidget {
  const MobileBrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return const BrandHeader(centered: true, compact: true);
  }
}

class AuthBrandHeader extends StatelessWidget {
  final bool compact;

  const AuthBrandHeader({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (compact) return const MobileBrandHeader();
    return const BrandHeader();
  }
}

class AuthBenefitList extends StatelessWidget {
  final List<AuthShellHighlight> highlights;
  final bool dense;

  const AuthBenefitList({
    super.key,
    required this.highlights,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 470),
      child: AppFormColumn(
        spacing: dense ? 8 : AppLayoutTokens.cardGap,
        children: [
          for (final highlight in highlights)
            _AuthBenefitTile(highlight: highlight, dense: dense),
        ],
      ),
    );
  }
}

class AuthFormPanel extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final bool mobile;

  const AuthFormPanel({
    super.key,
    required this.child,
    this.maxWidth = AppLayoutTokens.authMaxWidth,
    this.mobile = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = mobile
            ? const EdgeInsets.fromLTRB(20, 24, 20, 20)
            : const EdgeInsets.symmetric(horizontal: 48, vertical: 40);
        final minHeight = math.max(
          0.0,
          constraints.maxHeight - padding.vertical,
        );
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Column(
              mainAxisAlignment: mobile
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (mobile) ...[
                  const MobileBrandHeader(),
                  const SizedBox(height: AppLayoutTokens.sectionGap),
                ],
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: SizedBox(width: double.infinity, child: child),
                ),
                const SizedBox(height: AppLayoutTokens.formSectionGap),
                const AuthFooter(),
              ],
            ),
          ),
        );
      },
    );
  }
}

class LoginCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  const LoginCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact =
        MediaQuery.sizeOf(context).width < AppLayoutTokens.compactBreakpoint;
    final padding = EdgeInsets.all(
      isCompact
          ? AppLayoutTokens.authMobileCardPadding
          : AppLayoutTokens.authCardPadding,
    );
    return Semantics(
      container: true,
      label: title,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: AppRadius.allLg,
          border: Border.all(color: AppColors.borderOf(context)),
          boxShadow: AppShadowTokens.authCard(context),
        ),
        child: Padding(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.primarySurfaceOf(context),
                    borderRadius: AppRadius.allMd,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      icon,
                      size: 24,
                      color: AppColors.primaryOf(context),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppLayoutTokens.formFieldGap),
              Text(title, style: AppTextStyles.headingM),
              const SizedBox(height: 6),
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
    return LoginCard(
      icon: icon,
      title: title,
      subtitle: subtitle,
      child: child,
    );
  }
}

class AuthFooter extends StatelessWidget {
  const AuthFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      '© 2026 ${AppBrand.title}',
      textAlign: TextAlign.center,
      style: AppTextStyles.labelS.copyWith(
        color: AppColors.textMutedOf(context),
      ),
    );
  }
}

class _AuthBenefitTile extends StatefulWidget {
  final AuthShellHighlight highlight;
  final bool dense;

  const _AuthBenefitTile({required this.highlight, required this.dense});

  @override
  State<_AuthBenefitTile> createState() => _AuthBenefitTileState();
}

class _AuthBenefitTileState extends State<_AuthBenefitTile> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _focused;
    final borderColor = _focused
        ? AppColors.primaryOf(context)
        : AppColors.sidebarMutedOf(context).withValues(alpha: 0.24);
    return Semantics(
      container: true,
      label: widget.highlight.title,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.basic,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: AppColors.sidebarSelectedOf(
              context,
            ).withValues(alpha: active ? 0.18 : 0.10),
            borderRadius: AppRadius.allMd,
            border: Border.all(color: borderColor, width: _focused ? 2 : 1),
          ),
          child: Padding(
            padding: EdgeInsets.all(widget.dense ? 10 : 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.sidebarSelectedOf(
                      context,
                    ).withValues(alpha: active ? 0.22 : 0.14),
                    borderRadius: AppRadius.allMd,
                  ),
                  child: SizedBox.square(
                    dimension: widget.dense
                        ? AppLayoutTokens.authCompactBenefitIconSize
                        : AppLayoutTokens.authBenefitIconSize,
                    child: Icon(
                      widget.highlight.icon,
                      size: widget.dense ? 20 : 22,
                      color: AppColors.sidebarTextOf(context),
                    ),
                  ),
                ),
                const SizedBox(width: AppLayoutTokens.formInlineGap),
                Expanded(
                  child: Text(
                    widget.highlight.title,
                    style: AppTextStyles.labelM.copyWith(
                      color: AppColors.sidebarTextOf(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
