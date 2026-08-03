import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/widgets/app_feature_grid.dart';

void main() {
  testWidgets('feature tiles follow the Figma horizontal card geometry', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    tester.view.physicalSize = const Size(375, 812);
    await tester.pumpWidget(_fixture());
    expect(find.byType(AppFeatureTile), findsNWidgets(2));
    expect(
      tester.getSize(find.byType(AppFeatureTile).first),
      const Size(343, 96),
    );
    expect(find.text('2 công cụ'), findsOneWidget);

    tester.view.physicalSize = const Size(1200, 900);
    await tester.pumpWidget(_fixture(contentWidth: 1126));
    expect(tester.getSize(find.byType(AppFeatureTile).first).height, 96);
    expect(
      tester.getSize(find.byType(AppFeatureTile).first).width,
      closeTo(364.67, 0.01),
    );

    tester.view.physicalSize = const Size(1024, 900);
    await tester.pumpWidget(_fixture(contentWidth: 872));
    expect(
      tester.getSize(find.byType(AppFeatureTile).first),
      const Size(430, 96),
    );

    await tester.pumpWidget(_fixture(contentWidth: 872, actionCount: 5));
    expect(
      tester.getSize(find.byType(AppFeatureTile).first),
      const Size(280, 96),
    );
  });
}

Widget _fixture({double? contentWidth, int actionCount = 2}) {
  final allActions = const [
    AppFeatureAction(
      icon: Icons.qr_code,
      title: 'VietQR',
      description: 'Tạo mã chuyển khoản',
      color: Colors.blue,
      onTap: null,
    ),
    AppFeatureAction(
      icon: Icons.description_outlined,
      title: 'Báo cáo',
      description: 'Theo dõi báo cáo',
      color: Colors.green,
      onTap: null,
    ),
    AppFeatureAction(
      icon: Icons.article_outlined,
      title: 'Phụ lục',
      description: 'Tạo bảng hàng hóa',
      color: Colors.indigo,
      onTap: null,
    ),
    AppFeatureAction(
      icon: Icons.headset,
      title: 'Chăm sóc lại',
      description: 'Theo dõi khách hàng',
      color: Colors.orange,
      onTap: null,
    ),
    AppFeatureAction(
      icon: Icons.payments_outlined,
      title: 'Tiền vào',
      description: 'Theo dõi thanh toán',
      color: Colors.purple,
      onTap: null,
    ),
  ];
  return MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: contentWidth,
          child: AppFeatureSection(
            title: 'Bán hàng',
            actions: allActions.take(actionCount).toList(growable: false),
          ),
        ),
      ),
    ),
  );
}
