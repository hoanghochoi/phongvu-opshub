import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/widgets/gradient_header.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/fifo/data/repositories/fifo_log_repository.dart';
import 'package:phongvu_opshub/features/fifo/presentation/screens/fifo_history_screen.dart';
import 'package:provider/provider.dart';

void main() {
  setUp(() {
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  testWidgets('FIFO History renders content-only runtime tabs and filters', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeFifoLogRepository();
    await tester.pumpWidget(_buildApp(repository));
    await tester.pumpAndSettle();

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(GradientHeader), findsNothing);
    expect(find.byKey(const Key('fifo-history-header')), findsOneWidget);
    expect(find.byKey(const Key('fifo-history-filter-card')), findsOneWidget);
    expect(find.byKey(const Key('fifo-history-tabs')), findsOneWidget);
    expect(find.byKey(const Key('fifo-history-query-field')), findsOneWidget);
    expect(find.byKey(const Key('fifo-history-user-field')), findsOneWidget);
    expect(find.text('Kiểm tra 1'), findsOneWidget);
    expect(find.text('SN-CHECK-001'), findsOneWidget);
    expect(find.text('Truy vấn'), findsWidgets);

    await tester.tap(find.text('Sắp xếp FIFO'));
    await tester.pumpAndSettle();

    expect(repository.requestedTypes, contains('FIFO_SORT'));
    expect(find.text('BIN-A12'), findsOneWidget);
    expect(find.text('Sắp xếp 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FIFO History exposes retry after load failure', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeFifoLogRepository(checkFailures: 1);
    await tester.pumpWidget(_buildApp(repository));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fifo-history-error')), findsOneWidget);
    expect(find.text('Chưa tải được lịch sử kiểm tra FIFO.'), findsOneWidget);
    expect(find.text('Thử tải lại'), findsOneWidget);

    await tester.tap(find.text('Thử tải lại'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fifo-history-error')), findsNothing);
    expect(find.text('SN-CHECK-001'), findsOneWidget);
    expect(repository.checkRequests, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FIFO History loaded state stays usable on mobile width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeFifoLogRepository();
    await tester.pumpWidget(_buildApp(repository));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fifo-history-header')), findsOneWidget);
    expect(find.byKey(const Key('fifo-history-filter-card')), findsOneWidget);
    expect(find.byKey(const Key('fifo-history-tabs')), findsOneWidget);
    expect(find.text('Kiểm tra 1'), findsOneWidget);
    expect(find.text('SN-CHECK-001'), findsOneWidget);

    await tester.tap(find.text('Sắp xếp FIFO'));
    await tester.pumpAndSettle();

    expect(find.text('Sắp xếp 1'), findsOneWidget);
    expect(find.text('BIN-A12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _buildApp(FifoLogRepository repository) {
  return ChangeNotifierProvider<AuthProvider>.value(
    value: _FakeAuthProvider(),
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox.expand(child: FifoHistoryScreen(repository: repository)),
      ),
    ),
  );
}

class _FakeFifoLogRepository extends FifoLogRepository {
  _FakeFifoLogRepository({this.checkFailures = 0}) : super(ApiClient());

  final int checkFailures;
  final List<String> requestedTypes = [];
  int checkRequests = 0;

  @override
  Future<Map<String, dynamic>> getAdminLogs({
    String? type,
    int page = 1,
    int limit = 20,
    String? filterUserEmail,
    String? search,
  }) async {
    requestedTypes.add(type ?? '');
    if (type == 'FIFO_CHECK') {
      checkRequests += 1;
      if (checkRequests <= checkFailures) {
        throw Exception('Dữ liệu kiểm thử chưa sẵn sàng');
      }
    }
    final item = type == 'FIFO_SORT' ? _sortLog : _checkLog;
    return {
      'data': <FifoLogItem>[item],
      'total': 1,
      'page': page,
      'limit': limit,
    };
  }
}

class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider() : super(AuthRepository(ApiClient()));

  @override
  User? get user => const User(
    id: 'admin-1',
    email: 'admin@hoanghochoi.com',
    role: 'SUPER_ADMIN',
  );

  @override
  bool get isInitialized => true;

  @override
  bool get isAuthenticated => true;
}

const _checkLog = FifoLogItem(
  id: 'check-1',
  type: 'FIFO_CHECK',
  query: 'SN-CHECK-001',
  result: 'Đúng FIFO',
  resultJson: <Map<String, dynamic>>[
    <String, dynamic>{
      'sku': '250403171',
      'sku_name': 'Sản phẩm kiểm thử',
      'serial_number': 'SN-CHECK-001',
      'bin': 'LK.04-A-03-a',
      'import_date': '2026-07-01',
      'fifo': 'yes',
    },
  ],
  createdAt: '2026-07-02T09:20:00.000Z',
  userName: 'Nguyễn Ngọc Lan Tâm',
  userEmail: 'lan.tam@example.com',
  storeId: 'CP62',
  storeName: 'Phong Vũ Nguyễn Kiệm',
);

const _sortLog = FifoLogItem(
  id: 'sort-1',
  type: 'FIFO_SORT',
  query: 'BIN-A12',
  result: 'Đã sắp xếp 4 sản phẩm',
  createdAt: '2026-07-02T10:10:00.000Z',
  userName: 'Nguyễn Văn Hoàng',
  userEmail: 'van.hoang@example.com',
  storeId: 'CP75',
  storeName: 'Phong Vũ Điện Biên Phủ',
);
