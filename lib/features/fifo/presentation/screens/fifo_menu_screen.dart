import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_feature_grid.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class FifoMenuScreen extends StatefulWidget {
  const FifoMenuScreen({super.key});

  @override
  State<FifoMenuScreen> createState() => _FifoMenuScreenState();
}

class _FifoMenuScreenState extends State<FifoMenuScreen> {
  String _lastLogKey = '';

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.user;
    final role = user?.role ?? '';
    final canUseFifo = user?.canUseFeature('FIFO') == true;
    final canImportInventory = user?.canUseFeature('FIFO_IMPORT') == true;
    final canViewHistory = canUseFifo && User.isAdminRole(role);
    final hiddenCount = [
      canUseFifo,
      canUseFifo,
      canImportInventory,
      canViewHistory,
    ].where((enabled) => !enabled).length;
    final actions = [
      if (canUseFifo)
        AppFeatureAction(
          icon: Icons.qr_code_scanner_rounded,
          title: 'Kiểm tra FIFO',
          description: 'Tra cứu thứ tự FIFO',
          color: AppColors.info,
          onTap: () => _openWorkspace(
            context,
            destination: 'fifo-check',
            route: '/fifo-check',
          ),
        ),
      if (canUseFifo)
        AppFeatureAction(
          icon: Icons.swap_vert_rounded,
          title: 'Sắp xếp FIFO',
          description: 'Quét hoặc nhập SKU/BIN',
          color: AppColors.indigo600,
          onTap: () =>
              _openWorkspace(context, destination: 'fifo-sort', route: '/sort'),
        ),
      if (canImportInventory)
        AppFeatureAction(
          icon: Icons.upload_file_outlined,
          title: 'Cập nhật tồn kho',
          description: 'Import Excel cho FIFO',
          color: AppColors.amber500,
          onTap: () => _openWorkspace(
            context,
            destination: 'fifo-inventory-import',
            route: '/fifo/inventory-import',
          ),
        ),
      if (canViewHistory)
        AppFeatureAction(
          icon: Icons.history_rounded,
          title: 'Lịch sử FIFO',
          description: 'Kiểm tra & sắp xếp',
          color: AppColors.purple600,
          onTap: () => _openWorkspace(
            context,
            destination: 'fifo-history',
            route: '/fifo-history',
          ),
        ),
    ];

    _logResolved(
      visibleCount: actions.length,
      hiddenCount: hiddenCount,
      canUseFifo: canUseFifo,
      canImportInventory: canImportInventory,
      canViewHistory: canViewHistory,
    );

    return AppResponsiveScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (actions.isEmpty)
            const AppSurfaceCard(
              key: Key('fifo-menu-empty-state'),
              child: AppStatePanel.empty(
                icon: Icons.inventory_2_outlined,
                title: 'Chưa có tính năng FIFO',
                message:
                    'Liên hệ quản trị viên để được cấp quyền kiểm tra, sắp xếp hoặc import tồn kho FIFO.',
              ),
            )
          else
            AppFeatureSection(title: 'Chức năng FIFO', actions: actions),
        ],
      ),
    );
  }

  void _openWorkspace(
    BuildContext context, {
    required String destination,
    required String route,
  }) {
    unawaited(
      AppLogger.instance.info(
        'FIFO',
        'FIFO workspace opened from hub',
        context: {'destination': destination, 'route': route},
      ),
    );
    context.push(route);
  }

  void _logResolved({
    required int visibleCount,
    required int hiddenCount,
    required bool canUseFifo,
    required bool canImportInventory,
    required bool canViewHistory,
  }) {
    final key = [
      visibleCount,
      hiddenCount,
      canUseFifo,
      canImportInventory,
      canViewHistory,
    ].join('|');
    if (_lastLogKey == key) return;
    _lastLogKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        AppLogger.instance.info(
          'FIFO',
          'FIFO hub resolved',
          context: {
            'visibleActions': visibleCount,
            'hiddenActions': hiddenCount,
            'canUseFifo': canUseFifo,
            'canImportInventory': canImportInventory,
            'canViewHistory': canViewHistory,
          },
        ),
      );
    });
  }
}
