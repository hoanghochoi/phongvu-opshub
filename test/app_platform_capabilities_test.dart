import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/platform/app_platform_capabilities.dart';

void main() {
  group('AppPlatformCapabilities', () {
    test('supports payment monitor only on non-web Windows', () {
      expect(
        AppPlatformCapabilities.isPaymentMonitorSupported(
          isWeb: false,
          platform: TargetPlatform.windows,
        ),
        isTrue,
      );
    });

    test(
      'does not support payment monitor on web or non-Windows platforms',
      () {
        for (final platform in TargetPlatform.values) {
          expect(
            AppPlatformCapabilities.isPaymentMonitorSupported(
              isWeb: true,
              platform: platform,
            ),
            isFalse,
          );
        }

        for (final platform in TargetPlatform.values.where(
          (platform) => platform != TargetPlatform.windows,
        )) {
          expect(
            AppPlatformCapabilities.isPaymentMonitorSupported(
              isWeb: false,
              platform: platform,
            ),
            isFalse,
          );
        }
      },
    );
  });
}
