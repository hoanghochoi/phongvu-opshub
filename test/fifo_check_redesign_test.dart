import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:phongvu_opshub/app/theme/app_theme.dart';
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
    final semantics = tester.ensureSemantics();
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
    expect(find.text('SKU-12345'), findsOneWidget);
    expect(find.byTooltip('Quét mã'), findsOneWidget);
    expect(find.byTooltip('Tìm FIFO'), findsOneWidget);
    final fieldSemantics = tester.getSemantics(find.byType(EditableText));
    expect(fieldSemantics.label, startsWith('SKU hoặc serial'));
    expect(fieldSemantics.flagsCollection.isTextField, isTrue);
    expect(findsLegacyGradientHeader(), findsNothing);
    expect(find.byType(Scaffold), findsNothing);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('FIFO check keeps mobile scan and search beside input', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrapFifoCheck(_FakeFifoRepository()));

    final inputRect = tester.getRect(find.byType(TextField));
    final scanRect = tester.getRect(find.byTooltip('Quét mã'));
    final searchRect = tester.getRect(find.byTooltip('Tìm FIFO'));
    expect(scanRect.left, greaterThan(inputRect.right));
    expect(searchRect.left, greaterThan(scanRect.right));
    expect((scanRect.center.dy - inputRect.center.dy).abs(), lessThan(10));
    expect((searchRect.center.dy - inputRect.center.dy).abs(), lessThan(10));
    expect(tester.takeException(), isNull);
  });

  testWidgets('FIFO check follows approved 375 and web geometry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrapFifoCheck(_FakeFifoRepository(), contentWidth: 920),
    );

    final commandCard = tester.getRect(
      find.byKey(const Key('fifo-check-command-card')),
    );
    final resultPanel = tester.getRect(
      find.byKey(const Key('fifo-check-results')),
    );
    final inputRect = tester.getRect(find.byType(TextField));
    final scanRect = tester.getRect(find.byTooltip('Quét mã'));
    final searchRect = tester.getRect(find.byTooltip('Tìm FIFO'));

    expect(commandCard.width, 872);
    expect(commandCard.height, 172);
    expect(resultPanel.width, 872);
    expect(resultPanel.height, 340);
    expect((resultPanel.top - commandCard.bottom).abs(), 16);
    expect(inputRect.height, 48);
    expect(scanRect.size, const Size(48, 48));
    expect(searchRect.size, const Size(48, 48));
    expect(scanRect.left, greaterThan(inputRect.right));
    expect(searchRect.left, greaterThan(scanRect.right));
    expect(tester.takeException(), isNull);
  });

  testWidgets('FIFO command bar follows the R2 width and theme matrix', (
    tester,
  ) async {
    const cases = <(Size, double, double?)>[
      (Size(375, 812), 343, null),
      (Size(768, 900), 720, null),
      (Size(920, 900), 872, null),
      (Size(1200, 900), 1126, 1190),
    ];
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
      for (final (viewport, expectedWidth, contentWidth) in cases) {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          _wrapFifoCheck(
            _FakeFifoRepository(),
            contentWidth: contentWidth,
            themeMode: themeMode,
          ),
        );
        await tester.pumpAndSettle();

        final bar = tester.getRect(
          find.byKey(const Key('fifo-check-command-bar')),
        );
        final input = tester.getRect(find.byType(TextField));
        final scan = tester.getRect(find.byTooltip('Quét mã'));
        final search = tester.getRect(find.byTooltip('Tìm FIFO'));
        final toggle = tester.getRect(
          find.byKey(const Key('fifo-check-exported-toggle')),
        );
        expect(bar.width, expectedWidth);
        expect(bar.height, 108);
        expect(input.height, 48);
        expect(scan.size, const Size(48, 48));
        expect(search.size, const Size(48, 48));
        expect(scan.left, greaterThan(input.right));
        expect(search.left, greaterThan(scan.right));
        expect(toggle.top - bar.bottom, 16);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('FIFO serial correct follows approved mobile and web geometry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrapFifoCheck(_FakeFifoRepository()));
    await tester.enterText(find.byType(TextField), 'SN001');
    await tester.tap(find.byTooltip('Tìm FIFO'));
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byKey(const Key('fifo-check-results'))).size,
      const Size(343, 318),
    );
    expect(
      tester
          .getRect(find.byKey(const ValueKey('fifo-copy-serial-fifo-1')))
          .height,
      48,
    );
    expect(
      tester
          .getRect(find.byKey(const ValueKey('fifo-copy-location-fifo-1')))
          .height,
      48,
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('fifo-export-control'))).height,
      40,
    );

    tester.view.physicalSize = const Size(1024, 900);
    await tester.pumpWidget(
      _wrapFifoCheck(_FakeFifoRepository(), contentWidth: 920),
    );
    await tester.enterText(find.byType(TextField), 'SN001');
    await tester.tap(find.byTooltip('Tìm FIFO'));
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byKey(const Key('fifo-check-results'))).size,
      const Size(872, 248),
    );
    expect(
      tester
          .getRect(find.byKey(const ValueKey('fifo-copy-location-fifo-1')))
          .height,
      40,
    );
    expect(find.textContaining('Hàng bán mới tại kho'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FIFO provider loading maps to the canonical command state', (
    tester,
  ) async {
    final completer = Completer<FifoCheckResult>();
    await tester.pumpWidget(
      _wrapFifoCheck(_FakeFifoRepository(checkCompleter: completer)),
    );
    await tester.enterText(find.byType(TextField), 'SN001');
    await tester.tap(find.byTooltip('Tìm FIFO'));
    await tester.pump();

    final commandBar = find.byKey(const Key('fifo-check-command-bar'));
    expect(
      find.descendant(
        of: commandBar,
        matching: find.byIcon(PhosphorIconsRegular.spinnerGap),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: commandBar,
        matching: find.byIcon(PhosphorIconsRegular.magnifyingGlass),
      ),
      findsNothing,
    );
    expect(find.byTooltip('Đang tìm kiếm'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);

    completer.complete(
      FifoCheckResult(
        mode: 'serial',
        query: 'SN001',
        srCode: 'SR01',
        includeExported: false,
        status: 'correct',
        message: 'Đúng FIFO. Lấy sản phẩm này.',
        items: const [],
        item: _fifoItem,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Tìm FIFO'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
  });

  testWidgets(
    'FIFO serial wrong-order result follows approved status geometry',
    (tester) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrapFifoCheck(_FakeFifoRepository(status: 'wrong')),
      );
      await tester.enterText(find.byType(TextField), 'SN001');
      await tester.tap(find.byTooltip('Tìm FIFO'));
      await tester.pumpAndSettle();

      expect(find.text('Sai FIFO'), findsOneWidget);
      expect(find.text('Chuột Logitech B100'), findsOneWidget);
      expect(
        tester
            .getRect(find.byKey(const ValueKey('fifo-copy-serial-fifo-1')))
            .height,
        48,
      );
      expect(
        tester
            .getRect(find.byKey(const ValueKey('fifo-copy-location-fifo-1')))
            .height,
        48,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('FIFO R2 serial card matches approved mobile pill geometry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrapFifoCheck(_FakeFifoRepository(status: 'wrong')),
    );
    await tester.enterText(find.byType(TextField), 'SN001');
    await tester.tap(find.byTooltip('Tìm FIFO'));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const Key('fifo-check-results'))),
      const Size(343, 318),
    );
    final title = tester.getRect(
      find.byKey(const Key('fifo-mobile-product-title')),
    );
    final status = tester.getRect(
      find.byKey(const Key('fifo-mobile-status-pill')),
    );
    final metadata = tester.getRect(
      find.byKey(const Key('fifo-mobile-metadata-rows')),
    );
    final serial = tester.getRect(
      find.byKey(const ValueKey('fifo-copy-serial-fifo-1')),
    );
    final sku = tester.getRect(
      find.byKey(const ValueKey('fifo-copy-sku-fifo-1')),
    );
    final importDate = tester.getRect(
      find.byKey(const Key('fifo-import-date-pill')),
    );
    final age = tester.getRect(find.byKey(const Key('fifo-age-pill')));
    final location = tester.getRect(
      find.byKey(const ValueKey('fifo-copy-location-fifo-1')),
    );
    final binType = tester.getRect(find.byKey(const Key('fifo-bin-type-pill')));
    expect(status.left, title.left);
    expect(status.top, title.bottom + 4);
    expect(status.height, 30);
    expect(status.width, lessThan(metadata.width));
    expect(metadata.width, 304);
    expect(serial.width, lessThan(metadata.width));
    expect(sku.width, lessThan(metadata.width));
    expect(importDate.width, lessThan(metadata.width));
    expect(age.width, lessThan(metadata.width));
    expect(location.width, lessThan(metadata.width));
    expect(binType.width, lessThan(metadata.width));
    expect(
      {
        serial.top,
        sku.top,
        importDate.top,
        age.top,
        location.top,
        binType.top,
      }.length,
      greaterThan(1),
    );
    expect(find.text('Sai FIFO'), findsOneWidget);
    expect(find.text('Có lỗi'), findsNothing);
    expect(find.text('Hàng bán mới tại kho'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FIFO R2 serial card matches approved desktop geometry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrapFifoCheck(_FakeFifoRepository(status: 'wrong'), contentWidth: 1190),
    );
    await tester.enterText(find.byType(TextField), 'SN001');
    await tester.tap(find.byTooltip('Tìm FIFO'));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const Key('fifo-check-results'))),
      const Size(1126, 248),
    );
    expect(
      tester.getSize(find.byKey(const Key('fifo-desktop-metadata-wrap'))),
      const Size(1072, 92),
    );
    final card = tester.getRect(
      find.byKey(const Key('fifo-serial-result-card')),
    );
    final metadata = tester.getRect(
      find.byKey(const Key('fifo-desktop-metadata-wrap')),
    );
    final serial = tester.getRect(
      find.byKey(const ValueKey('fifo-copy-serial-fifo-1')),
    );
    final sku = tester.getRect(
      find.byKey(const ValueKey('fifo-copy-sku-fifo-1')),
    );
    final location = tester.getRect(
      find.byKey(const ValueKey('fifo-copy-location-fifo-1')),
    );
    final export = tester.getRect(
      find.byKey(const ValueKey('fifo-export-control')),
    );
    expect(metadata.left, closeTo(card.left + 32, 1));
    expect(metadata.right, closeTo(card.right - 24, 1));
    expect(serial.height, 40);
    expect(sku.height, 40);
    expect(location.height, 40);
    expect(serial.top, metadata.top);
    expect(sku.top, metadata.top);
    expect(location.top, anyOf(metadata.top, metadata.top + 52));
    expect(export.top, metadata.bottom + 16);
    expect(export.bottom, lessThanOrEqualTo(card.bottom - 24));
    expect(find.text('Sai FIFO'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FIFO serial exported and display-reserved states keep actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrapFifoCheck(_FakeFifoRepository(status: 'exported')),
    );
    await tester.enterText(find.byType(TextField), 'SN001');
    await tester.tap(find.byTooltip('Tìm FIFO'));
    await tester.pumpAndSettle();
    expect(find.text('Đã xuất kho'), findsOneWidget);
    expect(find.text('Bỏ đánh dấu xuất kho'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      _wrapFifoCheck(_FakeFifoRepository(status: 'display_reserved')),
    );
    await tester.enterText(find.byType(TextField), 'SN001');
    await tester.tap(find.byTooltip('Tìm FIFO'));
    await tester.pumpAndSettle();
    expect(find.text('Hàng trưng bày chỉ định'), findsOneWidget);
    expect(find.text('Hàng bán mới tại kho'), findsOneWidget);
    expect(find.text('Đánh dấu xuất kho'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FIFO serial not-found state uses the approved empty panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrapFifoCheck(_FakeFifoRepository(status: 'not_found')),
    );
    await tester.enterText(find.byType(TextField), 'SN404');
    await tester.tap(find.byTooltip('Tìm FIFO'));
    await tester.pumpAndSettle();

    expect(find.text('Không tìm thấy kết quả'), findsOneWidget);
    expect(find.textContaining('Hãy đổi từ khóa'), findsOneWidget);
    expect(find.byKey(const ValueKey('fifo-copy-serial-fifo-1')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FIFO SKU loaded result keeps approved item geometry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrapFifoCheck(_FakeFifoRepository(skuMode: true)));
    await tester.enterText(find.byType(TextField), 'SKU123');
    await tester.tap(find.byTooltip('Tìm FIFO'));
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byKey(const Key('fifo-check-results'))).size,
      const Size(343, 340),
    );
    expect(
      tester
          .getRect(find.byKey(const ValueKey('fifo-compact-item-sku-1')))
          .size,
      const Size(309, 154),
    );
    expect(find.text('SKU123 • Q3-001 • 3 sản phẩm'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('fifo-compact-item-sku-3')),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .getRect(find.byKey(const ValueKey('fifo-compact-item-sku-3')))
          .size,
      const Size(309, 164),
    );
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
    expect(find.text('Đúng FIFO'), findsOneWidget);
    expect(find.text('Chuột Logitech B100'), findsOneWidget);
    expect(find.text('SN001'), findsWidgets);
    expect(find.text('LK.04-A-03-a'), findsOneWidget);
    expect(find.textContaining('Tồn '), findsOneWidget);
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

      expect(
        find.byKey(const Key('fifo-check-recent-searches')),
        findsOneWidget,
      );

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
      expect(find.text('Đúng FIFO'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _wrapFifoCheck(
  _FakeFifoRepository repository, {
  double? contentWidth,
  ThemeMode themeMode = ThemeMode.light,
}) {
  return ChangeNotifierProvider<FifoProvider>(
    create: (_) => FifoProvider(repository),
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: contentWidth == null
          ? const FifoCheckScreen()
          : Center(
              child: SizedBox(
                width: contentWidth,
                child: const FifoCheckScreen(),
              ),
            ),
    ),
  );
}

class _FakeFifoRepository extends FifoRepository {
  _FakeFifoRepository({
    this.skuMode = false,
    this.status = 'correct',
    this.checkCompleter,
  }) : super(ApiClient());

  final bool skuMode;
  final String status;
  final Completer<FifoCheckResult>? checkCompleter;

  String? lastText;
  bool? lastIncludeExported;

  @override
  Future<FifoCheckResult> check({
    required String text,
    required bool includeExported,
  }) async {
    lastText = text;
    lastIncludeExported = includeExported;

    if (checkCompleter != null) return checkCompleter!.future;

    if (skuMode) {
      return FifoCheckResult(
        mode: 'sku',
        query: text,
        srCode: 'Q3-001',
        includeExported: includeExported,
        items: const [_skuItem1, _skuItem2, _skuItem3],
      );
    }

    return FifoCheckResult(
      mode: 'serial',
      query: text,
      srCode: 'SR01',
      includeExported: includeExported,
      status: status,
      message: switch (status) {
        'wrong' => 'Sai FIFO',
        'exported' => 'Đã xuất kho',
        'display_reserved' => 'Hàng trưng bày chỉ định',
        'not_found' => 'Không tìm thấy',
        _ => 'Đúng FIFO. Lấy sản phẩm này.',
      },
      items: const [],
      item: status == 'not_found'
          ? null
          : status == 'exported'
          ? _exportedFifoItem
          : _fifoItem,
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
  binType: 'Hàng bán mới tại kho',
  importDate: '2026-07-01',
  count: 1,
  exported: false,
  isFifo: true,
);

const _exportedFifoItem = FifoInventoryItem(
  id: 'fifo-1',
  srCode: 'SR01',
  sku: '250403171',
  skuName: 'Chuột Logitech B100',
  serialNumber: 'SN001',
  bin: 'LK.04-A-03-a',
  zone: 'A1',
  importDate: '2026-07-01',
  count: 1,
  exported: true,
  isFifo: false,
);

const _skuItem1 = FifoInventoryItem(
  id: 'sku-1',
  srCode: 'Q3-001',
  sku: 'SKU123',
  skuName: 'Laptop Pro 14',
  serialNumber: 'SN-001238',
  bin: 'BIN-A12',
  zone: 'Q3-001',
  importDate: '2026-05-12',
  count: 1,
  exported: false,
  isFifo: true,
);

const _skuItem2 = FifoInventoryItem(
  id: 'sku-2',
  srCode: 'Q3-001',
  sku: 'SKU123',
  skuName: 'Chuột không dây',
  serialNumber: 'SN-001491',
  bin: 'BIN-A18',
  zone: 'Q3-001',
  importDate: '2026-05-28',
  count: 1,
  exported: true,
  isFifo: false,
);

const _skuItem3 = FifoInventoryItem(
  id: 'sku-3',
  srCode: 'Q3-001',
  sku: 'SKU123',
  skuName: 'Màn hình 24 inch',
  serialNumber: 'SN-001880',
  bin: 'BIN-B02',
  zone: 'Q3-001',
  importDate: '2026-06-04',
  count: 1,
  exported: false,
  isFifo: true,
);

final _recentSearchStorageKey = AppStorageKeys.shared(
  'fifo_check_recent_searches',
);
