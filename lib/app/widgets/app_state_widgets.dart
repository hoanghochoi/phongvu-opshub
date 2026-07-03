import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

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
                    style: AppTextStyles.labelM.copyWith(color: color),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: AppTextStyles.bodyM.copyWith(
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

class AppListSkeleton extends StatelessWidget {
  final int itemCount;
  final bool showLeading;
  final bool showTrailing;
  final double itemHeight;
  final bool scrollable;

  const AppListSkeleton({
    super.key,
    this.itemCount = 5,
    this.showLeading = true,
    this.showTrailing = true,
    this.itemHeight = 92,
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    final children = _children();
    return Semantics(
      label: 'Đang tải dữ liệu',
      child: scrollable
          ? ListView(
              primary: false,
              physics: const NeverScrollableScrollPhysics(),
              children: children,
            )
          : Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  List<Widget> _children() {
    return [
      for (var index = 0; index < itemCount; index++) ...[
        if (index > 0) const SizedBox(height: AppLayoutTokens.cardGap),
        _AppSkeletonCard(
          showLeading: showLeading,
          showTrailing: showTrailing,
          itemHeight: itemHeight,
        ),
      ],
    ];
  }
}

class _AppSkeletonCard extends StatelessWidget {
  final bool showLeading;
  final bool showTrailing;
  final double itemHeight;

  const _AppSkeletonCard({
    required this.showLeading,
    required this.showTrailing,
    required this.itemHeight,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = Theme.of(context).brightness == Brightness.dark
        ? AppColors.neutral800
        : AppColors.neutral100;
    final highlightColor = Theme.of(context).brightness == Brightness.dark
        ? AppColors.neutral700
        : AppColors.neutral200;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
      ),
      child: SizedBox(
        height: itemHeight,
        child: Padding(
          padding: const EdgeInsets.all(AppLayoutTokens.cardPadding),
          child: Row(
            children: [
              if (showLeading) ...[
                _SkeletonBlock(
                  width: 42,
                  height: 42,
                  baseColor: baseColor,
                  highlightColor: highlightColor,
                ),
                const SizedBox(width: AppLayoutTokens.formInlineGap),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonBlock(
                      widthFactor: 0.72,
                      height: 14,
                      baseColor: baseColor,
                      highlightColor: highlightColor,
                    ),
                    const SizedBox(height: 10),
                    _SkeletonBlock(
                      widthFactor: 0.46,
                      height: 12,
                      baseColor: baseColor,
                      highlightColor: highlightColor,
                    ),
                  ],
                ),
              ),
              if (showTrailing) ...[
                const SizedBox(width: AppLayoutTokens.formInlineGap),
                _SkeletonBlock(
                  width: 72,
                  height: 28,
                  baseColor: baseColor,
                  highlightColor: highlightColor,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatefulWidget {
  final double? width;
  final double? widthFactor;
  final double height;
  final Color baseColor;
  final Color highlightColor;

  const _SkeletonBlock({
    this.width,
    this.widthFactor,
    required this.height,
    required this.baseColor,
    required this.highlightColor,
  });

  @override
  State<_SkeletonBlock> createState() => _SkeletonBlockState();
}

class _SkeletonBlockState extends State<_SkeletonBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animationsDisabled =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final block = AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = animationsDisabled ? 0.5 : _controller.value;
        final offset = (progress * 2.4) - 1.2;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1 + offset, 0),
              end: Alignment(1 + offset, 0),
              colors: [
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
              ],
              stops: const [0, 0.5, 1],
            ),
            borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
          ),
          child: child,
        );
      },
      child: SizedBox(width: widget.width, height: widget.height),
    );
    if (widget.widthFactor == null) return block;
    return FractionallySizedBox(widthFactor: widget.widthFactor, child: block);
  }
}
