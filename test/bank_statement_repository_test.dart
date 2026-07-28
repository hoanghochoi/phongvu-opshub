import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
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
}
