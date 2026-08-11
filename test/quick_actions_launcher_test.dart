import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:phongvu_opshub/app/theme/app_colors.dart';
import 'package:phongvu_opshub/app/theme/app_radius.dart';
import 'package:phongvu_opshub/app/theme/app_theme.dart';
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
  testWidgets('unavailable Windows launcher preserves approved FAB geometry', (
    tester,
  ) async {
    const user = User(email: 'staff@phongvu.vn', role: 'USER');
    const payload = QuickActionsPayload(
      stores: [],
      selectedStoreCode: null,
      availableActionCodes: {},
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
            body: QuickActionsLauncher(
              menuAxis: Axis.vertical,
              location: '/home',
              visibleWhenUnavailable: true,
            ),
          ),
        ),
      ),
    );

    final launcher = find.byKey(
      const Key('quick-actions-launcher-unavailable'),
    );
    expect(tester.getSize(launcher), const Size.square(64));
    expect(find.byTooltip('Chưa có thao tác nhanh khả dụng'), findsOneWidget);
    final surface = tester.widget<Material>(
      find.byKey(const Key('quick-actions-launcher-surface')),
    );
    expect(surface.shape, isA<CircleBorder>());
    final icon = tester.widget<Icon>(
      find.byIcon(PhosphorIconsRegular.lightning),
    );
    expect(icon.size, 24);
    expect(find.byKey(const Key('quick-actions-menu')), findsNothing);
  });

  testWidgets('compact launcher matches approved light geometry and states', (
    tester,
  ) async {
    await _pumpCompactLauncher(tester, AppTheme.lightTheme);

    final launcher = find.byKey(const Key('quick-actions-launcher'));
    expect(tester.getSize(launcher), const Size.square(48));
    expect(find.byTooltip('Thao tác nhanh'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Mở Thao tác nhanh'), findsOneWidget);
    semantics.dispose();

    final surface = tester.widget<Material>(
      find.byKey(const Key('quick-actions-launcher-surface')),
    );
    expect(surface.color, AppColors.transparent);
    expect(surface.elevation, 0);
    expect(surface.shape, isA<RoundedRectangleBorder>());
    expect(
      (surface.shape! as RoundedRectangleBorder).borderRadius,
      AppRadius.allXl,
    );
    final icon = tester.widget<Icon>(
      find.byIcon(PhosphorIconsRegular.lightning),
    );
    expect(icon.size, 20);
    expect(icon.color, AppColors.surface);

    var decoration = _launcherDecoration(tester);
    expect(decoration.color, AppColors.primary500);
    expect(decoration.borderRadius, AppRadius.allXl);
    expect(decoration.boxShadow, hasLength(1));
    final shadow = decoration.boxShadow!.single;
    expect(shadow.color, const Color.fromRGBO(8, 18, 56, 0.2));
    expect(shadow.offset, const Offset(0, 8));
    expect(shadow.blurRadius, 18);
    expect(shadow.spreadRadius, -4);

    final gesture = await tester.startGesture(tester.getCenter(launcher));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_launcherDecoration(tester).color, AppColors.primary700);
    await gesture.up();
    await tester.pump();
    expect(find.byKey(const Key('quick-actions-menu')), findsOneWidget);
    expect(_launcherDecoration(tester).color, AppColors.primary700);

    await tester.tapAt(const Offset(2, 2));
    await tester.pump();
    expect(find.byKey(const Key('quick-actions-menu')), findsNothing);

    final focus = tester.widget<Focus>(
      find.byKey(const Key('quick-actions-launcher-focus')),
    );
    focus.focusNode!.requestFocus();
    await tester.pump();
    decoration = _launcherDecoration(tester);
    final border = decoration.border! as Border;
    expect(border.top.color, AppColors.focus);
    expect(border.top.width, 2);
    expect(border.top.strokeAlign, BorderSide.strokeAlignOutside);
  });

  testWidgets('compact launcher resolves approved dark semantic states', (
    tester,
  ) async {
    await _pumpCompactLauncher(tester, AppTheme.darkTheme);

    final launcher = find.byKey(const Key('quick-actions-launcher'));
    expect(_launcherDecoration(tester).color, AppColors.darkPrimary);
    expect(
      tester.widget<Icon>(find.byIcon(PhosphorIconsRegular.lightning)).color,
      AppColors.surface,
    );

    final gesture = await tester.startGesture(tester.getCenter(launcher));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_launcherDecoration(tester).color, AppColors.darkPrimaryPressed);
    await gesture.cancel();
    await tester.pump();

    final focus = tester.widget<Focus>(
      find.byKey(const Key('quick-actions-launcher-focus')),
    );
    focus.focusNode!.requestFocus();
    await tester.pump();
    final border = _launcherDecoration(tester).border! as Border;
    expect(border.top.color, AppColors.darkInfo);
    expect(border.top.width, 2);
  });

  testWidgets('quick actions menu wraps eight actions into visible rows', (
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
    final actionCodes = [
      'FIFO',
      'VIETQR',
      'FOLLOW_UP',
      'SALES_REPORT',
      'APP_DOWNLOAD',
      'CHECK_IN',
      'ZALO_OA',
      'GOOGLE_MAP',
    ];
    final positions = actionCodes
        .map(
          (code) => tester.getTopLeft(
            find.byKey(Key('quick-action-grid-item-$code')),
          ),
        )
        .toList();
    final rowTops = positions.map((position) => position.dy.round()).toSet();
    expect(rowTops, hasLength(2));
    expect(positions.take(4).map((position) => position.dy.round()).toSet(), {
      positions.first.dy.round(),
    });
    expect(positions.skip(4).map((position) => position.dy.round()).toSet(), {
      positions[4].dy.round(),
    });
    expect(
      find.descendant(
        of: find.byKey(const Key('quick-actions-menu')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        ),
      ),
      findsNothing,
    );
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

Future<void> _pumpCompactLauncher(WidgetTester tester, ThemeData theme) async {
  const user = User(
    email: 'staff@phongvu.vn',
    role: 'USER',
    organizationNodeId: 'store-node',
    featureAccess: {
      'QUICK_ACTIONS': true,
      'QUICK_ACTION_FIFO': true,
      'FIFO': true,
    },
  );
  const payload = QuickActionsPayload(
    stores: [QuickActionStore(storeCode: 'HCM01', storeName: 'Showroom 1')],
    selectedStoreCode: null,
    availableActionCodes: {},
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
      child: MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: Center(
            child: QuickActionsLauncher(
              menuAxis: Axis.horizontal,
              location: '/home',
              buttonSize: 48,
              elevation: 0,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

BoxDecoration _launcherDecoration(WidgetTester tester) {
  return tester
          .widget<DecoratedBox>(
            find.byKey(const Key('quick-actions-launcher-decoration')),
          )
          .decoration
      as BoxDecoration;
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
