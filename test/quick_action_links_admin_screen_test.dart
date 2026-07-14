import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/quick_actions/data/quick_actions_repository.dart';
import 'package:phongvu_opshub/features/quick_actions/presentation/quick_action_links_admin_screen.dart';

void main() {
  testWidgets('returns focus to the scanned link instead of showroom search', (
    tester,
  ) async {
    final repository = _FakeQuickActionsRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickActionLinksAdminScreen(
            repository: repository,
            cameraScannerSupported: true,
            scanner: (_, _, _) async => 'https://example.com/app',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.tap(find.text('CP75 · Showroom 75').last);
    await tester.pump();
    await tester.tap(find.byTooltip('Quét mã Tải app'));
    await tester.pumpAndSettle();

    expect(find.text('https://example.com/app'), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'quick-action-APP_DOWNLOAD',
    );
    expect(find.text('CP75 · Showroom 75'), findsOneWidget);
  });
}

class _FakeQuickActionsRepository extends QuickActionsRepository {
  _FakeQuickActionsRepository() : super(ApiClient());

  @override
  Future<List<QuickActionStore>> loadManagedStores() async => const [
    QuickActionStore(storeCode: 'CP75', storeName: 'Showroom 75'),
  ];

  @override
  Future<Map<String, String?>> loadAdminLinks(String storeCode) async => const {
    'APP_DOWNLOAD': null,
    'CHECK_IN': null,
    'ZALO_OA': null,
    'GOOGLE_MAP': null,
  };
}
