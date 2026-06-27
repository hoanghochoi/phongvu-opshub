import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

typedef VietQrPlatformProvider = TargetPlatform Function();
typedef VietQrDownloadsDirectoryProvider = Future<Directory?> Function();
typedef VietQrDocumentsDirectoryProvider = Future<Directory> Function();

class VietQrImageSaveResult {
  final String method;
  final String destination;
  final String fileName;
  final String displayPath;
  final String userMessage;
  final String? fallbackReason;

  const VietQrImageSaveResult({
    required this.method,
    required this.destination,
    required this.fileName,
    required this.displayPath,
    required this.userMessage,
    this.fallbackReason,
  });

  bool get usedFallback => fallbackReason != null;
}

class VietQrImageSaver {
  VietQrImageSaver({
    MethodChannel? mediaChannel,
    VietQrPlatformProvider? platformProvider,
    VietQrDownloadsDirectoryProvider? downloadsDirectoryProvider,
    VietQrDocumentsDirectoryProvider? documentsDirectoryProvider,
  }) : _mediaChannel =
           mediaChannel ?? const MethodChannel('phongvu_opshub/media'),
       _platformProvider = platformProvider ?? _currentTargetPlatform,
       _downloadsDirectoryProvider =
           downloadsDirectoryProvider ?? getDownloadsDirectory,
       _documentsDirectoryProvider =
           documentsDirectoryProvider ?? getApplicationDocumentsDirectory;

  final MethodChannel _mediaChannel;
  final VietQrPlatformProvider _platformProvider;
  final VietQrDownloadsDirectoryProvider _downloadsDirectoryProvider;
  final VietQrDocumentsDirectoryProvider _documentsDirectoryProvider;

  Future<VietQrImageSaveResult> savePng({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final platform = _platformProvider();
    if (platform == TargetPlatform.android) {
      try {
        final uri = await _mediaChannel.invokeMethod<String>(
          'savePngToGallery',
          {'fileName': fileName, 'bytes': bytes},
        );
        return VietQrImageSaveResult(
          method: 'android_media_store',
          destination: 'gallery',
          fileName: fileName,
          displayPath: uri ?? '',
          userMessage: 'Đã lưu ảnh QR vào thư viện ảnh',
        );
      } on MissingPluginException {
        return _saveToDownloadFile(
          bytes: bytes,
          fileName: fileName,
          platform: platform,
          method: 'android_downloads_fallback',
          fallbackReason: 'missing_plugin',
        );
      } on PlatformException catch (error) {
        return _saveToDownloadFile(
          bytes: bytes,
          fileName: fileName,
          platform: platform,
          method: 'android_downloads_fallback',
          fallbackReason: error.code,
        );
      }
    }

    return _saveToDownloadFile(
      bytes: bytes,
      fileName: fileName,
      platform: platform,
      method: 'file_downloads',
    );
  }

  Future<VietQrImageSaveResult> _saveToDownloadFile({
    required Uint8List bytes,
    required String fileName,
    required TargetPlatform platform,
    required String method,
    String? fallbackReason,
  }) async {
    final directory = await _resolveDownloadDirectory(platform);
    await directory.create(recursive: true);
    final file = await _nextAvailableFile(directory, fileName);
    await file.writeAsBytes(bytes, flush: true);

    return VietQrImageSaveResult(
      method: method,
      destination: 'downloads',
      fileName: file.uri.pathSegments.last,
      displayPath: file.path,
      userMessage: 'Đã lưu ảnh QR vào: ${file.path}',
      fallbackReason: fallbackReason,
    );
  }

  Future<Directory> _resolveDownloadDirectory(TargetPlatform platform) async {
    if (platform == TargetPlatform.android) {
      return await _safeDownloadsDirectory() ??
          Directory('/storage/emulated/0/Download');
    }
    if (platform == TargetPlatform.iOS) {
      return _documentsDirectoryProvider();
    }
    return await _safeDownloadsDirectory() ??
        await _documentsDirectoryProvider();
  }

  Future<Directory?> _safeDownloadsDirectory() async {
    try {
      return _downloadsDirectoryProvider();
    } catch (_) {
      return null;
    }
  }

  Future<File> _nextAvailableFile(Directory directory, String fileName) async {
    final dotIndex = fileName.lastIndexOf('.');
    final baseName = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
    final extension = dotIndex > 0 ? fileName.substring(dotIndex) : '';
    var candidate = File('${directory.path}${Platform.pathSeparator}$fileName');
    var index = 1;

    while (await candidate.exists()) {
      candidate = File(
        '${directory.path}${Platform.pathSeparator}$baseName'
        '_$index$extension',
      );
      index += 1;
    }
    return candidate;
  }
}

String buildVietQrImageFileName(String transferContent, DateTime now) {
  final exportName = transferContent.isEmpty
      ? now.millisecondsSinceEpoch.toString()
      : transferContent;
  final safeName = exportName.replaceAll(RegExp(r'[^A-Z0-9_-]'), '_');
  return 'vietqr_$safeName.png';
}

TargetPlatform _currentTargetPlatform() => defaultTargetPlatform;
