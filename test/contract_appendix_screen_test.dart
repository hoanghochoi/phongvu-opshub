import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/navigation/app_nav_model.dart';
import 'package:phongvu_opshub/app/navigation/app_router.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/contract_appendix/data/contract_appendix_clipboard.dart';
import 'package:phongvu_opshub/features/contract_appendix/data/contract_appendix_repository.dart';
import 'package:phongvu_opshub/features/contract_appendix/domain/contract_appendix.dart';
import 'package:phongvu_opshub/features/contract_appendix/presentation/providers/contract_appendix_provider.dart';
import 'package:phongvu_opshub/features/contract_appendix/presentation/screens/contract_appendix_screen.dart';
import 'package:provider/provider.dart';

void main() {
  setUp(() => AppLogger.instance.setUploadsEnabledForTesting(false));
  tearDown(() => AppLogger.instance.setUploadsEnabledForTesting(true));

  testWidgets('390px keeps order input and add action in one row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final provider = ContractAppendixProvider(
      _ScreenDataSource(),
      clipboardWriter: _NoopClipboardWriter(),
    );
    expect(provider.addOrderCode('SO-390'), isTrue);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(
          home: Scaffold(body: ContractAppendixScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.byKey(const Key('contract-appendix-order-command-row'));
    final input = find.byKey(const Key('contract-appendix-order-input'));
    final button = find.byKey(const Key('contract-appendix-fetch-button'));
    expect(
      find.byKey(const Key('contract-appendix-workspace-header')),
      findsOneWidget,
    );
    expect(row, findsOneWidget);
    expect(input, findsOneWidget);
    final addButton = find.byKey(
      const Key('contract-appendix-add-order-button'),
    );
    expect(addButton, findsOneWidget);
    expect(button, findsOneWidget);
    expect(find.descendant(of: row, matching: input), findsOneWidget);
    expect(find.descendant(of: row, matching: addButton), findsOneWidget);
    expect(
      (tester.getCenter(input).dy - tester.getCenter(addButton).dy).abs(),
      lessThan(8),
    );
    expect(find.text('Lấy thông tin (1 đơn)'), findsOneWidget);
    expect(find.text('Tạo phụ lục hợp đồng'), findsNothing);
    expect(find.text('Đơn đã chọn  1/10'), findsNothing);
    expect(
      find.text('Bảng sẽ xuất hiện sau khi lấy thông tin'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected orders are managed from the summary card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final provider = ContractAppendixProvider(
      _ScreenDataSource(),
      clipboardWriter: _NoopClipboardWriter(),
    );
    expect(provider.addOrderCode('SO-SUMMARY'), isTrue);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(
          home: Scaffold(body: ContractAppendixScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('contract-appendix-order-summary-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('contract-appendix-order-summary-SO-SUMMARY')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('contract-appendix-order-chip-SO-SUMMARY')),
      findsNothing,
    );
    final remove = find.byTooltip('Xóa SO-SUMMARY');
    expect(remove, findsOneWidget);

    await tester.tap(remove);
    await tester.pumpAndSettle();

    expect(provider.selectedOrderCodes, isEmpty);
    expect(
      find.byKey(const Key('contract-appendix-order-summary-card')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected order chips fit their codes and wrap on desktop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final provider = ContractAppendixProvider(
      _ScreenDataSource(),
      clipboardWriter: _NoopClipboardWriter(),
    );
    for (final code in const [
      '26082030161170',
      '26081933596930',
      '26081934200750',
      '26082039574650',
      '26082039574651',
      '26082039574652',
      '26082039574653',
      '26082039574654',
      '26082039574655',
      '26082039574656',
    ]) {
      expect(provider.addOrderCode(code), isTrue);
    }

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(
          home: Scaffold(body: ContractAppendixScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final summary = find.byKey(
      const Key('contract-appendix-order-summary-card'),
    );
    const codes = [
      '26082030161170',
      '26081933596930',
      '26081934200750',
      '26082039574650',
      '26082039574651',
      '26082039574652',
      '26082039574653',
      '26082039574654',
      '26082039574655',
      '26082039574656',
    ];
    final chips = [
      for (final code in codes)
        find.byKey(ValueKey('contract-appendix-order-summary-$code')),
    ];
    expect(summary, findsOneWidget);
    final command = find.byKey(
      const Key('contract-appendix-order-command-row'),
    );
    expect(
      tester.getTopLeft(summary).dy,
      greaterThan(tester.getBottomLeft(command).dy),
    );
    for (var index = 0; index < chips.length; index++) {
      final chip = chips[index];
      expect(chip, findsOneWidget);
      expect(
        tester.getSize(chip).width,
        lessThan(tester.getSize(summary).width - 8),
      );
      final codeText = find.descendant(
        of: chip,
        matching: find.text(codes[index]),
      );
      expect(codeText, findsOneWidget);
      expect(
        tester.widget<Text>(codeText).overflow,
        isNot(TextOverflow.ellipsis),
      );
    }
    expect(
      tester.getTopLeft(chips[0]).dy,
      closeTo(tester.getTopLeft(chips[1]).dy, 0.1),
    );
    expect(
      tester.getTopLeft(chips[5]).dy,
      greaterThan(tester.getTopLeft(chips[0]).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide keeps the order summary below the command card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final provider = ContractAppendixProvider(
      _ScreenDataSource(),
      clipboardWriter: _NoopClipboardWriter(),
    );
    expect(provider.addOrderCode('SO-STABLE'), isTrue);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(
          home: Scaffold(body: ContractAppendixScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final command = find.byKey(
      const Key('contract-appendix-order-command-row'),
    );
    final summary = find.byKey(
      const Key('contract-appendix-order-summary-card'),
    );
    expect(summary, findsOneWidget);
    expect(
      tester.getTopLeft(summary).dy,
      greaterThan(tester.getBottomLeft(command).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop keeps editor and Word preview in one wide column', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final provider = ContractAppendixProvider(
      _ScreenDataSource(),
      clipboardWriter: _NoopClipboardWriter(),
    );
    await provider.lookupOrder('SO-DESKTOP');

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(
          home: Scaffold(body: ContractAppendixScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final preview = find.byKey(const Key('contract-appendix-preview-card'));
    final table = find.byKey(const Key('contract-appendix-preview-table'));
    final amount = find.byKey(const Key('contract-appendix-amount-in-words'));
    expect(preview, findsOneWidget);
    expect(table, findsOneWidget);
    expect(amount, findsOneWidget);
    expect(find.text('Mã hàng'), findsNothing);
    expect(find.text('Tổng cộng'), findsOneWidget);
    expect(find.text('Thuế GTGT'), findsOneWidget);
    expect(
      find.text('Bằng chữ: Mười lăm triệu năm trăm bảy mươi nghìn đồng chẵn.'),
      findsOneWidget,
    );
    expect(find.text('Thành tiền'), findsOneWidget);
    expect(find.text('15.570.000'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Word preview wraps and locks ERP name and unit cells', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(768, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const longName =
        'Máy tính xách tay Acer Aspire 7 A715 phiên bản hiệu năng cao '
        'màn hình 15.6 inch dành cho công việc và giải trí';
    final provider = ContractAppendixProvider(
      _ScreenDataSource(productName: longName),
      clipboardWriter: _NoopClipboardWriter(),
    );
    await provider.lookupOrder('SO-LOCKED');

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(
          home: Scaffold(body: ContractAppendixScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('Tên hàng hóa: $longName (đang khóa)'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Đơn vị tính: Bản (đang khóa)'),
      findsOneWidget,
    );
    expect(find.byTooltip('Xóa SO-LOCKED'), findsNothing);
    final name = find.text(longName);
    expect(name, findsOneWidget);
    expect(tester.getSize(name).height, greaterThan(20));
    final table = find.byKey(const Key('contract-appendix-preview-table'));
    expect(
      find.descendant(of: table, matching: find.byType(TextField)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('R2 geometry stays bounded at all approved viewports', (
    tester,
  ) async {
    final viewports = <Size>[
      const Size(390, 844),
      const Size(768, 1024),
      const Size(1024, 900),
      const Size(1440, 900),
    ];
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final viewport in viewports) {
      tester.view.physicalSize = viewport;
      final provider = ContractAppendixProvider(
        _ScreenDataSource(),
        clipboardWriter: _NoopClipboardWriter(),
      );
      await provider.lookupOrder('SO-R2');
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: const MaterialApp(
            home: Scaffold(body: ContractAppendixScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final input = find.byKey(const Key('contract-appendix-order-input'));
      final add = find.byKey(const Key('contract-appendix-add-order-button'));
      final fetch = find.byKey(const Key('contract-appendix-fetch-button'));
      expect(input, findsOneWidget);
      expect(add, findsOneWidget);
      expect(fetch, findsOneWidget);
      if (viewport.width < 600) {
        expect(
          (tester.getCenter(input).dy - tester.getCenter(add).dy).abs(),
          lessThan(8),
        );
        expect(
          tester.getTopLeft(fetch).dy,
          greaterThan(tester.getBottomLeft(input).dy),
        );
        expect(
          find.byKey(const ValueKey('contract-appendix-item-1:220909037')),
          findsOneWidget,
        );
      } else {
        expect(
          (tester.getCenter(input).dy - tester.getCenter(fetch).dy).abs(),
          lessThan(8),
        );
        expect(find.text('Mã hàng'), findsNothing);
        expect(find.text('Thành tiền'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    }
  });

  test('route and navigation fail closed without CONTRACT_APPENDIX', () {
    const allowed = User(
      email: 'allowed@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'store-1',
      featureAccess: {'CONTRACT_APPENDIX': true},
    );
    const denied = User(
      email: 'denied@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'store-1',
      featureAccess: {'SALES_REPORT': true},
    );

    expect(
      AppRouter.canUseRouteForTesting(allowed, '/contract-appendix'),
      isTrue,
    );
    expect(
      AppRouter.canUseRouteForTesting(denied, '/contract-appendix'),
      isFalse,
    );

    final destination = AppNavModel.destinations.singleWhere(
      (item) => item.id == 'contractAppendix',
    );
    expect(AppNavModel.canUseDestination(allowed, destination), isTrue);
    expect(AppNavModel.canUseDestination(denied, destination), isFalse);
    final salesIndex = AppNavModel.destinations.indexWhere(
      (item) => item.id == 'sales',
    );
    expect(AppNavModel.destinations[salesIndex + 1].id, 'contractAppendix');
  });
}

class _NoopClipboardWriter implements ContractAppendixClipboardWriter {
  @override
  Future<void> write(ContractAppendixDocument document) async {}
}

class _ScreenDataSource implements ContractAppendixDataSource {
  final String productName;

  _ScreenDataSource({
    this.productName = 'Phần mềm Microsoft Win Pro 11 64-bit',
  });

  @override
  Future<ContractAppendixDocument> preview({
    required List<String> orderCodes,
    List<Map<String, dynamic>> overrides = const [],
  }) async {
    return ContractAppendixDocument(
      id: null,
      orderCode: orderCodes.first,
      orderCodes: orderCodes,
      quoteVersion: 'quote-layout',
      terminalCode: '49180_PRICE_0001',
      sourceOrderFetchedAt: DateTime.utc(2026, 7, 17),
      items: [
        ContractAppendixItem(
          position: 1,
          sourceLineKey: '1:220909037',
          sku: '220909037',
          sellerSku: '220909037',
          productName: productName,
          quantity: 3,
          unit: 'Bản',
          finalSellPrice: 5190000,
          vatRateBps: 800,
          taxCode: 'VAT8',
          taxLabel: 'Thuế 8%',
          taxSource: 'ERP_PPM',
          taxFetchedAt: DateTime.utc(2026, 7, 17),
          unitPriceBeforeVat: 4805556,
          lineBeforeVat: 14416668,
          lineVatAmount: 1153332,
          lineAfterVat: 15570000,
        ),
      ],
      totalBeforeVat: 15570000,
      totalVatAmount: 0,
      totalAfterVat: 15570000,
      amountInWords: 'Mười lăm triệu năm trăm bảy mươi nghìn đồng chẵn.',
      manualTaxItemCount: 0,
      unresolvedTaxCount: 0,
      canSave: true,
      createdAt: null,
      expiresAt: null,
    );
  }

  @override
  Future<ContractAppendixDocument> save({
    required List<String> orderCodes,
    required String quoteVersion,
    required List<Map<String, dynamic>> overrides,
  }) => throw UnimplementedError();

  @override
  Future<ContractAppendixHistoryPage> list({
    required int page,
    required int limit,
    String? query,
  }) => throw UnimplementedError();

  @override
  Future<ContractAppendixDocument> detail(String id) =>
      throw UnimplementedError();
}
