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

  testWidgets('390px keeps order input and primary action in one row', (
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
    await provider.lookupOrder('SO-390');

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
    expect(row, findsOneWidget);
    expect(input, findsOneWidget);
    expect(button, findsOneWidget);
    expect(find.descendant(of: row, matching: input), findsOneWidget);
    expect(find.descendant(of: row, matching: button), findsOneWidget);
    expect(
      (tester.getCenter(input).dy - tester.getCenter(button).dy).abs(),
      lessThan(8),
    );
    expect(
      find.byKey(const ValueKey('contract-appendix-item-1:250902982')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('app-two-axis-horizontal-scrollbar')),
      findsOneWidget,
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

    final editor = find.byKey(const Key('contract-appendix-desktop-editor'));
    final preview = find.byKey(const Key('contract-appendix-preview-card'));
    final table = find.byKey(const Key('contract-appendix-preview-table'));
    final amount = find.byKey(const Key('contract-appendix-amount-in-words'));
    expect(editor, findsOneWidget);
    expect(preview, findsOneWidget);
    expect(
      tester.getTopLeft(preview).dy,
      greaterThan(tester.getBottomLeft(editor).dy),
    );
    expect(
      tester.getTopLeft(amount).dy,
      greaterThan(tester.getBottomLeft(table).dy),
    );
    expect(
      tester.getSize(editor).width,
      closeTo(tester.getSize(preview).width, 1),
    );
    expect(tester.getSize(table).width, closeTo(960, 1));
    expect(tester.takeException(), isNull);
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
  @override
  Future<ContractAppendixDocument> preview({
    required String orderCode,
    List<Map<String, dynamic>> overrides = const [],
  }) async {
    return ContractAppendixDocument(
      id: null,
      orderCode: orderCode,
      quoteVersion: 'quote-layout',
      terminalCode: '49180_PRICE_0001',
      sourceOrderFetchedAt: DateTime.utc(2026, 7, 17),
      items: [
        ContractAppendixItem(
          position: 1,
          sourceLineKey: '1:250902982',
          sku: '250902982',
          sellerSku: '250902982',
          productName: 'Laptop dùng kiểm thử giao diện mobile',
          quantity: 2,
          unit: 'Cái',
          finalSellPrice: 21576187,
          vatRateBps: 800,
          taxCode: 'VAT8',
          taxLabel: 'Thuế GTGT 8%',
          taxSource: 'ERP_PPM',
          taxFetchedAt: DateTime.utc(2026, 7, 17),
          unitPriceBeforeVat: 19977951,
          lineBeforeVat: 39955902,
          lineVatAmount: 3196472,
          lineAfterVat: 43152374,
        ),
      ],
      totalBeforeVat: 39955902,
      totalVatAmount: 3196472,
      totalAfterVat: 43152374,
      amountInWords:
          'Bốn mươi ba triệu một trăm năm mươi hai nghìn ba trăm '
          'bảy mươi bốn đồng chẵn.',
      manualTaxItemCount: 0,
      unresolvedTaxCount: 0,
      canSave: true,
      createdAt: null,
      expiresAt: null,
    );
  }

  @override
  Future<ContractAppendixDocument> save({
    required String orderCode,
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
