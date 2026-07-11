import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/legacy_widget_finders.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/utils/date_formatter.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/sort/data/repositories/sort_repository.dart';
import 'package:phongvu_opshub/features/sort/presentation/providers/sort_provider.dart';
import 'package:phongvu_opshub/features/sort/presentation/screens/sort_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  String? copiedText;

  setUp(() {
    copiedText = null;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    AppLogger.instance.setUploadsEnabledForTesting(false);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText =
                (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  testWidgets('Sort FIFO renders content-only empty state', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrapSortScreen(_FakeSortRepository()));

    expect(find.byKey(const Key('sort-fifo-header')), findsNothing);
    expect(find.byKey(const Key('sort-fifo-command-card')), findsOneWidget);
    expect(find.text('Sắp xếp FIFO'), findsNothing);
    expect(find.text('Chưa có kết quả sắp xếp'), findsOneWidget);
    expect(find.byTooltip('Quét mã'), findsOneWidget);
    expect(find.byTooltip('Tìm hàng để sắp xếp'), findsOneWidget);
    expect(findsLegacyGradientHeader(), findsNothing);
    expect(find.byType(Scaffold), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sort FIFO keeps mobile scan and search beside input', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrapSortScreen(_FakeSortRepository()));

    final inputRect = tester.getRect(find.byType(TextField));
    final scanRect = tester.getRect(find.byTooltip('Quét mã'));
    final searchRect = tester.getRect(find.byTooltip('Tìm hàng để sắp xếp'));

    expect(scanRect.left, greaterThan(inputRect.right));
    expect(searchRect.left, greaterThan(scanRect.right));
    expect((scanRect.center.dy - inputRect.center.dy).abs(), lessThan(10));
    expect((searchRect.center.dy - inputRect.center.dy).abs(), lessThan(10));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sort FIFO submits SKU and renders grouped results', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeSortRepository();

    await tester.pumpWidget(_wrapSortScreen(repository));

    await tester.enterText(find.byType(TextField), '250403171');
    await tester.tap(find.byTooltip('Tìm hàng để sắp xếp'));
    await tester.pumpAndSettle();

    expect(repository.lastText, '250403171');
    expect(find.byKey(const Key('sort-fifo-results')), findsOneWidget);
    expect(find.textContaining('Kết quả sắp xếp'), findsOneWidget);
    expect(find.text('1 nhóm'), findsOneWidget);
    expect(find.text('SKU: 250403171'), findsOneWidget);
    expect(find.text('Chuột Logitech B100'), findsWidgets);
    expect(find.text('SN001'), findsOneWidget);
    expect(find.text('LK.04-A-03-a'), findsOneWidget);
    expect(
      find.text(DateFormatter.inventoryAgeLabel('2026-07-01')!),
      findsOneWidget,
    );
    expect(find.text('Đánh dấu đã xếp'), findsOneWidget);
    expect(find.byTooltip('Sao chép serial'), findsOneWidget);
    expect(find.byTooltip('Sao chép vị trí'), findsOneWidget);
    expect(find.textContaining('LK.04-A-03-a'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Sao chép serial'));
    await tester.pump(const Duration(milliseconds: 250));

    expect(copiedText, 'SN001');
    expect(find.text('Đã sao chép serial.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _wrapSortScreen(_FakeSortRepository repository) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(AuthRepository(ApiClient())),
      ),
      ChangeNotifierProvider<SortProvider>(
        create: (_) => SortProvider(repository),
      ),
    ],
    child: const MaterialApp(home: SortScreen()),
  );
}

class _FakeSortRepository extends SortRepository {
  _FakeSortRepository() : super(ApiClient());

  String? lastText;
  String? lastUser;

  @override
  Future<String> sendSortRequest(String text, String user) async {
    lastText = text;
    lastUser = user;
    return [
      'SKU: 250403171',
      'Tên: Chuột Logitech B100',
      'Serial: SN001',
      'Mã BIN: LK.04-A-03-a',
      'Zone: A1',
      'Ngày nhập: 2026-07-01',
    ].join('\n');
  }

  @override
  Future<void> sendCompletionReport({
    required String user,
    required List<Map<String, dynamic>> sortedSKUs,
  }) async {}
}
