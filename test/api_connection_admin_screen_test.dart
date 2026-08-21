import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phongvu_opshub/app/widgets/app_buttons.dart';
import 'package:phongvu_opshub/core/network/api_exception.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/admin/data/api_connection_repository.dart';
import 'package:phongvu_opshub/features/admin/domain/api_connection.dart';
import 'package:phongvu_opshub/features/admin/presentation/screens/api_connection_admin_screen.dart';

void main() {
  test('API connection model parses a redacted snapshot', () {
    final snapshot = ApiConnectionSnapshot.fromJson(_snapshotJson);
    expect(snapshot.bankCode, 'BIDV');
    expect(snapshot.clients.single.clientId, 'bidv_public_client_id');
    expect(snapshot.keys.single.fingerprint, 'AABBCCDD');
    expect(snapshot.controls.ingressEffective, false);
    expect(jsonEncode(_snapshotJson), isNot(contains('clientSecret')));
    expect(jsonEncode(_snapshotJson), isNot(contains('privateKey')));
  });

  test(
    'API connection model parses the three operating modes and readiness',
    () {
      final json = Map<String, dynamic>.from(_snapshotJson)
        ..['controls'] = <String, dynamic>{
          'operatingMode': 'LIVE',
          'effectiveMode': 'LIVE',
          'ingressRequested': true,
          'projectionRequested': true,
          'ingressEffective': true,
          'projectionEffective': true,
          'readiness': {
            'infrastructure': true,
            'kek': true,
            'client': true,
            'openPgpKey': true,
          },
          'blockers': <String>[],
          'pendingProjectionCount': 3,
          'version': 7,
        };
      final controls = ApiConnectionSnapshot.fromJson(json).controls;

      expect(controls.operatingMode, ApiOperatingMode.live);
      expect(controls.effectiveMode, ApiOperatingMode.live);
      expect(controls.readiness.allReady, isTrue);
      expect(controls.pendingProjectionCount, 3);
      expect(controls.hasPendingProjection, isTrue);
    },
  );

  test('repository uses the dedicated admin endpoint', () async {
    late http.Request request;
    final client = ApiClient.test(
      MockClient((incoming) async {
        request = incoming;
        return http.Response(jsonEncode(_snapshotJson), 200);
      }),
    )..setAuthToken('staff-jwt');
    final repository = ApiConnectionRepository(client);

    final snapshot = await repository.fetchSnapshot();
    expect(snapshot.environment, 'staging');
    expect(request.url.path, '/v1/admin/api-connections/bidv');
    expect(request.headers['Authorization'], 'Bearer staff-jwt');
  });

  test('repository sends operating mode with optimistic version', () async {
    late http.Request request;
    final client = ApiClient.test(
      MockClient((incoming) async {
        request = incoming;
        return http.Response(jsonEncode(_snapshotJson), 200);
      }),
    );
    final repository = ApiConnectionRepository(client);

    await repository.updateOperatingMode(
      mode: ApiOperatingMode.live,
      expectedVersion: 9,
    );

    expect(request.url.path, '/v1/admin/api-connections/bidv/controls');
    expect(jsonDecode(request.body), {
      'operatingMode': 'LIVE',
      'expectedVersion': 9,
    });
  });

  testWidgets('unsupported platforms show actionable guidance', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ApiConnectionAdminScreen(platformSupported: false),
        ),
      ),
    );
    expect(find.text('Thiết bị chưa hỗ trợ quản lý kết nối'), findsOneWidget);
    expect(
      find.text('Vui lòng dùng OpsHub trên Windows hoặc Web để tiếp tục.'),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const Key('api-connection-unsupported-card'))),
      const Size(752, 236),
    );
    expect(find.text('Tạo client'), findsNothing);
  });

  testWidgets('unsupported mobile layout keeps the Figma state geometry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ApiConnectionAdminScreen(platformSupported: false),
        ),
      ),
    );

    final card = find.byKey(const Key('api-connection-unsupported-card'));
    expect(tester.getSize(card).height, greaterThanOrEqualTo(236));
    expect(tester.getSize(card).width, 343);
  });

  testWidgets('wide supported content uses the Figma 24px route gutter', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1190,
            child: ApiConnectionAdminScreen(
              platformSupported: true,
              repository: _FakeRepository(
                ApiConnectionSnapshot.fromJson(_snapshotJson),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const Key('api-connection-content'))).width,
      1142,
    );
    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey<String>('api-connection-client-card-client-row-1'),
            ),
          )
          .height,
      260,
    );
    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey<String>('api-connection-key-card-key-row-1'),
            ),
          )
          .height,
      292,
    );
    expect(
      tester
          .getSize(find.byKey(const Key('api-connection-controls-card')))
          .height,
      470,
    );
  });

  testWidgets('empty supported state uses the approved base card geometry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final emptySnapshot = Map<String, dynamic>.from(_snapshotJson)
      ..['clients'] = <dynamic>[]
      ..['keys'] = <dynamic>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1190,
            child: ApiConnectionAdminScreen(
              platformSupported: true,
              repository: _FakeRepository(
                ApiConnectionSnapshot.fromJson(emptySnapshot),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kết nối BIDV'), findsOneWidget);
    expect(find.text('Khóa OpenPGP'), findsOneWidget);
    expect(find.text('Chưa có khóa hoạt động'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('api-connection-header-card'))),
      const Size(1142, 168),
    );
    expect(
      tester.getSize(find.byKey(const Key('api-connection-controls-card'))),
      const Size(1142, 470),
    );
    expect(
      tester.getSize(
        find.byKey(const Key('api-connection-key-management-card')),
      ),
      const Size(1142, 220),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('supported Web compact and medium lanes keep approved gutters', (
    tester,
  ) async {
    final snapshot = ApiConnectionSnapshot.fromJson(_snapshotJson);
    final repository = _FakeRepository(snapshot);

    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 375,
            child: ApiConnectionAdminScreen(
              platformSupported: true,
              repository: repository,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('api-connection-content'))).width,
      343,
    );

    tester.view.physicalSize = const Size(834, 1112);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 746,
            child: ApiConnectionAdminScreen(
              platformSupported: true,
              repository: repository,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('api-connection-content'))).width,
      714,
    );
    expect(find.textContaining('bidv_public_client_id'), findsOneWidget);
    expect(find.textContaining('AABBCCDD'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders clients, keys and three operating modes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApiConnectionAdminScreen(
            platformSupported: true,
            repository: _FakeRepository(
              ApiConnectionSnapshot.fromJson(_snapshotJson),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('OAuth client hoạt động'), findsOneWidget);
    expect(find.text('Khóa OpenPGP hoạt động'), findsOneWidget);
    expect(find.textContaining('bidv_public_client_id'), findsOneWidget);
    expect(find.textContaining('AABBCCDD'), findsOneWidget);
    expect(find.text('Dừng'), findsOneWidget);
    expect(find.text('UAT — Chỉ tiếp nhận'), findsOneWidget);
    expect(find.text('Vận hành chính thức'), findsOneWidget);
    expect(find.text('Nhận giao dịch, chưa tạo Tiền vào.'), findsOneWidget);
    expect(find.text('Nhận giao dịch và tạo Tiền vào.'), findsOneWidget);
    expect(find.textContaining('secret-value'), findsNothing);
  });

  testWidgets('compact operating mode card stacks options without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApiConnectionAdminScreen(
            platformSupported: true,
            repository: _FakeRepository(
              ApiConnectionSnapshot.fromJson(_snapshotJson),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const Key('api-connection-controls-card'))),
      const Size(343, 704),
    );
    expect(
      tester.getSize(find.byKey(const Key('api-connection-mode-options'))),
      const Size(311, 274),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('medium operating mode card keeps vertical options', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(834, 1112);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 746,
            child: ApiConnectionAdminScreen(
              platformSupported: true,
              repository: _FakeRepository(
                ApiConnectionSnapshot.fromJson(_snapshotJson),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const Key('api-connection-mode-options'))),
      const Size(682, 274),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded operating mode card matches the approved 960px frame', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(992, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApiConnectionAdminScreen(
            platformSupported: true,
            repository: _FakeRepository(
              ApiConnectionSnapshot.fromJson(_snapshotJson),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const Key('api-connection-controls-card'))),
      const Size(960, 470),
    );
    expect(
      tester.getSize(find.byKey(const Key('api-connection-mode-options'))),
      const Size(928, 86),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading and failure states use the approved compact card path', (
    tester,
  ) async {
    final deferred = _DeferredRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApiConnectionAdminScreen(
            platformSupported: true,
            repository: deferred,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const Key('api-connection-loading-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('api-connection-loading-skeleton-0')),
      findsOneWidget,
    );

    deferred.complete(ApiConnectionSnapshot.fromJson(_snapshotJson));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('api-connection-content')), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApiConnectionAdminScreen(
            key: const Key('failure-state'),
            platformSupported: true,
            repository: _FailingRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('api-connection-failure-card')),
      findsOneWidget,
    );
    expect(
      find.text('Chưa tải được cấu hình kết nối. Vui lòng thử lại.'),
      findsOneWidget,
    );
    expect(find.text('Thử lại'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('live selection shows the pending projection confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final json = Map<String, dynamic>.from(_snapshotJson)
      ..['controls'] = <String, dynamic>{
        ...(_snapshotJson['controls'] as Map<String, dynamic>),
        'pendingProjectionCount': 12,
      };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApiConnectionAdminScreen(
            platformSupported: true,
            repository: _FakeRepository(ApiConnectionSnapshot.fromJson(json)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final liveOption = find.byKey(const ValueKey('api-connection-mode-LIVE'));
    await tester.ensureVisible(liveOption);
    await tester.tap(liveOption);
    await tester.pump();

    expect(find.text('Có 12 giao dịch chưa tạo Tiền vào.'), findsOneWidget);
    expect(
      find.text('Bật chính thức sẽ xử lý các giao dịch đủ điều kiện này.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('emergency hard-disable renders a safe disabled state', (
    tester,
  ) async {
    final json = Map<String, dynamic>.from(_snapshotJson)
      ..['controls'] = <String, dynamic>{
        ...(_snapshotJson['controls'] as Map<String, dynamic>),
        'emergencyDisabled': true,
      };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApiConnectionAdminScreen(
            platformSupported: true,
            repository: _FakeRepository(ApiConnectionSnapshot.fromJson(json)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Kênh kết nối đang được nền tảng tạm dừng. Liên hệ kỹ thuật.'),
      findsOneWidget,
    );
    expect(find.text('Tất cả trạng thái đang tạm dừng.'), findsOneWidget);
    expect(
      tester
          .widget<AppPrimaryButton>(
            find.descendant(
              of: find.byKey(const Key('api-connection-save-mode')),
              matching: find.byType(AppPrimaryButton),
            ),
          )
          .onPressed,
      isNull,
    );
  });
}

class _FakeRepository extends ApiConnectionRepository {
  _FakeRepository(this.snapshot)
    : super(ApiClient.test(MockClient((_) async => http.Response('{}', 200))));

  final ApiConnectionSnapshot snapshot;

  ApiOperatingMode? updatedMode;

  @override
  Future<ApiConnectionSnapshot> fetchSnapshot() async => snapshot;

  @override
  Future<ApiConnectionSnapshot> updateOperatingMode({
    required ApiOperatingMode mode,
    required int expectedVersion,
  }) async {
    updatedMode = mode;
    return snapshot;
  }
}

class _DeferredRepository extends _FakeRepository {
  _DeferredRepository() : super(ApiConnectionSnapshot.fromJson(_snapshotJson));

  final Completer<ApiConnectionSnapshot> _completer =
      Completer<ApiConnectionSnapshot>();

  void complete(ApiConnectionSnapshot snapshot) =>
      _completer.complete(snapshot);

  @override
  Future<ApiConnectionSnapshot> fetchSnapshot() => _completer.future;
}

class _FailingRepository extends _FakeRepository {
  _FailingRepository() : super(ApiConnectionSnapshot.fromJson(_snapshotJson));

  @override
  Future<ApiConnectionSnapshot> fetchSnapshot() async {
    throw ApiException('backend detail must stay hidden', 503);
  }
}

final _snapshotJson = <String, dynamic>{
  'bankCode': 'BIDV',
  'environment': 'staging',
  'publicBaseUrl': 'https://api-staging.phongvu.work/v1/bidv',
  'controls': {
    'ingressRequested': false,
    'projectionRequested': false,
    'ingressMasterEnabled': true,
    'projectionMasterEnabled': true,
    'ingressEffective': false,
    'projectionEffective': false,
    'emergencyDisabled': false,
    'readiness': {
      'infrastructure': true,
      'kek': true,
      'client': true,
      'openPgpKey': true,
    },
    'blockers': <dynamic>[],
    'pendingProjectionCount': 0,
    'version': 1,
    'updatedAt': '2026-07-30T00:00:00.000Z',
  },
  'clients': [
    {
      'id': 'client-row-1',
      'displayName': 'BIDV UAT',
      'clientId': 'bidv_public_client_id',
      'scope': 'balance-changes:write',
      'status': 'ACTIVE',
      'version': 1,
      'activatedAt': '2026-07-30T00:00:00.000Z',
    },
  ],
  'keys': [
    {
      'id': 'key-row-1',
      'displayName': 'BIDV UAT',
      'fingerprint': 'AABBCCDD',
      'algorithm': 'Ed25519+X25519',
      'status': 'ACTIVE',
      'version': 1,
      'activatedAt': '2026-07-30T00:00:00.000Z',
    },
  ],
  'audits': <dynamic>[],
};
