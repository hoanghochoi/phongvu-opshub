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

    test('supports payment monitor list on web', () {
      for (final platform in TargetPlatform.values) {
        expect(
          AppPlatformCapabilities.isPaymentMonitorSupported(
            isWeb: true,
            platform: platform,
          ),
          isTrue,
        );
      }
    });

    test('supports payment speaker on native Android, iOS and Windows', () {
      for (final platform in [
        TargetPlatform.windows,
        TargetPlatform.android,
        TargetPlatform.iOS,
      ]) {
        expect(
          AppPlatformCapabilities.isPaymentSpeakerSupported(
            isWeb: false,
            platform: platform,
          ),
          isTrue,
        );
      }
      expect(
        AppPlatformCapabilities.isPaymentSpeakerSupported(
          isWeb: true,
          platform: TargetPlatform.windows,
        ),
        isFalse,
      );
    });

    test('keeps the local preset pack Windows-only', () {
      expect(
        AppPlatformCapabilities.isPaymentSpeakerLocalPresetSupported(
          isWeb: false,
          platform: TargetPlatform.windows,
        ),
        isTrue,
      );
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        expect(
          AppPlatformCapabilities.isPaymentSpeakerLocalPresetSupported(
            isWeb: false,
            platform: platform,
          ),
          isFalse,
        );
      }
    });

    test('supports API connection administration on web and Windows only', () {
      expect(
        AppPlatformCapabilities.isApiConnectionAdminSupported(
          isWeb: true,
          platform: TargetPlatform.android,
        ),
        isTrue,
      );
      expect(
        AppPlatformCapabilities.isApiConnectionAdminSupported(
          isWeb: false,
          platform: TargetPlatform.windows,
        ),
        isTrue,
      );
      expect(
        AppPlatformCapabilities.isApiConnectionAdminSupported(
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        isFalse,
      );
    });
  });
}
