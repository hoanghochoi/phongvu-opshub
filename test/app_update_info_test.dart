import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/features/app_update/domain/app_update_info.dart';

void main() {
  group('AppUpdateInfo', () {
    test('does not require update when current build is already latest', () {
      const info = AppUpdateInfo(
        platform: 'android',
        latestVersion: '2026.05.20.7',
        latestBuild: 100007,
        minSupportedBuild: 100007,
        updateUrl: 'https://opshub.hoanghochoi.com/downloads/app.apk',
        releaseNotes: 'GitHub 5652baf',
        forceUpdate: true,
      );

      expect(info.hasUpdate(100007), isFalse);
      expect(info.requiresUpdate(100007), isFalse);
    });

    test('requires update when force update is enabled and build is old', () {
      const info = AppUpdateInfo(
        platform: 'android',
        latestVersion: '2026.05.20.7',
        latestBuild: 100007,
        minSupportedBuild: 100000,
        updateUrl: 'https://opshub.hoanghochoi.com/downloads/app.apk',
        releaseNotes: 'GitHub 5652baf',
        forceUpdate: true,
      );

      expect(info.hasUpdate(100006), isTrue);
      expect(info.requiresUpdate(100006), isTrue);
    });

    test(
      'requires update when current build is below minimum supported build',
      () {
        const info = AppUpdateInfo(
          platform: 'android',
          latestVersion: '2026.05.20.7',
          latestBuild: 100007,
          minSupportedBuild: 100005,
          updateUrl: 'https://opshub.hoanghochoi.com/downloads/app.apk',
          releaseNotes: 'GitHub 5652baf',
          forceUpdate: false,
        );

        expect(info.hasUpdate(100004), isTrue);
        expect(info.requiresUpdate(100004), isTrue);
      },
    );
  });
}
