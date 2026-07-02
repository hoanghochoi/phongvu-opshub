import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/widgets/gradient_header.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/reports/presentation/screens/report_workspace_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('Report workspace shows sales report actions by permissions', (
    tester,
  ) async {
    const user = User(
      email: 'lead@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'org-admin',
      featureAccess: {'SALES_REPORT': true, 'ADMIN_SALES_REPORTS': true},
    );

    await tester.pumpWidget(_wrap(user));
    await tester.pump();

    expect(find.byType(Scaffold), findsNothing);
    expect(find.byType(GradientHeader), findsNothing);
    expect(find.byKey(const Key('reports-workspace-header')), findsOneWidget);
    expect(find.text('Báo cáo khả dụng'), findsOneWidget);
    expect(find.text('2 báo cáo khả dụng'), findsOneWidget);
    expect(find.text('Báo cáo sale'), findsOneWidget);
    expect(find.text('Đơn chưa báo cáo và form mua/chưa mua'), findsOneWidget);
    expect(find.text('Danh sách báo cáo sale'), findsOneWidget);
    expect(find.text('Lọc danh sách và xuất file'), findsOneWidget);
  });

  testWidgets('Report workspace shows empty state without report permissions', (
    tester,
  ) async {
    const user = User(
      email: 'staff@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'org-store',
      featureAccess: {'FIFO': true},
    );

    await tester.pumpWidget(_wrap(user));
    await tester.pump();

    expect(find.byType(Scaffold), findsNothing);
    expect(find.byType(GradientHeader), findsNothing);
    expect(find.byKey(const Key('reports-empty-state')), findsOneWidget);
    expect(find.text('Chưa có báo cáo khả dụng'), findsNWidgets(2));
    expect(find.text('Báo cáo sale'), findsNothing);
  });
}

Widget _wrap(User user) {
  return ChangeNotifierProvider<AuthProvider>.value(
    value: _FakeAuthProvider(user),
    child: const MaterialApp(home: ReportWorkspaceScreen()),
  );
}

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
