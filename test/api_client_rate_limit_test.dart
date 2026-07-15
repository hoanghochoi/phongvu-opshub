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
    expect(events.map((event) => event.action), ['activated', 'recovered']);
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

    now = now.add(const Duration(seconds: 6));
    RateLimitedException? second;
    try {
      await client.get('/payment-notifications/ready');
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
}
