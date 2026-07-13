import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/navigation/app_router.dart';

void main() {
  group('AppRouter.initialLocationForUri', () {
    test('keeps the public help path on a direct browser entry', () {
      expect(
        AppRouter.initialLocationForUri(
          Uri.parse('https://opshub-staging.hoanghochoi.com/help'),
        ),
        '/help',
      );
    });

    test('keeps an existing hash route', () {
      expect(
        AppRouter.initialLocationForUri(
          Uri.parse('https://opshub-staging.hoanghochoi.com/#/operations'),
        ),
        '/operations',
      );
    });

    test('uses home for an ordinary root entry', () {
      expect(
        AppRouter.initialLocationForUri(
          Uri.parse('https://opshub-staging.hoanghochoi.com/'),
        ),
        '/home',
      );
    });
  });
}
