import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/features/contract_appendix/data/contract_appendix_clipboard.dart';
import 'package:phongvu_opshub/features/contract_appendix/data/contract_appendix_repository.dart';
import 'package:phongvu_opshub/features/contract_appendix/domain/contract_appendix.dart';
import 'package:phongvu_opshub/features/contract_appendix/presentation/providers/contract_appendix_provider.dart';

void main() {
  setUp(() => AppLogger.instance.setUploadsEnabledForTesting(false));
  tearDown(() => AppLogger.instance.setUploadsEnabledForTesting(true));

  group('ContractAppendixDocument', () {
    test('parses unresolved preview with nullable calculated money', () {
      final document = ContractAppendixDocument.fromJson({
        'orderCode': 'SO-1',
        'quoteVersion': 'quote-1',
        'terminalCode': '49180_PRICE_0001',
        'items': [
          {
            'position': 1,
            'sourceLineKey': '1:250902982',
            'sku': '250902982',
            'productName': 'Laptop',
            'quantity': 2,
            'unit': 'Cái',
            'finalSellPrice': 21576187,
            'vatRateBps': null,
            'taxSource': 'MISSING',
            'unitPriceBeforeVat': null,
            'lineBeforeVat': null,
            'lineVatAmount': null,
            'lineAfterVat': 43152374,
          },
        ],
        'totalBeforeVat': null,
        'totalVatAmount': null,
        'totalAfterVat': null,
        'amountInWords': null,
        'manualTaxItemCount': 0,
        'unresolvedTaxCount': 1,
        'canSave': false,
      });

      expect(document.totalBeforeVat, isNull);
      expect(document.items.single.lineAfterVat, 43152374);
      expect(document.items.single.isTaxMissing, isTrue);
      expect(document.canSave, isFalse);
    });
  });

  group('Contract appendix clipboard payload', () {
    test('builds escaped 7-column HTML and TSV with totals', () {
      final payload = buildContractAppendixClipboardPayload(
        _document(
          saved: true,
          productName: 'Laptop <Pro> & "Office"\nDòng 2',
          unit: 'Cái\tchiếc',
        ),
      );

      expect(RegExp('<th ').allMatches(payload.html), hasLength(7));
      expect(payload.html, contains('Thành tiền (VNĐ)<br>Chưa VAT'));
      expect(
        payload.html,
        contains('Laptop &lt;Pro&gt; &amp; &quot;Office&quot;'),
      );
      expect(payload.html, isNot(contains('Laptop <Pro>')));
      expect(payload.html, contains('Tổng giá trị hợp đồng'));
      expect(payload.html, contains('Bằng chữ: Năm mươi lăm triệu'));

      final lines = payload.plainText.split('\n');
      expect(lines.first.split('\t'), hasLength(7));
      expect(lines[1].split('\t'), hasLength(7));
      expect(lines[1], contains('Laptop <Pro> & "Office" Dòng 2'));
      expect(lines[1], contains('Cái chiếc'));
      expect(payload.plainText, contains('Thuế GTGT'));
    });

    test('rejects preview that has not been saved', () {
      expect(
        () => buildContractAppendixClipboardPayload(_document()),
        throwsStateError,
      );
    });
  });

  group('ContractAppendixProvider', () {
    test('dirty edit refreshes and saves before copy is enabled', () async {
      final dataSource = _FakeDataSource();
      final writer = _FakeClipboardWriter();
      final provider = ContractAppendixProvider(
        dataSource,
        clipboardWriter: writer,
      );

      expect(await provider.lookupOrder(' SO-1 '), isTrue);
      expect(provider.canCopy, isFalse);

      provider.updateProductName('1:250902982', 'Tên hợp đồng');
      expect(provider.isDirty, isTrue);
      expect(provider.canCopy, isFalse);

      expect(await provider.saveCurrent(), isTrue);
      expect(dataSource.previewCalls, 2);
      expect(dataSource.saveCalls, 1);
      expect(provider.saved?.items.single.productName, 'Tên hợp đồng');
      expect(provider.canCopy, isTrue);

      provider.updateUnit('1:250902982', 'Bộ');
      expect(provider.isDirty, isTrue);
      expect(provider.canCopy, isFalse);
    });

    test(
      'starts clipboard writer synchronously and makes no API call',
      () async {
        final dataSource = _FakeDataSource();
        final writer = _FakeClipboardWriter(block: true);
        final provider = ContractAppendixProvider(
          dataSource,
          clipboardWriter: writer,
        );
        await provider.lookupOrder('SO-1');
        await provider.saveCurrent();
        final previewCalls = dataSource.previewCalls;
        final saveCalls = dataSource.saveCalls;
        final listCalls = dataSource.listCalls;
        final detailCalls = dataSource.detailCalls;

        final copyFuture = provider.copySaved();
        expect(writer.invoked, isTrue);
        expect(dataSource.previewCalls, previewCalls);
        expect(dataSource.saveCalls, saveCalls);
        expect(dataSource.listCalls, listCalls);
        expect(dataSource.detailCalls, detailCalls);

        writer.complete();
        expect(await copyFuture, isTrue);
      },
    );

    test('loads history and immutable detail', () async {
      final dataSource = _FakeDataSource();
      final provider = ContractAppendixProvider(
        dataSource,
        clipboardWriter: _FakeClipboardWriter(),
      );

      expect(await provider.loadHistory(query: 'SO', page: 0), isTrue);
      expect(provider.history, hasLength(1));
      expect(provider.historyTotal, 1);
      expect(await provider.openHistoryDetail('appendix-1'), isTrue);
      expect(provider.historyDetail?.isFinalized, isTrue);
    });
  });
}

class _FakeClipboardWriter implements ContractAppendixClipboardWriter {
  final bool block;
  bool invoked = false;
  Completer<void>? _completer;

  _FakeClipboardWriter({this.block = false});

  @override
  Future<void> write(ContractAppendixDocument document) {
    invoked = true;
    if (!block) return Future<void>.value();
    _completer = Completer<void>();
    return _completer!.future;
  }

  void complete() => _completer?.complete();
}

class _FakeDataSource implements ContractAppendixDataSource {
  int previewCalls = 0;
  int saveCalls = 0;
  int listCalls = 0;
  int detailCalls = 0;

  @override
  Future<ContractAppendixDocument> preview({
    required String orderCode,
    List<Map<String, dynamic>> overrides = const [],
  }) async {
    previewCalls++;
    final name = overrides.isEmpty
        ? 'Laptop ERP'
        : overrides.single['productName'] as String;
    final unit = overrides.isEmpty ? 'Cái' : overrides.single['unit'] as String;
    return _document(
      quoteVersion: 'quote-$previewCalls',
      productName: name,
      unit: unit,
    );
  }

  @override
  Future<ContractAppendixDocument> save({
    required String orderCode,
    required String quoteVersion,
    required List<Map<String, dynamic>> overrides,
  }) async {
    saveCalls++;
    return _document(
      saved: true,
      quoteVersion: quoteVersion,
      productName: overrides.single['productName'] as String,
      unit: overrides.single['unit'] as String,
    );
  }

  @override
  Future<ContractAppendixHistoryPage> list({
    required int page,
    required int limit,
    String? query,
  }) async {
    listCalls++;
    final saved = _document(saved: true);
    return ContractAppendixHistoryPage(
      items: [
        ContractAppendixHistoryItem(
          id: saved.id!,
          orderCode: saved.orderCode,
          itemCount: saved.items.length,
          totalBeforeVat: saved.totalBeforeVat!,
          totalVatAmount: saved.totalVatAmount!,
          totalAfterVat: saved.totalAfterVat!,
          amountInWords: saved.amountInWords!,
          manualTaxItemCount: 0,
          createdAt: saved.createdAt,
          expiresAt: saved.expiresAt,
        ),
      ],
      page: page,
      limit: limit,
      total: 1,
      hasMore: false,
    );
  }

  @override
  Future<ContractAppendixDocument> detail(String id) async {
    detailCalls++;
    return _document(saved: true);
  }
}

ContractAppendixDocument _document({
  bool saved = false,
  String quoteVersion = 'quote-1',
  String productName = 'Laptop ERP',
  String unit = 'Cái',
}) {
  final createdAt = saved ? DateTime.utc(2026, 7, 17, 8) : null;
  return ContractAppendixDocument(
    id: saved ? 'appendix-1' : null,
    orderCode: 'SO-1',
    quoteVersion: quoteVersion,
    terminalCode: '49180_PRICE_0001',
    sourceOrderFetchedAt: DateTime.utc(2026, 7, 17, 7),
    items: [
      ContractAppendixItem(
        position: 1,
        sourceLineKey: '1:250902982',
        sku: '250902982',
        sellerSku: '250902982',
        productName: productName,
        quantity: 1,
        unit: unit,
        finalSellPrice: 55180000,
        vatRateBps: 800,
        taxCode: 'VAT8',
        taxLabel: 'Thuế GTGT 8%',
        taxSource: 'ERP_PPM',
        taxFetchedAt: DateTime.utc(2026, 7, 17, 7),
        unitPriceBeforeVat: 51092593,
        lineBeforeVat: 51092593,
        lineVatAmount: 4087407,
        lineAfterVat: 55180000,
      ),
    ],
    totalBeforeVat: 51092593,
    totalVatAmount: 4087407,
    totalAfterVat: 55180000,
    amountInWords: 'Năm mươi lăm triệu một trăm tám mươi nghìn đồng chẵn.',
    manualTaxItemCount: 0,
    unresolvedTaxCount: 0,
    canSave: true,
    createdAt: createdAt,
    expiresAt: createdAt?.add(const Duration(days: 30)),
  );
}
