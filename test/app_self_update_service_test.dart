import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phongvu_opshub/features/app_update/data/app_self_update_service.dart';
import 'package:phongvu_opshub/features/app_update/data/app_update_service.dart';
import 'package:phongvu_opshub/features/app_update/domain/app_update_info.dart';

void main() {
  group('AppSelfUpdateService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('opshub-update-test-');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('downloads, verifies, and launches installer', () async {
      final bytes = 'fake installer bytes'.codeUnits;
      AppUpdateInstallRequest? installRequest;
      final progress = <AppSelfUpdateProgress>[];
      final service = AppSelfUpdateService(
        httpClient: MockClient((_) async => http.Response.bytes(bytes, 200)),
        tempDirectoryProvider: () async => tempDir,
        installer: (request) async => installRequest = request,
      );

      await service.downloadAndInstall(
        _resultFor(bytes),
        onProgress: progress.add,
      );

      expect(installRequest, isNotNull);
      expect(installRequest!.filePath, endsWith('opshub.exe'));
      expect(installRequest!.installerArgs, [
        '/VERYSILENT',
        '/OPSHUBRELAUNCH=1',
      ]);
      expect(
        progress.map((item) => item.stage),
        contains(AppSelfUpdateStage.downloading),
      );
      expect(progress.last.stage, AppSelfUpdateStage.installing);
      expect(await File(installRequest!.filePath).readAsBytes(), bytes);
    });

    test(
      'uses relaunch default when Windows installer args are absent',
      () async {
        final bytes = 'fake installer bytes'.codeUnits;
        AppUpdateInstallRequest? installRequest;
        final service = AppSelfUpdateService(
          httpClient: MockClient((_) async => http.Response.bytes(bytes, 200)),
          tempDirectoryProvider: () async => tempDir,
          installer: (request) async => installRequest = request,
        );

        await service.downloadAndInstall(
          _resultFor(bytes, installerArgs: const <String>[]),
        );

        expect(installRequest, isNotNull);
        expect(installRequest!.installerArgs, [
          '/VERYSILENT',
          '/SUPPRESSMSGBOXES',
          '/NORESTART',
          '/CLOSEAPPLICATIONS',
          '/OPSHUBRELAUNCH=1',
        ]);
      },
    );

    test('stops when checksum does not match', () async {
      final bytes = 'fake installer bytes'.codeUnits;
      var installerCalled = false;
      final service = AppSelfUpdateService(
        httpClient: MockClient((_) async => http.Response.bytes(bytes, 200)),
        tempDirectoryProvider: () async => tempDir,
        installer: (_) async => installerCalled = true,
      );

      await expectLater(
        service.downloadAndInstall(
          _resultFor(
            bytes,
            sha256Override:
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          ),
        ),
        throwsA(isA<AppSelfUpdateException>()),
      );

      expect(installerCalled, isFalse);
      expect(
        await tempDir
            .list(recursive: true)
            .where((entity) => entity is File)
            .isEmpty,
        isTrue,
      );
    });
  });
}

AppUpdateCheckResult _resultFor(
  List<int> bytes, {
  String? sha256Override,
  List<String>? installerArgs,
}) {
  final digest = sha256.convert(bytes).toString();
  return AppUpdateCheckResult(
    currentVersion: '2026.07.01.1',
    currentBuild: 100001,
    updateInfo: AppUpdateInfo(
      platform: 'windows',
      latestVersion: '2026.07.06.1',
      latestBuild: 100002,
      minSupportedBuild: 100001,
      updateUrl: 'https://opshub.hoanghochoi.com/downloads/opshub.exe',
      packageUrl: 'https://opshub.hoanghochoi.com/downloads/opshub.exe',
      packageSha256: sha256Override ?? digest,
      packageSizeBytes: bytes.length,
      packageType: 'windowsInstaller',
      installerArgs: installerArgs ?? ['/VERYSILENT', '/OPSHUBRELAUNCH=1'],
      releaseNotes: 'Test build',
      forceUpdate: false,
    ),
  );
}
