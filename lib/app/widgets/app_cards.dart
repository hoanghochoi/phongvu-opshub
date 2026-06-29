import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_layout.dart';

class AppSurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final Color? backgroundColor;
  final double borderWidth;
  final VoidCallback? onTap;

  const AppSurfaceCard({
    super.key,
    required this.child,
    this.margin = EdgeInsets.zero,
    this.padding = const EdgeInsets.all(AppLayoutTokens.cardPadding),
    this.borderColor,
    this.backgroundColor,
    this.borderWidth = 1,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppLayoutTokens.cardRadius);
    final effectiveBorderColor = borderColor ?? Theme.of(context).dividerColor;
    final content = Padding(padding: padding, child: child);

    return Card(
      margin: margin,
      elevation: 0,
      color:
          backgroundColor ??
          Theme.of(context).cardTheme.color ??
          AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: effectiveBorderColor, width: borderWidth),
      ),
      child: onTap == null
          ? content
          : InkWell(onTap: onTap, borderRadius: radius, child: content),
    );
  }
}
