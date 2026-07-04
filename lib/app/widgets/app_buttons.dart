import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_text_styles.dart';
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
  final double height;
  final double radius;

  const AppPrimaryButton({
    super.key,
    required this.onPressed,
    this.icon,
    required this.label,
    this.isLoading = false,
    this.loadingLabel,
    this.height = AppButtonMetrics.height,
    this.radius = AppButtonMetrics.radius,
  });

  @override
  Widget build(BuildContext context) {
    final hasIcon = icon != null || isLoading;
    final buttonStyle = FilledButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.surface,
      disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.45),
      disabledForegroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
      textStyle: AppTextStyles.labelL,
    );

    final buttonLabel = Text(
      isLoading ? loadingLabel ?? label : label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
    );

    return SizedBox(
      width: double.infinity,
      height: height,
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
  final Color? foregroundColor;
  final Color? borderColor;
  final bool expand;
  final double height;
  final double radius;

  const AppSecondaryButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.isLoading = false,
    this.loadingLabel,
    this.foregroundColor,
    this.borderColor,
    this.expand = true,
    this.height = AppButtonMetrics.height,
    this.radius = AppButtonMetrics.radius,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveForegroundColor = foregroundColor ?? AppColors.primary;
    final effectiveBorderColor = borderColor ?? effectiveForegroundColor;
    return SizedBox(
      width: expand ? double.infinity : null,
      height: height,
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
          foregroundColor: effectiveForegroundColor,
          side: BorderSide(color: effectiveBorderColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
          textStyle: AppTextStyles.labelM,
        ),
      ),
    );
  }
}

class AppLinkButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final String? tooltip;
  final bool compact;

  const AppLinkButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.tooltip,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = AppColors.primaryOf(context);
    final horizontalPadding = compact ? 4.0 : 6.0;
    final iconSize = compact ? 16.0 : 18.0;
    final button = SizedBox(
      height: 44,
      child: TextButton(
        onPressed: onPressed,
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.textMutedOf(context);
            }
            return effectiveColor;
          }),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused) ||
                states.contains(WidgetState.hovered)) {
              return effectiveColor.withValues(alpha: 0.10);
            }
            if (states.contains(WidgetState.pressed)) {
              return effectiveColor.withValues(alpha: 0.16);
            }
            return null;
          }),
          minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: horizontalPadding),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppRadius.allMd),
          ),
          textStyle: const WidgetStatePropertyAll(AppTextStyles.labelS),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: iconSize),
            SizedBox(width: compact ? 4 : 6),
            Text(label, maxLines: 1, softWrap: false),
          ],
        ),
      ),
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
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
    final foreground = filled ? AppColors.surface : AppColors.primary;
    final background = filled
        ? AppColors.primary
        : AppColors.primary.withValues(alpha: 0.10);

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
      style: TextButton.styleFrom(textStyle: AppTextStyles.labelM),
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
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppButtonMetrics.radius),
        ),
        textStyle: AppTextStyles.labelM,
      ),
    );
  }
}

class AppDialogConfirmButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData? icon;
  final String label;
  final bool isLoading;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const AppDialogConfirmButton({
    super.key,
    required this.onPressed,
    this.icon,
    required this.label,
    this.isLoading = false,
    this.backgroundColor,
    this.foregroundColor,
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
    final effectiveBackgroundColor = backgroundColor ?? AppColors.primary;
    final effectiveForegroundColor = foregroundColor ?? AppColors.surface;
    final style = FilledButton.styleFrom(
      backgroundColor: effectiveBackgroundColor,
      foregroundColor: effectiveForegroundColor,
      disabledBackgroundColor: effectiveBackgroundColor.withValues(alpha: 0.45),
      disabledForegroundColor: effectiveForegroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppButtonMetrics.radius),
      ),
      textStyle: AppTextStyles.labelM,
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
