import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../app/widgets/app_toast.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_exception.dart';
import '../../data/repositories/sales_target_repository.dart';

class SalesTargetAdminScreen extends StatefulWidget {
  const SalesTargetAdminScreen({super.key, required this.repository});

  final SalesTargetRepository repository;

  @override
  State<SalesTargetAdminScreen> createState() => _SalesTargetAdminScreenState();
}

class _SalesTargetAdminScreenState extends State<SalesTargetAdminScreen> {
  final _controllers = <String, TextEditingController>{};
  final _moneyFormat = NumberFormat.decimalPattern('vi_VN');
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<SalesTargetItem> _items = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String get _monthKey => DateFormat('yyyy-MM').format(_month);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await AppLogger.instance.info(
      'SalesTargetAdmin',
      'Sales targets load started',
      context: {'month': _monthKey},
    );
    try {
      final items = await widget.repository.fetchTargets(_monthKey);
      if (!mounted) return;
      _replaceItems(items);
      setState(() => _loading = false);
      await AppLogger.instance.info(
        'SalesTargetAdmin',
        'Sales targets load succeeded',
        context: {
          'month': _monthKey,
          'storeCount': items.length,
          'configuredCount': items
              .where((item) => item.targetBeforeTax != null)
              .length,
        },
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
      await AppLogger.instance.warn(
        'SalesTargetAdmin',
        'Sales targets load failed',
        context: {'month': _monthKey, 'message': error.message},
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Chưa tải được chỉ tiêu. Vui lòng thử lại.';
      });
      await AppLogger.instance.error(
        'SalesTargetAdmin',
        'Sales targets load failed unexpectedly',
        error: error,
        stackTrace: stackTrace,
        context: {'month': _monthKey},
        upload: true,
      );
    }
  }

  void _replaceItems(List<SalesTargetItem> items) {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    _items = items;
    for (final item in items) {
      _controllers[item.organizationNodeId] = TextEditingController(
        text: item.targetBeforeTax == null
            ? ''
            : _moneyFormat.format(item.targetBeforeTax),
      );
    }
  }

  Future<void> _save() async {
    final values = <String, int?>{};
    for (final item in _items) {
      final raw = _controllers[item.organizationNodeId]?.text ?? '';
      final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
      final value = digits.isEmpty ? null : int.tryParse(digits);
      if (digits.isNotEmpty && (value == null || value <= 0)) {
        AppToast.show(
          context,
          const SnackBar(content: Text('Chỉ tiêu phải là số tiền lớn hơn 0.')),
        );
        return;
      }
      values[item.organizationNodeId] = value;
    }
    setState(() => _saving = true);
    await AppLogger.instance.info(
      'SalesTargetAdmin',
      'Sales targets save started',
      context: {
        'month': _monthKey,
        'itemCount': values.length,
        'configuredCount': values.values.whereType<int>().length,
      },
    );
    try {
      final items = await widget.repository.saveTargets(_monthKey, values);
      if (!mounted) return;
      _replaceItems(items);
      setState(() => _saving = false);
      AppToast.show(
        context,
        const SnackBar(content: Text('Đã lưu chỉ tiêu doanh số.')),
      );
      await AppLogger.instance.info(
        'SalesTargetAdmin',
        'Sales targets save succeeded',
        context: {'month': _monthKey, 'itemCount': items.length},
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.show(context, SnackBar(content: Text(error.message)));
      await AppLogger.instance.warn(
        'SalesTargetAdmin',
        'Sales targets save failed',
        context: {'month': _monthKey, 'message': error.message},
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.show(
        context,
        const SnackBar(
          content: Text('Chưa lưu được chỉ tiêu. Vui lòng thử lại.'),
        ),
      );
      await AppLogger.instance.error(
        'SalesTargetAdmin',
        'Sales targets save failed unexpectedly',
        error: error,
        stackTrace: stackTrace,
        context: {'month': _monthKey},
        upload: true,
      );
    }
  }

  Future<void> _moveMonth(int delta) async {
    _month = DateTime(_month.year, _month.month + delta);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return AppResponsiveScrollView(
      onRefresh: _load,
      refreshLogSource: 'SalesTargetAdmin',
      refreshLogContext: () => {
        'month': _monthKey,
        'itemCount': _items.length,
        'isLoading': _loading,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSurfaceCard(
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Tháng trước',
                  onPressed: _loading ? null : () => _moveMonth(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text('Quản lý doanh số', style: AppTextStyles.headingS),
                      Text(
                        'Tháng ${DateFormat('MM/yyyy').format(_month)} • Chỉ tiêu trước VAT',
                        style: AppTextStyles.bodyS.copyWith(
                          color: AppColors.textMutedOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Tháng sau',
                  onPressed: _loading ? null : () => _moveMonth(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppLayoutTokens.cardGap),
          if (_loading)
            const AppStatePanel.loading(
              title: 'Đang tải chỉ tiêu',
              message:
                  'Hệ thống đang lấy danh sách showroom trong phạm vi của bạn.',
            )
          else if (_error != null)
            AppStatePanel.error(
              title: 'Chưa tải được chỉ tiêu',
              message: _error,
              actionLabel: 'Thử lại',
              actionIcon: Icons.refresh_rounded,
              onAction: _load,
            )
          else if (_items.isEmpty)
            const AppStatePanel.empty(
              title: 'Không có showroom để cập nhật',
              message: 'Kiểm tra lại phạm vi tổ chức được cấp quyền.',
            )
          else ...[
            AppSurfaceCard(
              child: Column(
                children: [
                  for (var index = 0; index < _items.length; index++) ...[
                    _SalesTargetRow(
                      item: _items[index],
                      controller:
                          _controllers[_items[index].organizationNodeId]!,
                    ),
                    if (index < _items.length - 1) const Divider(height: 24),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppLayoutTokens.cardGap),
            Align(
              alignment: Alignment.centerRight,
              child: AppPrimaryButton(
                label: _saving ? 'Đang lưu...' : 'Lưu chỉ tiêu',
                icon: Icons.save_outlined,
                onPressed: _saving ? null : _save,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SalesTargetRow extends StatelessWidget {
  const _SalesTargetRow({required this.item, required this.controller});

  final SalesTargetItem item;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final field = AppTextInput(
          controller: controller,
          label: 'Chỉ tiêu tháng',
          keyboardType: TextInputType.number,
          suffixText: 'VND',
          helperText: 'Để trống nếu chưa thiết lập',
        );
        if (constraints.maxWidth < 600) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${item.storeCode} • ${item.storeName}'),
              const SizedBox(height: 10),
              field,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: Text('${item.storeCode} • ${item.storeName}')),
            const SizedBox(width: 20),
            SizedBox(width: 320, child: field),
          ],
        );
      },
    );
  }
}
