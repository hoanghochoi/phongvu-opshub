/// URL-checking utility, extracted from warranty_details_screen.dart
/// where it was duplicated 3 times.
class UrlUtils {
  UrlUtils._();

  /// Returns `true` if [value] looks like an HTTP(S) URL.
  static bool isUrl(String? value) {
    if (value == null || value.isEmpty) return false;
    return value.startsWith('http://') || value.startsWith('https://');
  }
}
