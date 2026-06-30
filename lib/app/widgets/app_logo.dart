import 'package:flutter/material.dart';

import '../../core/config/app_brand.dart';

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
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.asset(imageAsset, width: size, height: size, fit: fit),
    );
  }
}
