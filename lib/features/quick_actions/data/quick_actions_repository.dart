import 'dart:convert';

import '../../../core/network/api_client.dart';

class QuickActionStore {
  final String storeCode;
  final String storeName;

  const QuickActionStore({required this.storeCode, required this.storeName});

  factory QuickActionStore.fromJson(Map<String, dynamic> json) =>
      QuickActionStore(
        storeCode: json['storeCode']?.toString() ?? '',
        storeName: json['storeName']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
    'storeCode': storeCode,
    'storeName': storeName,
  };
}

class QuickActionsPayload {
  final List<QuickActionStore> stores;
  final String? selectedStoreCode;
  final Set<String> availableActionCodes;
  final Map<String, String?> links;

  const QuickActionsPayload({
    required this.stores,
    required this.selectedStoreCode,
    required this.availableActionCodes,
    required this.links,
  });

  factory QuickActionsPayload.fromJson(Map<String, dynamic> json) {
    final linksJson = json['links'] as Map<String, dynamic>? ?? const {};
    return QuickActionsPayload(
      stores: (json['stores'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(QuickActionStore.fromJson)
          .toList(growable: false),
      selectedStoreCode: json['selectedStoreCode']?.toString(),
      availableActionCodes:
          (json['availableActionCodes'] as List<dynamic>? ?? const [])
              .map((item) => item.toString())
              .toSet(),
      links: linksJson.map((key, value) => MapEntry(key, value?.toString())),
    );
  }

  Map<String, dynamic> toJson() => {
    'stores': stores.map((store) => store.toJson()).toList(growable: false),
    'selectedStoreCode': selectedStoreCode,
    'availableActionCodes': availableActionCodes.toList(growable: false),
    'links': links,
  };
}

class QuickActionsRepository {
  final ApiClient _client;

  QuickActionsRepository(this._client);

  Future<QuickActionsPayload> load({String? storeCode}) async {
    final response = await _client.get(
      '/quick-actions',
      queryParameters: {if (storeCode != null) 'storeCode': storeCode},
    );
    return QuickActionsPayload.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<List<QuickActionStore>> loadManagedStores() async {
    final response = await _client.get('/admin/quick-action-links/stores');
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return (json['stores'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(QuickActionStore.fromJson)
        .toList(growable: false);
  }

  Future<Map<String, String?>> loadAdminLinks(String storeCode) async {
    final response = await _client.get(
      '/admin/quick-action-links',
      queryParameters: {'storeCode': storeCode},
    );
    return _linksFromResponse(response.body);
  }

  Future<Map<String, String?>> saveAdminLinks(
    String storeCode,
    Map<String, String?> links,
  ) async {
    final response = await _client.put(
      '/admin/quick-action-links/${Uri.encodeComponent(storeCode)}',
      body: links,
    );
    return _linksFromResponse(response.body);
  }

  Map<String, String?> _linksFromResponse(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final links = json['links'] as Map<String, dynamic>? ?? const {};
    return links.map((key, value) => MapEntry(key, value?.toString()));
  }
}
