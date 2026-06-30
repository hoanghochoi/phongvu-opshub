import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/config/app_brand.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('resolves production and staging titles from environment', () {
    expect(
      AppBrand.titleFor(apiBaseUrl: 'https://opshub.hoanghochoi.com/api'),
      AppBrand.productionTitle,
    );
    expect(
      AppBrand.titleFor(
        apiBaseUrl: 'https://opshub-staging.hoanghochoi.com/api',
      ),
      AppBrand.stagingTitle,
    );
    expect(
      AppBrand.titleFor(
        apiBaseUrl: 'https://opshub.hoanghochoi.com/api',
        appEnv: 'staging',
      ),
      AppBrand.stagingTitle,
    );
  });

  test('staging logo asset is bundled', () async {
    final data = await rootBundle.load(
      AppBrand.logoAssetFor(
        apiBaseUrl: 'https://opshub-staging.hoanghochoi.com/api',
      ),
    );

    expect(data.lengthInBytes, greaterThan(0));
  });
}
