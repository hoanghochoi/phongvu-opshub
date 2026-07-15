import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../core/config/app_brand.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_client.dart';
import '../domain/app_update_info.dart';
import 'app_update_service.dart';

typedef AppUpdatePackageInstaller =
    Future<void> Function(AppUpdateInstallRequest request);
typedef AppUpdateTempDirectoryProvider = Future<Directory> Function();

class AppSelfUpdateService {
  AppSelfUpdateService({
    http.Client? httpClient,
    AppUpdatePackageInstaller? installer,
    AppUpdateTempDirectoryProvider? tempDirectoryProvider,
    int maxPackageBytes = 512 * 1024 * 1024,
    Duration overallDownloadTimeout = const Duration(minutes: 15),
  }) : _httpClient = httpClient ?? http.Client(),
       _installer = installer ?? _installPackage,
       _tempDirectoryProvider = tempDirectoryProvider ?? getTemporaryDirectory,
       _maxPackageBytes = maxPackageBytes,
       _overallDownloadTimeout = overallDownloadTimeout;

  static const _androidChannel = MethodChannel('phongvu_opshub/app_update');
  static const _connectTimeout = Duration(seconds: 30);
  static const _chunkTimeout = Duration(minutes: 5);
  static const _productionPackageHost = 'opshub.hoanghochoi.com';
  static const _stagingPackageHost = 'opshub-staging.hoanghochoi.com';
  static const _windowsRelaunchArg = '/OPSHUBRELAUNCH=1';
  static const _defaultWindowsInstallerArgs = [
    '/VERYSILENT',
    '/SUPPRESSMSGBOXES',
    '/NORESTART',
    '/CLOSEAPPLICATIONS',
    _windowsRelaunchArg,
  ];

  final http.Client _httpClient;
  final AppUpdatePackageInstaller _installer;
  final AppUpdateTempDirectoryProvider _tempDirectoryProvider;
  final int _maxPackageBytes;
  final Duration _overallDownloadTimeout;

  Future<void> downloadAndInstall(
    AppUpdateCheckResult result, {
    ValueChanged<AppSelfUpdateProgress>? onProgress,
  }) async {
    final info = result.updateInfo;
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
      if (kIsWeb || info.platform.trim().toLowerCase() == 'web') {
        throw const AppSelfUpdateException(
          'Bản web sẽ được tải lại trực tiếp, không cần gói cài đặt.',
          code: 'PREPARING_WEB_PACKAGE_UNSUPPORTED',
          stage: AppSelfUpdateStage.preparing,
        );
      }
      if (!info.hasSelfUpdatePackage) {
        throw const AppSelfUpdateException(
          'Bản cập nhật chưa có đủ thông tin kiểm tra an toàn. Vui lòng báo quản trị viên.',
          code: 'PREPARING_METADATA_INCOMPLETE',
          stage: AppSelfUpdateStage.preparing,
        );
      }

      final packageUri = Uri.tryParse(info.packageUrl);
      if (packageUri == null || !_isTrustedPackageUri(packageUri)) {
        throw const AppSelfUpdateException(
          'Gói cập nhật không đến từ máy chủ tin cậy. Vui lòng báo quản trị viên.',
          code: 'PREPARING_SOURCE_REJECTED',
          stage: AppSelfUpdateStage.preparing,
        );
      }
      _validatePackageContract(info, packageUri);
      if (_maxPackageBytes <= 0) {
        throw const AppSelfUpdateException(
          'Giới hạn tải bản cập nhật chưa được cấu hình an toàn.',
          code: 'PREPARING_LIMIT_INVALID',
          stage: AppSelfUpdateStage.preparing,
        );
      }
      if (info.packageSizeBytes > _maxPackageBytes) {
        throw AppSelfUpdateException(
          'Gói cập nhật vượt quá dung lượng an toàn. Vui lòng báo quản trị viên.',
          code: 'PREPARING_PACKAGE_TOO_LARGE',
          stage: AppSelfUpdateStage.preparing,
          expectedBytes: info.packageSizeBytes,
        );
      }

      final file = await _downloadPackage(info, packageUri, onProgress);
      await _verifyPackage(info, file, onProgress);
      final installRequest = AppUpdateInstallRequest(
        platform: info.platform.trim().toLowerCase(),
        packageType: info.packageType,
        filePath: file.path,
        installerArgs: _installerArgsFor(info),
      );
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
      await _logFailure(result, error, startedAt);
      rethrow;
    } on PlatformException catch (error) {
      final failure = AppSelfUpdateException(
        _messageForNativeInstaller(error),
        code: error.code.trim().isEmpty
            ? 'INSTALLING_NATIVE_FAILURE'
            : error.code,
        stage: AppSelfUpdateStage.installing,
      );
      await _logFailure(result, failure, startedAt);
      throw failure;
    } catch (_) {
      const failure = AppSelfUpdateException(
        'Chưa cập nhật được. Vui lòng thử lại sau ít phút.',
        code: 'UNEXPECTED_SELF_UPDATE_FAILURE',
        stage: AppSelfUpdateStage.unexpected,
      );
      await _logFailure(result, failure, startedAt);
      throw failure;
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
    late http.StreamedResponse response;
    try {
      response = await _httpClient.send(request).timeout(_connectTimeout);
    } on TimeoutException {
      throw const AppSelfUpdateException(
        'Kết nối tải bản cập nhật quá thời gian. Vui lòng thử lại.',
        code: 'DOWNLOADING_CONNECT_TIMEOUT',
        stage: AppSelfUpdateStage.downloading,
      );
    } on http.ClientException {
      throw const AppSelfUpdateException(
        'Chưa kết nối được máy chủ cập nhật. Vui lòng kiểm tra mạng và thử lại.',
        code: 'DOWNLOADING_NETWORK_FAILED',
        stage: AppSelfUpdateStage.downloading,
      );
    } on SocketException {
      throw const AppSelfUpdateException(
        'Chưa kết nối được máy chủ cập nhật. Vui lòng kiểm tra mạng và thử lại.',
        code: 'DOWNLOADING_NETWORK_FAILED',
        stage: AppSelfUpdateStage.downloading,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const AppSelfUpdateException(
        'Máy chủ cập nhật chưa sẵn sàng. Vui lòng thử lại sau.',
        code: 'DOWNLOADING_HTTP_FAILED',
        stage: AppSelfUpdateStage.downloading,
      );
    }

    final responseLength = response.contentLength ?? 0;
    if (responseLength > _maxPackageBytes) {
      throw AppSelfUpdateException(
        'Gói cập nhật vượt quá dung lượng an toàn. Đã dừng tải xuống.',
        code: 'DOWNLOADING_PACKAGE_TOO_LARGE',
        stage: AppSelfUpdateStage.downloading,
        receivedBytes: responseLength,
        expectedBytes: info.packageSizeBytes,
      );
    }
    if (info.packageSizeBytes > 0 &&
        responseLength > 0 &&
        responseLength != info.packageSizeBytes) {
      throw AppSelfUpdateException(
        'Dung lượng gói cập nhật không khớp thông tin phát hành.',
        code: 'DOWNLOADING_SIZE_MISMATCH',
        stage: AppSelfUpdateStage.downloading,
        receivedBytes: responseLength,
        expectedBytes: info.packageSizeBytes,
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
      try {
        await for (final chunk in response.stream.timeout(_chunkTimeout)) {
          receivedBytes += chunk.length;
          if (receivedBytes > _maxPackageBytes) {
            throw AppSelfUpdateException(
              'Gói cập nhật vượt quá dung lượng an toàn. Đã dừng tải xuống.',
              code: 'DOWNLOADING_PACKAGE_TOO_LARGE',
              stage: AppSelfUpdateStage.downloading,
              receivedBytes: receivedBytes,
              expectedBytes: info.packageSizeBytes,
            );
          }
          if (DateTime.now().difference(downloadStartedAt) >
              _overallDownloadTimeout) {
            throw AppSelfUpdateException(
              'Gói cập nhật tải quá thời gian. Vui lòng thử lại.',
              code: 'DOWNLOADING_OVERALL_TIMEOUT',
              stage: AppSelfUpdateStage.downloading,
              receivedBytes: receivedBytes,
              expectedBytes: info.packageSizeBytes,
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
      } on TimeoutException {
        throw AppSelfUpdateException(
          'Gói cập nhật tải quá thời gian. Vui lòng thử lại.',
          code: 'DOWNLOADING_STREAM_TIMEOUT',
          stage: AppSelfUpdateStage.downloading,
          receivedBytes: receivedBytes,
          expectedBytes: info.packageSizeBytes,
        );
      } on http.ClientException {
        throw AppSelfUpdateException(
          'Kết nối tải bản cập nhật bị gián đoạn. Vui lòng thử lại.',
          code: 'DOWNLOADING_NETWORK_FAILED',
          stage: AppSelfUpdateStage.downloading,
          receivedBytes: receivedBytes,
          expectedBytes: info.packageSizeBytes,
        );
      } on SocketException {
        throw AppSelfUpdateException(
          'Kết nối tải bản cập nhật bị gián đoạn. Vui lòng thử lại.',
          code: 'DOWNLOADING_NETWORK_FAILED',
          stage: AppSelfUpdateStage.downloading,
          receivedBytes: receivedBytes,
          expectedBytes: info.packageSizeBytes,
        );
      }
      downloadCompleted = true;
    } finally {
      await output.close();
      if (!downloadCompleted && await file.exists()) await file.delete();
    }

    if (info.packageSizeBytes > 0 && receivedBytes != info.packageSizeBytes) {
      if (await file.exists()) await file.delete();
      throw AppSelfUpdateException(
        'Gói cập nhật tải chưa đủ dữ liệu. Vui lòng thử lại.',
        code: 'DOWNLOADING_INCOMPLETE',
        stage: AppSelfUpdateStage.downloading,
        receivedBytes: receivedBytes,
        expectedBytes: info.packageSizeBytes,
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
        code: 'VERIFYING_SHA256_MISMATCH',
        stage: AppSelfUpdateStage.verifying,
      );
    }
    await AppLogger.instance.info(
      'AppSelfUpdate',
      'Self-update package SHA-256 verified',
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
    if (request.platform == 'android' && Platform.isAndroid) {
      await _androidChannel.invokeMethod<void>('installApk', {
        'path': request.filePath,
      });
      return;
    }
    if (request.platform == 'windows' && Platform.isWindows) {
      final args = request.installerArgs.isNotEmpty
          ? request.installerArgs
          : _defaultWindowsInstallerArgs;
      try {
        await Process.start(
          request.filePath,
          args,
          mode: ProcessStartMode.detached,
        );
      } on ProcessException {
        throw const AppSelfUpdateException(
          'Chưa mở được trình cài đặt. Vui lòng thử lại.',
          code: 'INSTALLING_LAUNCH_FAILED',
          stage: AppSelfUpdateStage.installing,
        );
      }
      exit(0);
    }
    throw const AppSelfUpdateException(
      'Nền tảng này chưa hỗ trợ tự cập nhật trong ứng dụng.',
      code: 'INSTALLING_UNSUPPORTED_PLATFORM',
      stage: AppSelfUpdateStage.installing,
    );
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
        code: 'PREPARING_PACKAGE_TYPE_INVALID',
        stage: AppSelfUpdateStage.preparing,
      );
    }
    if (platform == 'android' &&
        (packageType != 'apk' || !path.endsWith('.apk'))) {
      throw const AppSelfUpdateException(
        'Gói cập nhật Android không đúng định dạng được phép.',
        code: 'PREPARING_PACKAGE_TYPE_INVALID',
        stage: AppSelfUpdateStage.preparing,
      );
    }
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(info.packageSha256.trim())) {
      throw const AppSelfUpdateException(
        'Thông tin kiểm tra gói cập nhật không đúng định dạng.',
        code: 'PREPARING_PACKAGE_CONTRACT_INVALID',
        stage: AppSelfUpdateStage.preparing,
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
      return host == _stagingPackageHost && uri.path.startsWith('/downloads/');
    }
    return host == _productionPackageHost && uri.path.startsWith('/downloads/');
  }

  static Map<String, Object?> _logContext(AppUpdateCheckResult result) {
    final updateInfo = result.updateInfo;
    return {
      'platform': updateInfo.platform,
      'currentBuild': result.currentBuild,
      'latestBuild': updateInfo.latestBuild,
      'packageHost': Uri.tryParse(updateInfo.packageUrl)?.host.toLowerCase(),
      'packageSizeBytes': updateInfo.packageSizeBytes,
    };
  }

  static Future<void> _logFailure(
    AppUpdateCheckResult result,
    AppSelfUpdateException failure,
    DateTime startedAt,
  ) async {
    final context = <String, Object?>{
      ..._logContext(result),
      'code': failure.code,
      'stage': failure.stage.name,
      'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
      if (failure.receivedBytes != null) 'receivedBytes': failure.receivedBytes,
      if (failure.expectedBytes != null) 'expectedBytes': failure.expectedBytes,
    };
    if (failure.severity == AppSelfUpdateFailureSeverity.warning) {
      await AppLogger.instance.warn(
        'AppSelfUpdate',
        'Self-update transient failure',
        context: context,
      );
      return;
    }
    await AppLogger.instance.error(
      'AppSelfUpdate',
      'Self-update safety failure',
      context: context,
      upload: ApiClient().authToken != null,
    );
  }

  static List<String> _installerArgsFor(AppUpdateInfo info) {
    if (info.platform.toLowerCase() != 'windows') return info.installerArgs;
    return info.installerArgs.isNotEmpty
        ? info.installerArgs
        : _defaultWindowsInstallerArgs;
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

enum AppSelfUpdateStage {
  preparing,
  downloading,
  verifying,
  installing,
  unexpected,
}

enum AppSelfUpdateFailureSeverity { warning, error }

class AppSelfUpdateException implements Exception {
  const AppSelfUpdateException(
    this.message, {
    required this.code,
    required this.stage,
    this.receivedBytes,
    this.expectedBytes,
  });

  static const _warningCodes = <String>{
    'DOWNLOADING_CONNECT_TIMEOUT',
    'DOWNLOADING_NETWORK_FAILED',
    'DOWNLOADING_HTTP_FAILED',
    'DOWNLOADING_OVERALL_TIMEOUT',
    'DOWNLOADING_STREAM_TIMEOUT',
    'DOWNLOADING_INCOMPLETE',
  };

  final String message;
  final String code;
  final AppSelfUpdateStage stage;
  final int? receivedBytes;
  final int? expectedBytes;

  AppSelfUpdateFailureSeverity get severity => _warningCodes.contains(code)
      ? AppSelfUpdateFailureSeverity.warning
      : AppSelfUpdateFailureSeverity.error;

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
