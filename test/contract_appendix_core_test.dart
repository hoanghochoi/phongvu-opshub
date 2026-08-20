import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
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
      expect(document.orderCodes, ['SO-1']);
      expect(document.sourceOrders.single.orderCode, 'SO-1');
      expect(document.items.single.erpRowTotal, 15570000);
      expect(document.items.single.sourceOrderCodes, ['SO-1']);
    });

    test('parses plural order provenance and ERP row total', () {
      final document = ContractAppendixDocument.fromJson({
        'orderCode': 'SO-1',
        'orderCodes': ['SO-1', 'SO-2'],
        'sourceOrders': [
          {
            'position': 0,
            'orderCode': 'SO-1',
            'fetchedAt': '2026-08-19T01:00:00.000Z',
          },
          {
            'position': 1,
            'orderCode': 'SO-2',
            'fetchedAt': '2026-08-19T01:00:01.000Z',
          },
        ],
        'quoteVersion': 'quote-multi',
        'terminalCode': '49180_PRICE_0001',
        'items': [
          {
            'position': 1,
            'sourceLineKey': 'multi-line',
            'sku': 'SKU-1',
            'productName': 'Sản phẩm',
            'quantity': 2,
            'unit': 'Cái',
            'finalSellPrice': 250,
            'vatRateBps': 0,
            'taxSource': 'ERP_PPM',
            'unitPriceBeforeVat': 250,
            'lineBeforeVat': 500,
            'lineVatAmount': -1,
            'lineAfterVat': 499,
            'erpRowTotal': 499,
            'sourceOrderCodes': ['SO-1', 'SO-2'],
            'sourceLineIdentities': ['SO-1:line-1', 'SO-2:line-1'],
          },
        ],
        'totalBeforeVat': 500,
        'totalVatAmount': -1,
        'totalAfterVat': 499,
        'amountInWords': 'Bốn trăm chín mươi chín đồng.',
        'canSave': true,
      });

      expect(document.orderCodes, ['SO-1', 'SO-2']);
      expect(document.sourceOrders.map((value) => value.position), [0, 1]);
      expect(document.items.single.erpRowTotal, 499);
      expect(document.items.single.sourceOrderCodes, ['SO-1', 'SO-2']);
      expect(document.items.single.sourceLineIdentities, [
        'SO-1:line-1',
        'SO-2:line-1',
      ]);
    });
  });

  group('ContractAppendixRepository', () {
    test('sends plural-only order codes for preview and save', () async {
      final requests = <http.Request>[];
      final client = ApiClient.test(
        MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'orderCode': 'SO-1',
              'orderCodes': ['SO-1', 'SO-2'],
              'quoteVersion': 'quote-1',
              'terminalCode': '49180_PRICE_0001',
              'items': const [],
              'canSave': false,
            }),
            200,
          );
        }),
      );
      final repository = ContractAppendixRepository(client);

      await repository.preview(orderCodes: const [' SO-1 ', 'SO-2']);
      await repository.save(
        orderCodes: const [' SO-1 ', 'SO-2'],
        quoteVersion: 'quote-1',
        overrides: const [],
      );

      expect(requests, hasLength(2));
      for (final request in requests) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['orderCodes'], ['SO-1', 'SO-2']);
        expect(body.containsKey('orderCode'), isFalse);
      }
      expect(
        (jsonDecode(requests.last.body)
            as Map<String, dynamic>)['quoteVersion'],
        'quote-1',
      );
      client.dispose();
    });
  });

  group('Contract appendix clipboard payload', () {
    test('builds escaped 6-column HTML and TSV with totals', () {
      final payload = buildContractAppendixClipboardPayload(
        _document(
          saved: true,
          productName: 'Laptop <Pro> & "Office"\nDòng 2',
          unit: 'Cái\tchiếc',
        ),
      );

      expect(
        RegExp('<td width="').allMatches(payload.html).length,
        greaterThanOrEqualTo(12),
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
      for (final width in ['6%', '48%', '8%', '8%', '15%', '15%']) {
        expect(payload.html, contains('<col width="$width"'));
      }
      expect(payload.html, contains('<td width="48%"'));
      expect(payload.html, isNot(contains('Mã hàng')));
      expect(payload.html, isNot(contains('<thead>')));
      expect(payload.html, isNot(contains('</thead>')));
      expect(payload.html, contains('white-space:nowrap'));
      expect(payload.html, contains('word-wrap:break-word'));
      expect(payload.html, contains('overflow-wrap:break-word'));
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
      expect(lines.first.split('\t'), hasLength(6));
      expect(lines[1].split('\t'), hasLength(6));
      expect(lines[1], contains('Laptop <Pro> & "Office" Dòng 2'));
      expect(lines[1], isNot(contains('220909037')));
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
      'copies the reported 0% item with ERP unit and gross quantity total',
      () {
        final payload = buildContractAppendixClipboardPayload(
          _document(saved: true),
        );

        expect(
          payload.plainText,
          contains('Phần mềm Microsoft Win Pro 11 64-bit'),
        );
        expect(
          payload.plainText,
          contains(
            '\tPhần mềm Microsoft Win Pro 11 64-bit\tBản\t3\t'
            '5.190.000\t15.570.000',
          ),
        );
        expect(payload.plainText, contains('Tổng cộng\t\t\t\t\t15.570.000'));
        expect(
          payload.plainText,
          contains(
            'Tổng giá trị hợp đồng (đã bao gồm thuế GTGT)\t\t\t\t\t15.570.000',
          ),
        );
      },
    );
  });

  group('ContractAppendixProvider', () {
    test(
      'adds orders without API, deduplicates, fetches, locks and resets',
      () async {
        final dataSource = _FakeDataSource();
        final provider = ContractAppendixProvider(
          dataSource,
          clipboardWriter: _FakeClipboardWriter(),
        );

        expect(provider.addOrderCode(' SO-1 '), isTrue);
        expect(provider.addOrderCode('so-1'), isFalse);
        expect(provider.addOrderCode('SO-2'), isTrue);
        expect(provider.selectedOrderCodes, ['SO-1', 'SO-2']);
        expect(dataSource.previewCalls, 0);

        expect(await provider.fetchOrders(), isTrue);
        expect(dataSource.previewCalls, 1);
        expect(dataSource.lastPreviewOrderCodes, ['SO-1', 'SO-2']);
        expect(provider.isOrderSelectionLocked, isTrue);
        expect(provider.addOrderCode('SO-3'), isFalse);
        expect(provider.removeOrderCode('SO-1'), isFalse);

        expect(provider.resetOrderSelection(), isTrue);
        expect(provider.selectedOrderCodes, isEmpty);
        expect(provider.isOrderSelectionLocked, isFalse);
        expect(provider.draft, isNull);
        expect(provider.saved, isNull);
      },
    );

    test(
      'enforces ten orders and retains selection after atomic failure',
      () async {
        final dataSource = _FakeDataSource()
          ..previewError = StateError('ERP lỗi');
        final provider = ContractAppendixProvider(
          dataSource,
          clipboardWriter: _FakeClipboardWriter(),
        );

        for (var index = 1; index <= 10; index++) {
          expect(provider.addOrderCode('SO-$index'), isTrue);
        }
        expect(provider.addOrderCode('SO-11'), isFalse);
        expect(await provider.fetchOrders(), isFalse);
        expect(provider.selectedOrderCodes, hasLength(10));
        expect(provider.isOrderSelectionLocked, isFalse);
        expect(provider.draft, isNull);
      },
    );

    test('ERP name and unit remain locked before copy is enabled', () async {
      final dataSource = _FakeDataSource();
      final writer = _FakeClipboardWriter();
      final provider = ContractAppendixProvider(
        dataSource,
        clipboardWriter: writer,
      );

      expect(await provider.lookupOrder(' SO-1 '), isTrue);
      expect(provider.canCopy, isFalse);

      provider.updateProductName('1:220909037', 'Tên hợp đồng');
      provider.updateUnit('1:220909037', 'Bộ');
      expect(provider.isDirty, isFalse);
      expect(provider.draft?.items.single.productName, 'Laptop ERP');
      expect(provider.draft?.items.single.unit, 'Bản');
      expect(provider.canCopy, isFalse);

      expect(await provider.saveCurrent(), isTrue);
      expect(dataSource.previewCalls, 1);
      expect(dataSource.saveCalls, 1);
      expect(provider.saved?.items.single.productName, 'Laptop ERP');
      expect(provider.saved?.items.single.unit, 'Bản');
      expect(provider.canCopy, isTrue);
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
  Object? previewError;
  List<String>? lastPreviewOrderCodes;
  List<String>? lastSaveOrderCodes;

  @override
  Future<ContractAppendixDocument> preview({
    required List<String> orderCodes,
    List<Map<String, dynamic>> overrides = const [],
  }) async {
    previewCalls++;
    lastPreviewOrderCodes = List<String>.of(orderCodes);
    if (previewError case final error?) throw error;
    final name = overrides.isEmpty
        ? 'Laptop ERP'
        : overrides.single['productName'] as String;
    final unit = overrides.isEmpty ? 'Bản' : overrides.single['unit'] as String;
    return _document(
      orderCodes: orderCodes,
      quoteVersion: 'quote-$previewCalls',
      productName: name,
      unit: unit,
    );
  }

  @override
  Future<ContractAppendixDocument> save({
    required List<String> orderCodes,
    required String quoteVersion,
    required List<Map<String, dynamic>> overrides,
  }) async {
    saveCalls++;
    lastSaveOrderCodes = List<String>.of(orderCodes);
    return _document(
      saved: true,
      orderCodes: orderCodes,
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
  List<String> orderCodes = const ['SO-1'],
}) {
  final createdAt = saved ? DateTime.utc(2026, 7, 17, 8) : null;
  return ContractAppendixDocument(
    id: saved ? 'appendix-1' : null,
    orderCode: orderCodes.first,
    orderCodes: orderCodes,
    sourceOrders: [
      for (final entry in orderCodes.indexed)
        ContractAppendixSourceOrder(
          position: entry.$1,
          orderCode: entry.$2,
          fetchedAt: DateTime.utc(2026, 7, 17, 7),
        ),
    ],
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
        erpRowTotal: 15570000,
        sourceOrderCodes: orderCodes,
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
