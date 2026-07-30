import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/network/api_exception.dart';
import 'package:phongvu_opshub/features/bank_statement/data/bank_statement_repository.dart';

void main() {
  test(
    'updates statement tracking through the scoped tracking endpoint',
    () async {
      final requests = <http.Request>[];
      final repository = BankStatementRepository(
        ApiClient.test(
          MockClient((request) async {
            requests.add(request);
            return http.Response(
              jsonEncode({
                'id': 'tx-1',
                'storeId': 'CP01',
                'transactionKey': 'key-tx-1',
                'transactionNumber': 'MAP-001',
                'amount': 1250000,
                'content': 'Customer transfer',
                'orders': ['26052912345678'],
                'orderTrackingStatus': 'UNFOLLOWED',
                'canManageOrderTracking': true,
                'status': '00',
              }),
              200,
            );
          }),
        ),
      );

      final transaction = await repository.updateOrderTracking(
        'tx-1',
        'UNFOLLOWED',
      );

      expect(requests, hasLength(1));
      expect(
        requests.single.url.path,
        '/api/admin/map-vietin/statements/tx-1/order-tracking',
      );
      expect(requests.single.method, 'PATCH');
      expect(jsonDecode(requests.single.body), {'status': 'UNFOLLOWED'});
      expect(transaction.orderTrackingStatus, 'UNFOLLOWED');
      expect(transaction.isFollowing, isFalse);
    },
  );

  test('batch unfollows selected statements and parses no-op counts', () async {
    final requests = <http.Request>[];
    final repository = BankStatementRepository(
      ApiClient.test(
        MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'processedCount': 3,
              'changedCount': 2,
              'unchangedCount': 1,
            }),
            200,
          );
        }),
      ),
    );

    final result = await repository.batchUnfollow(const [
      'tx-1',
      'tx-2',
      'tx-3',
    ]);

    expect(requests, hasLength(1));
    expect(
      requests.single.url.path,
      '/api/admin/map-vietin/statements/order-tracking/batch',
    );
    expect(requests.single.method, 'PATCH');
    expect(jsonDecode(requests.single.body), {
      'transactionIds': ['tx-1', 'tx-2', 'tx-3'],
      'status': 'UNFOLLOWED',
    });
    expect(result.processedCount, 3);
    expect(result.changedCount, 2);
    expect(result.unchangedCount, 1);
  });

  for (final body in <Object?>[
    <String, Object?>{},
    <String, Object?>{
      'processedCount': '2',
      'changedCount': 1,
      'unchangedCount': 1,
    },
    <String, Object?>{
      'processedCount': 2,
      'changedCount': -1,
      'unchangedCount': 3,
    },
    <String, Object?>{
      'processedCount': 2,
      'changedCount': 2,
      'unchangedCount': 1,
    },
  ]) {
    test('rejects malformed batch-unfollow response $body', () async {
      final repository = BankStatementRepository(
        ApiClient.test(
          MockClient((_) async => http.Response(jsonEncode(body), 200)),
        ),
      );

      await expectLater(
        repository.batchUnfollow(const ['tx-1', 'tx-2']),
        throwsA(isA<ApiException>()),
      );
    });
  }
}
