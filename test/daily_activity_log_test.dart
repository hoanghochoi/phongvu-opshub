import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/daily_activity_log.dart';

void main() {
  group('DailyActivityLogSummary', () {
    test('summarizes only the target day and keeps notable errors', () {
      final summary = buildDailyActivityLogSummary(const [
        '{"ts":"2026-05-28T23:59:59.000","level":"info","source":"Auth","message":"Login succeeded"}',
        '{"ts":"2026-05-29T09:00:00.000","level":"info","source":"PaymentMonitor","message":"Payment notification audio played"}',
        '{"ts":"2026-05-29T09:01:00.000","level":"error","source":"PaymentMonitor","message":"Payment monitor poll failed","context":{"error":"Yeu cau qua lau"}}',
        '{"ts":"2026-05-30T00:00:01.000","level":"warn","source":"AppUpdate","message":"Update skipped"}',
      ], targetDate: DateTime(2026, 5, 29));

      expect(summary.logDate, '2026-05-29');
      expect(summary.scannedLines, 4);
      expect(summary.parsedLines, 4);
      expect(summary.matchedLines, 2);
      expect(summary.levelCounts, {'info': 1, 'error': 1});
      expect(summary.sourceCounts['PaymentMonitor'], 2);
      expect(summary.notableSamples, hasLength(1));
      expect(
        summary.notableSamples.single['message'],
        'Payment monitor poll failed',
      );
    });

    test('redacts sensitive values before building upload context', () {
      final summary = buildDailyActivityLogSummary(const [
        '{"ts":"2026-05-29T10:00:00.000","level":"error","source":"Auth","message":"Login crashed for staff@example.com Bearer abc.def","context":{"password":"secret","token":"abc","path":"C:\\\\Users\\\\Alice\\\\AppData\\\\Local"}}',
      ], targetDate: DateTime(2026, 5, 29));

      final context = summary.toContext(platform: 'windows');
      final samples = context['notableSamples']! as List<Map<String, Object?>>;
      final sample = samples.single;
      final sampleContext = sample['context']! as Map<String, Object?>;

      expect(sample['message'], contains('[redacted-email]'));
      expect(sample['message'], contains('Bearer [redacted]'));
      expect(sampleContext['password'], '[redacted]');
      expect(sampleContext['token'], '[redacted]');
      expect(sampleContext['path'], r'C:\Users\[user]\AppData\Local');
      expect(context['rawLogIncluded'], isFalse);
    });
  });
}
