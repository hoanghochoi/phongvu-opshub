import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_text_styles.dart';

/// Info chip: icon + text on a light background.
///
/// Used for displaying metadata (serial, date, location, etc.).
class AppInfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  final double? maxWidth;
  final VoidCallback? onTap;
  final String? tooltip;
  final String? semanticsLabel;

  const AppInfoChip(
    this.icon,
    this.text, {
    super.key,
    this.color,
    this.maxWidth,
    this.onTap,
    this.tooltip,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = text.isEmpty;
    final effectiveColor = AppColors.adaptOf(
      context,
      color ?? AppColors.textSecondaryOf(context),
    );
    final displayColor = isEmpty
        ? AppColors.textMutedOf(context)
        : effectiveColor;

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isEmpty ? AppColors.textMutedOf(context) : effectiveColor,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: ConstrainedBox(
              constraints: maxWidth != null
                  ? BoxConstraints(maxWidth: maxWidth!)
                  : const BoxConstraints(),
              child: Text(
                isEmpty ? 'Chưa có' : text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: AppTextStyles.labelS.copyWith(
                  color: displayColor,
                  fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(PhosphorIconsRegular.copy, size: 12, color: displayColor),
          ],
        ],
      ),
    );

    if (onTap == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.chipBackgroundOf(context),
          borderRadius: AppRadius.allSm,
        ),
        child: content,
      );
    }

    Widget interactiveChip = Semantics(
      button: true,
      excludeSemantics: true,
      label: semanticsLabel ?? text,
      hint: 'Sao chép',
      child: Material(
        color: AppColors.chipBackgroundOf(context),
        borderRadius: AppRadius.allSm,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.allSm,
          child: content,
        ),
      ),
    );
    if (tooltip?.isNotEmpty == true) {
      interactiveChip = Tooltip(message: tooltip!, child: interactiveChip);
    }
    return interactiveChip;
  }
}

/// Status chip: a small label with a tinted background.
///
/// Used for tags like "FIFO", "Đã xuất", "Query", "Kết quả", etc.
class AppStatusChip extends StatelessWidget {
  final String label;
  final Color? color;
  final Color? backgroundColor;
  final double fontSize;
  final FontWeight fontWeight;
  final EdgeInsets padding;
  final double? maxWidth;

  const AppStatusChip({
    super.key,
    required this.label,
    this.color,
    this.backgroundColor,
    this.fontSize = 11,
    this.fontWeight = FontWeight.w700,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = AppColors.adaptOf(
      context,
      color ?? AppColors.textSecondaryOf(context),
    );
    final effectiveBg =
        backgroundColor ?? effectiveColor.withValues(alpha: 0.08);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: AppRadius.allSm,
      ),
      child: ConstrainedBox(
        constraints: maxWidth == null
            ? const BoxConstraints()
            : BoxConstraints(maxWidth: maxWidth!),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: AppTextStyles.labelS.copyWith(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: effectiveColor,
          ),
        ),
      ),
    );
  }
}

/// Status pill: icon + text with a tinted border and background.
///
/// Used for connection status indicators (e.g. sync status).
class AppStatusPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isLoading;
  final double height;

  const AppStatusPill({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.isLoading = false,
    this.height = 36,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = AppColors.adaptOf(context, color);
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: effectiveColor.withValues(alpha: 0.10),
          borderRadius: AppRadius.allSm,
          border: Border.all(color: effectiveColor.withValues(alpha: 0.24)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 16,
                child: isLoading
                    ? CircularProgressIndicator(
                        strokeWidth: 2,
                        color: effectiveColor,
                      )
                    : Icon(icon, size: 16, color: effectiveColor),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: AppTextStyles.bodyS.copyWith(
                    color: effectiveColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
