import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phongvu_opshub/core/data/app_query_cache.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/home/data/repositories/home_summary_repository.dart';

void main() {
  test('Home summary revalidates at the exact 60-second boundary', () async {
    final fetchedAt = DateTime.utc(2026, 7, 15, 8);
    var now = fetchedAt;
    var requests = 0;
    final repository = HomeSummaryRepository(
      ApiClient.test(
        MockClient((_) async {
          requests += 1;
          return http.Response(
            jsonEncode(_summaryJson(totalOrders: requests)),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
      queryCache: AppQueryCache(now: () => now),
    );

    await repository.fetchSummary(
      startDate: '2026-07-15',
      endDate: '2026-07-15',
      cacheIdentity: 'user-ttl',
    );
    now = fetchedAt.add(const Duration(seconds: 59));
    final fresh = await repository.fetchSummary(
      startDate: '2026-07-15',
      endDate: '2026-07-15',
      cacheIdentity: 'user-ttl',
    );
    expect(fresh.totalOrders, 1);
    expect(requests, 1);

    now = fetchedAt.add(HomeSummaryRepository.summaryFreshTtl);
    final refreshed = await Future.wait([
      repository.fetchSummary(
        startDate: '2026-07-15',
        endDate: '2026-07-15',
        cacheIdentity: 'user-ttl',
      ),
      repository.fetchSummary(
        startDate: '2026-07-15',
        endDate: '2026-07-15',
        cacheIdentity: 'user-ttl',
      ),
    ]);
    expect(refreshed.map((summary) => summary.totalOrders), everyElement(2));
    expect(requests, 2);
  });

  test(
    'Home summary reuses a fresh keyed snapshot and supports invalidation',
    () async {
      var now = DateTime.utc(2026, 7, 15, 8);
      var requests = 0;
      final client = MockClient((request) async {
        requests += 1;
        return http.Response(
          jsonEncode(_summaryJson(totalOrders: requests)),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final cache = AppQueryCache(now: () => now);
      final repository = HomeSummaryRepository(
        ApiClient.test(client),
        queryCache: cache,
      );

      final first = await repository.fetchSummary(
        startDate: '2026-07-15',
        endDate: '2026-07-15',
        cacheIdentity: 'user-1',
      );
      final second = await repository.fetchSummary(
        startDate: '2026-07-15',
        endDate: '2026-07-15',
        cacheIdentity: 'user-1',
      );

      expect(first.totalOrders, 1);
      expect(second.totalOrders, 1);
      expect(requests, 1);
      expect(repository.lastSummarySource, AppQuerySource.memory);

      await cache.invalidateTag('home.summary');
      final refreshed = await repository.fetchSummary(
        startDate: '2026-07-15',
        endDate: '2026-07-15',
        cacheIdentity: 'user-1',
      );
      expect(refreshed.totalOrders, 2);
      expect(requests, 2);

      now = now.add(const Duration(minutes: 2));
      client.close();
    },
  );

  test('Home summary serves stale data when revalidation is offline', () async {
    var now = DateTime.utc(2026, 7, 15, 8);
    var offline = false;
    var requests = 0;
    final client = MockClient((request) async {
      requests += 1;
      if (offline) {
        return http.Response(
          jsonEncode({'message': 'Tạm thời chưa kết nối được.'}),
          503,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode(_summaryJson(totalOrders: 7)),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final repository = HomeSummaryRepository(
      ApiClient.test(client),
      queryCache: AppQueryCache(now: () => now),
    );

    await repository.fetchSummary(
      startDate: '2026-07-15',
      endDate: '2026-07-15',
      cacheIdentity: 'user-1',
    );
    final originalFetchedAt = repository.lastSummaryFetchedAt;
    now = now.add(HomeSummaryRepository.summaryFreshTtl);
    offline = true;
    final stale = await repository.fetchSummary(
      startDate: '2026-07-15',
      endDate: '2026-07-15',
      cacheIdentity: 'user-1',
    );

    expect(stale.totalOrders, 7);
    expect(requests, 2);
    expect(repository.lastSummaryWasStale, isTrue);
    expect(repository.lastSummaryFetchedAt, originalFetchedAt);

    now = now.add(const Duration(seconds: 1));
    await repository.fetchSummary(
      startDate: '2026-07-15',
      endDate: '2026-07-15',
      cacheIdentity: 'user-1',
    );
    expect(requests, 3);
    expect(repository.lastSummaryFetchedAt, originalFetchedAt);
  });
}

Map<String, dynamic> _summaryJson({required int totalOrders}) => {
  'date': '2026-07-15',
  'startDate': '2026-07-15',
  'endDate': '2026-07-15',
  'available': true,
  'scope': 'OWN',
  'scopeLabel': 'Phạm vi cá nhân',
  'coverageLabel': 'Tỉ lệ báo cáo',
  'totalOrders': totalOrders,
};
