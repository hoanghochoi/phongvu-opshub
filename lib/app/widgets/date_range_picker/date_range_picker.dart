import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/logging/app_logger.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_text_styles.dart';
import '../app_layout.dart';

typedef AppSelectableDayPredicate = bool Function(DateTime day);

class DateRangePickerResult {
  final DateTime? start;
  final DateTime? end;

  const DateRangePickerResult({required this.start, required this.end});

  bool get isEmpty => start == null && end == null;
}

enum DateRangePreset {
  today('Hôm nay'),
  yesterday('Hôm qua'),
  last3Days('3 ngày gần nhất'),
  last7Days('7 ngày gần nhất'),
  last30Days('30 ngày gần nhất'),
  last3Months('3 tháng gần nhất'),
  last6Months('6 tháng gần nhất'),
  last1Year('1 năm gần nhất'),
  custom('Tùy chỉnh');

  final String label;

  const DateRangePreset(this.label);
}

/// Canonical date-range selection surface for the whole application.
///
/// Feature code should use [DateRangePicker.show] (normally through
/// `AppDateRangeDropdown`) instead of importing or composing another calendar.
class DateRangePicker extends StatefulWidget {
  final DateTime? initialStart;
  final DateTime? initialEnd;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime currentDate;
  final bool allowClear;
  final bool mobile;
  final AppSelectableDayPredicate? selectableDayPredicate;
  final ValueChanged<DateRangePickerResult> onApply;
  final VoidCallback onCancel;

  const DateRangePicker({
    super.key,
    required this.initialStart,
    required this.initialEnd,
    required this.firstDate,
    required this.lastDate,
    required this.currentDate,
    required this.onApply,
    required this.onCancel,
    this.allowClear = true,
    this.mobile = false,
    this.selectableDayPredicate,
  });

  static Future<DateRangePickerResult?> show(
    BuildContext context, {
    DateTime? initialStart,
    DateTime? initialEnd,
    DateTime? firstDate,
    DateTime? lastDate,
    DateTime? currentDate,
    bool allowClear = true,
    AppSelectableDayPredicate? selectableDayPredicate,
  }) async {
    final today = _dateOnly(currentDate ?? DateTime.now());
    final minimum = _dateOnly(firstDate ?? DateTime(2020));
    final maximum = _dateOnly(lastDate ?? DateTime(2100, 12, 31));
    final mobile =
        MediaQuery.sizeOf(context).width < AppLayoutTokens.compactBreakpoint;
    final startedAt = DateTime.now();
    unawaited(
      AppLogger.instance.info(
        'DateRangePicker',
        'Date range picker opened',
        context: {
          'layout': mobile ? 'mobile' : 'desktop',
          'hasStartDate': initialStart != null,
          'hasEndDate': initialEnd != null,
          'allowClear': allowClear,
        },
      ),
    );

    try {
      DateRangePicker buildPicker(BuildContext pickerContext) {
        return DateRangePicker(
          key: const Key('date-range-picker'),
          initialStart: initialStart,
          initialEnd: initialEnd,
          firstDate: minimum,
          lastDate: maximum,
          currentDate: today,
          allowClear: allowClear,
          mobile: mobile,
          selectableDayPredicate: selectableDayPredicate,
          onApply: (result) => Navigator.of(pickerContext).pop(result),
          onCancel: () => Navigator.of(pickerContext).pop(),
        );
      }

      final DateRangePickerResult? result;
      if (mobile) {
        result = await showModalBottomSheet<DateRangePickerResult>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: AppColors.overlayOf(context),
          barrierColor: AppColors.shadow.withValues(alpha: 0.48),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.xxl),
            ),
          ),
          builder: (sheetContext) => SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.92,
            child: buildPicker(sheetContext),
          ),
        );
      } else {
        result = await showDialog<DateRangePickerResult>(
          context: context,
          barrierDismissible: true,
          barrierColor: AppColors.shadow.withValues(alpha: 0.48),
          builder: (dialogContext) => Dialog(
            backgroundColor: AppColors.overlayOf(dialogContext),
            surfaceTintColor: AppColors.transparent,
            insetPadding: const EdgeInsets.all(32),
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.allXxl,
              side: BorderSide(color: AppColors.borderOf(dialogContext)),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980, maxHeight: 640),
              child: buildPicker(dialogContext),
            ),
          ),
        );
      }

      await AppLogger.instance.info(
        'DateRangePicker',
        result == null
            ? 'Date range picker dismissed without changes'
            : 'Date range picker applied',
        context: {
          'layout': mobile ? 'mobile' : 'desktop',
          'outcome': result == null
              ? 'cancelled'
              : result.isEmpty
              ? 'cleared'
              : 'range_applied',
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      return result;
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'DateRangePicker',
        'Date range picker failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          'layout': mobile ? 'mobile' : 'desktop',
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      rethrow;
    }
  }

  @override
  State<DateRangePicker> createState() => _DateRangePickerState();
}

class _DateRangePickerState extends State<DateRangePicker> {
  DateTime? _draftStart;
  DateTime? _draftEnd;
  late DateTime _leftMonth;
  late DateTime _rightMonth;
  late DateTime _mobileMonth;
  late DateTime _focusedDate;
  DateRangePreset _selectedPreset = DateRangePreset.custom;

  @override
  void initState() {
    super.initState();
    _draftStart = _normalizedOrNull(widget.initialStart);
    _draftEnd = _normalizedOrNull(widget.initialEnd);
    final anchor = _draftStart ?? _clampDate(widget.currentDate);
    _leftMonth = DateTime(anchor.year, anchor.month);
    _rightMonth = _addMonths(_leftMonth, 1);
    _mobileMonth = _leftMonth;
    _focusedDate = anchor;
    _selectedPreset = _matchingPreset();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.overlayOf(context),
      child: widget.mobile ? _buildMobile(context) : _buildDesktop(context),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return SizedBox(
      key: const Key('date-range-desktop'),
      width: 980,
      height: 610,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 210,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.canvasOf(context),
                border: Border(
                  right: BorderSide(color: AppColors.subtleBorderOf(context)),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: _buildDesktopPresets(context),
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                _buildHeader(context),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _MonthCalendar(
                            key: const Key('from-calendar'),
                            label: 'Từ ngày',
                            month: _leftMonth,
                            firstDate: widget.firstDate,
                            lastDate: widget.lastDate,
                            currentDate: widget.currentDate,
                            start: _draftStart,
                            end: _draftEnd,
                            focusedDate: _focusedDate,
                            selectableDayPredicate:
                                widget.selectableDayPredicate,
                            onMonthChanged: (month) =>
                                setState(() => _leftMonth = month),
                            onDateFocused: _focusDate,
                            onDateSelected: _selectDate,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: _MonthCalendar(
                            key: const Key('to-calendar'),
                            label: 'Đến ngày',
                            month: _rightMonth,
                            firstDate: widget.firstDate,
                            lastDate: widget.lastDate,
                            currentDate: widget.currentDate,
                            start: _draftStart,
                            end: _draftEnd,
                            focusedDate: _focusedDate,
                            selectableDayPredicate:
                                widget.selectableDayPredicate,
                            onMonthChanged: (month) =>
                                setState(() => _rightMonth = month),
                            onDateFocused: _focusDate,
                            onDateSelected: _selectDate,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _buildActions(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobile(BuildContext context) {
    return Column(
      key: const Key('date-range-mobile'),
      children: [
        const SizedBox(height: 10),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.borderOf(context),
            borderRadius: AppRadius.allPill,
          ),
        ),
        _buildHeader(context),
        SizedBox(
          height: 52,
          child: ListView.separated(
            key: const Key('mobile-date-presets'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            scrollDirection: Axis.horizontal,
            itemBuilder: (context, index) => _PresetButton(
              preset: DateRangePreset.values[index],
              selected: _selectedPreset == DateRangePreset.values[index],
              onPressed: () => _applyPreset(DateRangePreset.values[index]),
            ),
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemCount: DateRangePreset.values.length,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: _MonthCalendar(
              key: const Key('mobile-calendar'),
              label: 'Chọn ngày',
              month: _mobileMonth,
              firstDate: widget.firstDate,
              lastDate: widget.lastDate,
              currentDate: widget.currentDate,
              start: _draftStart,
              end: _draftEnd,
              focusedDate: _focusedDate,
              selectableDayPredicate: widget.selectableDayPredicate,
              onMonthChanged: (month) => setState(() => _mobileMonth = month),
              onDateFocused: _focusDate,
              onDateSelected: _selectDate,
            ),
          ),
        ),
        _buildActions(context, mobile: true),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        widget.mobile ? 16 : 20,
        widget.mobile ? 14 : 18,
        widget.mobile ? 8 : 16,
        widget.mobile ? 12 : 16,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.subtleBorderOf(context)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.date_range_rounded, color: AppColors.primaryOf(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Khoảng ngày',
                  style: AppTextStyles.labelS.copyWith(
                    color: AppColors.textMutedOf(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _headerRangeLabel(),
                  key: const Key('date-range-header-value'),
                  style: AppTextStyles.headingS.copyWith(
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
              ],
            ),
          ),
          if (widget.mobile)
            IconButton(
              key: const Key('date-range-close'),
              tooltip: 'Đóng không lưu',
              onPressed: widget.onCancel,
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
    );
  }

  Widget _buildDesktopPresets(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: Text(
            'Khoảng nhanh',
            style: AppTextStyles.labelS.copyWith(
              color: AppColors.textMutedOf(context),
            ),
          ),
        ),
        for (final preset in DateRangePreset.values)
          _PresetButton(
            preset: preset,
            selected: _selectedPreset == preset,
            expanded: true,
            onPressed: () => _applyPreset(preset),
          ),
      ],
    );
  }

  Widget _buildActions(BuildContext context, {bool mobile = false}) {
    return SafeArea(
      top: false,
      minimum: EdgeInsets.only(bottom: mobile ? 8 : 0),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: mobile ? 16 : 20,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: AppColors.overlayOf(context),
          border: Border(
            top: BorderSide(color: AppColors.subtleBorderOf(context)),
          ),
        ),
        child: mobile
            ? Row(
                children: [
                  if (widget.allowClear) ...[
                    Expanded(
                      child: TextButton(
                        key: const Key('date-range-clear'),
                        onPressed: _clearDraft,
                        child: const Text('Xóa bộ lọc'),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: TextButton(
                      key: const Key('date-range-cancel'),
                      onPressed: widget.onCancel,
                      child: const Text('Hủy'),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: FilledButton(
                      key: const Key('date-range-apply'),
                      onPressed: _canApply ? _apply : null,
                      child: const Text('Áp dụng'),
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  if (widget.allowClear)
                    TextButton.icon(
                      key: const Key('date-range-clear'),
                      onPressed: _clearDraft,
                      icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                      label: const Text('Xóa bộ lọc'),
                    ),
                  const Spacer(),
                  TextButton(
                    key: const Key('date-range-cancel'),
                    onPressed: widget.onCancel,
                    child: const Text('Hủy'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('date-range-apply'),
                    onPressed: _canApply ? _apply : null,
                    child: const Text('Áp dụng'),
                  ),
                ],
              ),
      ),
    );
  }

  bool get _canApply =>
      (_draftStart == null && _draftEnd == null && widget.allowClear) ||
      (_draftStart != null && _draftEnd != null);

  void _apply() {
    widget.onApply(DateRangePickerResult(start: _draftStart, end: _draftEnd));
  }

  void _clearDraft() {
    setState(() {
      _draftStart = null;
      _draftEnd = null;
      _selectedPreset = DateRangePreset.custom;
    });
    unawaited(
      AppLogger.instance.info(
        'DateRangePicker',
        'Date range picker draft cleared',
      ),
    );
  }

  void _applyPreset(DateRangePreset preset) {
    if (preset == DateRangePreset.custom) {
      setState(() => _selectedPreset = preset);
      return;
    }
    final today = _clampDate(widget.currentDate);
    DateTime start;
    DateTime end = today;
    switch (preset) {
      case DateRangePreset.today:
        start = today;
      case DateRangePreset.yesterday:
        start = today.subtract(const Duration(days: 1));
        end = start;
      case DateRangePreset.last3Days:
        start = today.subtract(const Duration(days: 2));
      case DateRangePreset.last7Days:
        start = today.subtract(const Duration(days: 6));
      case DateRangePreset.last30Days:
        start = today.subtract(const Duration(days: 29));
      case DateRangePreset.last3Months:
        start = _subtractCalendarMonths(today, 3);
      case DateRangePreset.last6Months:
        start = _subtractCalendarMonths(today, 6);
      case DateRangePreset.last1Year:
        start = _subtractCalendarMonths(today, 12);
      case DateRangePreset.custom:
        return;
    }
    start = _clampDate(start);
    if (!_isSelectable(start) || !_isSelectable(end)) return;
    setState(() {
      _draftStart = start;
      _draftEnd = end;
      _selectedPreset = preset;
      _focusedDate = end;
      _leftMonth = DateTime(start.year, start.month);
      _rightMonth = DateTime(end.year, end.month);
      if (_rightMonth == _leftMonth) _rightMonth = _addMonths(_leftMonth, 1);
      _mobileMonth = DateTime(end.year, end.month);
    });
    unawaited(
      AppLogger.instance.info(
        'DateRangePicker',
        'Date range preset selected',
        context: {'preset': preset.name},
      ),
    );
  }

  void _selectDate(DateTime day) {
    if (!_isSelectable(day)) return;
    setState(() {
      _selectedPreset = DateRangePreset.custom;
      _focusedDate = day;
      if (_draftStart == null || _draftEnd != null) {
        _draftStart = day;
        _draftEnd = null;
      } else if (day.isBefore(_draftStart!)) {
        _draftEnd = _draftStart;
        _draftStart = day;
      } else {
        _draftEnd = day;
      }
    });
  }

  void _focusDate(DateTime day) {
    setState(() {
      _focusedDate = _clampDate(day);
      if (widget.mobile) {
        _mobileMonth = DateTime(_focusedDate.year, _focusedDate.month);
      }
    });
  }

  DateRangePreset _matchingPreset() {
    final start = _draftStart;
    final end = _draftEnd;
    if (start == null || end == null) return DateRangePreset.custom;
    final today = _clampDate(widget.currentDate);
    for (final preset in DateRangePreset.values) {
      if (preset == DateRangePreset.custom) continue;
      final range = _rangeForPreset(preset, today);
      if (_sameDate(start, range.$1) && _sameDate(end, range.$2)) {
        return preset;
      }
    }
    return DateRangePreset.custom;
  }

  (DateTime, DateTime) _rangeForPreset(DateRangePreset preset, DateTime today) {
    return switch (preset) {
      DateRangePreset.today => (today, today),
      DateRangePreset.yesterday => (
        today.subtract(const Duration(days: 1)),
        today.subtract(const Duration(days: 1)),
      ),
      DateRangePreset.last3Days => (
        today.subtract(const Duration(days: 2)),
        today,
      ),
      DateRangePreset.last7Days => (
        today.subtract(const Duration(days: 6)),
        today,
      ),
      DateRangePreset.last30Days => (
        today.subtract(const Duration(days: 29)),
        today,
      ),
      DateRangePreset.last3Months => (_subtractCalendarMonths(today, 3), today),
      DateRangePreset.last6Months => (_subtractCalendarMonths(today, 6), today),
      DateRangePreset.last1Year => (_subtractCalendarMonths(today, 12), today),
      DateRangePreset.custom => (today, today),
    };
  }

  DateTime? _normalizedOrNull(DateTime? value) {
    if (value == null) return null;
    return _clampDate(_dateOnly(value));
  }

  DateTime _clampDate(DateTime value) {
    final day = _dateOnly(value);
    if (day.isBefore(widget.firstDate)) return _dateOnly(widget.firstDate);
    if (day.isAfter(widget.lastDate)) return _dateOnly(widget.lastDate);
    return day;
  }

  bool _isSelectable(DateTime day) {
    final value = _dateOnly(day);
    if (value.isBefore(_dateOnly(widget.firstDate)) ||
        value.isAfter(_dateOnly(widget.lastDate))) {
      return false;
    }
    return widget.selectableDayPredicate?.call(value) ?? true;
  }

  String _headerRangeLabel() {
    if (_draftStart == null && _draftEnd == null) return 'Tất cả ngày';
    if (_draftStart != null && _draftEnd == null) {
      return '${_formatDate(_draftStart!)} – Chọn ngày kết thúc';
    }
    return '${_formatDate(_draftStart!)} – ${_formatDate(_draftEnd!)}';
  }
}

class _PresetButton extends StatelessWidget {
  final DateRangePreset preset;
  final bool selected;
  final bool expanded;
  final VoidCallback onPressed;

  const _PresetButton({
    required this.preset,
    required this.selected,
    required this.onPressed,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final button = TextButton(
      key: Key('date-range-preset-${preset.name}'),
      onPressed: onPressed,
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        foregroundColor: selected
            ? AppColors.primaryOf(context)
            : AppColors.textPrimaryOf(context),
        backgroundColor: selected
            ? AppColors.primarySurfaceOf(context)
            : AppColors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.allSm),
        minimumSize: Size(expanded ? double.infinity : 0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (expanded)
            Expanded(child: Text(preset.label, style: AppTextStyles.labelM))
          else
            Text(preset.label, style: AppTextStyles.labelM),
          if (selected) ...[
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, size: 18),
          ],
        ],
      ),
    );
    return expanded ? button : IntrinsicWidth(child: button);
  }
}

class _MonthCalendar extends StatefulWidget {
  final String label;
  final DateTime month;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime currentDate;
  final DateTime? start;
  final DateTime? end;
  final DateTime focusedDate;
  final AppSelectableDayPredicate? selectableDayPredicate;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDateFocused;
  final ValueChanged<DateTime> onDateSelected;

  const _MonthCalendar({
    super.key,
    required this.label,
    required this.month,
    required this.firstDate,
    required this.lastDate,
    required this.currentDate,
    required this.start,
    required this.end,
    required this.focusedDate,
    required this.onMonthChanged,
    required this.onDateFocused,
    required this.onDateSelected,
    this.selectableDayPredicate,
  });

  @override
  State<_MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<_MonthCalendar> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'Date range calendar');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final days = _calendarDays(widget.month);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.label,
          style: AppTextStyles.labelM.copyWith(
            color: AppColors.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 8),
        _buildMonthNavigation(context),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final weekday in const [
              'T2',
              'T3',
              'T4',
              'T5',
              'T6',
              'T7',
              'CN',
            ])
              Expanded(
                child: Center(
                  child: Text(
                    weekday,
                    style: AppTextStyles.labelS.copyWith(
                      color: AppColors.textMutedOf(context),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Focus(
            focusNode: _focusNode,
            autofocus: true,
            onKeyEvent: _handleKeyEvent,
            child: GridView.builder(
              key: Key('date-grid-${widget.month.year}-${widget.month.month}'),
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1.08,
              ),
              itemCount: days.length,
              itemBuilder: (context, index) => _buildDay(context, days[index]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMonthNavigation(BuildContext context) {
    final firstMonth = DateTime(widget.firstDate.year, widget.firstDate.month);
    final lastMonth = DateTime(widget.lastDate.year, widget.lastDate.month);
    final canPrevious = widget.month.isAfter(firstMonth);
    final canNext = widget.month.isBefore(lastMonth);
    return Row(
      children: [
        IconButton(
          tooltip: 'Tháng trước',
          onPressed: canPrevious
              ? () => widget.onMonthChanged(_addMonths(widget.month, -1))
              : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              key: ValueKey('month-${widget.key}'),
              value: widget.month.month,
              isExpanded: true,
              items: [
                for (var month = 1; month <= 12; month++)
                  DropdownMenuItem(value: month, child: Text('Tháng $month')),
              ],
              onChanged: (month) {
                if (month == null) return;
                final candidate = DateTime(widget.month.year, month);
                widget.onMonthChanged(
                  _clampMonth(candidate, firstMonth, lastMonth),
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 92,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              key: ValueKey('year-${widget.key}'),
              value: widget.month.year,
              isExpanded: true,
              items: [
                for (
                  var year = widget.firstDate.year;
                  year <= widget.lastDate.year;
                  year++
                )
                  DropdownMenuItem(value: year, child: Text('$year')),
              ],
              onChanged: (year) {
                if (year == null) return;
                final candidate = DateTime(year, widget.month.month);
                widget.onMonthChanged(
                  _clampMonth(candidate, firstMonth, lastMonth),
                );
              },
            ),
          ),
        ),
        IconButton(
          tooltip: 'Tháng sau',
          onPressed: canNext
              ? () => widget.onMonthChanged(_addMonths(widget.month, 1))
              : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }

  Widget _buildDay(BuildContext context, DateTime? day) {
    if (day == null) return const SizedBox.shrink();
    final enabled = _isSelectable(day);
    final isStart = widget.start != null && _sameDate(day, widget.start!);
    final isEnd = widget.end != null && _sameDate(day, widget.end!);
    final isEndpoint = isStart || isEnd;
    final inRange =
        widget.start != null &&
        widget.end != null &&
        !day.isBefore(widget.start!) &&
        !day.isAfter(widget.end!);
    final isToday = _sameDate(day, widget.currentDate);
    final isFocused = _sameDate(day, widget.focusedDate);
    final primary = AppColors.primaryOf(context);
    final textColor = !enabled
        ? AppColors.disabled
        : isEndpoint
        ? Theme.of(context).colorScheme.onPrimary
        : AppColors.textPrimaryOf(context);

    return Semantics(
      button: true,
      enabled: enabled,
      selected: isEndpoint || inRange,
      label: '${day.day} tháng ${day.month} năm ${day.year}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: inRange && !isEndpoint
              ? AppColors.primarySurfaceOf(context)
              : AppColors.transparent,
          child: InkWell(
            key: Key(_dateKey(day)),
            canRequestFocus: false,
            onTap: enabled
                ? () {
                    _focusNode.requestFocus();
                    widget.onDateSelected(day);
                  }
                : null,
            customBorder: isEndpoint ? const CircleBorder() : null,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isEndpoint ? primary : AppColors.transparent,
                shape: isEndpoint ? BoxShape.circle : BoxShape.rectangle,
                border: isFocused && !isEndpoint
                    ? Border.all(color: primary, width: 1.5)
                    : isToday && !isEndpoint
                    ? Border.all(color: primary)
                    : null,
                borderRadius: isEndpoint ? null : AppRadius.allXs,
              ),
              child: Text(
                '${day.day}',
                style: AppTextStyles.bodyM.copyWith(
                  color: textColor,
                  fontWeight: isEndpoint || isToday
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    var candidate = widget.focusedDate;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      candidate = candidate.subtract(const Duration(days: 1));
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      candidate = candidate.add(const Duration(days: 1));
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      candidate = candidate.subtract(const Duration(days: 7));
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      candidate = candidate.add(const Duration(days: 7));
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      if (_isSelectable(candidate)) widget.onDateSelected(candidate);
      return KeyEventResult.handled;
    } else {
      return KeyEventResult.ignored;
    }
    if (_isSelectable(candidate)) {
      widget.onDateFocused(candidate);
      final candidateMonth = DateTime(candidate.year, candidate.month);
      if (candidateMonth != widget.month) {
        widget.onMonthChanged(candidateMonth);
      }
    }
    return KeyEventResult.handled;
  }

  bool _isSelectable(DateTime day) {
    final value = _dateOnly(day);
    if (value.isBefore(_dateOnly(widget.firstDate)) ||
        value.isAfter(_dateOnly(widget.lastDate))) {
      return false;
    }
    return widget.selectableDayPredicate?.call(value) ?? true;
  }
}

List<DateTime?> _calendarDays(DateTime month) {
  final first = DateTime(month.year, month.month);
  final count = DateTime(month.year, month.month + 1, 0).day;
  final leading = first.weekday - DateTime.monday;
  return [
    ...List<DateTime?>.filled(leading, null),
    for (var day = 1; day <= count; day++)
      DateTime(month.year, month.month, day),
    ...List<DateTime?>.filled(42 - leading - count, null),
  ];
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _addMonths(DateTime value, int months) =>
    DateTime(value.year, value.month + months);

DateTime _subtractCalendarMonths(DateTime value, int months) {
  final targetMonth = DateTime(value.year, value.month - months);
  final lastDay = DateTime(targetMonth.year, targetMonth.month + 1, 0).day;
  return DateTime(
    targetMonth.year,
    targetMonth.month,
    value.day.clamp(1, lastDay),
  );
}

DateTime _clampMonth(DateTime value, DateTime minimum, DateTime maximum) {
  if (value.isBefore(minimum)) return minimum;
  if (value.isAfter(maximum)) return maximum;
  return value;
}

bool _sameDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

String _formatDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/'
    '${value.month.toString().padLeft(2, '0')}/${value.year}';

String _dateKey(DateTime value) =>
    'date-cell-${value.year}-${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
