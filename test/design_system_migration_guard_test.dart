import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app text selection and dialog dismissal contracts stay global', () {
    final appSource = File('lib/app/app.dart').readAsStringSync();
    expect(
      appSource,
      contains('AppGlobalSelectionScope('),
      reason:
          'MaterialApp.builder must keep route and overlay text selectable.',
    );

    final blockedDismissal = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final pattern = RegExp(r'barrierDismissible\s*:\s*false');
    for (final file in files) {
      final normalizedPath = file.path.replaceAll(r'\', '/');
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index += 1) {
        if (pattern.hasMatch(lines[index])) {
          blockedDismissal.add('$normalizedPath:${index + 1}');
        }
      }
    }

    expect(
      blockedDismissal,
      isEmpty,
      reason:
          'Dialogs must dismiss outside; dirty editors use AppDirtyFormGuard.\n'
          '${blockedDismissal.join('\n')}',
    );
  });

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
      (
        RegExp(
          r'\b(?:DropdownButtonFormField|DropdownButton|DropdownMenuItem)',
        ),
        'raw dropdown',
      ),
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

  test('all runtime editable fields keep the shared paste policy', () {
    const sharedInputFiles = <String>{
      'lib/app/widgets/app_inputs.dart',
      'lib/app/widgets/app_combobox.dart',
    };
    final rawInputPattern = RegExp(r'\b(?:TextField|TextFormField)\(');
    final unexpectedRawInputs = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in files) {
      final normalizedPath = file.path.replaceAll(r'\', '/');
      if (sharedInputFiles.contains(normalizedPath)) continue;
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index += 1) {
        if (rawInputPattern.hasMatch(lines[index])) {
          unexpectedRawInputs.add('$normalizedPath:${index + 1}');
        }
      }
    }

    expect(
      unexpectedRawInputs,
      isEmpty,
      reason:
          'New editable fields must reuse the shared selection/paste policy.\n'
          '${unexpectedRawInputs.join('\n')}',
    );

    final appInputsSource = File(
      'lib/app/widgets/app_inputs.dart',
    ).readAsStringSync();
    final editableInputSource = appInputsSource
        .split('class AppReadOnlyField')
        .first;
    expect(
      RegExp(
        r'\b(?:TextField|TextFormField)\(',
      ).allMatches(editableInputSource).length,
      2,
    );
    expect(
      RegExp(
        r'SelectionContainer\.disabled\(',
      ).allMatches(editableInputSource).length,
      2,
    );
    expect(
      RegExp(
        r'contextMenuBuilder:\s*appTextInputContextMenuBuilder\(\)',
      ).allMatches(editableInputSource).length,
      2,
    );

    final comboboxSource = File(
      'lib/app/widgets/app_combobox.dart',
    ).readAsStringSync();
    expect(RegExp(r'\bTextField\(').allMatches(comboboxSource).length, 1);
    expect(comboboxSource, contains('SelectionContainer.disabled('));
    expect(
      comboboxSource,
      contains('contextMenuBuilder: appTextInputContextMenuBuilder()'),
    );
  });

  test('runtime does not keep retired local dropdown primitives', () {
    final retiredDropdownPattern = RegExp(
      r'\b(?:AppFilterDropdown|AppSearchableFilterDropdown|'
      r'AppMultiSelectFilterDropdown|AppSelectField|'
      r'DropdownButtonFormField|DropdownButton|DropdownMenuItem)\b',
    );
    final hits = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where(
          (file) => !file.path
              .replaceAll(r'\', '/')
              .contains('/app/widgets/date_range_picker/'),
        );

    for (final file in files) {
      final normalizedPath = file.path.replaceAll(r'\', '/');
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index += 1) {
        if (retiredDropdownPattern.hasMatch(lines[index])) {
          hits.add('$normalizedPath:${index + 1}');
        }
      }
    }

    expect(
      hits,
      isEmpty,
      reason:
          'Use AppCombobox/AppDateRangeDropdown instead.\n${hits.join('\n')}',
    );
  });

  test('date range filters only use the canonical shared picker', () {
    final violations = <String>[];
    final forbiddenPattern = RegExp(
      r'\b(?:showDateRangePicker|DateRangePickerDialog|SfDateRangePicker|'
      r'CalendarDatePicker2|TableCalendar)\b',
    );
    final calendarImportPattern = RegExp(
      r'''^import ['"][^'"]*(?:table_calendar|syncfusion_flutter_datepicker|calendar_date_picker2)[^'"]*['"]''',
    );
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where(
          (file) => !file.path
              .replaceAll(r'\', '/')
              .contains('/app/widgets/date_range_picker/'),
        );

    for (final file in files) {
      final normalizedPath = file.path.replaceAll(r'\', '/');
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index += 1) {
        if (forbiddenPattern.hasMatch(lines[index]) ||
            calendarImportPattern.hasMatch(lines[index])) {
          violations.add('$normalizedPath:${index + 1}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'All date range filters must reuse DateRangePicker.\n'
          '${violations.join('\n')}',
    );
  });

  test('feature pagination uses the shared pagination control', () {
    final directPaginationPattern = RegExp(r"""["']Trang (?:trước|sau)["']""");
    final hits = <String>[];
    final files = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in files) {
      final normalizedPath = file.path.replaceAll(r'\', '/');
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index += 1) {
        if (directPaginationPattern.hasMatch(lines[index])) {
          hits.add('$normalizedPath:${index + 1}');
        }
      }
    }

    expect(
      hits,
      isEmpty,
      reason:
          'Use AppPaginationControls for page navigation.\n${hits.join('\n')}',
    );
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

  test('production UI does not keep legacy GradientHeader shells', () {
    final legacyHeaderPattern = RegExp(
      r"gradient_header\.dart|(?:\bGradientHeader\s*\()",
    );
    final hits = <String>[];
    final legacyHeaderFile = File(
      [
        'lib',
        'app',
        'widgets',
        'gradient_header.dart',
      ].join(Platform.pathSeparator),
    );
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    expect(
      legacyHeaderFile.existsSync(),
      isFalse,
      reason:
          'GradientHeader should stay retired after the AppShell migration.',
    );
    for (final file in files) {
      final normalizedPath = file.path.replaceAll(r'\', '/');
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
    expect(routerSource.contains('FifoCheckConversationScreen'), isFalse);
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('scan callers use the shared barcode scanner navigation helper', () {
    final directScannerPattern = RegExp(r'\bBarcodeScannerScreen\s*\(');
    final hits = <String>[];
    final files = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) {
          final normalizedPath = file.path.replaceAll(r'\', '/');
          return file.path.endsWith('.dart') &&
              !normalizedPath.endsWith(
                'fifo_check/presentation/widgets/barcode_scanner_screen.dart',
              );
        });
    for (final file in files) {
      final normalizedPath = file.path.replaceAll(r'\', '/');
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index += 1) {
        if (directScannerPattern.hasMatch(lines[index])) {
          hits.add('$normalizedPath:${index + 1}');
        }
      }
    }

    expect(
      hits,
      isEmpty,
      reason:
          'Use showBarcodeScanner so scanner UI/service swaps stay central.',
    );
  });

  test('feature routes do not nest local Scaffold shells', () {
    const allowedScaffoldFiles = <String, String>{
      'lib/features/auth/presentation/widgets/auth_screen_shell.dart':
          'public auth shell outside AppShell',
      'lib/features/fifo_check/presentation/widgets/barcode_scanner_screen.dart':
          'fullscreen scanner modal outside AppShell',
      'lib/features/help/presentation/screens/help_screen.dart':
          'public help route outside AppShell',
    };
    final scaffoldPattern = RegExp(r'\bScaffold\s*\(');
    final hits = <String>[];
    final files = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in files) {
      final normalizedPath = file.path.replaceAll(r'\', '/');
      final allowedReason = allowedScaffoldFiles[normalizedPath];
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index += 1) {
        if (!scaffoldPattern.hasMatch(lines[index])) continue;
        if (allowedReason != null) continue;
        hits.add('$normalizedPath:${index + 1}');
      }
    }

    expect(
      hits,
      isEmpty,
      reason:
          'Authenticated feature routes should render content-only under AppShell.',
    );
  });

  test('feature screens stay bounded by shared responsive wrappers', () {
    const shellBoundedScreens = <String, String>{
      'lib/features/auth/presentation/screens/assignment_pending_screen.dart':
          'public auth flow is bounded by AuthScreenShell',
      'lib/features/auth/presentation/screens/email_check_screen.dart':
          'public auth flow is bounded by AuthScreenShell',
      'lib/features/auth/presentation/screens/forgot_password_screen.dart':
          'public auth flow is bounded by AuthScreenShell',
      'lib/features/auth/presentation/screens/register_screen.dart':
          'public auth flow is bounded by AuthScreenShell',
      'lib/features/fifo_check/presentation/widgets/barcode_scanner_screen.dart':
          'fullscreen scanner modal owns its own shell',
    };
    final responsiveWrapperPattern = RegExp(
      r'\bAppResponsive(?:Content|ScrollView)\s*\(',
    );
    final hits = <String>[];
    final files = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('_screen.dart'));

    for (final file in files) {
      final normalizedPath = file.path.replaceAll(r'\', '/');
      if (shellBoundedScreens.containsKey(normalizedPath)) continue;
      if (responsiveWrapperPattern.hasMatch(file.readAsStringSync())) {
        continue;
      }
      hits.add('$normalizedPath: missing shared responsive wrapper');
    }

    expect(
      hits,
      isEmpty,
      reason:
          'Authenticated feature screens must use AppResponsiveContent or '
          'AppResponsiveScrollView so desktop pages stay width-bounded.',
    );
  });

  test('feature content does not repeat shell destination labels as headers', () {
    const shellDestinationLabels = <String>[
      'Trang chủ',
      'Quản trị',
      'FIFO',
      'Bảo hành',
      'VietQR',
      'Tiền vào',
      'Sao kê',
      'Cấn trừ',
      'Báo cáo',
      'Góp ý',
      'Cài đặt',
      'Tài khoản',
    ];
    final hits = <String>[];
    final files = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) {
          final normalizedPath = file.path.replaceAll(r'\', '/');
          return file.path.endsWith('.dart') &&
              normalizedPath.contains('/presentation/screens/');
        });

    for (final file in files) {
      final normalizedPath = file.path.replaceAll(r'\', '/');
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index += 1) {
        final line = lines[index];
        for (final label in shellDestinationLabels) {
          final escapedLabel = RegExp.escape(label);
          final repeatsHeading = RegExp(
            "Text\\(\\s*'$escapedLabel'\\s*,\\s*style:\\s*AppTextStyles\\.heading",
          ).hasMatch(line);
          final repeatsHeaderTitle = RegExp(
            "title:\\s*'$escapedLabel'\\s*,",
          ).hasMatch(line);
          if (repeatsHeading || repeatsHeaderTitle) {
            hits.add('$normalizedPath:${index + 1}: $label');
          }
        }
      }
    }

    expect(
      hits,
      isEmpty,
      reason:
          'The shell top bar owns destination titles; feature content should '
          'use task/status-specific headings instead of repeating them.',
    );
  });

  test('feature UI copy does not expose internal abbreviations', () {
    final blockedPatterns = <(RegExp, String)>[
      (RegExp(r'\bBH\s*/\s*SC\b'), 'BH/SC'),
      (RegExp(r'\bERP\b'), 'ERP'),
      (RegExp(r'\bSR\b'), 'SR'),
      (RegExp(r'\bpolicy\b', caseSensitive: false), 'policy'),
      (RegExp(r'\brule\b', caseSensitive: false), 'rule'),
      (RegExp(r'\bnode\b', caseSensitive: false), 'node'),
      (RegExp(r'\binternal\b', caseSensitive: false), 'internal'),
      (RegExp(r'\bJSON\b'), 'JSON'),
      (RegExp(r'\bKey\b'), 'Key'),
    ];
    const visibleMarkers = <String>[
      'Text(',
      'SelectableText(',
      'title:',
      'message:',
      'label:',
      'hintText:',
      'helperText:',
      'tooltip:',
      'emptyLabel:',
      'allLabel:',
      'actionLabel:',
      'loadingLabel:',
      'content: Text(',
    ];
    final stringLiteralPattern = RegExp(r"'([^'\\]*(?:\\.[^'\\]*)*)'");
    final hits = <String>[];
    final files = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) {
          final normalizedPath = file.path.replaceAll(r'\', '/');
          return file.path.endsWith('.dart') &&
              (normalizedPath.contains('/presentation/screens/') ||
                  normalizedPath.contains('/presentation/widgets/'));
        });

    for (final file in files) {
      final normalizedPath = file.path.replaceAll(r'\', '/');
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index += 1) {
        final line = lines[index];
        final previousLine = index == 0 ? '' : lines[index - 1];
        final isLikelyVisibleCopy =
            visibleMarkers.any(line.contains) ||
            visibleMarkers.any(previousLine.contains);
        if (!isLikelyVisibleCopy) continue;

        for (final literalMatch in stringLiteralPattern.allMatches(line)) {
          final literal = literalMatch.group(1)!;
          if (literal.contains(r'${') && !literal.contains('}')) continue;
          final visibleText = literal.replaceAll(RegExp(r'\$\{[^}]*\}'), '{}');
          for (final (pattern, label) in blockedPatterns) {
            if (pattern.hasMatch(visibleText)) {
              hits.add('$normalizedPath:${index + 1}: $label -> $visibleText');
            }
          }
        }
      }
    }

    expect(
      hits,
      isEmpty,
      reason:
          'Visible UI copy should use Vietnamese-first business labels instead '
          'of internal abbreviations or programming terms.',
    );
  });

  test('feature route pushes stay limited to reviewed modal surfaces', () {
    const allowedRoutePushFiles = <String, String>{
      'lib/features/fifo_check/presentation/widgets/barcode_scanner_screen.dart':
          'shared fullscreen scanner modal',
      'lib/features/warranty/presentation/screens/warranty_details_screen.dart':
          'receipt image viewer modal',
    };
    final materialRoutePattern = RegExp(r'\bMaterialPageRoute\s*\(');
    final hits = <String>[];
    final files = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in files) {
      final normalizedPath = file.path.replaceAll(r'\', '/');
      final allowedReason = allowedRoutePushFiles[normalizedPath];
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index += 1) {
        if (!materialRoutePattern.hasMatch(lines[index])) continue;
        if (allowedReason != null) continue;
        hits.add('$normalizedPath:${index + 1}');
      }
    }

    expect(
      hits,
      isEmpty,
      reason:
          'Feature navigation should stay in AppRouter; add exceptions only for reviewed modals.',
    );
  });

  test('approved Figma route gaps are routed through runtime screens', () {
    final routerSource = File(
      [
        'lib',
        'app',
        'navigation',
        'app_router.dart',
      ].join(Platform.pathSeparator),
    ).readAsStringSync();

    const requiredRouteMarkers = <String>[
      "path: '/reports'",
      "redirect: (context, state) => '/sales-reports'",
      'PersonnelCatalogAdminScreen',
      "path: '/admin/personnel'",
      'SalesTargetAdminScreen',
      "path: '/admin/sales-targets'",
      "'/reports' => 'SALES_REPORT'",
      "'/admin/personnel' => 'ADMIN_PERSONNEL'",
      "'/admin/sales-targets' => 'ADMIN_SALES_TARGETS'",
    ];
    for (final marker in requiredRouteMarkers) {
      expect(routerSource, contains(marker));
    }

    final gapMap = File(
      [
        'docs',
        'product',
        'opshub-redesign-gap-map-2026-07-01.md',
      ].join(Platform.pathSeparator),
    ).readAsStringSync();
    final testMatrix = File(
      ['docs', 'TEST_MATRIX.md'].join(Platform.pathSeparator),
    ).readAsStringSync();

    expect(
      gapMap,
      isNot(
        contains(
          '`PersonnelCatalogAdminScreen` và `FifoCheckConversationScreen` không nằm',
        ),
      ),
    );
    expect(
      gapMap,
      contains(
        '`PersonnelCatalogAdminScreen` đã được mở route thật `/admin/personnel`',
      ),
    );
    expect(
      testMatrix,
      contains(
        '`PersonnelCatalogAdminScreen` is now an approved runtime route',
      ),
    );
  });

  test('retired Figma route gaps stay documented and non-routed', () {
    final gapMap = File(
      [
        'docs',
        'product',
        'opshub-redesign-gap-map-2026-07-01.md',
      ].join(Platform.pathSeparator),
    ).readAsStringSync();
    final backlog = File(
      ['docs', 'stories', 'backlog.md'].join(Platform.pathSeparator),
    ).readAsStringSync();
    final routerSource = File(
      [
        'lib',
        'app',
        'navigation',
        'app_router.dart',
      ].join(Platform.pathSeparator),
    ).readAsStringSync();

    expect(gapMap, contains('| Data Workspace | Retired / hidden in Figma |'));
    expect(
      gapMap,
      contains('| FIFO Conversation Check | Retired / hidden in Figma |'),
    );
    expect(gapMap, contains('Figma retire sync 03/07/2026'));
    expect(gapMap, contains('Retired / Desktop v2 / Data Workspace'));
    expect(gapMap, contains('Retired / Desktop v2 / FIFO Conversation Check'));
    expect(gapMap, contains('visible=false'));
    expect(gapMap, contains('activeRetired: []'));
    expect(backlog, isNot(contains('Resolve Figma Data Workspace route gap')));
    expect(
      backlog,
      isNot(contains('Decide FIFO Conversation Check route fate')),
    );
    expect(
      File(
        [
          'lib',
          'features',
          'fifo_check',
          'presentation',
          'screens',
          'fifo_check_conversation_screen.dart',
        ].join(Platform.pathSeparator),
      ).existsSync(),
      isFalse,
    );

    const forbiddenRouteMarkers = <String>[
      'DataWorkspaceScreen',
      'FifoCheckConversationScreen',
      "path: '/data'",
      "path: '/data-workspace'",
      "path: '/report-workspace'",
      "path: '/fifo-conversation'",
      "path: '/fifo/check-conversation'",
    ];
    for (final marker in forbiddenRouteMarkers) {
      expect(
        routerSource.contains(marker),
        isFalse,
        reason:
            '$marker must stay non-routed until the product contract is approved.',
      );
    }
  });

  test(
    'Figma handoff inventory keeps screen pages separate from cover subset',
    () {
      final gapMap = File(
        [
          'docs',
          'product',
          'opshub-redesign-gap-map-2026-07-01.md',
        ].join(Platform.pathSeparator),
      ).readAsStringSync();
      final testMatrix = File(
        ['docs', 'TEST_MATRIX.md'].join(Platform.pathSeparator),
      ).readAsStringSync();

      expect(gapMap, contains('cover page hiện là curated subset'));
      expect(
        gapMap,
        contains('Figma screen-page inventory follow-up 03/07/2026'),
      );
      expect(gapMap, contains('40 unique runtime groups active'));
      expect(gapMap, contains('duplicateGroups: []'));
      expect(gapMap, contains('retiredVisible: []'));
      expect(
        gapMap,
        contains(
          'Archived / Desktop v2 / VietQR Workspace (superseded by 398:14)',
        ),
      );
      expect(
        gapMap,
        contains(
          'Archived / Desktop v2 / Statement Workspace (superseded by 388:2)',
        ),
      );
      expect(gapMap, contains('physical acceptance 03/07/2026'));
      expect(testMatrix, contains('OPSHUB_VISUAL_SMOKE_WARRANTY_RECEIPT'));
      expect(testMatrix, contains('the cover page is only a curated subset'));
      expect(
        testMatrix,
        contains('desktop now exposes 40 unique active runtime groups'),
      );
    },
  );

  test('feature progress indicators stay limited to reviewed inline states', () {
    const reviewedInlineIndicators = <String, ({int count, String reason})>{
      'lib/features/admin/presentation/screens/feedback_admin_screen.dart': (
        count: 2,
        reason: 'submit action and image viewer',
      ),
      'lib/features/app_update/presentation/app_update_gate.dart': (
        count: 1,
        reason: 'inline package download and install action',
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
      'lib/features/home/presentation/widgets/home_summary_page.dart': (
        count: 1,
        reason: 'toolbar refresh state',
      ),
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

  test('web visual smoke routes stay aligned with AppRouter', () {
    final routerSource = File(
      [
        'lib',
        'app',
        'navigation',
        'app_router.dart',
      ].join(Platform.pathSeparator),
    ).readAsStringSync();
    final smokeSource = File(
      ['scripts', 'opshub-web-visual-smoke.mjs'].join(Platform.pathSeparator),
    ).readAsStringSync();
    final gapMap = File(
      [
        'docs',
        'product',
        'opshub-redesign-gap-map-2026-07-01.md',
      ].join(Platform.pathSeparator),
    ).readAsStringSync();
    final testMatrix = File(
      ['docs', 'TEST_MATRIX.md'].join(Platform.pathSeparator),
    ).readAsStringSync();

    final shellRoutes = _extractShellRoutePaths(routerSource);
    final publicSmokeRoutes = _extractRouteLiteralsBetween(
      smokeSource,
      startMarker: 'const publicRoutes',
      endMarker: 'const pendingRoutes',
    );
    final pendingSmokeRoutes = _extractRouteLiteralsBetween(
      smokeSource,
      startMarker: 'const pendingRoutes',
      endMarker: 'const defaultAuthenticatedRoutes',
    );
    final authenticatedSmokeRoutes = _extractRouteLiteralsBetween(
      smokeSource,
      startMarker: 'const defaultAuthenticatedRoutes',
      endMarker: 'if (!email',
    );

    expect(
      publicSmokeRoutes,
      equals(['/login', '/register', '/forgot-password']),
      reason:
          'Assignment-pending stays widget/Figma-covered until a live pending '
          'fixture exists; public smoke should cover only unauthenticated auth.',
    );
    expect(
      pendingSmokeRoutes,
      equals(['/assignment-pending']),
      reason:
          'Assignment-pending should render from a tokenless cached pending '
          'session so the auth pre-shell route gets live visual smoke coverage.',
    );
    expect(
      authenticatedSmokeRoutes,
      equals(shellRoutes),
      reason:
          'Every authenticated ShellRoute in AppRouter must stay in the default '
          'web visual smoke route set.',
    );
    expect(
      (publicSmokeRoutes.length +
              pendingSmokeRoutes.length +
              authenticatedSmokeRoutes.length) *
          2,
      86,
      reason: 'Default smoke should stay at 43 routes across 2 viewports.',
    );
    expect(smokeSource, contains('readPngVisualStats'));
    expect(smokeSource, contains('uniqueSampledColors < 16'));
    expect(smokeSource, contains('lumaRange < 12'));
    expect(smokeSource, contains('sanitizeSensitiveText'));
    expect(smokeSource, contains('[REDACTED_JWT]'));
    expect(smokeSource, contains('resolveAuthenticatedRoutes'));
    expect(
      smokeSource,
      contains(
        'const authenticatedRoutes = authenticatedRouteResolution.routes',
      ),
    );
    expect(smokeSource, contains('OPSHUB_VISUAL_SMOKE_WARRANTY_RECEIPT'));
    expect(smokeSource, contains('GET /warranties'));
    expect(smokeSource, contains('skippedRoutes'));
    expect(gapMap, contains('tổng 86 route/viewport checks'));
    expect(gapMap, contains('39\n  authenticated shell routes'));
    expect(testMatrix, contains('default live staging smoke now runs 86'));
    expect(testMatrix, contains('all 39 authenticated shell routes'));
  });
}

List<String> _extractShellRoutePaths(String routerSource) {
  final shellStart = routerSource.indexOf('ShellRoute(');
  final featureMapStart = routerSource.indexOf(
    'static String? _featureForRoute',
    shellStart,
  );
  if (shellStart < 0 || featureMapStart < 0) {
    throw StateError('Could not locate ShellRoute section in AppRouter.');
  }
  final shellSection = routerSource.substring(shellStart, featureMapStart);
  return RegExp(
    r"path:\s*'([^']+)'",
  ).allMatches(shellSection).map((match) => match.group(1)!).toList();
}

List<String> _extractRouteLiteralsBetween(
  String source, {
  required String startMarker,
  required String endMarker,
}) {
  final start = source.indexOf(startMarker);
  final end = source.indexOf(endMarker, start + startMarker.length);
  if (start < 0 || end < 0) {
    throw StateError('Could not locate route list between script markers.');
  }
  final section = source.substring(start, end);
  return RegExp(
    r"'(/[A-Za-z0-9/:-]+)'",
  ).allMatches(section).map((match) => match.group(1)!).toList();
}
