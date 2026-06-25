import 'dart:convert';
import 'dart:io';

import 'daily_activity_log.dart';

const int appLogMaxBytes = 2 * 1024 * 1024;
const int appLogTrimTargetBytes = appLogMaxBytes ~/ 2;

List<String> normalizeAndRetainAppLogLines(
  Iterable<String> lines, {
  int maxBytes = appLogMaxBytes,
  int trimTargetBytes = appLogTrimTargetBytes,
}) {
  final normalized = <String>[];
  var normalizedBytes = 0;

  for (final line in lines) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) continue;
      final encoded = jsonEncode(sanitizeLogValue(decoded));
      normalized.add(encoded);
      normalizedBytes += utf8.encode(encoded).length + 1;
    } catch (_) {
      // Malformed or partially written lines are discarded during compaction.
    }
  }

  if (normalizedBytes <= maxBytes) return normalized;

  final retainedReversed = <String>[];
  var retainedBytes = 0;
  for (final line in normalized.reversed) {
    final lineBytes = utf8.encode(line).length + 1;
    if (retainedReversed.isNotEmpty &&
        retainedBytes + lineBytes > trimTargetBytes) {
      break;
    }
    retainedReversed.add(line);
    retainedBytes += lineBytes;
  }
  return retainedReversed.reversed.toList(growable: false);
}

Future<void> compactAppLogFile(File file) async {
  if (!await file.exists()) return;
  final normalized = normalizeAndRetainAppLogLines(await file.readAsLines());
  final content = normalized.isEmpty ? '' : '${normalized.join('\n')}\n';
  final tempFile = File('${file.path}.compact-$pid');
  final backupFile = File('${file.path}.backup-$pid');
  try {
    await tempFile.writeAsString(content, mode: FileMode.write, flush: true);
    if (await backupFile.exists()) await backupFile.delete();
    await file.rename(backupFile.path);
    try {
      await tempFile.rename(file.path);
    } catch (_) {
      if (await backupFile.exists()) {
        await backupFile.rename(file.path);
      }
      rethrow;
    }
    if (await backupFile.exists()) await backupFile.delete();
  } finally {
    if (await tempFile.exists()) await tempFile.delete();
  }
}
