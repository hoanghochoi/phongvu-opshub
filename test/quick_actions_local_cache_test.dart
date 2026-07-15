import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/features/quick_actions/data/quick_actions_local_cache.dart';
import 'package:phongvu_opshub/features/quick_actions/data/quick_actions_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'persists showroom QR payload and isolates permission identity',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesQuickActionsCacheStore();
      final loadedAt = DateTime(2026, 7, 15, 10);
      const payload = QuickActionsPayload(
        stores: [QuickActionStore(storeCode: 'CP75', storeName: 'Showroom 75')],
        selectedStoreCode: 'CP75',
        availableActionCodes: {'APP_DOWNLOAD'},
        links: {'APP_DOWNLOAD': 'https://example.com/app'},
      );

      await store.write(
        ownerId: 'user-1',
        cacheIdentity: 'permission-v1',
        cacheKey: 'CP75',
        record: QuickActionsCacheRecord(payload: payload, loadedAt: loadedAt),
      );

      final restored = await SharedPreferencesQuickActionsCacheStore().read(
        ownerId: 'user-1',
        cacheIdentity: 'permission-v1',
        cacheKey: 'CP75',
      );
      final rejected = await store.read(
        ownerId: 'user-1',
        cacheIdentity: 'permission-v2',
        cacheKey: 'CP75',
      );

      expect(restored?.loadedAt, loadedAt);
      expect(restored?.payload.selectedStoreCode, 'CP75');
      expect(
        restored?.payload.links['APP_DOWNLOAD'],
        'https://example.com/app',
      );
      expect(rejected, isNull);
    },
  );
}
