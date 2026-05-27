import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  static const imageAsset = 'assets/icon/source/app_icon_master.png';
  static const paddedImageAsset = 'assets/icon/source/app_icon_padded.png';

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
