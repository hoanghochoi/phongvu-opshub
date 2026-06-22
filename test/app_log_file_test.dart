import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/app_log_file.dart';

void main() {
  group('normalizeAndRetainAppLogLines', () {
    test('drops malformed lines and redacts local diagnostic identifiers', () {
      final lines = normalizeAndRetainAppLogLines(const [
        'partial-json',
        '{"ts":"2026-06-22T10:00:00.000","level":"error","source":"Auth","message":"Login failed for staff@example.com","context":{"email":"staff@example.com","token":"abc","path":"C:\\\\Users\\\\Alice\\\\AppData\\\\Roaming"}}',
      ]);

      expect(lines, hasLength(1));
      final decoded = jsonDecode(lines.single) as Map<String, dynamic>;
      final context = decoded['context'] as Map<String, dynamic>;
      expect(decoded['message'], contains('[redacted-email]'));
      expect(context['email'], '[redacted-email]');
      expect(context['token'], '[redacted]');
      expect(context['path'], r'C:\Users\[user]\AppData\Roaming');
    });

    test('retains complete newest JSON lines when trimming', () {
      final lines = List<String>.generate(
        12,
        (index) => jsonEncode({
          'ts': '2026-06-22T10:00:${index.toString().padLeft(2, '0')}.000',
          'level': 'info',
          'source': 'Test',
          'message': 'event-$index-${'x' * 30}',
        }),
      );

      final retained = normalizeAndRetainAppLogLines(
        lines,
        maxBytes: 300,
        trimTargetBytes: 180,
      );

      expect(retained.length, lessThan(lines.length));
      expect(retained.last, contains('event-11-'));
      for (final line in retained) {
        expect(() => jsonDecode(line), returnsNormally);
      }
    });

    test('compacts a file through an atomic replacement', () async {
      final directory = await Directory.systemTemp.createTemp(
        'opshub-app-log-file-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}${Platform.pathSeparator}opshub.log');
      await file.writeAsString(
        'broken\n'
        '{"ts":"2026-06-22T10:00:00.000","level":"info","source":"Auth","message":"staff@example.com"}\n',
      );

      await compactAppLogFile(file);

      final lines = await file.readAsLines();
      expect(lines, hasLength(1));
      expect(lines.single, contains('[redacted-email]'));
      expect(
        directory.listSync().where(
          (entry) =>
              entry.path.contains('.compact-') ||
              entry.path.contains('.backup-'),
        ),
        isEmpty,
      );
    });
  });
}
