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

/// Foundation metadata pill used by dense operational result cards.
///
/// Mobile keeps a 30 px visual surface with 12 px copy and 14 px icons. Copy
/// actions retain a 48 dp outer target. Desktop uses the approved 40 px pill.
class AppMetadataPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool mobileDensity;
  final VoidCallback? onTap;
  final String? tooltip;
  final String? semanticsLabel;

  const AppMetadataPill({
    super.key,
    required this.icon,
    required this.text,
    required this.mobileDensity,
    this.onTap,
    this.tooltip,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final visualHeight = mobileDensity ? 30.0 : 40.0;
    final iconSize = mobileDensity ? 14.0 : 20.0;
    final gap = mobileDensity ? 6.0 : 8.0;
    final horizontalPadding = mobileDensity ? 10.0 : 12.0;
    final radius = mobileDensity ? AppRadius.sm : AppRadius.pill;
    final foreground = AppColors.textSecondaryOf(context);
    final displayText = text.isEmpty ? 'Chưa có' : text;
    final compactLongValue = mobileDensity && displayText.length > 14;

    Widget surface = Container(
      height: visualHeight,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      decoration: BoxDecoration(
        color: AppColors.chipBackgroundOf(context),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: foreground),
          SizedBox(width: gap),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: mobileDensity
                    ? (onTap != null ? 80 : 120)
                    : double.infinity,
              ),
              child: Text(
                displayText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style:
                    (mobileDensity
                            ? AppTextStyles.labelSmallSubtle
                            : AppTextStyles.labelM)
                        .copyWith(
                          color: foreground,
                          fontSize: compactLongValue ? 10 : null,
                        ),
              ),
            ),
          ),
          if (onTap != null) ...[
            SizedBox(width: gap),
            Icon(PhosphorIconsRegular.copy, size: iconSize, color: foreground),
          ],
        ],
      ),
    );

    if (onTap == null) return surface;
    surface = Semantics(
      button: true,
      label: semanticsLabel ?? text,
      hint: 'Sao chép',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: Center(child: surface),
        ),
      ),
    );
    final target = SizedBox(height: 48, child: surface);
    return tooltip?.isNotEmpty == true
        ? Tooltip(message: tooltip!, child: target)
        : target;
  }
}

/// Text-only action pill. Mobile follows the shared 30/12 visual rule while
/// preserving a 48 dp hit target.
class AppActionPill extends StatelessWidget {
  final String label;
  final bool mobileDensity;
  final VoidCallback? onPressed;

  const AppActionPill({
    super.key,
    required this.label,
    required this.mobileDensity,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final visualHeight = mobileDensity ? 30.0 : 32.0;
    final radius = AppRadius.sm;
    final surface = Container(
      height: visualHeight,
      padding: EdgeInsets.symmetric(horizontal: mobileDensity ? 10 : 12),
      decoration: BoxDecoration(
        color: AppColors.infoSurfaceOf(context),
        border: Border.all(
          color: AppColors.infoOf(context).withValues(alpha: 0.24),
        ),
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        style: (mobileDensity ? AppTextStyles.labelS : AppTextStyles.labelM)
            .copyWith(color: AppColors.infoOf(context)),
      ),
    );
    return SizedBox(
      height: mobileDensity ? 48 : 32,
      child: Semantics(
        button: true,
        label: 'Tra cứu lại $label',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(radius),
            child: Center(child: surface),
          ),
        ),
      ),
    );
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
