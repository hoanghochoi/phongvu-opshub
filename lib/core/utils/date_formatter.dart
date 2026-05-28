import 'package:intl/intl.dart';

/// Shared date formatting utilities.
///
/// Extracted from `check_warranty_screen.dart`, `warranty_details_screen.dart`,
/// and `sort_sku_group_widget.dart` to eliminate duplication.
class DateFormatter {
  DateFormatter._();

  /// Formats a date string into `dd/MM/yyyy`.
  ///
  /// Handles multiple input formats:
  /// - ISO 8601 (yyyy-MM-dd, yyyy-MM-ddTHH:mm:ss)
  /// - dd/MM/yyyy
  /// - dd-MM-yyyy
  /// - YYYY-MM-DD
  /// - Millisecond timestamps
  ///
  /// Returns the original string if parsing fails.
  static String format(String? dateString, {String pattern = 'dd/MM/yyyy'}) {
    if (dateString == null || dateString.isEmpty) return 'Chưa có';

    final dateTime = tryParse(dateString);
    if (dateTime != null) {
      return DateFormat(pattern).format(dateTime);
    }
    return dateString;
  }

  /// Attempts to parse a date string in multiple common formats.
  ///
  /// Returns `null` if none of the known formats match.
  static DateTime? tryParse(String dateStr) {
    if (dateStr.isEmpty) return null;

    // ISO 8601 first (most reliable)
    try {
      return DateTime.parse(dateStr);
    } catch (_) {}

    // DD/MM/YYYY or DD-MM-YYYY or YYYY-MM-DD
    if (dateStr.contains('/') || dateStr.contains('-')) {
      final separator = dateStr.contains('/') ? '/' : '-';
      final parts = dateStr.split(separator);
      if (parts.length == 3) {
        try {
          if (parts[0].length == 4) {
            // YYYY-MM-DD
            return DateTime(
              int.parse(parts[0]),
              int.parse(parts[1]),
              int.parse(parts[2]),
            );
          } else {
            // DD/MM/YYYY
            return DateTime(
              int.parse(parts[2]),
              int.parse(parts[1]),
              int.parse(parts[0]),
            );
          }
        } catch (_) {}
      }
    }

    // Millisecond timestamp
    final timestamp = int.tryParse(dateStr);
    if (timestamp != null) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    }

    return null;
  }
}
