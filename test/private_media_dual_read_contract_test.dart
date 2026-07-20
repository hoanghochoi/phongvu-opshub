import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/network/private_media_headers.dart';
import 'package:phongvu_opshub/features/admin/data/feedback_display_content.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/warranty/domain/entities/warranty_record.dart';

void main() {
  const apiBaseUrl = 'https://opshub.example.test/api';
  const legacyUrl =
      'https://opshub.example.test/uploads/warranty/legacy-photo.jpg';
  const privateUrl =
      'https://opshub.example.test/api/media/123e4567-e89b-42d3-a456-426614174000';

  test(
    'avatar keeps legacy and private references with scoped credentials',
    () {
      for (final url in [legacyUrl, privateUrl]) {
        final user = User.fromJson({
          'id': 'user-1',
          'email': 'user@example.test',
          'avatarUrl': url,
        });
        expect(user.avatarUrl, url);
      }

      expect(
        privateMediaHeaders(
          legacyUrl,
          apiBaseUrl: apiBaseUrl,
          authToken: 'session-token',
        ),
        isEmpty,
      );
      expect(
        privateMediaHeaders(
          privateUrl,
          apiBaseUrl: apiBaseUrl,
          authToken: 'session-token',
        ),
        const {'Authorization': 'Bearer session-token'},
      );
    },
  );

  test('warranty keeps a mixed legacy and private image list in order', () {
    final record = WarrantyRecord.fromJson({
      'receipt_number': 'CP01-J12345678',
      'drive_link': '',
      'images': [legacyUrl, privateUrl],
    });

    expect(record.imageUrls, [legacyUrl, privateUrl]);
    expect(
      record.imageUrls.map(
        (url) => privateMediaHeaders(
          url,
          apiBaseUrl: apiBaseUrl,
          authToken: 'session-token',
        ),
      ),
      [
        const <String, String>{},
        const {'Authorization': 'Bearer session-token'},
      ],
    );
  });

  test('feedback keeps mixed legacy and private image references', () {
    final content = FeedbackDisplayContent.fromRaw(
      'Mô tả: kiểm tra dual-read\nHình ảnh: $legacyUrl;$privateUrl',
    );

    expect(content.body, 'Mô tả: kiểm tra dual-read');
    expect(content.imageUrls, [legacyUrl, privateUrl]);
    expect(
      content.imageUrls.map(
        (url) => privateMediaHeaders(
          url,
          apiBaseUrl: apiBaseUrl,
          authToken: 'session-token',
        ),
      ),
      [
        const <String, String>{},
        const {'Authorization': 'Bearer session-token'},
      ],
    );
  });
}
