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
}
