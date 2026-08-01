import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
    expect(request.url.path, '/api/admin/api-connections/bidv');
    expect(request.headers['Authorization'], 'Bearer staff-jwt');
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
    expect(find.textContaining('Windows hoặc trình duyệt web'), findsOneWidget);
    expect(find.text('Tạo client'), findsNothing);
  });

  testWidgets('renders clients, keys and disabled master state', (
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

    expect(find.text('Quản lý kết nối API'), findsOneWidget);
    expect(find.text('OAuth client'), findsOneWidget);
    expect(find.text('Khóa OpenPGP'), findsOneWidget);
    expect(find.text('bidv_public_client_id'), findsOneWidget);
    expect(find.text('AABBCCDD'), findsOneWidget);
    expect(find.textContaining('Hạ tầng đang khóa'), findsWidgets);
    expect(find.textContaining('secret-value'), findsNothing);
  });
}

class _FakeRepository extends ApiConnectionRepository {
  _FakeRepository(this.snapshot)
    : super(ApiClient.test(MockClient((_) async => http.Response('{}', 200))));

  final ApiConnectionSnapshot snapshot;

  @override
  Future<ApiConnectionSnapshot> fetchSnapshot() async => snapshot;
}

final _snapshotJson = <String, dynamic>{
  'bankCode': 'BIDV',
  'environment': 'staging',
  'publicBaseUrl': 'https://bidv-staging.opshub.hoanghochoi.com',
  'controls': {
    'ingressRequested': false,
    'projectionRequested': false,
    'ingressMasterEnabled': false,
    'projectionMasterEnabled': false,
    'ingressEffective': false,
    'projectionEffective': false,
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
