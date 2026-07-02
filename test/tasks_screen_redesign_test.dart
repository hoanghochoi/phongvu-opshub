import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/navigation/tasks_screen.dart';
import 'package:phongvu_opshub/app/widgets/gradient_header.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('Tasks index renders permission-aware workspace actions', (
    tester,
  ) async {
    const user = User(
      email: 'staff@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'org-store-cp01',
    );

    await tester.pumpWidget(_wrapWithAuth(user, const TasksScreen()));
    await tester.pump();

    expect(find.byType(Scaffold), findsNothing);
    expect(find.byType(GradientHeader), findsNothing);
    expect(find.byKey(const Key('tasks-header')), findsOneWidget);
    expect(find.text('Tác vụ của bạn'), findsOneWidget);
    expect(find.text('1 tác vụ khả dụng'), findsOneWidget);
    expect(find.text('9 tác vụ cần thêm quyền'), findsOneWidget);
    expect(find.text('Không gian làm việc'), findsOneWidget);
    expect(find.text('Cài đặt'), findsOneWidget);
    expect(find.text('FIFO'), findsNothing);
    expect(find.text('Báo cáo'), findsNothing);
  });

  testWidgets('Tasks index shows all workspaces for super admin', (
    tester,
  ) async {
    const user = User(
      email: 'admin@phongvu.vn',
      role: 'SUPER_ADMIN',
      organizationNodeId: 'org-root',
    );

    await tester.pumpWidget(_wrapWithAuth(user, const TasksScreen()));
    await tester.pump();

    expect(find.byType(Scaffold), findsNothing);
    expect(find.byType(GradientHeader), findsNothing);
    expect(find.byKey(const Key('tasks-header')), findsOneWidget);
    expect(find.text('10 tác vụ khả dụng'), findsOneWidget);
    expect(find.textContaining('tác vụ cần thêm quyền'), findsNothing);
    expect(find.text('Quản trị'), findsOneWidget);
    expect(find.text('FIFO'), findsOneWidget);
    expect(find.text('BH / SC'), findsOneWidget);
    expect(find.text('VietQR'), findsOneWidget);
    expect(find.text('Tiền vào'), findsOneWidget);
    expect(find.text('Sao kê'), findsOneWidget);
    expect(find.text('Cấn trừ'), findsOneWidget);
    expect(find.text('Báo cáo'), findsOneWidget);
    expect(find.text('Góp ý'), findsOneWidget);
    expect(find.text('Cài đặt'), findsOneWidget);
  });
}

Widget _wrapWithAuth(User user, Widget child) {
  return ChangeNotifierProvider<AuthProvider>.value(
    value: _FakeAuthProvider(user),
    child: MaterialApp(home: child),
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
