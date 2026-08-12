import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/src/api/file_picker_result.dart';
import 'package:file_picker/src/api/file_picker_types.dart';
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shared test-process setup for plugin-backed code.
///
/// Flutter tests execute in a host process where platform channels are not
/// registered by default. The fakes below make the benign, expected cases
/// deterministic while leaving feature tests free to inject a successful file
/// selection when that behavior is under test.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  final directory = await Directory.systemTemp.createTemp(
    'opshub-flutter-test-',
  );
  late PathProviderPlatform previousPathProvider;
  late FilePickerPlatform previousFilePicker;

  setUpAll(() {
    previousPathProvider = PathProviderPlatform.instance;
    previousFilePicker = FilePickerPlatform.instance;
    PathProviderPlatform.instance = _TestPathProvider(directory.path);
    FilePickerPlatform.instance = _CancelledFilePicker();
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });
  tearDownAll(() async {
    await AppLogger.instance.flushForTesting();
    PathProviderPlatform.instance = previousPathProvider;
    FilePickerPlatform.instance = previousFilePicker;
    AppLogger.instance.setUploadsEnabledForTesting(true);
    await _deleteOwnedTemporaryDirectory(directory);
  });

  await testMain();
}

class _TestPathProvider extends PathProviderPlatform {
  _TestPathProvider(this.root);

  final String root;

  @override
  Future<String> getTemporaryPath() async => root;

  @override
  Future<String> getApplicationSupportPath() async => root;

  @override
  Future<String> getLibraryPath() async => root;

  @override
  Future<String> getApplicationDocumentsPath() async => root;

  @override
  Future<String> getApplicationCachePath() async => root;

  @override
  Future<String> getDownloadsPath() async => root;

  @override
  Future<List<String>> getExternalCachePaths() async => <String>[root];

  @override
  Future<List<String>> getExternalStoragePaths({
    StorageDirectory? type,
  }) async => <String>[root];
}

class _CancelledFilePicker extends FilePickerPlatform {
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    bool cancelUploadOnWindowBlur = true,
  }) async {
    return null;
  }

  @override
  Future<List<String>?> pickFileAndDirectoryPaths({
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  }) async {
    return null;
  }

  @override
  Future<bool?> clearTemporaryFiles() async => false;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async {
    return null;
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    return null;
  }
}

/// A deterministic picker for export tests. It returns a caller-provided path
/// and records the requested save metadata without opening a native dialog.
class TestSaveFilePicker extends _CancelledFilePicker {
  TestSaveFilePicker({this.path, this.error});

  final String? path;
  final Object? error;
  String? lastDialogTitle;
  String? lastFileName;
  Uint8List? lastBytes;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    lastDialogTitle = dialogTitle;
    lastFileName = fileName;
    lastBytes = bytes;
    final failure = error;
    if (failure != null) throw failure;
    return path;
  }
}

Future<void> _deleteOwnedTemporaryDirectory(Directory directory) async {
  if (!await directory.exists()) return;
  Object? lastError;
  for (var attempt = 0; attempt < 5; attempt += 1) {
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException catch (error) {
      lastError = error;
      await Future<void>.delayed(Duration(milliseconds: 25 * (attempt + 1)));
    }
  }
  Error.throwWithStackTrace(
    lastError ?? StateError('Temporary test directory could not be removed'),
    StackTrace.current,
  );
}
