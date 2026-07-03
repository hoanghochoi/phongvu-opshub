import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/legacy_widget_finders.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/fifo/presentation/screens/fifo_menu_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('FIFO menu renders content-only workspace actions', (
    tester,
  ) async {
    const user = User(
      email: 'fifo.admin@phongvu.vn',
      role: 'ADMIN',
      organizationNodeId: 'org-store-cp01',
      featureAccess: {'FIFO': true, 'FIFO_IMPORT': true},
    );

    await tester.pumpWidget(_wrapWithAuth(user, const FifoMenuScreen()));
    await tester.pump();

    expect(find.byType(Scaffold), findsNothing);
    expect(findsLegacyGradientHeader(), findsNothing);
    expect(find.byKey(const Key('fifo-menu-header')), findsNothing);
    expect(find.text('FIFO'), findsNothing);
    expect(find.text('4 tác vụ khả dụng'), findsNothing);
    expect(find.text('Chức năng FIFO'), findsOneWidget);
    expect(find.text('Kiểm tra FIFO'), findsOneWidget);
    expect(find.text('Sắp xếp FIFO'), findsOneWidget);
    expect(find.text('Cập nhật tồn kho'), findsOneWidget);
    expect(find.text('Lịch sử FIFO'), findsOneWidget);
  });

  testWidgets('FIFO menu keeps empty state content-only without permissions', (
    tester,
  ) async {
    const user = User(
      email: 'staff@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'org-store-cp01',
    );

    await tester.pumpWidget(_wrapWithAuth(user, const FifoMenuScreen()));
    await tester.pump();

    expect(find.byType(Scaffold), findsNothing);
    expect(findsLegacyGradientHeader(), findsNothing);
    expect(find.byKey(const Key('fifo-menu-header')), findsNothing);
    expect(find.byKey(const Key('fifo-menu-empty-state')), findsOneWidget);
    expect(find.text('0 tác vụ khả dụng'), findsNothing);
    expect(find.text('4 tác vụ cần thêm quyền'), findsNothing);
    expect(find.text('Chưa có tính năng FIFO'), findsOneWidget);
    expect(
      find.textContaining('cấp quyền kiểm tra, sắp xếp hoặc import'),
      findsOneWidget,
    );
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
