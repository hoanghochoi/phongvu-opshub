import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../app/navigation/app_nav_model.dart';
import '../../../../app/widgets/app_feature_grid.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class OperationsScreen extends StatefulWidget {
  const OperationsScreen({super.key});

  @override
  State<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends State<OperationsScreen> {
  String _lastLogKey = '';

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final actions = _buildActions(context, user);

    _logOperationsResolved(actions.length, user);

    return AppResponsiveScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (actions.isEmpty)
            const AppStatePanel.empty(
              key: Key('operations-empty-state'),
              icon: Icons.apps_outlined,
              title: 'Chưa có công cụ khả dụng',
              message:
                  'Vui lòng liên hệ quản lý để kiểm tra phân quyền truy cập.',
            )
          else
            AppFeatureSection(
              key: const Key('operations-feature-section'),
              title: 'Công cụ theo quyền',
              actions: actions,
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  List<AppFeatureAction> _buildActions(BuildContext context, User? user) {
    final destinations = AppNavModel.visibleWorkspaceDestinations(user);
    return [
      for (final destination in destinations)
        AppFeatureAction(
          icon: destination.icon,
          title: destination.label,
          description: destination.description,
          color: destination.color,
          onTap: () {
            if (destination.id == 'feedback') {
              unawaited(
                AppLogger.instance.info(
                  'Feedback',
                  'Suggestion opened from operations',
                ),
              );
            }
            context.go(destination.route);
          },
        ),
    ];
  }

  void _logOperationsResolved(int visibleCount, User? user) {
    final hiddenCount = AppNavModel.hiddenWorkspaceCount(user);
    final key = '$visibleCount|$hiddenCount';
    if (_lastLogKey == key) return;
    _lastLogKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        AppLogger.instance.info(
          'Operations',
          'Operations workspace resolved',
          context: {
            'visibleActions': visibleCount,
            'hiddenActions': hiddenCount,
          },
        ),
      );
    });
  }
}
