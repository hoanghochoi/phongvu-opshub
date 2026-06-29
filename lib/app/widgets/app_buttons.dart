import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_theme.dart';
import 'app_layout.dart';

class AppButtonMetrics {
  AppButtonMetrics._();

  static const double height = 52;
  static const double radius = AppRadius.lg;
  static const double iconSize = 48;
  static const EdgeInsets horizontalPadding = EdgeInsets.symmetric(
    horizontal: 24,
  );
}

class AppPrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData? icon;
  final String label;
  final bool isLoading;
  final String? loadingLabel;

  const AppPrimaryButton({
    super.key,
    required this.onPressed,
    this.icon,
    required this.label,
    this.isLoading = false,
    this.loadingLabel,
  });

  @override
  Widget build(BuildContext context) {
    final hasIcon = icon != null || isLoading;
    final buttonStyle = FilledButton.styleFrom(
      backgroundColor: AppTheme.primaryBlue,
      foregroundColor: AppColors.surface,
      disabledBackgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.45),
      disabledForegroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppButtonMetrics.radius),
      ),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    );

    final buttonLabel = Text(
      isLoading ? loadingLabel ?? label : label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
    );

    return SizedBox(
      width: double.infinity,
      height: AppButtonMetrics.height,
      child: hasIcon
          ? FilledButton.icon(
              onPressed: isLoading ? null : onPressed,
              icon: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.surface,
                      ),
                    )
                  : Icon(icon),
              label: buttonLabel,
              style: buttonStyle,
            )
          : FilledButton(
              onPressed: onPressed,
              style: buttonStyle,
              child: buttonLabel,
            ),
    );
  }
}

class AppSecondaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final bool isLoading;
  final String? loadingLabel;

  const AppSecondaryButton({
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
      child: OutlinedButton.icon(
        onPressed: isLoading ? null : onPressed,
        icon: isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon),
        label: Text(
          isLoading ? loadingLabel ?? label : label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
        ),
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

class AppActionRow extends StatelessWidget {
  final List<Widget> children;
  final double maxButtonWidth;
  final double spacing;
  final MainAxisAlignment desktopAlignment;

  const AppActionRow({
    super.key,
    required this.children,
    this.maxButtonWidth = 220,
    this.spacing = AppLayoutTokens.formInlineGap,
    this.desktopAlignment = MainAxisAlignment.end,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final isCompact = width < AppLayoutTokens.compactBreakpoint;

        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0) SizedBox(height: spacing),
                children[index],
              ],
            ],
          );
        }

        final availableButtonWidth =
            (width - (spacing * (children.length - 1))) / children.length;
        final buttonWidth = math.min(maxButtonWidth, availableButtonWidth);

        return Row(
          mainAxisAlignment: desktopAlignment,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0) SizedBox(width: spacing),
              SizedBox(width: buttonWidth, child: children[index]),
            ],
          ],
        );
      },
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
    final foreground = filled ? AppColors.surface : AppTheme.primaryBlue;
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
          disabledBackgroundColor: AppColors.neutral200,
          disabledForegroundColor: AppColors.neutral500,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
        ),
      ),
    );
  }
}

class AppDialogCancelButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;

  const AppDialogCancelButton({
    super.key,
    required this.onPressed,
    this.label = 'Hủy',
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }
}

class AppDialogSecondaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;

  const AppDialogSecondaryButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
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
    );
  }
}

class AppDialogConfirmButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData? icon;
  final String label;
  final bool isLoading;

  const AppDialogConfirmButton({
    super.key,
    required this.onPressed,
    this.icon,
    required this.label,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveIcon = isLoading
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.surface,
            ),
          )
        : icon == null
        ? null
        : Icon(icon);
    final style = FilledButton.styleFrom(
      backgroundColor: AppTheme.primaryBlue,
      foregroundColor: AppColors.surface,
      disabledBackgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.45),
      disabledForegroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppButtonMetrics.radius),
      ),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );

    if (effectiveIcon != null) {
      return FilledButton.icon(
        onPressed: isLoading ? null : onPressed,
        icon: effectiveIcon,
        label: Text(label),
        style: style,
      );
    }
    return FilledButton(onPressed: onPressed, style: style, child: Text(label));
  }
}
