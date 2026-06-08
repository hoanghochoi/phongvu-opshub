import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/storage/app_storage_keys.dart';

void main() {
  test('maps known API base URLs to stable storage environments', () {
    expect(
      AppStorageKeys.environmentForBaseUrl(
        'https://opshub-staging.hoanghochoi.com/api',
      ),
      'staging',
    );
    expect(
      AppStorageKeys.environmentForBaseUrl(
        'https://opshub.hoanghochoi.com/api',
      ),
      'production',
    );
    expect(
      AppStorageKeys.environmentForBaseUrl('http://localhost:3000/api'),
      'local',
    );
    expect(
      AppStorageKeys.environmentForBaseUrl('http://192.168.1.20:3000/api'),
      'local',
    );
  });

  test('uses explicit environment when APP_ENV is provided', () {
    expect(
      AppStorageKeys.environmentForBaseUrl(
        'https://opshub.hoanghochoi.com/api',
        explicitEnvironment: 'Staging Build',
      ),
      'staging_build',
    );
  });

  test('namespaces shared and secure keys by resolved environment', () {
    final environment = AppStorageKeys.environment;

    expect(
      AppStorageKeys.shared('user_email'),
      'opshub.$environment.user_email',
    );
    expect(
      AppStorageKeys.secure('user_jwt_token'),
      'opshub.$environment.user_jwt_token',
    );
  });
}
