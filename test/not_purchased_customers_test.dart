import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/network/api_exception.dart';
import 'package:phongvu_opshub/core/network/realtime_connection_manager.dart';
import 'package:phongvu_opshub/features/sales_report/data/sales_report_repository.dart';
import 'package:phongvu_opshub/features/sales_report/domain/sales_report.dart';
import 'package:phongvu_opshub/features/sales_report/presentation/screens/not_purchased_customers_screen.dart';

void main() {
  testWidgets('hiển thị khách chỉ có Zalo và mở lịch sử chăm sóc', (
    tester,
  ) async {
    final item = _case(
      customerPhone: null,
      customerZaloContact: 'zalo-khach-a',
    );
    final repository = _FakeFollowUpRepository(item);
    final realtime = _FakeRealtimeClient();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotPurchasedCustomersScreen(
            repository: repository,
            realtimeClient: realtime,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chăm sóc lại'), findsOneWidget);
    expect(find.text('Nguyễn Văn A'), findsOneWidget);
    expect(find.text('zalo-khach-a'), findsOneWidget);

    await tester.tap(find.text('Nguyễn Văn A'));
    await tester.pumpAndSettle();

    expect(find.text('Tiếp xúc lần đầu'), findsOneWidget);
    expect(find.text('Lần chăm sóc 1'), findsOneWidget);
    expect(repository.detailCalls, 1);
    await realtime.dispose();
  });

  testWidgets('không hiển thị hồ sơ có số điện thoại là nội dung khác', (
    tester,
  ) async {
    final repository = _FakeFollowUpRepository(
      _case(customerPhone: 'Không cung cấp', customerZaloContact: null),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotPurchasedCustomersScreen(repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nguyễn Văn A'), findsNothing);
    expect(find.text('Không có khách hàng cần chăm sóc'), findsOneWidget);
  });

  testWidgets('tự thử lại khi tải lịch sử chăm sóc bị chập chờn', (
    tester,
  ) async {
    final item = _case(customerPhone: '0909000000', customerZaloContact: null);
    final repository = _FakeFollowUpRepository(item, detailFailures: 2);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotPurchasedCustomersScreen(repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nguyễn Văn A'));
    await tester.pumpAndSettle();

    expect(find.text('Lần chăm sóc 1'), findsOneWidget);
    expect(repository.detailCalls, 3);
  });

  testWidgets('realtime v2 follow-up filters, coalesces, and syncs once', (
    tester,
  ) async {
    final repository = _FakeFollowUpRepository(
      _case(customerPhone: '0909000000', customerZaloContact: null),
    );
    final realtime = _FakeRealtimeClient();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotPurchasedCustomersScreen(
            repository: repository,
            realtimeClient: realtime,
            realtimeDebounce: const Duration(milliseconds: 20),
            realtimeMaxWait: const Duration(milliseconds: 80),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.listCalls, 1);

    realtime.addEvent(_followUpEnvelope('wrong-source', source: 'erp_sync'));
    await tester.pump(const Duration(milliseconds: 30));
    expect(repository.listCalls, 1);

    realtime.addEvent(_followUpEnvelope('follow-up-1'));
    realtime.addEvent(_followUpEnvelope('follow-up-2'));
    await tester.pump(const Duration(milliseconds: 10));
    expect(repository.listCalls, 1);
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();
    expect(repository.listCalls, 2);

    realtime.requestSync(RealtimeSyncReason.appResumed);
    await tester.pump();
    await tester.pump();
    expect(repository.listCalls, 3);

    await tester.pumpWidget(const SizedBox.shrink());
    await realtime.dispose();
  });

  test('payload báo cáo giữ Zalo cá nhân độc lập với câu trả lời Zalo OA', () {
    const input = SalesReportInput(
      reportType: 'NOT_PURCHASED',
      orderCode: null,
      entrySource: null,
      customerName: 'Nguyễn Văn A',
      customerPhone: null,
      customerZaloContact: 'zalo-khach-a',
      categoryGroupId: 'NH01',
      categoryGroupIds: ['NH01'],
      customerNeed: 'Laptop',
      consultedSolutionAnswer: 'YES',
      consultedSolutionOtherReason: null,
      experiencedAnswer: 'YES',
      experiencedOtherReason: null,
      zaloAnswer: 'ALREADY_FOLLOWED_ZALO',
      zaloOtherReason: null,
      appDownloadAnswer: 'YES',
      appDownloadOtherReason: null,
      notPurchasedReason: 'CUSTOMER_BROWSING',
      notPurchasedOtherReason: null,
      customerType: 'PERSONAL',
      customerIsStudent: false,
      promotionCodes: [],
      installmentNeed: false,
      installmentApproved: null,
      installmentLoanAmount: null,
      installmentNoInstallmentReason: null,
      installmentStatus: null,
      installmentFailureReason: null,
      installmentPartnerCodes: [],
    );

    expect(input.toJson()['customerZaloContact'], 'zalo-khach-a');
    expect(input.toJson()['zaloAnswer'], 'ALREADY_FOLLOWED_ZALO');
    expect(input.toJson().containsKey('customerPhone'), isFalse);
  });
}

RealtimeEnvelope _followUpEnvelope(
  String id, {
  String source = 'follow_up_created',
}) {
  return RealtimeEnvelope(
    version: 2,
    kind: 'SALES_REPORT_ORDERS_UPDATED',
    id: id,
    topic: 'sales-report.orders',
    sequence: id.hashCode.abs(),
    timestamp: DateTime(2026, 7, 15, 9),
    data: {'source': source},
  );
}

SalesReportFollowUpCase _case({
  required String? customerPhone,
  required String? customerZaloContact,
}) {
  return SalesReportFollowUpCase(
    id: 'case-1',
    status: 'OPEN',
    customerName: 'Nguyễn Văn A',
    customerPhone: customerPhone,
    customerZaloContact: customerZaloContact,
    categoryNames: const ['Laptop'],
    storeCode: 'CP01',
    storeName: 'Phong Vũ CP01',
    firstContactAt: DateTime(2026, 7, 10, 9),
    firstContactByName: 'Nhân viên A',
    firstContactByEmail: 'a@phongvu.vn',
    firstReasonLabel: 'Khách tham khảo',
    firstOtherReason: null,
    assigneeUserId: 'user-a',
    assigneeName: 'Nhân viên A',
    lastFollowUpAt: null,
    lastFollowUpByName: null,
    followUpCount: 0,
    nextSequenceNumber: 1,
    careAgeDays: 4,
    canWrite: true,
    canReassign: false,
    canReopen: false,
    entries: const [],
    assignmentCandidates: const [],
  );
}

class _FakeFollowUpRepository extends SalesReportRepository {
  final SalesReportFollowUpCase item;
  final int detailFailures;
  int detailCalls = 0;
  int listCalls = 0;

  _FakeFollowUpRepository(this.item, {this.detailFailures = 0})
    : super(ApiClient());

  @override
  Future<SalesReportFollowUpPage> fetchFollowUpCases({
    String status = 'OPEN',
    String? search,
    int page = 0,
    int limit = 20,
  }) async {
    listCalls += 1;
    return SalesReportFollowUpPage(
      items: [item],
      page: page,
      limit: limit,
      total: 1,
      hasMore: false,
      managedScope: false,
    );
  }

  @override
  Future<SalesReportFollowUpCase> fetchFollowUpCase(String id) async {
    detailCalls += 1;
    if (detailCalls <= detailFailures) {
      throw ApiException('temporary detail failure');
    }
    return item;
  }
}

class _FakeRealtimeClient implements RealtimeClient {
  final _events = StreamController<RealtimeEnvelope>.broadcast();
  final _syncRequests = StreamController<RealtimeSyncReason>.broadcast();

  @override
  Stream<RealtimeEnvelope> get events => _events.stream;

  @override
  Stream<RealtimeSyncReason> get syncRequests => _syncRequests.stream;

  void addEvent(RealtimeEnvelope event) => _events.add(event);

  void requestSync(RealtimeSyncReason reason) => _syncRequests.add(reason);

  @override
  Future<void> syncSession(String? sessionKey) async {}

  Future<void> dispose() async {
    await _events.close();
    await _syncRequests.close();
  }
}
