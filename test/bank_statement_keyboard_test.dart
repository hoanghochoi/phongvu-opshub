import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/store_branch.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/bank_statement/data/bank_statement_repository.dart';
import 'package:phongvu_opshub/features/bank_statement/presentation/providers/bank_statement_provider.dart';
import 'package:phongvu_opshub/features/bank_statement/presentation/screens/bank_statement_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  testWidgets('keeps the focused mobile filter above the software keyboard', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final provider = BankStatementProvider(_KeyboardTestRepository());
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(
            value: _KeyboardTestAuthProvider(_accountingUser),
          ),
          ChangeNotifierProvider<BankStatementProvider>.value(value: provider),
        ],
        child: const MaterialApp(
          home: Scaffold(
            appBar: _KeyboardTestAppBar(),
            body: BankStatementScreen(),
            bottomNavigationBar: SizedBox(height: 68),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bộ lọc tìm kiếm'));
    await tester.pumpAndSettle();

    final contentInput = find.widgetWithText(
      TextField,
      'Nội dung chuyển khoản',
    );
    await tester.tap(contentInput);
    await tester.pump();

    tester.view.viewInsets = const FakeViewPadding(bottom: 360);
    await tester.pumpAndSettle();

    final keyboardScroll = find.byKey(
      const Key('bank-statement-mobile-scroll'),
    );
    expect(keyboardScroll, findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(contentInput).bottom,
      lessThanOrEqualTo(tester.getRect(keyboardScroll).bottom + 0.5),
    );
    expect(
      tester.widget<CustomScrollView>(keyboardScroll).keyboardDismissBehavior,
      ScrollViewKeyboardDismissBehavior.onDrag,
    );
  });
}

class _KeyboardTestAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _KeyboardTestAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(title: const Text('Sao kê'));
  }
}

class _KeyboardTestAuthProvider extends AuthProvider {
  final User currentUser;

  _KeyboardTestAuthProvider(this.currentUser)
    : super(AuthRepository(ApiClient()));

  @override
  User? get user => currentUser;
}

class _KeyboardTestRepository extends BankStatementRepository {
  _KeyboardTestRepository() : super(ApiClient());

  @override
  Future<List<StoreBranch>> fetchStores() async {
    return const [
      StoreBranch(id: 'store-1', storeId: 'CP01', storeName: 'Showroom 1'),
    ];
  }

  @override
  Future<BankStatementOrderTransferRequestPage> fetchOrderTransferRequests({
    String status = 'PENDING',
    bool allStores = false,
    List<String> storeIds = const [],
    int page = 0,
    int limit = 50,
  }) async {
    return BankStatementOrderTransferRequestPage(
      requests: const [],
      page: page,
      limit: limit,
      total: 0,
      canReview: false,
    );
  }
}

const _accountingUser = User(
  id: 'acc-keyboard-1',
  email: 'acc-keyboard@example.com',
  role: 'USER',
  storeId: 'CP01',
  workScopeType: 'STORE',
  departmentCode: 'ACC',
  featureAccess: {'BANK_STATEMENTS': true},
);
