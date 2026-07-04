import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/widgets/app_feature_grid.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/operations/presentation/screens/operations_screen.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  testWidgets('Góp ý is the last visible Operations action', (tester) async {
    await _pumpOperations(
      tester,
      const User(
        id: 'staff-1',
        email: 'staff@phongvu.vn',
        role: 'USER',
        organizationNodeId: 'org-store-cp01',
        featureAccess: {
          'FIFO': true,
          'WARRANTY': true,
          'VIETQR': true,
          'BANK_STATEMENTS': true,
          'FEEDBACK': true,
        },
      ),
    );

    final titles = tester
        .widgetList<AppFeatureTile>(find.byType(AppFeatureTile))
        .map((tile) => tile.action.title)
        .toList(growable: false);

    expect(find.byKey(const Key('operations-feature-section')), findsOneWidget);
    expect(
      titles,
      containsAll(<String>['FIFO', 'Bảo hành', 'VietQR', 'Sao kê']),
    );
    expect(titles.last, 'Góp ý');
    expect(titles.where((title) => title == 'Góp ý'), hasLength(1));
  });

  testWidgets(
    'Operations shows Báo cáo for admin sales report access without Quản trị',
    (tester) async {
      await _pumpOperations(
        tester,
        const User(
          id: 'lead-1',
          email: 'lead@phongvu.vn',
          role: 'USER',
          organizationNodeId: 'org-area-hcm',
          featureAccess: {'ADMIN_SALES_REPORTS': true},
        ),
      );

      final titles = tester
          .widgetList<AppFeatureTile>(find.byType(AppFeatureTile))
          .map((tile) => tile.action.title)
          .toList(growable: false);

      expect(titles, contains('Báo cáo'));
      expect(titles, isNot(contains('Quản trị')));
    },
  );

  testWidgets(
    'Operations shows shared empty state when no workspace is available',
    (tester) async {
      await _pumpOperations(
        tester,
        const User(
          id: 'staff-empty',
          email: 'staff.empty@phongvu.vn',
          role: 'USER',
          organizationNodeId: 'org-store-cp01',
        ),
      );

      expect(find.byKey(const Key('operations-empty-state')), findsOneWidget);
      expect(find.byType(AppFeatureTile), findsNothing);
      expect(find.text('Chưa có công cụ khả dụng'), findsOneWidget);
      expect(
        find.text('Vui lòng liên hệ quản lý để kiểm tra phân quyền truy cập.'),
        findsOneWidget,
      );
    },
  );
}

Future<void> _pumpOperations(WidgetTester tester, User user) async {
  final authProvider = _FakeAuthProvider(user);

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>.value(
      value: authProvider,
      child: const MaterialApp(home: OperationsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeAuthProvider extends AuthProvider {
  final User currentUser;

  _FakeAuthProvider(this.currentUser) : super(AuthRepository(ApiClient()));

  @override
  User? get user => currentUser;
}
