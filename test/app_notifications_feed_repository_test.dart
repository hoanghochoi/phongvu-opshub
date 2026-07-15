import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/notifications/data/app_notifications_feed_repository.dart';

void main() {
  test(
    'requests and parses the versioned aggregate notification feed',
    () async {
      var requestCount = 0;
      final client = ApiClient.test(
        MockClient((request) async {
          requestCount += 1;
          expect(request.method, 'GET');
          expect(request.url.path, '/api/notifications/feed');
          return http.Response(jsonEncode(_payload), 200);
        }),
      );
      final repository = AppNotificationsFeedRepository(client);

      final result = await repository.fetchFeed();

      expect(requestCount, 1);
      expect(result.schemaVersion, 1);
      expect(result.statementOrderTransfers.requests.single.id, 'statement-1');
      expect(result.statementOrderTransfers.total, 2);
      expect(result.offsetAdjustments.items.single.id, 'offset-1');
      expect(result.offsetAdjustments.total, 3);
    },
  );
}

final _payload = {
  'schemaVersion': 1,
  'generatedAt': '2026-07-15T05:00:00.000Z',
  'statementOrderTransfers': {
    'enabled': true,
    'page': 0,
    'limit': 20,
    'total': 2,
    'canReview': true,
    'list': [
      {
        'id': 'statement-1',
        'transactionId': 'transaction-1',
        'storeCode': 'CP01',
        'oldOrders': ['26071500000001'],
        'requestedOrders': ['26071500000002'],
        'status': 'PENDING',
        'amount': 1200000,
        'createdAt': '2026-07-15T04:00:00.000Z',
      },
    ],
  },
  'offsetAdjustments': {
    'enabled': true,
    'page': 0,
    'limit': 20,
    'total': 3,
    'canReview': true,
    'list': [
      {
        'id': 'offset-1',
        'type': 'SINGLE_ORDER',
        'status': 'PENDING',
        'storeCode': 'CP01',
        'oldOrderCode': '26071500000001',
        'newOrderCode': '26071500000002',
        'amount': 1500000,
        'submittedAt': '2026-07-15T04:30:00.000Z',
      },
    ],
  },
};
