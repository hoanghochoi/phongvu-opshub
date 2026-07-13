import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/widgets/app_buttons.dart';
import '../../../app/widgets/app_toast.dart';
import '../../../core/logging/app_logger.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import '../data/quick_actions_repository.dart';
import 'quick_actions_provider.dart';

class QuickActionsLauncher extends StatefulWidget {
  final Axis menuAxis;
  final String location;

  const QuickActionsLauncher({
    super.key,
    required this.menuAxis,
    required this.location,
  });

  @override
  State<QuickActionsLauncher> createState() => _QuickActionsLauncherState();
}

class _QuickActionsLauncherState extends State<QuickActionsLauncher>
    with WidgetsBindingObserver {
  final LayerLink _link = LayerLink();
  final FocusNode _buttonFocus = FocusNode(debugLabel: 'quick-actions-button');
  OverlayEntry? _overlay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant QuickActionsLauncher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) _closeMenu(returnFocus: false);
  }

  @override
  void didChangeMetrics() => _closeMenu(returnFocus: false);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _overlay?.remove();
    _overlay = null;
    _buttonFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    QuickActionsPayload? payload;
    try {
      payload = context.watch<QuickActionsProvider>().payload;
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    final actions = _availableActions(user, payload);
    if (user?.canUseFeature('QUICK_ACTIONS') != true || actions.isEmpty) {
      return const SizedBox.shrink();
    }
    return CompositedTransformTarget(
      link: _link,
      child: Semantics(
        button: true,
        label: 'Mở Thao tác nhanh',
        child: Focus(
          focusNode: _buttonFocus,
          child: Material(
            color: AppColors.primary,
            elevation: 8,
            borderRadius: AppRadius.allLg,
            child: InkWell(
              key: const Key('quick-actions-launcher'),
              borderRadius: AppRadius.allLg,
              onTap: () => _toggleMenu(actions),
              child: const SizedBox.square(
                dimension: 64,
                child: Icon(
                  Icons.bolt_rounded,
                  color: AppColors.surface,
                  size: 34,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<_QuickAction> _availableActions(
    dynamic user,
    QuickActionsPayload? data,
  ) {
    bool can(String child, String root) =>
        user?.canUseFeature(child) == true && user?.canUseFeature(root) == true;
    final qr = data?.availableActionCodes ?? const <String>{};
    return [
      if (can('QUICK_ACTION_FIFO', 'FIFO'))
        const _QuickAction(
          'FIFO',
          'Kiểm tra FIFO',
          Icons.inventory_2_outlined,
          route: '/fifo-check',
        ),
      if (can('QUICK_ACTION_VIETQR', 'VIETQR'))
        const _QuickAction(
          'VIETQR',
          'VietQR',
          Icons.qr_code_2_rounded,
          route: '/vietqr',
        ),
      if (can('QUICK_ACTION_SALES_REPORT', 'SALES_REPORT'))
        const _QuickAction(
          'SALES_REPORT',
          'Báo cáo bán hàng',
          Icons.assessment_outlined,
          route: '/sales-reports',
        ),
      if (user?.canUseFeature('QUICK_ACTION_APP_DOWNLOAD') == true &&
          qr.contains('APP_DOWNLOAD'))
        const _QuickAction('APP_DOWNLOAD', 'Tải app', Icons.download_rounded),
      if (user?.canUseFeature('QUICK_ACTION_CHECK_IN') == true &&
          qr.contains('CHECK_IN'))
        const _QuickAction('CHECK_IN', 'Check-in', Icons.how_to_reg_outlined),
      if (user?.canUseFeature('QUICK_ACTION_ZALO_OA') == true &&
          qr.contains('ZALO_OA'))
        const _QuickAction(
          'ZALO_OA',
          'Zalo OA',
          Icons.chat_bubble_outline_rounded,
        ),
      if (user?.canUseFeature('QUICK_ACTION_GOOGLE_MAP') == true &&
          qr.contains('GOOGLE_MAP'))
        const _QuickAction('GOOGLE_MAP', 'GG Map', Icons.location_on_outlined),
    ];
  }

  void _toggleMenu(List<_QuickAction> actions) {
    if (_overlay != null) {
      _closeMenu();
      return;
    }
    unawaited(
      AppLogger.instance.info(
        'QuickActions',
        'Quick actions menu opened',
        context: {'actionCount': actions.length, 'axis': widget.menuAxis.name},
      ),
    );
    final overlay = Overlay.of(context);
    _overlay = OverlayEntry(
      builder: (overlayContext) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _closeMenu();
        },
        child: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
          },
          child: Actions(
            actions: {
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (_) {
                  _closeMenu();
                  return null;
                },
              ),
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _closeMenu,
                  ),
                ),
                CompositedTransformFollower(
                  link: _link,
                  showWhenUnlinked: false,
                  targetAnchor: widget.menuAxis == Axis.horizontal
                      ? Alignment.topCenter
                      : Alignment.topRight,
                  followerAnchor: widget.menuAxis == Axis.horizontal
                      ? Alignment.bottomCenter
                      : Alignment.bottomRight,
                  offset: const Offset(0, -12),
                  child: _QuickActionsMenu(
                    axis: widget.menuAxis,
                    actions: actions,
                    onSelected: _selectAction,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    overlay.insert(_overlay!);
    setState(() {});
  }

  void _closeMenu({bool returnFocus = true}) {
    final entry = _overlay;
    if (entry == null) return;
    entry.remove();
    _overlay = null;
    unawaited(
      AppLogger.instance.info('QuickActions', 'Quick actions menu closed'),
    );
    if (returnFocus && mounted) _buttonFocus.requestFocus();
    if (mounted) setState(() {});
  }

  Future<void> _selectAction(_QuickAction action) async {
    _closeMenu(returnFocus: false);
    await AppLogger.instance.info(
      'QuickActions',
      'Quick action selected',
      context: {'actionCode': action.code},
    );
    if (!mounted) return;
    if (action.route != null) {
      await AppLogger.instance.info(
        'QuickActions',
        'Quick action navigation started',
        context: {'actionCode': action.code, 'route': action.route},
      );
      if (mounted) context.go(action.route!);
      return;
    }
    await _showQrAction(action);
  }

  Future<void> _showQrAction(_QuickAction action) async {
    final provider = context.read<QuickActionsProvider>();
    final stores = provider.payload?.stores ?? const <QuickActionStore>[];
    QuickActionStore? store;
    if (stores.length == 1) {
      store = stores.first;
    } else if (stores.isNotEmpty) {
      store = await showDialog<QuickActionStore>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: Text('Chọn showroom cho ${action.label}'),
          children: [
            for (final item in stores)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, item),
                child: Text('${item.storeCode} · ${item.storeName}'),
              ),
          ],
        ),
      );
      if (store != null) {
        await AppLogger.instance.info(
          'QuickActions',
          'Quick action showroom selected',
          context: {
            'actionCode': action.code,
            'storeCode': store.storeCode,
            'storeCount': stores.length,
          },
        );
      }
    }
    if (store == null || !mounted) return;
    final loaded = await provider.refresh(storeCode: store.storeCode);
    final url = loaded?.links[action.code];
    if (!mounted) return;
    if (url == null || url.isEmpty) {
      AppToast.show(
        context,
        const SnackBar(
          content: Text(
            'Showroom này chưa được cấu hình liên kết. Vui lòng chọn showroom khác hoặc liên hệ quản lý.',
          ),
        ),
      );
      return;
    }
    await AppLogger.instance.info(
      'QuickActions',
      'Quick action QR displayed',
      context: {
        'actionCode': action.code,
        'storeCode': store.storeCode,
        'urlLength': url.length,
      },
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(action.label),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${store!.storeCode} · ${store.storeName}',
                style: AppTextStyles.labelM,
              ),
              const SizedBox(height: 16),
              Semantics(
                label: 'Mã QR ${action.label} của ${store.storeName}',
                image: true,
                child: QrImageView(data: url, size: 260),
              ),
              const SizedBox(height: 12),
              Text(
                'Mời khách hàng quét mã QR bằng điện thoại.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyM.copyWith(
                  color: AppColors.textSecondaryOf(dialogContext),
                ),
              ),
            ],
          ),
        ),
        actions: [
          AppDialogCancelButton(
            onPressed: () => Navigator.pop(dialogContext),
            label: 'Đóng',
          ),
        ],
      ),
    );
  }
}

class _QuickActionsMenu extends StatelessWidget {
  final Axis axis;
  final List<_QuickAction> actions;
  final ValueChanged<_QuickAction> onSelected;

  const _QuickActionsMenu({
    required this.axis,
    required this.actions,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final children = [
      for (final action in actions)
        _QuickActionTile(
          action: action,
          horizontal: axis == Axis.horizontal,
          onTap: () => onSelected(action),
        ),
    ];
    return Material(
      key: const Key('quick-actions-menu'),
      color: AppColors.cardOf(context),
      elevation: 12,
      borderRadius: AppRadius.allLg,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: axis == Axis.horizontal
            ? BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width - 24,
                maxHeight: 92,
              )
            : BoxConstraints(
                maxWidth: 280,
                maxHeight: MediaQuery.sizeOf(context).height - 120,
              ),
        child: axis == Axis.horizontal
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: children),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
              ),
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final _QuickAction action;
  final bool horizontal;
  final VoidCallback onTap;
  const _QuickActionTile({
    required this.action,
    required this.horizontal,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: SizedBox(
      width: horizontal ? 96 : 264,
      height: horizontal ? 84 : 52,
      child: horizontal
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(action.icon, color: AppColors.primary),
                const SizedBox(height: 6),
                Text(
                  action.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.labelS,
                ),
              ],
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(action.icon, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(action.label, style: AppTextStyles.labelM),
                  ),
                ],
              ),
            ),
    ),
  );
}

class _QuickAction {
  final String code;
  final String label;
  final IconData icon;
  final String? route;
  const _QuickAction(this.code, this.label, this.icon, {this.route});
}
