import 'dart:convert';
import 'dart:io';

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

  test('shared backend bootstrap v1 fixture parses in Flutter', () async {
    final fixture = await File(
      'test/fixtures/auth_bootstrap_v1.json',
    ).readAsString();
    final apiClient = ApiClient.test(
      MockClient(
        (_) async => http.Response(
          fixture,
          200,
          headers: {'etag': '"contract-version"'},
        ),
      ),
    )..setAuthToken('jwt-token');

    final result = await AuthRepository(
      apiClient,
    ).getBootstrap(fallbackEmail: 'staff@phongvu-shop.vn');

    expect(result.data?.user.id, 'user-1');
    expect(result.data?.user.email, 'staff@phongvu-shop.vn');
    expect(result.data?.featureAccess['HOME_DASHBOARD'], isTrue);
    expect(result.data?.policyAccess['ADMIN_SETTINGS'], isFalse);
  });

  test(
    'bootstrap v1 without email uses the authenticated saved identity',
    () async {
      final apiClient = ApiClient.test(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'schemaVersion': 1,
              'generatedAt': '2026-07-15T08:00:00.000Z',
              'version': 'legacy-contract',
              'user': {'id': 'user-1', 'role': 'USER'},
              'featureAccess': {'HOME': true},
              'policyAccess': <String, bool>{},
              'capabilities': {
                'conditionalGet': true,
                'realtimeV2Topics': <String>[],
              },
            }),
            200,
          ),
        ),
      )..setAuthToken('jwt-token');

      final result = await AuthRepository(
        apiClient,
      ).getBootstrap(fallbackEmail: 'staff@phongvu.vn');

      expect(result.data?.user.email, 'staff@phongvu.vn');
      expect(result.data?.featureAccess['HOME'], isTrue);
    },
  );

  test(
    'bootstrap rejects an identity mismatch with contract diagnostics',
    () async {
      final apiClient = ApiClient.test(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'schemaVersion': 1,
              'generatedAt': '2026-07-15T08:00:00.000Z',
              'version': 'mismatched-contract',
              'user': {'id': 'user-2', 'email': 'other@phongvu.vn'},
              'featureAccess': <String, bool>{},
              'policyAccess': <String, bool>{},
              'capabilities': {
                'conditionalGet': true,
                'realtimeV2Topics': <String>[],
              },
            }),
            200,
          ),
        ),
      )..setAuthToken('jwt-token');

      await expectLater(
        AuthRepository(
          apiClient,
        ).getBootstrap(fallbackEmail: 'staff@phongvu.vn'),
        throwsA(
          isA<AuthBootstrapContractException>()
              .having((error) => error.reason, 'reason', 'identity_mismatch')
              .having((error) => error.statusCode, 'statusCode', 200)
              .having((error) => error.hasUserEmail, 'hasUserEmail', isTrue),
        ),
      );
    },
  );

  test('malformed bootstrap reports sanitized contract metadata', () async {
    final apiClient = ApiClient.test(
      MockClient((_) async => http.Response('{not-json', 200)),
    )..setAuthToken('jwt-token');

    await expectLater(
      AuthRepository(apiClient).getBootstrap(fallbackEmail: 'staff@phongvu.vn'),
      throwsA(
        isA<AuthBootstrapContractException>()
            .having((error) => error.reason, 'reason', 'invalid_json')
            .having(
              (error) => error.responseBodyBytes,
              'responseBodyBytes',
              greaterThan(0),
            )
            .having((error) => error.topLevelKeys, 'topLevelKeys', isEmpty),
      ),
    );
  });
}
