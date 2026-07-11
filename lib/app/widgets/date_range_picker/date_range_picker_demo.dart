import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../app_filter_dropdowns.dart';
import '../app_layout.dart';

/// Lightweight component-catalog demo used when this repository is run without
/// a Storybook dependency.
class DateRangePickerDemo extends StatefulWidget {
  const DateRangePickerDemo({super.key});

  @override
  State<DateRangePickerDemo> createState() => _DateRangePickerDemoState();
}

class _DateRangePickerDemoState extends State<DateRangePickerDemo> {
  DateTime? _start = DateTime(2026, 2, 10);
  DateTime? _end = DateTime(2026, 3, 17);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Demo Date Range Picker')),
      body: AppResponsiveScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Canonical shared component', style: AppTextStyles.headingL),
            const SizedBox(height: AppLayoutTokens.cardGap),
            Text(
              'Desktop mở popover nhỏ gắn với nút; thu nhỏ cửa sổ dưới 600 px để xem bottom sheet một tháng.',
              style: AppTextStyles.bodyM.copyWith(
                color: AppColors.textSecondaryOf(context),
              ),
            ),
            const SizedBox(height: AppLayoutTokens.sectionGap),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: AppDateRangeDropdown(
                label: 'Ngày',
                start: _start,
                end: _end,
                now: () => DateTime(2026, 3, 17),
                onChanged: (start, end) => setState(() {
                  _start = start;
                  _end = end;
                }),
              ),
            ),
            const SizedBox(height: AppLayoutTokens.sectionGap),
            Text(
              'Giá trị đã áp dụng: ${appFormatDateInput(_start)} – '
              '${appFormatDateInput(_end)}',
              key: const Key('date-range-demo-value'),
              style: AppTextStyles.labelM,
            ),
          ],
        ),
      ),
    );
  }
}
