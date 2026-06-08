import '../constants/api_constants.dart';

class AppStorageKeys {
  AppStorageKeys._();

  static const _explicitEnvironment = String.fromEnvironment('APP_ENV');

  static String get environment => environmentForBaseUrl(
    ApiConstants.baseUrl,
    explicitEnvironment: _explicitEnvironment,
  );

  static String shared(String key) => 'opshub.$environment.$key';

  static String secure(String key) => 'opshub.$environment.$key';

  static String environmentForBaseUrl(
    String baseUrl, {
    String explicitEnvironment = '',
  }) {
    final explicit = explicitEnvironment.trim().toLowerCase();
    if (explicit.isNotEmpty) return _sanitize(explicit);

    final uri = Uri.tryParse(baseUrl.trim());
    final host = (uri?.host.isNotEmpty == true ? uri!.host : baseUrl)
        .toLowerCase();
    final path = uri?.path.toLowerCase() ?? '';
    if (host.contains('opshub-staging') || path.contains('staging')) {
      return 'staging';
    }
    if (host == 'opshub.hoanghochoi.com') return 'production';
    if (host == 'localhost' ||
        host == '127.0.0.1' ||
        host.startsWith('192.168.') ||
        host.startsWith('10.') ||
        host.startsWith('172.')) {
      return 'local';
    }
    return _sanitize(host.isNotEmpty ? host : 'local');
  }

  static String _sanitize(String value) {
    final sanitized = value
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return sanitized.isEmpty ? 'local' : sanitized;
  }
}
