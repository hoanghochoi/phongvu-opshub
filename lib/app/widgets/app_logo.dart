import 'package:flutter/material.dart';

import '../../core/config/app_brand.dart';
import '../theme/app_colors.dart';

class AppLogo extends StatelessWidget {
  static String get imageAsset => AppBrand.logoAsset;
  static String get paddedImageAsset => AppBrand.paddedLogoAsset;

  final double size;
  final double borderRadius;
  final BoxFit fit;
  final Color? strokeColor;

  const AppLogo({
    super.key,
    required this.size,
    this.borderRadius = 14,
    this.fit = BoxFit.cover,
    this.strokeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // Figma `App Logo` keeps a 1px stroke inside the asset bounds. Shell
        // consumers pass the navigation foreground; light/auth surfaces keep
        // the context-aware text fallback.
        border: Border.all(
          color: strokeColor ?? AppColors.textPrimaryOf(context),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(imageAsset, fit: fit),
    );
  }
}
