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
        packageUrl: 'https://opshub.hoanghochoi.com/downloads/app.apk',
        packageSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        packageSizeBytes: 10,
        packageType: 'apk',
        installerArgs: [],
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
        packageUrl: 'https://opshub.hoanghochoi.com/downloads/app.apk',
        packageSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        packageSizeBytes: 10,
        packageType: 'apk',
        installerArgs: [],
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
          packageUrl: 'https://opshub.hoanghochoi.com/downloads/app.apk',
          packageSha256:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          packageSizeBytes: 10,
          packageType: 'apk',
          installerArgs: [],
          releaseNotes: 'GitHub 5652baf',
          forceUpdate: false,
        );

        expect(info.hasUpdate(100004), isTrue);
        expect(info.requiresUpdate(100004), isTrue);
      },
    );

    test('parses self-update package metadata', () {
      final info = AppUpdateInfo.fromJson({
        'platform': 'windows',
        'latestVersion': '2026.07.06.1',
        'latestBuild': 100123,
        'minSupportedBuild': 100120,
        'updateUrl': 'https://opshub.hoanghochoi.com/downloads/manual.exe',
        'packageUrl':
            'https://opshub.hoanghochoi.com/downloads/self-update.exe',
        'packageSha256':
            'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
        'packageSizeBytes': '987654',
        'packageType': 'windowsInstaller',
        'installerArgs': ['/VERYSILENT', '/NORESTART'],
        'releaseNotes': 'GitHub abc1234',
        'forceUpdate': false,
      });

      expect(info.packageUrl, endsWith('self-update.exe'));
      expect(
        info.packageSha256,
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      );
      expect(info.packageSizeBytes, 987654);
      expect(info.packageType, 'windowsInstaller');
      expect(info.installerArgs, ['/VERYSILENT', '/NORESTART']);
      expect(info.hasSelfUpdatePackage, isTrue);
    });

    test(
      'falls back package URL to update URL but still requires checksum',
      () {
        final info = AppUpdateInfo.fromJson({
          'platform': 'android',
          'latestVersion': '2026.07.06.1',
          'latestBuild': 100123,
          'minSupportedBuild': 100120,
          'updateUrl': 'https://opshub.hoanghochoi.com/downloads/app.apk',
        });

        expect(info.packageUrl, info.updateUrl);
        expect(info.hasSelfUpdatePackage, isFalse);
      },
    );
  });
}
