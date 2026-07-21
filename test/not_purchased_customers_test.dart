import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/network/api_exception.dart';
import 'package:phongvu_opshub/core/network/realtime_connection_manager.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/store_branch.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/sales_report/data/sales_report_repository.dart';
import 'package:phongvu_opshub/features/sales_report/domain/sales_report.dart';
import 'package:phongvu_opshub/features/sales_report/presentation/screens/not_purchased_customers_screen.dart';

void main() {
  testWidgets('quản lý xem trước và nhập Excel ngay tại Chăm sóc lại', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FakeFollowUpRepository(
      _case(customerPhone: '0900000000', customerZaloContact: null),
    );
    final authProvider = _FakeAuthProvider(
      const User(
        email: 'manager@phongvu.com',
        role: 'USER',
        featureAccess: {'ADMIN_SALES_REPORTS': true},
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: MaterialApp(
          home: Scaffold(
            body: NotPurchasedCustomersScreen(
              repository: repository,
              importFilePicker: () async => SalesReportImportFile(
                name: 'khach-chua-mua.xlsx',
                size: 4,
                bytes: Uint8List.fromList(const [1, 2, 3, 4]),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nhập Excel'), findsOneWidget);
    await tester.tap(find.text('Nhập Excel'));
    await tester.pumpAndSettle();
    expect(find.text('Nhập Excel khách chưa mua'), findsOneWidget);

    await tester.tap(find.text('Chọn file Excel'));
    await tester.pumpAndSettle();
    expect(find.text('khach-chua-mua.xlsx'), findsOneWidget);

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text('Hủy các thay đổi?'), findsOneWidget);
    await tester.tap(find.text('Tiếp tục chỉnh sửa'));
    await tester.pumpAndSettle();
    expect(find.text('Nhập Excel khách chưa mua'), findsOneWidget);

    await tester.tap(find.text('Xem trước dữ liệu'));
    await tester.pumpAndSettle();
    expect(find.text('Kết quả xem trước'), findsOneWidget);
    expect(repository.previewCalls, 1);

    await tester.tap(find.text('Nhập 1 dòng hợp lệ'));
    await tester.pumpAndSettle();
    expect(find.text('Đã nhập dữ liệu'), findsOneWidget);
    expect(repository.commitCalls, 1);

    await tester.tap(find.text('Hoàn tất'));
    await tester.pumpAndSettle();
    expect(repository.listCalls, 2);
  });

  testWidgets('nhân viên bán hàng không thấy thao tác nhập Excel', (
    tester,
  ) async {
    final repository = _FakeFollowUpRepository(
      _case(customerPhone: '0900000000', customerZaloContact: null),
    );
    final authProvider = _FakeAuthProvider(
      const User(
        email: 'staff@phongvu.com',
        role: 'USER',
        featureAccess: {'SALES_REPORT': true},
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: MaterialApp(
          home: Scaffold(
            body: NotPurchasedCustomersScreen(repository: repository),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nhập Excel'), findsNothing);
  });

  testWidgets('Lịch sử chăm sóc nằm giữa Cần chăm sóc và Đã ẩn', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FakeFollowUpRepository(
      _case(customerPhone: '0900000000', customerZaloContact: null),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotPurchasedCustomersScreen(repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final openX = tester.getCenter(find.text('Cần chăm sóc')).dx;
    final historyX = tester.getCenter(find.text('Lịch sử chăm sóc')).dx;
    final hiddenX = tester.getCenter(find.text('Đã ẩn')).dx;
    expect(openX, lessThan(historyX));
    expect(historyX, lessThan(hiddenX));

    await tester.tap(find.text('Lịch sử chăm sóc'));
    await tester.pumpAndSettle();
    expect(repository.lastStatus, 'HISTORY');
  });

  testWidgets('Super Admin có thể lọc khách chưa mua theo showroom', (
    tester,
  ) async {
    final repository = _FakeFollowUpRepository(
      _case(customerPhone: '0900000000', customerZaloContact: null),
    );
    final realtime = _FakeRealtimeClient();
    final authProvider = _FakeAuthProvider(
      const User(email: 'admin@phongvu.com', role: 'SUPER_ADMIN'),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: MaterialApp(
          home: Scaffold(
            body: NotPurchasedCustomersScreen(
              repository: repository,
              realtimeClient: realtime,
              storeLoader: () async => const [
                StoreBranch(
                  id: 'store-2',
                  storeId: 'CP02',
                  storeName: 'Quận 2',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mã showroom'), findsOneWidget);
    await tester.tap(find.byType(TextField).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('CP02 - Quận 2').last);
    await tester.pumpAndSettle();

    expect(repository.lastStoreCode, 'CP02');
    await realtime.dispose();
  });

  testWidgets('trong grace vẫn hiện khách chỉ có Zalo và mở lịch sử chăm sóc', (
    tester,
  ) async {
    final item = _case(
      customerPhone: null,
      customerZaloContact: 'zalo-khach-a',
    );
    final repository = _FakeFollowUpRepository(
      item,
      contactGracePeriodActive: true,
      contactGracePeriodEndsAt: DateTime(2026, 7, 31, 9),
    );
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
      _case(
        customerPhone: 'Không cung cấp',
        customerZaloContact: 'zalo-khach-a',
      ),
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

  testWidgets('tạm hiển thị mọi hồ sơ trong thời gian rà soát liên hệ', (
    tester,
  ) async {
    final repository = _FakeFollowUpRepository(
      _case(customerPhone: 'Không cung cấp', customerZaloContact: null),
      contactGracePeriodActive: true,
      contactGracePeriodEndsAt: DateTime(2026, 7, 31, 9),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotPurchasedCustomersScreen(repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nguyễn Văn A'), findsOneWidget);
    expect(
      find.textContaining('Tạm hiển thị toàn bộ khách chưa mua'),
      findsOneWidget,
    );
  });

  testWidgets('hiển thị hồ sơ có kênh Zalo OA dù không có số điện thoại', (
    tester,
  ) async {
    final repository = _FakeFollowUpRepository(
      _case(
        customerPhone: null,
        customerZaloContact: null,
        customerContactChannels: const [salesReportContactChannelZaloOa],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotPurchasedCustomersScreen(repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nguyễn Văn A'), findsOneWidget);
    expect(find.text('Zalo OA'), findsOneWidget);
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

  test('payload lưu riêng hai kênh Zalo và câu trả lời hành vi Zalo OA', () {
    const input = SalesReportInput(
      reportType: 'NOT_PURCHASED',
      orderCode: null,
      entrySource: null,
      customerName: 'Nguyễn Văn A',
      customerPhone: null,
      customerContactChannels: [
        salesReportContactChannelZaloPersonal,
        salesReportContactChannelZaloOa,
      ],
      customerZaloContact: null,
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

    expect(input.toJson()['customerContactChannels'], [
      salesReportContactChannelZaloPersonal,
      salesReportContactChannelZaloOa,
    ]);
    expect(input.toJson().containsKey('customerZaloContact'), isFalse);
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
  List<String> customerContactChannels = const [],
}) {
  return SalesReportFollowUpCase(
    id: 'case-1',
    status: 'OPEN',
    customerName: 'Nguyễn Văn A',
    customerPhone: customerPhone,
    customerContactChannels: customerContactChannels,
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
  final bool contactGracePeriodActive;
  final DateTime? contactGracePeriodEndsAt;
  int detailCalls = 0;
  int listCalls = 0;
  String? lastStoreCode;
  String? lastStatus;
  int previewCalls = 0;
  int commitCalls = 0;

  _FakeFollowUpRepository(
    this.item, {
    this.detailFailures = 0,
    this.contactGracePeriodActive = false,
    this.contactGracePeriodEndsAt,
  }) : super(ApiClient());

  @override
  Future<SalesReportFollowUpPage> fetchFollowUpCases({
    String status = 'OPEN',
    String? search,
    String? storeCode,
    int page = 0,
    int limit = 20,
  }) async {
    listCalls += 1;
    lastStoreCode = storeCode;
    lastStatus = status;
    return SalesReportFollowUpPage(
      items: [item],
      page: page,
      limit: limit,
      total: 1,
      hasMore: false,
      managedScope: false,
      contactGracePeriodActive: contactGracePeriodActive,
      contactGracePeriodEndsAt: contactGracePeriodEndsAt,
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

  @override
  Future<SalesReportImportPreview> previewImport(
    SalesReportImportFile file,
  ) async {
    previewCalls += 1;
    return _importPreview();
  }

  @override
  Future<SalesReportImportPreview> commitImport(
    SalesReportImportFile file, {
    required String expectedFileHash,
  }) async {
    commitCalls += 1;
    return _importPreview(batchId: 'batch-1', importedRows: 1);
  }
}

SalesReportImportPreview _importPreview({
  String? batchId,
  int importedRows = 0,
}) => SalesReportImportPreview(
  fileName: 'khach-chua-mua.xlsx',
  fileHash: List.filled(64, 'a').join(),
  batchId: batchId,
  totalRows: 1,
  validRows: 1,
  importedRows: importedRows,
  purchasedRows: 0,
  duplicateRows: 0,
  invalidRows: 0,
  unassignedRows: 0,
  rows: const [],
);

class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider(this.currentUser) : super(AuthRepository(ApiClient()));

  final User currentUser;

  @override
  User? get user => currentUser;

  @override
  bool get isInitialized => true;

  @override
  bool get isAuthenticated => true;
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
