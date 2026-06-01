import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

import 'app_buttons.dart';
import 'app_layout.dart';

enum AppStateTone {
  neutral,
  info,
  success,
  warning,
  error;

  Color get color {
    return switch (this) {
      AppStateTone.info => AppColors.info,
      AppStateTone.success => AppColors.success,
      AppStateTone.warning => AppColors.warning,
      AppStateTone.error => AppColors.error,
      AppStateTone.neutral => AppColors.neutral500,
    };
  }
}

class AppStatePanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final AppStateTone tone;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final bool compact;
  final bool isLoading;

  const AppStatePanel({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.tone = AppStateTone.neutral,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.compact = false,
  }) : isLoading = false;

  const AppStatePanel.empty({
    super.key,
    required this.title,
    this.icon = Icons.inbox_rounded,
    this.message,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.compact = false,
  }) : tone = AppStateTone.neutral,
       isLoading = false;

  const AppStatePanel.error({
    super.key,
    required this.title,
    this.icon = Icons.error_outline_rounded,
    this.message,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.compact = false,
  }) : tone = AppStateTone.error,
       isLoading = false;

  const AppStatePanel.loading({
    super.key,
    required this.title,
    this.message,
    this.compact = false,
  }) : icon = Icons.hourglass_top_rounded,
       tone = AppStateTone.info,
       actionLabel = null,
       actionIcon = null,
       onAction = null,
       isLoading = true;

  @override
  Widget build(BuildContext context) {
    final color = tone.color;
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: tone == AppStateTone.neutral ? AppColors.neutral700 : color,
    );
    final messageText = message;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: EdgeInsets.all(compact ? 14 : 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                SizedBox.square(
                  dimension: compact ? 28 : 36,
                  child: CircularProgressIndicator(
                    strokeWidth: compact ? 2.2 : 2.8,
                  ),
                )
              else
                Container(
                  width: compact ? 44 : 56,
                  height: compact ? 44 : 56,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(
                      AppLayoutTokens.cardRadius,
                    ),
                  ),
                  child: Icon(icon, color: color, size: compact ? 24 : 30),
                ),
              SizedBox(height: compact ? 10 : 14),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: titleStyle,
              ),
              if (messageText != null && messageText.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  messageText,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.neutral500,
                    height: 1.35,
                  ),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                SizedBox(height: compact ? 12 : 16),
                SizedBox(
                  width: compact ? 180 : 220,
                  child: AppSecondaryButton(
                    onPressed: onAction,
                    icon: actionIcon ?? Icons.refresh_rounded,
                    label: actionLabel!,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AppStatusBanner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final AppStateTone tone;

  const AppStatusBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.tone = AppStateTone.info,
  });

  @override
  Widget build(BuildContext context) {
    final color = tone.color;
    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.neutral200
                          : AppColors.neutral800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
