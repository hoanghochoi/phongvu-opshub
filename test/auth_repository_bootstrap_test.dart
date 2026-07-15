import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';

void main() {
  test('bootstrap 200 parses access maps and sends If-None-Match', () async {
    late http.Request captured;
    final apiClient = ApiClient.test(
      MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'schemaVersion': 1,
            'generatedAt': '2026-07-15T08:00:00.000Z',
            'version': 'version-2',
            'user': {
              'id': 'user-1',
              'email': 'staff@phongvu.vn',
              'role': 'USER',
            },
            'featureAccess': {'HOME': true, 'FIFO': false},
            'policyAccess': {'BANK_STATEMENT_ALL_SCOPE': true},
            'capabilities': {
              'conditionalGet': true,
              'realtimeV2Topics': ['home.summary', 'access.changed'],
            },
          }),
          200,
          headers: {'etag': '"version-2"'},
        );
      }),
    )..setAuthToken('jwt-token');

    final result = await AuthRepository(
      apiClient,
    ).getBootstrap(ifNoneMatch: '"version-1"');

    expect(captured.method, 'GET');
    expect(captured.url.path, endsWith('/auth/bootstrap'));
    expect(captured.headers['If-None-Match'], '"version-1"');
    expect(captured.headers['Authorization'], 'Bearer jwt-token');
    expect(result.isNotModified, isFalse);
    expect(result.etag, '"version-2"');
    expect(result.data?.user.email, 'staff@phongvu.vn');
    expect(result.data?.featureAccess, {'HOME': true, 'FIFO': false});
    expect(result.data?.policyAccess['BANK_STATEMENT_ALL_SCOPE'], isTrue);
    expect(result.data?.capabilities.realtimeV2Topics, [
      'home.summary',
      'access.changed',
    ]);
  });

  test('bootstrap 304 returns metadata without decoding a body', () async {
    final apiClient = ApiClient.test(
      MockClient(
        (_) async => http.Response('', 304, headers: {'etag': '"version-1"'}),
      ),
    );

    final result = await AuthRepository(
      apiClient,
    ).getBootstrap(ifNoneMatch: '"version-1"');

    expect(result.isNotModified, isTrue);
    expect(result.data, isNull);
    expect(result.etag, '"version-1"');
  });
}
