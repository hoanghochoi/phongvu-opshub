import 'package:flutter/services.dart' show rootBundle;

class EmailDomainPolicy {
  EmailDomainPolicy._();

  static const _assetPath = 'data/email_domain.txt';
  static const _breakGlassEmails = <String>{'admin@hoanghochoi.com'};
  static const _fallbackDomains = <String>['phongvu.vn', 'acare.vn'];

  static Future<List<String>> loadAllowedDomains() async {
    try {
      final raw = await rootBundle.loadString(_assetPath);
      final domains = parse(raw);
      if (domains.isNotEmpty) return _withFallbackDomains(domains);
    } catch (_) {
      // Keep login/register usable in tests and local tools that do not load assets.
    }
    return _fallbackDomains;
  }

  static List<String> parse(String raw) {
    return raw
        .split(RegExp(r'[\r\n,]+'))
        .map(
          (domain) =>
              domain.trim().replaceFirst(RegExp(r'^@'), '').toLowerCase(),
        )
        .where((domain) => domain.isNotEmpty)
        .toList(growable: false);
  }

  static bool isAllowedEmail(String email, List<String> domains) {
    final normalizedEmail = email.trim().toLowerCase();
    if (_breakGlassEmails.contains(normalizedEmail)) return true;
    final parts = normalizedEmail.split('@');
    if (parts.length != 2) return false;
    final effectiveDomains = _withFallbackDomains(domains);
    return effectiveDomains.contains(parts.last);
  }

  static List<String> _withFallbackDomains(List<String> domains) {
    return <String>{...domains, ..._fallbackDomains}.toList(growable: false);
  }

  static const promptText =
      'Dùng email được OpsHub chấp nhận và mật khẩu OpsHub';
  static const invalidDomainMessage =
      'Chỉ chấp nhận email thuộc domain OpsHub cho phép';
}
