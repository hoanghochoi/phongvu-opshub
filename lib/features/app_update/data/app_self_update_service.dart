import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../core/config/app_brand.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/app_update_info.dart';
import 'app_update_service.dart';

typedef AppUpdatePackageInstaller =
    Future<void> Function(AppUpdateInstallRequest request);
typedef AppUpdatePackageVerifier =
    Future<void> Function(AppUpdateInstallRequest request);
typedef AppUpdateTempDirectoryProvider = Future<Directory> Function();

class AppSelfUpdateService {
  AppSelfUpdateService({
    http.Client? httpClient,
    AppUpdatePackageInstaller? installer,
    AppUpdatePackageVerifier? packageVerifier,
    AppUpdateTempDirectoryProvider? tempDirectoryProvider,
    int maxPackageBytes = 512 * 1024 * 1024,
    Duration overallDownloadTimeout = const Duration(minutes: 15),
  }) : _httpClient = httpClient ?? http.Client(),
       _installer = installer ?? _installPackage,
       _packageVerifier = packageVerifier ?? _verifyPlatformPackage,
       _tempDirectoryProvider = tempDirectoryProvider ?? getTemporaryDirectory,
       _maxPackageBytes = maxPackageBytes,
       _overallDownloadTimeout = overallDownloadTimeout;

  static const _androidChannel = MethodChannel('phongvu_opshub/app_update');
  static const _connectTimeout = Duration(seconds: 30);
  static const _chunkTimeout = Duration(minutes: 5);
  static const _signatureCheckTimeout = Duration(seconds: 30);
  static const _productionPackageHost = 'opshub.hoanghochoi.com';
  static const _stagingPackageHost = 'opshub-staging.hoanghochoi.com';
  static const _windowsRelaunchArg = '/OPSHUBRELAUNCH=1';
  static const _windowsUpdateSignerSha256 = String.fromEnvironment(
    'WINDOWS_UPDATE_SIGNER_SHA256',
  );
  static const _defaultWindowsInstallerArgs = [
    '/VERYSILENT',
    '/SUPPRESSMSGBOXES',
    '/NORESTART',
    '/CLOSEAPPLICATIONS',
    _windowsRelaunchArg,
  ];

  final http.Client _httpClient;
  final AppUpdatePackageInstaller _installer;
  final AppUpdatePackageVerifier _packageVerifier;
  final AppUpdateTempDirectoryProvider _tempDirectoryProvider;
  final int _maxPackageBytes;
  final Duration _overallDownloadTimeout;

  Future<void> downloadAndInstall(
    AppUpdateCheckResult result, {
    ValueChanged<AppSelfUpdateProgress>? onProgress,
  }) async {
    final info = result.updateInfo;
    if (kIsWeb || info.platform == 'web') {
      throw const AppSelfUpdateException(
        'Bản web sẽ được tải lại trực tiếp, không cần gói cài đặt.',
      );
    }
    if (!info.hasSelfUpdatePackage) {
      throw const AppSelfUpdateException(
        'Bản cập nhật chưa có đủ thông tin kiểm tra an toàn. Vui lòng báo quản trị viên.',
      );
    }

    final packageUri = Uri.tryParse(info.packageUrl);
    if (packageUri == null || !_isTrustedPackageUri(packageUri)) {
      await AppLogger.instance.warn(
        'AppSelfUpdate',
        'Self-update package source rejected',
        context: {
          'platform': info.platform,
          'packageHost': packageUri?.host.toLowerCase() ?? 'invalid',
          'stagingBuild': AppBrand.isStaging,
        },
      );
      throw const AppSelfUpdateException(
        'Gói cập nhật không đến từ máy chủ tin cậy. Vui lòng báo quản trị viên.',
      );
    }
    _validatePackageContract(info, packageUri);
    if (_maxPackageBytes <= 0) {
      throw const AppSelfUpdateException(
        'Giới hạn tải bản cập nhật chưa được cấu hình an toàn.',
      );
    }
    if (info.packageSizeBytes > _maxPackageBytes) {
      throw const AppSelfUpdateException(
        'Gói cập nhật vượt quá dung lượng an toàn. Vui lòng báo quản trị viên.',
      );
    }

    final startedAt = DateTime.now();
    await AppLogger.instance.info(
      'AppSelfUpdate',
      'Self-update started',
      context: _logContext(result),
    );

    try {
      _emit(
        onProgress,
        const AppSelfUpdateProgress(
          stage: AppSelfUpdateStage.preparing,
          message: 'Đang chuẩn bị gói cập nhật...',
        ),
      );
      final file = await _downloadPackage(info, packageUri, onProgress);
      await _verifyPackage(info, file, onProgress);
      final installRequest = AppUpdateInstallRequest(
        platform: info.platform,
        packageType: info.packageType,
        filePath: file.path,
        installerArgs: _installerArgsFor(info),
      );
      await _packageVerifier(installRequest);
      _emit(
        onProgress,
        const AppSelfUpdateProgress(
          stage: AppSelfUpdateStage.installing,
          message: 'Đang mở trình cài đặt...',
        ),
      );
      await _installer(installRequest);
      await AppLogger.instance.info(
        'AppSelfUpdate',
        'Self-update installer launched',
        context: {
          ..._logContext(result),
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } on AppSelfUpdateException catch (error) {
      await AppLogger.instance.warn(
        'AppSelfUpdate',
        'Self-update stopped safely',
        context: {
          ..._logContext(result),
          'code': error.code ?? 'SELF_UPDATE_REJECTED',
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      rethrow;
    } on PlatformException catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AppSelfUpdate',
        'Self-update native installer failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          ..._logContext(result),
          'code': error.code,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      throw AppSelfUpdateException(
        _messageForNativeInstaller(error),
        code: error.code,
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AppSelfUpdate',
        'Self-update failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          ..._logContext(result),
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      throw const AppSelfUpdateException(
        'Chưa cập nhật được. Vui lòng thử lại khi mạng ổn định.',
      );
    }
  }

  Future<File> _downloadPackage(
    AppUpdateInfo info,
    Uri packageUri,
    ValueChanged<AppSelfUpdateProgress>? onProgress,
  ) async {
    final directory = Directory(
      '${(await _tempDirectoryProvider()).path}${Platform.pathSeparator}opshub-updates',
    );
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}${_downloadFileName(info, packageUri)}',
    );
    if (await file.exists()) await file.delete();

    final request = http.Request('GET', packageUri);
    request.followRedirects = false;
    final response = await _httpClient.send(request).timeout(_connectTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AppSelfUpdateException(
        'Không tải được gói cập nhật. Máy chủ trả về ${response.statusCode}.',
      );
    }

    final responseLength = response.contentLength ?? 0;
    if (responseLength > _maxPackageBytes) {
      throw const AppSelfUpdateException(
        'Gói cập nhật vượt quá dung lượng an toàn. Đã dừng tải xuống.',
      );
    }
    if (info.packageSizeBytes > 0 &&
        responseLength > 0 &&
        responseLength != info.packageSizeBytes) {
      throw const AppSelfUpdateException(
        'Dung lượng gói cập nhật không khớp thông tin phát hành.',
      );
    }
    final totalBytes = info.packageSizeBytes > 0
        ? info.packageSizeBytes
        : responseLength;
    var receivedBytes = 0;
    final downloadStartedAt = DateTime.now();
    final output = await file.open(mode: FileMode.write);
    var downloadCompleted = false;
    try {
      await for (final chunk in response.stream.timeout(_chunkTimeout)) {
        receivedBytes += chunk.length;
        if (receivedBytes > _maxPackageBytes ||
            DateTime.now().difference(downloadStartedAt) >
                _overallDownloadTimeout) {
          throw const AppSelfUpdateException(
            'Gói cập nhật tải quá lâu hoặc vượt dung lượng an toàn. Đã dừng tải xuống.',
          );
        }
        await output.writeFrom(chunk);
        _emit(
          onProgress,
          AppSelfUpdateProgress(
            stage: AppSelfUpdateStage.downloading,
            receivedBytes: receivedBytes,
            totalBytes: totalBytes > 0 ? totalBytes : null,
            message: 'Đang tải gói cập nhật...',
          ),
        );
      }
      downloadCompleted = true;
    } finally {
      await output.close();
      if (!downloadCompleted && await file.exists()) await file.delete();
    }

    if (info.packageSizeBytes > 0 && receivedBytes != info.packageSizeBytes) {
      if (await file.exists()) await file.delete();
      throw const AppSelfUpdateException(
        'Gói cập nhật tải chưa đủ dữ liệu. Vui lòng thử lại.',
      );
    }

    await AppLogger.instance.info(
      'AppSelfUpdate',
      'Self-update package downloaded',
      context: {
        'platform': info.platform,
        'latestBuild': info.latestBuild,
        'receivedBytes': receivedBytes,
        'expectedBytes': info.packageSizeBytes,
      },
    );
    return file;
  }

  Future<void> _verifyPackage(
    AppUpdateInfo info,
    File file,
    ValueChanged<AppSelfUpdateProgress>? onProgress,
  ) async {
    _emit(
      onProgress,
      const AppSelfUpdateProgress(
        stage: AppSelfUpdateStage.verifying,
        message: 'Đang kiểm tra gói cập nhật...',
      ),
    );
    final expected = info.packageSha256.trim().toLowerCase();
    final actual = await _sha256Of(file);
    if (actual != expected) {
      if (await file.exists()) await file.delete();
      throw const AppSelfUpdateException(
        'Gói cập nhật không khớp mã kiểm tra. Đã dừng để bảo vệ máy.',
      );
    }
    await AppLogger.instance.info(
      'AppSelfUpdate',
      'Self-update package verified',
      context: {
        'platform': info.platform,
        'latestBuild': info.latestBuild,
        'sizeBytes': await file.length(),
      },
    );
  }

  static Future<String> _sha256Of(File file) async {
    final sink = _DigestSink();
    final input = sha256.startChunkedConversion(sink);
    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
    input.close();
    return sink.value.toString();
  }

  static Future<void> _installPackage(AppUpdateInstallRequest request) async {
    if (request.platform == 'android' || Platform.isAndroid) {
      await _androidChannel.invokeMethod<void>('installApk', {
        'path': request.filePath,
      });
      return;
    }
    if (request.platform == 'windows' || Platform.isWindows) {
      final args = request.installerArgs.isNotEmpty
          ? request.installerArgs
          : _defaultWindowsInstallerArgs;
      await Process.start(
        request.filePath,
        args,
        mode: ProcessStartMode.detached,
      );
      exit(0);
    }
    throw const AppSelfUpdateException(
      'Nền tảng này chưa hỗ trợ tự cập nhật trong ứng dụng.',
    );
  }

  static Future<void> _verifyPlatformPackage(
    AppUpdateInstallRequest request,
  ) async {
    if (request.platform.toLowerCase() != 'windows') return;
    if (!Platform.isWindows) {
      throw const AppSelfUpdateException(
        'Không thể xác minh chữ ký gói Windows trên thiết bị này.',
      );
    }
    final trustedSigners = _windowsUpdateSignerSha256
        .split(RegExp(r'[,;\s]+'))
        .map(
          (value) =>
              value.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase(),
        )
        .where((value) => value.length == 64)
        .toSet();
    if (trustedSigners.isEmpty) {
      throw const AppSelfUpdateException(
        'Ứng dụng chưa có chứng thư tin cậy để tự cập nhật Windows. Vui lòng báo quản trị viên.',
      );
    }

    await AppLogger.instance.info(
      'AppSelfUpdate',
      'Windows package signature verification started',
      context: {'trustedSignerCount': trustedSigners.length},
    );
    try {
      final signer = await _readWindowsSignerSha256(request.filePath);
      if (!trustedSigners.contains(signer)) {
        await AppLogger.instance.warn(
          'AppSelfUpdate',
          'Windows package signer pin mismatch',
          context: {'signerHashPrefix': signer.substring(0, 12)},
        );
        throw const AppSelfUpdateException(
          'Chữ ký gói cập nhật Windows không đúng nhà phát hành tin cậy. Đã dừng cài đặt.',
          code: 'WINDOWS_SIGNER_PIN_MISMATCH',
        );
      }
      await AppLogger.instance.info(
        'AppSelfUpdate',
        'Windows package signature verification succeeded',
        context: {'signerHashPrefix': signer.substring(0, 12)},
      );
    } on AppSelfUpdateException catch (error) {
      await AppLogger.instance.warn(
        'AppSelfUpdate',
        'Windows package signature verification stopped',
        context: {'code': error.code ?? 'WINDOWS_SIGNATURE_REJECTED'},
      );
      rethrow;
    }
  }

  @visibleForTesting
  static Future<String> readWindowsSignerSha256ForTesting(String filePath) {
    return _readWindowsSignerSha256(filePath);
  }

  static Future<String> _readWindowsSignerSha256(String filePath) async {
    const packagePathEnvironmentKey = 'OPSHUB_UPDATE_PACKAGE_PATH';
    const script = r'''
$ErrorActionPreference = 'Stop'
$packagePath = [Environment]::GetEnvironmentVariable('OPSHUB_UPDATE_PACKAGE_PATH', 'Process')
if ([string]::IsNullOrWhiteSpace($packagePath)) { exit 12 }
$securityModule = Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1'
Import-Module -Name $securityModule -Force -ErrorAction Stop
$signature = Get-AuthenticodeSignature -LiteralPath $packagePath
if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate) { exit 11 }
$algorithm = [System.Security.Cryptography.HashAlgorithmName]::SHA256
[Console]::Out.Write($signature.SignerCertificate.GetCertHashString($algorithm))
''';
    late Process process;
    try {
      process = await Process.start(
        'powershell.exe',
        [
          '-NoLogo',
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          script,
        ],
        environment: {packagePathEnvironmentKey: filePath},
      );
      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      late int exitCode;
      try {
        exitCode = await process.exitCode.timeout(_signatureCheckTimeout);
      } on TimeoutException {
        process.kill();
        throw const AppSelfUpdateException(
          'Kiểm tra chữ ký gói cập nhật quá thời gian. Đã dừng cài đặt.',
          code: 'WINDOWS_SIGNATURE_CHECK_TIMEOUT',
        );
      }
      final signer = (await stdoutFuture)
          .replaceAll(RegExp(r'[^0-9A-Fa-f]'), '')
          .toUpperCase();
      final stderr = await stderrFuture;
      if (exitCode == 11) {
        throw const AppSelfUpdateException(
          'Windows chưa xác nhận được chữ ký của gói cập nhật. Đã dừng cài đặt.',
          code: 'WINDOWS_SIGNATURE_NOT_VALID',
        );
      }
      if (exitCode != 0 || signer.length != 64) {
        throw AppSelfUpdateException(
          'Chưa xác minh được chữ ký gói cập nhật Windows. Đã dừng cài đặt.',
          code: stderr.trim().isEmpty
              ? 'WINDOWS_SIGNATURE_CHECK_FAILED'
              : 'WINDOWS_SIGNATURE_CHECK_PROCESS_FAILED',
        );
      }
      return signer;
    } on AppSelfUpdateException {
      rethrow;
    } catch (_) {
      throw const AppSelfUpdateException(
        'Chưa xác minh được chữ ký gói cập nhật Windows. Đã dừng cài đặt.',
        code: 'WINDOWS_SIGNATURE_CHECK_FAILED',
      );
    }
  }

  static String _messageForNativeInstaller(PlatformException error) {
    if (error.code == 'INSTALL_PERMISSION_REQUIRED') {
      return 'Vui lòng cho phép OpsHub cài bản cập nhật, rồi quay lại bấm Cập nhật lần nữa.';
    }
    if (error.code == 'PACKAGE_MISMATCH') {
      return 'Gói cập nhật không đúng ứng dụng OpsHub. Đã dừng cài đặt.';
    }
    if (error.code == 'SIGNATURE_MISMATCH') {
      return 'Gói cập nhật không cùng chữ ký với bản đang cài. Đã dừng cài đặt.';
    }
    if (error.code == 'VERSION_NOT_NEWER') {
      return 'Gói cập nhật không mới hơn bản hiện tại. Đã dừng cài đặt.';
    }
    return 'Chưa mở được trình cài đặt. Vui lòng thử lại.';
  }

  static String _downloadFileName(AppUpdateInfo info, Uri packageUri) {
    final rawName = packageUri.pathSegments.isNotEmpty
        ? packageUri.pathSegments.last
        : 'opshub-update.${info.platform == 'android' ? 'apk' : 'exe'}';
    final sanitized = rawName.replaceAll(RegExp(r'[^0-9A-Za-z._+-]'), '_');
    if (sanitized.isEmpty) {
      return 'opshub-update-${info.latestBuild}.${info.platform == 'android' ? 'apk' : 'exe'}';
    }
    return sanitized;
  }

  static void _validatePackageContract(AppUpdateInfo info, Uri packageUri) {
    final platform = info.platform.trim().toLowerCase();
    final packageType = info.packageType.trim().toLowerCase();
    final path = packageUri.path.toLowerCase();
    if (platform == 'windows' &&
        (packageType != 'windowsinstaller' || !path.endsWith('.exe'))) {
      throw const AppSelfUpdateException(
        'Gói cập nhật Windows không đúng định dạng được phép.',
      );
    }
    if (platform == 'android' &&
        (packageType != 'apk' || !path.endsWith('.apk'))) {
      throw const AppSelfUpdateException(
        'Gói cập nhật Android không đúng định dạng được phép.',
      );
    }
  }

  static bool _isTrustedPackageUri(Uri uri) =>
      isTrustedPackageUriForTesting(uri, isStaging: AppBrand.isStaging);

  @visibleForTesting
  static bool isTrustedPackageUriForTesting(
    Uri uri, {
    required bool isStaging,
  }) {
    if (uri.scheme.toLowerCase() != 'https' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.pathSegments.any((segment) => segment == '.' || segment == '..')) {
      return false;
    }
    final host = uri.host.toLowerCase();
    if (isStaging) {
      return (host == _stagingPackageHost &&
              uri.path.startsWith('/downloads/')) ||
          (host == _productionPackageHost &&
              uri.path.startsWith('/staging-download/downloads/'));
    }
    return host == _productionPackageHost && uri.path.startsWith('/downloads/');
  }

  static Map<String, Object?> _logContext(AppUpdateCheckResult result) {
    final updateInfo = result.updateInfo;
    return {
      'platform': updateInfo.platform,
      'currentBuild': result.currentBuild,
      'latestBuild': updateInfo.latestBuild,
      'packageType': updateInfo.packageType,
      'packageHost': Uri.tryParse(updateInfo.packageUrl)?.host.toLowerCase(),
      'stagingBuild': AppBrand.isStaging,
      'packageSizeBytes': updateInfo.packageSizeBytes,
      'hasSha256': updateInfo.packageSha256.isNotEmpty,
      'windowsRelaunchRequested': updateInfo.platform.toLowerCase() == 'windows'
          ? _hasWindowsRelaunchArg(_installerArgsFor(updateInfo))
          : null,
    };
  }

  static List<String> _installerArgsFor(AppUpdateInfo info) {
    if (info.platform.toLowerCase() != 'windows') return info.installerArgs;
    return info.installerArgs.isNotEmpty
        ? info.installerArgs
        : _defaultWindowsInstallerArgs;
  }

  static bool _hasWindowsRelaunchArg(List<String> args) {
    return args.any((arg) {
      final normalized = arg.trim().toUpperCase();
      return normalized == '/OPSHUBRELAUNCH' ||
          normalized == _windowsRelaunchArg;
    });
  }

  static void _emit(
    ValueChanged<AppSelfUpdateProgress>? onProgress,
    AppSelfUpdateProgress progress,
  ) {
    onProgress?.call(progress);
  }
}

class AppUpdateInstallRequest {
  const AppUpdateInstallRequest({
    required this.platform,
    required this.packageType,
    required this.filePath,
    required this.installerArgs,
  });

  final String platform;
  final String packageType;
  final String filePath;
  final List<String> installerArgs;
}

class AppSelfUpdateProgress {
  const AppSelfUpdateProgress({
    required this.stage,
    required this.message,
    this.receivedBytes = 0,
    this.totalBytes,
  });

  final AppSelfUpdateStage stage;
  final String message;
  final int receivedBytes;
  final int? totalBytes;

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0, 1).toDouble();
  }

  String get displayMessage {
    final value = fraction;
    if (value == null || stage != AppSelfUpdateStage.downloading) {
      return message;
    }
    return '$message ${(value * 100).clamp(0, 100).toStringAsFixed(0)}%';
  }
}

enum AppSelfUpdateStage { preparing, downloading, verifying, installing }

class AppSelfUpdateException implements Exception {
  const AppSelfUpdateException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class _DigestSink implements Sink<Digest> {
  Digest? _value;

  Digest get value {
    final digest = _value;
    if (digest == null) {
      throw StateError('SHA256 digest has not been completed.');
    }
    return digest;
  }

  @override
  void add(Digest data) {
    _value = data;
  }

  @override
  void close() {}
}
