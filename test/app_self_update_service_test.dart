import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
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

    test(
      'downloads, verifies SHA-256, and launches without Authenticode trust',
      () async {
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
      },
    );

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
        throwsA(
          isA<AppSelfUpdateException>()
              .having(
                (error) => error.code,
                'code',
                'VERIFYING_SHA256_MISMATCH',
              )
              .having(
                (error) => error.stage,
                'stage',
                AppSelfUpdateStage.verifying,
              )
              .having(
                (error) => error.severity,
                'severity',
                AppSelfUpdateFailureSeverity.error,
              ),
        ),
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
        throwsA(
          isA<AppSelfUpdateException>()
              .having(
                (error) => error.code,
                'code',
                'PREPARING_SOURCE_REJECTED',
              )
              .having(
                (error) => error.stage,
                'stage',
                AppSelfUpdateStage.preparing,
              ),
        ),
      );
      expect(requestCount, 0);
    });

    test('rejects a package URL outside the trusted host and path', () async {
      final bytes = 'fake installer bytes'.codeUnits;
      final service = AppSelfUpdateService(
        httpClient: MockClient((_) async => http.Response.bytes(bytes, 200)),
        tempDirectoryProvider: () async => tempDir,
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
      final crossOriginLegacyStagingPackage = Uri.parse(
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
          crossOriginLegacyStagingPackage,
          isStaging: true,
        ),
        isFalse,
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
        installer: (_) async {},
      );

      await expectLater(
        service.downloadAndInstall(_resultFor(bytes)),
        throwsA(
          isA<AppSelfUpdateException>()
              .having((error) => error.code, 'code', 'DOWNLOADING_HTTP_FAILED')
              .having(
                (error) => error.stage,
                'stage',
                AppSelfUpdateStage.downloading,
              )
              .having(
                (error) => error.severity,
                'severity',
                AppSelfUpdateFailureSeverity.warning,
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains('302')),
              ),
        ),
      );
    });

    test('classifies a network failure as a local warning', () async {
      final bytes = 'fake installer bytes'.codeUnits;
      final service = AppSelfUpdateService(
        httpClient: MockClient((_) async {
          throw http.ClientException('test network failure');
        }),
        tempDirectoryProvider: () async => tempDir,
        installer: (_) async {},
      );

      await expectLater(
        service.downloadAndInstall(_resultFor(bytes)),
        throwsA(
          isA<AppSelfUpdateException>()
              .having(
                (error) => error.code,
                'code',
                'DOWNLOADING_NETWORK_FAILED',
              )
              .having(
                (error) => error.stage,
                'stage',
                AppSelfUpdateStage.downloading,
              )
              .having(
                (error) => error.severity,
                'severity',
                AppSelfUpdateFailureSeverity.warning,
              ),
        ),
      );
    });

    test(
      'deletes an incomplete download and classifies it as warning',
      () async {
        final expectedBytes = 'complete installer bytes'.codeUnits;
        final partialBytes = expectedBytes.take(7).toList(growable: false);
        final service = AppSelfUpdateService(
          httpClient: _StreamedClient(
            (_) async => http.StreamedResponse(
              Stream<List<int>>.value(partialBytes),
              200,
            ),
          ),
          tempDirectoryProvider: () async => tempDir,
          installer: (_) async {},
        );

        await expectLater(
          service.downloadAndInstall(_resultFor(expectedBytes)),
          throwsA(
            isA<AppSelfUpdateException>()
                .having((error) => error.code, 'code', 'DOWNLOADING_INCOMPLETE')
                .having(
                  (error) => error.stage,
                  'stage',
                  AppSelfUpdateStage.downloading,
                )
                .having(
                  (error) => error.severity,
                  'severity',
                  AppSelfUpdateFailureSeverity.warning,
                )
                .having(
                  (error) => error.receivedBytes,
                  'receivedBytes',
                  partialBytes.length,
                ),
          ),
        );
        expect(
          await tempDir
              .list(recursive: true)
              .where((entity) => entity is File)
              .isEmpty,
          isTrue,
        );
      },
    );

    test('classifies an invalid package type as a preparing error', () async {
      final bytes = 'fake installer bytes'.codeUnits;
      var requestCount = 0;
      final service = AppSelfUpdateService(
        httpClient: MockClient((_) async {
          requestCount += 1;
          return http.Response.bytes(bytes, 200);
        }),
        tempDirectoryProvider: () async => tempDir,
        installer: (_) async {},
      );

      await expectLater(
        service.downloadAndInstall(
          _resultFor(bytes, packageTypeOverride: 'zip'),
        ),
        throwsA(
          isA<AppSelfUpdateException>()
              .having(
                (error) => error.code,
                'code',
                'PREPARING_PACKAGE_TYPE_INVALID',
              )
              .having(
                (error) => error.stage,
                'stage',
                AppSelfUpdateStage.preparing,
              )
              .having(
                (error) => error.severity,
                'severity',
                AppSelfUpdateFailureSeverity.error,
              ),
        ),
      );
      expect(requestCount, 0);
    });

    test('preserves native installer code at the installing stage', () async {
      final bytes = 'fake installer bytes'.codeUnits;
      final service = AppSelfUpdateService(
        httpClient: MockClient((_) async => http.Response.bytes(bytes, 200)),
        tempDirectoryProvider: () async => tempDir,
        installer: (_) async {
          throw PlatformException(code: 'PACKAGE_MISMATCH');
        },
      );

      await expectLater(
        service.downloadAndInstall(_resultFor(bytes)),
        throwsA(
          isA<AppSelfUpdateException>()
              .having((error) => error.code, 'code', 'PACKAGE_MISMATCH')
              .having(
                (error) => error.stage,
                'stage',
                AppSelfUpdateStage.installing,
              )
              .having(
                (error) => error.severity,
                'severity',
                AppSelfUpdateFailureSeverity.error,
              ),
        ),
      );
    });

    test('maps an unclassified failure to the unexpected stage', () async {
      final bytes = 'fake installer bytes'.codeUnits;
      final service = AppSelfUpdateService(
        httpClient: MockClient((_) async => http.Response.bytes(bytes, 200)),
        tempDirectoryProvider: () async => tempDir,
        installer: (_) async => throw StateError('test-only failure'),
      );

      await expectLater(
        service.downloadAndInstall(_resultFor(bytes)),
        throwsA(
          isA<AppSelfUpdateException>()
              .having(
                (error) => error.code,
                'code',
                'UNEXPECTED_SELF_UPDATE_FAILURE',
              )
              .having(
                (error) => error.stage,
                'stage',
                AppSelfUpdateStage.unexpected,
              )
              .having(
                (error) => error.severity,
                'severity',
                AppSelfUpdateFailureSeverity.error,
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

class _StreamedClient extends http.BaseClient {
  _StreamedClient(this._send);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) _send;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _send(request);
}

AppUpdateCheckResult _resultFor(
  List<int> bytes, {
  String? sha256Override,
  List<String>? installerArgs,
  String? packageUrlOverride,
  String? packageTypeOverride,
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
      packageType: packageTypeOverride ?? 'windowsInstaller',
      installerArgs: installerArgs ?? ['/VERYSILENT', '/OPSHUBRELAUNCH=1'],
      releaseNotes: 'Test build',
      forceUpdate: false,
    ),
  );
}
