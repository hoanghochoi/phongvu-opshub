import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_text_styles.dart';
import 'app_inputs.dart';
import 'app_dialogs.dart';
import 'app_layout.dart';

class AppComboboxOption<T> {
  final T value;
  final String label;
  final String? subtitle;
  final List<String> searchKeywords;

  const AppComboboxOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.searchKeywords = const [],
  });

  bool matches(String query) {
    final normalized = _normalizeSearchText(query);
    if (normalized.isEmpty) return true;
    return _normalizeSearchText(label).contains(normalized) ||
        _normalizeSearchText(subtitle ?? '').contains(normalized) ||
        searchKeywords.any(
          (keyword) => _normalizeSearchText(keyword).contains(normalized),
        );
  }
}

class AppCombobox<T> extends StatefulWidget {
  final String label;
  final IconData? icon;
  final List<AppComboboxOption<T>> options;
  final T? value;
  final Set<T> values;
  final ValueChanged<T?>? onChanged;
  final ValueChanged<Set<T>>? onMultiChanged;
  final FormFieldValidator<T>? validator;
  final String emptyLabel;
  final String? hintText;
  final String? helperText;
  final bool multiSelect;
  final bool enabled;
  final bool dense;
  final bool allowClear;
  final double? menuWidth;
  final double? maxMenuHeight;
  final TextCapitalization textCapitalization;

  const AppCombobox.single({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    this.onChanged,
    this.icon,
    this.validator,
    this.emptyLabel = 'Tất cả',
    this.hintText,
    this.helperText,
    this.enabled = true,
    this.dense = false,
    this.allowClear = true,
    this.menuWidth,
    this.maxMenuHeight,
    this.textCapitalization = TextCapitalization.none,
  }) : values = const {},
       onMultiChanged = null,
       multiSelect = false;

  const AppCombobox.multi({
    super.key,
    required this.label,
    required this.options,
    required this.values,
    required ValueChanged<Set<T>> this.onMultiChanged,
    this.icon,
    this.emptyLabel = 'Tất cả',
    this.hintText,
    this.helperText,
    this.enabled = true,
    this.dense = false,
    this.allowClear = true,
    this.menuWidth,
    this.maxMenuHeight,
    this.textCapitalization = TextCapitalization.none,
  }) : value = null,
       onChanged = null,
       validator = null,
       multiSelect = true;

  @override
  State<AppCombobox<T>> createState() => _AppComboboxState<T>();
}

class _AppComboboxState<T> extends State<AppCombobox<T>> {
  final _layerLink = LayerLink();
  final _tapRegionGroup = Object();
  final _fieldKey = GlobalKey();
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;
  bool _showAbove = false;
  double _menuHeight = 320;
  int _highlightedIndex = 0;
  ValueChanged<T?>? _formDidChange;
  bool? _suffixWasOpenOnPointerDown;

  @override
  void initState() {
    super.initState();
    _controller.text = _displayText();
    _controller.addListener(_onSearchChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant AppCombobox<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isOpen) _syncDisplayText();
    _markOverlayNeedsBuild();
  }

  @override
  void dispose() {
    _closeOverlay(updateState: false);
    _controller.removeListener(_onSearchChanged);
    _focusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.validator == null || widget.multiSelect) {
      return _buildField(context, null, null);
    }
    return FormField<T>(
      initialValue: widget.value,
      validator: widget.validator,
      builder: (field) {
        return _buildField(
          context,
          field.errorText,
          (value) => field.didChange(value),
        );
      },
    );
  }

  Widget _buildField(
    BuildContext context,
    String? errorText,
    ValueChanged<T?>? didChange,
  ) {
    _formDidChange = didChange;
    return TapRegion(
      groupId: _tapRegionGroup,
      onTapOutside: _handleTapOutside,
      child: CompositedTransformTarget(
        link: _layerLink,
        child: Focus(
          onKeyEvent: _handleKeyEvent,
          child: TextField(
            key: _fieldKey,
            controller: _controller,
            focusNode: _focusNode,
            enabled: widget.enabled,
            readOnly: false,
            textCapitalization: widget.textCapitalization,
            textInputAction: TextInputAction.search,
            style: AppTextStyles.bodyM,
            onTap: _openOverlay,
            onSubmitted: (_) => _chooseHighlighted(didChange),
            decoration: appInputDecoration(
              label: widget.label,
              icon: widget.icon,
              hintText: _isOpen ? widget.hintText : widget.hintText,
              helperText: widget.helperText,
              errorText: errorText,
              dense: widget.dense,
              suffixIcon: _suffixIcon(didChange),
            ),
          ),
        ),
      ),
    );
  }

  Widget _suffixIcon(ValueChanged<T?>? didChange) {
    final hasSelection = widget.multiSelect
        ? widget.values.isNotEmpty
        : widget.value != null;
    if (widget.allowClear && widget.enabled && hasSelection && !_isOpen) {
      return IconButton(
        tooltip: 'Xóa lựa chọn',
        icon: const Icon(Icons.close_rounded, size: 18),
        onPressed: () {
          if (widget.multiSelect) {
            widget.onMultiChanged?.call(<T>{});
          } else {
            widget.onChanged?.call(null);
            _notifyFormValueChanged(null, didChange);
          }
          _logSelectionChanged(action: 'cleared_from_suffix');
          _closeOverlay();
          _focusNode.unfocus();
          _syncDisplayText();
        },
      );
    }
    return Listener(
      onPointerDown: (_) => _suffixWasOpenOnPointerDown = _isOpen,
      onPointerCancel: (_) => _suffixWasOpenOnPointerDown = null,
      child: IconButton(
        tooltip: _isOpen ? 'Đóng danh sách' : 'Mở danh sách',
        icon: Icon(
          _isOpen ? Icons.keyboard_arrow_up_rounded : Icons.search_rounded,
          size: 20,
        ),
        onPressed: widget.enabled ? _toggleOverlayFromSuffix : null,
      ),
    );
  }

  void _toggleOverlayFromSuffix() {
    // The TextField can gain focus and open the overlay before IconButton's
    // onPressed runs. Use the pointer-down state so that the same click does
    // not immediately close the menu it just opened.
    final wasOpen = _suffixWasOpenOnPointerDown ?? _isOpen;
    _suffixWasOpenOnPointerDown = null;
    if (wasOpen) {
      _closeOverlay();
      return;
    }
    _focusNode.requestFocus();
    _openOverlay(trigger: 'suffix_icon');
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!_isOpen &&
        (event.logicalKey == LogicalKeyboardKey.arrowDown ||
            event.logicalKey == LogicalKeyboardKey.enter)) {
      _openOverlay();
      return KeyEventResult.handled;
    }
    if (!_isOpen) return KeyEventResult.ignored;
    final options = _filteredOptions().toList(growable: false);
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _closeOverlay();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      _closeOverlay();
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
        options.isNotEmpty) {
      setState(() {
        _highlightedIndex = math.min(_highlightedIndex + 1, options.length - 1);
      });
      _markOverlayNeedsBuild();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp && options.isNotEmpty) {
      setState(() => _highlightedIndex = math.max(_highlightedIndex - 1, 0));
      _markOverlayNeedsBuild();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _chooseHighlighted(null);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _chooseHighlighted(ValueChanged<T?>? didChange) {
    final options = _filteredOptions().toList(growable: false);
    if (options.isEmpty) return;
    _selectOption(options[_highlightedIndex], didChange);
  }

  void _openOverlay({String trigger = 'field_or_focus'}) {
    if (!widget.enabled || _isOpen) return;
    unawaited(
      AppLogger.instance.info(
        'AppCombobox',
        'Filter dropdown open started',
        context: _logContext(trigger: trigger),
      ),
    );
    try {
      _calculateMenuGeometry();
      _controller
        ..text = ''
        ..selection = const TextSelection.collapsed(offset: 0);
      setState(() {
        _isOpen = true;
        _highlightedIndex = 0;
      });
      _overlayEntry = OverlayEntry(builder: _buildOverlay);
      Overlay.of(context).insert(_overlayEntry!);
      unawaited(
        AppLogger.instance.info(
          'AppCombobox',
          'Filter dropdown open succeeded',
          context: _logContext(trigger: trigger),
        ),
      );
    } catch (error, stackTrace) {
      _overlayEntry?.remove();
      _overlayEntry = null;
      if (mounted) setState(() => _isOpen = false);
      unawaited(
        AppLogger.instance.error(
          'AppCombobox',
          'Filter dropdown open failed',
          error: error,
          stackTrace: stackTrace,
          context: _logContext(trigger: trigger),
        ),
      );
      rethrow;
    }
  }

  void _closeOverlay({bool updateState = true}) {
    if (!_isOpen && _overlayEntry == null) return;
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted && updateState) {
      setState(() => _isOpen = false);
      _syncDisplayText();
    } else {
      _isOpen = false;
    }
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) _openOverlay();
  }

  void _handleTapOutside(PointerDownEvent event) {
    if (!_isOpen) return;
    unawaited(
      AppLogger.instance.info(
        'AppCombobox',
        'Filter dropdown dismissed outside',
        context: _logContext(action: 'outside_tap'),
      ),
    );
    _closeOverlay();
  }

  void _onSearchChanged() {
    if (!_isOpen) return;
    _highlightedIndex = 0;
    _markOverlayNeedsBuild();
  }

  Widget _buildOverlay(BuildContext overlayContext) {
    final filtered = _filteredOptions().toList(growable: false);
    final fieldSize = _fieldSize();
    final width = widget.menuWidth ?? fieldSize.width;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Stack(
          children: [
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: Offset(
                0,
                _showAbove
                    ? -_menuHeight - AppLayoutTokens.formInlineGap / 2
                    : fieldSize.height + AppLayoutTokens.formInlineGap / 2,
              ),
              child: TapRegion(
                groupId: _tapRegionGroup,
                child: Material(
                  color: AppColors.overlayOf(context),
                  elevation: 12,
                  shadowColor: AppColors.shadow.withValues(alpha: 0.22),
                  surfaceTintColor: AppColors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.allLg,
                    side: BorderSide(color: AppColors.borderOf(context)),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: fieldSize.width,
                      maxWidth: width,
                      maxHeight: _menuHeight,
                    ),
                    child: _buildMenuContent(filtered),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuContent(List<AppComboboxOption<T>> filtered) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.allowClear)
          _ClearSelectionTile(
            label: widget.emptyLabel,
            selected: widget.multiSelect
                ? widget.values.isEmpty
                : widget.value == null,
            onTap: () {
              if (widget.multiSelect) {
                widget.onMultiChanged?.call(<T>{});
                _logSelectionChanged(action: 'cleared_from_menu');
                _markOverlayNeedsBuild();
              } else {
                widget.onChanged?.call(null);
                _notifyFormValueChanged(null);
                _logSelectionChanged(action: 'cleared_from_menu');
                _closeOverlay();
              }
            },
          ),
        Flexible(
          child: filtered.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Không có lựa chọn phù hợp'),
                )
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final option = filtered[index];
                    final selected = widget.multiSelect
                        ? widget.values.contains(option.value)
                        : widget.value == option.value;
                    final highlighted = index == _highlightedIndex;
                    if (widget.multiSelect) {
                      return CheckboxListTile(
                        dense: true,
                        value: selected,
                        title: Text(
                          option.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: option.subtitle == null
                            ? null
                            : Text(
                                option.subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                        controlAffinity: ListTileControlAffinity.leading,
                        tileColor: highlighted
                            ? AppColors.primarySurfaceOf(context)
                            : null,
                        onChanged: (_) => _toggleOption(option),
                      );
                    }
                    return ListTile(
                      dense: true,
                      leading: selected
                          ? const Icon(Icons.check_rounded, size: 18)
                          : const SizedBox(width: 18),
                      title: Text(
                        option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: option.subtitle == null
                          ? null
                          : Text(
                              option.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      tileColor: highlighted
                          ? AppColors.primarySurfaceOf(context)
                          : null,
                      onTap: () => _selectOption(option, null),
                    );
                  },
                ),
        ),
        if (widget.multiSelect) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: OverflowBar(
              alignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  style: TextButton.styleFrom(textStyle: AppTextStyles.labelM),
                  onPressed: widget.values.isEmpty
                      ? null
                      : () {
                          widget.onMultiChanged?.call(<T>{});
                          _markOverlayNeedsBuild();
                        },
                  child: const Text('Xóa lọc'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    textStyle: AppTextStyles.labelM,
                  ),
                  onPressed: _closeOverlay,
                  child: const Text('Áp dụng'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _selectOption(AppComboboxOption<T> option, ValueChanged<T?>? didChange) {
    if (widget.multiSelect) {
      _toggleOption(option);
      return;
    }
    widget.onChanged?.call(option.value);
    _notifyFormValueChanged(option.value, didChange);
    _logSelectionChanged(action: 'single_selected', selectedCount: 1);
    _closeOverlay();
  }

  void _notifyFormValueChanged(T? value, [ValueChanged<T?>? didChange]) {
    notifyAppFormChanged(context);
    (didChange ?? _formDidChange)?.call(value);
  }

  void _toggleOption(AppComboboxOption<T> option) {
    final next = Set<T>.from(widget.values);
    if (next.contains(option.value)) {
      next.remove(option.value);
    } else {
      next.add(option.value);
    }
    widget.onMultiChanged?.call(next);
    _logSelectionChanged(
      action: next.contains(option.value)
          ? 'multi_option_selected'
          : 'multi_option_removed',
      selectedCount: next.length,
    );
    _markOverlayNeedsBuild();
  }

  void _logSelectionChanged({required String action, int? selectedCount}) {
    unawaited(
      AppLogger.instance.info(
        'AppCombobox',
        'Filter dropdown selection changed',
        context: _logContext(action: action, selectedCount: selectedCount ?? 0),
      ),
    );
  }

  Map<String, Object?> _logContext({
    String? trigger,
    String? action,
    int? selectedCount,
  }) {
    return {
      'label': widget.label,
      'multiSelect': widget.multiSelect,
      'optionCount': widget.options.length,
      if (trigger != null) 'trigger': trigger,
      if (action != null) 'action': action,
      if (selectedCount != null) 'selectedCount': selectedCount,
    };
  }

  void _markOverlayNeedsBuild() {
    final entry = _overlayEntry;
    if (entry == null) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _overlayEntry != entry) return;
        entry.markNeedsBuild();
      });
      return;
    }
    entry.markNeedsBuild();
  }

  Iterable<AppComboboxOption<T>> _filteredOptions() {
    return widget.options.where((option) => option.matches(_controller.text));
  }

  void _syncDisplayText() {
    final next = _displayText();
    if (_controller.text == next) return;
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  String _displayText() {
    if (widget.multiSelect) {
      if (widget.values.isEmpty) return widget.emptyLabel;
      if (widget.values.length == 1) {
        final value = widget.values.first;
        for (final option in widget.options) {
          if (option.value == value) return option.label;
        }
      }
      return '${widget.values.length} đã chọn';
    }
    final value = widget.value;
    if (value == null) return widget.emptyLabel;
    for (final option in widget.options) {
      if (option.value == value) return option.label;
    }
    return widget.emptyLabel;
  }

  void _calculateMenuGeometry() {
    final mediaQuery = MediaQuery.of(context);
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      _showAbove = false;
      _menuHeight = widget.maxMenuHeight ?? 320;
      return;
    }
    final topLeft = box.localToGlobal(Offset.zero);
    final below =
        mediaQuery.size.height -
        topLeft.dy -
        box.size.height -
        AppLayoutTokens.formInlineGap;
    final above =
        topLeft.dy - mediaQuery.padding.top - AppLayoutTokens.formInlineGap;
    _showAbove = below < 180 && above > below;
    final available = math.max(140.0, _showAbove ? above : below);
    final platformMax =
        mediaQuery.size.width < AppLayoutTokens.compactBreakpoint
        ? math.min(available, mediaQuery.size.height * 0.46)
        : math.min(available, 360.0);
    _menuHeight = widget.maxMenuHeight == null
        ? platformMax
        : math.min(widget.maxMenuHeight!, platformMax);
  }

  Size _fieldSize() {
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return const Size(280, AppInputMetrics.height);
    }
    return box.size;
  }
}

class _ClearSelectionTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ClearSelectionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: selected
          ? const Icon(Icons.check_rounded, size: 18)
          : const SizedBox(width: 18),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}

String _normalizeSearchText(String value) {
  var result = value.trim().toLowerCase();
  const replacements = <String, String>{
    'à': 'a',
    'á': 'a',
    'ạ': 'a',
    'ả': 'a',
    'ã': 'a',
    'â': 'a',
    'ầ': 'a',
    'ấ': 'a',
    'ậ': 'a',
    'ẩ': 'a',
    'ẫ': 'a',
    'ă': 'a',
    'ằ': 'a',
    'ắ': 'a',
    'ặ': 'a',
    'ẳ': 'a',
    'ẵ': 'a',
    'è': 'e',
    'é': 'e',
    'ẹ': 'e',
    'ẻ': 'e',
    'ẽ': 'e',
    'ê': 'e',
    'ề': 'e',
    'ế': 'e',
    'ệ': 'e',
    'ể': 'e',
    'ễ': 'e',
    'ì': 'i',
    'í': 'i',
    'ị': 'i',
    'ỉ': 'i',
    'ĩ': 'i',
    'ò': 'o',
    'ó': 'o',
    'ọ': 'o',
    'ỏ': 'o',
    'õ': 'o',
    'ô': 'o',
    'ồ': 'o',
    'ố': 'o',
    'ộ': 'o',
    'ổ': 'o',
    'ỗ': 'o',
    'ơ': 'o',
    'ờ': 'o',
    'ớ': 'o',
    'ợ': 'o',
    'ở': 'o',
    'ỡ': 'o',
    'ù': 'u',
    'ú': 'u',
    'ụ': 'u',
    'ủ': 'u',
    'ũ': 'u',
    'ư': 'u',
    'ừ': 'u',
    'ứ': 'u',
    'ự': 'u',
    'ử': 'u',
    'ữ': 'u',
    'ỳ': 'y',
    'ý': 'y',
    'ỵ': 'y',
    'ỷ': 'y',
    'ỹ': 'y',
    'đ': 'd',
  };
  replacements.forEach((from, to) {
    result = result.replaceAll(from, to);
  });
  return result;
}
