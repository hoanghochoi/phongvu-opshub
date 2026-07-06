import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/legacy_widget_finders.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/storage/app_storage_keys.dart';
import 'package:phongvu_opshub/features/fifo/data/repositories/fifo_repository.dart';
import 'package:phongvu_opshub/features/fifo/domain/entities/fifo_check_result.dart';
import 'package:phongvu_opshub/features/fifo/domain/entities/fifo_inventory_item.dart';
import 'package:phongvu_opshub/features/fifo/presentation/providers/fifo_provider.dart';
import 'package:phongvu_opshub/features/fifo/presentation/screens/fifo_check_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  String? copiedText;

  setUp(() {
    copiedText = null;
    SharedPreferences.setMockInitialValues({});
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

  testWidgets('FIFO check renders content-only empty state', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrapFifoCheck(_FakeFifoRepository()));

    expect(find.byKey(const Key('fifo-check-header')), findsNothing);
    expect(find.byKey(const Key('fifo-check-command-card')), findsOneWidget);
    expect(find.byKey(const Key('fifo-check-results')), findsOneWidget);
    expect(find.text('Kiểm tra FIFO'), findsNothing);
    expect(find.text('Chưa kiểm tra'), findsNothing);
    expect(find.text('0 sản phẩm'), findsNothing);
    expect(find.text('Chỉ còn tồn'), findsNothing);
    expect(find.text('Hiển thị đã xuất kho'), findsOneWidget);
    expect(find.text('Nhập SKU hoặc serial để kiểm tra FIFO'), findsOneWidget);
    expect(find.byTooltip('Quét mã'), findsOneWidget);
    expect(find.byTooltip('Tìm FIFO'), findsOneWidget);
    expect(findsLegacyGradientHeader(), findsNothing);
    expect(find.byType(Scaffold), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FIFO check submits serial and renders runtime result', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeFifoRepository();

    await tester.pumpWidget(_wrapFifoCheck(repository));

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'SN001');
    await tester.tap(find.byTooltip('Tìm FIFO'));
    await tester.pumpAndSettle();

    expect(repository.lastText, 'SN001');
    expect(repository.lastIncludeExported, isTrue);
    expect(find.text('Đúng FIFO. Lấy sản phẩm này.'), findsOneWidget);
    expect(find.text('Chuột Logitech B100'), findsOneWidget);
    expect(find.text('SN001'), findsWidgets);
    expect(find.text('250403171'), findsOneWidget);
    expect(find.text('LK.04-A-03-a'), findsOneWidget);
    expect(find.text('Đánh dấu xuất kho'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FIFO result copies serial and location by click or touch', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrapFifoCheck(_FakeFifoRepository()));
    await tester.enterText(find.byType(TextField), 'SN001');
    await tester.tap(find.byTooltip('Tìm FIFO'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Sao chép serial'), findsOneWidget);
    expect(find.byTooltip('Sao chép vị trí'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final serialChip = find.byKey(const ValueKey('fifo-copy-serial-fifo-1'));
    await tester.ensureVisible(serialChip);
    await tester.tap(serialChip);
    await tester.pump(const Duration(milliseconds: 250));

    expect(copiedText, 'SN001');
    expect(find.text('Đã sao chép serial.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final locationChip = find.byKey(
      const ValueKey('fifo-copy-location-fifo-1'),
    );
    await tester.ensureVisible(locationChip);
    await tester.tap(locationChip);
    await tester.pump(const Duration(milliseconds: 250));

    expect(copiedText, 'LK.04-A-03-a');
    expect(find.text('Đã sao chép vị trí.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'FIFO check shows and reorders recent searches from local cache',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({
        _recentSearchStorageKey: [
          'sn-old',
          '250403171',
          'SN001',
          'SN002',
          'SN003',
          'SN004',
        ],
      });
      final repository = _FakeFifoRepository();

      await tester.pumpWidget(_wrapFifoCheck(repository));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('fifo-check-recent-searches')), findsNothing);

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('fifo-check-recent-searches')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('fifo-check-recent-SN-OLD')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('fifo-check-recent-SN004')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('fifo-check-recent-250403171')),
      );
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();

      expect(repository.lastText, '250403171');
      expect(prefs.getStringList(_recentSearchStorageKey), [
        '250403171',
        'SN-OLD',
        'SN001',
        'SN002',
        'SN003',
      ]);
      expect(find.text('Đúng FIFO. Lấy sản phẩm này.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _wrapFifoCheck(_FakeFifoRepository repository) {
  return ChangeNotifierProvider<FifoProvider>(
    create: (_) => FifoProvider(repository),
    child: const MaterialApp(home: FifoCheckScreen()),
  );
}

class _FakeFifoRepository extends FifoRepository {
  _FakeFifoRepository() : super(ApiClient());

  String? lastText;
  bool? lastIncludeExported;

  @override
  Future<FifoCheckResult> check({
    required String text,
    required bool includeExported,
  }) async {
    lastText = text;
    lastIncludeExported = includeExported;

    return FifoCheckResult(
      mode: 'serial',
      query: text,
      srCode: 'SR01',
      includeExported: includeExported,
      status: 'correct',
      message: 'Đúng FIFO. Lấy sản phẩm này.',
      items: const [],
      item: _fifoItem,
    );
  }

  @override
  Future<FifoInventoryItem> setExported({
    required String inventoryId,
    required bool exported,
  }) async {
    return FifoInventoryItem(
      id: inventoryId,
      srCode: _fifoItem.srCode,
      sku: _fifoItem.sku,
      skuName: _fifoItem.skuName,
      serialNumber: _fifoItem.serialNumber,
      bin: _fifoItem.bin,
      zone: _fifoItem.zone,
      importDate: _fifoItem.importDate,
      count: _fifoItem.count,
      exported: exported,
      isFifo: _fifoItem.isFifo,
    );
  }
}

const _fifoItem = FifoInventoryItem(
  id: 'fifo-1',
  srCode: 'SR01',
  sku: '250403171',
  skuName: 'Chuột Logitech B100',
  serialNumber: 'SN001',
  bin: 'LK.04-A-03-a',
  zone: 'A1',
  importDate: '2026-07-01',
  count: 1,
  exported: false,
  isFifo: true,
);

final _recentSearchStorageKey = AppStorageKeys.shared(
  'fifo_check_recent_searches',
);
