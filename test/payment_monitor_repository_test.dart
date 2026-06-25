import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/repositories/payment_monitor_repository.dart';

void main() {
  test(
    'downloadNotificationAudio requests server-combined cue when enabled',
    () async {
      final requests = <http.Request>[];
      final apiClient = ApiClient.test(
        MockClient((request) async {
          requests.add(request);
          return http.Response.bytes(const [1, 2, 3], 200);
        }),
      );
      final repository = PaymentMonitorRepository(apiClient);

      await repository.downloadNotificationAudio('note-1', includeCue: true);

      expect(requests, hasLength(1));
      expect(
        requests.single.url.path,
        endsWith('/payment-notifications/note-1/audio'),
      );
      expect(requests.single.url.queryParameters['includeCue'], 'true');
    },
  );

  test('downloadNotificationAudio requests raw amount when enabled', () async {
    final requests = <http.Request>[];
    final apiClient = ApiClient.test(
      MockClient((request) async {
        requests.add(request);
        return http.Response.bytes(const [1, 2, 3], 200);
      }),
    );
    final repository = PaymentMonitorRepository(apiClient);

    await repository.downloadNotificationAudio('note-1', rawAmount: true);

    expect(requests, hasLength(1));
    expect(
      requests.single.url.path,
      endsWith('/payment-notifications/note-1/audio'),
    );
    expect(requests.single.url.queryParameters['rawAmount'], 'true');
  });

  test('downloadNotificationAudio keeps legacy URL by default', () async {
    final requests = <http.Request>[];
    final apiClient = ApiClient.test(
      MockClient((request) async {
        requests.add(request);
        return http.Response.bytes(const [1, 2, 3], 200);
      }),
    );
    final repository = PaymentMonitorRepository(apiClient);

    await repository.downloadNotificationAudio('note-1');

    expect(requests, hasLength(1));
    expect(
      requests.single.url.path,
      endsWith('/payment-notifications/note-1/audio'),
    );
    expect(requests.single.url.queryParameters, isEmpty);
  });
}
