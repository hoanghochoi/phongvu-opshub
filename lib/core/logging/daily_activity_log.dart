import 'dart:convert';

class DailyActivityLogSummary {
  const DailyActivityLogSummary({
    required this.logDate,
    required this.scannedLines,
    required this.parsedLines,
    required this.matchedLines,
    required this.firstTimestamp,
    required this.lastTimestamp,
    required this.levelCounts,
    required this.sourceCounts,
    required this.messageCounts,
    required this.notableSamples,
  });

  final String logDate;
  final int scannedLines;
  final int parsedLines;
  final int matchedLines;
  final String? firstTimestamp;
  final String? lastTimestamp;
  final Map<String, int> levelCounts;
  final Map<String, int> sourceCounts;
  final List<Map<String, Object?>> messageCounts;
  final List<Map<String, Object?>> notableSamples;

  Map<String, Object?> toContext({
    required String platform,
    String? appVersion,
    String? buildNumber,
  }) {
    return {
      'schemaVersion': 1,
      'logDate': logDate,
      'rawLogIncluded': false,
      'platform': platform,
      if (appVersion != null) 'appVersion': appVersion,
      if (buildNumber != null) 'buildNumber': buildNumber,
      'scannedLines': scannedLines,
      'parsedLines': parsedLines,
      'matchedLines': matchedLines,
      'firstTimestamp': firstTimestamp,
      'lastTimestamp': lastTimestamp,
      'levelCounts': levelCounts,
      'sourceCounts': _topCountEntries(sourceCounts, 40),
      'messageCounts': messageCounts,
      'notableSamples': notableSamples,
    };
  }
}

DailyActivityLogSummary buildDailyActivityLogSummary(
  Iterable<String> lines, {
  required DateTime targetDate,
  int maxMessageGroups = 80,
  int maxNotableSamples = 20,
}) {
  final logDate = formatLogDate(targetDate);
  var scannedLines = 0;
  var parsedLines = 0;
  var matchedLines = 0;
  String? firstTimestamp;
  String? lastTimestamp;
  final levelCounts = <String, int>{};
  final sourceCounts = <String, int>{};
  final messageCounts = <_MessageKey, int>{};
  final notableSamples = <Map<String, Object?>>[];

  for (final line in lines) {
    scannedLines += 1;
    final entry = _decodeLogLine(line);
    if (entry == null) continue;
    parsedLines += 1;

    final timestamp = entry['ts']?.toString();
    if (timestamp == null || !timestamp.startsWith('${logDate}T')) continue;
    matchedLines += 1;
    firstTimestamp ??= timestamp;
    lastTimestamp = timestamp;

    final level = _normalizedText(
      entry['level'],
      fallback: 'unknown',
    ).toLowerCase();
    final source = _normalizedText(entry['source'], fallback: 'Unknown');
    final message = sanitizeLogText(
      _normalizedText(entry['message'], fallback: 'Unknown'),
      maxLength: 240,
    );

    levelCounts[level] = (levelCounts[level] ?? 0) + 1;
    sourceCounts[source] = (sourceCounts[source] ?? 0) + 1;
    final key = _MessageKey(source: source, level: level, message: message);
    messageCounts[key] = (messageCounts[key] ?? 0) + 1;

    if (_isNotable(level, message) &&
        notableSamples.length < maxNotableSamples) {
      notableSamples.add({
        'ts': timestamp,
        'level': level,
        'source': source,
        'message': message,
        if (entry.containsKey('context'))
          'context': sanitizeLogValue(entry['context']),
      });
    }
  }

  return DailyActivityLogSummary(
    logDate: logDate,
    scannedLines: scannedLines,
    parsedLines: parsedLines,
    matchedLines: matchedLines,
    firstTimestamp: firstTimestamp,
    lastTimestamp: lastTimestamp,
    levelCounts: Map.unmodifiable(levelCounts),
    sourceCounts: Map.unmodifiable(sourceCounts),
    messageCounts: _topMessageEntries(messageCounts, maxMessageGroups),
    notableSamples: List.unmodifiable(notableSamples),
  );
}

String formatLogDate(DateTime date) {
  final localDate = DateTime(date.year, date.month, date.day);
  return '${localDate.year.toString().padLeft(4, '0')}-'
      '${localDate.month.toString().padLeft(2, '0')}-'
      '${localDate.day.toString().padLeft(2, '0')}';
}

Object? sanitizeLogValue(Object? value, {int depth = 0}) {
  if (depth > 4) return '[truncated-depth]';
  if (value is Map) {
    final result = <String, Object?>{};
    var count = 0;
    for (final entry in value.entries) {
      count += 1;
      if (count > 40) {
        result['_truncatedKeys'] = value.length - 40;
        break;
      }
      final key = sanitizeLogText(entry.key.toString(), maxLength: 80);
      if (_isSensitiveKey(key)) {
        result[key] = '[redacted]';
      } else if (_isPersonalDataKey(key)) {
        result[key] = '[redacted-pii]';
      } else {
        result[key] = sanitizeLogValue(entry.value, depth: depth + 1);
      }
    }
    return result;
  }
  if (value is Iterable) {
    final items = <Object?>[];
    var count = 0;
    for (final item in value) {
      count += 1;
      if (count > 20) {
        items.add('[truncated ${value.length - 20} items]');
        break;
      }
      items.add(sanitizeLogValue(item, depth: depth + 1));
    }
    return items;
  }
  if (value is String) return sanitizeLogText(value);
  return value;
}

String sanitizeLogText(String value, {int maxLength = 500}) {
  var sanitized = value.replaceAllMapped(
    RegExp(r'(Bearer\s+)[A-Za-z0-9._-]+', caseSensitive: false),
    (match) => '${match.group(1)}[redacted]',
  );
  sanitized = sanitized.replaceAllMapped(
    RegExp(
      r'("?(?:password|token|secret|authorization)"?\s*[:=]\s*)("[^"]+"|[^\s,}]+)',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}[redacted]',
  );
  sanitized = sanitized.replaceAll(
    RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'),
    '[redacted-email]',
  );
  sanitized = sanitized.replaceAll(
    RegExp(r'C:\\Users\\[^\\]+\\', caseSensitive: false),
    r'C:\Users\[user]\',
  );
  sanitized = sanitized.replaceAllMapped(
    RegExp(r'(https?://[^\s?#]+)\?[^\s#]*', caseSensitive: false),
    (match) => '${match.group(1)}?[redacted-query]',
  );
  if (sanitized.length <= maxLength) return sanitized;
  return '${sanitized.substring(0, maxLength)}...[truncated]';
}

Map<String, Object?>? _decodeLogLine(String line) {
  try {
    final decoded = jsonDecode(line);
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (_) {
    return null;
  }
  return null;
}

String _normalizedText(Object? value, {required String fallback}) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return fallback;
  return sanitizeLogText(text);
}

bool _isSensitiveKey(String key) {
  return RegExp(
    'token|password|secret|authorization',
    caseSensitive: false,
  ).hasMatch(key);
}

bool _isPersonalDataKey(String key) {
  return RegExp(
    r'(^|_)(email|phone|customerName)(_|$)|email|phone',
    caseSensitive: false,
  ).hasMatch(key);
}

bool _isNotable(String level, String message) {
  if (level == 'warn' || level == 'error' || level == 'fatal') return true;
  return RegExp(
    'failed|failure|exception|crashed|timeout',
    caseSensitive: false,
  ).hasMatch(message);
}

List<Map<String, Object?>> _topCountEntries(Map<String, int> counts, int max) {
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final countCompare = b.value.compareTo(a.value);
      if (countCompare != 0) return countCompare;
      return a.key.compareTo(b.key);
    });
  return entries
      .take(max)
      .map((entry) => {'name': entry.key, 'count': entry.value})
      .toList(growable: false);
}

List<Map<String, Object?>> _topMessageEntries(
  Map<_MessageKey, int> counts,
  int max,
) {
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final countCompare = b.value.compareTo(a.value);
      if (countCompare != 0) return countCompare;
      return a.key.message.compareTo(b.key.message);
    });
  return entries
      .take(max)
      .map(
        (entry) => {
          'source': entry.key.source,
          'level': entry.key.level,
          'message': entry.key.message,
          'count': entry.value,
        },
      )
      .toList(growable: false);
}

class _MessageKey {
  const _MessageKey({
    required this.source,
    required this.level,
    required this.message,
  });

  final String source;
  final String level;
  final String message;

  @override
  bool operator ==(Object other) {
    return other is _MessageKey &&
        other.source == source &&
        other.level == level &&
        other.message == message;
  }

  @override
  int get hashCode => Object.hash(source, level, message);
}
