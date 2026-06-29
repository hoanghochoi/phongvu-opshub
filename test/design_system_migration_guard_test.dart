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
}
