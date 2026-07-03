import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_feature_grid.dart';
import '../../../../app/widgets/app_layout.dart';

class WarrantyMainScreen extends StatelessWidget {
  final VoidCallback? onBackToHome;

  const WarrantyMainScreen({super.key, this.onBackToHome});

  @override
  Widget build(BuildContext context) {
    final actions = [
      AppFeatureAction(
        icon: Icons.add_photo_alternate_rounded,
        title: 'Lưu hình ảnh',
        description: 'Ghi nhận BH/SC',
        color: AppColors.success,
        onTap: () => context.push('/warranty'),
      ),
      AppFeatureAction(
        icon: Icons.search_rounded,
        title: 'Xem lại hình ảnh',
        description: 'Tìm theo biên nhận',
        color: AppColors.teal600,
        onTap: () => context.push('/check-warranty'),
      ),
    ];

    return AppResponsiveScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WarrantyMainHeader(onBackToHome: onBackToHome),
          const SizedBox(height: AppLayoutTokens.sectionGap),
          AppFeatureSection(title: 'Tác vụ BH / SC', actions: actions),
        ],
      ),
    );
  }
}

class _WarrantyMainHeader extends StatelessWidget {
  final VoidCallback? onBackToHome;

  const _WarrantyMainHeader({required this.onBackToHome});

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('warranty-main-header'),
      backgroundColor: AppColors.primarySurface,
      borderColor: AppColors.primary.withValues(alpha: 0.18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < AppLayoutTokens.tabletBreakpoint;
          final icon = Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
            ),
            child: const Icon(
              Icons.home_repair_service_rounded,
              color: AppColors.primary,
            ),
          );
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bảo hành / Sửa chữa', style: AppTextStyles.headingM),
              const SizedBox(height: 6),
              Text(
                'Lưu ảnh biên nhận và xem lại trạng thái xử lý theo số biên nhận hoặc mã sửa chữa.',
                style: AppTextStyles.bodyM.copyWith(
                  color: AppColors.neutral600,
                  height: 1.35,
                ),
              ),
            ],
          );
          final backButton = onBackToHome == null
              ? null
              : AppSecondaryButton(
                  onPressed: onBackToHome,
                  icon: Icons.home_outlined,
                  label: 'Về trang chủ',
                  expand: false,
                );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    icon,
                    if (backButton != null) ...[const Spacer(), backButton],
                  ],
                ),
                const SizedBox(height: 14),
                title,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              icon,
              const SizedBox(width: AppLayoutTokens.formInlineGap),
              Expanded(
                child: SizedBox(width: double.infinity, child: title),
              ),
              if (backButton != null) ...[
                const SizedBox(width: AppLayoutTokens.formInlineGap),
                backButton,
              ],
            ],
          );
        },
      ),
    );
  }
}
