import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/network/api_exception.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/repositories/payment_monitor_repository.dart';
import 'package:phongvu_opshub/features/payment_monitor/domain/payment_delivery_metrics.dart';

void main() {
  test('stored transaction user action forwards the cooldown bypass', () async {
    var requests = 0;
    final repository = PaymentMonitorRepository(
      ApiClient.test(
        MockClient((_) async {
          requests += 1;
          if (requests == 1) {
            return http.Response('', 429, headers: {'retry-after': '30'});
          }
          return http.Response(
            jsonEncode({
              'list': const [],
              'page': 0,
              'limit': 10,
              'total': 0,
              'canReviewOrderTransfers': false,
            }),
            200,
          );
        }),
      ),
    );

    await expectLater(
      repository.fetchStoredTransactions(),
      throwsA(isA<RateLimitedException>()),
    );
    final page = await repository.fetchStoredTransactions(
      allowRateLimitCooldownBypass: true,
    );

    expect(requests, 2);
    expect(page.transactions, isEmpty);
  });

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

  test('downloadNotificationStreamAudio uses stream URL', () async {
    final requests = <http.Request>[];
    final apiClient = ApiClient.test(
      MockClient((request) async {
        requests.add(request);
        return http.Response.bytes(const [1, 2, 3], 200);
      }),
    );
    final repository = PaymentMonitorRepository(apiClient);

    await repository.downloadNotificationStreamAudio(
      'note-1',
      rawAmount: true,
      clientId: 'pc-1',
    );

    expect(requests, hasLength(1));
    expect(
      requests.single.url.path,
      endsWith('/payment-notifications/note-1/stream'),
    );
    expect(requests.single.url.queryParameters['rawAmount'], 'true');
    expect(requests.single.url.queryParameters['clientId'], 'pc-1');
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

  test('fetchDeliveryHistory parses recent speaker rows', () async {
    final requests = <http.Request>[];
    final apiClient = ApiClient.test(
      MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'sampledAt': '2026-06-27T02:00:00.000Z',
            'limit': 20,
            'list': [
              {
                'deliveryLogId': 'log-1',
                'notificationId': 'note-1',
                'transactionId': 'txn-1',
                'storeCode': 'CP01',
                'amount': 1250000,
                'firstSeenAt': '2026-06-27T01:00:02.003Z',
                'paidAt': '2026-06-27T01:00:00.000Z',
                'notificationCreatedAt': '2026-06-27T01:00:01.000Z',
                'streamStartedAt': '2026-06-27T01:00:07.242Z',
                'playedAt': '2026-06-27T01:00:09.245Z',
                'status': 'PLAYED',
                'statusAt': '2026-06-27T01:00:09.245Z',
                'errorStatus': 'PLAYBACK_FAILED',
                'errorMessage': 'speaker failed attempt 1',
                'errorAt': '2026-06-27T01:00:05.000Z',
                'bankToStreamStartLatencyMs': 7242,
                'firstSeenToStreamStartLatencyMs': 5239,
                'playDurationMs': 2003,
                'firstSeenToPlayedMs': 7242,
              },
            ],
          }),
          200,
        );
      }),
    );
    final repository = PaymentMonitorRepository(apiClient);

    final history = await repository.fetchDeliveryHistory();

    expect(requests, hasLength(1));
    expect(
      requests.single.url.path,
      endsWith('/payment-notifications/delivery-history'),
    );
    expect(requests.single.url.queryParameters['limit'], '20');
    expect(history.limit, 20);
    expect(history.items, hasLength(1));
    expect(history.items.single.storeCode, 'CP01');
    expect(history.items.single.amount, 1250000);
    expect(history.items.single.status, 'PLAYED');
    expect(history.items.single.errorStatus, 'PLAYBACK_FAILED');
    expect(history.items.single.bankToStreamStartLatencyMs, 7242);
    expect(history.items.single.playDurationMs, 2003);
    expect(history.items.single.firstSeenToPlayedMs, 7242);
  });
}
