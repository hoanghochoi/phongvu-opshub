import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../../features/notifications/presentation/widgets/app_notifications_bell.dart';
import '../../features/payment_monitor/presentation/widgets/payment_delivery_metrics_chip.dart';

/// Reusable gradient header used across all screens.
/// Provides a dark blue → indigo gradient background with white text.
class GradientHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBack;
  final VoidCallback? onBack;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool includeGlobalNotifications;

  const GradientHeader({
    super.key,
    required this.title,
    this.showBack = false,
    this.onBack,
    this.actions,
    this.bottom,
    this.includeGlobalNotifications = true,
  });

  static const LinearGradient gradient = LinearGradient(
    colors: [
      AppColors.gradientStart,
      AppColors.gradientMid,
      AppColors.gradientEnd,
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient getGradient(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LinearGradient(
      colors: isDark
          ? [
              AppColors.darkGradientStart,
              AppColors.darkGradientMid,
              AppColors.darkGradientEnd,
            ]
          : [
              AppColors.gradientStart,
              AppColors.gradientMid,
              AppColors.gradientEnd,
            ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  PreferredSizeWidget? _headerBottom(BuildContext context) {
    final headerBottom = bottom;
    if (headerBottom == null) return null;

    return PreferredSize(
      preferredSize: headerBottom.preferredSize,
      child: Theme(
        data: Theme.of(context).copyWith(
          tabBarTheme: const TabBarThemeData(
            labelColor: AppColors.surface,
            unselectedLabelColor: AppColors.neutral100,
            indicatorColor: AppColors.surface,
            dividerColor: AppColors.transparent,
            labelStyle: AppTextStyles.labelM,
            unselectedLabelStyle: AppTextStyles.labelM,
          ),
        ),
        child: headerBottom,
      ),
    );
  }

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      centerTitle: true,
      backgroundColor: AppColors.transparent,
      foregroundColor: AppColors.surface,
      elevation: 0,
      automaticallyImplyLeading: showBack && onBack == null,
      leading: (showBack && onBack != null)
          ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack)
          : null,
      actions: [
        if (actions != null) ...actions!,
        if (includeGlobalNotifications) ...[
          const PaymentDeliveryMetricsChip(),
          const AppNotificationsBell(),
        ],
      ],
      bottom: _headerBottom(context),
      flexibleSpace: DecoratedBox(
        decoration: BoxDecoration(gradient: getGradient(context)),
        child: const SizedBox.expand(),
      ),
    );
  }
}
