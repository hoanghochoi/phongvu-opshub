import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/platform/media_kit_bootstrap.dart';

void main() {
  test('initializes media_kit only on non-web Windows', () {
    expect(
      shouldInitializeMediaKit(isWeb: false, platform: TargetPlatform.windows),
      isTrue,
    );
    expect(
      shouldInitializeMediaKit(isWeb: false, platform: TargetPlatform.android),
      isFalse,
    );
    expect(
      shouldInitializeMediaKit(isWeb: true, platform: TargetPlatform.windows),
      isFalse,
    );
  });
}
