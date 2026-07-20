import 'dart:convert';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/data/app_query_cache.dart';
import '../../../../core/data/shared_preferences_query_persistence.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/home_summary.dart';

class HomeSummaryScopeOptionDto {
  const HomeSummaryScopeOptionDto({
    required this.value,
    required this.label,
    required this.scope,
    this.organizationNodeId,
    this.organizationNodeType,
    this.storeCount,
    this.isDefault = false,
  });

  final String value;
  final String label;
  final String scope;
  final String? organizationNodeId;
  final String? organizationNodeType;
  final int? storeCount;
  final bool isDefault;

  factory HomeSummaryScopeOptionDto.fromJson(Map<String, dynamic> json) {
    return HomeSummaryScopeOptionDto(
      value: json['value']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      scope: json['scope']?.toString() ?? '',
      organizationNodeId: json['organizationNodeId']?.toString(),
      organizationNodeType: json['organizationNodeType']?.toString(),
      storeCount: json['storeCount'] is num
          ? (json['storeCount'] as num).toInt()
          : int.tryParse(json['storeCount']?.toString() ?? ''),
      isDefault: json['isDefault'] == true || json['isDefault'] == 'true',
    );
  }
}

class HomeSummaryRepository {
  static const Duration summaryFreshTtl = Duration(seconds: 60);

  final ApiClient _apiClient;
  final AppQueryCache _queryCache;

  AppQuerySnapshot<Map<String, dynamic>>? _lastSummarySnapshot;

  HomeSummaryRepository(this._apiClient, {AppQueryCache? queryCache})
    : _queryCache =
          queryCache ??
          AppQueryCache(persistence: const SharedPreferencesQueryPersistence());

  DateTime? get lastSummaryFetchedAt => _lastSummarySnapshot?.fetchedAt;
  AppQuerySource? get lastSummarySource => _lastSummarySnapshot?.source;
  bool get lastSummaryWasStale =>
      _lastSummarySnapshot?.source == AppQuerySource.staleFallback;

  Future<HomeSummary> fetchSummary({
    String? date,
    String? startDate,
    String? endDate,
    String? scope,
    String? organizationNodeId,
    String? salesProgressUserId,
    String? cacheIdentity,
    bool forceRefresh = false,
  }) async {
    final queryParameters = _buildSummaryQueryParameters(
      date: date,
      startDate: startDate,
      endDate: endDate,
      scope: scope,
      organizationNodeId: organizationNodeId,
      salesProgressUserId: salesProgressUserId,
    );
    final normalizedIdentity = cacheIdentity?.trim();
    if (normalizedIdentity == null || normalizedIdentity.isEmpty) {
      return HomeSummary.fromJson(await _loadSummaryJson(queryParameters));
    }
    final key = AppQueryKey(
      _queryKey(
        resource: ApiConstants.homeSummaryEndpoint,
        cacheIdentity: normalizedIdentity,
        queryParameters: queryParameters,
      ),
    );
    final snapshot = await _queryCache.getOrLoad<Map<String, dynamic>>(
      key: key,
      policy: const AppQueryPolicy(ttl: summaryFreshTtl),
      codec: const AppQueryCodec(
        encode: _encodeJsonMap,
        decode: _decodeJsonMap,
      ),
      tags: const ['home.summary'],
      forceRefresh: forceRefresh,
      loader: () => _loadSummaryJson(queryParameters),
    );
    _lastSummarySnapshot = snapshot;
    final cacheAgeSeconds = DateTime.now()
        .difference(snapshot.fetchedAt)
        .inSeconds;
    await AppLogger.instance.info(
      'HomeSummaryCache',
      'Home summary cache resolved',
      context: {
        'source': snapshot.source.name,
        'ageSeconds': cacheAgeSeconds < 0 ? 0 : cacheAgeSeconds,
        'forceRefresh': forceRefresh,
      },
    );
    return HomeSummary.fromJson(snapshot.data);
  }

  Future<HomeSummaryDetailsPage<HomeNotPurchasedReportDetail>>
  fetchNotPurchasedDetails({
    String? date,
    String? startDate,
    String? endDate,
    String? scope,
    String? organizationNodeId,
    String? salesProgressUserId,
    String? cursor,
    int limit = 50,
  }) => _fetchDetailsPage(
    kind: HomeSummaryDetailKind.notPurchased,
    itemFromJson: HomeNotPurchasedReportDetail.fromJson,
    date: date,
    startDate: startDate,
    endDate: endDate,
    scope: scope,
    organizationNodeId: organizationNodeId,
    salesProgressUserId: salesProgressUserId,
    cursor: cursor,
    limit: limit,
  );

  Future<HomeSummaryDetailsPage<HomeUnreportedOrderDetail>>
  fetchUnreportedOrderDetails({
    String? date,
    String? startDate,
    String? endDate,
    String? scope,
    String? organizationNodeId,
    String? salesProgressUserId,
    String? cursor,
    int limit = 50,
  }) => _fetchDetailsPage(
    kind: HomeSummaryDetailKind.unreportedOrder,
    itemFromJson: HomeUnreportedOrderDetail.fromJson,
    date: date,
    startDate: startDate,
    endDate: endDate,
    scope: scope,
    organizationNodeId: organizationNodeId,
    salesProgressUserId: salesProgressUserId,
    cursor: cursor,
    limit: limit,
  );

  Future<HomeSummaryDetailsPage<HomeInstallmentNeedDetail>>
  fetchInstallmentNeedDetails({
    String? date,
    String? startDate,
    String? endDate,
    String? scope,
    String? organizationNodeId,
    String? salesProgressUserId,
    String? cursor,
    int limit = 50,
  }) => _fetchDetailsPage(
    kind: HomeSummaryDetailKind.installmentNeed,
    itemFromJson: HomeInstallmentNeedDetail.fromJson,
    date: date,
    startDate: startDate,
    endDate: endDate,
    scope: scope,
    organizationNodeId: organizationNodeId,
    salesProgressUserId: salesProgressUserId,
    cursor: cursor,
    limit: limit,
  );

  Future<HomeSummaryDetailsPage<T>> _fetchDetailsPage<T>({
    required HomeSummaryDetailKind kind,
    required T Function(Map<String, dynamic> json) itemFromJson,
    String? date,
    String? startDate,
    String? endDate,
    String? scope,
    String? organizationNodeId,
    String? salesProgressUserId,
    String? cursor,
    int limit = 50,
  }) async {
    final queryParameters = _buildSummaryQueryParameters(
      date: date,
      startDate: startDate,
      endDate: endDate,
      scope: scope,
      organizationNodeId: organizationNodeId,
      salesProgressUserId: salesProgressUserId,
    );
    final normalizedCursor = cursor?.trim();
    queryParameters['kind'] = kind.apiValue;
    queryParameters['limit'] = limit.clamp(1, 100).toString();
    if (normalizedCursor != null && normalizedCursor.isNotEmpty) {
      queryParameters['cursor'] = normalizedCursor;
    }
    final response = await _apiClient.get(
      ApiConstants.homeSummaryDetailsV2Endpoint,
      queryParameters: queryParameters,
    );
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      throw ParseException(
        'Dữ liệu chi tiết báo cáo chưa đúng định dạng. Vui lòng thử lại.',
      );
    }
    try {
      return HomeSummaryDetailsPage<T>.fromJson(
        data,
        expectedKind: kind,
        itemFromJson: itemFromJson,
      );
    } on FormatException {
      throw ParseException(
        'Dữ liệu chi tiết báo cáo chưa đúng định dạng. Vui lòng thử lại.',
      );
    }
  }

  Future<List<HomeSummaryScopeOptionDto>> fetchScopeOptions({
    String? cacheIdentity,
    bool forceRefresh = false,
  }) async {
    final normalizedIdentity = cacheIdentity?.trim();
    final rawOptions = normalizedIdentity == null || normalizedIdentity.isEmpty
        ? await _loadScopeOptionsJson()
        : (await _queryCache.getOrLoad<List<dynamic>>(
            key: AppQueryKey(
              _queryKey(
                resource: ApiConstants.homeSummaryScopeOptionsEndpoint,
                cacheIdentity: normalizedIdentity,
                queryParameters: const {},
              ),
            ),
            policy: const AppQueryPolicy(ttl: Duration(hours: 24)),
            codec: const AppQueryCodec(
              encode: _encodeJsonList,
              decode: _decodeJsonList,
            ),
            tags: const ['home.scopes'],
            forceRefresh: forceRefresh,
            loader: _loadScopeOptionsJson,
          )).data;
    return rawOptions
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .map(HomeSummaryScopeOptionDto.fromJson)
        .where((option) => option.value.isNotEmpty && option.label.isNotEmpty)
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> _loadSummaryJson(
    Map<String, String> queryParameters,
  ) async {
    final response = await _apiClient.get(
      ApiConstants.homeSummaryEndpoint,
      queryParameters: queryParameters,
    );
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      throw ParseException(
        'Dữ liệu dashboard chưa đúng định dạng. Vui lòng thử lại.',
      );
    }
    return data;
  }

  Future<List<dynamic>> _loadScopeOptionsJson() async {
    final response = await _apiClient.get(
      ApiConstants.homeSummaryScopeOptionsEndpoint,
    );
    final data = jsonDecode(response.body);
    if (data is! List) {
      throw ParseException(
        'Dữ liệu phạm vi dashboard chưa đúng định dạng. Vui lòng thử lại.',
      );
    }
    return data;
  }

  String _queryKey({
    required String resource,
    required String cacheIdentity,
    required Map<String, String> queryParameters,
  }) {
    final sorted = queryParameters.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final query = sorted
        .map((entry) => '${entry.key}=${Uri.encodeQueryComponent(entry.value)}')
        .join('&');
    return '${ApiConstants.baseUrl}|$cacheIdentity|$resource|$query';
  }

  Map<String, String> _buildSummaryQueryParameters({
    String? date,
    String? startDate,
    String? endDate,
    String? scope,
    String? organizationNodeId,
    String? salesProgressUserId,
  }) {
    final queryParameters = <String, String>{};
    final normalizedDate = date?.trim();
    if (normalizedDate != null && normalizedDate.isNotEmpty) {
      queryParameters['date'] = normalizedDate;
    }
    final normalizedStartDate = startDate?.trim();
    if (normalizedStartDate != null && normalizedStartDate.isNotEmpty) {
      queryParameters['startDate'] = normalizedStartDate;
    }
    final normalizedEndDate = endDate?.trim();
    if (normalizedEndDate != null && normalizedEndDate.isNotEmpty) {
      queryParameters['endDate'] = normalizedEndDate;
    }
    final normalizedScope = scope?.trim().toUpperCase();
    if (normalizedScope != null &&
        normalizedScope.isNotEmpty &&
        normalizedScope != 'AUTO') {
      queryParameters['scope'] = normalizedScope;
    }
    final normalizedNodeId = organizationNodeId?.trim();
    if (normalizedNodeId != null && normalizedNodeId.isNotEmpty) {
      queryParameters['organizationNodeId'] = normalizedNodeId;
    }
    final normalizedSalesProgressUserId = salesProgressUserId?.trim();
    if (normalizedSalesProgressUserId != null &&
        normalizedSalesProgressUserId.isNotEmpty) {
      queryParameters['salesProgressUserId'] = normalizedSalesProgressUserId;
    }
    return queryParameters;
  }
}

Object? _encodeJsonMap(Map<String, dynamic> value) => value;

Map<String, dynamic> _decodeJsonMap(Object? value) {
  if (value is! Map) throw const FormatException('Expected JSON object');
  return Map<String, dynamic>.from(value);
}

Object? _encodeJsonList(List<dynamic> value) => value;

List<dynamic> _decodeJsonList(Object? value) {
  if (value is! List) throw const FormatException('Expected JSON list');
  return List<dynamic>.from(value);
}
