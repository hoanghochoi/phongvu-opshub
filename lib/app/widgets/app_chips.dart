import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';

/// Info chip: icon + text on a light background.
///
/// Used for displaying metadata (serial, date, location, etc.).
class AppInfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  final double? maxWidth;

  const AppInfoChip(
    this.icon,
    this.text, {
    super.key,
    this.color,
    this.maxWidth = 180,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.neutral700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.chipBackground,
        borderRadius: AppRadius.allSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: effectiveColor),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth ?? 180),
            child: Text(
              text.isEmpty ? 'Chưa có' : text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(fontSize: 12, color: effectiveColor),
            ),
          ),
        ],
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

  const AppStatusChip({
    super.key,
    required this.label,
    this.color,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.neutral700;
    final effectiveBg =
        backgroundColor ?? effectiveColor.withValues(alpha: 0.08);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: AppRadius.allSm,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: effectiveColor,
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
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: AppRadius.allSm,
          border: Border.all(color: color.withValues(alpha: 0.24)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 16,
                child: isLoading
                    ? CircularProgressIndicator(strokeWidth: 2, color: color)
                    : Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
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
