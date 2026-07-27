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
            'sourceLineKey': '1:220909037',
            'sku': '220909037',
            'productName': 'Phần mềm Microsoft Win Pro 11 64-bit',
            'quantity': 3,
            'unit': 'Bản',
            'finalSellPrice': 5190000,
            'vatRateBps': null,
            'taxSource': 'MISSING',
            'unitPriceBeforeVat': null,
            'lineBeforeVat': null,
            'lineVatAmount': null,
            'lineAfterVat': 15570000,
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
      expect(document.items.single.lineAfterVat, 15570000);
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

      expect(
        RegExp('<td width="').allMatches(payload.html).length,
        greaterThanOrEqualTo(14),
      );
      expect(payload.html, contains('Thành tiền (VNĐ)<br>(đã bao gồm VAT)'));
      expect(payload.plainText, contains('Thành tiền (VNĐ) (đã bao gồm VAT)'));
      expect(payload.plainText, contains('15.570.000'));
      expect(
        payload.html,
        contains('Laptop &lt;Pro&gt; &amp; &quot;Office&quot;'),
      );
      expect(payload.html, isNot(contains('Laptop <Pro>')));
      expect(payload.html, contains('Tổng giá trị hợp đồng'));
      expect(payload.html, contains('Bằng chữ: Mười lăm triệu'));
      expect(payload.html, contains("font-family:'Times New Roman'"));
      expect(payload.html, contains('font-size:12pt'));
      expect(payload.html.trimLeft(), startsWith('<table'));
      expect(payload.html, isNot(contains('<!DOCTYPE')));
      expect(payload.html, isNot(contains('<html')));
      expect(payload.html, isNot(contains('<head')));
      expect(payload.html, isNot(contains('<body')));
      expect(payload.html, isNot(contains('StartFragment')));
      expect(payload.html, isNot(contains('EndFragment')));
      expect(payload.html, contains('table-layout:fixed'));
      expect(payload.html, contains('mso-table-layout-alt:fixed'));
      expect(payload.html, contains('<colgroup>'));
      for (final width in ['6%', '40%', '6%', '7%', '16%', '9%', '16%']) {
        expect(payload.html, contains('<col width="$width"'));
      }
      expect(payload.html, contains('<td width="40%"'));
      expect(payload.html, isNot(contains('<thead>')));
      expect(payload.html, isNot(contains('</thead>')));
      expect(payload.html, contains('white-space:nowrap'));
      expect(payload.html, isNot(contains('<th')));
      expect(payload.html, contains('align="center" valign="middle"'));
      expect(payload.html, contains('dir="ltr"'));
      expect(payload.html, contains('text-align:center!important'));
      expect(payload.html, contains('text-align:left!important'));
      expect(payload.html, contains('text-justify:none'));
      expect(
        payload.html,
        contains(
          '<p align="center" dir="ltr" style="margin:0cm;'
          'mso-para-margin:0cm;',
        ),
      );
      expect(
        payload.html,
        contains(
          '<p align="left" dir="ltr" style="margin:0cm;'
          'mso-para-margin:0cm;',
        ),
      );
      expect(payload.html, isNot(contains('<div align=')));
      expect(payload.html, contains('<font face="Times New Roman" size="3"'));
      expect(payload.html, contains("mso-ascii-font-family:'Times New Roman'"));
      final tableEnd = payload.html.indexOf('</table>');
      final amountInWords = payload.html.indexOf('Bằng chữ:');
      expect(tableEnd, greaterThan(0));
      expect(amountInWords, greaterThan(tableEnd));
      expect(
        payload.html.substring(payload.html.indexOf('<table'), tableEnd),
        isNot(contains('Bằng chữ:')),
      );

      final lines = payload.plainText.split('\n');
      expect(lines.first.split('\t'), hasLength(7));
      expect(lines[1].split('\t'), hasLength(7));
      expect(lines[1], contains('Laptop <Pro> & "Office" Dòng 2'));
      expect(lines[1], contains('Cái chiếc'));
      expect(payload.plainText, contains('Thuế GTGT'));
      expect(payload.plainText, contains('\n\nBằng chữ:'));
    });

    test('rejects preview that has not been saved', () {
      expect(
        () => buildContractAppendixClipboardPayload(_document()),
        throwsStateError,
      );
    });

    test(
      'copies the reported 0% SKU with ERP unit and gross quantity total',
      () {
        final payload = buildContractAppendixClipboardPayload(
          _document(saved: true),
        );

        expect(
          payload.plainText,
          contains('Phần mềm Microsoft Win Pro 11 64-bit'),
        );
        expect(payload.plainText, contains('\tBản\t5.190.000\t0%\t15.570.000'));
        expect(payload.plainText, contains('Tổng cộng\t\t\t\t\t\t15.570.000'));
        expect(
          payload.plainText,
          contains(
            'Tổng giá trị hợp đồng (đã bao gồm thuế GTGT)\t\t\t\t\t\t15.570.000',
          ),
        );
      },
    );
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

      provider.updateProductName('1:220909037', 'Tên hợp đồng');
      expect(provider.isDirty, isTrue);
      expect(provider.canCopy, isFalse);

      expect(await provider.saveCurrent(), isTrue);
      expect(dataSource.previewCalls, 2);
      expect(dataSource.saveCalls, 1);
      expect(provider.saved?.items.single.productName, 'Tên hợp đồng');
      expect(provider.canCopy, isTrue);

      provider.updateUnit('1:220909037', 'Bộ');
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
    final unit = overrides.isEmpty ? 'Bản' : overrides.single['unit'] as String;
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
  String productName = 'Phần mềm Microsoft Win Pro 11 64-bit',
  String unit = 'Bản',
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
        sourceLineKey: '1:220909037',
        sku: '220909037',
        sellerSku: '220909037',
        productName: productName,
        quantity: 3,
        unit: unit,
        finalSellPrice: 5190000,
        vatRateBps: 0,
        taxCode: 'VAT0',
        taxLabel: 'Thuế 0%',
        taxSource: 'ERP_PPM',
        taxFetchedAt: DateTime.utc(2026, 7, 17, 7),
        unitPriceBeforeVat: 5190000,
        lineBeforeVat: 15570000,
        lineVatAmount: 0,
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
    createdAt: createdAt,
    expiresAt: createdAt?.add(const Duration(days: 30)),
  );
}
