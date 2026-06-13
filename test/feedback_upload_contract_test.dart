import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/network/api_exception.dart';
import 'package:phongvu_opshub/features/feedback/data/feedback_upload_contract.dart';

void main() {
  test('feedback fields match backend DTO without legacy metadata', () {
    final fields = buildFeedbackMultipartFields(
      functionName: '  Lỗi gửi ảnh  ',
      description: '  Không gửi được phản hồi  ',
    );

    expect(fields, {
      'function': 'Lỗi gửi ảnh',
      'description': 'Không gửi được phản hồi',
    });
    expect(fields, isNot(contains('user_email')));
    expect(fields, isNot(contains('timestamp')));
  });

  test(
    'feedback image multipart file includes an allowed image MIME type',
    () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'feedback_upload_test_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final image = File('${tempDir.path}${Platform.pathSeparator}receipt.png')
        ..writeAsBytesSync([0, 1, 2, 3]);

      final multipart = await buildFeedbackImageMultipartFile(
        image: image,
        index: 0,
      );

      expect(multipart.field, 'images');
      expect(multipart.filename, 'receipt.png');
      expect(multipart.contentType.toString(), 'image/png');
    },
  );

  test(
    'feedback upload rejects unsupported image extensions before sending',
    () {
      final tempDir = Directory.systemTemp.createTempSync(
        'feedback_upload_test_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final image = File('${tempDir.path}${Platform.pathSeparator}notes.txt')
        ..writeAsStringSync('not an image');

      expect(
        buildFeedbackImageMultipartFile(image: image, index: 0),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test('feedback image MIME detection accepts supported extensions', () {
    expect(feedbackImageMimeTypeFor(fileName: 'photo.jpg'), 'image/jpeg');
    expect(feedbackImageMimeTypeFor(fileName: 'photo.JPEG'), 'image/jpeg');
    expect(feedbackImageMimeTypeFor(fileName: 'photo.webp'), 'image/webp');
    expect(feedbackImageMimeTypeFor(fileName: 'photo.heic'), 'image/heic');
    expect(feedbackImageMimeTypeFor(fileName: 'photo.pdf'), isNull);
  });
}
