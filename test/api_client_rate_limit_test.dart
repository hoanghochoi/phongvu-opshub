import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/network/api_exception.dart';

void main() {
  test(
    '429 Retry-After blocks only the affected endpoint without new HTTP',
    () async {
      var now = DateTime.utc(2026, 7, 15, 4);
      var calls = 0;
      final events = <ApiRateLimitEvent>[];
      final client = ApiClient.test(
        MockClient((request) async {
          calls += 1;
          if (request.url.path.endsWith('/home/summary')) {
            return http.Response(
              '{"message":"Vui long cho"}',
              429,
              headers: {'retry-after': '30'},
            );
          }
          return http.Response('{}', 200);
        }),
        now: () => now,
      )..setRateLimitObserver(events.add);

      await expectLater(
        client.get('/home/summary'),
        throwsA(
          isA<RateLimitedException>().having(
            (error) => error.retryAt,
            'retryAt',
            now.add(const Duration(seconds: 30)),
          ),
        ),
      );
      await expectLater(
        client.get('/home/summary'),
        throwsA(isA<RateLimitedException>()),
      );
      expect(calls, 1);

      await client.get('/notifications');
      expect(calls, 2);
      expect(events.map((event) => event.action), ['activated', 'deferred']);

      now = now.add(const Duration(seconds: 31));
      await expectLater(
        client.get('/home/summary'),
        throwsA(isA<RateLimitedException>()),
      );
      expect(calls, 3);
      expect(events.map((event) => event.action), [
        'activated',
        'deferred',
        'expired',
        'activated',
      ]);
    },
  );

  test(
    'user action consumes one bypass ticket and a second 429 keeps it consumed',
    () async {
      final now = DateTime.utc(2026, 7, 15, 4);
      var calls = 0;
      final events = <ApiRateLimitEvent>[];
      final client = ApiClient.test(
        MockClient((request) async {
          calls += 1;
          if (request.method == 'GET' &&
              request.url.path.endsWith('/admin/map-vietin/transactions')) {
            return http.Response(
              '',
              429,
              headers: {'retry-after': calls == 1 ? '30' : '2'},
            );
          }
          return http.Response('{}', 200);
        }),
        now: () => now,
      )..setRateLimitObserver(events.add);

      await expectLater(
        client.get('/admin/map-vietin/transactions?storeId=CP01'),
        throwsA(isA<RateLimitedException>()),
      );
      await expectLater(
        client.get(
          '/admin/map-vietin/transactions?storeId=CP02',
          allowRateLimitCooldownBypass: true,
        ),
        throwsA(
          isA<RateLimitedException>().having(
            (error) => error.retryAt,
            'retryAt',
            now.add(const Duration(seconds: 2)),
          ),
        ),
      );
      await expectLater(
        client.get(
          '/admin/map-vietin/transactions?storeId=CP03',
          allowRateLimitCooldownBypass: true,
        ),
        throwsA(isA<RateLimitedException>()),
      );
      await expectLater(
        client.get('/admin/map-vietin/transactions?storeId=CP04'),
        throwsA(isA<RateLimitedException>()),
      );

      expect(calls, 2);
      expect(events.map((event) => event.action), [
        'activated',
        'bypassed',
        'activated',
        'deferred',
      ]);
      expect(events.map((event) => event.endpoint).toSet(), {
        '/admin/map-vietin/transactions',
      });

      await client.get('/admin/map-vietin/history');
      await client.post('/admin/map-vietin/transactions', body: const {});
      expect(calls, 4);
    },
  );

  test(
    'successful bypass recovers and resets the next cooldown ticket',
    () async {
      var calls = 0;
      final events = <ApiRateLimitEvent>[];
      final client = ApiClient.test(
        MockClient((_) async {
          calls += 1;
          if (calls == 1 || calls == 3) {
            return http.Response('', 429, headers: {'retry-after': '30'});
          }
          return http.Response('{}', 200);
        }),
      )..setRateLimitObserver(events.add);

      await expectLater(
        client.get('/payment'),
        throwsA(isA<RateLimitedException>()),
      );
      await client.get('/payment', allowRateLimitCooldownBypass: true);
      await expectLater(
        client.get('/payment'),
        throwsA(isA<RateLimitedException>()),
      );
      await client.get('/payment', allowRateLimitCooldownBypass: true);

      expect(calls, 4);
      expect(events.map((event) => event.action), [
        'activated',
        'bypassed',
        'recovered',
        'activated',
        'bypassed',
        'recovered',
      ]);
    },
  );

  test('successful retry clears endpoint backoff state', () async {
    var now = DateTime.utc(2026, 7, 15, 4);
    var calls = 0;
    final events = <ApiRateLimitEvent>[];
    final client = ApiClient.test(
      MockClient((request) async {
        calls += 1;
        return calls == 1
            ? http.Response('', 429, headers: {'retry-after': '5'})
            : http.Response('{}', 200);
      }),
      now: () => now,
    )..setRateLimitObserver(events.add);

    await expectLater(
      client.get('/home/summary'),
      throwsA(isA<RateLimitedException>()),
    );
    now = now.add(const Duration(seconds: 6));
    await client.get('/home/summary');
    await client.get('/home/summary');

    expect(calls, 3);
    expect(events.map((event) => event.action), ['activated', 'expired']);
  });

  test('429 without Retry-After uses exponential endpoint fallback', () async {
    var now = DateTime.utc(2026, 7, 15, 4);
    var calls = 0;
    final client = ApiClient.test(
      MockClient((request) async {
        calls += 1;
        return http.Response('', 429);
      }),
      now: () => now,
    );

    RateLimitedException? first;
    try {
      await client.get('/payment-notifications/ready');
    } on RateLimitedException catch (error) {
      first = error;
    }
    expect(first?.retryAt, now.add(const Duration(seconds: 5)));

    RateLimitedException? second;
    try {
      await client.get(
        '/payment-notifications/ready',
        allowRateLimitCooldownBypass: true,
      );
    } on RateLimitedException catch (error) {
      second = error;
    }
    expect(second?.retryAt, now.add(const Duration(seconds: 10)));

    await expectLater(
      client.get('/payment-notifications/ready'),
      throwsA(isA<RateLimitedException>()),
    );
    expect(calls, 2);
  });

  test(
    'late 401 from an old token cannot invalidate the current token',
    () async {
      final response = Completer<http.Response>();
      final client = ApiClient.test(MockClient((_) => response.future));
      var authFailureCalls = 0;
      client
        ..setAuthToken('old-token')
        ..setAuthFailureHandler((exception, failedAuthToken) async {
          authFailureCalls += 1;
        });

      final request = client.get('/protected');
      await Future<void>.delayed(Duration.zero);
      client.setAuthToken('new-token');
      response.complete(http.Response('', 401));

      await expectLater(request, throwsA(isA<ApiException>()));
      expect(authFailureCalls, 0);
      expect(client.authToken, 'new-token');
    },
  );
}
