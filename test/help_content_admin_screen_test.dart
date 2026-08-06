import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/help/data/repositories/help_content_repository.dart';
import 'package:phongvu_opshub/features/help/domain/help_content_page.dart';
import 'package:phongvu_opshub/features/help/presentation/screens/help_content_admin_screen.dart';

void main() {
  testWidgets('empty Help Content uses the approved state panel and CTA', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HelpContentAdminScreen(repository: _EmptyHelpContentRepository()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('help-content-empty-state')), findsOneWidget);
    expect(find.text('Chưa có trang hướng dẫn'), findsOneWidget);
    expect(find.text('Tạo trang đầu tiên để bắt đầu.'), findsOneWidget);
    expect(find.text('Quản lý hướng dẫn'), findsNothing);

    await tester.tap(find.byKey(const Key('app-state-action')));
    await tester.pump();

    expect(find.text('Tạo trang hướng dẫn'), findsOneWidget);
    expect(find.byKey(const Key('help-content-empty-state')), findsNothing);
  });
}

class _EmptyHelpContentRepository extends HelpContentRepository {
  _EmptyHelpContentRepository() : super(ApiClient());

  @override
  Future<HelpContentAdminSnapshot> fetchAdminSnapshot() async {
    return const HelpContentAdminSnapshot(pages: [], updatedAt: null);
  }
}
