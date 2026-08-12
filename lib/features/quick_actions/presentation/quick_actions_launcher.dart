import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
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
  final double buttonSize;
  final double elevation;
  final bool visibleWhenUnavailable;

  const QuickActionsLauncher({
    super.key,
    required this.menuAxis,
    required this.location,
    this.buttonSize = 64,
    this.elevation = 8,
    this.visibleWhenUnavailable = false,
  });

  static bool isAvailable(BuildContext context) {
    return _actionsForContext(context).isNotEmpty;
  }

  static List<_QuickAction> _actionsForContext(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    QuickActionsPayload? payload;
    try {
      payload = context.watch<QuickActionsProvider>().payload;
    } on ProviderNotFoundException {
      return const [];
    }
    if (user?.canUseFeature('QUICK_ACTIONS') != true) return const [];
    return _availableActions(user, payload);
  }

  static List<_QuickAction> _availableActions(
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
          PhosphorIconsRegular.package,
          route: '/fifo-check',
        ),
      if (can('QUICK_ACTION_VIETQR', 'VIETQR'))
        const _QuickAction(
          'VIETQR',
          'VietQR',
          PhosphorIconsRegular.qrCode,
          route: '/vietqr',
        ),
      if (user?.canUseFeature('QUICK_ACTION_FOLLOW_UP') == true &&
          (user?.canUseFeature('SALES_REPORT') == true ||
              user?.canUseFeature('ADMIN_SALES_REPORTS') == true))
        const _QuickAction(
          'FOLLOW_UP',
          'Chăm sóc lại',
          PhosphorIconsRegular.headset,
          route: '/sales-reports/follow-up-cases',
        ),
      if (can('QUICK_ACTION_SALES_REPORT', 'SALES_REPORT'))
        const _QuickAction(
          'SALES_REPORT',
          'Báo cáo bán hàng',
          PhosphorIconsRegular.chartBar,
          route: '/sales-reports',
        ),
      if (user?.canUseFeature('QUICK_ACTION_APP_DOWNLOAD') == true &&
          qr.contains('APP_DOWNLOAD'))
        const _QuickAction(
          'APP_DOWNLOAD',
          'Tải app',
          PhosphorIconsRegular.downloadSimple,
        ),
      if (user?.canUseFeature('QUICK_ACTION_CHECK_IN') == true &&
          qr.contains('CHECK_IN'))
        const _QuickAction(
          'CHECK_IN',
          'Check-in',
          PhosphorIconsRegular.userCheck,
        ),
      if (user?.canUseFeature('QUICK_ACTION_ZALO_OA') == true &&
          qr.contains('ZALO_OA'))
        const _QuickAction(
          'ZALO_OA',
          'Zalo OA',
          PhosphorIconsRegular.chatCircle,
        ),
      if (user?.canUseFeature('QUICK_ACTION_GOOGLE_MAP') == true &&
          qr.contains('GOOGLE_MAP'))
        const _QuickAction('GOOGLE_MAP', 'GG Map', PhosphorIconsRegular.mapPin),
    ];
  }

  @override
  State<QuickActionsLauncher> createState() => _QuickActionsLauncherState();
}

class _QuickActionsLauncherState extends State<QuickActionsLauncher>
    with WidgetsBindingObserver {
  final LayerLink _link = LayerLink();
  final FocusNode _buttonFocus = FocusNode(debugLabel: 'quick-actions-button');
  OverlayEntry? _overlay;
  bool _isPressed = false;
  bool _hasFocus = false;

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
    final actions = QuickActionsLauncher._actionsForContext(context);
    final compact = widget.buttonSize < 64;
    final launcherShape = !compact
        ? const CircleBorder()
        : RoundedRectangleBorder(borderRadius: AppRadius.allXl);
    if (actions.isEmpty) {
      if (!widget.visibleWhenUnavailable) return const SizedBox.shrink();
      return Semantics(
        button: true,
        enabled: false,
        label: 'Thao tác nhanh chưa khả dụng',
        child: Tooltip(
          message: 'Chưa có thao tác nhanh khả dụng',
          child: Material(
            key: const Key('quick-actions-launcher-surface'),
            color: AppColors.primaryOf(context),
            elevation: widget.elevation,
            shape: launcherShape,
            clipBehavior: Clip.antiAlias,
            child: SizedBox.square(
              key: const Key('quick-actions-launcher-unavailable'),
              dimension: widget.buttonSize,
              child: Icon(
                PhosphorIconsRegular.lightning,
                color: AppColors.primaryForegroundOf(context),
                size: widget.buttonSize >= 64 ? 24 : 20,
              ),
            ),
          ),
        ),
      );
    }
    return CompositedTransformTarget(
      link: _link,
      child: Semantics(
        button: true,
        label: 'Mở Thao tác nhanh',
        child: Tooltip(
          message: 'Thao tác nhanh',
          child: Focus(
            key: const Key('quick-actions-launcher-focus'),
            focusNode: _buttonFocus,
            onFocusChange: compact ? _handleFocusChange : null,
            child: compact
                ? _buildCompactLauncher(context, launcherShape)
                : _buildLegacyLauncher(context, launcherShape),
          ),
        ),
      ),
    );
  }

  Widget _buildLegacyLauncher(BuildContext context, ShapeBorder shape) {
    return Material(
      key: const Key('quick-actions-launcher-surface'),
      color: AppColors.primaryOf(context),
      elevation: widget.elevation,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('quick-actions-launcher'),
        customBorder: shape,
        onTap: _toggleMenu,
        child: SizedBox.square(
          dimension: widget.buttonSize,
          child: Icon(
            PhosphorIconsRegular.lightning,
            color: AppColors.primaryForegroundOf(context),
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildCompactLauncher(BuildContext context, ShapeBorder shape) {
    final active = _isPressed || _overlay != null;
    final background = active
        ? AppColors.navigationPressedOf(context)
        : AppColors.selectedNavigationOf(context);
    return DecoratedBox(
      key: const Key('quick-actions-launcher-decoration'),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.allXl,
        border: _hasFocus
            ? Border.all(
                color: AppColors.focusRingOf(context),
                width: 2,
                strokeAlign: BorderSide.strokeAlignOutside,
              )
            : null,
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(8, 18, 56, 0.2),
            offset: Offset(0, 8),
            blurRadius: 18,
            spreadRadius: -4,
          ),
        ],
      ),
      child: Material(
        key: const Key('quick-actions-launcher-surface'),
        color: AppColors.transparent,
        elevation: 0,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const Key('quick-actions-launcher'),
          customBorder: shape,
          overlayColor: const WidgetStatePropertyAll(AppColors.transparent),
          onHighlightChanged: _handleHighlightChanged,
          onTap: _toggleMenu,
          child: SizedBox.square(
            dimension: widget.buttonSize,
            child: Icon(
              PhosphorIconsRegular.lightning,
              color: AppColors.quickActionForegroundOf(context),
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  void _handleHighlightChanged(bool pressed) {
    if (_isPressed == pressed || !mounted) return;
    setState(() => _isPressed = pressed);
  }

  void _handleFocusChange(bool focused) {
    if (_hasFocus == focused || !mounted) return;
    setState(() => _hasFocus = focused);
  }

  Future<void> _toggleMenu() async {
    if (_overlay != null) {
      _closeMenu();
      return;
    }
    final provider = context.read<QuickActionsProvider>();
    final authProvider = context.read<AuthProvider>();
    provider.revalidateScopeIfStale();
    final user = authProvider.user;
    final actions = QuickActionsLauncher._availableActions(
      user,
      provider.payload,
    );
    if (actions.isEmpty) {
      setState(() {});
      AppToast.show(
        context,
        const SnackBar(
          content: Text(
            'Chưa có Thao tác nhanh khả dụng. Vui lòng kiểm tra lại quyền hoặc cấu hình showroom.',
          ),
        ),
      );
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
                child: SizedBox.square(
                  dimension: 260,
                  child: QrImageView(
                    key: const Key('quick-action-qr-code'),
                    data: url,
                    size: 260,
                    backgroundColor: AppColors.customerQrBackground,
                    eyeStyle: const QrEyeStyle(
                      color: AppColors.customerQrForeground,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      color: AppColors.customerQrForeground,
                    ),
                  ),
                ),
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
    final mediaSize = MediaQuery.sizeOf(context);
    final horizontalMenuWidth = math.max(
      0.0,
      math.min(mediaSize.width - 24, 420.0),
    );
    final maxMenuHeight = math.max(0.0, mediaSize.height - 120);
    return Material(
      key: const Key('quick-actions-menu'),
      color: AppColors.cardOf(context),
      elevation: 12,
      borderRadius: AppRadius.allLg,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: axis == Axis.horizontal
            ? BoxConstraints(
                minWidth: horizontalMenuWidth,
                maxWidth: horizontalMenuWidth,
                maxHeight: maxMenuHeight,
              )
            : BoxConstraints(maxWidth: 280, maxHeight: maxMenuHeight),
        child: axis == Axis.horizontal
            ? _QuickActionsGrid(actions: actions, onSelected: onSelected)
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final action in actions)
                      _QuickActionTile(
                        action: action,
                        horizontal: false,
                        onTap: () => onSelected(action),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _QuickActionsGrid extends StatelessWidget {
  final List<_QuickAction> actions;
  final ValueChanged<_QuickAction> onSelected;

  const _QuickActionsGrid({required this.actions, required this.onSelected});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columnCount = constraints.maxWidth >= 344
          ? 4
          : constraints.maxWidth >= 252
          ? 3
          : 2;
      final tileWidth = (constraints.maxWidth - 16) / columnCount;
      return SingleChildScrollView(
        key: const Key('quick-actions-grid'),
        padding: const EdgeInsets.all(8),
        child: Wrap(
          children: [
            for (final action in actions)
              SizedBox(
                key: Key('quick-action-grid-item-${action.code}'),
                width: tileWidth,
                child: _QuickActionTile(
                  action: action,
                  horizontal: true,
                  onTap: () => onSelected(action),
                ),
              ),
          ],
        ),
      );
    },
  );
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
      width: horizontal ? null : 264,
      height: horizontal ? 84 : 52,
      child: horizontal
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(action.icon, color: AppColors.primaryOf(context)),
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
                  Icon(action.icon, color: AppColors.primaryOf(context)),
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
