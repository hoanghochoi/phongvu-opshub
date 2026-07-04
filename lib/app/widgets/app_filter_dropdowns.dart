import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/utils/date_range_defaults.dart';
import '../theme/app_text_styles.dart';
import 'app_inputs.dart';
import 'app_layout.dart';

const double _filterButtonHeight = 52;

class AppFilterOption<T> {
  final T value;
  final String label;
  final String? subtitle;

  const AppFilterOption({
    required this.value,
    required this.label,
    this.subtitle,
  });

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return label.toLowerCase().contains(normalized) ||
        (subtitle?.toLowerCase().contains(normalized) ?? false);
  }
}

class AppFilterDropdown<T> extends StatefulWidget {
  final String label;
  final T? value;
  final List<AppFilterOption<T>> options;
  final ValueChanged<T?> onChanged;
  final String allLabel;
  final IconData icon;
  final bool forceSearch;

  const AppFilterDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.allLabel = 'Tất cả',
    this.icon = Icons.filter_list,
    this.forceSearch = false,
  });

  @override
  State<AppFilterDropdown<T>> createState() => _AppFilterDropdownState<T>();
}

class AppSearchableFilterDropdown<T> extends AppFilterDropdown<T> {
  const AppSearchableFilterDropdown({
    super.key,
    required super.label,
    required super.value,
    required super.options,
    required super.onChanged,
    super.allLabel,
    super.icon,
  }) : super(forceSearch: true);
}

class _AppFilterDropdownState<T> extends State<AppFilterDropdown<T>> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.options.where((item) => item.value == widget.value);
    final label = selected.isEmpty ? widget.allLabel : selected.first.label;
    return MenuAnchor(
      menuChildren: [_buildMenu(context)],
      builder: (context, controller, child) {
        return OutlinedButton.icon(
          icon: Icon(widget.icon, size: 18),
          style: _filterButtonStyle(),
          label: Text(
            '${widget.label}: $label',
            overflow: TextOverflow.ellipsis,
          ),
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
        );
      },
    );
  }

  Widget _buildMenu(BuildContext context) {
    final shouldSearch = widget.forceSearch || widget.options.length > 10;
    return SizedBox(
      width: 300,
      child: StatefulBuilder(
        builder: (context, setMenuState) {
          final liveFiltered = widget.options.where(
            (item) => item.matches(_searchController.text),
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (shouldSearch)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                  child: AppTextInput(
                    controller: _searchController,
                    label: 'Tìm trong bộ lọc',
                    icon: Icons.search,
                    dense: true,
                    onChanged: (_) => setMenuState(() {}),
                  ),
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: SingleChildScrollView(
                  primary: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        dense: true,
                        leading: widget.value == null
                            ? const Icon(Icons.check, size: 18)
                            : const SizedBox(width: 18),
                        title: Text(widget.allLabel),
                        onTap: () {
                          widget.onChanged(null);
                          MenuController.maybeOf(context)?.close();
                        },
                      ),
                      for (final option in liveFiltered)
                        ListTile(
                          dense: true,
                          leading: widget.value == option.value
                              ? const Icon(Icons.check, size: 18)
                              : const SizedBox(width: 18),
                          title: Text(option.label),
                          subtitle: option.subtitle == null
                              ? null
                              : Text(option.subtitle!),
                          onTap: () {
                            widget.onChanged(option.value);
                            MenuController.maybeOf(context)?.close();
                          },
                        ),
                      if (liveFiltered.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Không có lựa chọn phù hợp'),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class AppMultiSelectFilterDropdown<T> extends StatefulWidget {
  final String label;
  final Set<T> values;
  final List<AppFilterOption<T>> options;
  final ValueChanged<Set<T>> onChanged;
  final String emptyLabel;
  final IconData icon;
  final bool forceSearch;

  const AppMultiSelectFilterDropdown({
    super.key,
    required this.label,
    required this.values,
    required this.options,
    required this.onChanged,
    this.emptyLabel = 'Tất cả',
    this.icon = Icons.filter_list,
    this.forceSearch = false,
  });

  @override
  State<AppMultiSelectFilterDropdown<T>> createState() =>
      _AppMultiSelectFilterDropdownState<T>();
}

class _AppMultiSelectFilterDropdownState<T>
    extends State<AppMultiSelectFilterDropdown<T>> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.values.isEmpty
        ? widget.emptyLabel
        : '${widget.values.length} đã chọn';
    return MenuAnchor(
      menuChildren: [_buildMenu(context)],
      builder: (context, controller, child) {
        return OutlinedButton.icon(
          icon: Icon(widget.icon, size: 18),
          style: _filterButtonStyle(),
          label: Text(
            '${widget.label}: $label',
            overflow: TextOverflow.ellipsis,
          ),
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
        );
      },
    );
  }

  Widget _buildMenu(BuildContext context) {
    final shouldSearch = widget.forceSearch || widget.options.length > 10;
    return SizedBox(
      width: 320,
      child: StatefulBuilder(
        builder: (context, setMenuState) {
          final filtered = widget.options.where(
            (item) => item.matches(_searchController.text),
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (shouldSearch)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                  child: AppTextInput(
                    controller: _searchController,
                    label: 'Tìm trong bộ lọc',
                    icon: Icons.search,
                    dense: true,
                    onChanged: (_) => setMenuState(() {}),
                  ),
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: SingleChildScrollView(
                  primary: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final option in filtered)
                        CheckboxListTile(
                          dense: true,
                          value: widget.values.contains(option.value),
                          title: Text(option.label),
                          subtitle: option.subtitle == null
                              ? null
                              : Text(option.subtitle!),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (checked) {
                            final next = Set<T>.from(widget.values);
                            if (checked == true) {
                              next.add(option.value);
                            } else {
                              next.remove(option.value);
                            }
                            widget.onChanged(next);
                            setMenuState(() {});
                          },
                        ),
                      if (filtered.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Không có lựa chọn phù hợp'),
                        ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      textStyle: AppTextStyles.labelM,
                    ),
                    onPressed: widget.values.isEmpty
                        ? null
                        : () {
                            widget.onChanged(<T>{});
                            setMenuState(() {});
                          },
                    child: const Text('Xóa lọc'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      textStyle: AppTextStyles.labelM,
                    ),
                    onPressed: () => MenuController.maybeOf(context)?.close(),
                    child: const Text('Áp dụng'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class AppDateRangeDropdown extends StatefulWidget {
  final String label;
  final DateTime? start;
  final DateTime? end;
  final void Function(DateTime? start, DateTime? end) onChanged;
  final bool allowEmptyRange;
  final String? emptyRangeHelperText;

  const AppDateRangeDropdown({
    super.key,
    required this.label,
    required this.start,
    required this.end,
    required this.onChanged,
    this.allowEmptyRange = true,
    this.emptyRangeHelperText,
  });

  @override
  State<AppDateRangeDropdown> createState() => _AppDateRangeDropdownState();
}

class _AppDateRangeDropdownState extends State<AppDateRangeDropdown> {
  final _startController = TextEditingController();
  final _endController = TextEditingController();
  String? _errorText;

  @override
  void didUpdateWidget(covariant AppDateRangeDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.start != widget.start || oldWidget.end != widget.end) {
      _syncControllers();
    }
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _syncControllers();
    final helperText = _emptyRangeHelperText();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MenuAnchor(
          menuChildren: [_buildMenu(context)],
          builder: (context, controller, child) {
            return OutlinedButton.icon(
              icon: const Icon(Icons.date_range, size: 18),
              style: _filterButtonStyle(),
              label: Text(
                '${widget.label}: ${_rangeLabel(widget.start, widget.end)}',
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
            );
          },
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

  Widget _buildMenu(BuildContext context) {
    return SizedBox(
      width: 320,
      child: StatefulBuilder(
        builder: (context, setMenuState) {
          void choose(DateTime? start, DateTime? end) {
            widget.onChanged(start, end);
            setState(() => _errorText = null);
            MenuController.maybeOf(context)?.close();
          }

          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DatePresetTile(
                  label: 'Hôm nay',
                  onTap: () {
                    final today = _dateOnly(DateTime.now());
                    choose(today, today);
                  },
                ),
                _DatePresetTile(
                  label: '7 ngày',
                  onTap: () {
                    final today = _dateOnly(DateTime.now());
                    choose(today.subtract(const Duration(days: 6)), today);
                  },
                ),
                _DatePresetTile(
                  label: '30 ngày',
                  onTap: () {
                    final today = _dateOnly(DateTime.now());
                    choose(today.subtract(const Duration(days: 29)), today);
                  },
                ),
                _DatePresetTile(
                  label: 'Tháng này',
                  onTap: () {
                    final today = _dateOnly(DateTime.now());
                    choose(DateTime(today.year, today.month), today);
                  },
                ),
                if (widget.allowEmptyRange)
                  _DatePresetTile(
                    label: 'Tất cả ngày',
                    onTap: () => choose(null, null),
                  ),
                const Divider(),
                AppDateTextField(
                  controller: _startController,
                  label: 'Từ ngày',
                  dense: true,
                  onPickDate: () => _pickDateFor(
                    context,
                    controller: _startController,
                    fallback: widget.start ?? widget.end,
                    setMenuState: setMenuState,
                  ),
                ),
                const SizedBox(height: 8),
                AppDateTextField(
                  controller: _endController,
                  label: 'Đến ngày',
                  dense: true,
                  onPickDate: () => _pickDateFor(
                    context,
                    controller: _endController,
                    fallback: widget.end ?? widget.start,
                    setMenuState: setMenuState,
                  ),
                ),
                if (_errorText != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  style: FilledButton.styleFrom(
                    textStyle: AppTextStyles.labelM,
                  ),
                  onPressed: () {
                    final start = appParseDateInput(_startController.text);
                    final end = appParseDateInput(_endController.text);
                    if (_startController.text.trim().isNotEmpty &&
                        start == null) {
                      setMenuState(() => _errorText = 'Ngày bắt đầu chưa đúng');
                      return;
                    }
                    if (_endController.text.trim().isNotEmpty && end == null) {
                      setMenuState(
                        () => _errorText = 'Ngày kết thúc chưa đúng',
                      );
                      return;
                    }
                    if (start != null && end != null && end.isBefore(start)) {
                      setMenuState(
                        () =>
                            _errorText = 'Ngày kết thúc phải sau ngày bắt đầu',
                      );
                      return;
                    }
                    choose(start, end);
                  },
                  child: const Text('Áp dụng ngày tùy chỉnh'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _syncControllers() {
    final nextStart = appFormatDateInput(widget.start);
    final nextEnd = appFormatDateInput(widget.end);
    if (_startController.text != nextStart) _startController.text = nextStart;
    if (_endController.text != nextEnd) _endController.text = nextEnd;
  }

  String? _emptyRangeHelperText() {
    if (!widget.allowEmptyRange || widget.start != null || widget.end != null) {
      return null;
    }
    final text = widget.emptyRangeHelperText?.trim();
    if (text != null && text.isNotEmpty) return text;
    return appImplicitDateRangeHelperText();
  }

  Future<void> _pickDateFor(
    BuildContext context, {
    required TextEditingController controller,
    required void Function(VoidCallback fn) setMenuState,
    DateTime? fallback,
  }) async {
    final typedDate = appParseDateInput(controller.text);
    final now = _dateOnly(DateTime.now());
    final initial = typedDate ?? fallback ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setMenuState(() {
      controller.text = appFormatDateInput(picked);
      _errorText = null;
    });
  }
}

class _DatePresetTile extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DatePresetTile({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(dense: true, title: Text(label), onTap: onTap);
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
