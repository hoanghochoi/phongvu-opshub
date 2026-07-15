import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/widgets/app_combobox.dart';
import 'helpers/legacy_widget_finders.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/network/realtime_connection_manager.dart';
import 'package:phongvu_opshub/core/storage/app_storage_keys.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/store_branch.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/vietqr/data/repositories/vietqr_repository.dart';
import 'package:phongvu_opshub/features/vietqr/domain/entities/vietqr_transfer.dart';
import 'package:phongvu_opshub/features/vietqr/presentation/screens/vietqr_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLogger.instance.setUploadsEnabledForTesting(false);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  testWidgets(
    'VietQR lets super-admin choose any showroom from the full list',
    (tester) async {
      final authRepository = _FakeAuthRepository([
        const StoreBranch(
          id: 'store-62',
          storeId: 'CP62',
          storeName: 'SR CP62',
        ),
        const StoreBranch(
          id: 'store-75',
          storeId: 'CP75',
          storeName: 'SR CP75',
        ),
      ]);
      final authProvider = _FakeAuthProvider(
        const User(
          id: 'super-1',
          email: 'admin@phongvu.vn',
          role: 'SUPER_ADMIN',
          assignedStores: [],
        ),
        repository: authRepository,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: authProvider,
          child: MaterialApp(
            home: VietQrScreen(authRepository: authRepository),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('vietqr-workspace-header')), findsNothing);
      expect(find.byType(Scaffold), findsNothing);
      expect(findsLegacyGradientHeader(), findsNothing);
      expect(find.byType(AppCombobox<String>), findsOneWidget);
      expect(find.text('CP62 - SR CP62'), findsOneWidget);

      final showroomCombobox = find.byType(AppCombobox<String>);
      final showroomInput = find.descendant(
        of: showroomCombobox,
        matching: find.byType(TextField),
      );
      await tester.tap(showroomInput);
      await tester.pumpAndSettle();
      await tester.enterText(showroomInput, 'CP75');
      await tester.pumpAndSettle();

      expect(find.text('CP75 - SR CP75'), findsOneWidget);

      await tester.tap(find.text('CP75 - SR CP75').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(1), 'DH-001');
      await tester.pumpAndSettle();

      expect(find.text('DH-001 CP75 BOT'), findsOneWidget);
    },
  );

  testWidgets('VietQR desktop shows history and reopens a still-valid QR', (
    tester,
  ) async {
    final createdAt = DateTime.now().toUtc().subtract(
      const Duration(minutes: 5),
    );
    final historyKey = AppStorageKeys.shared('vietqr_history.user-1');
    SharedPreferences.setMockInitialValues({
      historyKey: jsonEncode([
        {
          'storeCode': 'CP62',
          'transfer': {
            'id': 'payment-1',
            'bankBin': '970436',
            'bankName': 'Vietcombank',
            'accountNumber': '123456789',
            'accountName': 'PHONG VU',
            'amount': 150000,
            'transferContent': 'DH-001 CP62 BOT',
            'qrPayload': 'payload',
            'status': 'PENDING',
            'createdAt': createdAt.toIso8601String(),
            'qrBrand': {
              'key': 'phongvu',
              'title': 'Phong Vũ',
              'logoKey': 'phongvu',
              'logoAsset': 'assets/icon/source/app_icon_master.png',
            },
          },
        },
      ]),
    });
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authProvider = _FakeAuthProvider(
      const User(
        id: 'user-1',
        email: 'staff@phongvu.vn',
        role: 'USER',
        assignedStores: [
          StoreBranch(id: 'store-62', storeId: 'CP62', storeName: 'SR CP62'),
        ],
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: const MaterialApp(home: VietQrScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lịch sử tạo QR'), findsOneWidget);
    expect(find.text('Thông tin chuyển khoản'), findsOneWidget);

    final formTopLeft = tester.getTopLeft(find.text('Thông tin chuyển khoản'));
    final historyTopLeft = tester.getTopLeft(find.text('Lịch sử tạo QR'));
    expect(historyTopLeft.dy, lessThan(formTopLeft.dy + 120));
    expect(historyTopLeft.dx, greaterThanOrEqualTo(formTopLeft.dx));

    expect(find.text('Còn hạn'), findsOneWidget);

    await tester.tap(find.text('Showroom CP62').last);
    await tester.pumpAndSettle();

    expect(find.text('Kiểm tra ngay'), findsOneWidget);
    expect(find.text('Tải ảnh QR'), findsOneWidget);
  });

  testWidgets('VietQR uses filtered debounced realtime v2 and one-shot sync', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final createdAt = DateTime.now().toUtc().subtract(
      const Duration(minutes: 5),
    );
    SharedPreferences.setMockInitialValues({
      AppStorageKeys.shared('vietqr_history.user-1'): jsonEncode([
        {
          'storeCode': 'CP62',
          'transfer': {
            'id': 'payment-1',
            'bankBin': '970436',
            'bankName': 'Vietcombank',
            'accountNumber': '123456789',
            'accountName': 'PHONG VU',
            'amount': 150000,
            'transferContent': 'DH-001 CP62 BOT',
            'qrPayload': 'payload',
            'status': 'PENDING',
            'createdAt': createdAt.toIso8601String(),
            'qrBrand': {
              'key': 'phongvu',
              'title': 'Phong Vũ',
              'logoKey': 'phongvu',
              'logoAsset': 'assets/icon/source/app_icon_master.png',
            },
          },
        },
        {
          'storeCode': 'CP75',
          'transfer': {
            'id': 'payment-2',
            'bankBin': '970436',
            'bankName': 'Vietcombank',
            'accountNumber': '123456789',
            'accountName': 'PHONG VU',
            'amount': 200000,
            'transferContent': 'DH-002 CP75 BOT',
            'qrPayload': 'payload-2',
            'status': 'PENDING',
            'createdAt': createdAt.toIso8601String(),
            'qrBrand': {
              'key': 'phongvu',
              'title': 'Phong Vũ',
              'logoKey': 'phongvu',
              'logoAsset': 'assets/icon/source/app_icon_master.png',
            },
          },
        },
      ]),
    });
    final realtime = _FakeRealtimeClient();
    final repository = _FakeVietQrRepository();
    final authProvider = _FakeAuthProvider(
      const User(
        id: 'user-1',
        email: 'staff@phongvu.vn',
        role: 'USER',
        assignedStores: [
          StoreBranch(id: 'store-62', storeId: 'CP62', storeName: 'SR CP62'),
        ],
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: MaterialApp(
          home: VietQrScreen(
            repository: repository,
            realtimeClient: realtime,
            realtimeDebounce: const Duration(milliseconds: 20),
            realtimeMaxWait: const Duration(milliseconds: 80),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Showroom CP75'));
    await tester.tap(find.text('Showroom CP75'));
    await tester.pumpAndSettle();

    realtime.requestSync(RealtimeSyncReason.reconnected);
    await tester.pump();
    await tester.pump();
    expect(repository.confirmCalls, 1);

    realtime.addEvent(_paymentEnvelope(id: 'wrong-store', storeCode: 'CP75'));
    realtime.addEvent(_paymentEnvelope(id: 'payment-match', storeCode: 'CP62'));
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.text('Đã nhận thanh toán'), findsNothing);
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();
    expect(find.text('Đã nhận thanh toán'), findsWidgets);
    expect(repository.confirmCalls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await realtime.dispose();
  });
}

RealtimeEnvelope _paymentEnvelope({
  required String id,
  required String storeCode,
}) {
  return RealtimeEnvelope(
    version: 2,
    kind: 'PAYMENT_NOTIFICATION',
    id: id,
    topic: 'payment.transactions',
    sequence: id.hashCode.abs(),
    timestamp: DateTime.now(),
    data: {
      'storeCode': storeCode,
      'amount': 150000,
      'transactionContent': 'THANH TOAN DH-001 CP62 BOT',
      'transactionId': 'transaction-1',
    },
  );
}

class _FakeAuthProvider extends AuthProvider {
  final User currentUser;

  _FakeAuthProvider(this.currentUser, {AuthRepository? repository})
    : super(repository ?? _FakeAuthRepository(const []));

  @override
  User? get user => currentUser;
}

class _FakeAuthRepository extends AuthRepository {
  final List<StoreBranch> stores;

  _FakeAuthRepository(this.stores) : super(ApiClient());

  @override
  Future<List<StoreBranch>> getStores({String? query}) async {
    return stores;
  }
}

class _FakeVietQrRepository extends VietQrRepository {
  _FakeVietQrRepository() : super(ApiClient());

  int confirmCalls = 0;

  @override
  Future<VietQrPaymentConfirmation> confirmPayment(String paymentId) async {
    confirmCalls += 1;
    return VietQrPaymentConfirmation(
      id: paymentId,
      status: 'PENDING',
      confirmed: false,
      reason: 'NOT_FOUND',
    );
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
