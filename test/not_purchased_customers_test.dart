import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
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

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotPurchasedCustomersScreen(repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Khách hàng chưa mua'), findsOneWidget);
    expect(find.text('Nguyễn Văn A'), findsOneWidget);
    expect(find.text('zalo-khach-a'), findsOneWidget);

    await tester.tap(find.text('Nguyễn Văn A'));
    await tester.pumpAndSettle();

    expect(find.text('Tiếp xúc lần đầu'), findsOneWidget);
    expect(find.text('Lần chăm sóc 1'), findsOneWidget);
    expect(repository.detailCalls, 1);
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
  int detailCalls = 0;

  _FakeFollowUpRepository(this.item) : super(ApiClient());

  @override
  Future<SalesReportFollowUpPage> fetchFollowUpCases({
    String status = 'OPEN',
    String? search,
    int page = 0,
    int limit = 20,
  }) async {
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
    return item;
  }
}
