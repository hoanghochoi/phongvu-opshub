import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppButtonMetrics {
  AppButtonMetrics._();

  static const double height = 52;
  static const double radius = 14;
  static const double iconSize = 48;
  static const EdgeInsets horizontalPadding = EdgeInsets.symmetric(
    horizontal: 24,
  );
}

class AppPrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final bool isLoading;
  final String? loadingLabel;

  const AppPrimaryButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.isLoading = false,
    this.loadingLabel,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: AppButtonMetrics.height,
      child: FilledButton.icon(
        onPressed: isLoading ? null : onPressed,
        icon: isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon),
        label: Text(isLoading ? loadingLabel ?? label : label),
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.primaryBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.45),
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppButtonMetrics.radius),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class AppSecondaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;

  const AppSecondaryButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: AppButtonMetrics.height,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.primaryBlue,
          side: const BorderSide(color: AppTheme.primaryBlue),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppButtonMetrics.radius),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class AppIconAction extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String tooltip;
  final bool filled;

  const AppIconAction({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.tooltip,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = filled ? Colors.white : AppTheme.primaryBlue;
    final background = filled
        ? AppTheme.primaryBlue
        : AppTheme.primaryBlue.withValues(alpha: 0.10);

    return SizedBox.square(
      dimension: AppButtonMetrics.iconSize,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        tooltip: tooltip,
        color: foreground,
        style: IconButton.styleFrom(
          backgroundColor: background,
          disabledBackgroundColor: Colors.grey.shade200,
          disabledForegroundColor: Colors.grey.shade500,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
