import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_text_styles.dart';

class AppNotificationIconButton extends StatelessWidget {
  final int count;
  final VoidCallback? onPressed;
  final String tooltip;
  final Color badgeColor;
  final IconData icon;
  final String? label;

  const AppNotificationIconButton({
    super.key,
    required this.count,
    required this.onPressed,
    required this.tooltip,
    this.badgeColor = AppColors.warning,
    this.icon = PhosphorIconsRegular.bell,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBadgeColor = badgeColor == AppColors.warning
        ? AppColors.warningOf(context)
        : AppColors.adaptOf(context, badgeColor);
    final notificationIcon = Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (count > 0)
          Positioned(
            right: -8,
            top: -8,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: effectiveBadgeColor,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                count > 99 ? '99+' : '$count',
                style: AppTextStyles.captionBold.copyWith(
                  color: AppColors.surface,
                  fontSize: 10,
                ),
              ),
            ),
          ),
      ],
    );
    if (label == null) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: notificationIcon,
      );
    }
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.isDark(context)
            ? AppColors.darkPrimarySurface
            : AppColors.primarySurface,
        borderRadius: AppRadius.allSm,
        child: InkWell(
          onTap: onPressed,
          borderRadius: AppRadius.allSm,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTheme(
                  data: IconThemeData(
                    color: AppColors.textPrimaryOf(context),
                    size: 18,
                  ),
                  child: notificationIcon,
                ),
                const SizedBox(width: 6),
                Text(
                  label!,
                  style: AppTextStyles.labelS.copyWith(
                    color: AppColors.textPrimaryOf(context),
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
