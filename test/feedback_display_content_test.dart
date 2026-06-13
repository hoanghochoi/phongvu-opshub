import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/features/admin/data/feedback_display_content.dart';

void main() {
  test('extracts feedback image links from backend content', () {
    final content = FeedbackDisplayContent.fromRaw(
      'Chức năng: Phản hồi\n'
      'Mô tả: Không gửi được ảnh\n'
      'Hình ảnh: https://img.example.com/feedback/1/a.jpg;'
      ' https://img.example.com/feedback/1/b.png',
    );

    expect(content.body, 'Chức năng: Phản hồi\nMô tả: Không gửi được ảnh');
    expect(content.imageUrls, [
      'https://img.example.com/feedback/1/a.jpg',
      'https://img.example.com/feedback/1/b.png',
    ]);
  });

  test('keeps invalid image line visible when no displayable link exists', () {
    final content = FeedbackDisplayContent.fromRaw(
      'Mô tả: Lỗi\nHình ảnh: not-a-url',
    );

    expect(content.body, 'Mô tả: Lỗi\nHình ảnh: not-a-url');
    expect(content.imageUrls, isEmpty);
  });

  test('deduplicates image links and keeps non-image leftover text', () {
    final content = FeedbackDisplayContent.fromRaw(
      'Mô tả: Lỗi\n'
      'Hình ảnh: https://img.example.com/a.jpg; note;'
      ' https://img.example.com/a.jpg',
    );

    expect(content.body, 'Mô tả: Lỗi\nHình ảnh: note');
    expect(content.imageUrls, ['https://img.example.com/a.jpg']);
  });

  test('uses fallback body when content only contains image links', () {
    final content = FeedbackDisplayContent.fromRaw(
      'Hình ảnh: https://img.example.com/a.jpg',
    );

    expect(content.body, 'Không có nội dung');
    expect(content.imageUrls, ['https://img.example.com/a.jpg']);
  });
}
