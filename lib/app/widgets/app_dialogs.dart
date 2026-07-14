import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/logging/app_logger.dart';
import '../theme/app_colors.dart';
import 'app_buttons.dart';

class AppFormChangedNotification extends Notification {
  const AppFormChangedNotification();
}

void notifyAppFormChanged(BuildContext context) {
  const AppFormChangedNotification().dispatch(context);
}

class AppDirtyFormGuard extends StatefulWidget {
  final Widget child;
  final String source;

  const AppDirtyFormGuard({
    super.key,
    required this.child,
    required this.source,
  });

  @override
  State<AppDirtyFormGuard> createState() => _AppDirtyFormGuardState();
}

class _AppDirtyFormGuardState extends State<AppDirtyFormGuard> {
  bool _dirty = false;
  bool _allowPop = false;
  bool _confirming = false;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<AppFormChangedNotification>(
      onNotification: (_) {
        if (!_dirty) {
          setState(() => _dirty = true);
          unawaited(
            AppLogger.instance.info(widget.source, 'Dialog form marked dirty'),
          );
        }
        return false;
      },
      child: PopScope(
        canPop: !_dirty || _allowPop,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          // Editors may return `true`, an id, or a selected value on commit.
          // `null` and `false` remain cancel/close results and must be guarded.
          if (result != null && result != false) {
            _completePop(result, committed: true);
            return;
          }
          unawaited(_confirmDiscard());
        },
        child: widget.child,
      ),
    );
  }

  Future<void> _confirmDiscard() async {
    if (_confirming || !mounted) return;
    _confirming = true;
    await AppLogger.instance.info(
      widget.source,
      'Unsaved dialog dismissal confirmation opened',
    );
    if (!mounted) return;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hủy các thay đổi?'),
        content: const Text(
          'Thông tin đang sửa chưa được lưu. Bạn có muốn thoát và hủy toàn bộ thay đổi không?',
        ),
        actions: [
          AppDialogCancelButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            label: 'Tiếp tục chỉnh sửa',
          ),
          AppDialogConfirmButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            label: 'Thoát và hủy',
            backgroundColor: AppColors.error,
            foregroundColor: AppColors.surface,
          ),
        ],
      ),
    );
    if (!mounted) return;
    _confirming = false;
    await AppLogger.instance.info(
      widget.source,
      'Unsaved dialog dismissal confirmation completed',
      context: {'discarded': discard == true},
    );
    if (discard != true || !mounted) return;
    _completePop(null, committed: false);
  }

  void _completePop(Object? result, {required bool committed}) {
    if (!mounted) return;
    setState(() {
      _dirty = false;
      _allowPop = true;
    });
    unawaited(
      AppLogger.instance.info(
        widget.source,
        committed
            ? 'Dirty dialog committed and closed'
            : 'Dirty dialog changes discarded',
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
  }
}
