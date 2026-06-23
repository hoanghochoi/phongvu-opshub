import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/platform/app_platform_capabilities.dart';

void main() {
  group('AppPlatformCapabilities', () {
    test('supports payment monitor on non-web app platforms', () {
      expect(
        AppPlatformCapabilities.isPaymentMonitorSupported(
          isWeb: false,
          platform: TargetPlatform.windows,
        ),
        isTrue,
      );
      expect(
        AppPlatformCapabilities.isPaymentMonitorSupported(
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        isTrue,
      );
    });

    test('does not support payment monitor on web', () {
      for (final platform in TargetPlatform.values) {
        expect(
          AppPlatformCapabilities.isPaymentMonitorSupported(
            isWeb: true,
            platform: platform,
          ),
          isFalse,
        );
      }
    });

    test('supports payment speaker only on non-web Windows', () {
      expect(
        AppPlatformCapabilities.isPaymentSpeakerSupported(
          isWeb: false,
          platform: TargetPlatform.windows,
        ),
        isTrue,
      );
      expect(
        AppPlatformCapabilities.isPaymentSpeakerSupported(
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        isFalse,
      );
      expect(
        AppPlatformCapabilities.isPaymentSpeakerSupported(
          isWeb: true,
          platform: TargetPlatform.windows,
        ),
        isFalse,
      );
    });
  });
}
