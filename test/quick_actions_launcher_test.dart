import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/quick_actions/data/quick_actions_repository.dart';
import 'package:phongvu_opshub/features/quick_actions/presentation/quick_actions_launcher.dart';
import 'package:phongvu_opshub/features/quick_actions/presentation/quick_actions_provider.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('quick actions menu keeps the approved seven-action order', (
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
}

class _FakeAuthProvider extends AuthProvider {
  final User _user;
  _FakeAuthProvider(this._user) : super(AuthRepository(ApiClient()));
  @override
  User? get user => _user;
}

class _FakeQuickActionsProvider extends QuickActionsProvider {
  final QuickActionsPayload _payload;
  _FakeQuickActionsProvider(this._payload)
    : super(QuickActionsRepository(ApiClient()));
  @override
  QuickActionsPayload get payload => _payload;
}
