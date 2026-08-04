import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/platform/media_kit_bootstrap.dart';

void main() {
  test('initializes media_kit on supported native audio platforms', () {
    for (final platform in [
      TargetPlatform.windows,
      TargetPlatform.android,
      TargetPlatform.iOS,
    ]) {
      expect(
        shouldInitializeMediaKit(isWeb: false, platform: platform),
        isTrue,
      );
    }
    expect(
      shouldInitializeMediaKit(isWeb: true, platform: TargetPlatform.windows),
      isFalse,
    );
  });
}
