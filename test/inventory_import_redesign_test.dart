import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/legacy_widget_finders.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/features/admin/data/repositories/inventory_import_repository.dart';
import 'package:phongvu_opshub/features/admin/presentation/screens/inventory_import_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  testWidgets('Inventory import renders content-only upload and result flow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? uploadedPath;

    await tester.pumpWidget(
      MaterialApp(
        home: InventoryImportScreen(
          filePicker: () async => const InventoryPickedFile(
            name: 'ton-kho-fifo.xlsx',
            path: 'C:/tmp/ton-kho-fifo.xlsx',
            size: 2048,
          ),
          uploader: (path) async {
            uploadedPath = path;
            return const InventoryImportResult(
              importedRows: 8,
              deactivatedRows: 1,
              skippedRows: 2,
              totalRows: 11,
              srCodes: ['CP62', 'CP75'],
            );
          },
        ),
      ),
    );

    expect(find.byKey(const Key('inventory-import-header')), findsOneWidget);
    expect(
      find.byKey(const Key('inventory-import-upload-panel')),
      findsOneWidget,
    );
    expect(find.text('Cập nhật tồn kho FIFO'), findsOneWidget);
    expect(find.text('Chưa chọn file Excel'), findsOneWidget);
    expect(findsLegacyGradientHeader(), findsNothing);
    expect(find.byType(Scaffold), findsNothing);

    await tester.tap(find.text('Chọn file'));
    await tester.pumpAndSettle();

    expect(find.text('ton-kho-fifo.xlsx'), findsOneWidget);
    expect(find.text('XLSX'), findsOneWidget);

    await tester.tap(find.text('Cập nhật tồn kho'));
    await tester.pumpAndSettle();

    expect(uploadedPath, 'C:/tmp/ton-kho-fifo.xlsx');
    expect(
      find.byKey(const Key('inventory-import-result-panel')),
      findsOneWidget,
    );
    expect(find.text('Kết quả cập nhật'), findsOneWidget);
    expect(find.text('Tổng dòng'), findsOneWidget);
    expect(find.text('Dòng hợp lệ'), findsOneWidget);
    expect(find.text('Dòng bỏ qua'), findsOneWidget);
    expect(find.text('Dòng ngừng active'), findsOneWidget);
    expect(find.text('CP62'), findsOneWidget);
    expect(find.text('CP75'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Inventory import shows retryable upload error', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var uploadCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: InventoryImportScreen(
          filePicker: () async => const InventoryPickedFile(
            name: 'ton-kho-loi.xls',
            path: 'C:/tmp/ton-kho-loi.xls',
            size: 1024,
          ),
          uploader: (_) async {
            uploadCalls += 1;
            if (uploadCalls == 1) {
              throw Exception('upload busy');
            }
            return const InventoryImportResult(
              importedRows: 1,
              deactivatedRows: 0,
              skippedRows: 0,
              totalRows: 1,
              srCodes: ['CP62'],
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Chọn file'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cập nhật tồn kho'));
    await tester.pumpAndSettle();

    expect(
      find.text('Chưa cập nhật được tồn kho. Vui lòng thử lại.'),
      findsOneWidget,
    );
    expect(find.text('Thử cập nhật lại'), findsOneWidget);

    await tester.ensureVisible(find.text('Thử cập nhật lại'));
    await tester.tap(find.text('Thử cập nhật lại'));
    await tester.pumpAndSettle();

    expect(
      find.text('Chưa cập nhật được tồn kho. Vui lòng thử lại.'),
      findsNothing,
    );
    expect(find.text('Kết quả cập nhật'), findsOneWidget);
    expect(find.text('CP62'), findsOneWidget);
    expect(uploadCalls, 2);
    expect(tester.takeException(), isNull);
  });
}
