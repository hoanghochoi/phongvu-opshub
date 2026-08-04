import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/features/help/domain/help_content_page.dart';
import 'package:phongvu_opshub/features/help/presentation/screens/help_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  testWidgets('Help screen renders runtime pages and switches sections', (
    tester,
  ) async {
    var backPressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: HelpScreen(
          onBack: () => backPressed += 1,
          loader: () async => HelpContentPublicSnapshot(
            pages: const [
              HelpContentPage(
                id: 'page-getting-started',
                key: 'getting-started',
                title: 'Bắt đầu sử dụng',
                fileName: 'getting-started.md',
                parentKey: 'guide',
                sortOrder: 0,
                markdown: '# Bắt đầu\nLàm quen với OpsHub',
                isPublished: true,
                seededFromDocsAt: null,
                updatedAt: null,
                updatedByUserId: null,
                updatedByEmail: null,
              ),
              HelpContentPage(
                id: 'page-home',
                key: 'home',
                title: 'Trang chủ',
                fileName: 'home.md',
                parentKey: 'guide',
                sortOrder: 1,
                markdown: '# Trang chủ\nTổng quan vận hành',
                isPublished: true,
                seededFromDocsAt: null,
                updatedAt: null,
                updatedByUserId: null,
                updatedByEmail: null,
              ),
              HelpContentPage(
                id: 'page-roadmap',
                key: 'roadmap',
                title: 'Roadmap',
                fileName: 'roadmap.md',
                parentKey: null,
                sortOrder: 1,
                markdown: '# Roadmap\nNhững gì sắp tới',
                isPublished: true,
                seededFromDocsAt: null,
                updatedAt: null,
                updatedByUserId: null,
                updatedByEmail: null,
              ),
              HelpContentPage(
                id: 'page-guide',
                key: 'guide',
                title: 'Hướng dẫn sử dụng',
                fileName: 'index.md',
                parentKey: null,
                sortOrder: 0,
                markdown: '# Chào mừng\nNội dung trang gốc',
                isPublished: true,
                seededFromDocsAt: null,
                updatedAt: null,
                updatedByUserId: null,
                updatedByEmail: null,
              ),
            ],
            updatedAt: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('help-screen-header')), findsOneWidget);
    expect(find.text('Kho nội dung hỗ trợ OpsHub'), findsOneWidget);
    expect(find.byTooltip('Quay lại'), findsOneWidget);
    expect(find.text('Hướng dẫn sử dụng'), findsWidgets);
    expect(find.text('Nội dung trang gốc'), findsOneWidget);
    expect(find.byKey(const Key('help-nav-item-guide')), findsOneWidget);
    expect(
      find.byKey(const Key('help-nav-item-getting-started')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('help-nav-item-home')), findsOneWidget);
    expect(find.byKey(const Key('help-nav-item-roadmap')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('help-nav-item-guide'))).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const Key('help-nav-item-getting-started')))
            .dy,
      ),
    );
    expect(
      tester
          .getTopLeft(find.byKey(const Key('help-nav-item-getting-started')))
          .dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('help-nav-item-home'))).dy,
      ),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('help-nav-item-home'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('help-nav-item-roadmap'))).dy,
      ),
    );

    await tester.tap(find.byKey(const Key('help-nav-item-getting-started')));
    await tester.pumpAndSettle();

    expect(find.text('Bắt đầu sử dụng'), findsWidgets);
    expect(find.text('Thuộc mục Hướng dẫn sử dụng'), findsOneWidget);
    expect(find.text('Làm quen với OpsHub'), findsOneWidget);
    expect(find.text('Nội dung trang gốc'), findsNothing);

    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pumpAndSettle();

    expect(backPressed, 1);
  });

  testWidgets(
    'embedded Help screen stays inside shell content without app bar',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HelpScreen(
              embeddedInShell: true,
              loader: () async => HelpContentPublicSnapshot(
                pages: const [
                  HelpContentPage(
                    id: 'page-guide',
                    key: 'guide',
                    title: 'Hướng dẫn sử dụng',
                    fileName: 'index.md',
                    parentKey: null,
                    sortOrder: 0,
                    markdown: '# Chào mừng\nNội dung trang gốc',
                    isPublished: true,
                    seededFromDocsAt: null,
                    updatedAt: null,
                    updatedByUserId: null,
                    updatedByEmail: null,
                  ),
                ],
                updatedAt: null,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsNothing);
      expect(find.byTooltip('Quay lại'), findsNothing);
      expect(find.byTooltip('Tải lại hướng dẫn'), findsOneWidget);
      expect(find.byKey(const Key('help-screen-header')), findsOneWidget);
      expect(find.text('Nội dung trang gốc'), findsOneWidget);
    },
  );

  testWidgets('public Help follows Figma desktop and tablet geometry', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1024);
    await tester.pumpWidget(MaterialApp(home: HelpScreen(loader: _snapshot)));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const Key('help-screen-header'))),
      const Size(1120, 114),
    );
    expect(
      tester.getSize(find.byKey(const Key('help-navigation-card'))),
      const Size(300, 290),
    );
    expect(
      tester.getSize(find.byKey(const Key('help-content-card'))),
      const Size(804, 329),
    );
    expect(tester.getSize(find.byTooltip('Quay lại')), const Size(48, 48));

    tester.view.physicalSize = const Size(1024, 768);
    await tester.pumpWidget(MaterialApp(home: HelpScreen(loader: _snapshot)));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('help-screen-header'))),
      const Size(992, 114),
    );
    expect(
      tester.getSize(find.byKey(const Key('help-navigation-card'))),
      const Size(992, 290),
    );
    expect(
      tester.getSize(find.byKey(const Key('help-content-card'))),
      const Size(992, 329),
    );
  });

  testWidgets('authenticated Help follows compact and tablet shell geometry', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HelpScreen(embeddedInShell: true, loader: _snapshot),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('help-screen-header'))),
      const Size(343, 148),
    );
    expect(
      tester.getSize(find.byKey(const Key('help-navigation-card'))),
      const Size(343, 290),
    );
    expect(
      tester.getSize(find.byKey(const Key('help-content-card'))),
      const Size(343, 455),
    );

    tester.view.physicalSize = const Size(834, 1112);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HelpScreen(embeddedInShell: true, loader: _snapshot),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('help-navigation-card'))).width,
      210,
    );
    expect(
      tester.getSize(find.byKey(const Key('help-content-card'))).width,
      480,
    );
  });
}

Future<HelpContentPublicSnapshot> _snapshot() async {
  return HelpContentPublicSnapshot(
    pages: [
      const HelpContentPage(
        id: 'page-getting-started',
        key: 'getting-started',
        title: 'Bắt đầu sử dụng',
        fileName: 'getting-started.md',
        parentKey: 'guide',
        sortOrder: 0,
        markdown:
            '# Bắt đầu\nLàm quen với OpsHub\n\n## Tiếp theo\nChọn công cụ phù hợp.',
        isPublished: true,
        seededFromDocsAt: null,
        updatedAt: null,
        updatedByUserId: null,
        updatedByEmail: null,
      ),
      const HelpContentPage(
        id: 'page-home',
        key: 'home',
        title: 'Trang chủ',
        fileName: 'home.md',
        parentKey: 'guide',
        sortOrder: 1,
        markdown: '# Trang chủ\nTổng quan vận hành',
        isPublished: true,
        seededFromDocsAt: null,
        updatedAt: null,
        updatedByUserId: null,
        updatedByEmail: null,
      ),
      const HelpContentPage(
        id: 'page-roadmap',
        key: 'roadmap',
        title: 'Roadmap',
        fileName: 'roadmap.md',
        parentKey: null,
        sortOrder: 1,
        markdown: '# Roadmap\nNhững gì sắp tới',
        isPublished: true,
        seededFromDocsAt: null,
        updatedAt: null,
        updatedByUserId: null,
        updatedByEmail: null,
      ),
      HelpContentPage(
        id: 'page-guide',
        key: 'guide',
        title: 'Hướng dẫn sử dụng',
        fileName: 'index.md',
        parentKey: null,
        sortOrder: 0,
        markdown:
            '# Chào mừng\nNội dung trang gốc\n\n## Bắt đầu\nChọn đúng không gian làm việc.',
        isPublished: true,
        seededFromDocsAt: null,
        updatedAt: DateTime.utc(2026, 7, 27, 10, 30),
        updatedByUserId: null,
        updatedByEmail: null,
      ),
    ],
    updatedAt: DateTime.utc(2026, 7, 27, 10, 30),
  );
}
