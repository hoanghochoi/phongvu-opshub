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

PaymentDeliveryMetricTrend _trendFromJson(Object? value) {
  return switch (value?.toString().trim().toLowerCase()) {
    'up' => PaymentDeliveryMetricTrend.up,
    'down' => PaymentDeliveryMetricTrend.down,
    'flat' => PaymentDeliveryMetricTrend.flat,
    _ => PaymentDeliveryMetricTrend.unknown,
  };
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
