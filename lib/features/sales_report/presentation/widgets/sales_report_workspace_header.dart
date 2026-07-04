import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_layout.dart';

class SalesReportWorkspaceHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> chips;

  const SalesReportWorkspaceHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.chips = const [],
  });

  @override
  Widget build(BuildContext context) {
    final navigator = Navigator.of(context);
    final canPop = navigator.canPop();
    return AppSurfaceCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final leading = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canPop) ...[
                AppIconAction(
                  onPressed: () => navigator.maybePop(),
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Quay lại',
                ),
                const SizedBox(width: 8),
              ],
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(
                    AppLayoutTokens.cardRadius,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(icon, color: AppColors.primary),
                ),
              ),
            ],
          );
          final titleBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.headingS),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: AppTextStyles.bodyS.copyWith(
                  color: AppColors.neutral600,
                ),
              ),
              if (chips.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: chips),
              ],
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [leading, const SizedBox(height: 12), titleBlock],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading,
              const SizedBox(width: 16),
              Expanded(child: titleBlock),
            ],
          );
        },
      ),
    );
  }
}
