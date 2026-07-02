import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('feature UI only uses shared Design System primitives', () {
    final violations = <String>[];
    final checks = <(RegExp, String)>[
      (RegExp(r'\bColor\(0x'), 'raw Color'),
      (RegExp(r'\bTextStyle\('), 'raw TextStyle'),
      (RegExp(r'\bTextField\('), 'raw TextField'),
      (RegExp(r'\bTextFormField\('), 'raw TextFormField'),
      (RegExp(r'\bCard\('), 'raw Card'),
      (
        RegExp(r'\b(?:Filled|Outlined|Elevated|Text)Button(?:\.icon)?\('),
        'raw button',
      ),
      (RegExp(r'\bDropdownButtonFormField'), 'raw dropdown'),
      (RegExp(r'\bInputDecoration\('), 'raw input decoration'),
      (RegExp(r'\bRadius\.circular\([0-9]'), 'raw radius'),
    ];

    final files = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index += 1) {
        final line = lines[index];
        if (line.contains('Colors.') && !line.contains('AppColors.')) {
          violations.add('${file.path}:${index + 1}: raw Colors');
        }
        for (final (pattern, label) in checks) {
          if (pattern.hasMatch(line)) {
            violations.add('${file.path}:${index + 1}: $label');
          }
        }
      }
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('legacy chat namespace stays retired in favor of fifo_check', () {
    final legacyFeaturePath = [
      'lib',
      'features',
      'chat',
    ].join(Platform.pathSeparator);
    expect(Directory(legacyFeaturePath).existsSync(), isFalse);

    final legacyProvider = ['Chat', 'Provider'].join();
    final legacyRepository = ['Chat', 'Repository'].join();
    final legacyModel = ['Message', 'Model'].join();
    final legacyNames = RegExp(
      '\\b(?:$legacyProvider|$legacyRepository|$legacyModel)\\b'
      r'|features[\\/]'
      'chat',
    );
    final hits = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index += 1) {
        if (legacyNames.hasMatch(lines[index])) {
          hits.add('${file.path}:${index + 1}');
        }
      }
    }

    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('exposed feature screens do not use legacy GradientHeader shells', () {
    final allowedNonRoutedLegacyFiles = {
      'lib/features/admin/presentation/screens/personnel_catalog_admin_screen.dart',
      'lib/features/fifo_check/presentation/screens/fifo_check_conversation_screen.dart',
    };
    final legacyHeaderPattern = RegExp(
      r"gradient_header\.dart|(?:\bGradientHeader\s*\()",
    );
    final hits = <String>[];
    final files = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in files) {
      final normalizedPath = file.path.replaceAll(r'\', '/');
      if (allowedNonRoutedLegacyFiles.contains(normalizedPath)) continue;

      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index += 1) {
        if (legacyHeaderPattern.hasMatch(lines[index])) {
          hits.add('$normalizedPath:${index + 1}');
        }
      }
    }

    final routerSource = File(
      [
        'lib',
        'app',
        'navigation',
        'app_router.dart',
      ].join(Platform.pathSeparator),
    ).readAsStringSync();
    expect(routerSource.contains('PersonnelCatalogAdminScreen'), isFalse);
    expect(routerSource.contains('FifoCheckConversationScreen'), isFalse);
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('feature progress indicators stay limited to reviewed inline states', () {
    const reviewedInlineIndicators = <String, ({int count, String reason})>{
      'lib/features/admin/presentation/screens/feedback_admin_screen.dart': (
        count: 2,
        reason: 'submit action and image viewer',
      ),
      'lib/features/warranty/presentation/screens/warranty_details_screen.dart':
          (count: 1, reason: 'cached image placeholder'),
      'lib/features/offset_adjustment/presentation/screens/offset_adjustment_screen.dart':
          (count: 1, reason: 'inline refresh progress'),
      'lib/features/settings/presentation/screens/settings_screen.dart': (
        count: 1,
        reason: 'log action progress',
      ),
      'lib/features/fifo/presentation/screens/fifo_history_screen.dart': (
        count: 1,
        reason: 'load-more row',
      ),
      'lib/features/fifo/presentation/screens/fifo_check_screen.dart': (
        count: 1,
        reason: 'result action progress',
      ),
      'lib/features/payment_monitor/presentation/widgets/payment_delivery_metrics_chip.dart':
          (count: 2, reason: 'compact metric chips'),
      'lib/features/payment_monitor/presentation/screens/payment_monitor_screen.dart':
          (count: 1, reason: 'inline refresh progress'),
      'lib/features/bank_statement/presentation/screens/bank_statement_screen.dart':
          (count: 1, reason: 'inline refresh progress'),
      'lib/features/vietqr/presentation/widgets/payment_waiting_card.dart': (
        count: 1,
        reason: 'payment waiting status',
      ),
      'lib/features/sales_report/presentation/screens/sales_report_screen.dart':
          (count: 1, reason: 'form submit action'),
    };
    final actual = <String, int>{};
    final indicatorPattern = RegExp(
      r'\b(?:Circular|Linear)ProgressIndicator\s*\(',
    );
    final files = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in files) {
      final count = indicatorPattern.allMatches(file.readAsStringSync()).length;
      if (count == 0) continue;
      actual[file.path.replaceAll(r'\', '/')] = count;
    }

    final expected = {
      for (final entry in reviewedInlineIndicators.entries)
        entry.key: entry.value.count,
    };
    expect(
      actual,
      equals(expected),
      reason:
          'Full loading/empty/error states must use AppStatePanel. '
          'Review any new inline indicator and document why it cannot use the shared state.',
    );
  });

  test('screen Center fallback stays limited to compact payment rows', () {
    final hits = <String>[];
    final centerReturnPattern = RegExp(r'return\s+(?:const\s+)?Center\s*\(');
    final files = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('_screen.dart'));

    for (final file in files) {
      final normalizedPath = file.path.replaceAll(r'\', '/');
      final count = centerReturnPattern
          .allMatches(file.readAsStringSync())
          .length;
      for (var index = 0; index < count; index += 1) {
        hits.add(normalizedPath);
      }
    }

    expect(
      hits,
      equals([
        'lib/features/payment_monitor/presentation/screens/payment_monitor_screen.dart',
      ]),
      reason:
          'The only screen-level Center fallback is the compact transaction '
          'label below 130px height; normal states use AppStatePanel.',
    );
  });
}
