import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/theme/app_colors.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/quick_actions/data/quick_actions_repository.dart';
import 'package:phongvu_opshub/features/quick_actions/presentation/quick_actions_launcher.dart';
import 'package:phongvu_opshub/features/quick_actions/presentation/quick_actions_provider.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  testWidgets('quick actions menu keeps the approved eight-action order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const user = User(
      email: 'staff@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'store-node',
      featureAccess: {
        'QUICK_ACTIONS': true,
        'QUICK_ACTION_FIFO': true,
        'QUICK_ACTION_VIETQR': true,
        'QUICK_ACTION_FOLLOW_UP': true,
        'QUICK_ACTION_SALES_REPORT': true,
        'QUICK_ACTION_APP_DOWNLOAD': true,
        'QUICK_ACTION_CHECK_IN': true,
        'QUICK_ACTION_ZALO_OA': true,
        'QUICK_ACTION_GOOGLE_MAP': true,
        'FIFO': true,
        'VIETQR': true,
        'SALES_REPORT': true,
      },
    );
    const payload = QuickActionsPayload(
      stores: [QuickActionStore(storeCode: 'HCM01', storeName: 'Showroom 1')],
      selectedStoreCode: null,
      availableActionCodes: {
        'APP_DOWNLOAD',
        'CHECK_IN',
        'ZALO_OA',
        'GOOGLE_MAP',
      },
      links: {},
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(
            value: _FakeAuthProvider(user),
          ),
          ChangeNotifierProvider<QuickActionsProvider>.value(
            value: _FakeQuickActionsProvider(payload),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: QuickActionsLauncher(
                menuAxis: Axis.horizontal,
                location: '/home',
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('quick-actions-launcher')), findsOneWidget);
    await tester.tap(find.byKey(const Key('quick-actions-launcher')));
    await tester.pump();

    expect(find.byKey(const Key('quick-actions-menu')), findsOneWidget);
    final labels = [
      'Kiểm tra FIFO',
      'VietQR',
      'Chăm sóc lại',
      'Báo cáo bán hàng',
      'Tải app',
      'Check-in',
      'Zalo OA',
      'GG Map',
    ];
    for (final label in labels) {
      expect(find.text(label), findsOneWidget);
    }
    final xPositions = labels
        .map((label) => tester.getTopLeft(find.text(label)).dx)
        .toList();
    expect(xPositions, orderedEquals([...xPositions]..sort()));
  });

  testWidgets('opens from cached QR actions without refreshing the API', (
    tester,
  ) async {
    const user = User(
      email: 'super.admin@phongvu.vn',
      role: 'SUPER_ADMIN',
      featureAccess: {'QUICK_ACTIONS': true},
    );
    const cachedPayload = QuickActionsPayload(
      stores: [QuickActionStore(storeCode: 'CP75', storeName: 'Showroom 75')],
      selectedStoreCode: null,
      availableActionCodes: {
        'APP_DOWNLOAD',
        'CHECK_IN',
        'ZALO_OA',
        'GOOGLE_MAP',
      },
      links: {},
    );
    final quickActions = _FakeQuickActionsProvider(cachedPayload);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(
            value: _FakeAuthProvider(user),
          ),
          ChangeNotifierProvider<QuickActionsProvider>.value(
            value: quickActions,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: QuickActionsLauncher(
              menuAxis: Axis.horizontal,
              location: '/home',
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('quick-actions-launcher')));
    await tester.pumpAndSettle();

    expect(quickActions.revalidateCount, 1);
    expect(quickActions.refreshCount, 0);
    expect(find.text('Tải app'), findsOneWidget);
    expect(find.text('Check-in'), findsOneWidget);
    expect(find.text('Zalo OA'), findsOneWidget);
    expect(find.text('GG Map'), findsOneWidget);
  });

  testWidgets('keeps customer QR black on a white surface in dark mode', (
    tester,
  ) async {
    const user = User(
      email: 'super.admin@phongvu.vn',
      role: 'SUPER_ADMIN',
      featureAccess: {'QUICK_ACTIONS': true, 'QUICK_ACTION_ZALO_OA': true},
    );
    const payload = QuickActionsPayload(
      stores: [
        QuickActionStore(storeCode: 'CP75', storeName: 'Phan Đăng Lưu 2'),
      ],
      selectedStoreCode: 'CP75',
      availableActionCodes: {'ZALO_OA'},
      links: {'ZALO_OA': 'https://example.com/zalo'},
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(
            value: _FakeAuthProvider(user),
          ),
          ChangeNotifierProvider<QuickActionsProvider>.value(
            value: _FakeQuickActionsProvider(payload),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: EdgeInsets.all(24),
                child: QuickActionsLauncher(
                  menuAxis: Axis.vertical,
                  location: '/home',
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('quick-actions-launcher')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zalo OA'));
    await tester.pumpAndSettle();

    final qr = tester.widget<QrImageView>(
      find.byKey(const Key('quick-action-qr-code')),
    );
    expect(qr.backgroundColor, AppColors.customerQrBackground);
    expect(qr.eyeStyle.color, AppColors.customerQrForeground);
    expect(qr.dataModuleStyle.color, AppColors.customerQrForeground);
  });
}

class _FakeAuthProvider extends AuthProvider {
  final User _user;
  _FakeAuthProvider(this._user) : super(AuthRepository(ApiClient()));
  @override
  User? get user => _user;
}

class _FakeQuickActionsProvider extends QuickActionsProvider {
  final QuickActionsPayload _payload;
  int refreshCount = 0;
  int revalidateCount = 0;

  _FakeQuickActionsProvider(this._payload)
    : super(QuickActionsRepository(ApiClient()));
  @override
  QuickActionsPayload get payload => _payload;

  @override
  Future<QuickActionsPayload?> refresh({
    String? storeCode,
    bool force = false,
  }) async {
    refreshCount += 1;
    notifyListeners();
    return _payload;
  }

  @override
  void revalidateScopeIfStale() {
    revalidateCount += 1;
  }
}
