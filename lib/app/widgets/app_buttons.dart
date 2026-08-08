import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_text_styles.dart';
import 'app_layout.dart';

class AppButtonMetrics {
  AppButtonMetrics._();

  static const double height = 52;
  static const double smallHeight = 40;
  static const double mediumHeight = 48;
  static const double largeHeight = 52;
  static const double mobileActionHeight = AppLayoutTokens.mobileActionHeight;
  static const double compactActionHeight = AppLayoutTokens.compactActionHeight;
  static const double radius = AppRadius.md;
  static const double iconSize = AppLayoutTokens.iconTouchTarget;
  static const EdgeInsets horizontalPadding = EdgeInsets.symmetric(
    horizontal: 20,
  );
  static const double gap = 8;

  static double heightFor(AppButtonSize size) => switch (size) {
    AppButtonSize.small => smallHeight,
    AppButtonSize.medium => mediumHeight,
    AppButtonSize.large => largeHeight,
  };
}

enum AppButtonSize { small, medium, large }

class AppPrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData? icon;
  final String label;
  final bool isLoading;
  final String? loadingLabel;
  final AppButtonSize size;
  final double? height;
  final double radius;
  final TextStyle? textStyle;
  final EdgeInsetsGeometry? padding;

  const AppPrimaryButton({
    super.key,
    required this.onPressed,
    this.icon,
    required this.label,
    this.isLoading = false,
    this.loadingLabel,
    this.size = AppButtonSize.large,
    this.height,
    this.radius = AppButtonMetrics.radius,
    this.textStyle,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final hasIcon = icon != null || isLoading;
    final buttonStyle =
        FilledButton.styleFrom(
          backgroundColor: AppColors.primaryOf(context),
          foregroundColor: AppColors.primaryForegroundOf(context),
          disabledBackgroundColor: AppColors.borderOf(context),
          disabledForegroundColor: AppColors.textMutedOf(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
          textStyle: textStyle ?? AppTextStyles.labelL,
          padding: padding ?? AppButtonMetrics.horizontalPadding,
          minimumSize: Size(0, height ?? AppButtonMetrics.heightFor(size)),
          maximumSize: Size(
            double.infinity,
            height ?? AppButtonMetrics.heightFor(size),
          ),
        ).copyWith(
          side: WidgetStateProperty.resolveWith<BorderSide?>((states) {
            if (states.contains(WidgetState.focused)) {
              return const BorderSide(color: AppColors.focus, width: 2);
            }
            return BorderSide.none;
          }),
        );

    final buttonLabel = Text(
      isLoading ? loadingLabel ?? label : label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
    );

    return SizedBox(
      width: double.infinity,
      height: height ?? AppButtonMetrics.heightFor(size),
      child: hasIcon
          ? FilledButton.icon(
              onPressed: isLoading ? null : onPressed,
              icon: isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primaryForegroundOf(context),
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
  final IconData? icon;
  final String label;
  final bool isLoading;
  final String? loadingLabel;
  final Color? foregroundColor;
  final Color? borderColor;
  final bool expand;
  final AppButtonSize size;
  final double? height;
  final double radius;
  final TextStyle? textStyle;
  final double? iconSize;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final Color? disabledBackgroundColor;

  const AppSecondaryButton({
    super.key,
    required this.onPressed,
    this.icon,
    required this.label,
    this.isLoading = false,
    this.loadingLabel,
    this.foregroundColor,
    this.borderColor,
    this.expand = true,
    this.size = AppButtonSize.large,
    this.height,
    this.radius = AppButtonMetrics.radius,
    this.textStyle,
    this.iconSize,
    this.padding,
    this.backgroundColor,
    this.disabledBackgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveForegroundColor =
        foregroundColor ?? AppColors.primaryOf(context);
    final effectiveBorderColor = borderColor ?? effectiveForegroundColor;
    return SizedBox(
      width: expand ? double.infinity : null,
      height: height ?? AppButtonMetrics.heightFor(size),
      child: _buildButton(
        effectiveForegroundColor: effectiveForegroundColor,
        effectiveBorderColor: effectiveBorderColor,
      ),
    );
  }

  Widget _buildButton({
    required Color effectiveForegroundColor,
    required Color effectiveBorderColor,
  }) {
    final buttonStyle =
        OutlinedButton.styleFrom(
          foregroundColor: effectiveForegroundColor,
          backgroundColor: backgroundColor,
          disabledBackgroundColor: disabledBackgroundColor,
          side: BorderSide(color: effectiveBorderColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
          textStyle: textStyle ?? AppTextStyles.labelM,
          minimumSize: Size(0, height ?? AppButtonMetrics.heightFor(size)),
          maximumSize: Size(
            double.infinity,
            height ?? AppButtonMetrics.heightFor(size),
          ),
          padding: padding ?? AppButtonMetrics.horizontalPadding,
        ).copyWith(
          side: WidgetStateProperty.resolveWith<BorderSide?>((states) {
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: effectiveBorderColor, width: 2);
            }
            return BorderSide(color: effectiveBorderColor);
          }),
        );
    final buttonLabel = Text(
      isLoading ? loadingLabel ?? label : label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
    );

    if (icon == null && !isLoading) {
      return OutlinedButton(
        onPressed: onPressed,
        style: buttonStyle,
        child: buttonLabel,
      );
    }
    if (iconSize != null || padding != null) {
      return OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: buttonStyle,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              SizedBox(
                width: iconSize ?? 20,
                height: iconSize ?? 20,
                child: const CircularProgressIndicator(strokeWidth: 2),
              )
            else if (icon != null)
              Icon(icon, size: iconSize),
            if (isLoading || icon != null) const SizedBox(width: 6),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: buttonLabel,
              ),
            ),
          ],
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: isLoading ? null : onPressed,
      icon: isLoading
          ? SizedBox(
              width: iconSize ?? 20,
              height: iconSize ?? 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: iconSize),
      label: buttonLabel,
      style: buttonStyle,
    );
  }
}

class AppLinkButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData? icon;
  final String label;
  final String? tooltip;
  final bool compact;

  const AppLinkButton({
    super.key,
    required this.onPressed,
    this.icon,
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
      height: AppButtonMetrics.compactActionHeight,
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
          minimumSize: const WidgetStatePropertyAll(
            Size(0, AppButtonMetrics.compactActionHeight),
          ),
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
            if (icon != null) ...[
              Icon(icon, size: iconSize),
              SizedBox(width: compact ? 4 : 6),
            ],
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
  final bool isLoading;
  final bool filled;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double dimension;
  final double radius;

  const AppIconAction({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.tooltip,
    this.isLoading = false,
    this.filled = false,
    this.backgroundColor,
    this.foregroundColor,
    this.dimension = AppButtonMetrics.iconSize,
    this.radius = AppButtonMetrics.radius,
  });

  @override
  Widget build(BuildContext context) {
    final foreground =
        foregroundColor ??
        (filled
            ? AppColors.primaryForegroundOf(context)
            : AppColors.primaryOf(context));
    final background =
        backgroundColor ??
        (filled
            ? AppColors.primaryOf(context)
            : AppColors.primaryOf(context).withValues(alpha: 0.10));

    return SizedBox.square(
      dimension: dimension,
      child: IconButton(
        onPressed: isLoading ? null : onPressed,
        icon: isLoading
            ? SizedBox.square(
                dimension: dimension * 0.42,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              )
            : Icon(icon),
        tooltip: tooltip,
        color: foreground,
        style: IconButton.styleFrom(
          foregroundColor: foreground,
          backgroundColor: background,
          disabledBackgroundColor: AppColors.borderOf(context),
          disabledForegroundColor: AppColors.textMutedOf(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
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
        foregroundColor: AppColors.primaryOf(context),
        side: BorderSide(color: AppColors.primaryOf(context)),
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
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primaryForegroundOf(context),
            ),
          )
        : icon == null
        ? null
        : Icon(icon);
    final effectiveBackgroundColor =
        backgroundColor ?? AppColors.primaryOf(context);
    final effectiveForegroundColor =
        foregroundColor ?? AppColors.primaryForegroundOf(context);
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
