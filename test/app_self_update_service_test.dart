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
        packageVerifier: (_) async {},
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
          packageVerifier: (_) async {},
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
        packageVerifier: (_) async {},
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

    test('rejects an HTTP package URL before making a request', () async {
      final bytes = 'fake installer bytes'.codeUnits;
      var requestCount = 0;
      final service = AppSelfUpdateService(
        httpClient: MockClient((_) async {
          requestCount += 1;
          return http.Response.bytes(bytes, 200);
        }),
        tempDirectoryProvider: () async => tempDir,
        packageVerifier: (_) async {},
        installer: (_) async {},
      );

      await expectLater(
        service.downloadAndInstall(
          _resultFor(
            bytes,
            packageUrlOverride:
                'http://opshub.hoanghochoi.com/downloads/opshub.exe',
          ),
        ),
        throwsA(isA<AppSelfUpdateException>()),
      );
      expect(requestCount, 0);
    });

    test('rejects a package URL outside the trusted host and path', () async {
      final bytes = 'fake installer bytes'.codeUnits;
      final service = AppSelfUpdateService(
        httpClient: MockClient((_) async => http.Response.bytes(bytes, 200)),
        tempDirectoryProvider: () async => tempDir,
        packageVerifier: (_) async {},
        installer: (_) async {},
      );

      for (final packageUrl in <String>[
        'https://downloads.example.com/downloads/opshub.exe',
        'https://opshub.hoanghochoi.com/untrusted/opshub.exe',
        'https://opshub.hoanghochoi.com/downloads/../untrusted/opshub.exe',
      ]) {
        await expectLater(
          service.downloadAndInstall(
            _resultFor(bytes, packageUrlOverride: packageUrl),
          ),
          throwsA(isA<AppSelfUpdateException>()),
          reason: packageUrl,
        );
      }
    });

    test('scopes trusted package hosts to the build environment', () {
      final productionPackage = Uri.parse(
        'https://opshub.hoanghochoi.com/downloads/opshub.exe',
      );
      final stagingPackage = Uri.parse(
        'https://opshub-staging.hoanghochoi.com/downloads/opshub.exe',
      );
      final legacyStagingPackage = Uri.parse(
        'https://opshub.hoanghochoi.com/staging-download/downloads/opshub.exe',
      );

      expect(
        AppSelfUpdateService.isTrustedPackageUriForTesting(
          productionPackage,
          isStaging: false,
        ),
        isTrue,
      );
      expect(
        AppSelfUpdateService.isTrustedPackageUriForTesting(
          stagingPackage,
          isStaging: false,
        ),
        isFalse,
      );
      expect(
        AppSelfUpdateService.isTrustedPackageUriForTesting(
          stagingPackage,
          isStaging: true,
        ),
        isTrue,
      );
      expect(
        AppSelfUpdateService.isTrustedPackageUriForTesting(
          legacyStagingPackage,
          isStaging: true,
        ),
        isTrue,
      );
    });

    test('does not follow package download redirects', () async {
      final bytes = 'fake installer bytes'.codeUnits;
      final service = AppSelfUpdateService(
        httpClient: MockClient((request) async {
          expect(request.followRedirects, isFalse);
          return http.Response(
            '',
            302,
            headers: {'location': 'https://evil.test'},
          );
        }),
        tempDirectoryProvider: () async => tempDir,
        packageVerifier: (_) async {},
        installer: (_) async {},
      );

      await expectLater(
        service.downloadAndInstall(_resultFor(bytes)),
        throwsA(isA<AppSelfUpdateException>()),
      );
    });

    test(
      'checks the platform signature before launching the installer',
      () async {
        final bytes = 'fake installer bytes'.codeUnits;
        final calls = <String>[];
        final service = AppSelfUpdateService(
          httpClient: MockClient((_) async => http.Response.bytes(bytes, 200)),
          tempDirectoryProvider: () async => tempDir,
          packageVerifier: (_) async => calls.add('verify-signature'),
          installer: (_) async => calls.add('launch-installer'),
        );

        await service.downloadAndInstall(_resultFor(bytes));

        expect(calls, ['verify-signature', 'launch-installer']);
      },
    );

    test(
      'does not launch when platform signature verification fails',
      () async {
        final bytes = 'fake installer bytes'.codeUnits;
        var installerCalled = false;
        final service = AppSelfUpdateService(
          httpClient: MockClient((_) async => http.Response.bytes(bytes, 200)),
          tempDirectoryProvider: () async => tempDir,
          packageVerifier: (_) async =>
              throw const AppSelfUpdateException('Chữ ký không hợp lệ.'),
          installer: (_) async => installerCalled = true,
        );

        await expectLater(
          service.downloadAndInstall(_resultFor(bytes)),
          throwsA(isA<AppSelfUpdateException>()),
        );
        expect(installerCalled, isFalse);
      },
    );

    test(
      'Windows signature verifier handles a signed path with shell metacharacters',
      () async {
        if (!Platform.isWindows) return;
        final windowsRoot = Platform.environment['WINDIR'];
        expect(windowsRoot, isNotNull);
        final signedSource = File(
          '$windowsRoot${Platform.pathSeparator}System32'
          '${Platform.pathSeparator}WindowsPowerShell'
          '${Platform.pathSeparator}v1.0'
          '${Platform.pathSeparator}powershell.exe',
        );
        expect(await signedSource.exists(), isTrue);
        final signedDirectory = Directory(
          '${tempDir.path}${Platform.pathSeparator}signed package test',
        );
        await signedDirectory.create(recursive: true);
        final signedCopy = await signedSource.copy(
          '${signedDirectory.path}${Platform.pathSeparator}'
          "signed package ' + ; test.exe",
        );

        final signer =
            await AppSelfUpdateService.readWindowsSignerSha256ForTesting(
              signedCopy.path,
            );

        expect(signer, matches(RegExp(r'^[0-9A-F]{64}$')));
      },
    );

    test('Windows signature verifier rejects an unsigned executable', () async {
      if (!Platform.isWindows) return;
      final unsignedFile = File(
        '${tempDir.path}${Platform.pathSeparator}unsigned.exe',
      );
      await unsignedFile.writeAsString('not a signed executable');

      await expectLater(
        AppSelfUpdateService.readWindowsSignerSha256ForTesting(
          unsignedFile.path,
        ),
        throwsA(
          isA<AppSelfUpdateException>()
              .having(
                (error) => error.code,
                'code',
                'WINDOWS_SIGNATURE_NOT_VALID',
              )
              .having(
                (error) => error.message,
                'message',
                contains('Windows chưa xác nhận được chữ ký'),
              ),
        ),
      );
    });

    test('stops streaming when package exceeds the local hard cap', () async {
      final bytes = 'fake installer bytes'.codeUnits;
      var installerCalled = false;
      final service = AppSelfUpdateService(
        httpClient: MockClient((_) async => http.Response.bytes(bytes, 200)),
        tempDirectoryProvider: () async => tempDir,
        packageVerifier: (_) async {},
        installer: (_) async => installerCalled = true,
        maxPackageBytes: bytes.length - 1,
      );

      await expectLater(
        service.downloadAndInstall(_resultFor(bytes)),
        throwsA(isA<AppSelfUpdateException>()),
      );
      expect(installerCalled, isFalse);
    });
  });
}

AppUpdateCheckResult _resultFor(
  List<int> bytes, {
  String? sha256Override,
  List<String>? installerArgs,
  String? packageUrlOverride,
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
      packageUrl:
          packageUrlOverride ??
          'https://opshub.hoanghochoi.com/downloads/opshub.exe',
      packageSha256: sha256Override ?? digest,
      packageSizeBytes: bytes.length,
      packageType: 'windowsInstaller',
      installerArgs: installerArgs ?? ['/VERYSILENT', '/OPSHUBRELAUNCH=1'],
      releaseNotes: 'Test build',
      forceUpdate: false,
    ),
  );
}
