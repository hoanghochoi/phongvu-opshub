import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Reusable gradient header used across all screens.
/// Provides a dark blue → indigo gradient background with white text.
class GradientHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBack;
  final VoidCallback? onBack;
  final List<Widget>? actions;

  const GradientHeader({
    super.key,
    required this.title,
    this.showBack = false,
    this.onBack,
    this.actions,
  });

  static const LinearGradient gradient = LinearGradient(
    colors: [AppColors.gradientStart, AppColors.gradientMid, AppColors.gradientEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient getGradient(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LinearGradient(
      colors: isDark
          ? [AppColors.darkGradientStart, AppColors.darkGradientMid, AppColors.darkGradientEnd]
          : [AppColors.gradientStart, AppColors.gradientMid, AppColors.gradientEnd],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: getGradient(context)),
      child: AppBar(
        title: Text(title),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: showBack && onBack == null,
        leading: (showBack && onBack != null)
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: onBack,
              )
            : null,
        actions: actions,
      ),
    );
  }
}
