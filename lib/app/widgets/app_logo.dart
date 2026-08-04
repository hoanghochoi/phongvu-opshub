import 'package:flutter/material.dart';

import '../../core/config/app_brand.dart';
import '../theme/app_colors.dart';

class AppLogo extends StatelessWidget {
  static String get imageAsset => AppBrand.logoAsset;
  static String get paddedImageAsset => AppBrand.paddedLogoAsset;

  final double size;
  final double borderRadius;
  final BoxFit fit;

  const AppLogo({
    super.key,
    required this.size,
    this.borderRadius = 14,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.textPrimaryOf(context), width: 1),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(imageAsset, fit: fit),
    );
  }
}
