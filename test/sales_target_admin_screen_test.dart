import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/admin/data/repositories/sales_target_repository.dart';
import 'package:phongvu_opshub/features/admin/presentation/screens/sales_target_admin_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => AppLogger.instance.setUploadsEnabledForTesting(false));
  tearDown(() => AppLogger.instance.setUploadsEnabledForTesting(true));

  test('sales target item parses numeric and string target values', () {
    expect(
      SalesTargetItem.fromJson({
        'organizationNodeId': 'node-cp01',
        'storeCode': 'CP01',
        'storeName': 'Phong Vũ Quận 1',
        'targetBeforeTax': '320000000',
      }).targetBeforeTax,
      320000000,
    );
  });

  testWidgets('sales target screen loads scoped SR rows and saves changes', (
    tester,
  ) async {
    final repository = _FakeSalesTargetRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SalesTargetAdminScreen(repository: repository)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Quản lý doanh số'), findsOneWidget);
    expect(find.text('CP01 • Phong Vũ Quận 1'), findsOneWidget);
    expect(find.text('300.000.000'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '320000000');
    await tester.tap(find.text('Lưu chỉ tiêu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(repository.savedValues?['node-cp01'], 320000000);
    expect(find.text('Đã lưu chỉ tiêu doanh số.'), findsOneWidget);
  });
}

class _FakeSalesTargetRepository extends SalesTargetRepository {
  _FakeSalesTargetRepository() : super(ApiClient());

  Map<String, int?>? savedValues;

  @override
  Future<List<SalesTargetItem>> fetchTargets(String month) async => const [
    SalesTargetItem(
      organizationNodeId: 'node-cp01',
      storeCode: 'CP01',
      storeName: 'Phong Vũ Quận 1',
      targetBeforeTax: 300000000,
    ),
  ];

  @override
  Future<List<SalesTargetItem>> saveTargets(
    String month,
    Map<String, int?> targets,
  ) async {
    savedValues = Map.of(targets);
    return [
      SalesTargetItem(
        organizationNodeId: 'node-cp01',
        storeCode: 'CP01',
        storeName: 'Phong Vũ Quận 1',
        targetBeforeTax: targets['node-cp01'],
      ),
    ];
  }
}
