import 'package:flutter/foundation.dart';

class AppPlatformCapabilities {
  AppPlatformCapabilities._();

  static bool isPaymentMonitorSupported({
    bool? isWeb,
    TargetPlatform? platform,
  }) {
    final effectiveIsWeb = isWeb ?? kIsWeb;
    final effectivePlatform = platform ?? defaultTargetPlatform;
    return !effectiveIsWeb && effectivePlatform == TargetPlatform.windows;
  }
}
