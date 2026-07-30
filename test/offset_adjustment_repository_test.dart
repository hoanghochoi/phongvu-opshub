import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/network/api_exception.dart';
import 'package:phongvu_opshub/features/offset_adjustment/data/offset_adjustment_repository.dart';
import 'package:phongvu_opshub/features/offset_adjustment/domain/offset_adjustment.dart';

void main() {
  test('parses ERP selling store and OpsHub creation channel metadata', () {
    final adjustment = OffsetAdjustment.fromJson({
      'id': 'offset-1',
      'type': OffsetAdjustmentType.singleOrder,
      'status': OffsetAdjustmentStatus.pending,
      'storeCode': 'CP01',
      'sellingStores': [
        {'orderCode': '2607020002', 'storeCode': 'CP99'},
      ],
      'creationChannel': 'Cấn trừ trên OpsHub',
      'amount': 100000,
    });

    expect(adjustment.creationChannel, 'Cấn trừ trên OpsHub');
    expect(adjustment.sellingStores.single.orderCode, '2607020002');
    expect(adjustment.sellingStores.single.storeCode, 'CP99');
  });

  test(
    'batch completes selected offsets through the atomic endpoint',
    () async {
      final requests = <http.Request>[];
      final repository = OffsetAdjustmentRepository(
        ApiClient.test(
          MockClient((request) async {
            requests.add(request);
            return http.Response(jsonEncode({'processedCount': 2}), 200);
          }),
        ),
      );

      final processedCount = await repository.batchComplete(const [
        'offset-1',
        'offset-2',
      ]);

      expect(requests, hasLength(1));
      expect(
        requests.single.url.path,
        '/api/offset-adjustments/batch-complete',
      );
      expect(requests.single.method, 'POST');
      expect(jsonDecode(requests.single.body), {
        'ids': ['offset-1', 'offset-2'],
      });
      expect(processedCount, 2);
    },
  );

  for (final body in <Object?>[
    <String, Object?>{},
    <String, Object?>{'processedCount': '2'},
    <String, Object?>{'processedCount': -1},
    <String, Object?>{'processedCount': 1},
  ]) {
    test('rejects malformed batch-complete response $body', () async {
      final repository = OffsetAdjustmentRepository(
        ApiClient.test(
          MockClient((_) async => http.Response(jsonEncode(body), 200)),
        ),
      );

      await expectLater(
        repository.batchComplete(const ['offset-1', 'offset-2']),
        throwsA(isA<ApiException>()),
      );
    });
  }
}
