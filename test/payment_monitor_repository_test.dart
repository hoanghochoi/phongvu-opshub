import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/repositories/payment_monitor_repository.dart';
import 'package:phongvu_opshub/features/payment_monitor/domain/payment_delivery_metrics.dart';

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

  test('fetchDeliveryMetrics parses average and trend data', () async {
    final requests = <http.Request>[];
    final apiClient = ApiClient.test(
      MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'sampledAt': '2026-06-27T02:00:00.000Z',
            'windowHours': 24,
            'current': {
              'count': 3,
              'averageMs': 7242,
              'from': '2026-06-26T02:00:00.000Z',
              'to': '2026-06-27T02:00:00.000Z',
            },
            'previous': {
              'count': 2,
              'averageMs': 8342,
              'from': '2026-06-25T02:00:00.000Z',
              'to': '2026-06-26T02:00:00.000Z',
            },
            'deltaMs': -1100,
            'deltaPercent': -13.2,
            'trend': 'down',
          }),
          200,
        );
      }),
    );
    final repository = PaymentMonitorRepository(apiClient);

    final metrics = await repository.fetchDeliveryMetrics();

    expect(requests, hasLength(1));
    expect(
      requests.single.url.path,
      endsWith('/payment-notifications/delivery-metrics'),
    );
    expect(requests.single.url.queryParameters['windowHours'], '24');
    expect(metrics.current.averageMs, 7242);
    expect(metrics.previous.count, 2);
    expect(metrics.deltaMs, -1100);
    expect(metrics.deltaPercent, -13.2);
    expect(metrics.trend, PaymentDeliveryMetricTrend.down);
  });
}
