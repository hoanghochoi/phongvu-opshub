enum PaymentDeliveryMetricTrend { up, down, flat, unknown }

class PaymentDeliveryMetricBucket {
  final int count;
  final int? averageMs;
  final DateTime? from;
  final DateTime? to;

  const PaymentDeliveryMetricBucket({
    required this.count,
    required this.averageMs,
    required this.from,
    required this.to,
  });

  factory PaymentDeliveryMetricBucket.fromJson(Map<String, dynamic> json) {
    return PaymentDeliveryMetricBucket(
      count: _intFromJson(json['count']) ?? 0,
      averageMs: _intFromJson(json['averageMs']),
      from: _dateFromJson(json['from']),
      to: _dateFromJson(json['to']),
    );
  }
}

class PaymentDeliveryMetrics {
  final DateTime? sampledAt;
  final int windowHours;
  final PaymentDeliveryMetricBucket current;
  final PaymentDeliveryMetricBucket previous;
  final int? deltaMs;
  final double? deltaPercent;
  final PaymentDeliveryMetricTrend trend;

  const PaymentDeliveryMetrics({
    required this.sampledAt,
    required this.windowHours,
    required this.current,
    required this.previous,
    required this.deltaMs,
    required this.deltaPercent,
    required this.trend,
  });

  factory PaymentDeliveryMetrics.fromJson(Map<String, dynamic> json) {
    final current = json['current'] is Map
        ? Map<String, dynamic>.from(json['current'] as Map)
        : <String, dynamic>{};
    final previous = json['previous'] is Map
        ? Map<String, dynamic>.from(json['previous'] as Map)
        : <String, dynamic>{};
    return PaymentDeliveryMetrics(
      sampledAt: _dateFromJson(json['sampledAt']),
      windowHours: _intFromJson(json['windowHours']) ?? 24,
      current: PaymentDeliveryMetricBucket.fromJson(current),
      previous: PaymentDeliveryMetricBucket.fromJson(previous),
      deltaMs: _intFromJson(json['deltaMs']),
      deltaPercent: _doubleFromJson(json['deltaPercent']),
      trend: _trendFromJson(json['trend']),
    );
  }

  bool get hasCurrentAverage => current.averageMs != null;
}

class PaymentDeliveryHistory {
  final DateTime? sampledAt;
  final int limit;
  final List<PaymentDeliveryHistoryItem> items;

  const PaymentDeliveryHistory({
    required this.sampledAt,
    required this.limit,
    required this.items,
  });

  factory PaymentDeliveryHistory.fromJson(Map<String, dynamic> json) {
    final rows = json['list'] is List ? json['list'] as List : const [];
    return PaymentDeliveryHistory(
      sampledAt: _dateFromJson(json['sampledAt']),
      limit: _intFromJson(json['limit']) ?? 20,
      items: rows
          .whereType<Map>()
          .map(
            (row) => PaymentDeliveryHistoryItem.fromJson(
              row.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList(growable: false),
    );
  }
}

class PaymentDeliveryHistoryItem {
  final String? deliveryLogId;
  final String? notificationId;
  final String? transactionId;
  final String storeCode;
  final int amount;
  final DateTime? firstSeenAt;
  final DateTime? paidAt;
  final DateTime? notificationCreatedAt;
  final DateTime? streamStartedAt;
  final DateTime? playedAt;
  final String status;
  final DateTime? statusAt;
  final String? errorStatus;
  final String? errorMessage;
  final DateTime? errorAt;
  final int? bankToStreamStartLatencyMs;
  final int? firstSeenToStreamStartLatencyMs;
  final int? playDurationMs;
  final int? firstSeenToPlayedMs;

  const PaymentDeliveryHistoryItem({
    required this.deliveryLogId,
    required this.notificationId,
    required this.transactionId,
    required this.storeCode,
    required this.amount,
    required this.firstSeenAt,
    required this.paidAt,
    required this.notificationCreatedAt,
    required this.streamStartedAt,
    required this.playedAt,
    required this.status,
    required this.statusAt,
    required this.errorStatus,
    required this.errorMessage,
    required this.errorAt,
    required this.bankToStreamStartLatencyMs,
    required this.firstSeenToStreamStartLatencyMs,
    required this.playDurationMs,
    required this.firstSeenToPlayedMs,
  });

  factory PaymentDeliveryHistoryItem.fromJson(Map<String, dynamic> json) {
    return PaymentDeliveryHistoryItem(
      deliveryLogId: _stringFromJson(json['deliveryLogId']),
      notificationId: _stringFromJson(json['notificationId']),
      transactionId: _stringFromJson(json['transactionId']),
      storeCode: _stringFromJson(json['storeCode']) ?? '',
      amount: _intFromJson(json['amount']) ?? 0,
      firstSeenAt: _dateFromJson(json['firstSeenAt']),
      paidAt: _dateFromJson(json['paidAt']),
      notificationCreatedAt: _dateFromJson(json['notificationCreatedAt']),
      streamStartedAt: _dateFromJson(json['streamStartedAt']),
      playedAt: _dateFromJson(json['playedAt']),
      status: _stringFromJson(json['status']) ?? 'UNKNOWN',
      statusAt: _dateFromJson(json['statusAt']),
      errorStatus: _stringFromJson(json['errorStatus']),
      errorMessage: _stringFromJson(json['errorMessage']),
      errorAt: _dateFromJson(json['errorAt']),
      bankToStreamStartLatencyMs: _intFromJson(
        json['bankToStreamStartLatencyMs'],
      ),
      firstSeenToStreamStartLatencyMs: _intFromJson(
        json['firstSeenToStreamStartLatencyMs'],
      ),
      playDurationMs: _intFromJson(json['playDurationMs']),
      firstSeenToPlayedMs: _intFromJson(json['firstSeenToPlayedMs']),
    );
  }

  bool get hasError => errorStatus != null || errorMessage != null;
  bool get isPlayed => status.toUpperCase() == 'PLAYED';
}

PaymentDeliveryMetricTrend _trendFromJson(Object? value) {
  return switch (value?.toString().trim().toLowerCase()) {
    'up' => PaymentDeliveryMetricTrend.up,
    'down' => PaymentDeliveryMetricTrend.down,
    'flat' => PaymentDeliveryMetricTrend.flat,
    _ => PaymentDeliveryMetricTrend.unknown,
  };
}

String? _stringFromJson(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return text;
}

DateTime? _dateFromJson(Object? value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) return null;
  return DateTime.tryParse(text)?.toLocal();
}

int? _intFromJson(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return num.tryParse(value.toString())?.round();
}

double? _doubleFromJson(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
