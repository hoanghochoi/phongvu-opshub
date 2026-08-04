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
  final double? radius;
  final VoidCallback? onTap;

  const AppSurfaceCard({
    super.key,
    required this.child,
    this.margin = EdgeInsets.zero,
    this.padding = const EdgeInsets.all(AppLayoutTokens.cardPadding),
    this.borderColor,
    this.backgroundColor,
    this.borderWidth = 1,
    this.radius,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = BorderRadius.circular(
      radius ?? AppLayoutTokens.cardRadius,
    );
    final effectiveBorderColor = borderColor ?? AppColors.borderOf(context);
    final content = Padding(padding: padding, child: child);

    return Card(
      margin: margin,
      elevation: 0,
      color: backgroundColor ?? AppColors.cardOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: effectiveRadius,
        side: BorderSide(color: effectiveBorderColor, width: borderWidth),
      ),
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: effectiveRadius,
              child: content,
            ),
    );
  }
}
