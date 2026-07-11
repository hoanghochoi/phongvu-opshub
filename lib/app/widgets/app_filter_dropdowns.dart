import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/utils/date_range_defaults.dart';
import '../theme/app_text_styles.dart';
import 'app_inputs.dart';
import 'app_layout.dart';
import 'date_range_picker/date_range_picker.dart';

const double _filterButtonHeight = AppLayoutTokens.mobileActionHeight;

/// Shared trigger used by filter bars. The selection surface itself is the
/// canonical [DateRangePicker].
class AppDateRangeDropdown extends StatelessWidget {
  final String label;
  final DateTime? start;
  final DateTime? end;
  final void Function(DateTime? start, DateTime? end) onChanged;
  final bool allowEmptyRange;
  final String? emptyRangeHelperText;
  final bool showEmptyRangeHelperText;
  final DateTime Function()? now;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final AppSelectableDayPredicate? selectableDayPredicate;

  const AppDateRangeDropdown({
    super.key,
    required this.label,
    required this.start,
    required this.end,
    required this.onChanged,
    this.allowEmptyRange = true,
    this.emptyRangeHelperText,
    this.showEmptyRangeHelperText = true,
    this.now,
    this.firstDate,
    this.lastDate,
    this.selectableDayPredicate,
  });

  @override
  Widget build(BuildContext context) {
    final helperText = _emptyRangeHelperText();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Builder(
          builder: (buttonContext) => OutlinedButton.icon(
            key: const Key('open-date-range-picker'),
            icon: const Icon(Icons.date_range_rounded, size: 18),
            style: _filterButtonStyle(),
            label: Text(
              '$label: ${_rangeLabel(start, end)}',
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: () => _openPicker(buttonContext),
          ),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              helperText,
              style:
                  Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ) ??
                  AppTextStyles.bodyS,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    final result = await DateRangePicker.show(
      context,
      initialStart: start,
      initialEnd: end,
      currentDate: _dateOnly((now ?? DateTime.now)()),
      firstDate: firstDate,
      lastDate: lastDate,
      allowClear: allowEmptyRange,
      selectableDayPredicate: selectableDayPredicate,
    );
    if (result == null || !context.mounted) return;
    onChanged(result.start, result.end);
  }

  String? _emptyRangeHelperText() {
    if (!showEmptyRangeHelperText) return null;
    if (!allowEmptyRange || start != null || end != null) return null;
    final text = emptyRangeHelperText?.trim();
    if (text != null && text.isNotEmpty) return text;
    return appImplicitDateRangeHelperText();
  }
}

class AppDateTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool dense;
  final VoidCallback? onPickDate;

  const AppDateTextField({
    super.key,
    required this.controller,
    required this.label,
    this.dense = false,
    this.onPickDate,
  });

  @override
  Widget build(BuildContext context) {
    return AppTextInput(
      controller: controller,
      label: label,
      hintText: 'dd/mm/yyyy',
      dense: dense,
      keyboardType: TextInputType.number,
      inputFormatters: const [AppDateInputFormatter()],
      suffixIcon: onPickDate == null
          ? null
          : IconButton(
              tooltip: 'Chọn ngày',
              icon: const Icon(Icons.calendar_today_rounded),
              onPressed: onPickDate,
            ),
    );
  }
}

ButtonStyle _filterButtonStyle() {
  return OutlinedButton.styleFrom(
    minimumSize: const Size(0, _filterButtonHeight),
    padding: const EdgeInsets.symmetric(horizontal: 14),
    textStyle: AppTextStyles.labelM,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
    ),
  );
}

DateTime _dateOnly(DateTime value) => appDateOnly(value);

DateTime? appParseDateInput(String value) {
  final text = value.trim();
  if (text.isEmpty) return null;
  final slashParts = text.split('/');
  final dashParts = text.split('-');
  final isSlash = slashParts.length == 3;
  final parts = isSlash ? slashParts : dashParts;
  if (parts.length != 3) return null;
  final day = int.tryParse(isSlash ? parts[0] : parts[2]);
  final month = int.tryParse(parts[1]);
  final year = int.tryParse(isSlash ? parts[2] : parts[0]);
  if (year == null || month == null || day == null) return null;
  final parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return parsed;
}

String appFormatDateInput(DateTime? value) {
  if (value == null) return '';
  return [
    value.day.toString().padLeft(2, '0'),
    value.month.toString().padLeft(2, '0'),
    value.year.toString().padLeft(4, '0'),
  ].join('/');
}

String _rangeLabel(DateTime? start, DateTime? end) {
  if (start == null && end == null) return 'Tất cả ngày';
  if (start != null &&
      end != null &&
      appFormatDateInput(start) == appFormatDateInput(end)) {
    return appFormatDateInput(start);
  }
  return '${appFormatDateInput(start)} - ${appFormatDateInput(end)}';
}

class AppDateInputFormatter extends TextInputFormatter {
  const AppDateInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final clipped = digits.length > 8 ? digits.substring(0, 8) : digits;
    final buffer = StringBuffer();
    for (var index = 0; index < clipped.length; index += 1) {
      if (index == 2 || index == 4) buffer.write('/');
      buffer.write(clipped[index]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
