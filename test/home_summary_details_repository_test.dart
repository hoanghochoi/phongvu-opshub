import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/network/api_exception.dart';
import 'package:phongvu_opshub/features/home/data/repositories/home_summary_repository.dart';
import 'package:phongvu_opshub/features/home/domain/home_summary.dart';

void main() {
  group('Home summary details v2 repository', () {
    test(
      'Given a cursor, when loading not-purchased details, then calls v2 with a bounded page size',
      () async {
        late Uri requestedUri;
        final repository = HomeSummaryRepository(
          ApiClient.test(
            MockClient((request) async {
              requestedUri = request.url;
              return http.Response(
                jsonEncode({
                  'kind': 'NOT_PURCHASED',
                  'startDate': '2026-07-01',
                  'endDate': '2026-07-30',
                  'scope': 'MANAGED_SCOPE',
                  'scopeLabel': 'Showroom được gán',
                  'selectedSalesProgressUserId': 'sales-1',
                  'limit': 100,
                  'total': 101,
                  'items': [
                    {
                      'id': 'report-51',
                      'storeCode': 'CP75',
                      'salesName': 'SA Một',
                      'customerName': 'Khách hàng A',
                    },
                  ],
                  'nextCursor': 'cursor-101',
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
          ),
        );

        final page = await repository.fetchNotPurchasedDetails(
          startDate: '2026-07-01',
          endDate: '2026-07-30',
          scope: 'managed_scope',
          organizationNodeId: 'node-1',
          salesProgressUserId: 'sales-1',
          cursor: '  cursor-50  ',
          limit: 500,
        );

        expect(requestedUri.path, '/api/home/summary/details/v2');
        expect(requestedUri.queryParameters, {
          'startDate': '2026-07-01',
          'endDate': '2026-07-30',
          'scope': 'MANAGED_SCOPE',
          'organizationNodeId': 'node-1',
          'salesProgressUserId': 'sales-1',
          'kind': 'NOT_PURCHASED',
          'limit': '100',
          'cursor': 'cursor-50',
        });
        expect(page.kind, HomeSummaryDetailKind.notPurchased);
        expect(page.items.single.id, 'report-51');
        expect(page.total, 101);
        expect(page.hasNextPage, isTrue);
      },
    );

    test(
      'Given a mismatched response kind, when loading details, then returns a Vietnamese parse error',
      () async {
        final repository = HomeSummaryRepository(
          ApiClient.test(
            MockClient(
              (_) async => http.Response(
                jsonEncode({
                  'kind': 'INSTALLMENT_NEED',
                  'startDate': '2026-07-20',
                  'endDate': '2026-07-20',
                  'scope': 'OWN',
                  'scopeLabel': 'Phạm vi cá nhân',
                  'limit': 50,
                  'total': 0,
                  'items': [],
                  'nextCursor': null,
                }),
                200,
                headers: {'content-type': 'application/json'},
              ),
            ),
          ),
        );

        expect(
          repository.fetchUnreportedOrderDetails(),
          throwsA(
            isA<ParseException>().having(
              (error) => error.message,
              'message',
              contains('Vui lòng thử lại'),
            ),
          ),
        );
      },
    );
  });

  test('Typed detail pages append only within the same query snapshot', () {
    final first = HomeSummaryDetailsPage<HomeUnreportedOrderDetail>(
      kind: HomeSummaryDetailKind.unreportedOrder,
      startDate: '2026-07-20',
      endDate: '2026-07-20',
      scope: 'OWN',
      scopeLabel: 'Phạm vi cá nhân',
      selectedSalesProgressUserId: null,
      limit: 1,
      total: 2,
      items: const [
        HomeUnreportedOrderDetail(
          orderCode: 'order-1',
          grandTotal: 1000000,
          soldAt: null,
          storeCode: 'CP75',
          salesName: 'SA Một',
        ),
      ],
      nextCursor: 'cursor-1',
    );
    final second = HomeSummaryDetailsPage<HomeUnreportedOrderDetail>(
      kind: HomeSummaryDetailKind.unreportedOrder,
      startDate: '2026-07-20',
      endDate: '2026-07-20',
      scope: 'OWN',
      scopeLabel: 'Phạm vi cá nhân',
      selectedSalesProgressUserId: null,
      limit: 1,
      total: 2,
      items: const [
        HomeUnreportedOrderDetail(
          orderCode: 'order-2',
          grandTotal: 2000000,
          soldAt: null,
          storeCode: 'CP75',
          salesName: 'SA Hai',
        ),
      ],
      nextCursor: null,
    );

    final combined = first.append(second);

    expect(combined.items.map((item) => item.orderCode), [
      'order-1',
      'order-2',
    ]);
    expect(combined.hasNextPage, isFalse);
    expect(
      () => first.append(
        HomeSummaryDetailsPage<HomeUnreportedOrderDetail>(
          kind: HomeSummaryDetailKind.unreportedOrder,
          startDate: '2026-07-19',
          endDate: '2026-07-20',
          scope: 'OWN',
          scopeLabel: 'Phạm vi cá nhân',
          selectedSalesProgressUserId: null,
          limit: 1,
          total: 2,
          items: const [],
          nextCursor: null,
        ),
      ),
      throwsFormatException,
    );
  });
}
