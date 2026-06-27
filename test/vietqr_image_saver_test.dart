import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/features/vietqr/presentation/services/vietqr_image_saver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildVietQrImageFileName', () {
    test('uses transfer content when available', () {
      expect(
        buildVietQrImageFileName('ABC123 SR01 BOT', DateTime(2026)),
        'vietqr_ABC123_SR01_BOT.png',
      );
    });

    test('uses timestamp when transfer content is blank', () {
      expect(
        buildVietQrImageFileName(
          '',
          DateTime.fromMillisecondsSinceEpoch(123456789),
        ),
        'vietqr_123456789.png',
      );
    });
  });

  group('VietQrImageSaver', () {
    test('saves through Android gallery channel when available', () async {
      final channel = MethodChannel('test_vietqr_media_gallery');
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'savePngToGallery');
            expect(call.arguments['fileName'], 'vietqr_TEST.png');
            expect(call.arguments['bytes'], Uint8List.fromList([1, 2, 3]));
            return 'content://media/vietqr_TEST.png';
          });

      final saver = VietQrImageSaver(
        mediaChannel: channel,
        platformProvider: () => TargetPlatform.android,
      );

      final result = await saver.savePng(
        bytes: Uint8List.fromList([1, 2, 3]),
        fileName: 'vietqr_TEST.png',
      );

      expect(result.method, 'android_media_store');
      expect(result.destination, 'gallery');
      expect(result.displayPath, 'content://media/vietqr_TEST.png');
      expect(result.usedFallback, isFalse);
    });

    test('falls back to downloads when Android channel is missing', () async {
      final tempDir = await Directory.systemTemp.createTemp('vietqr_saver_');
      addTearDown(() => tempDir.delete(recursive: true));
      final channel = MethodChannel('test_vietqr_media_missing');
      final saver = VietQrImageSaver(
        mediaChannel: channel,
        platformProvider: () => TargetPlatform.android,
        downloadsDirectoryProvider: () async => tempDir,
      );

      final result = await saver.savePng(
        bytes: Uint8List.fromList([4, 5, 6]),
        fileName: 'vietqr_TEST.png',
      );

      final file = File(
        '${tempDir.path}${Platform.pathSeparator}vietqr_TEST.png',
      );
      expect(result.method, 'android_downloads_fallback');
      expect(result.destination, 'downloads');
      expect(result.fallbackReason, 'missing_plugin');
      expect(await file.readAsBytes(), Uint8List.fromList([4, 5, 6]));
    });

    test(
      'desktop saves to downloads without overwriting existing files',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('vietqr_saver_');
        addTearDown(() => tempDir.delete(recursive: true));
        final existing = File(
          '${tempDir.path}${Platform.pathSeparator}vietqr_TEST.png',
        );
        await existing.writeAsBytes([0], flush: true);
        final saver = VietQrImageSaver(
          platformProvider: () => TargetPlatform.windows,
          downloadsDirectoryProvider: () async => tempDir,
        );

        final result = await saver.savePng(
          bytes: Uint8List.fromList([7, 8, 9]),
          fileName: 'vietqr_TEST.png',
        );

        final saved = File(
          '${tempDir.path}${Platform.pathSeparator}vietqr_TEST_1.png',
        );
        expect(result.method, 'file_downloads');
        expect(result.destination, 'downloads');
        expect(result.fileName, 'vietqr_TEST_1.png');
        expect(await existing.readAsBytes(), [0]);
        expect(await saved.readAsBytes(), Uint8List.fromList([7, 8, 9]));
      },
    );
  });
}
