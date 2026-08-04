import 'package:flutter/foundation.dart';

class AppPlatformCapabilities {
  AppPlatformCapabilities._();

  static bool isPaymentMonitorSupported({
    bool? isWeb,
    TargetPlatform? platform,
  }) {
    return true;
  }

  static bool isPaymentSpeakerSupported({
    bool? isWeb,
    TargetPlatform? platform,
  }) {
    final effectiveIsWeb = isWeb ?? kIsWeb;
    final effectivePlatform = platform ?? defaultTargetPlatform;
    return !effectiveIsWeb &&
        (effectivePlatform == TargetPlatform.windows ||
            effectivePlatform == TargetPlatform.android ||
            effectivePlatform == TargetPlatform.iOS);
  }

  /// The Windows client composes the approved local preset pack. Mobile and
  /// tablet clients use the authenticated server audio stream instead; Web is
  /// deliberately list-only and never reaches this path.
  static bool isPaymentSpeakerLocalPresetSupported({
    bool? isWeb,
    TargetPlatform? platform,
  }) {
    final effectiveIsWeb = isWeb ?? kIsWeb;
    final effectivePlatform = platform ?? defaultTargetPlatform;
    return !effectiveIsWeb && effectivePlatform == TargetPlatform.windows;
  }

  static bool isApiConnectionAdminSupported({
    bool? isWeb,
    TargetPlatform? platform,
  }) {
    final effectiveIsWeb = isWeb ?? kIsWeb;
    final effectivePlatform = platform ?? defaultTargetPlatform;
    return effectiveIsWeb || effectivePlatform == TargetPlatform.windows;
  }
}
